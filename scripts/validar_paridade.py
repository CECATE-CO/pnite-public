"""
PNITE — Teste de paridade: API do Supabase (public.indicadores) × pacote compilado atual
(data/Transporte Escolar/pnite_dados_consolidados.json, gerado pelo scripts/extrair_dados_excel.py).

Lê a API com a chave publishable (mesmo caminho do front-end) e compara, campo a campo:
  - DATA (indicadores) e RAW_DATA dos escopos estaduais/regionais/nacional;
  - contadores municipais (municipios_rotas, _alunos, _cobertura, _motoristas, _monitores).

Uso:
    python scripts/validar_paridade.py --uf go     # piloto: GO e seus municípios
    python scripts/validar_paridade.py             # todos os escopos
"""

import argparse
import json
import os
import sys
from collections import Counter, defaultdict
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
from supabase_api import RAIZ  # noqa: E402  (carrega o .env)

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

PACOTE = RAIZ / "data" / "Transporte Escolar" / "pnite_dados_consolidados.json"
TOLERANCIA = 0.011  # arredondamento em 2 casas (Python float × PostgreSQL numeric)

# campo do pacote municipal -> campo de raw na API
MAPA_MUNICIPAL = {
    "municipios_rotas": {"rotas": "tot_rotas", "geo": "georref", "imped": "dif", "km_total": "km_total",
                         "km_geo": "km_geo", "km_medio": "km_medio", "tempo_mediano": "tempo_mediano",
                         "tempo_medio": "tempo_medio", "porteira": "rot_porteira", "mataburro": "rot_mataburro",
                         "colchete": "rot_colchete", "atoleiro": "rot_atoleiro", "ponte": "rot_ponte"},
    "municipios_alunos": {"total": "al_cad", "pcd": "al_pcd", "pari": "al_dif", "porteira": "al_porteira",
                          "mataburro": "al_mataburro", "colchete": "al_colchete", "atoleiro": "al_atoleiro",
                          "ponte": "al_ponte"},
    "municipios_cobertura": {"demanda_censo": "demanda_censo", "atendidos_sete": "al_transp_sete"},
    "municipios_motoristas": {"tot": "tot_mot_info", "outro": "mot_sem_vinculo", "cv": "mot_cv"},
    "municipios_monitores": {"tot": "tot_mon", "outro": "mon_sem_vinculo", "cv": "mon_cv"},
}


def buscar(params, pagina=1000):
    """Lê todas as linhas, paginando: o PostgREST do servidor limita cada resposta a 1000 linhas."""
    url = os.environ["SUPABASE_URL"].rstrip("/") + "/rest/v1/indicadores"
    chave = os.environ["SUPABASE_PUBLISHABLE_KEY"]
    linhas = []
    while True:
        resp = requests.get(url, params={**params, "order": "nivel,chave", "limit": pagina, "offset": len(linhas)},
                            headers={"apikey": chave}, timeout=60)
        resp.raise_for_status()
        lote = resp.json()
        linhas += lote
        if len(lote) < pagina:
            return linhas


def igual(a, b):
    if a is None or b is None:
        return a is None and b is None
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return abs(float(a) - float(b)) <= TOLERANCIA
    return a == b


def main():
    p = argparse.ArgumentParser(description="Paridade API × pacote compilado.")
    p.add_argument("--uf", help="restringe a uma UF (ex.: go)")
    p.add_argument("--ano-carga", default=os.getenv("ANO_CARGA_SETE", "2026"))
    p.add_argument("--exemplos", type=int, default=5)
    args = p.parse_args()

    pacote = json.loads(PACOTE.read_text(encoding="utf-8"))
    filtro = {"ano_carga": f"eq.{args.ano_carga}"}
    if args.uf:
        filtro["uf"] = f"eq.{args.uf.lower()}"
    linhas = buscar({**filtro, "select": "nivel,chave,uf,label,raw,indicadores"})
    print(f"API: {len(linhas)} escopos lidos ({Counter(r['nivel'] for r in linhas)})")

    divergencias = defaultdict(list)
    comparados = Counter()

    for r in linhas:
        nivel, chave = r["nivel"], r["chave"]
        if nivel == "municipio":
            for bloco, mapa in MAPA_MUNICIPAL.items():
                ref = pacote.get(bloco, {}).get(chave)
                if ref is None:
                    continue
                for campo_ref, campo_api in mapa.items():
                    if campo_ref not in ref:
                        continue
                    comparados[f"municipio.{campo_api}"] += 1
                    if not igual(ref[campo_ref], r["raw"].get(campo_api)):
                        divergencias[f"municipio.{campo_api}"].append((chave, ref[campo_ref], r["raw"].get(campo_api)))
            continue
        if args.uf and nivel != "estado":
            continue  # no piloto, região/Brasil só contêm a UF carregada
        ref_data = pacote["DATA"]["nacional"] if nivel == "nacional" else pacote["DATA"][nivel].get(chave)
        ref_raw = pacote["RAW_DATA"].get(chave, {})
        for k, v in (ref_data or {}).items():
            comparados[f"{nivel}.DATA.{k}"] += 1
            if not igual(v, r["indicadores"].get(k)):
                divergencias[f"{nivel}.DATA.{k}"].append((chave, v, r["indicadores"].get(k)))
        for k, v in ref_raw.items():
            comparados[f"{nivel}.RAW.{k}"] += 1
            if not igual(v, r["raw"].get(k)):
                divergencias[f"{nivel}.RAW.{k}"].append((chave, v, r["raw"].get(k)))

    total = sum(comparados.values())
    erros = sum(len(v) for v in divergencias.values())
    print(f"Comparações: {total:,} | divergências: {erros:,} em {len(divergencias)} campos")
    for campo in sorted(divergencias):
        lista = divergencias[campo]
        print(f"  {campo}: {len(lista)}/{comparados[campo]} divergentes")
        for chave, ref, api in lista[:args.exemplos]:
            print(f"      {chave}: pacote={ref!r}  api={api!r}")
    sys.exit(1 if erros else 0)


if __name__ == "__main__":
    main()
