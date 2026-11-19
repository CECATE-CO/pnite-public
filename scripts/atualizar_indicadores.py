"""
PNITE — Recalcula as views materializadas da cascata (pnite_meta.atualizar_indicadores), para todas
as cargas do SETE, e mostra as cargas disponíveis na interface (public.cargas_sete).

A atualização passa do tempo do gateway (~30 s); o comando segue no banco e o script aguarda o
término (supabase_api.executar_sql_longo) antes de conferir o resultado.

Uso:
    python scripts/atualizar_indicadores.py
"""

import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from supabase_api import executar_sql, executar_sql_longo  # noqa: E402

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")


def main():
    inicio_banco = executar_sql("SELECT now() AS t;")[0]["t"]
    t = time.time()
    executar_sql_longo("SELECT pnite_meta.atualizar_indicadores();")
    atualizado = executar_sql(
        "SELECT max(atualizado_em) > " f"'{inicio_banco}'::timestamptz AS ok FROM public.indicadores_nacional;")[0]["ok"]
    if not atualizado:
        sys.exit("A atualização não terminou corretamente (public.indicadores_nacional não foi renovada). "
                 "Rode de novo para ver a mensagem de erro.")
    print(f"Views atualizadas em {time.time() - t:.0f}s. Cargas disponíveis:")
    for c in executar_sql("SELECT carga, rotulo, atual FROM public.cargas_sete ORDER BY carga;"):
        print(f"  {c['carga']}  {c['rotulo']}" + ("  (atual)" if c["atual"] else ""))


if __name__ == "__main__":
    main()
