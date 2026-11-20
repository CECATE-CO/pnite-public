-- ============================================================================
-- PNITE — 0029: valores municipais do Censo Escolar por ano, numa linha por ano
--
-- Usada pela interface quando o usuário escolhe um ano do Censo diferente do pareado à carga do
-- SETE: o mapa e a tabela municipal trocam ATE, MEDATE, PATM e PATE de todos os municípios numa
-- única consulta (public.indicadores_censo_anual tem uma linha por município e ano).
-- dados = { "<código IBGE>": [ATE, MEDATE, PATM, PATE, transp, esc_at, mun, est], ... }
-- ============================================================================

CREATE MATERIALIZED VIEW public.censo_anual_municipios AS
SELECT ano_censo,
       jsonb_object_agg(chave, jsonb_build_array(ind -> 'ATE', ind -> 'MEDATE', ind -> 'PATM', ind -> 'PATE',
                                                 raw -> 'transp', raw -> 'esc_at', raw -> 'mun', raw -> 'est')) AS dados,
       now() AS atualizado_em
FROM analise.mv_censo_anual
WHERE nivel = 'municipio'
GROUP BY ano_censo;

CREATE UNIQUE INDEX idx_censo_anual_municipios ON public.censo_anual_municipios (ano_censo);
COMMENT ON MATERIALIZED VIEW public.censo_anual_municipios IS
  'PNITE — Censo Escolar por ano e município: {código IBGE: [ATE, MEDATE, PATM, PATE, transp, esc_at, mun, est]}. Ex.: /rest/v1/censo_anual_municipios?ano_censo=eq.2024&select=dados';

REVOKE ALL ON public.censo_anual_municipios FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.censo_anual_municipios TO anon, authenticated;

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
                            'analise.mv_censo_anual', 'public.indicadores_censo_anual',
                            'public.censo_anual_municipios'] LOOP
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
