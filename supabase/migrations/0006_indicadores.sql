-- ============================================================================
-- PNITE — 0006: indicadores por escopo (camada pública, lida pela API)
-- ----------------------------------------------------------------------------
-- public.indicadores: uma linha por (ano_carga, nivel, chave) — Brasil, 5 regiões,
-- 27 UFs e cada município — com:
--   raw         contadores no formato de RAW_DATA do front-end;
--   indicadores indicadores no formato de DATA (mesmas fórmulas de calcular_indicadores()
--               em extrair_dados_excel.py);
--   detalhes    detalhes_scripts das planilhas consolidadas (somente UF/nacional).
-- Só contém agregados: é a única relação legível com a chave publishable (anon).
--
-- Consultas típicas (PostgREST):
--   /rest/v1/indicadores?ano_carga=eq.2026&nivel=eq.estado&chave=eq.go
--   /rest/v1/indicadores?ano_carga=eq.2026&nivel=eq.estado&select=chave,label,indicadores
--   /rest/v1/indicadores?ano_carga=eq.2026&nivel=eq.municipio&uf=eq.go&select=chave,label,indicadores
-- ============================================================================

-- Número de um campo jsonb (NULL se ausente ou não numérico)
CREATE OR REPLACE FUNCTION analise.num(r jsonb, k text) RETURNS numeric
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT CASE WHEN jsonb_typeof(r -> k) = 'number' THEN (r ->> k)::numeric END
$$;

-- pct(a, b) do extrair_dados_excel.py: round(a / b * 100, 2) se b > 0 e a não nulo
CREATE OR REPLACE FUNCTION analise.pct(a numeric, b numeric) RETURNS numeric
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT CASE WHEN b > 0 AND a IS NOT NULL THEN round(a / b * 100, 2) END
$$;

-- Porta fiel de calcular_indicadores(r, label) (extrair_dados_excel.py)
CREATE OR REPLACE FUNCTION analise.calcular_indicadores(r jsonb, label text) RETURNS jsonb
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  WITH v AS (
    SELECT analise.num(r, 'tot_rotas') AS tr, analise.num(r, 'tot_veic') AS tv,
           analise.num(r, 'n_veic_validos') AS nvv, analise.num(r, 'cap_media') AS cap_m,
           analise.num(r, 'al_transp') AS at, analise.num(r, 'esc_at') AS ea,
           analise.num(r, 'tot_mon') AS tm, analise.num(r, 'tot_mot_info') AS tmi,
           analise.num(r, 'dif') AS dif, analise.num(r, 'al_cad') AS al_cad,
           coalesce(analise.num(r, 'mot_sem_vinculo'), 0) AS mot_sem,
           coalesce(analise.num(r, 'mon_sem_vinculo'), 0) AS mon_sem
  ), c AS (
    SELECT v.*,
           analise.pct(dif, tr) AS prio,
           CASE WHEN tmi > 0 THEN round((1 - mot_sem / tmi) * 100, 2)
                ELSE analise.pct(analise.num(r, 'mot_cv'), tmi) END AS pmve,
           CASE WHEN tm > 0 THEN round((1 - mon_sem / tm) * 100, 2)
                ELSE analise.pct(analise.num(r, 'mon_cv'), tm) END AS pmnve,
           CASE WHEN at <> 0 AND nvv <> 0 AND cap_m <> 0 AND nvv * cap_m > 0
                THEN round(at / (nvv * cap_m), 2) END AS iuc,
           CASE WHEN at <> 0 AND ea > 0 THEN round(at / ea, 2) END AS ate
    FROM v
  )
  SELECT jsonb_build_object(
    'label', label,
    'PRGM',  analise.pct(analise.num(r, 'georref'), tr),
    'PRDAM', prio,
    'PRIO',  prio,
    'PRRM',  analise.pct(analise.num(r, 't1'), tr),
    'PRHM',  analise.pct(analise.num(r, 't2'), tr),
    'PRMM',  analise.pct(analise.num(r, 't3'), tr),
    'PVP',   analise.pct(analise.num(r, 'vp'), tv),
    'PVT',   analise.pct(analise.num(r, 'vt'), tv),
    'PVPCE', analise.pct(analise.num(r, 'ce_veic'), tv),
    'PECS',  analise.pct(analise.num(r, 'sete_esc'), analise.num(r, 'cs_esc_transp')),
    'IUC',   iuc,
    'PMVE',  pmve,
    'PMNVE', pmnve,
    'MON_CVE', pmnve,
    'MOT_CVE', pmve,
    'PRPM',  NULL,
    'ATE',   ate,
    'TETI',  NULL,
    'IPE',   NULL,
    'TEDC',  analise.pct(at, al_cad),
    'PATM',  analise.pct(analise.num(r, 'cs_tmun'), analise.num(r, 'cs_transp')),
    'PATE',  analise.pct(analise.num(r, 'cs_test'), analise.num(r, 'cs_transp')),
    'IPTE',  NULL,
    'MEDATE', r -> 'medate_val',
    'ICA',   NULL,
    'IMFP',  r -> 'imfp',
    'IMFT',  r -> 'imft',
    'MIFCE', r -> 'mifce',
    'PAFI',  NULL,
    'PAD',   analise.pct(analise.num(r, 'al_pcd'), al_cad),
    'PARI',  analise.pct(analise.num(r, 'al_dif'), coalesce(nullif(al_cad, 0), at)),
    'PCSC',  analise.pct(analise.num(r, 'al_transp_sete'), analise.num(r, 'demanda_censo')),
    'PAIH',  NULL,
    'PRPNP', NULL,
    'DMC',   NULL,
    'PVCED', NULL,
    'TVA',   r -> 'tva'
  )
  FROM c
$$;
COMMENT ON FUNCTION analise.calcular_indicadores(jsonb, text) IS
  'Indicadores (formato DATA) a partir dos contadores (formato RAW_DATA). Porta de calcular_indicadores() do extrair_dados_excel.py.';

CREATE MATERIALIZED VIEW IF NOT EXISTS public.indicadores AS
WITH base AS (
    SELECT b.*, u.regiao
    FROM analise.mv_base_municipio b
    JOIN ref.uf u ON u.sigla = b.uf
),
agg AS (
    SELECT ano_carga,
           CASE WHEN GROUPING(codigo_cidade) = 0 THEN 'municipio'
                WHEN GROUPING(uf) = 0 THEN 'estado'
                WHEN GROUPING(regiao) = 0 THEN 'regiao'
                ELSE 'nacional' END AS nivel,
           CASE WHEN GROUPING(codigo_cidade) = 0 THEN codigo_cidade::text
                WHEN GROUPING(uf) = 0 THEN uf
                WHEN GROUPING(regiao) = 0 THEN regiao
                ELSE 'nacional' END AS chave,
           CASE WHEN GROUPING(uf) = 0 THEN uf END AS uf,
           CASE WHEN GROUPING(regiao) = 0 THEN regiao END AS regiao,
           sum(al_cad) AS al_cad, sum(al_pcd) AS al_pcd, sum(al_dif) AS al_dif,
           sum(al_porteira) AS al_porteira, sum(al_mataburro) AS al_mataburro, sum(al_colchete) AS al_colchete,
           sum(al_atoleiro) AS al_atoleiro, sum(al_ponte) AS al_ponte,
           sum(tot_rotas) AS tot_rotas, sum(georref) AS georref, sum(dif) AS dif,
           sum(t1) AS t1, sum(t2) AS t2, sum(t3) AS t3,
           sum(rot_porteira) AS rot_porteira, sum(rot_mataburro) AS rot_mataburro,
           sum(rot_colchete) AS rot_colchete, sum(rot_atoleiro) AS rot_atoleiro, sum(rot_ponte) AS rot_ponte,
           sum(km_total) AS km_total, sum(km_geo) AS km_geo,
           sum(tot_veic) AS tot_veic, sum(vp) AS vp, sum(vt) AS vt,
           sum(n_veic_validos) AS n_veic_validos, sum(cap_sum) AS cap_sum, sum(ce_veic_sete) AS ce_veic_sete,
           sum(tot_mot_info) AS tot_mot_info, sum(mot_sem_vinculo) AS mot_sem_vinculo, sum(mot_cv) AS mot_cv,
           sum(tot_mon) AS tot_mon, sum(mon_sem_vinculo) AS mon_sem_vinculo, sum(mon_cv) AS mon_cv,
           sum(al_transp_sete) AS al_transp_sete, sum(esc_at_sete) AS esc_at_sete,
           sum(demanda_censo) AS demanda_censo
    FROM base
    GROUP BY GROUPING SETS ((ano_carga, codigo_cidade, uf, regiao), (ano_carga, uf, regiao),
                            (ano_carga, regiao), (ano_carga))
),
calc AS (
    SELECT a.ano_carga, a.nivel, a.chave, a.uf, a.regiao,
           jsonb_build_object(
             'tot_rotas', a.tot_rotas, 'georref', a.georref, 'dif', a.dif,
             't1', a.t1, 't2', a.t2, 't3', a.t3,
             'km_total', round(a.km_total, 1), 'km_geo', round(a.km_geo, 1),
             'km_medio', CASE WHEN a.tot_rotas > 0 THEN round(round(a.km_total, 1) / a.tot_rotas, 1) END,
             'rot_porteira', a.rot_porteira, 'rot_mataburro', a.rot_mataburro, 'rot_colchete', a.rot_colchete,
             'rot_atoleiro', a.rot_atoleiro, 'rot_ponte', a.rot_ponte,
             'tot_veic', a.tot_veic, 'vp', a.vp, 'vt', a.vt,
             'n_veic_validos', a.n_veic_validos, 'cap_sum', a.cap_sum,
             'cap_media', CASE WHEN a.n_veic_validos > 0 THEN round(a.cap_sum / a.n_veic_validos, 2) ELSE 0.0 END,
             'ce_veic_sete', a.ce_veic_sete,
             'al_cad', a.al_cad, 'al_pcd', a.al_pcd, 'al_dif', a.al_dif,
             'al_porteira', a.al_porteira, 'al_mataburro', a.al_mataburro, 'al_colchete', a.al_colchete,
             'al_atoleiro', a.al_atoleiro, 'al_ponte', a.al_ponte,
             'al_transp_sete', a.al_transp_sete, 'al_transp', a.al_transp_sete,
             'esc_at_sete', a.esc_at_sete,
             'demanda_censo', a.demanda_censo,
             'tot_mot_info', a.tot_mot_info, 'mot_sem_vinculo', a.mot_sem_vinculo, 'mot_cv', a.mot_cv,
             'tot_mon', a.tot_mon, 'mon_sem_vinculo', a.mon_sem_vinculo, 'mon_cv', a.mon_cv
           ) || jsonb_strip_nulls(jsonb_build_object('tempo_mediano', t.tempo_mediano, 'tempo_medio', t.tempo_medio))
             AS calculado
    FROM agg a
    LEFT JOIN analise.mv_tempo_rotas t USING (ano_carga, nivel, chave)
)
SELECT c.ano_carga, c.nivel, c.chave,
       coalesce(c.uf, CASE WHEN c.nivel = 'estado' THEN c.chave END) AS uf,
       c.regiao,
       lbl.label,
       -- contadores calculados dos dados brutos sobrepõem os valores de referência (legado + planilhas)
       coalesce(rr.dados, '{}'::jsonb) || c.calculado AS raw,
       analise.calcular_indicadores(coalesce(rr.dados, '{}'::jsonb) || c.calculado, lbl.label) AS indicadores,
       det.detalhes,
       now() AS atualizado_em
FROM calc c
LEFT JOIN ref.raw_referencia rr ON rr.ano_carga = c.ano_carga AND rr.chave = c.chave AND c.nivel <> 'municipio'
LEFT JOIN LATERAL (
    SELECT jsonb_object_agg(d.script, d.dados) AS detalhes
    FROM ref.detalhes_scripts d
    WHERE d.ano_carga = c.ano_carga AND d.chave = c.chave AND c.nivel IN ('estado', 'nacional')
) det ON true
LEFT JOIN LATERAL (
    SELECT CASE c.nivel
             WHEN 'nacional'  THEN 'Brasil'
             WHEN 'regiao'    THEN (SELECT min(regiao_label) FROM ref.uf WHERE regiao = c.chave)
             WHEN 'estado'    THEN (SELECT nome FROM ref.uf WHERE sigla = c.chave)
             ELSE coalesce((SELECT m.nome FROM ref.municipios m WHERE m.codigo_ibge = c.chave::integer),
                           'Município ' || c.chave) || ' (' || upper(c.uf) || ')'
           END AS label
) lbl ON true
WITH NO DATA;

CREATE UNIQUE INDEX IF NOT EXISTS idx_indicadores_pk ON public.indicadores (ano_carga, nivel, chave);
CREATE INDEX IF NOT EXISTS idx_indicadores_uf ON public.indicadores (ano_carga, nivel, uf);
COMMENT ON MATERIALIZED VIEW public.indicadores IS
  'PNITE — indicadores agregados por escopo (nacional, região, UF, município). Somente leitura via API.';

-- Somente leitura para a API (anon/authenticated); nada mais é exposto.
REVOKE ALL ON public.indicadores FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.indicadores TO anon, authenticated;

-- Atualiza toda a cadeia após uma carga
CREATE OR REPLACE FUNCTION pnite_meta.atualizar_indicadores() RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  mv text;
BEGIN
  FOREACH mv IN ARRAY ARRAY['analise.mv_base_municipio', 'analise.mv_tempo_rotas', 'public.indicadores'] LOOP
    IF (SELECT ispopulated FROM pg_matviews WHERE schemaname || '.' || matviewname = mv) THEN
      EXECUTE format('REFRESH MATERIALIZED VIEW CONCURRENTLY %s', mv);
    ELSE
      EXECUTE format('REFRESH MATERIALIZED VIEW %s', mv);
    END IF;
  END LOOP;
END
$$;
REVOKE ALL ON FUNCTION pnite_meta.atualizar_indicadores() FROM PUBLIC;
