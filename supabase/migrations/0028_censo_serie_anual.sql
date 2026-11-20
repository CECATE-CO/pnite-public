-- ============================================================================
-- PNITE — 0028: série anual do Censo Escolar (vários anos em censo.matricula)
--
-- censo.matricula passa a guardar vários anos (ano_carga = ano do Censo: 2023, 2024, 2025...).
-- Os indicadores das cargas do SETE continuam usando só o Censo pareado em ref.cargas; esta
-- migração acrescenta uma série independente do SETE, um ponto por ano do Censo, com os
-- indicadores que dependem apenas do Censo (ATE, MEDATE, PATM, PATE) e seus contadores, em
-- município, UF, região e Brasil, com as mesmas regras do complemento municipal (0013/0022):
--   ATE    = teto(alunos com transporte público ÷ escolas com transporte público)
--   MEDATE = teto(mediana dos alunos com transporte público por escola que tem transporte)
--   PATM   = transporte de responsabilidade municipal ÷ (municipal + estadual) × 100
--   PATE   = transporte de responsabilidade estadual  ÷ (municipal + estadual) × 100
-- Universo: escolas em atividade com matrícula (o recorte da tabela de matrículas de 2025; nos
-- arquivos de escolas de outros anos o carregador aplica o mesmo recorte).
-- ============================================================================

COMMENT ON COLUMN censo.matricula.ano_carga IS 'Ano do Censo Escolar da linha (a tabela guarda vários anos; o SETE usa o ano pareado em ref.cargas).';

CREATE MATERIALIZED VIEW analise.mv_censo_anual AS
WITH e AS (
    SELECT m.ano_carga AS ano_censo, m.co_municipio::integer AS codigo_cidade,
           coalesce(lower(nullif(trim(m.sg_uf), '')), mu.uf) AS uf, u.regiao,
           m.qt_mat_bas, m.qt_transp_publico, m.qt_transp_resp_mun, m.qt_transp_resp_est
    FROM censo.matricula m
    LEFT JOIN ref.municipios mu ON mu.codigo_ibge = m.co_municipio
    JOIN ref.uf u ON u.sigla = coalesce(lower(nullif(trim(m.sg_uf), '')), mu.uf)),
g AS (
    SELECT ano_censo,
           CASE WHEN GROUPING(codigo_cidade) = 0 THEN 'municipio'
                WHEN GROUPING(uf) = 0 THEN 'estado'
                WHEN GROUPING(regiao) = 0 THEN 'regiao'
                ELSE 'nacional' END AS nivel,
           CASE WHEN GROUPING(codigo_cidade) = 0 THEN codigo_cidade::text
                WHEN GROUPING(uf) = 0 THEN uf
                WHEN GROUPING(regiao) = 0 THEN regiao
                ELSE 'nacional' END AS chave,
           count(*)                                         AS escolas,
           sum(qt_mat_bas)                                  AS matriculas_basica,
           sum(qt_transp_publico)                           AS transp,
           sum(qt_transp_resp_mun)                          AS mun,
           sum(qt_transp_resp_est)                          AS est,
           count(*) FILTER (WHERE qt_transp_publico > 0)    AS esc_at,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY qt_transp_publico)
               FILTER (WHERE qt_transp_publico > 0)         AS mediana
    FROM e
    GROUP BY GROUPING SETS ((ano_censo, codigo_cidade, uf, regiao), (ano_censo, uf, regiao),
                            (ano_censo, regiao), (ano_censo)))
SELECT ano_censo::smallint AS ano_censo, nivel, chave,
       jsonb_build_object(
           'ATE',    CASE WHEN esc_at > 0 THEN ceil(transp::numeric / esc_at) END,
           'MEDATE', ceil(mediana),
           'PATM',   analise.pct_par(mun, mun + est),
           'PATE',   analise.pct_par(est, mun + est)) AS ind,
       jsonb_build_object(
           'escolas', escolas, 'matriculas_basica', matriculas_basica, 'transp', transp,
           'esc_at', esc_at, 'mun', mun, 'est', est) AS raw
FROM g;

CREATE UNIQUE INDEX idx_mv_censo_anual ON analise.mv_censo_anual (ano_censo, nivel, chave);
COMMENT ON MATERIALIZED VIEW analise.mv_censo_anual IS
  'Série anual do Censo Escolar: ATE, MEDATE, PATM e PATE (regras do complemento municipal) e contadores, por ano, nível e chave.';

-- API: série anual do Censo (somente leitura)
CREATE MATERIALIZED VIEW public.indicadores_censo_anual AS
SELECT ano_censo, nivel, chave, ind, raw, now() AS atualizado_em
FROM analise.mv_censo_anual;
CREATE UNIQUE INDEX idx_indicadores_censo_anual ON public.indicadores_censo_anual (ano_censo, nivel, chave);
COMMENT ON MATERIALIZED VIEW public.indicadores_censo_anual IS
  'PNITE — indicadores do Censo Escolar por ano (ATE, MEDATE, PATM, PATE e contadores). Ex.: /rest/v1/indicadores_censo_anual?nivel=eq.estado&chave=eq.go&order=ano_censo';

REVOKE ALL ON public.indicadores_censo_anual FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.indicadores_censo_anual TO anon, authenticated;

-- Cascata: a série anual entra no fim (não depende das cargas do SETE)
CREATE OR REPLACE FUNCTION pnite_meta.atualizar_indicadores() RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  mv text;
BEGIN
  FOREACH mv IN ARRAY ARRAY['analise.mv_base_municipio', 'analise.mv_tempo_rotas', 'analise.mv_rotas_estatisticas',
                            'analise.mv_medianas_nivel',
                            'public.indicadores_municipio', 'public.indicadores_estado',
                            'public.indicadores_regiao', 'public.indicadores_nacional',
                            'public.rotas_tracado',
                            'analise.mv_complemento_municipio', 'analise.mv_sete_municipio',
                            'public.indicadores_municipio_complemento', 'public.sete_municipios',
                            'public.cargas_sete',
                            'analise.mv_censo_anual', 'public.indicadores_censo_anual'] LOOP
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
