-- ============================================================================
-- PNITE — 0010: traçado simplificado calculado na carga
-- ----------------------------------------------------------------------------
-- Converter e simplificar ~1,9 GB de GeoJSON de uma vez (REFRESH de
-- public.rotas_tracado) leva ~75 s e excede o tempo máximo das requisições
-- HTTP do gateway (~60 s), única via de acesso ao banco. A conversão passa a
-- ser feita por linha, no momento da inserção (gatilho em sete.rota_shape),
-- distribuída pelos lotes da carga; a view materializada vira uma junção simples.
-- ============================================================================

ALTER TABLE sete.rota_shape ADD COLUMN IF NOT EXISTS geometria jsonb;
COMMENT ON COLUMN sete.rota_shape.geometria IS
  'Traçado simplificado em EPSG:4326 (GeoJSON), calculado na inserção por analise.tracado_simplificado(shape).';

CREATE OR REPLACE FUNCTION sete.tg_rota_shape_geometria() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.geometria := analise.tracado_simplificado(NEW.shape);
  RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS tg_rota_shape_geometria ON sete.rota_shape;
CREATE TRIGGER tg_rota_shape_geometria
  BEFORE INSERT OR UPDATE OF shape ON sete.rota_shape
  FOR EACH ROW EXECUTE FUNCTION sete.tg_rota_shape_geometria();

DROP MATERIALIZED VIEW IF EXISTS public.rotas_tracado;
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
       s.geometria
FROM sete.rota_shape s
JOIN sete.rotas r USING (ano_carga, codigo_cidade, id_rota)
WITH NO DATA;

CREATE INDEX idx_rotas_tracado_cidade ON public.rotas_tracado (ano_carga, codigo_cidade);
COMMENT ON MATERIALIZED VIEW public.rotas_tracado IS
  'PNITE — traçado simplificado das rotas (EPSG:4326). Ex.: /rest/v1/rotas_tracado?ano_carga=eq.2026&codigo_cidade=eq.5212501';

REVOKE ALL ON public.rotas_tracado FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.rotas_tracado TO anon, authenticated;
