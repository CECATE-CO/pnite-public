# Scripts e Utilitários da PNITE

Conjunto de scripts Python e Node.js para processamento, extração, agregação e integração dos dados do transporte escolar e capacitações da PNITE.

---

## Estrutura dos Scripts

- **`scripts/extrair_dados_excel.py`**:
  Lê as planilhas consolidadas em `data/Transporte Escolar/`. Tem dois usos:
  - **Biblioteca da carga de referência** (em uso): `carregar_planilhas`, `extrair_metricas_por_uf` e `montar_raw_referencia` são chamadas por `criar_banco_dados_brutos.py --tabelas referencia` para gravar `ref.raw_referencia` e `ref.detalhes_scripts`.
  - **Execução direta** (legado): `python scripts/extrair_dados_excel.py` gera o pacote local `pnite_dados_consolidados.json`/`.js`, que a interface não lê mais (os indicadores vêm do Supabase); só o `validar_paridade.py` o utiliza. O cálculo dos indicadores foi portado para `analise.calcular_indicadores` no banco.

- **`scripts/criar_banco_dados_brutos.py`**:
  Estrutura e carga dos dados brutos do SETE (`ano_carga` 2026) e do Censo Escolar (`ano_carga` 2025) no Supabase **via API** (HTTPS `/pg/query`, chave secreta do `.env`). Gera as migrações `0003_sete.sql`/`0004_censo.sql` (`--gerar-ddl`), carrega em lotes idempotentes com checkpoint (`--retomar`), aceita carga por UF (`--uf go`) e carrega as referências (`--tabelas municipios referencia`).

- **`scripts/importar_planilha.py`**:
  Envio genérico de planilhas (CSV, TSV, TXT, XLSX, XLSM, XLS, ODS) ao Supabase via API. Sem argumentos, lê toda a pasta `upload/` (fora do Git; ver `upload/README.md`) e cria uma tabela por arquivo no schema privado `importacao`, com colunas em snake_case e tipos inferidos (inteiro, numérico em formato BR ou internacional, data, texto; códigos com zero à esquerda ficam como texto). Opções: `--simular`, `--modo criar|substituir|anexar`, `--tabela schema.nome`, `--aba`, `--todas-abas`, `--ano-carga`. Recusa os schemas `public`, `sete`, `censo`, `analise` e `pnite_meta`.

- **`scripts/build_vercel.mjs`**:
  Build da publicação na Vercel (executado pelo `vercel.json`). Copia para `dist/` só uma lista fechada de arquivos (`PNITE.html` → `index.html`, `assets/logos`, `assets/img` e os dois JS da capacitação) e gera `dist/config.local.js` com os mesmos valores públicos de `gerar_config_web.py`, lidos das variáveis de ambiente da Vercel (ou do `.env` local). Falha se faltar alguma variável ou se a chave não for publishable.

- **`scripts/supabase_migrar.py`**:
  Aplica as migrações SQL de `supabase/migrations/` (schemas, tabelas, views de análise e a view pública `indicadores`), registrando-as em `pnite_meta.migracoes`.

- **`scripts/validar_paridade.py`**:
  Compara a API (`/rest/v1/indicadores`, chave publishable) com o pacote compilado `pnite_dados_consolidados.json`, campo a campo, por escopo.

- **`scripts/gerar_config_web.py`**:
  Gera `config.local.js` (fora do Git) a partir do `.env`, copiando **somente** valores públicos: `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` e `ANO_CARGA_SETE`. É lido pelo `PNITE.html` para consultar a API.

- **`scripts/supabase_api.py`**:
  Cliente mínimo da API do Supabase usado pelos scripts acima (lê `SUPABASE_URL` e `SUPABASE_SECRET_KEY` do `.env`).

- **`scripts/extrair_capacitacao.py`**:
  Extrai e consolida os dados das capacitações a partir de `data/Capacitação/` (convocações HTML, formulários de inscrição, listas de presença e avaliações de cada `XCTE`, além do legado `legado_cte_01a04_powerbi.json` das capacitações 1 a 4). Grava as tabelas consolidadas, sem dados pessoais, no schema privado `capacitacao` do Supabase (migração `0012_capacitacao.sql`), numa única transação, e atualiza a view pública `public.capacitacao_dados` lida pelo `PNITE.html`. Uso: `pip install openpyxl requests python-dotenv` e `python scripts/extrair_capacitacao.py`.

- **`scripts/pegar_dado_rota.py` / `scripts/pegar_dado_rota.js`**:
  Utilitários para amostragem e inspeção detalhada de traçados geométricos de rotas e coordenadas geográficas do SETE.

- **`scripts/agrega_ind.py`**:
  Rotina histórica de agregação municipal/estadual a partir das tabelas da Divisão Territorial Brasileira (DTB/IBGE) e dados operacionais de rotas, veículos e alunos.

---

## Como Executar a Atualização de Dados

Os indicadores da interface são atualizados no banco (ver `DATABASE.md`, seção 7). Para regenerar o pacote local legado:
```bash
python scripts/extrair_dados_excel.py
```
Os arquivos consolidados em `data/Transporte Escolar/` (pasta local, fora do Git) são atualizados; a interface lê os indicadores da API do Supabase.

---

## Base de Dados no Supabase

Documentação completa da estrutura: [`DATABASE.md`](../DATABASE.md).

Camadas (definidas em `supabase/migrations/`):

| Schema | Conteúdo | Acesso pela API |
|---|---|---|
| `sete` | dados brutos do SETE (14 tabelas + `rota_shape` com o GeoJSON das rotas) | não exposto |
| `censo` | microdados do Censo Escolar (`matricula`) | não exposto |
| `ref` | UFs, municípios IBGE, pareamento de cargas, valores de referência legados | não exposto |
| `analise` | views de leitura limpa (`v_alunos`, `v_rotas`, ...) e agregações municipais | não exposto |
| `public` | `indicadores_municipio` → `indicadores_estado` → `indicadores_regiao` → `indicadores_nacional` (views materializadas em cascata: cada nível soma o anterior) e `indicadores` (união dos quatro, interface por `nivel`/`chave`) | leitura (`anon`) |
| `public` | `indicadores_municipio_complemento`: indicadores municipais do Censo `{ATE, MEDATE, PATM, PATE}` e da frota `{PVPCE, IMFP, IMFT, MIFCE}`; `sete_municipios`: tabela "Dados SETE" `{cols, municipios, ufs}` (migração `0013`, mesmas regras das antigas bases embutidas no HTML) | leitura (`anon`) |
| `public` | `capacitacao_dados`: capacitações em um objeto JSON (migração `0012`) | leitura (`anon`) |
| `public` | `rotas_tracado`: traçado das rotas por município, convertido de Web Mercator (EPSG:3857) para longitude/latitude (EPSG:4326) e simplificado (~10 m) com PostGIS | leitura (`anon`) |

Os dados brutos contêm dados pessoais (CPF, placa, coordenadas de alunos) e nunca são expostos; a chave publishable lê apenas `public.indicadores`.

Atualização completa (na raiz, com o `.env` preenchido a partir de `.env.example`):
```bash
pip install requests python-dotenv python-docx pandas openpyxl
python scripts/supabase_migrar.py
python scripts/criar_banco_dados_brutos.py --tabelas municipios referencia
python scripts/criar_banco_dados_brutos.py            # SETE + Censo (use --retomar se interromper)
python -c "import sys; sys.path.insert(0,'scripts'); from supabase_api import executar_sql; executar_sql('SELECT pnite_meta.atualizar_indicadores();')"
python scripts/validar_paridade.py
```

Consulta pela API:
```
GET {SUPABASE_URL}/rest/v1/indicadores_estado?ano_carga=eq.2026&uf=eq.go
GET {SUPABASE_URL}/rest/v1/indicadores_municipio?ano_carga=eq.2026&uf=eq.go&select=label,georref,indicadores&order=georref.desc
GET {SUPABASE_URL}/rest/v1/indicadores_regiao?ano_carga=eq.2026&regiao=eq.centro-oeste
GET {SUPABASE_URL}/rest/v1/indicadores_nacional?ano_carga=eq.2026
GET {SUPABASE_URL}/rest/v1/indicadores?ano_carga=eq.2026&nivel=eq.estado&chave=eq.go
GET {SUPABASE_URL}/rest/v1/indicadores?ano_carga=eq.2026&nivel=eq.municipio&uf=eq.go&select=chave,label,indicadores
Cabeçalho: apikey: {SUPABASE_PUBLISHABLE_KEY}
```
