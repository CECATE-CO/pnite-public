"""
PNITE — Aplica as migrações SQL de ``supabase/migrations`` no Supabase via API (/pg/query).

Cada arquivo é executado uma única vez, em ordem alfabética, numa transação; os aplicados
ficam registrados em ``pnite_meta.migracoes``.

Uso:
    python scripts/supabase_migrar.py            # aplica as pendentes
    python scripts/supabase_migrar.py --listar   # mostra o estado de cada arquivo
"""

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from supabase_api import RAIZ, ErroSQL, executar_sql  # noqa: E402

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

PASTA = RAIZ / "supabase" / "migrations"


def aplicadas():
    existe = executar_sql("SELECT to_regclass('pnite_meta.migracoes') IS NOT NULL AS ok;")[0]["ok"]
    if not existe:
        return set()
    return {r["arquivo"] for r in executar_sql("SELECT arquivo FROM pnite_meta.migracoes;")}


def main():
    p = argparse.ArgumentParser(description=__doc__.strip().splitlines()[0])
    p.add_argument("--listar", action="store_true")
    args = p.parse_args()

    feitas = aplicadas()
    arquivos = sorted(PASTA.glob("*.sql"))
    for arq in arquivos:
        if args.listar:
            print(f"  [{'x' if arq.name in feitas else ' '}] {arq.name}")
            continue
        if arq.name in feitas:
            continue
        sql = arq.read_text(encoding="utf-8")
        registro = f"INSERT INTO pnite_meta.migracoes (arquivo) VALUES ('{arq.name}');"
        try:
            executar_sql(f"BEGIN;\n{sql}\n{registro}\nCOMMIT;")
        except ErroSQL as e:
            sys.exit(f"Falha em {arq.name}: {e}")
        print(f"  aplicada: {arq.name}")
    if not args.listar:
        executar_sql("NOTIFY pgrst, 'reload schema';")
        print("Migrações em dia.")


if __name__ == "__main__":
    main()
