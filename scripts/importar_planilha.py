"""
PNITE — Importa planilhas (CSV/TSV/TXT, XLSX/XLSM, XLS, ODS) para tabelas do Supabase via API.

Sem argumentos, importa todos os arquivos da pasta ``upload/`` (fora do Git: os arquivos podem
conter dados pessoais), incluindo subpastas; cada arquivo vira uma tabela. Um arquivo com erro
não interrompe os demais.

Tudo trafega por HTTPS no endpoint ``/pg/query`` (ver ``scripts/supabase_api.py``), com a chave
secreta do ``.env``, nos mesmos lotes de ``criar_banco_dados_brutos.py``.

Regras:
- destino padrão: schema privado ``importacao`` (sem acesso pela API pública), tabela com o nome
  do arquivo; ``--tabela schema.nome`` escolhe outro destino;
- schemas protegidos (``public``, exposto pela API; ``sete``/``censo``, mantidos pela carga oficial;
  ``analise``/``pnite_meta``) são recusados;
- nomes de colunas normalizados para snake_case sem acentos (``Código IBGE`` -> ``codigo_ibge``);
- tipos inferidos lendo o arquivo inteiro: bigint, numeric (aceita ``1.234,56`` e ``1234.56``),
  date (``AAAA-MM-DD`` ou ``DD/MM/AAAA``), timestamp e text; códigos com zero à esquerda (CEP, CPF)
  ficam como text; célula vazia vira NULL;
- ``--modo criar`` (padrão) falha se a tabela existir; ``substituir`` recria; ``anexar`` insere
  numa tabela existente (as colunas do arquivo devem existir nela);
- ``--ano-carga`` acrescenta a coluna ``ano_carga`` e registra a carga em ``pnite_meta.cargas_log``;
- ``--simular`` mostra colunas, tipos e o DDL sem enviar nada.

Uso:
    pip install requests python-dotenv pandas openpyxl   # + xlrd (.xls) / odfpy (.ods)
    python scripts/importar_planilha.py --simular                       # toda a pasta upload/
    python scripts/importar_planilha.py --modo substituir               # reenvia upload/
    python scripts/importar_planilha.py dados.xlsx --simular
    python scripts/importar_planilha.py dados.xlsx                      # -> importacao.dados
    python scripts/importar_planilha.py dados.csv --tabela ref.minha_tabela --modo substituir
    python scripts/importar_planilha.py dados.xlsx --aba "Plan2" --ano-carga 2026
    python scripts/importar_planilha.py dados.xlsx --todas-abas         # uma tabela por aba
"""

import argparse
import csv
import re
import sys
import time
import unicodedata
from datetime import date, datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from criar_banco_dados_brutos import enviar_linhas, sql_literal  # noqa: E402
from supabase_api import RAIZ, executar_sql  # noqa: E402

for _saida in (sys.stdout, sys.stderr):
    if hasattr(_saida, "reconfigure"):
        _saida.reconfigure(encoding="utf-8")

PASTA_UPLOAD = RAIZ / "upload"
SCHEMA_PADRAO = "importacao"
SCHEMAS_PROTEGIDOS = {"public", "sete", "censo", "analise", "pnite_meta", "auth", "storage"}
EXT_CSV = {".csv", ".tsv", ".txt"}
EXT_PLANILHA = {".xlsx", ".xlsm", ".xls", ".ods"}
LOTE_BYTES = 1_500_000
csv.field_size_limit(2**31 - 1)

class ErroImportacao(RuntimeError):
    pass


RE_INT = re.compile(r"^-?\d{1,18}$")
RE_NUM_PONTO = re.compile(r"^-?\d+(\.\d+)?([eE][-+]?\d+)?$")
RE_NUM_BR = re.compile(r"^-?(\d{1,3}(\.\d{3})+|\d+)(,\d+)?$")
RE_DATA_ISO = re.compile(r"^\d{4}-\d{2}-\d{2}$")
RE_DATA_BR = re.compile(r"^\d{2}/\d{2}/\d{4}$")
RE_DATAHORA = re.compile(r"^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}(:\d{2}(\.\d+)?)?$")


# ---------------------------------------------------------------------------
# Leitura
# ---------------------------------------------------------------------------

def nome_sql(texto, padrao="coluna"):
    """'Código IBGE (2025)' -> 'codigo_ibge_2025' (identificador Postgres seguro, até 63 bytes)."""
    texto = unicodedata.normalize("NFKD", str(texto)).encode("ascii", "ignore").decode()
    texto = re.sub(r"[^a-z0-9]+", "_", texto.lower()).strip("_") or padrao
    if texto[0].isdigit():
        texto = f"{padrao[0]}_{texto}"
    return texto[:63]


def nomes_colunas(cabecalho):
    nomes, usados = [], set()
    for i, c in enumerate(cabecalho):
        base = nome_sql(c, f"coluna_{i + 1}") if str(c).strip() else f"coluna_{i + 1}"
        nome, n = base, 1
        while nome in usados:
            n += 1
            nome = f"{base[:58]}_{n}"
        usados.add(nome)
        nomes.append(nome)
    return nomes


class FonteCSV:
    """Lê o CSV em fluxo (duas passagens: inferência e envio), sem carregar tudo na memória."""

    def __init__(self, caminho, sep=None, encoding=None):
        self.caminho = caminho
        self.encoding = encoding or self._detectar_encoding()
        with open(caminho, encoding=self.encoding, newline="") as fh:
            amostra = fh.read(256_000)
        if sep:
            self.sep = "\t" if sep in ("\\t", "tab") else sep
        else:
            try:
                self.sep = csv.Sniffer().sniff(amostra, delimiters=",;\t|").delimiter
            except csv.Error:
                self.sep = "\t" if caminho.suffix.lower() == ".tsv" else ","
        self.cabecalho = next(self._leitor())

    def _detectar_encoding(self):
        try:
            with open(self.caminho, encoding="utf-8-sig") as fh:
                while fh.read(4_000_000):
                    pass
            return "utf-8-sig"
        except UnicodeDecodeError:
            return "cp1252"

    def _leitor(self):
        fh = open(self.caminho, encoding=self.encoding, newline="")
        try:
            yield from csv.reader(fh, delimiter=self.sep)
        finally:
            fh.close()

    def linhas(self):
        leitor = self._leitor()
        next(leitor, None)
        return leitor

    def descricao(self):
        return f"encoding {self.encoding}, separador {self.sep!r}"


class FontePlanilha:
    """Uma aba de planilha, lida como texto pelo pandas (datas viram 'AAAA-MM-DD HH:MM:SS')."""

    def __init__(self, df, aba):
        self.aba = aba
        self.cabecalho = [str(c) for c in df.columns]
        self.valores = df.values.tolist()

    def linhas(self):
        return iter(self.valores)

    def descricao(self):
        return f"aba {self.aba!r}"


def ler_abas(caminho, aba=None, todas=False):
    try:
        import pandas as pd
    except ImportError:
        sys.exit("pandas não instalado: pip install pandas openpyxl")
    motor = {".xls": "xlrd", ".ods": "odf"}.get(caminho.suffix.lower(), "openpyxl")
    alvo = None if todas else (aba if aba is not None else 0)
    if isinstance(alvo, str) and alvo.isdigit():
        alvo = int(alvo)
    try:
        lido = pd.read_excel(caminho, sheet_name=alvo, dtype=str, keep_default_na=False, engine=motor)
    except ImportError as e:
        raise ErroImportacao(f"Leitor de {caminho.suffix} ausente ({e}); instale: pip install "
                             + {"xlrd": "xlrd", "odf": "odfpy"}.get(motor, "openpyxl"))
    except ValueError as e:  # aba inexistente
        raise ErroImportacao(str(e))
    if not isinstance(lido, dict):
        nomes_abas = pd.ExcelFile(caminho, engine=motor).sheet_names
        lido = {nomes_abas[alvo] if isinstance(alvo, int) else alvo: lido}
    return [(nome, FontePlanilha(df.fillna(""), nome)) for nome, df in lido.items()]


# ---------------------------------------------------------------------------
# Tipos
# ---------------------------------------------------------------------------

class Perfil:
    """Acompanha, por coluna, quais tipos ainda são compatíveis com todos os valores lidos."""

    def __init__(self):
        self.int = self.num_ponto = self.num_br = self.data = self.datahora = True
        self.meia_noite = True
        self.vazio = True
        self.largura = 0

    def ver(self, v):
        self.vazio = False
        self.largura = max(self.largura, len(v))
        if self.int and not (RE_INT.match(v) and not re.match(r"^-?0\d", v)):
            self.int = False
        if self.num_ponto and not RE_NUM_PONTO.match(v):
            self.num_ponto = False
        if self.num_br and not RE_NUM_BR.match(v):
            self.num_br = False
        if self.num_ponto or self.num_br:
            # zero à esquerda indica código (CEP, CPF, código de escola), não quantidade
            if re.match(r"^-?0\d", v):
                self.num_ponto = self.num_br = False
        if self.data and not (RE_DATA_ISO.match(v) or RE_DATA_BR.match(v)):
            self.data = False
        if self.datahora:
            if RE_DATAHORA.match(v):
                self.meia_noite &= v[11:].strip("0:.") == ""
            else:
                self.datahora = False

    def tipo(self):
        if self.vazio:
            return "text"
        if self.int:
            return "bigint"
        if self.num_ponto:
            return "numeric"
        if self.num_br:
            return "numeric_br"
        if self.data:
            return "date"
        if self.datahora:
            return "date_hora0" if self.meia_noite else "timestamp"
        return "text"


TIPO_SQL = {"numeric_br": "numeric", "date_hora0": "date"}


def converter(tipo, v):
    """Valor do arquivo -> texto aceito pelo Postgres no tipo inferido (ValueError = inválido)."""
    if tipo == "numeric_br":
        return v.replace(".", "").replace(",", ".")
    if tipo == "date":
        return (datetime.strptime(v, "%d/%m/%Y").date() if "/" in v else date.fromisoformat(v)).isoformat()
    if tipo == "date_hora0":
        return v[:10]
    if tipo == "timestamp":
        return datetime.fromisoformat(v).isoformat(sep=" ")
    return v


def limpar(v):
    v = "" if v is None else str(v).replace("\x00", "").strip()
    return None if v == "" or v.lower() in ("nan", "nat") else v


def inferir_tipos(fonte, n_colunas):
    perfis = [Perfil() for _ in range(n_colunas)]
    total = 0
    for registro in fonte.linhas():
        if not any(limpar(v) for v in registro):
            continue
        total += 1
        for i, v in enumerate(registro[:n_colunas]):
            v = limpar(v)
            if v is not None:
                perfis[i].ver(v)
    return [p.tipo() for p in perfis], total


# ---------------------------------------------------------------------------
# Banco
# ---------------------------------------------------------------------------

def separar_destino(destino):
    schema, _, nome = destino.rpartition(".")
    schema, nome = nome_sql(schema or SCHEMA_PADRAO, "importacao"), nome_sql(nome, "tabela")
    if schema in SCHEMAS_PROTEGIDOS or schema.startswith("pg_"):
        raise ErroImportacao(f"Schema {schema!r} é protegido. Use o padrão {SCHEMA_PADRAO!r}, 'ref' ou outro schema privado.")
    return schema, nome


def colunas_existentes(schema, nome):
    linhas = executar_sql(
        "SELECT column_name, data_type FROM information_schema.columns "
        f"WHERE table_schema = {sql_literal(schema)} AND table_name = {sql_literal(nome)} ORDER BY ordinal_position;")
    return {r["column_name"]: r["data_type"] for r in linhas}


def ddl(schema, nome, colunas, ano_carga, origem):
    tabela = f"{schema}.{nome}"
    defs = ([f"    ano_carga smallint NOT NULL DEFAULT {ano_carga}"] if ano_carga else [])
    defs += [f"    {c} {t}" for c, t in colunas]
    return "\n".join([
        f"CREATE SCHEMA IF NOT EXISTS {schema};",
        f"REVOKE ALL ON SCHEMA {schema} FROM PUBLIC, anon, authenticated;" if schema == SCHEMA_PADRAO else "",
        f"CREATE TABLE {tabela} (",
        ",\n".join(defs),
        ");",
        f"COMMENT ON TABLE {tabela} IS {sql_literal(f'Importado de {origem} em {date.today().isoformat()} (scripts/importar_planilha.py).')};",
    ]).replace("\n\n", "\n")


def importar(fonte, schema, nome, args, origem):
    tabela = f"{schema}.{nome}"
    nomes = nomes_colunas(fonte.cabecalho)
    print(f"\n{origem} -> {tabela}  ({fonte.descricao()})")
    tipos, total = inferir_tipos(fonte, len(nomes))
    colunas = [(c, TIPO_SQL.get(t, t)) for c, t in zip(nomes, tipos)]
    largura = max(len(c) for c in nomes)
    for original, (c, t) in zip(fonte.cabecalho, colunas):
        print(f"  {c:<{largura}}  {t:<10}" + (f"  <- {original!r}" if original != c else ""))
    print(f"  {total:,} linhas")

    if args.simular:
        print("\n" + ddl(schema, nome, colunas, args.ano_carga, origem))
        return True

    existentes = colunas_existentes(schema, nome)
    if existentes and args.modo == "criar":
        raise ErroImportacao(f"{tabela} já existe: use --modo substituir (recria) ou --modo anexar (acrescenta linhas).")
    if args.modo == "anexar" and existentes:
        faltando = [c for c in nomes if c not in existentes]
        if faltando:
            raise ErroImportacao(f"Colunas ausentes em {tabela}: {', '.join(faltando)}")
        if args.ano_carga and "ano_carga" not in existentes:
            raise ErroImportacao(f"{tabela} não tem a coluna ano_carga (remova --ano-carga).")
        colunas_envio = [(c, existentes[c]) for c in nomes]
    else:
        executar_sql((f"DROP TABLE IF EXISTS {tabela};\n" if existentes else "")
                     + ddl(schema, nome, colunas, args.ano_carga, origem))
        colunas_envio = colunas
    if args.ano_carga:
        colunas_envio = [("ano_carga", "smallint")] + colunas_envio

    antes = executar_sql(f"SELECT count(*) AS n FROM {tabela};")[0]["n"]
    inicio = time.time()
    lote, bytes_lote, enviadas, invalidos = [], 0, 0, []
    for n_linha, registro in enumerate(fonte.linhas(), start=2):
        if not any(limpar(v) for v in registro):
            continue
        valores = [str(args.ano_carga)] if args.ano_carga else []
        for i, (c, t) in enumerate(zip(nomes, tipos)):
            v = limpar(registro[i]) if i < len(registro) else None
            if v is not None:
                try:
                    v = converter(t, v)
                except ValueError:
                    invalidos.append((n_linha, c, v[:60]))
                    v = None
            valores.append(v)
        lote.append(valores)
        bytes_lote += sum(len(v) + 6 for v in valores if v)
        if bytes_lote >= LOTE_BYTES:
            enviar_linhas(tabela, colunas_envio, lote)
            enviadas += len(lote)
            print(f"    ... {enviadas:,} linhas", flush=True)
            lote, bytes_lote = [], 0
    enviar_linhas(tabela, colunas_envio, lote)
    enviadas += len(lote)

    log = (f" INSERT INTO pnite_meta.cargas_log (tabela, ano_carga, linhas, invalidos) VALUES "
           f"({sql_literal(tabela)}, {args.ano_carga}, {enviadas}, {len(invalidos)});" if args.ano_carga else "")
    executar_sql(f"ANALYZE {tabela};{log}")
    no_banco = executar_sql(f"SELECT count(*) AS n FROM {tabela};")[0]["n"] - antes
    ok = no_banco == enviadas == total
    print(f"  {tabela}: {no_banco:,} linhas inseridas em {time.time() - inicio:.0f}s — "
          + ("OK" if ok else f"DIVERGENTE (arquivo {total:,}, enviadas {enviadas:,})"))
    for linha, coluna, valor in invalidos[:20]:
        print(f"    [NULL] linha {linha}, {coluna} = {valor!r} (valor inválido para o tipo)")
    if len(invalidos) > 20:
        print(f"    ... e mais {len(invalidos) - 20} valores inválidos convertidos em NULL")
    return ok


def arquivos_upload(pasta):
    extensoes = EXT_CSV | EXT_PLANILHA
    return sorted(a for a in pasta.rglob("*")
                  if a.is_file() and a.suffix.lower() in extensoes and not a.name.startswith(("~$", ".")))


def importar_arquivo(caminho, args):
    """Importa um arquivo (todas as abas pedidas); devolve True se as contagens conferem."""
    ext = caminho.suffix.lower()
    schema, nome = separar_destino(args.tabela or caminho.stem)
    if ext in EXT_CSV:
        fontes = [(caminho.name, FonteCSV(caminho, args.sep, args.encoding))]
        destinos = [(schema, nome)]
    elif ext in EXT_PLANILHA:
        abas = ler_abas(caminho, args.aba, args.todas_abas)
        fontes = [(f"{caminho.name} [{aba}]", f) for aba, f in abas]
        destinos = ([(schema, nome_sql(f"{nome}_{aba}")) for aba, _ in abas] if args.todas_abas
                    else [(schema, nome)])
    else:
        raise ErroImportacao(f"Extensão {ext!r} não suportada: use {', '.join(sorted(EXT_CSV | EXT_PLANILHA))}")
    return all([importar(f, s, n, args, origem) for (origem, f), (s, n) in zip(fontes, destinos)])


def main():
    p = argparse.ArgumentParser(description="Importa CSV/TSV/TXT/XLSX/XLSM/XLS/ODS para o Supabase.")
    p.add_argument("arquivo", type=Path, nargs="?", default=PASTA_UPLOAD,
                   help="arquivo ou pasta (padrão: upload/, com subpastas)")
    p.add_argument("--tabela", help=f"destino schema.nome (padrão: {SCHEMA_PADRAO}.<nome do arquivo>; só com um arquivo)")
    p.add_argument("--aba", help="nome ou índice (0, 1, ...) da aba; padrão: a primeira")
    p.add_argument("--todas-abas", action="store_true", help="importa cada aba numa tabela <nome>_<aba>")
    p.add_argument("--sep", help="separador do CSV (padrão: detectado; use 'tab' para tabulação)")
    p.add_argument("--encoding", help="codificação do CSV (padrão: UTF-8, ou cp1252 se não for UTF-8)")
    p.add_argument("--modo", choices=["criar", "substituir", "anexar"], default="criar")
    p.add_argument("--ano-carga", type=int, help="acrescenta a coluna ano_carga e registra em pnite_meta.cargas_log")
    p.add_argument("--simular", action="store_true", help="mostra colunas, tipos e DDL sem enviar")
    args = p.parse_args()

    alvo = args.arquivo.resolve()
    if alvo.is_dir():
        arquivos = arquivos_upload(alvo)
        if not arquivos:
            sys.exit(f"Nenhuma planilha em {alvo}")
    elif alvo.is_file():
        arquivos = [alvo]
    else:
        sys.exit(f"Arquivo ou pasta não encontrado: {alvo}")
    if args.tabela and len(arquivos) > 1:
        sys.exit("--tabela só pode ser usado com um único arquivo.")

    falhas = []
    for caminho in arquivos:
        try:
            if not importar_arquivo(caminho, args):
                falhas.append((caminho.name, "contagem divergente"))
        except ErroImportacao as e:
            print(f"  [ERRO] {caminho.name}: {e}")
            falhas.append((caminho.name, str(e)))
    if len(arquivos) > 1:
        print(f"\n{len(arquivos) - len(falhas)} de {len(arquivos)} arquivo(s) importado(s).")
        for nome, motivo in falhas:
            print(f"  falhou: {nome} — {motivo}")
    sys.exit(1 if falhas else 0)


if __name__ == "__main__":
    main()
