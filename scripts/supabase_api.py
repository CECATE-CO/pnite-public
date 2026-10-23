"""
PNITE — Cliente mínimo da API do Supabase (self-hosted) usado pelos scripts de carga.

O Postgres do servidor não é acessível diretamente (portas 5432/6543 fechadas), então
todo SQL administrativo (migrações e carga) é enviado pelo endpoint HTTPS ``/pg/query``
(postgres-meta), autenticado com a chave secreta do ``.env``.

A chave secreta dá acesso total ao banco: nunca a use no front-end nem a versione.
"""

import json
import os
import secrets
import sys
import time
from pathlib import Path

import requests
from dotenv import load_dotenv

RAIZ = Path(__file__).resolve().parent.parent
load_dotenv(RAIZ / ".env")


# O postgres-meta do servidor recusa corpos acima de ~2 MB ("Request body is too large").
LIMITE_CORPO = 1_900_000


class ErroSQL(RuntimeError):
    pass


def tamanho_corpo(query):
    """Tamanho em bytes do corpo HTTP que executar_sql enviaria para ``query``."""
    return len(json.dumps({"query": query}, ensure_ascii=False).encode("utf-8"))


def _config():
    faltando = [v for v in ("SUPABASE_URL", "SUPABASE_SECRET_KEY") if not os.getenv(v)]
    if faltando:
        sys.exit(f"Variáveis ausentes no .env: {', '.join(faltando)}")
    return os.environ["SUPABASE_URL"].rstrip("/"), os.environ["SUPABASE_SECRET_KEY"]


_sessao = requests.Session()


def executar_sql(query, tentativas=4, timeout=900):
    """Executa SQL via /pg/query e devolve a lista de linhas (dicts) do último comando."""
    url, chave = _config()
    cabecalhos = {"apikey": chave, "Authorization": f"Bearer {chave}", "Content-Type": "application/json"}
    corpo = json.dumps({"query": query}, ensure_ascii=False).encode("utf-8")
    for tentativa in range(1, tentativas + 1):
        try:
            resp = _sessao.post(f"{url}/pg/query", data=corpo, headers=cabecalhos, timeout=timeout)
        except requests.RequestException as e:
            if tentativa == tentativas:
                raise
            print(f"    [rede] {e.__class__.__name__}; nova tentativa em {5 * tentativa}s", flush=True)
            time.sleep(5 * tentativa)
            continue
        if resp.status_code == 200:
            return resp.json()
        # Erros de SQL (400) e corpo grande demais não são repetidos; erros de gateway (5xx/429) sim.
        if (resp.status_code >= 500 or resp.status_code == 429) and "too large" not in resp.text:
            if tentativa < tentativas:
                print(f"    [HTTP {resp.status_code}] nova tentativa em {5 * tentativa}s", flush=True)
                time.sleep(5 * tentativa)
                continue
        try:
            msg = resp.json().get("message") or resp.text
        except ValueError:
            msg = resp.text
        raise ErroSQL(f"HTTP {resp.status_code}: {msg[:2000]}")


def literal_dolar(texto):
    """Envolve ``texto`` em dollar-quoting com tag aleatória que não ocorre no conteúdo."""
    while True:
        tag = f"$p{secrets.token_hex(6)}$"
        if tag not in texto:
            return f"{tag}{texto}{tag}"
