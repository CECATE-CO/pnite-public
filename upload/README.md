# Pasta `upload/` — planilhas para envio ao banco

Coloque aqui as planilhas (CSV, TSV, TXT, XLSX, XLSM, XLS, ODS) de capacitação ou de outras fontes
que devem ser enviadas ao Supabase. Subpastas são permitidas (ex.: `upload/capacitacao/`).

**O conteúdo desta pasta não vai para o Git** (só este README): as planilhas podem conter dados
pessoais (nomes, CPF, e-mails).

## Envio

Na raiz do repositório, com o `.env` preenchido:

```bash
python scripts/importar_planilha.py --simular           # confere colunas e tipos, sem enviar
python scripts/importar_planilha.py                     # envia: cada arquivo vira importacao.<nome_do_arquivo>
python scripts/importar_planilha.py --modo substituir   # reenvia, recriando as tabelas
```

As tabelas ficam no schema privado `importacao`, sem acesso pela API pública.

## Regras por planilha

Este envio é genérico: a estrutura de cada tabela é inferida do próprio arquivo. A estrutura esperada
de cada planilha e o tratamento específico (tabela de destino, colunas, anonimização) serão definidos
planilha a planilha e registrados na seção "Pasta `upload/`" do `AGENTS.md`.
