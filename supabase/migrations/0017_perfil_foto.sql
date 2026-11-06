-- ============================================================================
-- PNITE — 0017: Foto e edição do próprio perfil
-- ----------------------------------------------------------------------------
-- A foto é uma imagem pequena (recortada e reduzida para 256×256 px no
-- navegador) guardada como data URL JPEG/PNG/WebP em acesso.autorizacoes.foto.
-- Cada usuário edita apenas o próprio nome e foto (public.pnite_atualizar_perfil);
-- a senha é trocada pela API do Supabase Auth (PUT /auth/v1/user).
-- ============================================================================

ALTER TABLE acesso.autorizacoes
    ADD COLUMN IF NOT EXISTS foto text
    CHECK (foto IS NULL OR (foto ~ '^data:image/(jpeg|png|webp);base64,' AND length(foto) <= 200000));
COMMENT ON COLUMN acesso.autorizacoes.foto IS 'Foto do perfil (data URL, até ~150 KB).';

CREATE OR REPLACE FUNCTION public.pnite_meu_acesso()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
    SELECT jsonb_build_object('email', a.email, 'nome', a.nome, 'papel', a.papel, 'foto', a.foto,
                              'pode_baixar', a.pode_baixar AND a.ativo, 'ativo', a.ativo)
    FROM acesso.perfis p JOIN acesso.autorizacoes a ON a.email = p.email
    WHERE p.user_id = auth.uid();
$$;

-- O próprio usuário altera nome e foto (p_remover_foto = true apaga a foto)
CREATE OR REPLACE FUNCTION public.pnite_atualizar_perfil(
    p_nome text DEFAULT NULL, p_foto text DEFAULT NULL, p_remover_foto boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    v_email text;
BEGIN
    SELECT p.email INTO v_email FROM acesso.perfis p WHERE p.user_id = auth.uid();
    IF v_email IS NULL THEN
        RAISE EXCEPTION 'Conta sem autorização na PNITE.' USING ERRCODE = '42501';
    END IF;
    IF p_nome IS NOT NULL AND length(btrim(p_nome)) > 120 THEN
        RAISE EXCEPTION 'O nome deve ter até 120 caracteres.' USING ERRCODE = '22023';
    END IF;
    IF p_foto IS NOT NULL AND (p_foto !~ '^data:image/(jpeg|png|webp);base64,' OR length(p_foto) > 200000) THEN
        RAISE EXCEPTION 'Foto inválida ou grande demais.' USING ERRCODE = '22023';
    END IF;
    UPDATE acesso.autorizacoes SET
        nome = CASE WHEN p_nome IS NULL THEN nome ELSE NULLIF(btrim(p_nome), '') END,
        foto = CASE WHEN p_remover_foto THEN NULL ELSE COALESCE(p_foto, foto) END,
        atualizado_em = now(), atualizado_por = v_email
    WHERE email = v_email;
    RETURN public.pnite_meu_acesso();
END $$;

DROP FUNCTION IF EXISTS public.pnite_admin_listar_usuarios();
CREATE FUNCTION public.pnite_admin_listar_usuarios()
RETURNS TABLE (email text, nome text, papel text, pode_baixar boolean, ativo boolean,
               conta_criada boolean, email_confirmado boolean, ultimo_acesso timestamptz,
               criado_em timestamptz, atualizado_em timestamptz, atualizado_por text, foto text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    PERFORM acesso.exigir_admin();
    RETURN QUERY
    SELECT a.email, a.nome, a.papel, a.pode_baixar, a.ativo,
           (p.user_id IS NOT NULL), (u.email_confirmed_at IS NOT NULL), u.last_sign_in_at,
           a.criado_em, a.atualizado_em, a.atualizado_por, a.foto
    FROM acesso.autorizacoes a
    LEFT JOIN acesso.perfis p ON p.email = a.email
    LEFT JOIN auth.users u ON u.id = p.user_id
    ORDER BY (a.papel = 'admin') DESC, a.email;
END $$;

REVOKE ALL ON FUNCTION public.pnite_meu_acesso(), public.pnite_atualizar_perfil(text, text, boolean),
    public.pnite_admin_listar_usuarios() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pnite_meu_acesso(), public.pnite_atualizar_perfil(text, text, boolean),
    public.pnite_admin_listar_usuarios() TO authenticated;
