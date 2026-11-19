-- ============================================================================
-- PNITE — 0026: exclusão do visual SETE_PAINEL_SNAPSHOT do catálogo
-- ----------------------------------------------------------------------------
-- A pedido do administrador (19/11/2026), sai do catálogo o visual "Acompanhamento SETE —
-- fotografia do painel FNDE" (Transporte › Monitoramento SETE), em rascunho e sem publicação.
-- A exclusão fica na trilha de auditoria com a definição completa, o que permite recriá-lo.
-- Efeito: pnite_snapshot_painel('sete') só devolve a fotografia com o visual publicado; o
-- Monitoramento SETE continua mostrando "Fotografia FNDE: não publicada", como hoje.
-- O snapshot em gestao.snapshots_paineis não é tocado.
-- ============================================================================

DO $$
DECLARE i catalogo.indicadores;
BEGIN
  IF EXISTS (SELECT 1 FROM catalogo.publicacoes p JOIN catalogo.indicadores x ON x.id = p.indicador_id WHERE x.codigo = 'SETE_PAINEL_SNAPSHOT') THEN
    RAISE EXCEPTION 'Há publicação registrada para SETE_PAINEL_SNAPSHOT; exclusão cancelada.';
  END IF;
  FOR i IN SELECT * FROM catalogo.indicadores WHERE codigo = 'SETE_PAINEL_SNAPSHOT' LOOP
    PERFORM catalogo.auditar('migracao 0026', 'excluir_indicador', 'indicador', i.id::text,
      to_jsonb(i) || jsonb_build_object('versoes',
        (SELECT jsonb_agg(to_jsonb(v) ORDER BY v.versao) FROM catalogo.indicador_versoes v WHERE v.indicador_id = i.id)),
      NULL, 'Exclusão do visual do Monitoramento SETE a pedido do administrador da PNITE (19/11/2026).');
    DELETE FROM catalogo.indicador_versoes WHERE indicador_id = i.id;
    DELETE FROM catalogo.indicadores WHERE id = i.id;
  END LOOP;
END $$;
