-- ============================================================================
-- PNITE — 0030: Participação oficial nas capacitações (planilha do CECATE-CO)
-- ----------------------------------------------------------------------------
-- A planilha "2024-2026 - Participantes das Capacitações" (mantida pela equipe no
-- Google Planilhas) passa a ser a fonte oficial de PARTICIPAÇÃO e PRESENTES por
-- município e capacitação. Convites (convocações), inscrições e avaliações
-- continuam em capacitacao.municipio_capacitacao e demais tabelas (0012).
--
-- Somente AGREGADOS são gravados: código IBGE, capacitação, participou e contagens
-- de presentes por cargo. Nome, CPF, e-mail e telefone da planilha são usados
-- apenas em memória (para não contar a mesma pessoa duas vezes) e nunca saem do
-- computador. Carga: scripts/importar_capacitacao_oficial.py (AGENTS.md §45.1).
--
-- Sem chave estrangeira para capacitacao.capacitacoes, para que o TRUNCATE feito
-- por scripts/extrair_capacitacao.py continue funcionando sem CASCADE.
-- A view pública é recriada com o mesmo conteúdo da 0012 e as duas chaves novas.
-- ============================================================================

CREATE TABLE capacitacao.participacao_oficial (
    seq                integer  NOT NULL,
    capacitacao        smallint NOT NULL,
    cod_ibge           char(7)  NOT NULL CHECK (cod_ibge ~ '^[0-9]{7}$'),
    participou         boolean  NOT NULL,                   -- ao menos um "Sim" na planilha
    presentes_total    integer  NOT NULL CHECK (presentes_total >= 0),   -- pessoas distintas com "Sim"
    presentes_gestores integer  NOT NULL CHECK (presentes_gestores >= 0),
    presentes_cacs     integer  NOT NULL CHECK (presentes_cacs >= 0),
    presentes_outros   integer  NOT NULL CHECK (presentes_outros >= 0),
    PRIMARY KEY (capacitacao, cod_ibge)
);
COMMENT ON TABLE capacitacao.participacao_oficial IS
    'Participação oficial por município × capacitação (agregada da planilha oficial do CECATE-CO; sem dados pessoais).';

-- Metadados da última carga (uma linha)
CREATE TABLE capacitacao.participacao_oficial_carga (
    id           boolean PRIMARY KEY DEFAULT true CHECK (id),
    arquivo      text    NOT NULL,
    carregado_em text    NOT NULL,                           -- 'AAAA-MM-DD HH:MM'
    linhas       integer NOT NULL,                           -- linhas lidas da planilha
    fonte        text    NOT NULL
);

DROP MATERIALIZED VIEW public.capacitacao_dados;
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
    'participacao_oficial', jsonb_build_object(
        'colunas', jsonb_build_array('capacitacao', 'cod_ibge', 'participou', 'presentes_total', 'presentes_gestores', 'presentes_cacs', 'presentes_outros'),
        'linhas', (SELECT coalesce(jsonb_agg(jsonb_build_array(capacitacao, cod_ibge, participou, presentes_total, presentes_gestores,
                                                               presentes_cacs, presentes_outros) ORDER BY seq), '[]')
                   FROM capacitacao.participacao_oficial)),
    'participacao_oficial_carga', (SELECT to_jsonb(c) - 'id' FROM capacitacao.participacao_oficial_carga c),
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
