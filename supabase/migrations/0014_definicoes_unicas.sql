-- ============================================================================
-- PNITE — 0014: definições únicas de km, capacidade, vínculo e código de município
-- ----------------------------------------------------------------------------
-- Unifica regras que divergiam entre o painel principal (public.indicadores_*) e a
-- tabela "Dados SETE" (0013), aprovadas pelo usuário:
--   1) km: rota com mais de 2.000 km é erro de cadastro e não entra em km_total, km_geo,
--      km_medio nem rotas_com_km (125 rotas, 4,9 mi km, 53% do km total antes da regra).
--      Em analise.v_rotas o km passa a NULL nesses casos; o valor original fica em km_informado
--      (mesmo padrão de tempo_valido e de idade negativa -> NULL).
--   2) capacidade válida: 1 a 100 lugares (antes 1 a 150 no painel; 1 a 70 no IUC da tabela SETE).
--   3) vínculo de motoristas e monitores: efetivo, comissionado ou terceirizado (1, 2, 3) sobre o
--      vínculo informado, como já fazia o painel (PMVE/PMNVE); a tabela SETE passa a usar o mesmo valor.
--   4) município: só códigos IBGE de 7 dígitos. Remove de ref.municipios a linha duplicada de
--      Aparecida de Goiânia com código 520140500 (vinda da Lista de Municípios IBGE) e o aluno
--      cadastrado com esse código no SETE.
-- A tabela SETE passa a ler km_total, cap_media, IUC, MON_CVE e MOT_CVE dos mesmos valores do
-- painel (public.indicadores_municipio), para que não voltem a divergir.
-- ============================================================================

DELETE FROM ref.municipios WHERE codigo_ibge NOT BETWEEN 1000000 AND 9999999;

-- Views de leitura limpa (definições da 0005 com as regras acima)
CREATE OR REPLACE VIEW analise.v_alunos WITH (security_invoker = true) AS
SELECT ano_carga, codigo_cidade, lower(uf) AS uf, id_aluno,
       loc_latitude, loc_longitude,
       analise.sn(da_porteira) AS da_porteira, analise.sn(da_mataburro) AS da_mataburro,
       analise.sn(da_colchete) AS da_colchete, analise.sn(da_atoleiro) AS da_atoleiro,
       analise.sn(da_ponterustica) AS da_ponterustica,
       (analise.sn(da_porteira) OR analise.sn(da_mataburro) OR analise.sn(da_colchete)
        OR analise.sn(da_atoleiro) OR analise.sn(da_ponterustica)) AS tem_impedancia,
       CASE WHEN idade >= 0 THEN idade END AS idade,
       sexo, CASE sexo WHEN 1 THEN 'Masculino' WHEN 2 THEN 'Feminino' WHEN 3 THEN 'Não informado' END AS sexo_label,
       cor, CASE cor WHEN 1 THEN 'Branco' WHEN 2 THEN 'Preto' WHEN 3 THEN 'Pardo' WHEN 4 THEN 'Amarelo'
                     WHEN 5 THEN 'Indígena' WHEN 0 THEN 'Não declarada' END AS cor_label,
       grau_responsavel,
       CASE grau_responsavel WHEN -1 THEN 'Não informado' WHEN 0 THEN 'Pai, Mãe, Padrasto ou Madrasta'
                             WHEN 1 THEN 'Avô ou Avó' WHEN 2 THEN 'Irmão ou Irmã' WHEN 4 THEN 'Outro Parente'
       END AS grau_responsavel_label,
       analise.sn(def_caminhar) AS def_caminhar, analise.sn(def_ouvir) AS def_ouvir,
       analise.sn(def_enxergar) AS def_enxergar, analise.sn(def_mental) AS def_mental,
       (analise.sn(def_caminhar) OR analise.sn(def_ouvir) OR analise.sn(def_enxergar)
        OR analise.sn(def_mental)) AS tem_deficiencia,
       turno, CASE turno WHEN 1 THEN 'Manhã' WHEN 2 THEN 'Tarde' WHEN 3 THEN 'Noite'
                         WHEN 4 THEN 'Manhã e Tarde (Integral)' END AS turno_label,
       nivel, CASE nivel WHEN 1 THEN 'Infantil / Pré-escola' WHEN 2 THEN 'Fundamental' WHEN 3 THEN 'Médio'
                         WHEN 4 THEN 'Superior' WHEN 5 THEN 'Outro' END AS nivel_label,
       dt_criacao, dt_alteracao
FROM sete.alunos
WHERE codigo_cidade BETWEEN 1000000 AND 9999999;

CREATE OR REPLACE VIEW analise.v_rotas WITH (security_invoker = true) AS
SELECT ano_carga, codigo_cidade, lower(uf) AS uf, id_rota, nome,
       CASE WHEN km <= 2000 THEN km END AS km,                       -- acima de 2.000 km: erro de cadastro
       analise.sn(da_porteira) AS da_porteira, analise.sn(da_mataburro) AS da_mataburro,
       analise.sn(da_colchete) AS da_colchete, analise.sn(da_atoleiro) AS da_atoleiro,
       analise.sn(da_ponterustica) AS da_ponterustica,
       (analise.sn(da_porteira) OR analise.sn(da_mataburro) OR analise.sn(da_colchete)
        OR analise.sn(da_atoleiro) OR analise.sn(da_ponterustica)) AS tem_impedancia,
       analise.sn(turno_matutino) AS turno_matutino, analise.sn(turno_vespertino) AS turno_vespertino,
       analise.sn(turno_noturno) AS turno_noturno,
       tem_shape,
       tempo,
       coalesce(tempo BETWEEN 1 AND 360, false) AS tempo_valido,   -- faixa operacional usada no tempo mediano
       tipo, CASE tipo WHEN 1 THEN 'Rodoviário' WHEN 2 THEN 'Aquaviário' WHEN 3 THEN 'Mista' END AS tipo_label,
       ativo,
       km AS km_informado                                            -- valor original do cadastro
FROM sete.rotas
WHERE codigo_cidade BETWEEN 1000000 AND 9999999;

CREATE OR REPLACE VIEW analise.v_veiculos WITH (security_invoker = true) AS
SELECT ano_carga, codigo_cidade, lower(uf) AS uf, id_veiculo, placa, renavam,
       ano AS ano_fabricacao,
       modo, CASE modo WHEN 0 THEN 'Rodoviário' WHEN 1 THEN 'Aquaviário' END AS modo_label,
       origem, CASE origem WHEN 1 THEN 'Veículo Próprio' WHEN 2 THEN 'Veículo Terceirizado' END AS origem_label,
       capacidade,
       coalesce(capacidade > 0 AND capacidade <= 100, false) AS capacidade_valida,  -- 1 a 100 lugares: capacidade média e IUC
       km_inicial, km_atual,
       tipo, CASE tipo WHEN 1 THEN 'Ônibus' WHEN 2 THEN 'Micro-ônibus' WHEN 3 THEN 'Van' WHEN 4 THEN 'Kombi'
                       WHEN 5 THEN 'Caminhão' WHEN 6 THEN 'Caminhonete' WHEN 7 THEN 'Motocicleta'
                       WHEN 8 THEN 'Animal de tração' WHEN 9 THEN 'Lancha/Voadeira' WHEN 10 THEN 'Barco de Madeira'
                       WHEN 11 THEN 'Barco de alumínio' WHEN 12 THEN 'Canoa motorizada' WHEN 13 THEN 'Canoa a remo'
                       WHEN 14 THEN 'Bicicleta' WHEN 99 THEN 'Outro' END AS tipo_label,
       analise.sn(manutencao) AS manutencao,
       marca,
       ipva, dpvat, seguro_anual, consumo,
       tipo_combustivel,
       CASE upper(tipo_combustivel) WHEN 'G' THEN 'Gasolina' WHEN 'D' THEN 'Diesel' WHEN 'E' THEN 'Etanol'
                                    WHEN 'N' THEN 'Gás Natural' WHEN 'O' THEN 'Outro' END AS tipo_combustivel_label,
       numero_de_pneus, vida_util_do_pneu, preco, potencia_do_motor,
       modelo, CASE modelo WHEN 0 THEN 'Não se aplica' WHEN 1 THEN 'ORE 1' WHEN 2 THEN 'ORE 1 (4x4)'
                           WHEN 3 THEN 'ORE 2' WHEN 4 THEN 'ORE 3' WHEN 6 THEN 'ONUREA'
                           WHEN 7 THEN 'Lancha a Gasolina' WHEN 8 THEN 'Lancha a Diesel' END AS modelo_label,
       coalesce(modelo <> 0, false) AS caminho_da_escola,   -- modelo ≠ 0: veículo do programa Caminho da Escola
       ativo, dt_criacao, dt_alteracao
FROM sete.veiculos
WHERE codigo_cidade BETWEEN 1000000 AND 9999999;

CREATE OR REPLACE VIEW analise.v_motoristas WITH (security_invoker = true) AS
SELECT ano_carga, codigo_cidade, lower(uf) AS uf,
       CASE WHEN idade >= 0 THEN idade END AS idade,
       sexo, CASE sexo WHEN 1 THEN 'Masculino' WHEN 2 THEN 'Feminino' WHEN 3 THEN 'Não informado' END AS sexo_label,
       analise.sn(tem_cnh_a) AS tem_cnh_a, analise.sn(tem_cnh_b) AS tem_cnh_b, analise.sn(tem_cnh_c) AS tem_cnh_c,
       analise.sn(tem_cnh_d) AS tem_cnh_d, analise.sn(tem_cnh_e) AS tem_cnh_e,
       analise.sn(turno_manha) AS turno_manha, analise.sn(turno_tarde) AS turno_tarde,
       analise.sn(turno_noite) AS turno_noite,
       data_validade_cnh,
       vinculo, CASE vinculo WHEN 1 THEN 'Servidor Efetivo' WHEN 2 THEN 'Servidor Comissionado'
                             WHEN 3 THEN 'Terceirizado' WHEN 4 THEN 'Outro' END AS vinculo_label,
       coalesce(vinculo BETWEEN 1 AND 4, false) AS vinculo_informado,
       coalesce(vinculo IN (1, 2, 3), false)    AS vinculo_formal,
       coalesce(vinculo = 4, false)             AS sem_vinculo,
       salario
FROM sete.motoristas
WHERE codigo_cidade BETWEEN 1000000 AND 9999999;

CREATE OR REPLACE VIEW analise.v_monitores WITH (security_invoker = true) AS
SELECT ano_carga, codigo_cidade, lower(uf) AS uf,
       CASE WHEN idade >= 0 THEN idade END AS idade,
       sexo, CASE sexo WHEN 1 THEN 'Masculino' WHEN 2 THEN 'Feminino' WHEN 3 THEN 'Não informado' END AS sexo_label,
       analise.sn(turno_manha) AS turno_manha, analise.sn(turno_tarde) AS turno_tarde,
       analise.sn(turno_noite) AS turno_noite,
       vinculo, CASE vinculo WHEN 1 THEN 'Servidor Efetivo' WHEN 2 THEN 'Servidor Comissionado'
                             WHEN 3 THEN 'Terceirizado' WHEN 4 THEN 'Outro' END AS vinculo_label,
       coalesce(vinculo BETWEEN 1 AND 4, false) AS vinculo_informado,
       coalesce(vinculo IN (1, 2, 3), false)    AS vinculo_formal,
       coalesce(vinculo = 4, false)             AS sem_vinculo,
       salario, dt_criacao, dt_alteracao
FROM sete.monitores
WHERE codigo_cidade BETWEEN 1000000 AND 9999999;

-- ---------------------------------------------------------------------------
-- Tabela "Dados SETE" (0013) com os valores do painel principal
-- ---------------------------------------------------------------------------
DROP MATERIALIZED VIEW public.sete_municipios;
DROP MATERIALIZED VIEW analise.mv_sete_municipio;

CREATE MATERIALIZED VIEW analise.mv_sete_municipio AS
WITH
esc AS (SELECT ano_carga, codigo_cidade, count(*) AS n FROM sete.escolas GROUP BY 1, 2),
rk  AS (SELECT ano_carga, codigo_cidade, count(*) FILTER (WHERE km > 0) AS n
        FROM analise.v_rotas GROUP BY 1, 2),
mot AS (SELECT ano_carga, codigo_cidade, count(*) AS n FROM analise.v_motoristas GROUP BY 1, 2),
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
           coalesce(esc.n, 0) AS escolas, coalesce(rk.n, 0) AS rotas_com_km,
           coalesce(mot.n, 0) AS motoristas,
           i.indicadores AS ind,
           coalesce(fo.n, 0) AS fornecedores, coalesce(os.n, 0) AS ordens_servico, coalesce(nm.n, 0) AS normas,
           coalesce(eta.n, 0) AS v_eta, coalesce(rpe.n, 0) AS v_rpe, coalesce(rpv.n, 0) AS v_rpv, coalesce(rdm.n, 0) AS v_rdm,
           coalesce(al_adeq.n, 0) AS al_adequado
    FROM analise.mv_base_municipio b
    JOIN ref.municipios mu ON mu.codigo_ibge = b.codigo_cidade AND mu.codigo_ibge < 10000000
    LEFT JOIN esc     USING (ano_carga, codigo_cidade)
    LEFT JOIN rk      USING (ano_carga, codigo_cidade)
    LEFT JOIN mot     USING (ano_carga, codigo_cidade)
    LEFT JOIN fo      USING (ano_carga, codigo_cidade)
    LEFT JOIN os      USING (ano_carga, codigo_cidade)
    LEFT JOIN nm      USING (ano_carga, codigo_cidade)
    LEFT JOIN eta     USING (ano_carga, codigo_cidade)
    LEFT JOIN rpe     USING (ano_carga, codigo_cidade)
    LEFT JOIN rpv     USING (ano_carga, codigo_cidade)
    LEFT JOIN rdm     USING (ano_carga, codigo_cidade)
    LEFT JOIN al_adeq USING (ano_carga, codigo_cidade)
    -- valores do painel principal: mesma definição de km, capacidade, IUC e vínculo
    LEFT JOIN public.indicadores_municipio i ON i.ano_carga = b.ano_carga AND i.codigo_cidade = b.codigo_cidade AND i.uf = b.uf)
SELECT base.ano_carga, base.codigo_cidade, base.uf, base.nome,
       base.al_cad, base.al_transp_sete, base.escolas, base.tot_rotas,
       round(base.km_total, 1) AS km_total, base.km_total AS km_bruto, base.rotas_com_km,
       base.t1, base.t2, base.t3, base.tot_veic, base.vp, base.vt,
       CASE WHEN base.n_veic_validos > 0 THEN round(base.cap_sum / base.n_veic_validos, 2) END AS cap_media,
       base.cap_sum, base.n_veic_validos,
       base.tot_mon, base.motoristas, base.fornecedores, base.ordens_servico, base.normas,
       base.v_eta, base.v_rpe, base.v_rpv, base.v_rdm,
       analise.pct_par(base.georref, base.tot_rotas) AS prgm,
       analise.pct_par(base.dif, base.tot_rotas)     AS prdam,
       analise.pct_par(base.t1, base.tot_rotas)      AS prrm,
       analise.pct_par(base.t2, base.tot_rotas)      AS prhm,
       analise.pct_par(base.t3, base.tot_rotas)      AS prmm,
       analise.pct_par(base.vp, base.tot_veic)       AS pvp,
       analise.pct_par(base.vt, base.tot_veic)       AS pvt,
       (base.ind ->> 'PMNVE')::numeric AS mon_cve,
       (base.ind ->> 'PMVE')::numeric  AS mot_cve,
       (base.ind ->> 'IUC')::numeric   AS iuc,
       analise.pct_par(base.al_transp_sete, base.al_cad) AS tedc,
       analise.pct_par(base.al_adequado, base.al_transp_sete) AS teti
FROM base
WHERE base.al_cad > 0 OR base.tot_rotas > 0 OR base.tot_veic > 0 OR base.escolas > 0
   OR base.tot_mon > 0 OR base.motoristas > 0
WITH NO DATA;

CREATE UNIQUE INDEX idx_mv_sete_municipio ON analise.mv_sete_municipio (ano_carga, codigo_cidade);
COMMENT ON MATERIALIZED VIEW analise.mv_sete_municipio IS
  'Tabela "Dados SETE" por município; km_total, cap_media, IUC, MON_CVE e MOT_CVE iguais aos do painel (public.indicadores_municipio).';

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
                    round(sum(m.cap_sum) / nullif(sum(m.n_veic_validos), 0), 2) AS cap,
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
REVOKE ALL ON public.sete_municipios FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.sete_municipios TO anon, authenticated;
