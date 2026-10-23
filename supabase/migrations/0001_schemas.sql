-- ============================================================================
-- PNITE — 0001: schemas e controle de migrações
-- ----------------------------------------------------------------------------
-- Camadas:
--   sete     dados brutos do SETE (privado; contém dados pessoais)
--   censo    microdados do Censo Escolar (privado)
--   ref      tabelas de referência (UF, municípios, cargas, valores legados)
--   analise  views de leitura limpa e agregações municipais (privado)
--   public   somente as views materializadas agregadas, lidas pela API (anon)
-- Os schemas privados não são expostos pelo PostgREST e não têm GRANT para
-- anon/authenticated: só o papel postgres (scripts administrativos) os acessa.
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS pnite_meta;
CREATE SCHEMA IF NOT EXISTS sete;
CREATE SCHEMA IF NOT EXISTS censo;
CREATE SCHEMA IF NOT EXISTS ref;
CREATE SCHEMA IF NOT EXISTS analise;

COMMENT ON SCHEMA sete    IS 'PNITE — dados brutos do SETE (privado: contém dados pessoais).';
COMMENT ON SCHEMA censo   IS 'PNITE — microdados do Censo Escolar (privado).';
COMMENT ON SCHEMA ref     IS 'PNITE — tabelas de referência (UF, municípios, cargas, valores legados).';
COMMENT ON SCHEMA analise IS 'PNITE — views de leitura limpa e agregações municipais (privado).';

REVOKE ALL ON SCHEMA pnite_meta, sete, censo, ref, analise FROM PUBLIC, anon, authenticated;

CREATE TABLE IF NOT EXISTS pnite_meta.migracoes (
    arquivo     text PRIMARY KEY,
    aplicada_em timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS pnite_meta.cargas_log (
    id          bigserial PRIMARY KEY,
    tabela      text        NOT NULL,
    ano_carga   smallint    NOT NULL,
    filtro_uf   text,
    linhas      bigint      NOT NULL,
    invalidos   bigint      NOT NULL DEFAULT 0,
    concluida_em timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE pnite_meta.cargas_log IS 'Histórico das cargas (linhas enviadas e valores inválidos convertidos em NULL).';
