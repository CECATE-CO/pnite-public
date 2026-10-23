-- ============================================================================
-- PNITE — 0007: área de trânsito da carga via API
-- ----------------------------------------------------------------------------
-- O postgres-meta recusa requisições acima de ~2 MB. Valores maiores (GeoJSON de
-- rotas extensas) sobem em partes e são remontados com string_agg no INSERT final.
-- ============================================================================

CREATE TABLE IF NOT EXISTS pnite_meta.partes_texto (
    token  text    NOT NULL,
    parte  integer NOT NULL,
    texto  text    NOT NULL,
    PRIMARY KEY (token, parte)
);
