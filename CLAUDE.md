# PNITE — instruções para o Claude Code

As diretrizes completas do projeto estão em `AGENTS.md` (idêntico a `.agents/rules/DIRETRIZES_AGENTE_PNITE.md`) e valem integralmente aqui:

@AGENTS.md

## Pasta `upload/` (resumo da §45)

- Recebe planilhas de capacitação e de outras fontes para envio ao Supabase; o conteúdo fica fora do Git (só `upload/README.md` é versionado) porque pode conter dados pessoais.
- Envio: `python scripts/importar_planilha.py --simular` e depois `python scripts/importar_planilha.py` (uma tabela por arquivo no schema privado `importacao`).
- A estrutura e o tratamento de cada planilha serão definidos pelo usuário caso a caso e registrados na §45 do `AGENTS.md`.
