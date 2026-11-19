-- ============================================================================
-- PNITE — 0023: referência calculada só onde a carga não tem planilha consolidada
-- ----------------------------------------------------------------------------
-- Na 0022, analise.referencia_calculada completava as chaves ausentes da referência
-- legada. As 5 regiões não têm esc_at em ref.raw_referencia (o ATE regional era "—") e
-- passaram a receber o esc_at calculado do SETE, uma regra diferente da usada nas UFs.
-- A referência calculada passa a valer só para o escopo/carga SEM linha em
-- ref.raw_referencia (cargas novas, como novembro/2026): a carga de maio/2026 volta a ser
-- idêntica à anterior. A função lê ref.raw_referencia, por isso deixa de ser IMMUTABLE.
-- ============================================================================

CREATE OR REPLACE FUNCTION analise.referencia_calculada(c jsonb, mifce numeric, medate numeric) RETURNS jsonb
LANGUAGE sql STABLE PARALLEL SAFE AS $$
  SELECT CASE WHEN EXISTS (
             SELECT 1 FROM ref.raw_referencia rr
              WHERE rr.carga = (c ->> 'carga')::integer
                AND rr.chave = coalesce(c ->> 'uf', c ->> 'regiao', 'nacional'))
         THEN '{}'::jsonb
         ELSE jsonb_strip_nulls(jsonb_build_object(
           'ce_veic',              c -> 'ce_veic_sete',
           'esc_at',               c -> 'esc_at_sete',
           'cs_tmun',              c -> 'censo_mun',
           'cs_test',              c -> 'censo_est',
           'cs_transp',            analise.num(c, 'censo_mun') + analise.num(c, 'censo_est'),
           'cs_escolas_atendidas', c -> 'censo_esc_transp',
           'medate_n',             c -> 'censo_esc_transp',
           'medate_val',           medate,
           'imfp', CASE WHEN analise.num(c, 'idade_prop_n') > 0
                        THEN analise.round_par((analise.num(c, 'idade_prop_soma') / analise.num(c, 'idade_prop_n'))::float8, 1) END,
           'imft', CASE WHEN analise.num(c, 'idade_terc_n') > 0
                        THEN analise.round_par((analise.num(c, 'idade_terc_soma') / analise.num(c, 'idade_terc_n'))::float8, 1) END,
           'mifce', mifce))
         END
$$;
COMMENT ON FUNCTION analise.referencia_calculada(jsonb, numeric, numeric) IS
  'Valores de referência (ce_veic, esc_at, cs_*, medate_*, imfp, imft, mifce) calculados dos contadores de um nível; só para escopo/carga sem linha em ref.raw_referencia.';

SELECT pnite_meta.atualizar_indicadores();
