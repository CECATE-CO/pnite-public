"""
PNITE — Estrutura e carga dos dados brutos (SETE e Censo Escolar) no Supabase via API.

O Postgres do servidor não aceita conexão direta, então tudo trafega por HTTPS no
endpoint ``/pg/query`` (ver ``scripts/supabase_api.py``), com a chave secreta do ``.env``.

Fluxo:
  1) ``--gerar-ddl``: gera ``supabase/migrations/0003_sete.sql`` e ``0004_censo.sql`` a
     partir de ``TABELAS``/cabeçalho do Censo (tipos do dicionário; descrições viram COMMENT);
  2) ``python scripts/supabase_migrar.py``: aplica as migrações pendentes;
  3) carga, uma tabela por vez: ``--tabelas alunos rotas ...`` (padrão: todas), opcionalmente
     só uma UF (``--uf go``, usado na carga piloto).

Regras de carga:
- ``ano_carga`` = ``ANO_CARGA_SETE`` (2026) para o SETE e ``ANO_CARGA_CENSO`` (2025) para o Censo;
- idempotente: antes de inserir, apaga as linhas do mesmo ano_carga (e da UF, se filtrada);
- lotes de ``--lote-mb`` MB enviados como JSON (``INSERT ... SELECT FROM json_array_elements``)
  em requisições de até ~1,9 MB (limite do postgres-meta); valores maiores sobem em partes;
  um checkpoint permite retomar com ``--retomar``;
- valores que não podem ser convertidos ao tipo da coluna viram NULL e são listados no log;
- rotas: o GeoJSON (``shape``, ~1,9 GB) vai para ``sete.rota_shape``; ``sete.rotas`` guarda
  ``tem_shape`` com a mesma regra do extrair_dados_excel.py (não nulo, não vazio, ≠ 'NULL').

Referências (``--tabelas municipios referencia``):
- municipios: ``Lista de Municipios IBGE.csv`` -> ``ref.municipios``;
- referencia: RAW_DATA legado + planilhas ``consolidado *.xlsx`` -> ``ref.raw_referencia`` e
  ``ref.detalhes_scripts`` (requer pandas/openpyxl; reutiliza scripts/extrair_dados_excel.py).

Uso:
    pip install requests python-dotenv python-docx pandas openpyxl
    python scripts/criar_banco_dados_brutos.py --gerar-ddl
    python scripts/supabase_migrar.py
    python scripts/criar_banco_dados_brutos.py --tabelas municipios referencia
    python scripts/criar_banco_dados_brutos.py --uf go            # piloto
    python scripts/criar_banco_dados_brutos.py                    # carga completa
"""

import argparse
import csv
import json
import os
import re
import sys
import time
from datetime import date, datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from supabase_api import LIMITE_CORPO, RAIZ, executar_sql, literal_dolar, tamanho_corpo  # noqa: E402

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

PASTA_DADOS = RAIZ / "data" / "Transporte Escolar"
DICIONARIO = PASTA_DADOS / "dicionario.docx"
ARQ_CENSO = "Micro_Dados_Censo_Tabela_Matricula_2025_V2.csv"
ARQ_MUNICIPIOS = "Lista de Municipios IBGE.csv"
PASTA_MIGRACOES = RAIZ / "supabase" / "migrations"
# Um checkpoint por tabela: permite cargas paralelas (ex.: rotas num processo, o resto em outro)
PASTA_CHECKPOINT = RAIZ / "scripts" / ".checkpoint_carga"

ANO_SETE = int(os.getenv("ANO_CARGA_SETE", "2026"))
ANO_CENSO = int(os.getenv("ANO_CARGA_CENSO", "2025"))

csv.field_size_limit(2**31 - 1)

SN = "char(1)"  # variáveis binárias S/N
CIDADE = [("codigo_cidade", "integer"), ("nome_cidade", "text"), ("uf", "varchar(2)"), ("estado", "text")]

# Ordem das colunas = ordem do cabeçalho de cada CSV (validada na carga).
# Ordem crescente de volume: as tabelas menores carregam primeiro.
TABELAS = {
    "normas": {
        "arquivo": "script_09_normas_consolidado.csv",
        "descricao": "Normas municipais de transporte escolar cadastradas no SETE.",
        "colunas": [("id", "integer"), *CIDADE, ("numero_norma", "text"), ("titulo", "text"),
                    ("data_norma", "timestamp"), ("id_tipo", "smallint"), ("tipo_veiculo", "smallint"),
                    ("outro_tipo", "text")],
        "indices": [("codigo_cidade", "id")],
    },
    "fornecedores": {
        "arquivo": "script_10_fornecedores_consolidado.csv",
        "descricao": "Fornecedores (mecânica, combustível, seguro) cadastrados no SETE.",
        "colunas": [*CIDADE, ("id_fornecedor", "integer"), ("ramo_mecanica", SN), ("ramo_combustivel", SN),
                    ("ramo_seguro", SN), ("dt_criacao", "timestamp"), ("dt_alteracao", "timestamp")],
        "indices": [("codigo_cidade", "id_fornecedor")],
    },
    "monitores": {
        "arquivo": "script_05_monitores_consolidado.csv",
        "descricao": "Monitores do transporte escolar cadastrados no SETE.",
        "colunas": [*CIDADE, ("idade", "integer"), ("sexo", "smallint"), ("vinculo", "smallint"),
                    ("salario", "numeric"), ("turno_manha", SN), ("turno_tarde", SN), ("turno_noite", SN),
                    ("loc_latitude", "double precision"), ("loc_longitude", "double precision"),
                    ("dt_criacao", "timestamp"), ("dt_alteracao", "timestamp")],
        "indices": [("codigo_cidade",)],
    },
    "rota_possui_veiculo": {
        "arquivo": "script_16_rota_possui_veiculo_consolidado.csv",
        "descricao": "Vínculo rota × veículo (chave: codigo_cidade + id_rota / id_veiculo).",
        "colunas": [("id_rota", "integer"), ("id_veiculo", "integer"), *CIDADE],
        "indices": [("codigo_cidade", "id_rota"), ("codigo_cidade", "id_veiculo")],
    },
    "rota_dirigida_por_motorista": {
        "arquivo": "script_17_rota_dirigida_por_motorista_consolidado.csv",
        "descricao": "Vínculo rota × motorista (chave: codigo_cidade + id_rota / cpf_motorista).",
        "colunas": [("id_rota", "integer"), ("cpf_motorista", "text"), *CIDADE],
        "indices": [("codigo_cidade", "id_rota")],
    },
    "motoristas": {
        "arquivo": "script_06_motoristas_consolidado.csv",
        "descricao": "Motoristas do transporte escolar cadastrados no SETE.",
        "colunas": [*CIDADE, ("idade", "integer"), ("sexo", "smallint"), ("tem_cnh_a", SN), ("tem_cnh_b", SN),
                    ("tem_cnh_c", SN), ("tem_cnh_d", SN), ("tem_cnh_e", SN), ("turno_manha", SN),
                    ("turno_tarde", SN), ("turno_noite", SN), ("data_validade_cnh", "date"),
                    ("vinculo", "smallint"), ("salario", "numeric")],
        "indices": [("codigo_cidade",)],
    },
    "veiculos": {
        "arquivo": "script_04_veiculos_consolidado.csv",
        "descricao": "Frota (veículos) do transporte escolar cadastrada no SETE.",
        "colunas": [*CIDADE, ("id_veiculo", "integer"), ("placa", "text"), ("ano", "integer"), ("modo", "smallint"),
                    ("origem", "smallint"), ("km_inicial", "numeric"), ("capacidade", "numeric"),
                    ("km_atual", "numeric"), ("tipo", "smallint"), ("renavam", "text"), ("manutencao", SN),
                    ("marca", "smallint"), ("id_firebase", "text"), ("ipva", "numeric"), ("dpvat", "numeric"),
                    ("seguro_anual", "numeric"), ("consumo", "numeric"), ("tipo_combustivel", SN),
                    ("numero_de_pneus", "integer"), ("vida_util_do_pneu", "numeric"), ("preco", "numeric"),
                    ("potencia_do_motor", "numeric"), ("modelo", "smallint"), ("outro_tipo_text", "text"),
                    ("is_state", "text"), ("historico", "text"), ("ativo", "smallint"),
                    ("dt_criacao", "timestamp"), ("criado_id", "integer"), ("dt_alteracao", "timestamp"),
                    ("alterado_id", "integer")],
        "indices": [("codigo_cidade", "id_veiculo")],
    },
    "rota_passa_por_escolas": {
        "arquivo": "script_15_rota_passa_por_escolas_consolidado.csv",
        "descricao": "Vínculo rota × escola (chave: codigo_cidade + id_rota / id_escola).",
        "colunas": [("id_rota", "integer"), ("id_escola", "integer"), *CIDADE],
        "indices": [("codigo_cidade", "id_rota"), ("codigo_cidade", "id_escola")],
    },
    "ordem_servico": {
        "arquivo": "script_11_ordem_servico_consolidado.csv",
        "descricao": "Ordens de serviço (manutenção, combustível etc.) vinculadas a veículos e fornecedores.",
        "colunas": [*CIDADE, ("id_fornecedor", "integer"), ("id_veiculo", "integer"), ("termino", SN),
                    ("data", "timestamp"), ("tipo_servico", "smallint"), ("comentario", "text"),
                    ("id_ordem", "integer"), ("id_firebase", "text"), ("is_state", "text")],
        "indices": [("codigo_cidade", "id_ordem"), ("codigo_cidade", "id_veiculo")],
    },
    "escolas": {
        "arquivo": "script_02_escolas_consolidado.csv",
        "descricao": "Escolas atendidas pelo transporte escolar cadastradas no SETE.",
        "colunas": [*CIDADE, ("id_escola", "integer"), ("nome", "text"), ("mec_co_entidade", "bigint"),
                    ("mec_co_uf", "smallint"), ("mec_co_municipio", "integer"), ("mec_no_entidade", "text"),
                    ("mec_tp_dependencia", "smallint"), ("mec_tp_localizacao", "smallint"),
                    ("mec_in_regular", SN), ("mec_in_eja", SN), ("mec_in_profissionalizante", SN),
                    ("mec_in_especial_exclusiva", SN), ("loc_latitude", "double precision"),
                    ("loc_longitude", "double precision"), ("loc_cep", "text"), ("loc_endereco", "text"),
                    ("contato_responsavel", "text"), ("contato_telefone", "text"), ("contato_email", "text"),
                    ("horario_matutino", SN), ("horario_vespertino", SN), ("horario_noturno", SN),
                    ("ensino_superior", SN), ("ensino_medio", SN), ("ensino_fundamental", SN),
                    ("ensino_pre_escola", SN), ("mec_tp_localizacao_diferenciada", "smallint"),
                    ("codigo_escola_firebase", "text"), ("alterado_por", "text"), ("dt_criacao", "timestamp"),
                    ("criado_por", "text"), ("dt_alteracao", "timestamp"), ("horario_integral", SN),
                    ("informacoes_adicionais", "jsonb"), ("nome_unidade_anexa", "text"), ("tipo_unidade", "text")],
        "indices": [("codigo_cidade", "id_escola")],
    },
    "rota_atende_aluno": {
        "arquivo": "script_13_rota_atende_aluno_consolidado.csv",
        "descricao": "Vínculo rota × aluno (chave: codigo_cidade + id_rota / id_aluno).",
        "colunas": [("id_rota", "integer"), ("id_aluno", "integer"), *CIDADE],
        "indices": [("codigo_cidade", "id_rota"), ("codigo_cidade", "id_aluno")],
    },
    "escola_tem_aluno": {
        "arquivo": "script_12_escola_tem_aluno_consolidado.csv",
        "descricao": "Vínculo escola × aluno (chave: codigo_cidade + id_escola / id_aluno).",
        "colunas": [("id_escola", "integer"), ("id_aluno", "integer"), *CIDADE],
        "indices": [("codigo_cidade", "id_escola"), ("codigo_cidade", "id_aluno")],
    },
    "alunos": {
        "arquivo": "script_01_alunos_consolidado.csv",
        "descricao": "Alunos usuários do transporte escolar cadastrados no SETE.",
        "colunas": [*CIDADE, ("id_aluno", "integer"), ("loc_latitude", "double precision"),
                    ("loc_longitude", "double precision"), ("da_porteira", SN), ("da_mataburro", SN),
                    ("da_colchete", SN), ("da_atoleiro", SN), ("da_ponterustica", SN), ("idade", "integer"),
                    ("sexo", "smallint"), ("cor", "smallint"), ("grau_responsavel", "smallint"),
                    ("def_caminhar", SN), ("def_ouvir", SN), ("def_enxergar", SN), ("def_mental", SN),
                    ("turno", "smallint"), ("nivel", "smallint"), ("dt_criacao", "timestamp"),
                    ("dt_alteracao", "timestamp")],
        "indices": [("codigo_cidade", "id_aluno")],
    },
    "rotas": {
        "arquivo": "script_03_rotas_consolidado.csv",
        "descricao": "Rotas do transporte escolar cadastradas no SETE (o traçado fica em sete.rota_shape).",
        "colunas": [*CIDADE, ("id_rota", "integer"), ("nome", "text"), ("km", "numeric"), ("da_porteira", SN),
                    ("da_mataburro", SN), ("da_colchete", SN), ("da_atoleiro", SN), ("da_ponterustica", SN),
                    ("turno_matutino", SN), ("turno_vespertino", SN), ("turno_noturno", SN), ("shape", "text"),
                    ("tempo", "numeric"), ("tipo", "smallint"), ("ativo", "smallint")],
        "indices": [("codigo_cidade", "id_rota")],
        "shape_separado": True,
    },
}

# Seções do dicionário (docx) -> tabela
SECOES_DICIONARIO = {"Escolas": "escolas", "Alunos": "alunos", "Rotas": "rotas",
                     "Veículos": "veiculos", "Motoristas": "motoristas", "Monitores": "monitores"}

RE_INT = re.compile(r"^-?\d+(\.0+)?$")
RE_NUM = re.compile(r"^-?(\d+(\.\d*)?|\.\d+)$")
LIMITES_INT = {"smallint": 2**15, "integer": 2**31, "bigint": 2**63}


# ---------------------------------------------------------------------------
# Estrutura
# ---------------------------------------------------------------------------

def colunas_banco(cfg):
    """Colunas efetivamente criadas no banco (rotas: shape sai, tem_shape entra)."""
    cols = [(c, t) for c, t in cfg["colunas"] if not (cfg.get("shape_separado") and c == "shape")]
    if cfg.get("shape_separado"):
        cols.append(("tem_shape", "boolean"))
    return cols


def cabecalho_censo():
    with open(PASTA_DADOS / ARQ_CENSO, encoding="latin1", newline="") as fh:
        return next(csv.reader(fh, delimiter=";"))


def tipo_coluna_censo(nome):
    if nome.startswith("CO_"):
        return "bigint"
    if nome.startswith(("QT_", "IN_", "TP_", "NU_")):
        return "integer"
    return "text"


def config_censo():
    cab = cabecalho_censo()
    return {
        "arquivo": ARQ_CENSO,
        "descricao": "Microdados do Censo Escolar (tabela de matrículas por escola).",
        "colunas": [(c.lower(), tipo_coluna_censo(c)) for c in cab],
        "indices": [("co_municipio",), ("sg_uf",)],
        "csv": {"encoding": "latin1", "delimiter": ";"},
        "coluna_uf": "sg_uf",
    }


def ler_dicionario():
    """Lê data/Transporte Escolar/dicionario.docx -> {tabela: {coluna: descrição}}."""
    try:
        import docx
        from docx.oxml.ns import qn
    except ImportError:
        print("  [aviso] python-docx não instalado; comentários do dicionário não gerados.")
        return {}
    if not DICIONARIO.exists():
        return {}
    doc = docx.Document(DICIONARIO)
    resultado, secao, idx_tabela = {}, None, 0
    for el in doc.element.body.iterchildren():
        if el.tag == qn("w:p"):
            texto = "".join(t.text or "" for t in el.iter(qn("w:t"))).strip()
            if texto in SECOES_DICIONARIO:
                secao = SECOES_DICIONARIO[texto]
        elif el.tag == qn("w:tbl"):
            tabela_doc = doc.tables[idx_tabela]
            idx_tabela += 1
            if secao:
                for linha in tabela_doc.rows[1:]:
                    celulas = [c.text.strip() for c in linha.cells]
                    if len(celulas) >= 3 and celulas[0]:
                        resultado.setdefault(secao, {})[celulas[0]] = " ".join(celulas[2].split())
    return resultado


def sql_literal(texto):
    return "'" + texto.replace("'", "''") + "'"


def ddl_tabela(schema, nome, cfg, ano_padrao, comentarios=None):
    tabela = f"{schema}.{nome}"
    linhas = [f"-- {cfg['descricao']}", f"CREATE TABLE IF NOT EXISTS {tabela} ("]
    defs = [f"    ano_carga smallint NOT NULL DEFAULT {ano_padrao}"]
    defs += [f"    {c} {t}" for c, t in colunas_banco(cfg)]
    linhas.append(",\n".join(defs))
    linhas.append(");")
    linhas.append(f"COMMENT ON TABLE {tabela} IS "
                  f"{sql_literal(cfg['descricao'] + ' Fonte: data/Transporte Escolar/' + cfg['arquivo'] + '.')};")
    linhas.append(f"COMMENT ON COLUMN {tabela}.ano_carga IS 'Ano de referência da carga do dado.';")
    for coluna, texto in sorted((comentarios or {}).items()):
        if coluna in {c for c, _ in colunas_banco(cfg)}:
            linhas.append(f"COMMENT ON COLUMN {tabela}.{coluna} IS {sql_literal(texto)};")
    if cfg.get("shape_separado"):
        linhas.append(f"COMMENT ON COLUMN {tabela}.tem_shape IS "
                      "'Rota georreferenciada: shape não nulo, não vazio e diferente de NULL (regra do PRGM).';")
    coluna_uf = cfg.get("coluna_uf", "uf")
    linhas.append(f"CREATE INDEX IF NOT EXISTS idx_{schema}_{nome}_uf ON {tabela} (ano_carga, {coluna_uf});")
    for i, cols in enumerate(cfg["indices"]):
        linhas.append(f"CREATE INDEX IF NOT EXISTS idx_{schema}_{nome}_{i} ON {tabela} (ano_carga, {', '.join(cols)});")
    return "\n".join(linhas)


def gerar_ddl():
    dicionario = ler_dicionario()
    partes = ["-- ============================================================================",
              "-- PNITE — 0003: dados brutos do SETE (gerado por scripts/criar_banco_dados_brutos.py --gerar-ddl)",
              "-- Colunas = cabeçalho dos CSVs; tipos e descrições = dicionário do SETE.",
              "-- ============================================================================", ""]
    for nome, cfg in TABELAS.items():
        partes += [ddl_tabela("sete", nome, cfg, ANO_SETE, dicionario.get(nome)), ""]
    partes += [
        "-- Traçado (GeoJSON) das rotas, separado por volume (~1,9 GB no CSV).",
        "CREATE TABLE IF NOT EXISTS sete.rota_shape (",
        f"    ano_carga smallint NOT NULL DEFAULT {ANO_SETE},",
        "    codigo_cidade integer,",
        "    uf varchar(2),",
        "    id_rota integer,",
        "    shape text",
        ");",
        "ALTER TABLE sete.rota_shape ALTER COLUMN shape SET COMPRESSION lz4;",
        "COMMENT ON TABLE sete.rota_shape IS 'Traçado GeoJSON das rotas do SETE (coluna shape de script_03_rotas).';",
        "CREATE INDEX IF NOT EXISTS idx_sete_rota_shape_0 ON sete.rota_shape (ano_carga, codigo_cidade, id_rota);",
        "CREATE INDEX IF NOT EXISTS idx_sete_rota_shape_uf ON sete.rota_shape (ano_carga, uf);",
        "",
    ]
    (PASTA_MIGRACOES / "0003_sete.sql").write_text("\n".join(partes), encoding="utf-8")

    censo = ["-- ============================================================================",
             "-- PNITE — 0004: microdados do Censo Escolar (gerado por criar_banco_dados_brutos.py --gerar-ddl)",
             "-- Colunas = cabeçalho do CSV do INEP em minúsculas.",
             "-- ============================================================================", "",
             ddl_tabela("censo", "matricula", config_censo(), ANO_CENSO), ""]
    (PASTA_MIGRACOES / "0004_censo.sql").write_text("\n".join(censo), encoding="utf-8")
    print("Gerados: supabase/migrations/0003_sete.sql e 0004_censo.sql"
          + ("" if dicionario else " (sem comentários do dicionário)"))


# ---------------------------------------------------------------------------
# Conversão de valores
# ---------------------------------------------------------------------------

def conversor(tipo):
    """Retorna função valor_csv -> texto aceito pelo Postgres (None = NULL; ValueError = inválido)."""
    if tipo in LIMITES_INT:
        limite = LIMITES_INT[tipo]

        def f(v):
            if not RE_INT.match(v):
                raise ValueError
            n = int(v.split(".")[0])
            if not -limite <= n < limite:
                raise ValueError
            return str(n)
        return f
    if tipo in ("numeric", "double precision"):
        def f(v):
            v = v.replace(",", ".")  # mesma regra do extrair_dados_excel.py (km, tempo)
            if v.lower() == "nan":
                return None  # NaN é ignorado nas somas do pandas; no banco vira NULL
            if RE_NUM.match(v):
                return v
            raise ValueError
        return f
    if tipo == "timestamp":
        return lambda v: datetime.fromisoformat(v).isoformat(sep=" ")
    if tipo == "date":
        return lambda v: date.fromisoformat(v).isoformat()
    if tipo == "boolean":
        return lambda v: v
    if tipo == "jsonb":
        def f(v):
            json.loads(v)
            return v
        return f
    if tipo == SN or tipo.startswith("varchar"):
        tamanho = 1 if tipo == SN else int(tipo[8:-1])

        def f(v):
            if len(v) > tamanho:
                raise ValueError
            return v
        return f
    return lambda v: v


def tem_shape(v):
    v = (v or "").strip()
    return v != "" and v.upper() != "NULL"


# ---------------------------------------------------------------------------
# Carga
# ---------------------------------------------------------------------------

def arquivo_checkpoint(chave):
    return PASTA_CHECKPOINT / (re.sub(r"[^\w.-]", "_", chave) + ".json")


def ler_checkpoint(chave):
    try:
        return json.loads(arquivo_checkpoint(chave).read_text(encoding="utf-8")).get("linhas", 0)
    except (OSError, ValueError):
        return 0


def gravar_checkpoint(chave, linhas):
    PASTA_CHECKPOINT.mkdir(exist_ok=True)
    arquivo_checkpoint(chave).write_text(json.dumps({"tabela": chave, "linhas": linhas}), encoding="utf-8")


def limpar_checkpoint(chave):
    arquivo_checkpoint(chave).unlink(missing_ok=True)


def sql_insert(tabela, colunas, linhas, substituir=None):
    """INSERT a partir de um array JSON de arrays (posicional, mais compacto que objetos).

    ``substituir`` = {índice_coluna: expressão SQL} troca a leitura do JSON por outra expressão.
    """
    substituir = substituir or {}
    exprs = ", ".join(substituir.get(i, f"(e->>{i})::{t}") for i, (_, t) in enumerate(colunas))
    nomes = ", ".join(c for c, _ in colunas)
    payload = json.dumps(linhas, ensure_ascii=False, separators=(",", ":"))
    return (f"INSERT INTO {tabela} ({nomes}) SELECT {exprs} "
            f"FROM json_array_elements({literal_dolar(payload)}::json) AS e;")


def enviar_linhas(tabela, colunas, linhas):
    """Envia as linhas em requisições de até LIMITE_CORPO bytes, dividindo o lote quando preciso."""
    if not linhas:
        return
    sql = sql_insert(tabela, colunas, linhas)
    if tamanho_corpo(sql) <= LIMITE_CORPO:
        executar_sql(sql)
    elif len(linhas) == 1:
        enviar_linha_grande(tabela, colunas, linhas[0])
    else:
        meio = len(linhas) // 2
        enviar_linhas(tabela, colunas, linhas[:meio])
        enviar_linhas(tabela, colunas, linhas[meio:])


def enviar_linha_grande(tabela, colunas, linha, tamanho_parte=600_000):
    """Linha maior que o limite (ex.: GeoJSON de rota extensa): o maior valor sobe em partes
    para pnite_meta.partes_texto e é remontado no banco com string_agg."""
    idx = max(range(len(linha)), key=lambda i: len(linha[i] or ""))
    texto = linha[idx]
    token = os.urandom(8).hex()
    partes = [texto[i:i + tamanho_parte] for i in range(0, len(texto), tamanho_parte)]
    for n, parte in enumerate(partes):
        executar_sql(f"INSERT INTO pnite_meta.partes_texto (token, parte, texto) "
                     f"VALUES ('{token}', {n}, {literal_dolar(parte)});")
    tipo = colunas[idx][1]
    expr = (f"(SELECT string_agg(texto, '' ORDER BY parte) FROM pnite_meta.partes_texto "
            f"WHERE token = '{token}')::{tipo}")
    copia = list(linha)
    copia[idx] = None
    executar_sql(sql_insert(tabela, colunas, [copia], {idx: expr})
                 + f" DELETE FROM pnite_meta.partes_texto WHERE token = '{token}';")


def carregar_tabela(schema, nome, cfg, ano, args):
    caminho = PASTA_DADOS / cfg["arquivo"]
    opcoes_csv = cfg.get("csv", {"encoding": "utf-8-sig", "delimiter": ","})
    nomes_csv = [c for c, _ in cfg["colunas"]]
    conversores = [conversor(t) for _, t in cfg["colunas"]]
    separa_shape = cfg.get("shape_separado", False)
    idx_shape = nomes_csv.index("shape") if separa_shape else None
    coluna_uf = cfg.get("coluna_uf", "uf")
    idx_uf = nomes_csv.index(coluna_uf)
    idx_cidade = nomes_csv.index("codigo_cidade") if "codigo_cidade" in nomes_csv else None
    idx_rota = nomes_csv.index("id_rota") if "id_rota" in nomes_csv else None

    tabela = f"{schema}.{nome}"
    colunas = [("ano_carga", "smallint")] + colunas_banco(cfg)
    col_shape = [("ano_carga", "smallint"), ("codigo_cidade", "integer"), ("uf", "varchar(2)"),
                 ("id_rota", "integer"), ("shape", "text")]

    chave_ck = f"{tabela}|{ano}|{args.uf or '*'}"
    pular = ler_checkpoint(chave_ck) if args.retomar else 0

    filtro = f"ano_carga = {ano}" + (f" AND lower({coluna_uf}) = {sql_literal(args.uf)}" if args.uf else "")
    if not pular:
        executar_sql(f"DELETE FROM {tabela} WHERE {filtro};"
                     + (f" DELETE FROM sete.rota_shape WHERE {filtro.replace(coluna_uf, 'uf')};" if separa_shape else ""))
    else:
        print(f"  retomando {tabela} após {pular:,} linhas já enviadas")

    lote, lote_shape, bytes_lote = [], [], 0
    limite = args.lote_mb * 2**20
    lidas = enviadas = 0
    invalidos = []
    inicio = time.time()

    def enviar():
        nonlocal lote, lote_shape, bytes_lote, enviadas
        if not lote:
            return
        enviar_linhas(tabela, colunas, lote)
        enviar_linhas("sete.rota_shape", col_shape, lote_shape)
        enviadas += len(lote)
        gravar_checkpoint(chave_ck, pular + enviadas)
        lote, lote_shape, bytes_lote = [], [], 0
        taxa = enviadas / max(time.time() - inicio, 1e-6)
        print(f"    ... {pular + enviadas:,} linhas ({taxa:,.0f}/s)", flush=True)

    with open(caminho, encoding=opcoes_csv["encoding"], newline="") as fh:
        leitor = csv.reader(fh, delimiter=opcoes_csv["delimiter"])
        cabecalho = next(leitor)
        if [c.lower() for c in cabecalho] != nomes_csv:
            raise RuntimeError(f"Cabeçalho de {cfg['arquivo']} difere da estrutura esperada:\n"
                               f"  CSV:      {cabecalho}\n  esperado: {nomes_csv}")
        for registro in leitor:
            if args.uf and registro[idx_uf].strip().lower() != args.uf:
                continue
            lidas += 1
            if lidas <= pular:
                continue
            valores = [str(ano)]
            for i, (nome_col, conv, v) in enumerate(zip(nomes_csv, conversores, registro)):
                if i == idx_shape:
                    continue
                v = v.replace("\x00", "")
                if v == "":
                    valores.append(None)
                    continue
                try:
                    valores.append(conv(v))
                except ValueError:
                    valores.append(None)
                    invalidos.append((lidas + 1, nome_col, v[:60]))
            if separa_shape:
                shape = registro[idx_shape]
                possui = tem_shape(shape)
                valores.append("true" if possui else "false")
                if possui:
                    lote_shape.append([str(ano), valores[1 + idx_cidade], valores[1 + idx_uf],
                                       valores[1 + idx_rota], shape.replace("\x00", "")])
                    bytes_lote += int(len(shape) * 1.3)  # aspas do GeoJSON são escapadas no corpo HTTP
            lote.append(valores)
            # estimativa do corpo: valores + aspas/vírgulas/escape (o limite real é conferido no envio)
            bytes_lote += sum(len(v) + 6 for v in valores if v)
            if bytes_lote >= limite:
                enviar()
    enviar()

    total = pular + enviadas
    executar_sql(f"ANALYZE {tabela};"
                 + (" ANALYZE sete.rota_shape;" if separa_shape else "")
                 + f" INSERT INTO pnite_meta.cargas_log (tabela, ano_carga, filtro_uf, linhas, invalidos)"
                   f" VALUES ({sql_literal(tabela)}, {ano}, {sql_literal(args.uf) if args.uf else 'NULL'},"
                   f" {total}, {len(invalidos)});")
    no_banco = executar_sql(f"SELECT count(*) AS n FROM {tabela} WHERE {filtro};")[0]["n"]
    status = "OK" if no_banco == lidas else f"DIVERGENTE (CSV {lidas:,})"
    print(f"  {tabela}: {no_banco:,} linhas no banco em {time.time() - inicio:.0f}s — {status}")
    for linha, coluna, valor in invalidos[:20]:
        print(f"    [NULL] linha {linha}, {coluna} = {valor!r} (valor inválido para o tipo)")
    if len(invalidos) > 20:
        print(f"    ... e mais {len(invalidos) - 20} valores inválidos convertidos em NULL")
    limpar_checkpoint(chave_ck)
    return no_banco == lidas


def carregar_municipios():
    codigos = {r["codigo_ibge"]: r["sigla"] for r in executar_sql("SELECT codigo_ibge, sigla FROM ref.uf;")}
    linhas = []
    with open(PASTA_DADOS / ARQ_MUNICIPIOS, encoding="utf-8-sig", newline="") as fh:
        leitor = csv.reader(fh, delimiter=";")
        next(leitor)
        for r in leitor:
            # só códigos IBGE de 7 dígitos (a lista traz Aparecida de Goiânia duplicada como 520140500)
            if len(r) < 9 or not re.fullmatch(r"\d{7}", r[2].strip()):
                continue
            linhas.append([r[2].strip(), r[3].strip(), codigos[int(r[0])], r[5].strip() or None,
                           r[6].strip() or None, r[7].strip() or None, r[8].strip() or None])
    colunas = [("codigo_ibge", "integer"), ("nome", "text"), ("uf", "text"), ("codigo_rgi", "integer"),
               ("nome_rgi", "text"), ("codigo_rgim", "integer"), ("nome_rgim", "text")]
    executar_sql("DELETE FROM ref.municipios;\n" + sql_insert("ref.municipios", colunas, linhas))
    print(f"  ref.municipios: {len(linhas):,} municípios")


def carregar_referencia(ano):
    """RAW_DATA de referência (legado do HTML + planilhas consolidado *.xlsx) e detalhes_scripts."""
    import extrair_dados_excel as ext  # scripts/ já está no sys.path; caminhos resolvidos pela raiz

    tabelas = ext.carregar_planilhas(str(PASTA_DADOS))
    detalhes = ext.extrair_metricas_por_uf(tabelas)
    raw = ext.montar_raw_referencia(detalhes)
    linhas_raw = [[str(ano), chave, json.dumps(dados, ensure_ascii=False)] for chave, dados in raw.items()]
    linhas_det = [[str(ano), chave, script, json.dumps(dados, ensure_ascii=False)]
                  for chave, scripts in detalhes.items() for script, dados in scripts.items()]
    executar_sql(
        f"DELETE FROM ref.raw_referencia WHERE ano_carga = {ano};"
        f" DELETE FROM ref.detalhes_scripts WHERE ano_carga = {ano};\n"
        + sql_insert("ref.raw_referencia", [("ano_carga", "smallint"), ("chave", "text"), ("dados", "jsonb")], linhas_raw)
        + "\n" + sql_insert("ref.detalhes_scripts", [("ano_carga", "smallint"), ("chave", "text"),
                                                      ("script", "text"), ("dados", "jsonb")], linhas_det))
    print(f"  ref.raw_referencia: {len(linhas_raw)} escopos | ref.detalhes_scripts: {len(linhas_det)} registros")


def main():
    entidades = ["municipios", "referencia", *TABELAS, "censo"]
    p = argparse.ArgumentParser(description="Estrutura e carga dos dados brutos da PNITE no Supabase (via API).")
    p.add_argument("--gerar-ddl", action="store_true", help="gera as migrações 0003/0004 e sai")
    p.add_argument("--tabelas", nargs="*", choices=entidades, help="o que carregar (padrão: SETE + Censo)")
    p.add_argument("--uf", help="carrega apenas uma UF (sigla, ex.: go) — carga piloto")
    p.add_argument("--lote-mb", type=float, default=1.5,
                   help="tamanho aproximado de cada lote (MB); requisições acima do limite do servidor são divididas")
    p.add_argument("--retomar", action="store_true", help="retoma a partir do checkpoint da última carga")
    args = p.parse_args()
    if args.uf:
        args.uf = args.uf.strip().lower()

    if args.gerar_ddl:
        gerar_ddl()
        return

    alvo = args.tabelas or [*TABELAS, "censo"]
    falhas = []
    for nome in alvo:
        print(f"[{nome}]", flush=True)
        if nome == "municipios":
            carregar_municipios()
        elif nome == "referencia":
            carregar_referencia(ANO_SETE)
        elif nome == "censo":
            if not carregar_tabela("censo", "matricula", config_censo(), ANO_CENSO, args):
                falhas.append(nome)
        elif not carregar_tabela("sete", nome, TABELAS[nome], ANO_SETE, args):
            falhas.append(nome)
    if falhas:
        sys.exit("Contagem divergente em: " + ", ".join(falhas))


if __name__ == "__main__":
    main()
