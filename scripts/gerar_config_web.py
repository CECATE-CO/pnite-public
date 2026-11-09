"""
PNITE — Gera ``config.local.js`` (raiz do projeto) a partir do ``.env``.

O navegador não lê o ``.env``; este script copia para o front-end SOMENTE o que é
público por definição: a URL do Supabase, a chave publishable (que só lê as views
públicas de indicadores) e o ano de carga. A chave secreta e as senhas nunca saem
do ``.env``. O arquivo gerado fica fora do Git (.gitignore).

Uso:
    python scripts/gerar_config_web.py
"""

import json
import os
import sys
from pathlib import Path

try:
    from dotenv import load_dotenv
except ImportError:
    def load_dotenv(path):
        p = Path(path)
        if not p.exists():
            return
        with open(p, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    k, v = line.split('=', 1)
                    k = k.strip()
                    v = v.strip().strip('"').strip("'")
                    os.environ[k] = v

RAIZ = Path(__file__).resolve().parent.parent
PERMITIDAS = {"SUPABASE_URL": "supabaseUrl", "SUPABASE_PUBLISHABLE_KEY": "publishableKey",
              "ANO_CARGA_SETE": "anoCarga"}


def main():
    load_dotenv(RAIZ / ".env")
    faltando = [v for v in PERMITIDAS if not os.getenv(v)]
    if faltando:
        sys.exit(f"Variáveis ausentes no .env: {', '.join(faltando)}")
    chave = os.environ["SUPABASE_PUBLISHABLE_KEY"]
    if not chave.startswith("sb_publishable_"):
        sys.exit("SUPABASE_PUBLISHABLE_KEY não parece uma chave publishable; nada foi gerado.")
    config = {destino: os.environ[origem] for origem, destino in PERMITIDAS.items()}
    config["supabaseUrl"] = config["supabaseUrl"].rstrip("/")
    config["anoCarga"] = int(config["anoCarga"])
    destino = RAIZ / "config.local.js"
    destino.write_text(
        "// Gerado por scripts/gerar_config_web.py a partir do .env — não versionar.\n"
        "// Contém apenas valores públicos (URL e chave publishable).\n"
        f"window.PNITE_CONFIG = {json.dumps(config, ensure_ascii=False, indent=2)};\n",
        encoding="utf-8")
    print(f"Gerado: {destino.name}")


if __name__ == "__main__":
    main()
