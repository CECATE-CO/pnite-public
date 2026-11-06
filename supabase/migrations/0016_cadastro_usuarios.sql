-- ============================================================================
-- PNITE — 0016: Cadastro de usuários pela própria PNITE (página "Usuários")
-- ----------------------------------------------------------------------------
-- O administrador cria a conta completa (e-mail confirmado + senha inicial)
-- sem passar pelo e-mail de confirmação, redefine senhas e desativa contas.
-- A conta é gravada no Supabase Auth (auth.users + auth.identities) com senha
-- bcrypt (pgcrypto), no mesmo formato usado pelo GoTrue.
-- Conta desativada recebe banned_until no Auth: o login passa a ser recusado.
-- ============================================================================

CREATE OR REPLACE FUNCTION acesso.validar_senha(p_senha text)
RETURNS void LANGUAGE plpgsql IMMUTABLE SET search_path = '' AS $$
BEGIN
    IF p_senha IS NULL OR length(p_senha) < 8 THEN
        RAISE EXCEPTION 'A senha deve ter pelo menos 8 caracteres.' USING ERRCODE = '22023';
    END IF;
END $$;

CREATE OR REPLACE FUNCTION acesso.aplicar_bloqueio(p_email text, p_ativo boolean)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
    UPDATE auth.users SET banned_until = CASE WHEN p_ativo THEN NULL ELSE now() + interval '100 years' END,
                          updated_at = now()
    WHERE id IN (SELECT user_id FROM acesso.perfis WHERE email = lower(btrim(p_email)));
$$;
REVOKE ALL ON FUNCTION acesso.validar_senha(text), acesso.aplicar_bloqueio(text, boolean) FROM PUBLIC, anon, authenticated;

-- Autorização (redefinida para também bloquear/desbloquear a conta no Auth)
CREATE OR REPLACE FUNCTION public.pnite_admin_definir_acesso(
    p_email text, p_papel text DEFAULT 'usuario', p_pode_baixar boolean DEFAULT true,
    p_ativo boolean DEFAULT true, p_nome text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    v_admin text := acesso.exigir_admin();
    v_email text := lower(btrim(p_email));
BEGIN
    IF v_email IS NULL OR v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN
        RAISE EXCEPTION 'Informe um e-mail válido.' USING ERRCODE = '22023';
    END IF;
    IF p_papel NOT IN ('admin', 'usuario') THEN
        RAISE EXCEPTION 'Papel inválido: %.', p_papel USING ERRCODE = '22023';
    END IF;
    IF v_email = v_admin AND (p_papel <> 'admin' OR NOT p_ativo) THEN
        RAISE EXCEPTION 'Você não pode remover o seu próprio acesso de administrador.' USING ERRCODE = '42501';
    END IF;
    INSERT INTO acesso.autorizacoes AS a (email, nome, papel, pode_baixar, ativo, atualizado_por)
    VALUES (v_email, NULLIF(btrim(p_nome), ''), p_papel, p_pode_baixar, p_ativo, v_admin)
    ON CONFLICT (email) DO UPDATE SET
        nome = COALESCE(NULLIF(btrim(p_nome), ''), a.nome),
        papel = EXCLUDED.papel, pode_baixar = EXCLUDED.pode_baixar, ativo = EXCLUDED.ativo,
        atualizado_em = now(), atualizado_por = v_admin;
    PERFORM acesso.aplicar_bloqueio(v_email, p_ativo);
END $$;

-- Cria a conta completa (autorização + usuário confirmado com senha inicial)
CREATE OR REPLACE FUNCTION public.pnite_admin_criar_usuario(
    p_email text, p_senha text, p_nome text DEFAULT NULL, p_papel text DEFAULT 'usuario',
    p_pode_baixar boolean DEFAULT true)
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    v_email text := lower(btrim(p_email));
    v_id    uuid := gen_random_uuid();
BEGIN
    PERFORM acesso.exigir_admin();
    PERFORM acesso.validar_senha(p_senha);
    IF EXISTS (SELECT 1 FROM auth.users WHERE lower(email) = v_email) THEN
        RAISE EXCEPTION 'Já existe uma conta com este e-mail. Use "Redefinir senha" na lista.' USING ERRCODE = '23505';
    END IF;
    -- Autoriza antes de criar (o gatilho de auth.users exige autorização ativa)
    PERFORM public.pnite_admin_definir_acesso(v_email, p_papel, p_pode_baixar, true, p_nome);

    INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                            raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                            confirmation_token, recovery_token, email_change_token_new, email_change)
    VALUES ('00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', v_email,
            extensions.crypt(p_senha, extensions.gen_salt('bf', 10)), now(),
            jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
            jsonb_build_object('nome', NULLIF(btrim(p_nome), ''), 'email_verified', true),
            now(), now(), '', '', '', '');

    INSERT INTO auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    VALUES (v_id::text, v_id,
            jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true, 'phone_verified', false),
            'email', now(), now(), now());
    RETURN v_id;
END $$;

-- Redefine a senha de uma conta existente (somente administrador)
CREATE OR REPLACE FUNCTION public.pnite_admin_definir_senha(p_email text, p_senha text)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    v_n integer;
BEGIN
    PERFORM acesso.exigir_admin();
    PERFORM acesso.validar_senha(p_senha);
    UPDATE auth.users SET encrypted_password = extensions.crypt(p_senha, extensions.gen_salt('bf', 10)),
                          email_confirmed_at = COALESCE(email_confirmed_at, now()), updated_at = now()
    WHERE id IN (SELECT user_id FROM acesso.perfis WHERE email = lower(btrim(p_email)));
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n = 0 THEN
        RAISE EXCEPTION 'Este e-mail ainda não tem conta criada.' USING ERRCODE = 'P0002';
    END IF;
END $$;

-- Lista com data de cadastro e confirmação de e-mail
DROP FUNCTION IF EXISTS public.pnite_admin_listar_usuarios();
CREATE FUNCTION public.pnite_admin_listar_usuarios()
RETURNS TABLE (email text, nome text, papel text, pode_baixar boolean, ativo boolean,
               conta_criada boolean, email_confirmado boolean, ultimo_acesso timestamptz,
               criado_em timestamptz, atualizado_em timestamptz, atualizado_por text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    PERFORM acesso.exigir_admin();
    RETURN QUERY
    SELECT a.email, a.nome, a.papel, a.pode_baixar, a.ativo,
           (p.user_id IS NOT NULL), (u.email_confirmed_at IS NOT NULL), u.last_sign_in_at,
           a.criado_em, a.atualizado_em, a.atualizado_por
    FROM acesso.autorizacoes a
    LEFT JOIN acesso.perfis p ON p.email = a.email
    LEFT JOIN auth.users u ON u.id = p.user_id
    ORDER BY (a.papel = 'admin') DESC, a.email;
END $$;

REVOKE ALL ON FUNCTION public.pnite_admin_listar_usuarios(),
    public.pnite_admin_definir_acesso(text, text, boolean, boolean, text),
    public.pnite_admin_criar_usuario(text, text, text, text, boolean),
    public.pnite_admin_definir_senha(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pnite_admin_listar_usuarios(),
    public.pnite_admin_definir_acesso(text, text, boolean, boolean, text),
    public.pnite_admin_criar_usuario(text, text, text, text, boolean),
    public.pnite_admin_definir_senha(text, text) TO authenticated;
