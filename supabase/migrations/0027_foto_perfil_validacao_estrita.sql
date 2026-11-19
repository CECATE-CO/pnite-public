-- ============================================================================
-- PNITE — 0027: validação estrita da foto de perfil
-- ----------------------------------------------------------------------------
-- A 0017 só conferia o início do texto ('^data:image/(jpeg|png|webp);base64,'). Como a foto é
-- gravada pelo próprio usuário (public.pnite_atualizar_perfil) e depois exibida na lista de
-- usuários do administrador, um valor com aspas depois do prefixo podia injetar atributos no
-- <img> da interface. A partir daqui o valor inteiro precisa ser um data URI de imagem em
-- base64 (letras, dígitos, + e /, com até dois = no fim), no CHECK da tabela e na RPC.
-- A interface (v.3.4.5) passou a exigir o mesmo padrão e a escapar o valor.
-- Nenhuma foto gravada foge do novo padrão (conferido antes de aplicar: 0 fotos no banco).
-- ============================================================================

ALTER TABLE acesso.autorizacoes DROP CONSTRAINT IF EXISTS autorizacoes_foto_check;
ALTER TABLE acesso.autorizacoes ADD CONSTRAINT autorizacoes_foto_check
    CHECK (foto IS NULL OR (foto ~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/]+={0,2}$' AND length(foto) <= 200000));

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
    IF p_foto IS NOT NULL AND (p_foto !~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/]+={0,2}$' OR length(p_foto) > 200000) THEN
        RAISE EXCEPTION 'Foto inválida ou grande demais.' USING ERRCODE = '22023';
    END IF;
    UPDATE acesso.autorizacoes SET
        nome = CASE WHEN p_nome IS NULL THEN nome ELSE NULLIF(btrim(p_nome), '') END,
        foto = CASE WHEN p_remover_foto THEN NULL ELSE COALESCE(p_foto, foto) END,
        atualizado_em = now(), atualizado_por = v_email
    WHERE email = v_email;
    RETURN public.pnite_meu_acesso();
END $$;
