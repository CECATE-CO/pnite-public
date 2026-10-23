-- ============================================================================
-- PNITE — 0009: traçado das rotas para o mapa (PostGIS)
-- ----------------------------------------------------------------------------
-- O shape das rotas no SETE é um GeoJSON FeatureCollection em Web Mercator
-- (EPSG:3857, coordenadas x/y/z em metros). O volume bruto é inviável para o
-- navegador (ex.: 237 MB em um único município de GO), então o banco:
--   1) extrai as LineStrings (descarta pontos e a coordenada z);
--   2) simplifica em metros, ainda em 3857 (tolerância de 10 m);
--   3) converte para longitude/latitude (EPSG:4326), a mesma referência das malhas IBGE do mapa;
--   4) grava GeoJSON com 5 casas decimais (~1 m).
-- public.rotas_tracado expõe apenas traçado e atributos operacionais da rota
-- (sem alunos, motoristas ou veículos) e é lida por município pela API.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA extensions;

-- Traçado simplificado em EPSG:4326 (GeoJSON MultiLineString); NULL se o shape for inválido
CREATE OR REPLACE FUNCTION analise.tracado_simplificado(shape text, tolerancia_m double precision DEFAULT 10)
RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE
SET search_path = extensions, public, pg_temp AS $$
DECLARE
  linhas geometry;
BEGIN
  SELECT ST_Collect(ST_Force2D(ST_SetSRID(ST_GeomFromGeoJSON(f -> 'geometry'), 3857)))
    INTO linhas
  FROM jsonb_array_elements(shape::jsonb -> 'features') AS f
  WHERE f -> 'geometry' ->> 'type' IN ('LineString', 'MultiLineString');

  IF linhas IS NULL OR ST_IsEmpty(linhas) THEN
    RETURN NULL;
  END IF;

  RETURN ST_AsGeoJSON(
           ST_Transform(ST_SimplifyPreserveTopology(ST_RemoveRepeatedPoints(ST_Multi(ST_LineMerge(linhas))), tolerancia_m), 4326),
           5)::jsonb;
EXCEPTION WHEN OTHERS THEN
  RETURN NULL;   -- shape malformado não interrompe a atualização da view
END
$$;
COMMENT ON FUNCTION analise.tracado_simplificado(text, double precision) IS
  'GeoJSON do SETE (EPSG:3857) -> MultiLineString simplificada em EPSG:4326 (5 casas decimais).';

CREATE MATERIALIZED VIEW public.rotas_tracado AS
SELECT r.ano_carga,
       r.codigo_cidade,
       lower(r.uf) AS uf,
       r.id_rota,
       r.nome,
       r.tipo,
       CASE r.tipo WHEN 1 THEN 'Rodoviário' WHEN 2 THEN 'Aquaviário' WHEN 3 THEN 'Mista' END AS tipo_label,
       r.km,
       r.tempo,
       analise.tracado_simplificado(s.shape) AS geometria
FROM sete.rota_shape s
JOIN sete.rotas r USING (ano_carga, codigo_cidade, id_rota)
WITH NO DATA;

CREATE INDEX idx_rotas_tracado_cidade ON public.rotas_tracado (ano_carga, codigo_cidade);
COMMENT ON MATERIALIZED VIEW public.rotas_tracado IS
  'PNITE — traçado simplificado das rotas (EPSG:4326). Ex.: /rest/v1/rotas_tracado?ano_carga=eq.2026&codigo_cidade=eq.5212501';

REVOKE ALL ON public.rotas_tracado FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.rotas_tracado TO anon, authenticated;

-- Inclui o traçado na atualização em cascata
CREATE OR REPLACE FUNCTION pnite_meta.atualizar_indicadores() RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  mv text;
BEGIN
  FOREACH mv IN ARRAY ARRAY['analise.mv_base_municipio', 'analise.mv_tempo_rotas',
                            'public.indicadores_municipio', 'public.indicadores_estado',
                            'public.indicadores_regiao', 'public.indicadores_nacional',
                            'public.rotas_tracado'] LOOP
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
