"""
PNITE — Carrega a participação oficial nas capacitações (planilha do CECATE-CO) no Supabase.

Fonte: planilha "2024-2026 - Participantes das Capacitações", mantida pela equipe no Google
Planilhas e copiada em Excel para ``upload/`` (fora do Git). Regra registrada em AGENTS.md §45.1.

A planilha tem uma linha por participante ("Participou" = Sim) e uma linha por município
convidado que não participou ("Não"). O script:

- identifica a capacitação de cada linha pela data da formação (entre data_inicio e data_fim
  de ``capacitacao.capacitacoes``) e recusa linhas sem correspondência;
- valida o código IBGE (7 dígitos) e recusa município com "Sim" e "Não" no mesmo evento;
- agrega por capacitação × município: participou, pessoas distintas com "Sim" (CPF ou, sem CPF,
  nome normalizado) e a divisão por cargo (gestor, CACS, outros);
- grava SOMENTE esses agregados em ``capacitacao.participacao_oficial`` (migração 0030), numa
  transação que também atualiza ``capacitacao.participacao_oficial_carga`` e a view pública.

Nome, CPF, e-mail e telefone são lidos apenas em memória para não contar a mesma pessoa duas
vezes; nunca são impressos nem enviados.

Uso (na raiz do repositório, com o ``.env`` preenchido):
    pip install requests python-dotenv openpyxl
    python scripts/importar_capacitacao_oficial.py --simular     # mostra o resumo, não envia
    python scripts/importar_capacitacao_oficial.py               # envia (substitui a carga anterior)
    python scripts/importar_capacitacao_oficial.py "upload/outro nome.xlsx"
"""

import argparse
import re
import sys
import unicodedata
from collections import Counter, defaultdict
from datetime import date, datetime
from pathlib import Path

import openpyxl

sys.path.insert(0, str(Path(__file__).resolve().parent))
from criar_banco_dados_brutos import sql_insert, sql_literal  # noqa: E402
from supabase_api import RAIZ, executar_sql  # noqa: E402

for _saida in (sys.stdout, sys.stderr):
    if hasattr(_saida, "reconfigure"):
        _saida.reconfigure(encoding="utf-8")

PADRAO_ARQUIVO = "*Participantes das Capacita*.xlsx"
FONTE = "Planilha oficial de participantes das capacitações (CECATE-CO/UFG, Google Planilhas)"
UF_POR_PREFIXO = {"50": "MS", "51": "MT", "52": "GO", "53": "DF"}


def chave(texto):
    t = unicodedata.normalize("NFKD", str(texto or ""))
    return re.sub(r"[^a-z0-9]", "", "".join(c for c in t if not unicodedata.combining(c)).lower())


def localizar_arquivo(arg):
    if arg:
        caminho = Path(arg)
        if not caminho.exists():
            sys.exit(f"Arquivo não encontrado: {caminho}")
        return caminho
    candidatos = sorted((RAIZ / "upload").glob(PADRAO_ARQUIVO))
    if len(candidatos) != 1:
        sys.exit(f"Esperado exatamente um arquivo '{PADRAO_ARQUIVO}' em upload/; encontrados: {[c.name for c in candidatos]}")
    return candidatos[0]


def ler_planilha(caminho):
    wb = openpyxl.load_workbook(caminho, read_only=True, data_only=True)
    ws = wb.worksheets[0]
    linhas = [r for r in ws.iter_rows(values_only=True) if any(c not in (None, "") for c in r)]
    wb.close()
    i_cab = next((i for i, r in enumerate(linhas[:10])
                  if any(re.match(r"c.digo ibge", str(c or ""), re.I) for c in r) and any(re.match(r"participou", str(c or ""), re.I) for c in r)), None)
    if i_cab is None:
        sys.exit("Cabeçalho não encontrado (colunas 'Código IBGE' e 'Participou').")
    cab = [str(c or "").strip() for c in linhas[i_cab]]

    def col(padrao):
        idx = [i for i, c in enumerate(cab) if re.match(padrao, c, re.I)]
        if not idx:
            sys.exit(f"Coluna obrigatória ausente: {padrao}")
        return idx[0]

    return linhas[i_cab + 1:], {
        "cod": col(r"c.digo ibge"), "data": col(r"data"), "part": col(r"participou"),
        "cargo": col(r"cargo"), "cpf": col(r"cpf"), "nome": col(r"nome"),
    }


def para_data(v):
    if isinstance(v, datetime):
        return v.date()
    if isinstance(v, date):
        return v
    m = re.match(r"^\s*(\d{1,2})/(\d{1,2})/(\d{4})", str(v or ""))
    return date(int(m.group(3)), int(m.group(2)), int(m.group(1))) if m else None


def segmento(cargo):
    c = chave(cargo)
    if "cacs" in c or "conselh" in c:
        return "cacs"
    if "gest" in c:
        return "gestores"
    return "outros"


def agregar(linhas, c, capacitacoes):
    erros, agg, situacoes = [], defaultdict(lambda: {"sim": set(), "cargos": {}}), defaultdict(set)
    for n_linha, r in enumerate(linhas, start=3):
        cod = r[c["cod"]]
        cod = str(int(cod)) if isinstance(cod, (int, float)) else str(cod or "").strip()
        if not re.fullmatch(r"\d{7}", cod):
            erros.append(f"linha {n_linha}: código IBGE inválido ({cod!r})")
            continue
        d = para_data(r[c["data"]])
        caps = [cap["numero"] for cap in capacitacoes if d and cap["data_inicio"] <= d <= cap["data_fim"]]
        if len(caps) != 1:
            erros.append(f"linha {n_linha}: data {r[c['data']]!r} não corresponde a uma única capacitação")
            continue
        part = chave(r[c["part"]])
        if part not in ("sim", "nao"):
            erros.append(f"linha {n_linha}: 'Participou' inválido ({r[c['part']]!r})")
            continue
        k = (caps[0], cod)
        situacoes[k].add(part)
        agg[k]  # garante a linha do município também quando só há "Não"
        if part == "sim":
            pessoa = re.sub(r"\D", "", str(r[c["cpf"]] or "")) or chave(r[c["nome"]])
            if not pessoa:
                erros.append(f"linha {n_linha}: participante sem CPF e sem nome")
                continue
            agg[k]["sim"].add(pessoa)
            agg[k]["cargos"].setdefault(pessoa, segmento(r[c["cargo"]]))
    for (cap, cod), s in situacoes.items():
        if len(s) > 1:
            erros.append(f"capacitação {cap}, município {cod}: 'Sim' e 'Não' no mesmo evento")
    linhas_banco = []
    for (cap, cod), a in sorted(agg.items()):
        seg = Counter(a["cargos"].values())
        linhas_banco.append([cap, cod, bool(a["sim"]), len(a["sim"]), seg["gestores"], seg["cacs"], seg["outros"]])
    return linhas_banco, erros


def resumo(linhas_banco):
    part = [l for l in linhas_banco if l[2]]
    municipios = {l[1] for l in part}
    por_uf = Counter(UF_POR_PREFIXO.get(c[:2], "fora do CO") for c in municipios)
    print(f"Registros município × capacitação: {len(linhas_banco)} ({len(part)} com participação)")
    print(f"Municípios capacitados (distintos): {len(municipios)} {dict(sorted(por_uf.items()))}")
    print("Cap. | municípios com participação | participantes (gestores / CACS / outros)")
    for cap in sorted({l[0] for l in linhas_banco}):
        ls = [l for l in part if l[0] == cap]
        print(f"{cap:4d} | {len(ls):3d} | {sum(l[3] for l in ls):3d} ({sum(l[4] for l in ls)} / {sum(l[5] for l in ls)} / {sum(l[6] for l in ls)})")


def main():
    p = argparse.ArgumentParser(description=__doc__.strip().splitlines()[0])
    p.add_argument("arquivo", nargs="?", help="planilha (padrão: único arquivo de participantes em upload/)")
    p.add_argument("--simular", action="store_true", help="mostra o resumo sem enviar nada")
    args = p.parse_args()

    caminho = localizar_arquivo(args.arquivo)
    linhas, colunas = ler_planilha(caminho)
    capacitacoes = [{"numero": int(r["numero"]), "data_inicio": date.fromisoformat(str(r["data_inicio"])[:10]),
                     "data_fim": date.fromisoformat(str(r["data_fim"])[:10])}
                    for r in executar_sql("SELECT numero, data_inicio::text, data_fim::text FROM capacitacao.capacitacoes ORDER BY numero;")]
    linhas_banco, erros = agregar(linhas, colunas, capacitacoes)
    print(f"Arquivo: {caminho.name} — {len(linhas)} linhas de dados")
    if erros:
        print(f"\n{len(erros)} problema(s); nada foi enviado:")
        for e in erros[:50]:
            print(" -", e)
        sys.exit(1)
    resumo(linhas_banco)
    if args.simular:
        print("\nSimulação: nada foi enviado.")
        return

    colunas_banco = [("seq", "integer"), ("capacitacao", "smallint"), ("cod_ibge", "char(7)"), ("participou", "boolean"),
                     ("presentes_total", "integer"), ("presentes_gestores", "integer"), ("presentes_cacs", "integer"), ("presentes_outros", "integer")]
    agora = datetime.now().strftime("%Y-%m-%d %H:%M")
    sql = "\n".join([
        "BEGIN;",
        "TRUNCATE capacitacao.participacao_oficial, capacitacao.participacao_oficial_carga;",
        sql_insert("capacitacao.participacao_oficial", colunas_banco, [[i + 1, *l] for i, l in enumerate(linhas_banco)]),
        "INSERT INTO capacitacao.participacao_oficial_carga (arquivo, carregado_em, linhas, fonte) VALUES ("
        f"{sql_literal(caminho.name)}, {sql_literal(agora)}, {len(linhas)}, {sql_literal(FONTE)});",
        "REFRESH MATERIALIZED VIEW public.capacitacao_dados;",
        "COMMIT;",
    ])
    executar_sql(sql)
    gravadas = executar_sql("SELECT count(*) AS n FROM capacitacao.participacao_oficial;")[0]["n"]
    print(f"\nGravado: {gravadas} registro(s) em capacitacao.participacao_oficial"
          + (" — OK" if gravadas == len(linhas_banco) else f" — DIVERGENTE (esperado {len(linhas_banco)})"))


if __name__ == "__main__":
    sys.exit(main())
