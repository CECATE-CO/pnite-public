# PNITE — Backlog

Pendências levantadas na revisão geral da v.3.4.5 (19/11/2026) que **não** foram resolvidas nessa versão.
O que foi corrigido está no histórico do Git e na nota de versão do `PNITE.html`.

## 1. Decisões metodológicas (dependem do responsável pela PNITE)

Divergências entre partes do código sobre o mesmo indicador. Não foram alteradas (AGENTS.md §11, §33 e §44.4).

| Item | Divergência | Onde |
|---|---|---|
| PAD | A memória de cálculo divide por alunos **transportados**; o painel, o mapa e o banco dividem por alunos **cadastrados**. A calculadora diz "cadastrados" e o catálogo diz "transportado". | `renderMemoria`, `CALC_DEFS.PAD`, `ALL_INDICATORS`, `analise.calcular_indicadores` |
| ATE | A memória usa o Censo (⌈alunos ÷ escolas atendidas⌉); o painel usa o SETE (`al_transp_sete ÷ esc_at`). Também segue aberta a diferença do denominador de maio (27.751 × 29.525 escolas). | `renderMemoria`, `CALC_DEFS.ATE`, banco |
| PMVE / PMNVE | O rótulo diz "Total de monitores cadastrados", mas o dado é "com vínculo informado" (o dos motoristas já diz isso). | `renderMemoria`, `CALC_DEFS` |
| Cores do mapa | PMNVE sai em âmbar e PMVE em verde; o texto "Como interpretar" cita uma cor fixa diferente da escala real em alguns indicadores (ex.: PCSC). | `getMapaTheme`, `MAPA_INFO_DICT` |
| Monitoramento SETE | Nas abas Alunos, Veículos e Rotas, município sem dado aparece como 0 (na aba Gerais aparece "sem dados"). | `smRender`, `smTabelaMun` |
| Capacitação 6–16 | O filtro "Tipo da resposta" muda o gráfico, mas não o cartão "Respostas abertas". | `capRenderStat616` |
| Downloads de cartões e painéis | Funcionam sem login; as demais exportações exigem a permissão de download. Definir se é intencional. | `pniteBaixarCardIndicador`, `pniteBaixarPainelCompleto`, `pniteBaixarPainelExcel` |
| TETI | Regra a definir (o vínculo rota × veículo cobre 55% dos transportados). | — |
| Catálogo | Os 30 indicadores em revisão estão sem responsável, o que impede aprovar. | Gerenciador de indicadores |

## 2. Defeitos conhecidos, ainda sem correção

**Exportações**
- PNG do mapa: o mapa sai esticado, a caixa do mini-mapa sai vazia e não há legenda de cores (`exportarMapaPnite`).
- Botão "baixar a caixa do gráfico": título genérico e fonte errada nos gráficos da Capacitação e da Gestão; aparece em cartões sem gráfico; duplica o botão do plugin de download (`pniteBaixarGraficoCard`, `setupChartDownloadButtons`).
- Excel dos painéis grava os valores como texto ("37.6%"), não como número.

**Mapa**
- Seleção territorial personalizada: a busca se perde ao marcar um item, "Cancelar" não desfaz as marcações e Esc não fecha a janela.
- Cartão de comparação no recorte regional ainda fala em "Panorama Territorial Nacional", "Liderança Nacional" e "27 Unidades da Federação"; a "Liderança" fica em verde também nos indicadores em que o ideal é 0%.
- Itens clicáveis sem `role="button"` e `tabindex`: `.map-subdiv-legend-item` e `.mpt-region-head`.

**Idioma**
- A troca de idioma sobrescreve textos que dependem do estado da tela: botão do guia, título do mapa e botão "Brasil/Estados" (`setLanguage`).

**Login e usuários**
- Na lista de usuários, salvar uma linha descarta as alterações não salvas das outras.
- Falha de rede ao consultar o acesso é tratada como "sem autorização"; nesse estado, "Editar perfil" diz "Perfil atualizado" sem gravar.

**Limpeza**
- Código sem uso que restou: variáveis `chartModal`, `chartFrota`, `chartPRGM`, `chartFrotaEstado`, `currentIndTab`, `currentGiTab`, `MG_CITY_LABELS`, `TIPO_LABEL`, `mapaInited`, `mapaSelected`, `mapaLastLevel`, `isZoomAnimating`, `targetPrgm`; funções `st` e `drawScaleBarOnCanvas` (vazia); ramos do tema `dim`; contêiner "ELEMENTOS DE COMPATIBILIDADE" (o `regionSelect` ainda é lido).

## 3. Scripts de carga

- Lotes não idempotentes: uma falha de rede depois de o banco confirmar o lote, ou um `--retomar`, pode duplicar linhas. Hoje isso só aparece na conferência final (`DIVERGENTE`, inclusive para os traçados). Solução: gravar o checkpoint no banco, na mesma requisição do lote.
- `importar_planilha.py`: uma coluna com valores como `1.234` (milhar brasileiro, sem decimais) é lida como decimal (1,234).
- `importar_caminho_escola.py`: uma carga que falhou no meio agora gera erro explícito, mas a limpeza da versão incompleta ainda é manual.
- Scripts fora de uso, a remover: `pegar_dado_rota.py`, `pegar_dado_rota.js` e `agrega_ind.py`.
- A conferência dos traçados (`sete.rota_shape`) e as demais proteções novas do carregador foram testadas com a tabela `normas`; falta exercitá-las numa carga real de `rotas`.

## 4. Evolução dos Indicadores (aba nova)

- Exportar a série (CSV e PNG).
- Indicar o sentido de cada indicador (se subir é bom ou ruim) para colorir as variações.
- Traduzir a aba (hoje só em português, como o Comparativo).
- Leitura dos pontos do gráfico pelo teclado (hoje os valores estão na tabela abaixo dele).

## 5. Dados que faltam para indicadores em construção

- PRPM e IPE: a extração do SETE não traz vínculo entre rota e monitor.
- DMC: não há pontos de embarque.
- PVRO e PVCED: a base do FNDE é de contratações, sem placa ou chassi, e não há registro de baixas.
- PRPNP: não há tipo de pavimento.

## 6. Operação

- O site publicado precisa estar na v.3.3.7 ou posterior para lidar com mais de uma carga do SETE.
- Os testes do gerenciador de indicadores e do login foram feitos com respostas simuladas; falta um teste com uma conta real de administrador.
