-- ============================================================================
-- PNITE — 0013: tabela "Dados SETE" e complementos municipais no banco
-- ----------------------------------------------------------------------------
-- Substitui as bases embutidas no PNITE.html (SETE_MUN, CENSO_MUNICIPIOS,
-- VEICULOS_MUNICIPIOS), reproduzindo exatamente as regras com que foram geradas
-- (validadas município a município contra os valores embutidos):
--   - rotas: só km <= 2.000 entram em km_total e rotas_com_km;
--   - capacidade média: veículos com capacidade de 1 a 100 lugares;
--   - IUC: alunos transportados / (veículos com capacidade de 1 a 70 × capacidade média deles);
--   - MON_CVE / MOT_CVE: vínculo efetivo ou comissionado (1, 2) / vínculo informado (1 a 4);
--   - TETI: alunos em rotas com veículo adequado (ônibus, micro-ônibus, van) / transportados;
--   - Censo: ATE = teto(transportados / escolas com transporte); MEDATE = teto(mediana dos
--     transportados por escola com transporte); PATM e PATE sobre (rede municipal + estadual);
--   - frota: idade = ano de carga − ano de fabricação (1930 até o ano de carga); IMFP e IMFT
--     são médias (frota própria / terceirizada); MIFCE é a mediana do Caminho da Escola
--     (modelo ≠ 0, mesma regra de analise.v_veiculos); PVPCE = Caminho da Escola / frota;
--   - municípios: código IBGE de 7 dígitos existente em ref.municipios e algum registro no SETE
--     (ref.municipios tem um código inválido de 9 dígitos, 520140500, que fica de fora).
-- Arredondamento com empate para o par (round de double precision), o mesmo do Python
-- que gerou as bases embutidas.
--
-- Interface pública:
--   public.indicadores_municipio_complemento  uma linha por município: {censo, frota}
--   public.sete_municipios                    um objeto JSON por ano de carga: {cols, municipios, ufs}
-- ============================================================================

-- Arredondamento com empate para o par (equivale ao round() do Python sobre double)
CREATE OR REPLACE FUNCTION analise.round_par(x double precision, casas integer) RETURNS double precision
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$ SELECT round(x * 10 ^ casas) / 10 ^ casas $$;

CREATE OR REPLACE FUNCTION analise.pct_par(a numeric, b numeric) RETURNS double precision
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT CASE WHEN b IS NOT NULL AND b <> 0 THEN analise.round_par(coalesce(a, 0)::float8 / b::float8 * 100, 2) END
$$;
COMMENT ON FUNCTION analise.pct_par(numeric, numeric) IS 'Percentual com 2 casas e empate para o par; NULL quando o denominador é 0 ou NULL.';

-- ---------------------------------------------------------------------------
-- Complementos municipais: Censo (pareado por ref.cargas) e frota do SETE
-- ---------------------------------------------------------------------------
CREATE MATERIALIZED VIEW analise.mv_complemento_municipio AS
WITH
cen AS (
    SELECT c.ano_carga_sete AS ano_carga, m.co_municipio::integer AS codigo_cidade,
           sum(m.qt_transp_publico)   AS transp,
           sum(m.qt_transp_resp_mun)  AS mun,
           sum(m.qt_transp_resp_est)  AS est,
           count(*) FILTER (WHERE m.qt_transp_publico > 0) AS esc_at,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY m.qt_transp_publico)
               FILTER (WHERE m.qt_transp_publico > 0) AS mediana
    FROM censo.matricula m
    JOIN ref.cargas c ON c.ano_carga_censo = m.ano_carga
    GROUP BY 1, 2),
fro AS (
    SELECT ano_carga, codigo_cidade,
           count(*)                             AS tot_veic,
           count(*) FILTER (WHERE origem = 1)   AS vp,
           count(*) FILTER (WHERE origem = 2)   AS vt,
           count(*) FILTER (WHERE modelo <> 0)  AS ce_veic,
           avg((ano_carga - ano)::float8) FILTER (WHERE origem = 1 AND ano BETWEEN 1930 AND ano_carga) AS idade_propria,
           avg((ano_carga - ano)::float8) FILTER (WHERE origem = 2 AND ano BETWEEN 1930 AND ano_carga) AS idade_terceirizada,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY ano_carga - ano)
               FILTER (WHERE modelo <> 0 AND ano BETWEEN 1930 AND ano_carga) AS mediana_ce
    FROM sete.veiculos
    GROUP BY 1, 2),
chaves AS (SELECT ano_carga, codigo_cidade FROM cen UNION SELECT ano_carga, codigo_cidade FROM fro)
SELECT k.ano_carga, k.codigo_cidade, lower(mu.uf) AS uf,
       CASE WHEN cen.codigo_cidade IS NOT NULL THEN jsonb_build_object(
           'ATE',    CASE WHEN cen.esc_at > 0 THEN ceil(cen.transp::numeric / cen.esc_at) END,
           'MEDATE', ceil(cen.mediana),
           'PATM',   analise.pct_par(cen.mun, cen.mun + cen.est),
           'PATE',   analise.pct_par(cen.est, cen.mun + cen.est),
           'transp', cen.transp, 'esc_at', cen.esc_at, 'mun', cen.mun, 'est', cen.est) END AS censo,
       CASE WHEN fro.codigo_cidade IS NOT NULL THEN jsonb_build_object(
           'PVPCE',  analise.pct_par(fro.ce_veic, fro.tot_veic),
           'IMFP',   analise.round_par(fro.idade_propria, 1),
           'IMFT',   analise.round_par(fro.idade_terceirizada, 1),
           'MIFCE',  fro.mediana_ce,
           'ce_veic', fro.ce_veic, 'tot_veic', fro.tot_veic, 'vp', fro.vp, 'vt', fro.vt) END AS frota
FROM chaves k
JOIN ref.municipios mu ON mu.codigo_ibge = k.codigo_cidade AND mu.codigo_ibge < 10000000
LEFT JOIN cen ON cen.ano_carga = k.ano_carga AND cen.codigo_cidade = k.codigo_cidade
LEFT JOIN fro ON fro.ano_carga = k.ano_carga AND fro.codigo_cidade = k.codigo_cidade
WITH NO DATA;

CREATE UNIQUE INDEX idx_mv_complemento_municipio ON analise.mv_complemento_municipio (ano_carga, codigo_cidade);
COMMENT ON MATERIALIZED VIEW analise.mv_complemento_municipio IS
  'Indicadores municipais do Censo (ATE, MEDATE, PATM, PATE) e da frota (PVPCE, IMFP, IMFT, MIFCE), com as regras das antigas bases embutidas.';

-- ---------------------------------------------------------------------------
-- Tabela "Dados SETE" por município (colunas do antigo SETE_MUN)
-- ---------------------------------------------------------------------------
CREATE MATERIALIZED VIEW analise.mv_sete_municipio AS
WITH
esc AS (SELECT ano_carga, codigo_cidade, count(*) AS n FROM sete.escolas GROUP BY 1, 2),
rk  AS (SELECT ano_carga, codigo_cidade,
               sum(km::float8) FILTER (WHERE km <= 2000)           AS km,
               count(*) FILTER (WHERE km > 0 AND km <= 2000)       AS n
        FROM sete.rotas GROUP BY 1, 2),
cap AS (SELECT ano_carga, codigo_cidade,
               avg(capacidade::float8) FILTER (WHERE capacidade > 0 AND capacidade <= 100) AS media_100,
               count(*) FILTER (WHERE capacidade > 0 AND capacidade <= 70)                 AS n_70,
               avg(capacidade::float8) FILTER (WHERE capacidade > 0 AND capacidade <= 70)  AS media_70
        FROM sete.veiculos GROUP BY 1, 2),
mon AS (SELECT ano_carga, codigo_cidade,
               count(*) FILTER (WHERE vinculo BETWEEN 1 AND 4) AS informado,
               count(*) FILTER (WHERE vinculo IN (1, 2))       AS cv
        FROM sete.monitores GROUP BY 1, 2),
mot AS (SELECT ano_carga, codigo_cidade, count(*) AS n,
               count(*) FILTER (WHERE vinculo BETWEEN 1 AND 4) AS informado,
               count(*) FILTER (WHERE vinculo IN (1, 2))       AS cv
        FROM sete.motoristas GROUP BY 1, 2),
fo  AS (SELECT ano_carga, codigo_cidade, count(*) AS n FROM sete.fornecedores GROUP BY 1, 2),
os  AS (SELECT ano_carga, codigo_cidade, count(*) AS n FROM sete.ordem_servico GROUP BY 1, 2),
nm  AS (SELECT ano_carga, codigo_cidade, count(*) AS n FROM sete.normas GROUP BY 1, 2),
eta AS (SELECT ano_carga, codigo_cidade, count(*) AS n FROM sete.escola_tem_aluno GROUP BY 1, 2),
rpe AS (SELECT ano_carga, codigo_cidade, count(*) AS n FROM sete.rota_passa_por_escolas GROUP BY 1, 2),
rpv AS (SELECT ano_carga, codigo_cidade, count(*) AS n FROM sete.rota_possui_veiculo GROUP BY 1, 2),
rdm AS (SELECT ano_carga, codigo_cidade, count(*) AS n FROM sete.rota_dirigida_por_motorista GROUP BY 1, 2),
-- Rotas com veículo adequado (ônibus, micro-ônibus ou van) e alunos atendidos por elas (TETI)
adequada AS (
    SELECT DISTINCT p.ano_carga, p.codigo_cidade, p.id_rota
    FROM sete.rota_possui_veiculo p
    JOIN sete.veiculos v ON v.ano_carga = p.ano_carga AND v.codigo_cidade = p.codigo_cidade AND v.id_veiculo = p.id_veiculo
    WHERE v.tipo IN (1, 2, 3)),
al_adeq AS (
    SELECT a.ano_carga, a.codigo_cidade, count(DISTINCT a.id_aluno) AS n
    FROM sete.rota_atende_aluno a
    JOIN adequada r ON r.ano_carga = a.ano_carga AND r.codigo_cidade = a.codigo_cidade AND r.id_rota = a.id_rota
    GROUP BY 1, 2),
base AS (
    SELECT b.*, mu.nome,
           coalesce(esc.n, 0) AS escolas, rk.km, coalesce(rk.n, 0) AS rotas_com_km,
           cap.media_100, cap.n_70, cap.media_70,
           coalesce(mon.informado, 0) AS mon_informado, coalesce(mon.cv, 0) AS mon_cv12,
           coalesce(mot.n, 0) AS motoristas, coalesce(mot.informado, 0) AS mot_informado, coalesce(mot.cv, 0) AS mot_cv12,
           coalesce(fo.n, 0) AS fornecedores, coalesce(os.n, 0) AS ordens_servico, coalesce(nm.n, 0) AS normas,
           coalesce(eta.n, 0) AS v_eta, coalesce(rpe.n, 0) AS v_rpe, coalesce(rpv.n, 0) AS v_rpv, coalesce(rdm.n, 0) AS v_rdm,
           coalesce(al_adeq.n, 0) AS al_adequado
    FROM analise.mv_base_municipio b
    JOIN ref.municipios mu ON mu.codigo_ibge = b.codigo_cidade AND mu.codigo_ibge < 10000000
    LEFT JOIN esc     USING (ano_carga, codigo_cidade)
    LEFT JOIN rk      USING (ano_carga, codigo_cidade)
    LEFT JOIN cap     USING (ano_carga, codigo_cidade)
    LEFT JOIN mon     USING (ano_carga, codigo_cidade)
    LEFT JOIN mot     USING (ano_carga, codigo_cidade)
    LEFT JOIN fo      USING (ano_carga, codigo_cidade)
    LEFT JOIN os      USING (ano_carga, codigo_cidade)
    LEFT JOIN nm      USING (ano_carga, codigo_cidade)
    LEFT JOIN eta     USING (ano_carga, codigo_cidade)
    LEFT JOIN rpe     USING (ano_carga, codigo_cidade)
    LEFT JOIN rpv     USING (ano_carga, codigo_cidade)
    LEFT JOIN rdm     USING (ano_carga, codigo_cidade)
    LEFT JOIN al_adeq USING (ano_carga, codigo_cidade))
SELECT base.ano_carga, base.codigo_cidade, base.uf, base.nome,
       base.al_cad, base.al_transp_sete, base.escolas, base.tot_rotas,
       coalesce(analise.round_par(base.km, 1), 0) AS km_total, coalesce(base.km, 0) AS km_bruto, base.rotas_com_km,
       base.t1, base.t2, base.t3, base.tot_veic, base.vp, base.vt,
       analise.round_par(base.media_100, 1) AS cap_media,
       base.tot_mon, base.motoristas, base.fornecedores, base.ordens_servico, base.normas,
       base.v_eta, base.v_rpe, base.v_rpv, base.v_rdm,
       analise.pct_par(base.georref, base.tot_rotas) AS prgm,
       analise.pct_par(base.dif, base.tot_rotas)     AS prdam,
       analise.pct_par(base.t1, base.tot_rotas)      AS prrm,
       analise.pct_par(base.t2, base.tot_rotas)      AS prhm,
       analise.pct_par(base.t3, base.tot_rotas)      AS prmm,
       analise.pct_par(base.vp, base.tot_veic)       AS pvp,
       analise.pct_par(base.vt, base.tot_veic)       AS pvt,
       analise.pct_par(base.mon_cv12, base.mon_informado) AS mon_cve,
       analise.pct_par(base.mot_cv12, base.mot_informado) AS mot_cve,
       CASE WHEN base.al_transp_sete > 0 AND base.n_70 > 0 AND base.media_70 > 0
            THEN analise.round_par(base.al_transp_sete / (base.n_70 * base.media_70), 2) END AS iuc,
       analise.pct_par(base.al_transp_sete, base.al_cad) AS tedc,
       analise.pct_par(base.al_adequado, base.al_transp_sete) AS teti
FROM base
WHERE base.al_cad > 0 OR base.tot_rotas > 0 OR base.tot_veic > 0 OR base.escolas > 0
   OR base.tot_mon > 0 OR base.motoristas > 0
WITH NO DATA;

CREATE UNIQUE INDEX idx_mv_sete_municipio ON analise.mv_sete_municipio (ano_carga, codigo_cidade);
COMMENT ON MATERIALIZED VIEW analise.mv_sete_municipio IS
  'Tabela "Dados SETE" por município (colunas do antigo SETE_MUN), com as regras validadas contra a base embutida.';

-- ---------------------------------------------------------------------------
-- Interface pública
-- ---------------------------------------------------------------------------
CREATE MATERIALIZED VIEW public.indicadores_municipio_complemento AS
SELECT ano_carga, codigo_cidade, uf, censo, frota
FROM analise.mv_complemento_municipio
WITH NO DATA;
CREATE UNIQUE INDEX idx_indicadores_municipio_complemento ON public.indicadores_municipio_complemento (ano_carga, codigo_cidade);
COMMENT ON MATERIALIZED VIEW public.indicadores_municipio_complemento IS
  'Indicadores municipais do Censo {ATE, MEDATE, PATM, PATE, ...} e da frota {PVPCE, IMFP, IMFT, MIFCE, ...} (lidos pela interface PNITE).';

CREATE MATERIALIZED VIEW public.sete_municipios AS
SELECT s.ano_carga,
       jsonb_build_object(
         'cols', jsonb_build_array('cod', 'mun', 'uf', 'alunos', 'al_transp', 'escolas', 'rotas', 'km_total', 'rotas_com_km',
                                   'rotas_t1', 'rotas_t2', 'rotas_t3', 'veiculos', 'veic_origem1', 'veic_origem2', 'cap_media',
                                   'monitores', 'motoristas', 'fornecedores', 'ordens_servico', 'normas', 'vinc_escola_aluno',
                                   'vinc_rota_escola', 'vinc_rota_veiculo', 'vinc_rota_motorista', 'PRGM', 'PRDAM', 'PRRM', 'PRHM',
                                   'PRMM', 'PVP', 'PVT', 'MON_CVE', 'MOT_CVE', 'ATE', 'MEDATE', 'IUC', 'TEDC', 'TETI', 'PATE', 'PATM',
                                   'PVPCE', 'IMFP', 'IMFT', 'MIFCE'),
         'municipios', (
           SELECT jsonb_agg(jsonb_build_array(
                    m.codigo_cidade, m.nome, upper(m.uf), m.al_cad, m.al_transp_sete, m.escolas, m.tot_rotas, m.km_total, m.rotas_com_km,
                    m.t1, m.t2, m.t3, m.tot_veic, m.vp, m.vt, m.cap_media,
                    m.tot_mon, m.motoristas, m.fornecedores, m.ordens_servico, m.normas, m.v_eta,
                    m.v_rpe, m.v_rpv, m.v_rdm, m.prgm, m.prdam, m.prrm, m.prhm,
                    m.prmm, m.pvp, m.pvt, m.mon_cve, m.mot_cve, c.censo -> 'ATE', c.censo -> 'MEDATE', m.iuc, m.tedc, m.teti,
                    c.censo -> 'PATE', c.censo -> 'PATM',
                    c.frota -> 'PVPCE', c.frota -> 'IMFP', c.frota -> 'IMFT', c.frota -> 'MIFCE') ORDER BY m.codigo_cidade)
           FROM analise.mv_sete_municipio m
           LEFT JOIN analise.mv_complemento_municipio c USING (ano_carga, codigo_cidade)
           WHERE m.ano_carga = s.ano_carga),
         'ufs', (
           SELECT jsonb_object_agg(upper(u.uf), jsonb_build_object(
                    'nome', uf.nome, 'mun', u.mun, 'alunos', u.alunos, 'at', u.at, 'escolas', u.escolas, 'rotas', u.rotas,
                    'km', u.km, 'km_n', u.km_n, 'rt1', u.rt1, 'rt2', u.rt2, 'rt3', u.rt3, 'veiculos', u.veiculos,
                    'vp', u.vp, 'vt', u.vt, 'cap', u.cap, 'monitores', u.monitores, 'motoristas', u.motoristas,
                    'fornecedores', u.fornecedores, 'ordens', u.ordens, 'normas', u.normas,
                    'v_eta', u.v_eta, 'v_rpe', u.v_rpe, 'v_rpv', u.v_rpv, 'v_rdm', u.v_rdm))
           FROM (
             SELECT m.uf, count(*) AS mun, sum(m.al_cad) AS alunos, sum(m.al_transp_sete) AS at, sum(m.escolas) AS escolas,
                    sum(m.tot_rotas) AS rotas, analise.round_par(sum(m.km_bruto), 1) AS km, sum(m.rotas_com_km) AS km_n,
                    sum(m.t1) AS rt1, sum(m.t2) AS rt2, sum(m.t3) AS rt3, sum(m.tot_veic) AS veiculos,
                    sum(m.vp) AS vp, sum(m.vt) AS vt,
                    (SELECT analise.round_par(avg(v.capacidade::float8), 1) FROM sete.veiculos v
                      JOIN ref.municipios mu ON mu.codigo_ibge = v.codigo_cidade AND mu.codigo_ibge < 10000000
                      WHERE v.ano_carga = s.ano_carga AND lower(v.uf) = m.uf AND v.capacidade > 0 AND v.capacidade <= 100) AS cap,
                    sum(m.tot_mon) AS monitores, sum(m.motoristas) AS motoristas, sum(m.fornecedores) AS fornecedores,
                    sum(m.ordens_servico) AS ordens, sum(m.normas) AS normas,
                    sum(m.v_eta) AS v_eta, sum(m.v_rpe) AS v_rpe, sum(m.v_rpv) AS v_rpv, sum(m.v_rdm) AS v_rdm
             FROM analise.mv_sete_municipio m
             WHERE m.ano_carga = s.ano_carga
             GROUP BY m.uf) u
           JOIN ref.uf uf ON uf.sigla = u.uf)
       ) AS dados
FROM (SELECT DISTINCT ano_carga FROM analise.mv_sete_municipio) s
WITH NO DATA;
CREATE UNIQUE INDEX idx_sete_municipios ON public.sete_municipios (ano_carga);
COMMENT ON MATERIALIZED VIEW public.sete_municipios IS
  'Tabela "Dados SETE": {cols, municipios (linhas por município), ufs (resumo por UF)} por ano de carga (lida pela interface PNITE).';

REVOKE ALL ON public.indicadores_municipio_complemento, public.sete_municipios FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.indicadores_municipio_complemento, public.sete_municipios TO anon, authenticated;

-- Atualização em cascata (a ordem importa: cada nível lê o anterior); mantém a lista da 0010
CREATE OR REPLACE FUNCTION pnite_meta.atualizar_indicadores() RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  mv text;
BEGIN
  FOREACH mv IN ARRAY ARRAY['analise.mv_base_municipio', 'analise.mv_tempo_rotas',
                            'public.indicadores_municipio', 'public.indicadores_estado',
                            'public.indicadores_regiao', 'public.indicadores_nacional',
                            'public.rotas_tracado',
                            'analise.mv_complemento_municipio', 'analise.mv_sete_municipio',
                            'public.indicadores_municipio_complemento', 'public.sete_municipios'] LOOP
    IF (SELECT ispopulated FROM pg_matviews WHERE schemaname || '.' || matviewname = mv)
       AND EXISTS (SELECT 1 FROM pg_indexes i JOIN pg_index x ON x.indexrelid = (i.schemaname || '.' || i.indexname)::regclass
                   WHERE i.schemaname || '.' || i.tablename = mv AND x.indisunique) THEN
      EXECUTE format('REFRESH MATERIALIZED VIEW CONCURRENTLY %s', mv);
    ELSE
      EXECUTE format('REFRESH MATERIALIZED VIEW %s', mv);
    END IF;
  END LOOP;
END
$$;
REVOKE ALL ON FUNCTION pnite_meta.atualizar_indicadores() FROM PUBLIC;
