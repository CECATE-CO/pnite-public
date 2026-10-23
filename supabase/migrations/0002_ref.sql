-- ============================================================================
-- PNITE — 0002: tabelas de referência
-- ============================================================================

-- Unidades da Federação e regiões (chaves iguais às usadas no front-end: 'go', 'centro-oeste')
CREATE TABLE IF NOT EXISTS ref.uf (
    sigla         text PRIMARY KEY,          -- minúscula: 'go'
    nome          text     NOT NULL,
    codigo_ibge   smallint NOT NULL UNIQUE,
    regiao        text     NOT NULL,         -- 'norte' | 'nordeste' | 'sudeste' | 'sul' | 'centro-oeste'
    regiao_label  text     NOT NULL
);

INSERT INTO ref.uf (sigla, nome, codigo_ibge, regiao, regiao_label) VALUES
  ('ro','Rondônia',11,'norte','Norte'), ('ac','Acre',12,'norte','Norte'), ('am','Amazonas',13,'norte','Norte'),
  ('rr','Roraima',14,'norte','Norte'), ('pa','Pará',15,'norte','Norte'), ('ap','Amapá',16,'norte','Norte'),
  ('to','Tocantins',17,'norte','Norte'),
  ('ma','Maranhão',21,'nordeste','Nordeste'), ('pi','Piauí',22,'nordeste','Nordeste'), ('ce','Ceará',23,'nordeste','Nordeste'),
  ('rn','Rio Grande do Norte',24,'nordeste','Nordeste'), ('pb','Paraíba',25,'nordeste','Nordeste'),
  ('pe','Pernambuco',26,'nordeste','Nordeste'), ('al','Alagoas',27,'nordeste','Nordeste'), ('se','Sergipe',28,'nordeste','Nordeste'),
  ('ba','Bahia',29,'nordeste','Nordeste'),
  ('mg','Minas Gerais',31,'sudeste','Sudeste'), ('es','Espírito Santo',32,'sudeste','Sudeste'),
  ('rj','Rio de Janeiro',33,'sudeste','Sudeste'), ('sp','São Paulo',35,'sudeste','Sudeste'),
  ('pr','Paraná',41,'sul','Sul'), ('sc','Santa Catarina',42,'sul','Sul'), ('rs','Rio Grande do Sul',43,'sul','Sul'),
  ('ms','Mato Grosso do Sul',50,'centro-oeste','Centro-Oeste'), ('mt','Mato Grosso',51,'centro-oeste','Centro-Oeste'),
  ('go','Goiás',52,'centro-oeste','Centro-Oeste'), ('df','Distrito Federal',53,'centro-oeste','Centro-Oeste')
ON CONFLICT (sigla) DO NOTHING;

-- Municípios (fonte: data/Transporte Escolar/Lista de Municipios IBGE.csv)
CREATE TABLE IF NOT EXISTS ref.municipios (
    codigo_ibge  integer PRIMARY KEY,        -- 7 dígitos
    nome         text    NOT NULL,
    uf           text    NOT NULL REFERENCES ref.uf (sigla),
    codigo_rgi   integer,                    -- região geográfica intermediária
    nome_rgi     text,
    codigo_rgim  integer,                    -- região geográfica imediata
    nome_rgim    text
);
CREATE INDEX IF NOT EXISTS idx_ref_municipios_uf ON ref.municipios (uf);

-- Pareamento entre a carga do SETE e a do Censo usada no cruzamento (PCSC)
CREATE TABLE IF NOT EXISTS ref.cargas (
    ano_carga_sete   smallint PRIMARY KEY,
    ano_carga_censo  smallint NOT NULL,
    descricao        text
);
INSERT INTO ref.cargas VALUES (2026, 2025, 'SETE extraído em 2026 × Censo Escolar 2025')
ON CONFLICT (ano_carga_sete) DO NOTHING;

-- RAW_DATA de referência por escopo (nacional, regiões e UFs): valores que não saem dos
-- CSVs brutos — legado embutido no PNITE.html (_FALLBACK_RAW_DATA) sobreposto pelos
-- totais das planilhas "consolidado XX - script_XX_*.xlsx". Os campos calculados a
-- partir dos dados brutos sobrescrevem estes valores em public.indicadores.
CREATE TABLE IF NOT EXISTS ref.raw_referencia (
    ano_carga  smallint NOT NULL,
    chave      text     NOT NULL,            -- 'nacional' | região | sigla UF
    dados      jsonb    NOT NULL,
    PRIMARY KEY (ano_carga, chave)
);

-- Detalhamento por script das planilhas "consolidado *.xlsx" (detalhes_scripts do pacote)
CREATE TABLE IF NOT EXISTS ref.detalhes_scripts (
    ano_carga  smallint NOT NULL,
    chave      text     NOT NULL,            -- 'nacional' | sigla UF
    script     text     NOT NULL,            -- ex.: 'script_01_alunos'
    dados      jsonb    NOT NULL,
    PRIMARY KEY (ano_carga, chave, script)
);
