"""
PNITE — Exemplo de consulta autenticada à API REST do Supabase (Python).

Fluxo:
1. Autentica o usuário (USER_ID / USER_PASSWORD) no Supabase Auth usando a
   chave publicável (SUPABASE_PUBLISHABLE_KEY) e obtém um access_token (JWT);
2. Consulta a tabela dado_bruto_rotas pelo PostgREST (/rest/v1) enviando o
   token no cabeçalho Authorization. As tabelas dado_bruto_* têm RLS ativo e só
   liberam SELECT ao papel "authenticated" — sem login a API responde HTTP 401.

Uso:
    pip install requests python-dotenv truststore
    python scripts/pegar_dado_rota.py [UF] [LIMITE]
    python scripts/pegar_dado_rota.py GO 5
"""

import os
import sys
from pathlib import Path

import requests
from dotenv import load_dotenv

try:
    # Usa o repositório de certificados do sistema operacional (necessário quando
    # antivírus/proxy corporativo inspeciona TLS com uma CA própria).
    import truststore
    truststore.inject_into_ssl()
except ImportError:
    pass

load_dotenv(Path(__file__).resolve().parent.parent / ".env")

PROJECT_URL = os.environ["PROJECT_URL"].rstrip("/")
CHAVE_PUBLICAVEL = os.environ["SUPABASE_PUBLISHABLE_KEY"]


def autenticar(email, senha):
    """Login por e-mail/senha no Supabase Auth; retorna o access_token (JWT)."""
    resp = requests.post(
        f"{PROJECT_URL}/auth/v1/token",
        params={"grant_type": "password"},
        headers={"apikey": CHAVE_PUBLICAVEL, "Content-Type": "application/json"},
        json={"email": email, "password": senha},
        timeout=30,
    )
    resp.raise_for_status()
    return resp.json()["access_token"]


def pegar_rotas(token, uf=None, limite=10, offset=0):
    """Busca rotas (sem a coluna shape, que pode ter vários MB por linha)."""
    params = {
        "select": "ano_carga,codigo_cidade,nome_cidade,uf,id_rota,nome,km,tempo,tipo,ativo",
        "order": "codigo_cidade.asc,id_rota.asc",
        "limit": limite,
        "offset": offset,
    }
    if uf:
        params["uf"] = f"eq.{uf.upper()}"  # filtros PostgREST: eq, gt, lt, in.(...), ilike etc.
    resp = requests.get(
        f"{PROJECT_URL}/rest/v1/dado_bruto_rotas",
        params=params,
        headers={
            "apikey": CHAVE_PUBLICAVEL,
            "Authorization": f"Bearer {token}",
            "Prefer": "count=exact",  # total de registros retornado em Content-Range
        },
        timeout=60,
    )
    resp.raise_for_status()
    total = resp.headers.get("Content-Range", "*/?").split("/")[-1]
    return resp.json(), total


def pegar_shape(token, codigo_cidade, id_rota):
    """Busca o GeoJSON (shape) de uma rota específica (chave: codigo_cidade + id_rota)."""
    resp = requests.get(
        f"{PROJECT_URL}/rest/v1/dado_bruto_rotas",
        params={"select": "shape", "codigo_cidade": f"eq.{codigo_cidade}", "id_rota": f"eq.{id_rota}"},
        headers={"apikey": CHAVE_PUBLICAVEL, "Authorization": f"Bearer {token}"},
        timeout=120,
    )
    resp.raise_for_status()
    dados = resp.json()
    return dados[0]["shape"] if dados else None


if __name__ == "__main__":
    uf = sys.argv[1] if len(sys.argv) > 1 else None
    limite = int(sys.argv[2]) if len(sys.argv) > 2 else 10

    token = autenticar(os.environ["USER_ID"], os.environ["USER_PASSWORD"])
    rotas, total = pegar_rotas(token, uf=uf, limite=limite)
    print(f"Total de rotas{f' em {uf.upper()}' if uf else ''}: {total} — exibindo {len(rotas)}")
    for r in rotas:
        print(f"  {r['uf']} | {r['nome_cidade']:<28} | rota {r['id_rota']:>6} | {r['km']:>8} km | {r['nome']}")

    if rotas:
        shape = pegar_shape(token, rotas[0]["codigo_cidade"], rotas[0]["id_rota"])
        print(f"Shape da 1ª rota: {len(shape):,} caracteres" if shape else "1ª rota sem shape cadastrado")
