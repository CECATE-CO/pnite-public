"""
PNITE — Cliente mínimo da API do Supabase (self-hosted) usado pelos scripts de carga.

O Postgres do servidor não é acessível diretamente (portas 5432/6543 fechadas), então
todo SQL administrativo (migrações e carga) é enviado pelo endpoint HTTPS ``/pg/query``
(postgres-meta), autenticado com a chave secreta do ``.env``.

O gateway (Cloudflare) encerra a requisição HTTP após ~30 s, mas o comando continua no
banco até terminar. Comandos que podem passar disso (migrações, atualização das views)
usam ``executar_sql_longo``: envio único, sem repetição, e espera pelo término no próprio
banco (``pg_stat_activity``).

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
    def __init__(self, mensagem, status=None):
        super().__init__(mensagem)
        self.status = status


# Tempo esgotado no gateway: o comando pode continuar no banco, então não é repetido.
STATUS_TEMPO_GATEWAY = {504, 522, 524}


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
        # Erros de SQL (400), corpo grande demais e tempo esgotado no gateway não são repetidos
        # (no último caso o comando pode seguir no banco); demais erros de gateway (5xx/429) sim.
        if ((resp.status_code >= 500 or resp.status_code == 429) and "too large" not in resp.text
                and resp.status_code not in STATUS_TEMPO_GATEWAY):
            if tentativa < tentativas:
                print(f"    [HTTP {resp.status_code}] nova tentativa em {5 * tentativa}s", flush=True)
                time.sleep(5 * tentativa)
                continue
        try:
            msg = resp.json().get("message") or resp.text
        except ValueError:
            msg = resp.text
        raise ErroSQL(f"HTTP {resp.status_code}: {msg[:2000]}", resp.status_code)


def executar_sql_longo(query, intervalo=5, limite=3600):
    """Executa SQL que pode passar do tempo do gateway (~30 s).

    Envia uma única vez. Se a resposta chega a tempo, devolve as linhas como ``executar_sql``.
    Se o gateway desiste, aguarda no banco o fim do comando (identificado por um marcador em
    ``pg_stat_activity``) e devolve ``None``: o chamador confere o efeito (ex.: migração
    registrada), pois um erro ocorrido depois do corte não chega ao cliente.
    """
    marcador = f"pnite-longo-{secrets.token_hex(8)}"
    try:
        return executar_sql(f"/* {marcador} */ " + query, tentativas=1, timeout=limite)
    except ErroSQL as e:
        if e.status not in STATUS_TEMPO_GATEWAY:
            raise
    except requests.Timeout:
        pass
    print("    [gateway] tempo de resposta esgotado; aguardando o término no banco...", flush=True)
    inicio = time.time()
    while time.time() - inicio < limite:
        time.sleep(intervalo)
        ativos = executar_sql("SELECT count(*) AS n FROM pg_stat_activity "
                              f"WHERE pid <> pg_backend_pid() AND query LIKE '%{marcador}%';")[0]["n"]
        if not ativos:
            print(f"    [banco] comando concluído em ~{time.time() - inicio + 30:.0f}s", flush=True)
            return None
    raise ErroSQL(f"Comando ainda em execução no banco após {limite}s (marcador {marcador}).")


def literal_dolar(texto):
    """Envolve ``texto`` em dollar-quoting com tag aleatória que não ocorre no conteúdo."""
    while True:
        tag = f"$p{secrets.token_hex(6)}$"
        if tag not in texto:
            return f"{tag}{texto}{tag}"
