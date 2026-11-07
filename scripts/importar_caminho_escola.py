"""
PNITE — Carga das fontes do Programa Caminho da Escola e dos snapshots dos painéis FNDE.

Grava no Supabase (schemas privados ``gestao``/``catalogo``, migração 0018):

* CSV de contratações (``Base_Caminho_da_Escola_HMG.csv``) -> ``gestao.ce_contratacao_itens``,
  uma linha por linha do arquivo (número da linha, hash, flags de qualidade), numa nova
  ``gestao.dataset_versoes`` da fonte ``caminho_contratacoes``;
* XLSX de extração (``Extracao_dois_paineis_FNDE.xlsx``) -> ``gestao.snapshots_paineis`` (abas
  documentais/snapshots) e ``gestao.pendencias_qualidade`` (aba Auditoria), fonte
  ``paineis_fnde_snapshot``. A aba ``Base_Contratacoes`` NÃO é carregada: é equivalente ao CSV
  (conferido linha a linha) e somá-la duplicaria as contratações.

Regras:
* idempotente por hash SHA-256: o mesmo arquivo não é carregado duas vezes (a versão existente
  é informada e reaproveitada);
* moeda em formato brasileiro (``R$ 1.234,56``) lida com ``Decimal``; vazio vira NULL;
  marcador ``'-`` em termo/processo vira NULL com flag;
* ao final a carga fica ``validada`` (contagens e somas conferidas). Ativar é um passo separado
  (``--ativar`` aqui, ou "Fontes e cargas" na área administrativa) e não publica indicadores.

Uso (na raiz, com o .env):
    python scripts/importar_caminho_escola.py --csv CAMINHO.csv --xlsx CAMINHO.xlsx
    python scripts/importar_caminho_escola.py --csv CAMINHO.csv --ativar "motivo"
"""

import argparse
import csv
import hashlib
import json
import re
import sys
from datetime import date, datetime
from decimal import Decimal, InvalidOperation
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from criar_banco_dados_brutos import enviar_linhas, sql_literal  # noqa: E402
from supabase_api import executar_sql  # noqa: E402

for _s in (sys.stdout, sys.stderr):
    if hasattr(_s, "reconfigure"):
        _s.reconfigure(encoding="utf-8")

IMPORTADOR = "importar_caminho_escola.py 1.0"
CABECALHO = ["Ano", "Cód IBGE", "Termo de Compromisso", "Número Processo", "Região", "UF", "Município", "Esfera",
             "Entidade", "Veículos Contratados", "Quantidade", "Valor Unitário do Veículo",
             "Valor Total da Contratação", "Forma de Pagamento", "Resultado Primário", "Data da Contratação",
             "Nome do Fornecedor", "Pregão"]
COLUNAS = [("dataset_versao_id", "bigint"), ("source_row_number", "integer"), ("row_hash", "text"),
           ("ano_contratacao", "smallint"), ("codigo_territorial_origem", "text"), ("termo_compromisso", "text"),
           ("numero_processo", "text"), ("regiao_origem", "text"), ("uf_origem", "text"),
           ("municipio_nome_origem", "text"), ("esfera_administrativa", "text"), ("entidade_nome", "text"),
           ("tipo_veiculo_origem", "text"), ("quantidade", "integer"), ("valor_unitario", "numeric"),
           ("valor_total", "numeric"), ("forma_pagamento_origem", "text"), ("resultado_primario_origem", "text"),
           ("data_contratacao_origem", "date"), ("fornecedor_nome", "text"), ("pregao_origem", "text"),
           ("flag_termo_marcador", "boolean"), ("flag_processo_marcador", "boolean"),
           ("flag_unitario_ausente", "boolean"), ("flag_produto_divergente", "boolean")]
MARCADOR = {"'-", "-"}
LOTE = 1500


class ErroCarga(RuntimeError):
    pass


def sha256(caminho):
    h = hashlib.sha256()
    with open(caminho, "rb") as fh:
        for bloco in iter(lambda: fh.read(1 << 20), b""):
            h.update(bloco)
    return h.hexdigest()


def texto(v):
    v = (v or "").replace("\x00", "").strip()
    return v or None


def moeda(v):
    """'R$ 227780,00' / 'R$ 1.234,56' / '227780.5' -> Decimal; vazio -> None."""
    v = texto(v)
    if v is None:
        return None
    s = re.sub(r"[R$\s ]", "", v)
    if "," in s:                       # formato brasileiro: ponto = milhar, vírgula = decimal
        s = s.replace(".", "").replace(",", ".")
    try:
        return Decimal(s).quantize(Decimal("0.01"))
    except InvalidOperation:
        raise ErroCarga(f"valor monetário inválido: {v!r}")


def data_iso(v):
    v = texto(v)
    if v is None:
        return None
    if re.match(r"^\d{4}-\d{2}-\d{2}", v):
        return date.fromisoformat(v[:10])
    if re.match(r"^\d{2}/\d{2}/\d{4}$", v):          # declarado: DD/MM/AAAA (padrão brasileiro)
        return datetime.strptime(v, "%d/%m/%Y").date()
    raise ErroCarga(f"data inválida: {v!r}")


def versao_existente(fonte, hash_):
    r = executar_sql(f"SELECT id, status FROM gestao.dataset_versoes WHERE fonte = {sql_literal(fonte)} "
                     f"AND sha256 = {sql_literal(hash_)};")
    return r[0] if r else None


def nova_versao(fonte, caminho, hash_, data_captura=None):
    return executar_sql(
        "INSERT INTO gestao.dataset_versoes (fonte, arquivo, sha256, bytes, data_captura, importador, responsavel) VALUES ("
        f"{sql_literal(fonte)}, {sql_literal(caminho.name)}, {sql_literal(hash_)}, {caminho.stat().st_size}, "
        f"{sql_literal(data_captura.isoformat()) if data_captura else 'NULL'}, {sql_literal(IMPORTADOR)}, 'carga via script') "
        "RETURNING id;")[0]["id"]


def carregar_csv(caminho):
    hash_ = sha256(caminho)
    ja = versao_existente("caminho_contratacoes", hash_)
    if ja:
        print(f"CSV já carregado (versão {ja['id']}, {ja['status']}); nada a fazer.")
        return ja["id"]
    with open(caminho, encoding="utf-8-sig", newline="") as fh:
        leitor = csv.reader(fh)
        cab = [c.strip() for c in next(leitor)]
        if cab != CABECALHO:
            raise ErroCarga(f"cabeçalho diferente do esperado: {cab}")
        registros = list(leitor)

    vid = nova_versao("caminho_contratacoes", caminho, hash_)
    print(f"Versão {vid} criada para {caminho.name} ({hash_[:12]}…); {len(registros):,} linhas.")
    linhas, soma_q, soma_v, alertas, datas = [], 0, Decimal(0), 0, []
    try:
        for n, r in enumerate(registros, start=2):
            if len(r) != len(CABECALHO):
                raise ErroCarga(f"linha {n}: {len(r)} colunas (esperado {len(CABECALHO)})")
            ano, cod, termo, proc, reg, uf, mun, esf, ent, tipo, qtd, unit, tot, forma, rp, dt, forn, preg = r
            termo_t, proc_t = texto(termo), texto(proc)
            f_termo, f_proc = termo_t in MARCADOR, proc_t in MARCADOR
            q = int(texto(qtd)) if texto(qtd) is not None else None
            u, t = moeda(unit), moeda(tot)
            d = data_iso(dt)
            f_unit = u is None
            f_div = (q is not None and u is not None and t is not None and abs(q * u - t) > Decimal("0.01"))
            if f_unit or f_div:
                alertas += 1
            if q is not None:
                soma_q += q
            if t is not None:
                soma_v += t
            if d:
                datas.append(d)
            h = hashlib.sha256("\x1f".join(r).encode("utf-8")).hexdigest()
            vals = [vid, n, h, texto(ano), texto(cod), None if f_termo else termo_t, None if f_proc else proc_t,
                    texto(reg), (texto(uf) or "").upper() or None, texto(mun), texto(esf), texto(ent), texto(tipo),
                    q, u, t, texto(forma), texto(rp), d, texto(forn), texto(preg), f_termo, f_proc, f_unit, f_div]
            linhas.append([None if v is None else (("true" if v else "false") if isinstance(v, bool) else str(v))
                           for v in vals])
            if len(linhas) >= LOTE:
                enviar_linhas("gestao.ce_contratacao_itens", COLUNAS, linhas)
                linhas = []
        enviar_linhas("gestao.ce_contratacao_itens", COLUNAS, linhas)

        banco = executar_sql(f"SELECT count(*) n, sum(quantidade) q, sum(valor_total) v FROM gestao.ce_contratacao_itens "
                             f"WHERE dataset_versao_id = {vid};")[0]
        ok = int(banco["n"]) == len(registros) and int(banco["q"] or 0) == soma_q and Decimal(str(banco["v"] or 0)) == soma_v
        if not ok:
            raise ErroCarga(f"conferência falhou: banco {banco}, arquivo n={len(registros)} q={soma_q} v={soma_v}")
        executar_sql(
            f"UPDATE gestao.dataset_versoes SET status = 'validada', linhas = {len(registros)}, "
            f"linhas_com_alerta = {alertas}, soma_quantidade = {soma_q}, soma_valor_total = {soma_v}, "
            f"periodo_inicio = {sql_literal(min(datas).isoformat()) if datas else 'NULL'}, "
            f"periodo_fim = {sql_literal(max(datas).isoformat()) if datas else 'NULL'} WHERE id = {vid};")
        print(f"  validada: {len(registros):,} linhas, quantidade {soma_q:,}, valor R$ {soma_v:,.2f}, "
              f"{alertas} linha(s) com alerta.")
        return vid
    except Exception:
        executar_sql(f"UPDATE gestao.dataset_versoes SET status = 'rejeitada' WHERE id = {vid};")
        raise


def num(v):
    if isinstance(v, (int, float)) and not isinstance(v, bool):
        return Decimal(str(v))
    return None


def carregar_xlsx(caminho):
    import openpyxl
    hash_ = sha256(caminho)
    ja = versao_existente("paineis_fnde_snapshot", hash_)
    if ja:
        print(f"XLSX já carregado (versão {ja['id']}, {ja['status']}); nada a fazer.")
        return ja["id"]
    wb = openpyxl.load_workbook(caminho, read_only=True, data_only=True)
    abas = {ws.title: [list(r) for r in ws.iter_rows(values_only=True)] for ws in wb.worksheets}
    captura = None
    for r in abas.get("Leia-me", []):
        if r and r[0] and "Data da extra" in str(r[0]) and r[1]:
            captura = r[1].date() if isinstance(r[1], datetime) else datetime.strptime(str(r[1]).strip(), "%d/%m/%Y").date()
    vid = nova_versao("paineis_fnde_snapshot", caminho, hash_, captura)
    print(f"Versão {vid} criada para {caminho.name} (captura {captura}); abas: {', '.join(abas)}.")
    painel_da_aba = {"SETE_Indicadores": "sete", "SETE_Séries": "sete", "Caminho_Painel": "caminho",
                     "Leia-me": "documentacao", "Agregados_CSV": "documentacao", "Fontes": "documentacao"}
    cols = [("dataset_versao_id", "bigint"), ("painel", "text"), ("aba", "text"), ("ordem", "integer"),
            ("pagina", "text"), ("indicador", "text"), ("categoria", "text"), ("valor", "numeric"),
            ("unidade", "text"), ("observacao", "text"), ("linha", "jsonb"), ("source_type", "text")]
    try:
        total = 0
        for aba, painel in painel_da_aba.items():
            linhas_aba = abas.get(aba)
            if not linhas_aba:
                print(f"  [aviso] aba {aba!r} ausente")
                continue
            tabular = aba != "Leia-me"
            cab = [str(c).strip() if c is not None else "" for c in linhas_aba[0]] if tabular else ["Campo", "Valor"]
            corpo = linhas_aba[1:] if tabular else linhas_aba
            enviar = []
            for ordem, r in enumerate(corpo, start=1):
                if not any(c not in (None, "") for c in r):
                    continue
                d = {cab[i] if i < len(cab) and cab[i] else f"col{i + 1}":
                     (c.isoformat() if isinstance(c, (datetime, date)) else c) for i, c in enumerate(r) if c is not None}
                g = lambda *nomes: next((d[n] for n in nomes if n in d), None)  # noqa: E731
                valor = num(g("Valor"))
                vals = [vid, painel, aba, ordem, g("Página", "Painel", "Tipo"), g("Indicador", "Fonte/agregado", "Fonte", "Campo"),
                        g("Categoria"), valor, g("Unidade"), g("Observação", "Origem/observação", "URL/arquivo", "Valor") if valor is None else g("Observação"),
                        json.dumps(d, ensure_ascii=False, default=str), "panel_snapshot" if painel != "documentacao" else "documentacao"]
                enviar.append([None if v is None else str(v) for v in vals])
            enviar_linhas("gestao.snapshots_paineis", cols, enviar)
            total += len(enviar)
            print(f"  {aba}: {len(enviar)} registro(s)")
        aud = abas.get("Auditoria") or []
        cab = [str(c).strip() for c in aud[0]] if aud else []
        pend = []
        for r in aud[1:]:
            if not any(r):
                continue
            d = dict(zip(cab, r))
            pend.append([str(vid), str(d.get("Painel") or ""), str(d.get("Verificação") or ""),
                         None if num(d.get("Valor")) is None else str(num(d.get("Valor"))), str(d.get("Origem/observação") or "")])
        enviar_linhas("gestao.pendencias_qualidade",
                      [("dataset_versao_id", "bigint"), ("painel", "text"), ("verificacao", "text"), ("valor", "numeric"), ("origem", "text")],
                      pend)
        print(f"  Auditoria: {len(pend)} pendência(s) de qualidade")
        print("  Base_Contratacoes: não carregada (equivalente ao CSV; fonte canônica = CSV).")
        executar_sql(f"UPDATE gestao.dataset_versoes SET status = 'validada', linhas = {total}, "
                     f"periodo_inicio = {sql_literal(captura.isoformat()) if captura else 'NULL'}, "
                     f"periodo_fim = {sql_literal(captura.isoformat()) if captura else 'NULL'} WHERE id = {vid};")
        return vid
    except Exception:
        executar_sql(f"UPDATE gestao.dataset_versoes SET status = 'rejeitada' WHERE id = {vid};")
        raise


def ativar(vid, motivo):
    r = executar_sql(f"SELECT fonte, status FROM gestao.dataset_versoes WHERE id = {vid};")[0]
    if r["status"] == "ativa":
        print(f"  versão {vid} já está ativa.")
        return
    if r["status"] not in ("validada", "inativa"):
        raise ErroCarga(f"versão {vid} está {r['status']}; só cargas validadas podem ser ativadas")
    executar_sql(
        "BEGIN;"
        f"UPDATE gestao.dataset_versoes SET status = 'inativa' WHERE fonte = {sql_literal(r['fonte'])} AND status = 'ativa';"
        f"UPDATE gestao.dataset_versoes SET status = 'ativa', ativada_em = now(), ativada_por = 'script' WHERE id = {vid};"
        f"SELECT catalogo.auditar('script ({IMPORTADOR})', 'ativar_carga', 'dataset_versao', '{vid}', NULL, "
        f"jsonb_build_object('fonte', {sql_literal(r['fonte'])}), {sql_literal(motivo)});"
        "COMMIT;")
    print(f"  versão {vid} ({r['fonte']}) ativada.")


def main():
    p = argparse.ArgumentParser(description=__doc__.strip().splitlines()[0])
    p.add_argument("--csv", type=Path, help="Base_Caminho_da_Escola_HMG.csv")
    p.add_argument("--xlsx", type=Path, help="Extracao_dois_paineis_FNDE.xlsx")
    p.add_argument("--ativar", metavar="MOTIVO", help="ativa as versões carregadas (não publica indicadores)")
    a = p.parse_args()
    if not a.csv and not a.xlsx:
        p.error("informe --csv e/ou --xlsx")
    try:
        ids = []
        if a.csv:
            ids.append(carregar_csv(a.csv.resolve()))
        if a.xlsx:
            ids.append(carregar_xlsx(a.xlsx.resolve()))
        if a.ativar:
            for vid in ids:
                ativar(vid, a.ativar)
    except ErroCarga as e:
        sys.exit(f"[ERRO] {e}")


if __name__ == "__main__":
    main()
