-- ============================================================================
-- PNITE — 0025: exclusão dos itens do catálogo Gestão › Caminho da Escola
-- ----------------------------------------------------------------------------
-- A pedido do administrador (19/11/2026), saem do catálogo os 9 itens cadastrados na 0019
-- para a frente Gestão › Caminho da Escola (6 indicadores e 3 visuais), todos em rascunho e
-- sem publicação. Cada exclusão fica na trilha de auditoria com a definição completa
-- (indicador e versões), o que permite recriar o item pelo gerenciador.
-- Efeito: os painéis da frente Gestão (pnite_ce_painel, pnite_ce_detalhe e o snapshot
-- 'caminho') só vão a público com o visual publicado; sem os visuais, continuam como hoje
-- ("não publicado") até que os itens sejam recriados e publicados.
-- Os dados (gestao.*) e o visual SETE_PAINEL_SNAPSHOT não são tocados.
-- ============================================================================

DO $$
DECLARE
  v_codigos text[] := ARRAY['CE_QTD_CONTRATADA', 'CE_VALOR_CONTRATADO', 'CE_PRECO_MEDIO_PONDERADO', 'CE_COBERTURA_ENTES',
                            'CE_COMPLETUDE_RP', 'CE_VALOR_PAGO', 'CE_PAINEL_CONTRATACOES', 'CE_DETALHAMENTO', 'CE_REPASSES_SNAPSHOT'];
  i catalogo.indicadores;
BEGIN
  IF EXISTS (SELECT 1 FROM catalogo.publicacoes p JOIN catalogo.indicadores x ON x.id = p.indicador_id WHERE x.codigo = ANY (v_codigos)) THEN
    RAISE EXCEPTION 'Há publicação registrada para algum item do Caminho da Escola; exclusão cancelada.';
  END IF;
  FOR i IN SELECT * FROM catalogo.indicadores WHERE codigo = ANY (v_codigos) ORDER BY ordem LOOP
    PERFORM catalogo.auditar('migracao 0025', 'excluir_indicador', 'indicador', i.id::text,
      to_jsonb(i) || jsonb_build_object('versoes',
        (SELECT jsonb_agg(to_jsonb(v) ORDER BY v.versao) FROM catalogo.indicador_versoes v WHERE v.indicador_id = i.id)),
      NULL, 'Exclusão dos itens do Caminho da Escola a pedido do administrador da PNITE (19/11/2026).');
    DELETE FROM catalogo.indicador_versoes WHERE indicador_id = i.id;
    DELETE FROM catalogo.indicadores WHERE id = i.id;
  END LOOP;
END $$;
