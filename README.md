# PNITE — Plataforma Nacional de Inteligência em Transporte Escolar

A **PNITE** é uma plataforma analítica desenvolvida para visualização, monitoramento, exploração e interpretação de informações estratégicas sobre o transporte escolar público brasileiro.

A ferramenta consolida dados operacionais do Sistema Eletrônico de Gestão do Transporte Escolar (**SETE**), do **Censo Escolar** (MEC/Inep) e das ações de formação do Centro Colaborador de Apoio ao Transporte Escolar (**CECATE/UFG**).

---

## 🏛️ Realização e Parcerias

- **MEC** — Ministério da Educação
- **FNDE** — Fundo Nacional de Desenvolvimento da Educação
- **UFG** — Universidade Federal de Goiás
- **CECATE** — Centro Colaborador de Apoio ao Transporte Escolar

---

## 🚀 Como Executar

A PNITE é uma aplicação web de alta performance projetada para execução direta no navegador (arquitetura *client-side* prioritária), sem necessidade de servidor back-end obrigatório:

1. Clone o repositório ou faça o download dos arquivos:
   ```bash
   git clone https://github.com/mathmorato/pnite.git
   ```
2. Gere a configuração pública da API (URL e chave publishable do Supabase) a partir do `.env` (modelo em `.env.example`):
   ```bash
   python scripts/gerar_config_web.py      # cria config.local.js (fora do Git)
   ```
   Desde a v.3.0.8 os indicadores do Transporte Escolar são lidos da API do Supabase; sem o `config.local.js` a plataforma exibe um aviso de configuração ausente.
3. Abra o arquivo principal no navegador:
   - Dê um duplo-clique em `PNITE.html`, ou
   - Inicie um servidor local se preferir (nunca a partir de uma pasta que exponha o `.env`):
     ```bash
     npx serve .
     # ou
     python -m http.server 8000
     ```

### Publicação na Vercel

O repositório já está configurado (`vercel.json`, `.vercelignore`, `scripts/build_vercel.mjs`):

1. Na Vercel, **Add New → Project** e importe o repositório do GitHub (Framework Preset: *Other*; as demais opções vêm do `vercel.json`).
2. Em **Settings → Environment Variables**, cadastre apenas os valores públicos: `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` e `ANO_CARGA_SETE`. **Nunca** cadastre `SUPABASE_SECRET_KEY` nem senhas.
3. Faça o deploy. O build (`node scripts/build_vercel.mjs`) monta `dist/` com `PNITE.html` (servido como `index.html`), os logos e imagens, os dois arquivos JS da capacitação e o `config.local.js` gerado das variáveis. Sem as variáveis, o build falha e a versão no ar não é substituída.

Só a lista fechada de arquivos do build é publicada (HTML, logos e imagens); todos os dados vêm das APIs. `data/`, `upload/`, `old/` e `.env` nunca vão para o site. Para conferir localmente: `node scripts/build_vercel.mjs` e `python -m http.server 8000 --directory dist`.

---

## 📂 Organização do Repositório

O repositório adota uma estrutura limpa e modular:

```
pnite/
├── PNITE.html                 # Aplicação web principal (versão mais recente)
├── README.md                  # Documentação geral do repositório
├── AGENTS.md                  # Diretrizes e regras técnicas de manutenção e versionamento
├── GEMINI.md                  # Referência de regras do agente
├── LICENSE                    # Licença do projeto
│
├── assets/                    # Recursos visuais e logomarcas
│   ├── README.md              # Guia de identidade e especificações de uso
│   ├── logos/                 # Logomarcas oficiais (PNG e SVG vetorial)
│   │   ├── logo_pnite_color.png
│   │   ├── logo_pnite_white.png
│   │   ├── logo_pnite_original.png
│   │   ├── logo_ufg.jpg
│   │   └── logo_cecate.svg
│   └── img/                   # Ilustrações e fotografias de frotas
│       └── escolar_sao_goncalo.png
│
├── data/                      # SOMENTE LOCAL (fora do Git desde a v.3.1.4): dados brutos com dados pessoais
│   ├── Transporte Escolar/    # Planilhas e consolidados do SETE e Censo Escolar
│   │   ├── pnite_dados_consolidados.js
│   │   ├── pnite_dados_consolidados.json
│   │   ├── malhas_mg.json
│   │   ├── sete_mun.json
│   │   └── *.xlsx / *.csv consolidados
│   ├── Capacitação/           # Formulários das oficinas regionais (5CTE a 16CTE) → banco (extrair_capacitacao.py)
│   │   └── *CTE - Avaliação, Formulário e Lista de Presença.xlsx
│   └── Gestão/                # Diretório reservado para indicadores de governança e regulação
│
├── supabase/migrations/       # Estrutura SQL do banco (schemas, tabelas, views, API)
├── upload/                    # Planilhas para envio ao banco (fora do Git; ver upload/README.md)
│
├── scripts/                   # Utilitários de agregação e banco de dados
│   ├── README.md              # Descrição das rotinas de suporte
│   ├── criar_banco_dados_brutos.py
│   ├── pegar_dado_rota.js
│   ├── pegar_dado_rota.py
│   └── agrega_ind.py
│
├── dic/                       # Dicionários de dados originais de extração
│   ├── Dicionário utilizado Marcos extração SETE.docx
│   └── Dicionário utilizado Marcos extração SETE.pdf
│
├── old/                       # Histórico rigoroso de versões arquivadas (v.1.0.0 até atual)
│   └── PNITE [V.*].html
│
└── scripts/                   # Carga do banco e utilitários (inclui extrair_dados_excel.py)
```

---

## 📊 Frentes Analíticas da Plataforma

1. **Indicadores do Transporte Escolar:**
   - Diagnóstico nacional, regional e estadual por 18 indicadores analíticos (PRGM, PRIO, PRRM, PVP, PVT, IUC, ATE, MEDATE, PCSC, PARI, etc.).
   - Mapa coroplético do Brasil interativo por UF com faixas metodológicas.
   - Detalhamento por rotas, alunos, escolas, frotas, motoristas e monitores.
   - Memória de cálculo detalhada com fórmulas e fontes.

2. **Indicadores da Capacitação (Centro-Oeste):**
   - Monitoramento das ações presenciais nos estados de GO, MT, MS e DF.
   - Filtros por polo de formação, UF, perfil de participação e ano (2024–2025).
   - Estatísticas de engajamento de Conselheiros CACS-Fundeb e Gestores Municipais/Estaduais.
   - Mapa georreferenciado dos municípios participantes.

3. **Gestão e Regulação:**
   - Módulo preparado para integração de normas, compras públicas, custos operacionais e fornecedores.

---

## 🔄 Atualização dos Dados

Para recalcular o pacote local a partir de planilhas adicionadas ou atualizadas em `data/Transporte Escolar/`:

```bash
python scripts/extrair_dados_excel.py
```

O script recalcula os totais nacionais, agregações regionais/estaduais e atualiza os arquivos:
- `data/Transporte Escolar/pnite_dados_consolidados.json`
- `data/Transporte Escolar/pnite_dados_consolidados.js`

Esses arquivos são de uso local (a interface lê os indicadores da API do Supabase, descrita abaixo).

> A pasta `data/` não é versionada desde a v.3.1.4: contém dados brutos com dados pessoais e fica apenas na máquina de quem faz a carga. A interface não lê nenhum arquivo de `data/`.

### Base de dados no Supabase

Estrutura completa (schemas, tabelas, views da API, regras de cálculo e atualização): [`DATABASE.md`](DATABASE.md).

Os dados das capacitações também vêm da API (`/rest/v1/capacitacao_dados`, gravada por `scripts/extrair_capacitacao.py`), e a malha municipal do mapa da capacitação vem da API de malhas do IBGE.

Os dados brutos do SETE e do Censo Escolar ficam no Supabase, com os indicadores calculados no banco e servidos por escopo via API (`/rest/v1/indicadores_{nacional,regiao,estado,municipio}`). A plataforma consulta a API na abertura (Brasil, regiões e UFs) e a cada troca de território. Base nacional completa: SETE (ano de carga 2026) e Censo Escolar (2025) das 27 UFs. Estrutura, carga e validação estão descritas em [`scripts/README.md`](scripts/README.md#base-de-dados-no-supabase). As credenciais ficam no `.env` (modelo em `.env.example`), que nunca deve ser versionado nem servido pelo navegador.

---

## 🏷️ Versionamento

A plataforma segue um versionamento sequencial $Z \rightarrow Y \rightarrow X$ estrito (`v.X.Y.Z`). Toda evolução é arquivada em `old/PNITE [V.X.Y.Z].html` antes de cada incremento, garantindo rastreabilidade histórica e segurança operacional.
