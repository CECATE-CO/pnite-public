import pandas as pd, json, re, numpy as np
from collections import defaultdict

# ---------- DTB ----------
dtb = pd.read_excel('dtb/RELATORIO_DTB_BRASIL_2024_MUNICIPIOS.xls', header=6)
dtb = dtb.rename(columns={'UF':'cod_uf','Código Município Completo':'cod_mun','Nome_Município':'nome_mun'})
SIGLA = {11:'RO',12:'AC',13:'AM',14:'RR',15:'PA',16:'AP',17:'TO',21:'MA',22:'PI',23:'CE',
 24:'RN',25:'PB',26:'PE',27:'AL',28:'SE',29:'BA',31:'MG',32:'ES',33:'RJ',35:'SP',
 41:'PR',42:'SC',43:'RS',50:'MS',51:'MT',52:'GO',53:'DF'}
dtb['cod_mun'] = dtb['cod_mun'].astype(int)
dtb['sigla'] = dtb['cod_uf'].astype(int).map(SIGLA)
LK = dtb.set_index('cod_mun')['sigla'].to_dict()

def norm(s):
    try: c = int(float(s))
    except (ValueError, TypeError): return None
    return c if c in LK else None

I = defaultdict(lambda: dict(tot_rotas=0, georref=0, dif=0, t1=0, t2=0, t3=0,
    tot_veic=0, vp=0, vt=0, nvv=0, cap_sum=0.0,
    tot_mon=0, mon_cv=0, tot_mot_info=0, mot_cv=0, al_cad=0))
al_transp = defaultdict(set)   # cod -> alunos distintos transportados
al_adeq   = defaultdict(set)   # cod -> alunos distintos em rota com veículo adequado
esc_at    = defaultdict(set)   # cod -> escolas distintas atendidas por rota (script_15)

# ---------- rotas: georref, dif, tipos ----------
print('rotas (com shape)...')
DA = ['da_porteira','da_mataburro','da_colchete','da_atoleiro','da_ponterustica']
for ch in pd.read_csv('pdde/script_03_rotas.csv',
        usecols=['codigo_cidade','shape','tipo']+DA, dtype=str, chunksize=50_000):
    ch['c'] = ch['codigo_cidade'].map(norm)
    ch = ch.dropna(subset=['c'])
    ch['g'] = ch['shape'].notna() & (ch['shape'].str.strip() != '')
    ch['d'] = False
    for f in DA: ch['d'] |= (ch[f] == 'S')
    for c, g in ch.groupby(ch['c'].astype(int)):
        d = I[c]
        d['tot_rotas'] += len(g); d['georref'] += int(g['g'].sum()); d['dif'] += int(g['d'].sum())
        t = g['tipo'].value_counts()
        d['t1'] += int(t.get('1',0)); d['t2'] += int(t.get('2',0)); d['t3'] += int(t.get('3',0))

# ---------- veículos ----------
print('veiculos...')
vei = pd.read_csv('pdde/script_04_veiculos.csv',
                  usecols=['codigo_cidade','id_veiculo','origem','capacidade','tipo'], dtype=str)
vei['c'] = vei['codigo_cidade'].map(norm); vei = vei.dropna(subset=['c'])
vei['c'] = vei['c'].astype(int)
vei['cap'] = pd.to_numeric(vei['capacidade'], errors='coerce')
vei['ok'] = (vei['cap'] > 0) & (vei['cap'] <= 70)
for c, g in vei.groupby('c'):
    d = I[c]; d['tot_veic'] += len(g)
    o = g['origem'].value_counts()
    d['vp'] += int(o.get('1',0)); d['vt'] += int(o.get('2',0))
    d['nvv'] += int(g['ok'].sum()); d['cap_sum'] += float(g.loc[g['ok'],'cap'].sum())
# veículos adequados (tipo 1,2,3) por (cod, id_veiculo) — para TETI
adeq_veic = set(zip(vei.loc[vei['tipo'].isin(['1','2','3']),'c'],
                    vei.loc[vei['tipo'].isin(['1','2','3']),'id_veiculo']))

# ---------- monitores / motoristas ----------
print('profissionais...')
mon = pd.read_csv('pdde/script_05_monitores.csv', usecols=['codigo_cidade','vinculo'], dtype=str)
mon['c'] = mon['codigo_cidade'].map(norm); mon = mon.dropna(subset=['c'])
for c, g in mon.groupby(mon['c'].astype(int)):
    I[c]['tot_mon'] += len(g); I[c]['mon_cv'] += int(g['vinculo'].isin(['1','2']).sum())
mot = pd.read_csv('pdde/script_06_motoristas.csv', usecols=['codigo_cidade','vinculo'], dtype=str)
mot['c'] = mot['codigo_cidade'].map(norm); mot = mot.dropna(subset=['c'])
for c, g in mot.groupby(mot['c'].astype(int)):
    I[c]['tot_mot_info'] += int(g['vinculo'].notna().sum())
    I[c]['mot_cv'] += int(g['vinculo'].isin(['1','2']).sum())

# ---------- alunos cadastrados ----------
print('alunos...')
for ch in pd.read_csv('pdde/script_01_alunos.csv', usecols=['codigo_cidade'], dtype=str, chunksize=1_000_000):
    vc = ch['codigo_cidade'].map(norm).dropna().astype(int).value_counts()
    for c, n in vc.items(): I[c]['al_cad'] += int(n)

# ---------- rota→veículo adequado; rota→aluno; rota→escola ----------
print('vínculos rota...')
rpv = pd.read_csv('pdde/script_16_rota_possui_veiculo.csv', dtype=str)
rpv['c'] = rpv['codigo_cidade'].map(norm); rpv = rpv.dropna(subset=['c'])
rpv['c'] = rpv['c'].astype(int)
rota_adeq = set(zip(rpv['c'], rpv['id_rota'])) & set()  # placeholder
rota_adeq = {(c, r) for c, r, v in zip(rpv['c'], rpv['id_rota'], rpv['id_veiculo'])
             if (c, v) in adeq_veic}

for ch in pd.read_csv('pdde/script_13_rota_atende_aluno.csv', dtype=str, chunksize=1_000_000):
    ch['c'] = ch['codigo_cidade'].map(norm); ch = ch.dropna(subset=['c'])
    ch['c'] = ch['c'].astype(int)
    for c, r, a in zip(ch['c'], ch['id_rota'], ch['id_aluno']):
        if pd.isna(a): continue
        al_transp[c].add(a)
        if (c, r) in rota_adeq: al_adeq[c].add(a)

rpe = pd.read_csv('pdde/script_15_rota_passa_por_escolas.csv', dtype=str)
rpe['c'] = rpe['codigo_cidade'].map(norm); rpe = rpe.dropna(subset=['c'])
for c, e in zip(rpe['c'].astype(int), rpe['id_escola']):
    if pd.notna(e): esc_at[c].add(e)

# ---------- MEDATE: alunos transportados por escola (script_12 ∩ transportados) ----------
print('medate...')
esc_cnt = defaultdict(lambda: defaultdict(int))  # cod -> escola -> n alunos transp
for ch in pd.read_csv('pdde/script_12_escola_tem_aluno.csv', dtype=str, chunksize=1_000_000):
    ch['c'] = ch['codigo_cidade'].map(norm); ch = ch.dropna(subset=['c'])
    ch['c'] = ch['c'].astype(int)
    for c, e, a in zip(ch['c'], ch['id_escola'], ch['id_aluno']):
        if pd.notna(a) and pd.notna(e) and a in al_transp.get(c, ()):
            esc_cnt[c][e] += 1

# ---------- montar indicadores por município ----------
def pct(a, b): return round(a / b * 100, 2) if b else None
IND = {}
for c, d in I.items():
    at = len(al_transp.get(c, ())); ad = len(al_adeq.get(c, ()))
    ea = len(esc_at.get(c, ())); tr = d['tot_rotas']; tv = d['tot_veic']
    cnts = sorted(esc_cnt.get(c, {}).values())
    med = float(np.median(cnts)) if cnts else None
    cap_m = d['cap_sum'] / d['nvv'] if d['nvv'] else None
    IND[c] = dict(
        PRGM=pct(d['georref'], tr), PRDAM=pct(d['dif'], tr),
        PRRM=pct(d['t1'], tr), PRHM=pct(d['t2'], tr), PRMM=pct(d['t3'], tr),
        PVP=pct(d['vp'], tv), PVT=pct(d['vt'], tv),
        MON_CVE=pct(d['mon_cv'], d['tot_mon']), MOT_CVE=pct(d['mot_cv'], d['tot_mot_info']),
        ATE=round(at/ea, 1) if ea else None, MEDATE=med,
        IUC=round(at/(d['nvv']*cap_m), 2) if (d['nvv'] and cap_m and at) else None,
        TEDC=pct(at, d['al_cad']), TETI=pct(ad, at))

# ---------- VALIDAÇÃO: reagrega por UF e compara com RAW_DATA do dashboard ----------
h = open('dashboard.html', encoding='utf-8').read()
RAW = json.loads(re.search(r'const RAW_DATA = (\{.*?\});\n', h, re.S).group(1))
uf_in = defaultdict(lambda: defaultdict(float))
uf_at, uf_ad, uf_ea = defaultdict(set), defaultdict(set), defaultdict(int)
uf_med = defaultdict(list)
for c, d in I.items():
    s = LK[c].lower()
    for k in ['tot_rotas','georref','dif','t1','t2','t3','tot_veic','vp','vt','nvv',
              'cap_sum','tot_mon','mon_cv','tot_mot_info','mot_cv','al_cad']:
        uf_in[s][k] += d[k]
    uf_at[s] |= {(c, a) for a in al_transp.get(c, ())}
    uf_ad[s] |= {(c, a) for a in al_adeq.get(c, ())}
    uf_ea[s] += len(esc_at.get(c, ()))
    uf_med[s].extend(esc_cnt.get(c, {}).values())
print('\n== VALIDAÇÃO estado a estado (calculado vs dashboard) ==')
bad = 0
for s in sorted(uf_in):
    r = RAW.get(s);
    if not r: continue
    checks = [('tot_rotas', uf_in[s]['tot_rotas']), ('georref', uf_in[s]['georref']),
        ('dif', uf_in[s]['dif']), ('t1', uf_in[s]['t1']), ('t2', uf_in[s]['t2']),
        ('t3', uf_in[s]['t3']), ('tot_veic', uf_in[s]['tot_veic']), ('vp', uf_in[s]['vp']),
        ('vt', uf_in[s]['vt']), ('n_veic_validos', uf_in[s]['nvv']),
        ('tot_mon', uf_in[s]['tot_mon']), ('mon_cv', uf_in[s]['mon_cv']),
        ('tot_mot_info', uf_in[s]['tot_mot_info']), ('mot_cv', uf_in[s]['mot_cv']),
        ('al_cad', uf_in[s]['al_cad']), ('al_transp', len(uf_at[s])),
        ('al_adeq', len(uf_ad[s])), ('esc_at', uf_ea[s]),
        ('medate_n', len(uf_med[s])),
        ('medate_val', float(np.median(uf_med[s])) if uf_med[s] else None)]
    for k, v in checks:
        exp = r.get(k)
        if exp is None and (v in (None, 0)): continue
        if exp is None or v is None or abs(float(v) - float(exp)) > 0.51:
            print(f'  DIVERGE {s.upper()} {k}: calc={v} vs dash={exp}'); bad += 1
print('Total de divergências:', bad)

json.dump({str(c): v for c, v in IND.items()}, open('sete_ind.json','w'),
          ensure_ascii=False, separators=(',',':'))
import os; print('sete_ind.json:', os.path.getsize('sete_ind.json')//1024, 'KB ·', len(IND), 'municípios')
