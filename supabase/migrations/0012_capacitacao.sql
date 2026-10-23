-- ============================================================================
-- PNITE — 0012: Capacitações do Transporte Escolar no banco
-- ----------------------------------------------------------------------------
-- Substitui o arquivo data/Capacitação/pnite_capacitacao_dados.js: as tabelas
-- consolidadas por scripts/extrair_capacitacao.py (mesmas colunas do antigo
-- schema_capacitacao.sql) ficam no schema privado `capacitacao`, e a interface
-- lê a view materializada pública `public.capacitacao_dados`, que devolve um
-- único objeto JSON no mesmo formato {colunas, linhas} do arquivo JS.
--
-- `seq` preserva a ordem de geração das linhas (a interface depende dela, ex.:
-- ordem das perguntas e dos respondentes). Não há dados pessoais: presença e
-- inscrição são contagens por município; respondentes têm ID sequencial.
--
-- `municipios_mapa` lista nome e UF de todos os municípios do Centro-Oeste
-- (ref.municipios) para o mapa da capacitação, cuja malha vem da API do IBGE.
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS capacitacao;
COMMENT ON SCHEMA capacitacao IS 'PNITE — Capacitações do Transporte Escolar (privado; lido pela view public.capacitacao_dados).';
REVOKE ALL ON SCHEMA capacitacao FROM PUBLIC, anon, authenticated;

-- Metadados da extração (uma linha)
CREATE TABLE capacitacao.metadados (
    id                      boolean PRIMARY KEY DEFAULT true CHECK (id),
    versao_esquema          smallint    NOT NULL,
    gerado_em               text        NOT NULL,           -- 'AAAA-MM-DD HH:MM' da extração
    fontes                  jsonb       NOT NULL,
    presentes_sem_municipio jsonb       NOT NULL            -- {capacitação: presentes sem município identificado}
);

-- Municípios envolvidos (convidados, participantes, polos e avaliações)
CREATE TABLE capacitacao.municipios (
    seq      integer      NOT NULL,
    cod_ibge char(7)      PRIMARY KEY,
    nome     text         NOT NULL,
    uf       char(2)      NOT NULL,
    lat      numeric(8,4),                                  -- centróide da malha municipal
    lon      numeric(8,4)
);

-- Uma linha por capacitação (XCTE)
CREATE TABLE capacitacao.capacitacoes (
    seq           integer  NOT NULL,
    numero        smallint PRIMARY KEY,
    polo          text     NOT NULL,
    polo_cod_ibge char(7)  NOT NULL REFERENCES capacitacao.municipios (cod_ibge),
    uf            char(2)  NOT NULL,
    data_inicio   date     NOT NULL,
    data_fim      date     NOT NULL,
    local         text,
    fonte         text     NOT NULL                         -- 'arquivos_brutos' | 'legado_power_bi'
);

-- Fato município × capacitação: convite, inscrições e presença
CREATE TABLE capacitacao.municipio_capacitacao (
    seq                integer  NOT NULL,
    capacitacao        smallint NOT NULL REFERENCES capacitacao.capacitacoes (numero),
    cod_ibge           char(7)  NOT NULL REFERENCES capacitacao.municipios (cod_ibge),
    convidado          smallint NOT NULL CHECK (convidado IN (0, 1)),
    inscritos_total    integer,                             -- NULL sem formulário (capacitações 1 a 4)
    inscritos_gestores integer,
    inscritos_cacs     integer,
    inscritos_outros   integer,
    presentes_total    integer  NOT NULL,
    presentes_gestores integer  NOT NULL,
    presentes_cacs     integer  NOT NULL,
    presentes_outros   integer  NOT NULL,
    distancia_polo_km  numeric(7,1),                        -- linha reta entre centróides
    PRIMARY KEY (capacitacao, cod_ibge)
);

-- Avaliação das capacitações 1 a 5 (Ótimo/Bom/Regular/Ruim e Sim/Em parte/Não)
CREATE TABLE capacitacao.aval15_perguntas (
    seq         integer  NOT NULL,
    id_pergunta smallint PRIMARY KEY,
    bloco       text     NOT NULL,
    subgrupo    text     NOT NULL,
    pergunta    text     NOT NULL
);

CREATE TABLE capacitacao.aval15_respondentes (
    seq         integer  NOT NULL,
    id_resposta text     PRIMARY KEY,
    capacitacao smallint NOT NULL REFERENCES capacitacao.capacitacoes (numero),
    publico     text     NOT NULL                           -- Gestores | CACS | Outros
);

CREATE TABLE capacitacao.aval15_respostas (
    seq         integer  NOT NULL,
    id_resposta text     NOT NULL REFERENCES capacitacao.aval15_respondentes (id_resposta),
    id_pergunta smallint NOT NULL REFERENCES capacitacao.aval15_perguntas (id_pergunta),
    resposta    text     NOT NULL
);

-- Avaliação das capacitações 6 a 16 (notas de 1 a 5)
CREATE TABLE capacitacao.aval616_perguntas (
    seq      integer  NOT NULL,
    ordem    smallint PRIMARY KEY,
    pergunta text     NOT NULL
);

CREATE TABLE capacitacao.aval616_respondentes (
    seq                integer  NOT NULL,
    id_resposta        text     PRIMARY KEY,
    capacitacao        smallint NOT NULL REFERENCES capacitacao.capacitacoes (numero),
    cod_ibge           char(7)  REFERENCES capacitacao.municipios (cod_ibge),
    municipio          text,
    cargo              text     NOT NULL,                   -- Gestores | CACS | Outros
    instituicao        text,
    aspectos_positivos text,
    aspectos_melhorar  text,
    temas_futuros      text,
    comentarios        text
);

CREATE TABLE capacitacao.aval616_notas (
    seq         integer  NOT NULL,
    id_resposta text     NOT NULL REFERENCES capacitacao.aval616_respondentes (id_resposta),
    ordem       smallint NOT NULL REFERENCES capacitacao.aval616_perguntas (ordem),
    nota        smallint NOT NULL CHECK (nota BETWEEN 1 AND 5),
    PRIMARY KEY (id_resposta, ordem)
);

CREATE TABLE capacitacao.aval616_canais (
    seq         integer NOT NULL,
    id_resposta text    NOT NULL REFERENCES capacitacao.aval616_respondentes (id_resposta),
    canal       text    NOT NULL
);

-- ----------------------------------------------------------------------------
-- Interface pública: um objeto JSON com todas as tabelas, no formato do antigo
-- pnite_capacitacao_dados.js. Atualizada por scripts/extrair_capacitacao.py.
-- ----------------------------------------------------------------------------
CREATE MATERIALIZED VIEW public.capacitacao_dados AS
SELECT jsonb_build_object(
    'versao_esquema', m.versao_esquema,
    'gerado_em', m.gerado_em,
    'fontes', m.fontes,
    'presentes_sem_municipio', m.presentes_sem_municipio,
    'capacitacoes', jsonb_build_object(
        'colunas', jsonb_build_array('numero', 'polo', 'polo_cod_ibge', 'uf', 'data_inicio', 'data_fim', 'local', 'fonte'),
        'linhas', (SELECT coalesce(jsonb_agg(jsonb_build_array(numero, polo, polo_cod_ibge, uf, data_inicio, data_fim, local, fonte) ORDER BY seq), '[]')
                   FROM capacitacao.capacitacoes)),
    'municipios', jsonb_build_object(
        'colunas', jsonb_build_array('cod_ibge', 'nome', 'uf', 'lat', 'lon'),
        'linhas', (SELECT coalesce(jsonb_agg(jsonb_build_array(cod_ibge, nome, uf, lat, lon) ORDER BY seq), '[]')
                   FROM capacitacao.municipios)),
    'municipio_capacitacao', jsonb_build_object(
        'colunas', jsonb_build_array('capacitacao', 'cod_ibge', 'convidado', 'inscritos_total', 'inscritos_gestores', 'inscritos_cacs',
                                     'inscritos_outros', 'presentes_total', 'presentes_gestores', 'presentes_cacs', 'presentes_outros', 'distancia_polo_km'),
        'linhas', (SELECT coalesce(jsonb_agg(jsonb_build_array(capacitacao, cod_ibge, convidado, inscritos_total, inscritos_gestores, inscritos_cacs,
                                                               inscritos_outros, presentes_total, presentes_gestores, presentes_cacs, presentes_outros,
                                                               distancia_polo_km) ORDER BY seq), '[]')
                   FROM capacitacao.municipio_capacitacao)),
    'aval15_perguntas', jsonb_build_object(
        'colunas', jsonb_build_array('id_pergunta', 'bloco', 'subgrupo', 'pergunta'),
        'linhas', (SELECT coalesce(jsonb_agg(jsonb_build_array(id_pergunta, bloco, subgrupo, pergunta) ORDER BY seq), '[]')
                   FROM capacitacao.aval15_perguntas)),
    'aval15_respondentes', jsonb_build_object(
        'colunas', jsonb_build_array('id_resposta', 'capacitacao', 'publico'),
        'linhas', (SELECT coalesce(jsonb_agg(jsonb_build_array(id_resposta, capacitacao, publico) ORDER BY seq), '[]')
                   FROM capacitacao.aval15_respondentes)),
    'aval15_respostas', jsonb_build_object(
        'colunas', jsonb_build_array('id_resposta', 'id_pergunta', 'resposta'),
        'linhas', (SELECT coalesce(jsonb_agg(jsonb_build_array(id_resposta, id_pergunta, resposta) ORDER BY seq), '[]')
                   FROM capacitacao.aval15_respostas)),
    'aval616_perguntas', jsonb_build_object(
        'colunas', jsonb_build_array('ordem', 'pergunta'),
        'linhas', (SELECT coalesce(jsonb_agg(jsonb_build_array(ordem, pergunta) ORDER BY seq), '[]')
                   FROM capacitacao.aval616_perguntas)),
    'aval616_respondentes', jsonb_build_object(
        'colunas', jsonb_build_array('id_resposta', 'capacitacao', 'cod_ibge', 'municipio', 'cargo', 'instituicao',
                                     'aspectos_positivos', 'aspectos_melhorar', 'temas_futuros', 'comentarios'),
        'linhas', (SELECT coalesce(jsonb_agg(jsonb_build_array(id_resposta, capacitacao, cod_ibge, municipio, cargo, instituicao,
                                                               aspectos_positivos, aspectos_melhorar, temas_futuros, comentarios) ORDER BY seq), '[]')
                   FROM capacitacao.aval616_respondentes)),
    'aval616_notas', jsonb_build_object(
        'colunas', jsonb_build_array('id_resposta', 'ordem', 'nota'),
        'linhas', (SELECT coalesce(jsonb_agg(jsonb_build_array(id_resposta, ordem, nota) ORDER BY seq), '[]')
                   FROM capacitacao.aval616_notas)),
    'aval616_canais', jsonb_build_object(
        'colunas', jsonb_build_array('id_resposta', 'canal'),
        'linhas', (SELECT coalesce(jsonb_agg(jsonb_build_array(id_resposta, canal) ORDER BY seq), '[]')
                   FROM capacitacao.aval616_canais)),
    'municipios_mapa', jsonb_build_object(
        'colunas', jsonb_build_array('cod_ibge', 'nome', 'uf'),
        'linhas', (SELECT coalesce(jsonb_agg(jsonb_build_array(codigo_ibge::text, nome, upper(uf)) ORDER BY codigo_ibge), '[]')
                   FROM ref.municipios WHERE lower(uf) IN ('go', 'mt', 'ms', 'df')))
) AS dados
FROM capacitacao.metadados m;

COMMENT ON MATERIALIZED VIEW public.capacitacao_dados IS
    'Capacitações do Transporte Escolar em um objeto JSON {tabela: {colunas, linhas}} (lido pela interface PNITE).';
REVOKE ALL ON public.capacitacao_dados FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.capacitacao_dados TO anon, authenticated;
