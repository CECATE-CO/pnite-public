-- ============================================================================
-- PNITE — 0015: Login de usuários e controle de acesso (downloads)
-- ----------------------------------------------------------------------------
-- Os usuários são os do Supabase Auth (auth.users). A plataforma continua
-- pública para consulta; o login libera o download de gráficos, tabelas,
-- indicadores e mapa para quem tiver permissão.
--
-- * acesso.autorizacoes: lista de e-mails autorizados pelo administrador
--   (papel, permissão de download e situação). Só e-mails autorizados podem
--   criar conta (gatilho em auth.users).
-- * acesso.perfis: um perfil por conta criada, sincronizado com a autorização.
-- * morato@ufg.br é o administrador inicial: gerencia o acesso de todos os
--   demais usuários pelas funções public.pnite_admin_* (RPC da API).
--
-- Schema privado (sem GRANT a anon/authenticated): a leitura e a escrita
-- passam apenas pelas funções SECURITY DEFINER abaixo, que conferem o papel.
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS acesso;
COMMENT ON SCHEMA acesso IS 'PNITE — Usuários, papéis e permissões de download (privado; acesso via RPC public.pnite_*).';
REVOKE ALL ON SCHEMA acesso FROM PUBLIC, anon, authenticated;

CREATE TABLE acesso.autorizacoes (
    email          text        PRIMARY KEY CHECK (email = lower(btrim(email)) AND email LIKE '%_@_%'),
    nome           text,
    papel          text        NOT NULL DEFAULT 'usuario' CHECK (papel IN ('admin', 'usuario')),
    pode_baixar    boolean     NOT NULL DEFAULT true,
    ativo          boolean     NOT NULL DEFAULT true,
    criado_em      timestamptz NOT NULL DEFAULT now(),
    atualizado_em  timestamptz NOT NULL DEFAULT now(),
    atualizado_por text
);
COMMENT ON TABLE acesso.autorizacoes IS 'E-mails autorizados a criar conta na PNITE, com papel e permissão de download.';

CREATE TABLE acesso.perfis (
    user_id   uuid        PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
    email     text        NOT NULL UNIQUE REFERENCES acesso.autorizacoes (email) ON UPDATE CASCADE ON DELETE CASCADE,
    criado_em timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE acesso.perfis IS 'Contas do Supabase Auth vinculadas a uma autorização.';

-- Administrador inicial
INSERT INTO acesso.autorizacoes (email, nome, papel, pode_baixar, ativo, atualizado_por)
VALUES ('morato@ufg.br', 'Administrador PNITE', 'admin', true, true, 'migração 0015')
ON CONFLICT (email) DO UPDATE SET papel = 'admin', pode_baixar = true, ativo = true;

-- Vincula contas já existentes que tenham autorização
INSERT INTO acesso.perfis (user_id, email)
SELECT u.id, lower(u.email) FROM auth.users u
JOIN acesso.autorizacoes a ON a.email = lower(u.email)
ON CONFLICT DO NOTHING;

-- ----------------------------------------------------------------------------
-- Gatilho: só e-mails autorizados criam conta; a conta recebe o perfil.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION acesso.ao_criar_usuario()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    v_email text := lower(btrim(NEW.email));
BEGIN
    IF NOT EXISTS (SELECT 1 FROM acesso.autorizacoes WHERE email = v_email AND ativo) THEN
        RAISE EXCEPTION 'E-mail não autorizado na PNITE. Solicite acesso ao administrador.'
            USING ERRCODE = 'P0001';
    END IF;
    INSERT INTO acesso.perfis (user_id, email) VALUES (NEW.id, v_email)
    ON CONFLICT (user_id) DO UPDATE SET email = EXCLUDED.email;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS pnite_ao_criar_usuario ON auth.users;
CREATE TRIGGER pnite_ao_criar_usuario
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION acesso.ao_criar_usuario();

-- Situação do usuário autenticado (NULL quando não há sessão ou autorização)
CREATE OR REPLACE FUNCTION acesso.usuario_atual()
RETURNS acesso.autorizacoes LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
    SELECT a.* FROM acesso.perfis p
    JOIN acesso.autorizacoes a ON a.email = p.email
    WHERE p.user_id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION acesso.exigir_admin()
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    v acesso.autorizacoes;
BEGIN
    v := acesso.usuario_atual();
    IF v.email IS NULL OR v.papel <> 'admin' OR NOT v.ativo THEN
        RAISE EXCEPTION 'Acesso restrito ao administrador da PNITE.' USING ERRCODE = '42501';
    END IF;
    RETURN v.email;
END $$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA acesso FROM PUBLIC, anon, authenticated;

-- ----------------------------------------------------------------------------
-- API (RPC) — public.pnite_*
-- ----------------------------------------------------------------------------

-- Acesso do usuário logado: {email, nome, papel, pode_baixar, ativo}
CREATE OR REPLACE FUNCTION public.pnite_meu_acesso()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
    SELECT jsonb_build_object('email', a.email, 'nome', a.nome, 'papel', a.papel,
                              'pode_baixar', a.pode_baixar AND a.ativo, 'ativo', a.ativo)
    FROM acesso.perfis p JOIN acesso.autorizacoes a ON a.email = p.email
    WHERE p.user_id = auth.uid();
$$;

-- Lista de autorizações com a situação da conta (somente administrador)
CREATE OR REPLACE FUNCTION public.pnite_admin_listar_usuarios()
RETURNS TABLE (email text, nome text, papel text, pode_baixar boolean, ativo boolean,
               conta_criada boolean, ultimo_acesso timestamptz, atualizado_em timestamptz, atualizado_por text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    PERFORM acesso.exigir_admin();
    RETURN QUERY
    SELECT a.email, a.nome, a.papel, a.pode_baixar, a.ativo,
           (p.user_id IS NOT NULL), u.last_sign_in_at, a.atualizado_em, a.atualizado_por
    FROM acesso.autorizacoes a
    LEFT JOIN acesso.perfis p ON p.email = a.email
    LEFT JOIN auth.users u ON u.id = p.user_id
    ORDER BY (a.papel = 'admin') DESC, a.email;
END $$;

-- Cria ou altera uma autorização (somente administrador)
CREATE OR REPLACE FUNCTION public.pnite_admin_definir_acesso(
    p_email text, p_papel text DEFAULT 'usuario', p_pode_baixar boolean DEFAULT true,
    p_ativo boolean DEFAULT true, p_nome text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    v_admin text := acesso.exigir_admin();
    v_email text := lower(btrim(p_email));
BEGIN
    IF v_email IS NULL OR v_email NOT LIKE '%_@_%' THEN
        RAISE EXCEPTION 'Informe um e-mail válido.' USING ERRCODE = '22023';
    END IF;
    IF p_papel NOT IN ('admin', 'usuario') THEN
        RAISE EXCEPTION 'Papel inválido: %.', p_papel USING ERRCODE = '22023';
    END IF;
    -- O administrador não pode retirar o próprio acesso de administrador
    IF v_email = v_admin AND (p_papel <> 'admin' OR NOT p_ativo) THEN
        RAISE EXCEPTION 'Você não pode remover o seu próprio acesso de administrador.' USING ERRCODE = '42501';
    END IF;
    INSERT INTO acesso.autorizacoes AS a (email, nome, papel, pode_baixar, ativo, atualizado_por)
    VALUES (v_email, NULLIF(btrim(p_nome), ''), p_papel, p_pode_baixar, p_ativo, v_admin)
    ON CONFLICT (email) DO UPDATE SET
        nome = COALESCE(NULLIF(btrim(p_nome), ''), a.nome),
        papel = EXCLUDED.papel, pode_baixar = EXCLUDED.pode_baixar, ativo = EXCLUDED.ativo,
        atualizado_em = now(), atualizado_por = v_admin;
END $$;

-- Remove uma autorização e a conta vinculada (somente administrador)
CREATE OR REPLACE FUNCTION public.pnite_admin_remover_usuario(p_email text)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    v_admin text := acesso.exigir_admin();
    v_email text := lower(btrim(p_email));
BEGIN
    IF v_email = v_admin THEN
        RAISE EXCEPTION 'Você não pode remover a sua própria conta.' USING ERRCODE = '42501';
    END IF;
    DELETE FROM auth.users WHERE id IN (SELECT user_id FROM acesso.perfis WHERE email = v_email);
    DELETE FROM acesso.autorizacoes WHERE email = v_email;
END $$;

REVOKE ALL ON FUNCTION public.pnite_meu_acesso(), public.pnite_admin_listar_usuarios(),
    public.pnite_admin_definir_acesso(text, text, boolean, boolean, text),
    public.pnite_admin_remover_usuario(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pnite_meu_acesso(), public.pnite_admin_listar_usuarios(),
    public.pnite_admin_definir_acesso(text, text, boolean, boolean, text),
    public.pnite_admin_remover_usuario(text) TO authenticated;
