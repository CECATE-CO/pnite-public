# PNITE — instruções para o Claude Code

As diretrizes completas do projeto estão em `AGENTS.md` (idêntico a `.agents/rules/DIRETRIZES_AGENTE_PNITE.md`) e valem integralmente aqui:

@AGENTS.md

## Pasta `upload/` (resumo da §45)

- Recebe planilhas de capacitação e de outras fontes para envio ao Supabase; o conteúdo fica fora do Git (só `upload/README.md` é versionado) porque pode conter dados pessoais.
- Envio: `python scripts/importar_planilha.py --simular` e depois `python scripts/importar_planilha.py` (uma tabela por arquivo no schema privado `importacao`).
- A estrutura e o tratamento de cada planilha serão definidos pelo usuário caso a caso e registrados na §45 do `AGENTS.md`.
- Extrações do SETE ficam em `upload/sete/AAAA-MM/` (fora do `importar_planilha.py`) e vão ao banco por `python scripts/criar_banco_dados_brutos.py --carga AAAA-MM --pasta upload/sete/AAAA-MM` + `python scripts/atualizar_indicadores.py`.
- Microdados do Censo Escolar ficam em `upload/censo/AAAA/` (um CSV do INEP por ano, fora do `importar_planilha.py`) e vão ao banco por `python scripts/criar_banco_dados_brutos.py --tabelas censo --censo-ano AAAA` + `python scripts/atualizar_indicadores.py`; cada ano vira um ponto da série "Anos do Censo Escolar" na aba Evolução.
