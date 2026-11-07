-- ============================================================================
-- PNITE — 0018: Catálogo editorial de indicadores, base Caminho da Escola,
--               snapshots dos painéis FNDE, qualidade e auditoria
-- ----------------------------------------------------------------------------
-- Camadas (roteiro de migração dos painéis FNDE, §3 e §6):
--   1. originais privados e imutáveis: gestao.dataset_versoes (hash SHA-256)
--   2. staging/canônico: gestao.ce_contratacao_itens (uma linha por linha do
--      arquivo, com número da linha, hash e flags de qualidade)
--   3. snapshots documentais: gestao.snapshots_paineis (abas transcritas;
--      NÃO são fatos recalculáveis)
--   4. catálogo publicável: catalogo.indicadores / indicador_versoes /
--      publicacoes, com trilha catalogo.auditoria (append-only)
--
-- Schemas privados (sem GRANT a anon/authenticated). O público lê apenas pelas
-- funções public.pnite_* abaixo, que só devolvem itens com publicação ativa.
-- As funções administrativas exigem administrador ativo (acesso.exigir_admin),
-- conferido no banco a cada chamada — não depende de localStorage nem de CSS.
-- Cálculo só por operações e campos de allowlist: nenhum SQL vindo do cliente.
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS gestao;
CREATE SCHEMA IF NOT EXISTS catalogo;
COMMENT ON SCHEMA gestao IS 'PNITE — Bases de gestão (Caminho da Escola) e snapshots dos painéis FNDE (privado).';
COMMENT ON SCHEMA catalogo IS 'PNITE — Catálogo editorial de indicadores, publicações e auditoria (privado).';
REVOKE ALL ON SCHEMA gestao, catalogo FROM PUBLIC, anon, authenticated;

-- ----------------------------------------------------------------------------
-- Proteção do último administrador (concorrência): serializa alterações de
-- papel/situação e recusa a que deixaria a PNITE sem administrador ativo.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION acesso.proteger_ultimo_admin()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    IF OLD.papel = 'admin' AND OLD.ativo
       AND (TG_OP = 'DELETE' OR NEW.papel <> 'admin' OR NOT NEW.ativo) THEN
        PERFORM pg_advisory_xact_lock(hashtext('pnite_admins'));
        IF NOT EXISTS (SELECT 1 FROM acesso.autorizacoes a
                       WHERE a.papel = 'admin' AND a.ativo AND a.email <> OLD.email) THEN
            RAISE EXCEPTION 'A PNITE precisa de pelo menos um administrador ativo.' USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN COALESCE(NEW, OLD);
END $$;
DROP TRIGGER IF EXISTS pnite_ultimo_admin ON acesso.autorizacoes;
CREATE TRIGGER pnite_ultimo_admin BEFORE UPDATE OR DELETE ON acesso.autorizacoes
    FOR EACH ROW EXECUTE FUNCTION acesso.proteger_ultimo_admin();

-- ----------------------------------------------------------------------------
-- Fontes e versões de dados
-- ----------------------------------------------------------------------------
CREATE TABLE gestao.fontes (
    codigo        text PRIMARY KEY,
    descricao     text NOT NULL,
    dono          text,
    classificacao text NOT NULL DEFAULT 'interna' CHECK (classificacao IN ('publica', 'interna', 'restrita')),
    formato       text,
    observacao    text
);

CREATE TABLE gestao.dataset_versoes (
    id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fonte             text NOT NULL REFERENCES gestao.fontes (codigo),
    arquivo           text NOT NULL,
    sha256            text NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
    bytes             bigint,
    periodo_inicio    date,
    periodo_fim       date,
    data_captura      date,
    status            text NOT NULL DEFAULT 'carregando'
                      CHECK (status IN ('carregando', 'validada', 'ativa', 'inativa', 'rejeitada')),
    linhas            integer,
    linhas_com_alerta integer,
    soma_quantidade   bigint,
    soma_valor_total  numeric(20, 2),
    importador        text,
    responsavel       text,
    recebido_em       timestamptz NOT NULL DEFAULT now(),
    ativada_em        timestamptz,
    ativada_por       text,
    UNIQUE (fonte, sha256)
);
CREATE UNIQUE INDEX dataset_versoes_uma_ativa ON gestao.dataset_versoes (fonte) WHERE status = 'ativa';
COMMENT ON TABLE gestao.dataset_versoes IS 'Cada arquivo recebido (hash SHA-256 único por fonte: a mesma fotografia não é carregada duas vezes).';

CREATE TABLE gestao.ce_contratacao_itens (
    id                         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    dataset_versao_id          bigint  NOT NULL REFERENCES gestao.dataset_versoes (id),
    source_row_number          integer NOT NULL,
    row_hash                   text    NOT NULL,
    ano_contratacao            smallint,
    codigo_territorial_origem  text,
    termo_compromisso          text,
    numero_processo            text,
    regiao_origem              text,
    uf_origem                  text,
    municipio_nome_origem      text,
    esfera_administrativa      text,
    entidade_nome              text,
    tipo_veiculo_origem        text,
    quantidade                 integer,
    valor_unitario             numeric(16, 2),
    valor_total                numeric(18, 2),
    forma_pagamento_origem     text,
    resultado_primario_origem  text,
    data_contratacao_origem    date,
    fornecedor_nome            text,
    pregao_origem              text,
    flag_termo_marcador        boolean NOT NULL DEFAULT false,
    flag_processo_marcador     boolean NOT NULL DEFAULT false,
    flag_unitario_ausente      boolean NOT NULL DEFAULT false,
    flag_produto_divergente    boolean NOT NULL DEFAULT false,
    importado_em               timestamptz NOT NULL DEFAULT now(),
    UNIQUE (dataset_versao_id, source_row_number)
);
CREATE INDEX ce_itens_dataset ON gestao.ce_contratacao_itens (dataset_versao_id, ano_contratacao, uf_origem);
COMMENT ON TABLE gestao.ce_contratacao_itens IS 'Fato de itens de contratação do Caminho da Escola (uma linha por linha do arquivo; ID vale dentro da versão).';
COMMENT ON COLUMN gestao.ce_contratacao_itens.termo_compromisso IS 'NULL quando a fonte traz o marcador textual ''- (flag_termo_marcador = true).';
COMMENT ON COLUMN gestao.ce_contratacao_itens.quantidade IS 'Quantidade contratada do item (não comprova entrega nem operação).';

CREATE TABLE gestao.snapshots_paineis (
    id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    dataset_versao_id bigint NOT NULL REFERENCES gestao.dataset_versoes (id),
    painel        text NOT NULL CHECK (painel IN ('sete', 'caminho', 'documentacao')),
    aba           text NOT NULL,
    ordem         integer NOT NULL,
    pagina        text,
    indicador     text,
    categoria     text,
    valor         numeric,
    unidade       text,
    observacao    text,
    linha         jsonb NOT NULL,
    source_type   text NOT NULL DEFAULT 'panel_snapshot'
);
COMMENT ON TABLE gestao.snapshots_paineis IS 'Abas transcritas dos painéis Power BI (fotografia com data de captura). Não são microdados nem fonte recalculável.';

CREATE TABLE gestao.pendencias_qualidade (
    id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    dataset_versao_id bigint REFERENCES gestao.dataset_versoes (id),
    painel        text,
    verificacao   text NOT NULL,
    valor         numeric,
    origem        text,
    severidade    text NOT NULL DEFAULT 'alerta' CHECK (severidade IN ('info', 'alerta', 'bloqueio')),
    situacao      text NOT NULL DEFAULT 'aberta' CHECK (situacao IN ('aberta', 'aceita', 'resolvida')),
    decisao       text,
    decidido_por  text,
    decidido_em   timestamptz,
    criado_em     timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE gestao.reconciliacoes (
    id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    medida        text NOT NULL,
    valor_base    numeric,
    valor_painel  numeric,
    data_painel   date,
    situacao      text NOT NULL DEFAULT 'nao_reconciliada'
                  CHECK (situacao IN ('nao_reconciliada', 'reconciliada', 'divergencia_aceita')),
    nota          text
);

INSERT INTO gestao.fontes (codigo, descricao, dono, classificacao, formato, observacao) VALUES
 ('caminho_contratacoes', 'Contratações do Programa Caminho da Escola (download do painel FNDE)', 'FNDE/MEC — DIRAE', 'publica', 'CSV UTF-8 com BOM',
  'Contém contratações; não contém pagamentos, entrega ou operação.'),
 ('paineis_fnde_snapshot', 'Extração dos dois painéis Power BI (SETE e Caminho da Escola)', 'FNDE/MEC — DIRAE/DIRTI', 'publica', 'XLSX (8 abas)',
  'Fotografia dos visuais; não substitui as bases operacionais SETE e SIGEF.'),
 ('sigef_pagamentos', 'Pagamentos do Caminho da Escola (Databricks — SIGEF)', 'FNDE/MEC', 'interna', NULL,
  'Pendente: base não fornecida. Valores pagos não podem ser calculados.');

-- ----------------------------------------------------------------------------
-- Catálogo editorial
-- ----------------------------------------------------------------------------
CREATE TABLE catalogo.indicadores (
    id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo     text NOT NULL UNIQUE CHECK (codigo ~ '^[A-Z][A-Z0-9_]{1,40}$'),
    slug       text NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9][a-z0-9-]{1,80}$'),
    tipo       text NOT NULL DEFAULT 'indicador' CHECK (tipo IN ('indicador', 'visual')),
    frente     text NOT NULL CHECK (frente IN ('transporte', 'capacitacao', 'gestao')),
    modulo     text NOT NULL,
    categoria  text,
    ordem      integer NOT NULL DEFAULT 100,
    criado_em  timestamptz NOT NULL DEFAULT now(),
    criado_por text
);

CREATE TABLE catalogo.indicador_versoes (
    id                    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    indicador_id          bigint NOT NULL REFERENCES catalogo.indicadores (id),
    versao                integer NOT NULL,
    titulo                text NOT NULL CHECK (length(btrim(titulo)) BETWEEN 3 AND 200),
    descricao             text,
    objetivo              text,
    unidade               text,
    casas_decimais        smallint NOT NULL DEFAULT 0 CHECK (casas_decimais BETWEEN 0 AND 4),
    visual                text NOT NULL DEFAULT 'cartao' CHECK (visual IN ('cartao', 'barras', 'colunas', 'tabela', 'mapa', 'pagina')),
    niveis                text[] NOT NULL DEFAULT ARRAY['nacional']::text[],
    dimensoes             text[] NOT NULL DEFAULT '{}'::text[],
    formula_texto         text,
    calculo               jsonb,
    fonte                 text REFERENCES gestao.fontes (codigo),
    periodo_referencia    text,
    regra_nulos           text,
    sentido               text NOT NULL DEFAULT 'neutro' CHECK (sentido IN ('maior_melhor', 'menor_melhor', 'neutro')),
    situacao_metodologica text NOT NULL DEFAULT 'em_construcao'
                          CHECK (situacao_metodologica IN ('validado', 'em_construcao', 'pendente_fonte')),
    estado_editorial      text NOT NULL DEFAULT 'rascunho'
                          CHECK (estado_editorial IN ('rascunho', 'em_revisao', 'aprovado', 'publicado', 'suspenso', 'arquivado')),
    responsavel           text,
    nota                  text,
    lock_version          integer NOT NULL DEFAULT 1,
    criado_por            text,
    criado_em             timestamptz NOT NULL DEFAULT now(),
    atualizado_em         timestamptz NOT NULL DEFAULT now(),
    aprovado_por          text,
    aprovado_em           timestamptz,
    UNIQUE (indicador_id, versao)
);

CREATE TABLE catalogo.publicacoes (
    id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    indicador_id      bigint NOT NULL REFERENCES catalogo.indicadores (id),
    versao_id         bigint NOT NULL REFERENCES catalogo.indicador_versoes (id),
    dataset_versao_id bigint REFERENCES gestao.dataset_versoes (id),
    somente_ficha     boolean NOT NULL DEFAULT false,
    ativa             boolean NOT NULL DEFAULT true,
    inicio            timestamptz NOT NULL DEFAULT now(),
    fim               timestamptz,
    publicado_por     text NOT NULL,
    justificativa     text NOT NULL,
    encerrado_por     text
);
CREATE UNIQUE INDEX publicacoes_uma_ativa ON catalogo.publicacoes (indicador_id) WHERE ativa;
COMMENT ON TABLE catalogo.publicacoes IS 'Releases: versão do indicador + versão de dados congelada. Uma ativa por indicador.';

CREATE TABLE catalogo.auditoria (
    id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    em             timestamptz NOT NULL DEFAULT now(),
    ator           text NOT NULL,
    operacao       text NOT NULL,
    entidade       text NOT NULL,
    entidade_id    text,
    antes          jsonb,
    depois         jsonb,
    justificativa  text,
    correlation_id uuid NOT NULL DEFAULT gen_random_uuid()
);
CREATE INDEX auditoria_em ON catalogo.auditoria (em DESC);

CREATE OR REPLACE FUNCTION catalogo.auditoria_imutavel()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'A trilha de auditoria é somente de inclusão.' USING ERRCODE = '42501';
END $$;
CREATE TRIGGER auditoria_sem_alteracao BEFORE UPDATE OR DELETE ON catalogo.auditoria
    FOR EACH ROW EXECUTE FUNCTION catalogo.auditoria_imutavel();
CREATE TRIGGER auditoria_sem_truncate BEFORE TRUNCATE ON catalogo.auditoria
    FOR EACH STATEMENT EXECUTE FUNCTION catalogo.auditoria_imutavel();

CREATE OR REPLACE FUNCTION catalogo.auditar(p_ator text, p_operacao text, p_entidade text, p_id text,
                                            p_antes jsonb, p_depois jsonb, p_justificativa text)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
    INSERT INTO catalogo.auditoria (ator, operacao, entidade, entidade_id, antes, depois, justificativa)
    VALUES (p_ator, p_operacao, p_entidade, p_id, p_antes, p_depois, p_justificativa);
$$;

-- ----------------------------------------------------------------------------
-- Motor de cálculo (allowlist de operações, campos e filtros)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION catalogo.validar_filtros(p_f jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SET search_path = '' AS $$
DECLARE k text;
BEGIN
    IF p_f IS NULL OR p_f = 'null'::jsonb THEN RETURN '{}'::jsonb; END IF;
    IF jsonb_typeof(p_f) <> 'object' THEN
        RAISE EXCEPTION 'Filtros inválidos.' USING ERRCODE = '22023';
    END IF;
    FOR k IN SELECT jsonb_object_keys(p_f) LOOP
        IF k NOT IN ('ano', 'uf', 'regiao', 'esfera', 'tipo_veiculo', 'forma_pagamento', 'municipio',
                     'resultado_primario', 'fornecedor', 'processo', 'termo', 'pregao') THEN
            RAISE EXCEPTION 'Filtro não permitido: %', k USING ERRCODE = '22023';
        END IF;
        IF jsonb_typeof(p_f -> k) NOT IN ('string', 'number', 'null') THEN
            RAISE EXCEPTION 'Valor inválido para o filtro %', k USING ERRCODE = '22023';
        END IF;
    END LOOP;
    IF p_f ? 'ano' AND p_f ->> 'ano' IS NOT NULL AND p_f ->> 'ano' !~ '^\d{4}$' THEN
        RAISE EXCEPTION 'Ano inválido.' USING ERRCODE = '22023';
    END IF;
    RETURN jsonb_strip_nulls(p_f);
END $$;

CREATE OR REPLACE FUNCTION gestao.ce_itens(p_dataset bigint, p_f jsonb)
RETURNS SETOF gestao.ce_contratacao_itens LANGUAGE sql STABLE SET search_path = '' AS $$
    SELECT i.* FROM gestao.ce_contratacao_itens i
    WHERE i.dataset_versao_id = p_dataset
      AND (p_f ->> 'ano'                IS NULL OR i.ano_contratacao = (p_f ->> 'ano')::smallint)
      AND (p_f ->> 'uf'                 IS NULL OR i.uf_origem = p_f ->> 'uf')
      AND (p_f ->> 'regiao'             IS NULL OR i.regiao_origem = p_f ->> 'regiao')
      AND (p_f ->> 'esfera'             IS NULL OR i.esfera_administrativa = p_f ->> 'esfera')
      AND (p_f ->> 'tipo_veiculo'       IS NULL OR i.tipo_veiculo_origem = p_f ->> 'tipo_veiculo')
      AND (p_f ->> 'forma_pagamento'    IS NULL OR i.forma_pagamento_origem = p_f ->> 'forma_pagamento')
      AND (p_f ->> 'municipio'          IS NULL OR i.codigo_territorial_origem = p_f ->> 'municipio')
      AND (p_f ->> 'resultado_primario' IS NULL OR i.resultado_primario_origem = p_f ->> 'resultado_primario')
      AND (p_f ->> 'fornecedor'         IS NULL OR i.fornecedor_nome = p_f ->> 'fornecedor')
      AND (p_f ->> 'processo'           IS NULL OR i.numero_processo = p_f ->> 'processo')
      AND (p_f ->> 'termo'              IS NULL OR i.termo_compromisso = p_f ->> 'termo')
      AND (p_f ->> 'pregao'             IS NULL OR i.pregao_origem = p_f ->> 'pregao');
$$;

-- Calcula um indicador estruturado. Operações: sum, count, count_distinct, ratio, completude.
CREATE OR REPLACE FUNCTION catalogo.calcular(p_calc jsonb, p_dataset bigint, p_f jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    v_op   text := p_calc ->> 'operacao';
    v_c    text := p_calc ->> 'campo';
    v_num  text := p_calc ->> 'numerador';
    v_den  text := p_calc ->> 'denominador';
    v_f    jsonb := catalogo.validar_filtros(p_f);
    v_n    bigint; v_a numeric; v_b numeric;
BEGIN
    IF p_dataset IS NULL THEN
        RETURN jsonb_build_object('valor', NULL, 'estado', 'sem_dados');
    END IF;
    IF v_op = 'sum' AND v_c IN ('quantidade', 'valor_total') THEN
        SELECT count(*), sum(CASE v_c WHEN 'quantidade' THEN i.quantidade::numeric ELSE i.valor_total END)
          INTO v_n, v_a FROM gestao.ce_itens(p_dataset, v_f) i;
        RETURN jsonb_build_object('valor', v_a, 'n', v_n, 'estado', CASE WHEN v_n = 0 THEN 'sem_dados' ELSE 'ok' END);
    ELSIF v_op = 'count' THEN
        SELECT count(*) INTO v_n FROM gestao.ce_itens(p_dataset, v_f);
        RETURN jsonb_build_object('valor', v_n, 'n', v_n, 'estado', CASE WHEN v_n = 0 THEN 'sem_dados' ELSE 'ok' END);
    ELSIF v_op = 'count_distinct' AND v_c IN ('codigo_territorial_origem', 'entidade_nome', 'numero_processo', 'fornecedor_nome') THEN
        SELECT count(*), count(DISTINCT CASE v_c WHEN 'codigo_territorial_origem' THEN i.codigo_territorial_origem
                                                 WHEN 'entidade_nome' THEN i.entidade_nome
                                                 WHEN 'numero_processo' THEN i.numero_processo
                                                 ELSE i.fornecedor_nome END)
          INTO v_n, v_a FROM gestao.ce_itens(p_dataset, v_f) i;
        RETURN jsonb_build_object('valor', v_a, 'n', v_n, 'estado', CASE WHEN v_n = 0 THEN 'sem_dados' ELSE 'ok' END);
    ELSIF v_op = 'ratio' AND v_num IN ('quantidade', 'valor_total') AND v_den IN ('quantidade', 'valor_total') AND v_num <> v_den THEN
        -- Razão de somas sobre as linhas elegíveis (numerador e denominador presentes)
        SELECT count(*),
               sum(CASE v_num WHEN 'quantidade' THEN i.quantidade::numeric ELSE i.valor_total END),
               sum(CASE v_den WHEN 'quantidade' THEN i.quantidade::numeric ELSE i.valor_total END)
          INTO v_n, v_a, v_b FROM gestao.ce_itens(p_dataset, v_f) i
         WHERE i.quantidade IS NOT NULL AND i.valor_total IS NOT NULL;
        IF v_n = 0 THEN RETURN jsonb_build_object('valor', NULL, 'n', 0, 'estado', 'sem_dados'); END IF;
        IF COALESCE(v_b, 0) = 0 THEN
            RETURN jsonb_build_object('valor', NULL, 'numerador', v_a, 'denominador', v_b, 'n', v_n, 'estado', 'denominador_zero');
        END IF;
        RETURN jsonb_build_object('valor', v_a / v_b, 'numerador', v_a, 'denominador', v_b, 'n', v_n, 'estado', 'ok');
    ELSIF v_op = 'completude' AND v_c IN ('resultado_primario_origem', 'valor_unitario', 'termo_compromisso', 'numero_processo') THEN
        SELECT count(*), count(CASE v_c WHEN 'resultado_primario_origem' THEN i.resultado_primario_origem
                                        WHEN 'valor_unitario' THEN i.valor_unitario::text
                                        WHEN 'termo_compromisso' THEN i.termo_compromisso
                                        ELSE i.numero_processo END)
          INTO v_n, v_a FROM gestao.ce_itens(p_dataset, v_f) i;
        IF v_n = 0 THEN RETURN jsonb_build_object('valor', NULL, 'n', 0, 'estado', 'sem_dados'); END IF;
        RETURN jsonb_build_object('valor', 100.0 * v_a / v_n, 'numerador', v_a, 'denominador', v_n, 'n', v_n, 'estado', 'ok');
    END IF;
    RAISE EXCEPTION 'Cálculo não permitido (operação/campo fora da lista autorizada).' USING ERRCODE = '22023';
END $$;

CREATE OR REPLACE FUNCTION catalogo.calculo_valido(p_calc jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
    SELECT p_calc IS NULL OR (
        (p_calc ->> 'operacao' = 'sum' AND p_calc ->> 'campo' IN ('quantidade', 'valor_total')) OR
        (p_calc ->> 'operacao' = 'count') OR
        (p_calc ->> 'operacao' = 'count_distinct' AND p_calc ->> 'campo' IN ('codigo_territorial_origem', 'entidade_nome', 'numero_processo', 'fornecedor_nome')) OR
        (p_calc ->> 'operacao' = 'ratio' AND p_calc ->> 'numerador' IN ('quantidade', 'valor_total')
             AND p_calc ->> 'denominador' IN ('quantidade', 'valor_total') AND p_calc ->> 'numerador' <> p_calc ->> 'denominador') OR
        (p_calc ->> 'operacao' = 'completude' AND p_calc ->> 'campo' IN ('resultado_primario_origem', 'valor_unitario', 'termo_compromisso', 'numero_processo')));
$$;
ALTER TABLE catalogo.indicador_versoes ADD CONSTRAINT calculo_permitido CHECK (catalogo.calculo_valido(calculo));

CREATE OR REPLACE FUNCTION gestao.dataset_ativo(p_fonte text)
RETURNS bigint LANGUAGE sql STABLE SET search_path = '' AS $$
    SELECT id FROM gestao.dataset_versoes WHERE fonte = p_fonte AND status = 'ativa';
$$;

-- Publicação ativa de um código (NULL se não publicado) — base de toda leitura pública
CREATE OR REPLACE FUNCTION catalogo.publicacao_ativa(p_codigo text)
RETURNS TABLE (pub_id bigint, indicador_id bigint, versao_id bigint, dataset_id bigint, somente_ficha boolean, inicio timestamptz)
LANGUAGE sql STABLE SET search_path = '' AS $$
    SELECT p.id, p.indicador_id, p.versao_id, p.dataset_versao_id, p.somente_ficha, p.inicio
    FROM catalogo.publicacoes p JOIN catalogo.indicadores i ON i.id = p.indicador_id
    WHERE i.codigo = p_codigo AND p.ativa;
$$;

CREATE OR REPLACE FUNCTION catalogo.ficha(p_versao_id bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path = '' AS $$
    SELECT jsonb_build_object(
        'codigo', i.codigo, 'slug', i.slug, 'tipo', i.tipo, 'frente', i.frente, 'modulo', i.modulo,
        'categoria', i.categoria, 'ordem', i.ordem, 'versao', v.versao, 'titulo', v.titulo,
        'descricao', v.descricao, 'objetivo', v.objetivo, 'unidade', v.unidade, 'casas_decimais', v.casas_decimais,
        'visual', v.visual, 'niveis', to_jsonb(v.niveis), 'dimensoes', to_jsonb(v.dimensoes),
        'formula_texto', v.formula_texto, 'fonte', v.fonte, 'fonte_descricao', f.descricao,
        'periodo_referencia', v.periodo_referencia, 'regra_nulos', v.regra_nulos, 'sentido', v.sentido,
        'situacao_metodologica', v.situacao_metodologica, 'responsavel', v.responsavel, 'nota', v.nota)
    FROM catalogo.indicador_versoes v
    JOIN catalogo.indicadores i ON i.id = v.indicador_id
    LEFT JOIN gestao.fontes f ON f.codigo = v.fonte
    WHERE v.id = p_versao_id;
$$;

CREATE OR REPLACE FUNCTION gestao.dataset_info(p_id bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path = '' AS $$
    SELECT jsonb_build_object('id', d.id, 'fonte', d.fonte, 'arquivo', d.arquivo, 'data_captura', d.data_captura,
                              'periodo_inicio', d.periodo_inicio, 'periodo_fim', d.periodo_fim,
                              'linhas', d.linhas, 'carregado_em', d.recebido_em, 'ativada_em', d.ativada_em)
    FROM gestao.dataset_versoes d WHERE d.id = p_id;
$$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA gestao, catalogo FROM PUBLIC, anon, authenticated;

-- ============================================================================
-- API PÚBLICA (anon + authenticated): somente o que tem publicação ativa
-- ============================================================================

-- Catálogo publicado (fichas + valor nacional quando não for "somente ficha")
CREATE OR REPLACE FUNCTION public.pnite_catalogo_publicado(p_frente text DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
    SELECT COALESCE(jsonb_agg(
        catalogo.ficha(p.versao_id) || jsonb_build_object(
            'publicado_em', p.inicio, 'somente_ficha', p.somente_ficha,
            'dados', gestao.dataset_info(p.dataset_versao_id),
            'resultado', CASE WHEN p.somente_ficha OR v.calculo IS NULL THEN NULL
                              ELSE catalogo.calcular(v.calculo, p.dataset_versao_id, '{}'::jsonb) END)
        ORDER BY i.frente, i.ordem, i.codigo), '[]'::jsonb)
    FROM catalogo.publicacoes p
    JOIN catalogo.indicadores i ON i.id = p.indicador_id
    JOIN catalogo.indicador_versoes v ON v.id = p.versao_id
    WHERE p.ativa AND (p_frente IS NULL OR i.frente = p_frente);
$$;

-- Valor de um indicador publicado com filtros (resultado não revelador se não publicado)
CREATE OR REPLACE FUNCTION public.pnite_indicador_valor(p_codigo text, p_filtros jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE r record; v_calc jsonb;
BEGIN
    SELECT * INTO r FROM catalogo.publicacao_ativa(p_codigo);
    IF r.pub_id IS NULL THEN RETURN jsonb_build_object('encontrado', false); END IF;
    SELECT calculo INTO v_calc FROM catalogo.indicador_versoes WHERE id = r.versao_id;
    RETURN jsonb_build_object('encontrado', true, 'ficha', catalogo.ficha(r.versao_id),
        'dados', gestao.dataset_info(r.dataset_id), 'somente_ficha', r.somente_ficha,
        'filtros', catalogo.validar_filtros(p_filtros),
        'resultado', CASE WHEN r.somente_ficha OR v_calc IS NULL THEN NULL
                          ELSE catalogo.calcular(v_calc, r.dataset_id, p_filtros) END);
END $$;

-- Painel "Contratação de Ônibus" (visual CE_PAINEL_CONTRATACOES)
CREATE OR REPLACE FUNCTION public.pnite_ce_painel(p_filtros jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE r record; v_f jsonb := catalogo.validar_filtros(p_filtros); v jsonb;
BEGIN
    SELECT * INTO r FROM catalogo.publicacao_ativa('CE_PAINEL_CONTRATACOES');
    IF r.pub_id IS NULL OR r.dataset_id IS NULL THEN RETURN jsonb_build_object('publicado', false); END IF;
    WITH b AS (SELECT * FROM gestao.ce_itens(r.dataset_id, v_f)),
         tudo AS (SELECT * FROM gestao.ce_contratacao_itens WHERE dataset_versao_id = r.dataset_id)
    SELECT jsonb_build_object(
        'publicado', true, 'ficha', catalogo.ficha(r.versao_id), 'dados', gestao.dataset_info(r.dataset_id),
        'filtros', v_f,
        'totais', (SELECT jsonb_build_object(
                     'linhas', count(*), 'quantidade', sum(quantidade), 'valor_total', sum(valor_total),
                     'preco_medio_ponderado', CASE WHEN sum(quantidade) FILTER (WHERE valor_total IS NOT NULL) > 0
                         THEN sum(valor_total) FILTER (WHERE quantidade IS NOT NULL)
                              / sum(quantidade) FILTER (WHERE valor_total IS NOT NULL) END,
                     'entes', count(DISTINCT codigo_territorial_origem),
                     'entidades', count(DISTINCT entidade_nome),
                     'unitario_ausente', count(*) FILTER (WHERE flag_unitario_ausente),
                     'rp_ausente', count(*) FILTER (WHERE resultado_primario_origem IS NULL)) FROM b),
        'por_ano', (SELECT COALESCE(jsonb_agg(x ORDER BY x.k), '[]') FROM
                     (SELECT ano_contratacao::text k, sum(quantidade) qtd, sum(valor_total) valor FROM b GROUP BY 1) x),
        'por_tipo', (SELECT COALESCE(jsonb_agg(x ORDER BY x.qtd DESC), '[]') FROM
                     (SELECT tipo_veiculo_origem k, sum(quantidade) qtd, sum(valor_total) valor FROM b GROUP BY 1) x),
        'por_regiao', (SELECT COALESCE(jsonb_agg(x ORDER BY x.qtd DESC), '[]') FROM
                     (SELECT regiao_origem k, sum(quantidade) qtd, sum(valor_total) valor FROM b GROUP BY 1) x),
        'por_uf', (SELECT COALESCE(jsonb_agg(x ORDER BY x.qtd DESC), '[]') FROM
                     (SELECT uf_origem k, sum(quantidade) qtd, sum(valor_total) valor FROM b GROUP BY 1) x),
        'por_esfera', (SELECT COALESCE(jsonb_agg(x ORDER BY x.qtd DESC), '[]') FROM
                     (SELECT esfera_administrativa k, sum(quantidade) qtd, sum(valor_total) valor FROM b GROUP BY 1) x),
        'entidades_top', (SELECT COALESCE(jsonb_agg(x ORDER BY x.qtd DESC, x.entidade), '[]') FROM
                     (SELECT entidade_nome entidade, uf_origem uf, municipio_nome_origem municipio,
                             sum(quantidade) qtd, sum(valor_total) valor
                      FROM b GROUP BY 1, 2, 3 ORDER BY 4 DESC, 1 LIMIT 100) x),
        'dominios', jsonb_build_object(
            'ano', (SELECT jsonb_agg(DISTINCT ano_contratacao ORDER BY ano_contratacao) FROM tudo),
            'regiao', (SELECT jsonb_agg(DISTINCT regiao_origem ORDER BY regiao_origem) FROM tudo WHERE regiao_origem IS NOT NULL),
            'uf', (SELECT jsonb_agg(DISTINCT uf_origem ORDER BY uf_origem) FROM tudo WHERE uf_origem IS NOT NULL),
            'esfera', (SELECT jsonb_agg(DISTINCT esfera_administrativa ORDER BY esfera_administrativa) FROM tudo WHERE esfera_administrativa IS NOT NULL),
            'tipo_veiculo', (SELECT jsonb_agg(DISTINCT tipo_veiculo_origem ORDER BY tipo_veiculo_origem) FROM tudo WHERE tipo_veiculo_origem IS NOT NULL),
            'forma_pagamento', (SELECT jsonb_agg(DISTINCT forma_pagamento_origem ORDER BY forma_pagamento_origem) FROM tudo WHERE forma_pagamento_origem IS NOT NULL)),
        'reconciliacoes', (SELECT COALESCE(jsonb_agg(to_jsonb(rc) - 'id'), '[]') FROM gestao.reconciliacoes rc))
    INTO v;
    RETURN v;
END $$;

-- Detalhamento das contratações (visual CE_DETALHAMENTO): colunas em allowlist, paginado
CREATE OR REPLACE FUNCTION public.pnite_ce_detalhe(p_filtros jsonb DEFAULT '{}'::jsonb, p_busca text DEFAULT NULL,
                                                   p_pagina integer DEFAULT 1, p_tamanho integer DEFAULT 25,
                                                   p_ordem text DEFAULT 'data_desc')
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE r record; v_f jsonb := catalogo.validar_filtros(p_filtros); v_tam int; v_pag int; v_b text; v jsonb;
BEGIN
    SELECT * INTO r FROM catalogo.publicacao_ativa('CE_DETALHAMENTO');
    IF r.pub_id IS NULL OR r.dataset_id IS NULL THEN RETURN jsonb_build_object('publicado', false); END IF;
    v_tam := LEAST(GREATEST(COALESCE(p_tamanho, 25), 1), 100);
    v_pag := LEAST(GREATEST(COALESCE(p_pagina, 1), 1), 100000);
    v_b := NULLIF(btrim(left(COALESCE(p_busca, ''), 80)), '');
    IF v_b IS NOT NULL THEN v_b := '%' || replace(replace(replace(v_b, '\', '\\'), '%', '\%'), '_', '\_') || '%'; END IF;
    IF p_ordem NOT IN ('data_desc', 'data_asc', 'valor_desc', 'qtd_desc', 'entidade') THEN p_ordem := 'data_desc'; END IF;
    WITH b AS (
        SELECT * FROM gestao.ce_itens(r.dataset_id, v_f) i
        WHERE v_b IS NULL OR i.entidade_nome ILIKE v_b OR i.municipio_nome_origem ILIKE v_b
           OR i.fornecedor_nome ILIKE v_b OR i.numero_processo ILIKE v_b OR i.pregao_origem ILIKE v_b
           OR i.termo_compromisso ILIKE v_b)
    SELECT jsonb_build_object('publicado', true, 'dados', gestao.dataset_info(r.dataset_id),
        'total', (SELECT count(*) FROM b),
        'quantidade', (SELECT sum(quantidade) FROM b), 'valor_total', (SELECT sum(valor_total) FROM b),
        'pagina', v_pag, 'tamanho', v_tam,
        'linhas', (SELECT COALESCE(jsonb_agg(x), '[]') FROM (
            SELECT ano_contratacao ano, codigo_territorial_origem cod_ibge, termo_compromisso termo, numero_processo processo,
                   regiao_origem regiao, uf_origem uf, municipio_nome_origem municipio, esfera_administrativa esfera,
                   entidade_nome entidade, tipo_veiculo_origem tipo_veiculo, quantidade, valor_unitario, valor_total,
                   forma_pagamento_origem forma_pagamento, resultado_primario_origem resultado_primario,
                   data_contratacao_origem data_contratacao, fornecedor_nome fornecedor, pregao_origem pregao
            FROM b
            ORDER BY CASE WHEN p_ordem = 'data_desc' THEN data_contratacao_origem END DESC NULLS LAST,
                     CASE WHEN p_ordem = 'data_asc' THEN data_contratacao_origem END ASC NULLS LAST,
                     CASE WHEN p_ordem = 'valor_desc' THEN valor_total END DESC NULLS LAST,
                     CASE WHEN p_ordem = 'qtd_desc' THEN quantidade END DESC NULLS LAST,
                     CASE WHEN p_ordem = 'entidade' THEN entidade_nome END ASC,
                     source_row_number
            OFFSET (v_pag - 1) * v_tam LIMIT v_tam) x))
    INTO v;
    RETURN v;
END $$;

-- Snapshot documental dos painéis (visuais CE_REPASSES_SNAPSHOT e SETE_PAINEL_SNAPSHOT)
CREATE OR REPLACE FUNCTION public.pnite_snapshot_painel(p_painel text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE r record; v_cod text;
BEGIN
    v_cod := CASE p_painel WHEN 'caminho' THEN 'CE_REPASSES_SNAPSHOT' WHEN 'sete' THEN 'SETE_PAINEL_SNAPSHOT' END;
    IF v_cod IS NULL THEN RETURN jsonb_build_object('publicado', false); END IF;
    SELECT * INTO r FROM catalogo.publicacao_ativa(v_cod);
    IF r.pub_id IS NULL OR r.dataset_id IS NULL THEN RETURN jsonb_build_object('publicado', false); END IF;
    RETURN jsonb_build_object('publicado', true, 'ficha', catalogo.ficha(r.versao_id), 'dados', gestao.dataset_info(r.dataset_id),
        'linhas', (SELECT COALESCE(jsonb_agg(jsonb_build_object('aba', s.aba, 'pagina', s.pagina, 'indicador', s.indicador,
                       'categoria', s.categoria, 'valor', s.valor, 'unidade', s.unidade, 'observacao', s.observacao) ORDER BY s.aba, s.ordem), '[]')
                   FROM gestao.snapshots_paineis s WHERE s.dataset_versao_id = r.dataset_id AND s.painel = p_painel),
        'auditoria', (SELECT COALESCE(jsonb_agg(jsonb_build_object('verificacao', q.verificacao, 'valor', q.valor, 'origem', q.origem,
                       'situacao', q.situacao) ORDER BY q.id), '[]')
                   FROM gestao.pendencias_qualidade q WHERE q.dataset_versao_id = r.dataset_id
                    AND q.painel = CASE p_painel WHEN 'caminho' THEN 'Caminho da Escola' ELSE 'SETE' END));
END $$;

-- ============================================================================
-- API ADMINISTRATIVA (authenticated + administrador ativo conferido no banco)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.pnite_admin_cat_listar()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    PERFORM acesso.exigir_admin();
    RETURN (SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', i.id, 'codigo', i.codigo, 'slug', i.slug, 'tipo', i.tipo, 'frente', i.frente, 'modulo', i.modulo,
        'categoria', i.categoria, 'ordem', i.ordem,
        'publicacao', (SELECT jsonb_build_object('id', p.id, 'versao_id', p.versao_id, 'inicio', p.inicio,
                              'dataset_versao_id', p.dataset_versao_id, 'somente_ficha', p.somente_ficha, 'publicado_por', p.publicado_por)
                       FROM catalogo.publicacoes p WHERE p.indicador_id = i.id AND p.ativa),
        'versoes', (SELECT jsonb_agg(to_jsonb(v) - 'indicador_id' ORDER BY v.versao DESC)
                    FROM catalogo.indicador_versoes v WHERE v.indicador_id = i.id))
        ORDER BY i.frente, i.ordem, i.codigo), '[]'::jsonb) FROM catalogo.indicadores i);
END $$;

-- Normaliza e valida o JSON do formulário (campos permitidos apenas)
CREATE OR REPLACE FUNCTION catalogo.campos_versao(p jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SET search_path = '' AS $$
DECLARE k text; v_calc jsonb;
BEGIN
    IF p IS NULL OR jsonb_typeof(p) <> 'object' THEN RAISE EXCEPTION 'Dados inválidos.' USING ERRCODE = '22023'; END IF;
    FOR k IN SELECT jsonb_object_keys(p) LOOP
        IF k NOT IN ('titulo', 'descricao', 'objetivo', 'unidade', 'casas_decimais', 'visual', 'niveis', 'dimensoes',
                     'formula_texto', 'calculo', 'fonte', 'periodo_referencia', 'regra_nulos', 'sentido',
                     'situacao_metodologica', 'responsavel', 'nota') THEN
            RAISE EXCEPTION 'Campo não permitido: %', k USING ERRCODE = '22023';
        END IF;
    END LOOP;
    v_calc := NULLIF(p -> 'calculo', 'null'::jsonb);
    IF NOT catalogo.calculo_valido(v_calc) THEN
        RAISE EXCEPTION 'Cálculo não permitido (use as operações e campos da lista).' USING ERRCODE = '22023';
    END IF;
    RETURN p;
END $$;

CREATE OR REPLACE FUNCTION public.pnite_admin_cat_criar(p_codigo text, p_slug text, p_tipo text, p_frente text,
                                                        p_modulo text, p_categoria text, p_ordem integer, p_dados jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_admin text := acesso.exigir_admin(); v_id bigint; v_ver bigint; d jsonb := catalogo.campos_versao(p_dados);
BEGIN
    INSERT INTO catalogo.indicadores (codigo, slug, tipo, frente, modulo, categoria, ordem, criado_por)
    VALUES (upper(btrim(p_codigo)), lower(btrim(p_slug)), COALESCE(p_tipo, 'indicador'), p_frente, btrim(p_modulo),
            NULLIF(btrim(p_categoria), ''), COALESCE(p_ordem, 100), v_admin)
    RETURNING id INTO v_id;
    INSERT INTO catalogo.indicador_versoes (indicador_id, versao, titulo, descricao, objetivo, unidade, casas_decimais, visual,
        niveis, dimensoes, formula_texto, calculo, fonte, periodo_referencia, regra_nulos, sentido, situacao_metodologica,
        responsavel, nota, criado_por)
    VALUES (v_id, 1, d ->> 'titulo', d ->> 'descricao', d ->> 'objetivo', d ->> 'unidade',
        COALESCE((d ->> 'casas_decimais')::smallint, 0), COALESCE(d ->> 'visual', 'cartao'),
        CASE WHEN jsonb_typeof(d -> 'niveis') = 'array' THEN ARRAY(SELECT jsonb_array_elements_text(d -> 'niveis')) ELSE ARRAY['nacional'] END,
        CASE WHEN jsonb_typeof(d -> 'dimensoes') = 'array' THEN ARRAY(SELECT jsonb_array_elements_text(d -> 'dimensoes')) ELSE '{}'::text[] END,
        d ->> 'formula_texto', NULLIF(d -> 'calculo', 'null'::jsonb), NULLIF(d ->> 'fonte', ''), d ->> 'periodo_referencia',
        d ->> 'regra_nulos', COALESCE(d ->> 'sentido', 'neutro'), COALESCE(d ->> 'situacao_metodologica', 'em_construcao'),
        d ->> 'responsavel', d ->> 'nota', v_admin)
    RETURNING id INTO v_ver;
    PERFORM catalogo.auditar(v_admin, 'criar_indicador', 'indicador', v_id::text, NULL,
        jsonb_build_object('codigo', upper(btrim(p_codigo)), 'versao_id', v_ver), NULL);
    RETURN jsonb_build_object('indicador_id', v_id, 'versao_id', v_ver);
EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'Já existe um indicador com este código ou slug.' USING ERRCODE = '23505';
END $$;

-- Nova versão em rascunho a partir de uma existente (a publicada não muda)
CREATE OR REPLACE FUNCTION public.pnite_admin_cat_nova_versao(p_versao_base bigint)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_admin text := acesso.exigir_admin(); b catalogo.indicador_versoes; v_nova bigint; v_n int;
BEGIN
    SELECT * INTO b FROM catalogo.indicador_versoes WHERE id = p_versao_base;
    IF b.id IS NULL THEN RAISE EXCEPTION 'Versão não encontrada.' USING ERRCODE = 'P0002'; END IF;
    PERFORM 1 FROM catalogo.indicadores WHERE id = b.indicador_id FOR UPDATE;
    SELECT max(versao) + 1 INTO v_n FROM catalogo.indicador_versoes WHERE indicador_id = b.indicador_id;
    INSERT INTO catalogo.indicador_versoes (indicador_id, versao, titulo, descricao, objetivo, unidade, casas_decimais, visual,
        niveis, dimensoes, formula_texto, calculo, fonte, periodo_referencia, regra_nulos, sentido, situacao_metodologica,
        responsavel, nota, criado_por)
    SELECT b.indicador_id, v_n, b.titulo, b.descricao, b.objetivo, b.unidade, b.casas_decimais, b.visual, b.niveis, b.dimensoes,
        b.formula_texto, b.calculo, b.fonte, b.periodo_referencia, b.regra_nulos, b.sentido, b.situacao_metodologica,
        b.responsavel, b.nota, v_admin
    RETURNING id INTO v_nova;
    PERFORM catalogo.auditar(v_admin, 'nova_versao', 'indicador_versao', v_nova::text,
        jsonb_build_object('base', p_versao_base), jsonb_build_object('versao', v_n), NULL);
    RETURN jsonb_build_object('versao_id', v_nova, 'versao', v_n);
END $$;

-- Edita rascunho/em revisão (controle otimista por lock_version)
CREATE OR REPLACE FUNCTION public.pnite_admin_cat_editar(p_versao_id bigint, p_lock integer, p_dados jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_admin text := acesso.exigir_admin(); a catalogo.indicador_versoes; d jsonb := catalogo.campos_versao(p_dados);
BEGIN
    SELECT * INTO a FROM catalogo.indicador_versoes WHERE id = p_versao_id FOR UPDATE;
    IF a.id IS NULL THEN RAISE EXCEPTION 'Versão não encontrada.' USING ERRCODE = 'P0002'; END IF;
    IF a.lock_version <> p_lock THEN
        RAISE EXCEPTION 'Esta versão foi alterada por outra pessoa. Recarregue antes de salvar.' USING ERRCODE = '40001';
    END IF;
    IF a.estado_editorial NOT IN ('rascunho', 'em_revisao') THEN
        RAISE EXCEPTION 'Só rascunhos e versões em revisão podem ser editados. Crie uma nova versão.' USING ERRCODE = '42501';
    END IF;
    UPDATE catalogo.indicador_versoes SET
        titulo = COALESCE(d ->> 'titulo', titulo),
        descricao = CASE WHEN d ? 'descricao' THEN d ->> 'descricao' ELSE descricao END,
        objetivo = CASE WHEN d ? 'objetivo' THEN d ->> 'objetivo' ELSE objetivo END,
        unidade = CASE WHEN d ? 'unidade' THEN d ->> 'unidade' ELSE unidade END,
        casas_decimais = COALESCE((d ->> 'casas_decimais')::smallint, casas_decimais),
        visual = COALESCE(d ->> 'visual', visual),
        niveis = CASE WHEN d ? 'niveis' THEN ARRAY(SELECT jsonb_array_elements_text(d -> 'niveis')) ELSE niveis END,
        dimensoes = CASE WHEN d ? 'dimensoes' THEN ARRAY(SELECT jsonb_array_elements_text(d -> 'dimensoes')) ELSE dimensoes END,
        formula_texto = CASE WHEN d ? 'formula_texto' THEN d ->> 'formula_texto' ELSE formula_texto END,
        calculo = CASE WHEN d ? 'calculo' THEN NULLIF(d -> 'calculo', 'null'::jsonb) ELSE calculo END,
        fonte = CASE WHEN d ? 'fonte' THEN NULLIF(d ->> 'fonte', '') ELSE fonte END,
        periodo_referencia = CASE WHEN d ? 'periodo_referencia' THEN d ->> 'periodo_referencia' ELSE periodo_referencia END,
        regra_nulos = CASE WHEN d ? 'regra_nulos' THEN d ->> 'regra_nulos' ELSE regra_nulos END,
        sentido = COALESCE(d ->> 'sentido', sentido),
        situacao_metodologica = COALESCE(d ->> 'situacao_metodologica', situacao_metodologica),
        responsavel = CASE WHEN d ? 'responsavel' THEN d ->> 'responsavel' ELSE responsavel END,
        nota = CASE WHEN d ? 'nota' THEN d ->> 'nota' ELSE nota END,
        estado_editorial = 'rascunho',
        lock_version = lock_version + 1, atualizado_em = now()
    WHERE id = p_versao_id;
    PERFORM catalogo.auditar(v_admin, 'editar_versao', 'indicador_versao', p_versao_id::text,
        to_jsonb(a) - 'lock_version', d, NULL);
    RETURN jsonb_build_object('versao_id', p_versao_id, 'lock_version', a.lock_version + 1);
END $$;

-- Transições editoriais: enviar_revisao, voltar_rascunho, aprovar, publicar, suspender, restaurar, arquivar
CREATE OR REPLACE FUNCTION public.pnite_admin_cat_transicao(p_versao_id bigint, p_acao text, p_lock integer,
                                                            p_justificativa text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    v_admin text := acesso.exigir_admin();
    a catalogo.indicador_versoes; i catalogo.indicadores; p_atual catalogo.publicacoes;
    v_novo text; v_dataset bigint; v_ficha boolean := false; v_just text := NULLIF(btrim(p_justificativa), '');
BEGIN
    SELECT * INTO a FROM catalogo.indicador_versoes WHERE id = p_versao_id;
    IF a.id IS NULL THEN RAISE EXCEPTION 'Versão não encontrada.' USING ERRCODE = 'P0002'; END IF;
    SELECT * INTO i FROM catalogo.indicadores WHERE id = a.indicador_id FOR UPDATE;   -- serializa por indicador
    SELECT * INTO a FROM catalogo.indicador_versoes WHERE id = p_versao_id FOR UPDATE;
    SELECT * INTO p_atual FROM catalogo.publicacoes WHERE indicador_id = i.id AND ativa;

    -- Idempotência: publicar de novo a versão já publicada não cria outra release
    IF p_acao = 'publicar' AND p_atual.versao_id = a.id THEN
        RETURN jsonb_build_object('ok', true, 'idempotente', true, 'publicacao_id', p_atual.id);
    END IF;
    IF a.lock_version <> p_lock THEN
        RAISE EXCEPTION 'Esta versão foi alterada por outra pessoa. Recarregue antes de continuar.' USING ERRCODE = '40001';
    END IF;
    IF p_acao IN ('aprovar', 'publicar', 'suspender', 'restaurar', 'arquivar') AND v_just IS NULL THEN
        RAISE EXCEPTION 'Informe a justificativa.' USING ERRCODE = '22023';
    END IF;

    IF p_acao = 'enviar_revisao' AND a.estado_editorial = 'rascunho' THEN
        v_novo := 'em_revisao';
    ELSIF p_acao = 'voltar_rascunho' AND a.estado_editorial IN ('em_revisao', 'aprovado') THEN
        v_novo := 'rascunho';
    ELSIF p_acao = 'aprovar' AND a.estado_editorial = 'em_revisao' THEN
        IF a.responsavel IS NULL OR btrim(a.responsavel) = '' THEN
            RAISE EXCEPTION 'Defina o responsável antes de aprovar.' USING ERRCODE = '22023';
        END IF;
        v_novo := 'aprovado';
    ELSIF p_acao = 'publicar' AND a.estado_editorial = 'aprovado' THEN
        v_novo := 'publicado';
    ELSIF p_acao = 'restaurar' AND a.estado_editorial = 'suspenso' AND a.aprovado_em IS NOT NULL THEN
        v_novo := 'publicado';
    ELSIF p_acao = 'suspender' AND a.estado_editorial = 'publicado' THEN
        v_novo := 'suspenso';
    ELSIF p_acao = 'arquivar' AND a.estado_editorial IN ('rascunho', 'em_revisao', 'aprovado', 'suspenso') THEN
        v_novo := 'arquivado';
    ELSE
        RAISE EXCEPTION 'Ação "%" não permitida no estado "%".', p_acao, a.estado_editorial USING ERRCODE = '42501';
    END IF;

    IF v_novo = 'publicado' THEN
        -- Fonte aprovada (versão de dados ativa) e situação metodológica
        IF a.fonte IS NOT NULL THEN
            v_dataset := gestao.dataset_ativo(a.fonte);
        END IF;
        IF a.calculo IS NOT NULL AND v_dataset IS NULL THEN
            RAISE EXCEPTION 'Não há versão de dados ativa para a fonte deste indicador.' USING ERRCODE = '22023';
        END IF;
        IF i.tipo = 'visual' AND a.fonte IS NOT NULL AND v_dataset IS NULL THEN
            RAISE EXCEPTION 'Não há versão de dados ativa para a fonte deste visual.' USING ERRCODE = '22023';
        END IF;
        -- Indicador não validado só pode ir a público como ficha metodológica, sem valores
        v_ficha := (i.tipo = 'indicador' AND a.situacao_metodologica <> 'validado');
        IF p_atual.id IS NOT NULL THEN
            UPDATE catalogo.publicacoes SET ativa = false, fim = now(), encerrado_por = v_admin WHERE id = p_atual.id;
            UPDATE catalogo.indicador_versoes SET estado_editorial = 'suspenso', lock_version = lock_version + 1, atualizado_em = now()
             WHERE id = p_atual.versao_id;
        END IF;
        INSERT INTO catalogo.publicacoes (indicador_id, versao_id, dataset_versao_id, somente_ficha, publicado_por, justificativa)
        VALUES (i.id, a.id, v_dataset, v_ficha, v_admin, v_just);
    ELSIF v_novo = 'suspenso' THEN
        UPDATE catalogo.publicacoes SET ativa = false, fim = now(), encerrado_por = v_admin
         WHERE indicador_id = i.id AND ativa;
    END IF;

    UPDATE catalogo.indicador_versoes SET estado_editorial = v_novo, lock_version = lock_version + 1, atualizado_em = now(),
        aprovado_por = CASE WHEN v_novo = 'aprovado' THEN v_admin ELSE aprovado_por END,
        aprovado_em  = CASE WHEN v_novo = 'aprovado' THEN now() ELSE aprovado_em END
    WHERE id = a.id;

    PERFORM catalogo.auditar(v_admin, p_acao, 'indicador_versao', a.id::text,
        jsonb_build_object('estado', a.estado_editorial, 'publicacao_anterior', p_atual.id),
        jsonb_build_object('estado', v_novo, 'codigo', i.codigo, 'dataset_versao_id', v_dataset, 'somente_ficha', v_ficha),
        v_just);
    RETURN jsonb_build_object('ok', true, 'estado', v_novo, 'somente_ficha', v_ficha);
END $$;

-- Prévia privada: valor da versão (rascunho ou não) na versão de dados ativa x publicação atual
CREATE OR REPLACE FUNCTION public.pnite_admin_cat_previa(p_versao_id bigint, p_filtros jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE a catalogo.indicador_versoes; p catalogo.publicacoes; pv catalogo.indicador_versoes; v_ds bigint;
BEGIN
    PERFORM acesso.exigir_admin();
    SELECT * INTO a FROM catalogo.indicador_versoes WHERE id = p_versao_id;
    IF a.id IS NULL THEN RAISE EXCEPTION 'Versão não encontrada.' USING ERRCODE = 'P0002'; END IF;
    SELECT * INTO p FROM catalogo.publicacoes WHERE indicador_id = a.indicador_id AND ativa;
    SELECT * INTO pv FROM catalogo.indicador_versoes WHERE id = p.versao_id;
    v_ds := CASE WHEN a.fonte IS NOT NULL THEN gestao.dataset_ativo(a.fonte) END;
    RETURN jsonb_build_object(
        'versao', catalogo.ficha(a.id), 'dados', gestao.dataset_info(v_ds),
        'resultado', CASE WHEN a.calculo IS NULL THEN NULL ELSE catalogo.calcular(a.calculo, v_ds, p_filtros) END,
        'publicada', CASE WHEN p.id IS NULL THEN NULL ELSE catalogo.ficha(pv.id) END,
        'resultado_publicado', CASE WHEN p.id IS NULL OR pv.calculo IS NULL THEN NULL
                                    ELSE catalogo.calcular(pv.calculo, p.dataset_versao_id, p_filtros) END,
        'diferencas', (SELECT COALESCE(jsonb_object_agg(k, jsonb_build_object('publicada', catalogo.ficha(pv.id) -> k,
                                                                             'nova', catalogo.ficha(a.id) -> k)), '{}')
                       FROM jsonb_object_keys(catalogo.ficha(a.id)) k
                       WHERE p.id IS NOT NULL AND k <> 'versao'
                         AND catalogo.ficha(pv.id) -> k IS DISTINCT FROM catalogo.ficha(a.id) -> k));
END $$;

-- Fontes e cargas
CREATE OR REPLACE FUNCTION public.pnite_admin_cargas()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    PERFORM acesso.exigir_admin();
    RETURN jsonb_build_object(
        'fontes', (SELECT COALESCE(jsonb_agg(to_jsonb(f) ORDER BY f.codigo), '[]') FROM gestao.fontes f),
        'versoes', (SELECT COALESCE(jsonb_agg(to_jsonb(d) ORDER BY d.id DESC), '[]') FROM gestao.dataset_versoes d),
        'qualidade', (SELECT COALESCE(jsonb_agg(jsonb_build_object('dataset_versao_id', i.dataset_versao_id,
                          'unitario_ausente', i.ua, 'produto_divergente', i.pd, 'termo_marcador', i.tm,
                          'processo_marcador', i.pm, 'rp_ausente', i.rp, 'linhas', i.n)), '[]')
                      FROM (SELECT dataset_versao_id, count(*) n, count(*) FILTER (WHERE flag_unitario_ausente) ua,
                                   count(*) FILTER (WHERE flag_produto_divergente) pd, count(*) FILTER (WHERE flag_termo_marcador) tm,
                                   count(*) FILTER (WHERE flag_processo_marcador) pm,
                                   count(*) FILTER (WHERE resultado_primario_origem IS NULL) rp
                            FROM gestao.ce_contratacao_itens GROUP BY 1) i),
        'pendencias', (SELECT COALESCE(jsonb_agg(to_jsonb(q) ORDER BY q.id), '[]') FROM gestao.pendencias_qualidade q),
        'reconciliacoes', (SELECT COALESCE(jsonb_agg(to_jsonb(r) ORDER BY r.id), '[]') FROM gestao.reconciliacoes r));
END $$;

-- Ativa uma versão de dados validada (transacional; não publica indicadores)
CREATE OR REPLACE FUNCTION public.pnite_admin_carga_ativar(p_dataset bigint, p_justificativa text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_admin text := acesso.exigir_admin(); d gestao.dataset_versoes; v_ant bigint;
BEGIN
    IF NULLIF(btrim(p_justificativa), '') IS NULL THEN RAISE EXCEPTION 'Informe a justificativa.' USING ERRCODE = '22023'; END IF;
    SELECT * INTO d FROM gestao.dataset_versoes WHERE id = p_dataset FOR UPDATE;
    IF d.id IS NULL THEN RAISE EXCEPTION 'Carga não encontrada.' USING ERRCODE = 'P0002'; END IF;
    IF d.status = 'ativa' THEN RETURN jsonb_build_object('ok', true, 'idempotente', true); END IF;
    IF d.status NOT IN ('validada', 'inativa') THEN
        RAISE EXCEPTION 'Só cargas validadas podem ser ativadas (situação atual: %).', d.status USING ERRCODE = '42501';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtext('pnite_carga_' || d.fonte));
    UPDATE gestao.dataset_versoes SET status = 'inativa' WHERE fonte = d.fonte AND status = 'ativa' RETURNING id INTO v_ant;
    UPDATE gestao.dataset_versoes SET status = 'ativa', ativada_em = now(), ativada_por = v_admin WHERE id = d.id;
    PERFORM catalogo.auditar(v_admin, 'ativar_carga', 'dataset_versao', d.id::text,
        jsonb_build_object('anterior', v_ant), jsonb_build_object('fonte', d.fonte, 'sha256', d.sha256), p_justificativa);
    RETURN jsonb_build_object('ok', true, 'anterior', v_ant);
END $$;

CREATE OR REPLACE FUNCTION public.pnite_admin_pendencia_decidir(p_id bigint, p_situacao text, p_decisao text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_admin text := acesso.exigir_admin(); q gestao.pendencias_qualidade;
BEGIN
    IF p_situacao NOT IN ('aberta', 'aceita', 'resolvida') OR NULLIF(btrim(p_decisao), '') IS NULL THEN
        RAISE EXCEPTION 'Informe a situação e a decisão.' USING ERRCODE = '22023';
    END IF;
    SELECT * INTO q FROM gestao.pendencias_qualidade WHERE id = p_id FOR UPDATE;
    IF q.id IS NULL THEN RAISE EXCEPTION 'Pendência não encontrada.' USING ERRCODE = 'P0002'; END IF;
    UPDATE gestao.pendencias_qualidade SET situacao = p_situacao, decisao = p_decisao, decidido_por = v_admin, decidido_em = now()
     WHERE id = p_id;
    PERFORM catalogo.auditar(v_admin, 'decidir_pendencia', 'pendencia_qualidade', p_id::text,
        jsonb_build_object('situacao', q.situacao), jsonb_build_object('situacao', p_situacao), p_decisao);
    RETURN jsonb_build_object('ok', true);
END $$;

CREATE OR REPLACE FUNCTION public.pnite_admin_auditoria(p_limite integer DEFAULT 50, p_offset integer DEFAULT 0,
                                                        p_entidade text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    PERFORM acesso.exigir_admin();
    RETURN jsonb_build_object(
        'total', (SELECT count(*) FROM catalogo.auditoria WHERE p_entidade IS NULL OR entidade = p_entidade),
        'linhas', (SELECT COALESCE(jsonb_agg(to_jsonb(a) ORDER BY a.em DESC, a.id DESC), '[]') FROM (
            SELECT * FROM catalogo.auditoria WHERE p_entidade IS NULL OR entidade = p_entidade
            ORDER BY em DESC, id DESC OFFSET GREATEST(COALESCE(p_offset, 0), 0)
            LIMIT LEAST(GREATEST(COALESCE(p_limite, 50), 1), 200)) a));
END $$;

-- Permissões
REVOKE ALL ON FUNCTION
    public.pnite_catalogo_publicado(text), public.pnite_indicador_valor(text, jsonb), public.pnite_ce_painel(jsonb),
    public.pnite_ce_detalhe(jsonb, text, integer, integer, text), public.pnite_snapshot_painel(text),
    public.pnite_admin_cat_listar(), public.pnite_admin_cat_criar(text, text, text, text, text, text, integer, jsonb),
    public.pnite_admin_cat_nova_versao(bigint), public.pnite_admin_cat_editar(bigint, integer, jsonb),
    public.pnite_admin_cat_transicao(bigint, text, integer, text), public.pnite_admin_cat_previa(bigint, jsonb),
    public.pnite_admin_cargas(), public.pnite_admin_carga_ativar(bigint, text),
    public.pnite_admin_pendencia_decidir(bigint, text, text), public.pnite_admin_auditoria(integer, integer, text)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION
    public.pnite_catalogo_publicado(text), public.pnite_indicador_valor(text, jsonb), public.pnite_ce_painel(jsonb),
    public.pnite_ce_detalhe(jsonb, text, integer, integer, text), public.pnite_snapshot_painel(text)
TO anon, authenticated;
GRANT EXECUTE ON FUNCTION
    public.pnite_admin_cat_listar(), public.pnite_admin_cat_criar(text, text, text, text, text, text, integer, jsonb),
    public.pnite_admin_cat_nova_versao(bigint), public.pnite_admin_cat_editar(bigint, integer, jsonb),
    public.pnite_admin_cat_transicao(bigint, text, integer, text), public.pnite_admin_cat_previa(bigint, jsonb),
    public.pnite_admin_cargas(), public.pnite_admin_carga_ativar(bigint, text),
    public.pnite_admin_pendencia_decidir(bigint, text, text), public.pnite_admin_auditoria(integer, integer, text)
TO authenticated;
