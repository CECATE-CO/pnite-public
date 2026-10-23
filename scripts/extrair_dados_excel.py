"""
Script de Extração e Consolidação de Dados das Planilhas Excel da PNITE
PNITE — Plataforma Nacional de Inteligência em Transporte Escolar

Este script realiza a leitura automatizada de todas as planilhas Excel consolidadas
armazenadas em 'data/Transporte Escolar/' (com o prefixo 'consolidado XX - script_XX_*.xlsx'),
consolida os indicadores estaduais, regionais e nacionais, e exporta os resultados
para:
  1) data/Transporte Escolar/pnite_dados_consolidados.json (lido por scripts/validar_paridade.py)
  2) data/Transporte Escolar/pnite_dados_consolidados.js   (objeto window.PNITE_EXCEL_DATA)

Uso (de qualquer pasta): python scripts/extrair_dados_excel.py
As funções carregar_planilhas, extrair_metricas_por_uf e montar_raw_referencia também são usadas
por scripts/criar_banco_dados_brutos.py (tabelas ref.raw_referencia e ref.detalhes_scripts).
"""

import os
import sys
import glob
import json
import re
import unicodedata
import pandas as pd
import numpy as np
from datetime import datetime

# Raiz do repositório: os caminhos de data/, PNITE.html e old/ não dependem da pasta atual
RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Assegura suporte a utf-8 no console Windows
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')


# Mapeamento de nomes de estado para sigla (UF)
UF_SIGLA_MAP = {
    'acre': 'ac', 'alagoas': 'al', 'amapa': 'ap', 'amazonas': 'am', 'bahia': 'ba',
    'ceara': 'ce', 'distrito federal': 'df', 'espirito santo': 'es', 'goias': 'go',
    'maranhao': 'ma', 'mato grosso': 'mt', 'mato grosso do sul': 'ms', 'minas gerais': 'mg',
    'para': 'pa', 'paraiba': 'pb', 'parana': 'pr', 'pernambuco': 'pe', 'piaui': 'pi',
    'rio de janeiro': 'rj', 'rio grande do norte': 'rn', 'rio grande do sul': 'rs',
    'rondonia': 'ro', 'roraima': 'rr', 'santa catarina': 'sc', 'sao paulo': 'sp',
    'sergipe': 'se', 'tocantins': 'to', 'brasil': 'nacional', 'total': 'nacional',
    'total geral': 'nacional'
}

UF_LABELS = {
    'ac': 'Acre', 'al': 'Alagoas', 'ap': 'Amapá', 'am': 'Amazonas', 'ba': 'Bahia',
    'ce': 'Ceará', 'df': 'Distrito Federal', 'es': 'Espírito Santo', 'go': 'Goiás',
    'ma': 'Maranhão', 'mt': 'Mato Grosso', 'ms': 'Mato Grosso do Sul', 'mg': 'Minas Gerais',
    'pa': 'Pará', 'pb': 'Paraíba', 'pr': 'Paraná', 'pe': 'Pernambuco', 'pi': 'Piauí',
    'rj': 'Rio de Janeiro', 'rn': 'Rio Grande do Norte', 'rs': 'Rio Grande do Sul',
    'ro': 'Rondônia', 'rr': 'Roraima', 'sc': 'Santa Catarina', 'sp': 'São Paulo',
    'se': 'Sergipe', 'to': 'Tocantins', 'nacional': 'Brasil'
}

REGIOES = {
    'norte': ['ac', 'ap', 'am', 'pa', 'ro', 'rr', 'to'],
    'nordeste': ['al', 'ba', 'ce', 'ma', 'pb', 'pe', 'pi', 'rn', 'se'],
    'sudeste': ['es', 'mg', 'rj', 'sp'],
    'sul': ['pr', 'rs', 'sc'],
    'centro-oeste': ['df', 'go', 'mt', 'ms']
}

REGIAO_LABELS = {
    'norte': 'Norte',
    'nordeste': 'Nordeste',
    'sudeste': 'Sudeste',
    'sul': 'Sul',
    'centro-oeste': 'Centro-Oeste'
}

def normalizar_texto(texto):
    """Remove acentuação e converte para minúsculas para correspondência segura."""
    if not isinstance(texto, str):
        return ''
    nfkd = unicodedata.normalize('NFKD', texto)
    sem_acento = u"".join([c for c in nfkd if not unicodedata.combining(c)])
    return sem_acento.strip().lower()

def carregar_planilhas(data_dir='data'):
    """Lê todas as planilhas consolidadas na pasta especificada."""
    padrao = os.path.join(data_dir, 'consolidado *.xlsx')
    arquivos = sorted(glob.glob(padrao))
    if not arquivos:
        arquivos = sorted(glob.glob(os.path.join(data_dir, '*Consolida*.xlsx')))
    
    print(f"Encontrados {len(arquivos)} arquivos Excel para processar em '{data_dir}'.")
    tabelas = {}
    for caminho in arquivos:
        nome_base = os.path.basename(caminho)
        partes = nome_base.split(' - ')
        chave = partes[1].replace('.xlsx', '').strip() if len(partes) > 1 else nome_base.replace('.xlsx', '')
        try:
            df = pd.read_excel(caminho)
            tabelas[chave] = {
                'arquivo': nome_base,
                'df': df
            }
            print(f"  [OK] {nome_base} ({len(df)} registros)")
        except Exception as e:
            print(f"  [ERRO] Falha ao ler {nome_base}: {e}")
            
    return tabelas

def extrair_metricas_por_uf(tabelas):
    """Extrai e calcula as variáveis por UF a partir das tabelas carregadas."""
    dados_uf = {uf: {} for uf in list(UF_LABELS.keys())}
    detalhes_scripts = {uf: {} for uf in list(UF_LABELS.keys())}

    for chave, tab in tabelas.items():
        df = tab['df']
        if 'estado' not in df.columns:
            continue
        
        for _, row in df.iterrows():
            est_norm = normalizar_texto(str(row['estado']))
            uf = UF_SIGLA_MAP.get(est_norm)
            if not uf or uf not in dados_uf:
                continue
            
            detalhe = {}
            for col in df.columns:
                if col != 'estado':
                    val = row[col]
                    if pd.isna(val):
                        detalhe[col] = None
                    elif isinstance(val, (int, float, bool)):
                        detalhe[col] = int(val) if isinstance(val, float) and val.is_integer() else round(val, 2)
                    else:
                        detalhe[col] = str(val)
            detalhes_scripts[uf][chave] = detalhe

    return detalhes_scripts

def processar_alunos(data_dir='data'):
    """
    Processa script_01_alunos_consolidado.csv para calcular:
      1) PAD: Alunos com Deficiência Atendidos pelo Transporte Escolar (def_caminhar, def_ouvir, def_enxergar, def_mental == 'S')
      2) PARI: Percentual de Alunos em Rotas com Impedância (da_porteira, da_mataburro, da_colchete, da_atoleiro, da_ponterustica == 'S')
    Contagem única por aluno (se tiver múltiplas deficiências ou múltiplos obstáculos, conta apenas uma vez).
    Gera estatísticas consolidadas por Cidade, Estado, Região e Brasil.
    """
    csv_path = os.path.join(data_dir, 'script_01_alunos_consolidado.csv')
    if not os.path.exists(csv_path):
        print(f"  [AVISO] Arquivo '{csv_path}' não encontrado para cálculo de alunos.")
        return None
        
    print(f"  [INFO] Processando alunos, PCD (PAD) e impedâncias operacionais (PARI) em '{csv_path}'...")
    cols = ['codigo_cidade', 'uf', 'def_caminhar', 'def_ouvir', 'def_enxergar', 'def_mental',
            'da_porteira', 'da_mataburro', 'da_colchete', 'da_atoleiro', 'da_ponterustica']
    
    total_br = 0
    pcd_br = 0
    pari_br = 0
    porteira_br = 0
    mataburro_br = 0
    colchete_br = 0
    atoleiro_br = 0
    ponte_br = 0

    est_tot = {}
    est_pcd = {}
    est_pari = {}
    
    mun_dados = {}
    
    chunksize = 500000
    for chunk in pd.read_csv(csv_path, usecols=cols, chunksize=chunksize, dtype=str):
        has_def = (chunk['def_caminhar'].str.upper() == 'S') | \
                  (chunk['def_ouvir'].str.upper() == 'S') | \
                  (chunk['def_enxergar'].str.upper() == 'S') | \
                  (chunk['def_mental'].str.upper() == 'S')
        
        p = (chunk['da_porteira'].str.upper() == 'S')
        m = (chunk['da_mataburro'].str.upper() == 'S')
        c = (chunk['da_colchete'].str.upper() == 'S')
        a = (chunk['da_atoleiro'].str.upper() == 'S')
        pr = (chunk['da_ponterustica'].str.upper() == 'S')
        has_pari = p | m | c | a | pr

        total_br += len(chunk)
        pcd_br += int(has_def.sum())
        pari_br += int(has_pari.sum())
        porteira_br += int(p.sum())
        mataburro_br += int(m.sum())
        colchete_br += int(c.sum())
        atoleiro_br += int(a.sum())
        ponte_br += int(pr.sum())
        
        for uf, g in chunk.groupby('uf'):
            s = str(uf).lower().strip()
            est_tot[s] = est_tot.get(s, 0) + len(g)
            est_pcd[s] = est_pcd.get(s, 0) + int(has_def.loc[g.index].sum())
            est_pari[s] = est_pari.get(s, 0) + int(has_pari.loc[g.index].sum())
            
        for cod, g in chunk.groupby('codigo_cidade'):
            cd = str(cod).strip()
            if cd not in mun_dados:
                mun_dados[cd] = {
                    'total': 0, 'pcd': 0, 'pari': 0,
                    'porteira': 0, 'mataburro': 0, 'colchete': 0, 'atoleiro': 0, 'ponte': 0
                }
            md = mun_dados[cd]
            md['total'] += len(g)
            md['pcd'] += int(has_def.loc[g.index].sum())
            md['pari'] += int(has_pari.loc[g.index].sum())
            md['porteira'] += int(p.loc[g.index].sum())
            md['mataburro'] += int(m.loc[g.index].sum())
            md['colchete'] += int(c.loc[g.index].sum())
            md['atoleiro'] += int(a.loc[g.index].sum())
            md['ponte'] += int(pr.loc[g.index].sum())
            
    pad_br = round((pcd_br / total_br) * 100, 2) if total_br > 0 else 0.0
    pari_pct_br = round((pari_br / total_br) * 100, 2) if total_br > 0 else 0.0
    print(f"  [OK] PCD Nacional (PAD): {pcd_br:,} de {total_br:,} alunos ({pad_br}%).")
    print(f"  [OK] Alunos em Impedância (PARI): {pari_br:,} de {total_br:,} alunos ({pari_pct_br}%).")
    print(f"       (Atoleiros: {atoleiro_br:,} | Mata-burros: {mataburro_br:,} | Porteiras: {porteira_br:,} | Pontes: {ponte_br:,} | Colchetes: {colchete_br:,})")

    # Formatar dados municipais
    mun_formatado = {}
    for cd, md in mun_dados.items():
        tot = md['total']
        pcd = md['pcd']
        pari = md['pari']
        mun_formatado[cd] = {
            'total': tot,
            'pcd': pcd,
            'PAD': round((pcd / tot) * 100, 2) if tot > 0 else 0.0,
            'pari': pari,
            'PARI': round((pari / tot) * 100, 2) if tot > 0 else 0.0,
            'porteira': md['porteira'],
            'mataburro': md['mataburro'],
            'colchete': md['colchete'],
            'atoleiro': md['atoleiro'],
            'ponte': md['ponte']
        }
    
    return {
        'total_br': total_br,
        'pcd_br': pcd_br,
        'pad_br': pad_br,
        'pari_br': pari_br,
        'pari_pct_br': pari_pct_br,
        'porteira_br': porteira_br,
        'mataburro_br': mataburro_br,
        'colchete_br': colchete_br,
        'atoleiro_br': atoleiro_br,
        'ponte_br': ponte_br,
        'est_tot': est_tot,
        'est_pcd': est_pcd,
        'est_pari': est_pari,
        'municipios': mun_formatado
    }

def processar_censo_e_cobertura(data_dir='data'):
    """
    Processa o cruzamento entre SETE e Censo Escolar 2025 para calcular o indicador PCSC:
    Percentual de Cobertura entre SETE e Censo Escolar.
    Fontes:
      1) data/script_13_rota_atende_aluno_consolidado.csv -> Alunos atendidos por rotas no SETE
      2) data/Micro_Dados_Censo_Tabela_Matricula_2025_V2.csv (coluna QT_TRANSP_PUBLICO) -> Demanda declarada no Censo Escolar
    Calcula por Município, Estado, Região e Brasil.
    """
    censo_path = os.path.join(data_dir, 'Micro_Dados_Censo_Tabela_Matricula_2025_V2.csv')
    s13_path = os.path.join(data_dir, 'script_13_rota_atende_aluno_consolidado.csv')
    
    if not os.path.exists(censo_path) or not os.path.exists(s13_path):
        print(f"  [AVISO] Arquivos necessários para PCSC não encontrados ({censo_path} ou {s13_path}).")
        return None
        
    print(f"  [INFO] Processando demanda Censo 2025 ('{censo_path}') e atendimento SETE ('{s13_path}')...")
    
    # 1. Demanda Censo Escolar 2025
    censo_cols = ['CO_MUNICIPIO', 'SG_UF', 'QT_TRANSP_PUBLICO']
    df_censo = pd.read_csv(censo_path, usecols=censo_cols, sep=';', encoding='latin1')
    df_censo['uf_clean'] = df_censo['SG_UF'].astype(str).str.lower().str.strip()
    df_censo['cod_mun'] = df_censo['CO_MUNICIPIO'].astype(str).str.strip()
    
    censo_mun = df_censo.groupby('cod_mun')['QT_TRANSP_PUBLICO'].sum().to_dict()
    censo_uf = df_censo.groupby('uf_clean')['QT_TRANSP_PUBLICO'].sum().to_dict()
    censo_br = int(df_censo['QT_TRANSP_PUBLICO'].sum())
    
    # 2. Atendimento SETE (script 13)
    df13 = pd.read_csv(s13_path, usecols=['id_aluno', 'codigo_cidade', 'uf'], dtype=str)
    df13['uf_clean'] = df13['uf'].str.lower().str.strip()
    df13['cod_mun'] = df13['codigo_cidade'].str.strip()
    
    sete_mun = df13.groupby('cod_mun')['id_aluno'].nunique().to_dict()
    sete_uf = df13.groupby('uf_clean')['id_aluno'].nunique().to_dict()
    sete_br = int(df13['id_aluno'].nunique())
    
    pcsc_br = round((sete_br / censo_br) * 100, 2) if censo_br > 0 else 0.0
    print(f"  [OK] Cobertura Nacional (PCSC): {sete_br:,} (SETE) de {censo_br:,} (Censo) = {pcsc_br}%.")
    
    # Formatação municipal
    todos_muns = set(censo_mun.keys()).union(set(sete_mun.keys()))
    mun_formatado = {}
    for cod in todos_muns:
        dem = int(censo_mun.get(cod, 0))
        atend = int(sete_mun.get(cod, 0))
        pcsc_val = round((atend / dem) * 100, 2) if dem > 0 else (100.0 if atend > 0 else 0.0)
        mun_formatado[cod] = {
            'demanda_censo': dem,
            'atendidos_sete': atend,
            'PCSC': pcsc_val
        }
        
    return {
        'censo_br': censo_br,
        'sete_br': sete_br,
        'pcsc_br': pcsc_br,
        'censo_uf': censo_uf,
        'sete_uf': sete_uf,
        'municipios': mun_formatado
    }

def processar_rotas_prgm(data_dir='data'):
    """
    Processa script_03_rotas_consolidado.csv para calcular:
      1) PRGM: Percentual de Rotas Georreferenciadas e Distâncias da Malha (km)
      2) PRIO: Percentual de Rotas com Impedância Operacional (porteiras, mata-burros, colchetes, atoleiros, pontes)
      3) Tempo de Viagem: média e mediana do tempo operacional por rota
    Computa por Cidade, Estado, Região e Brasil.
    """
    csv_path = os.path.join(data_dir, 'script_03_rotas_consolidado.csv')
    if not os.path.exists(csv_path):
        print(f"  [AVISO] Arquivo '{csv_path}' não encontrado para cálculo de rotas.")
        return None

    print(f"  [INFO] Processando rotas, georreferenciamento, impedâncias e tempos em '{csv_path}'...")
    cols = ['codigo_cidade', 'uf', 'km', 'shape', 'da_porteira', 'da_mataburro', 'da_colchete', 'da_atoleiro', 'da_ponterustica', 'tempo', 'tipo']
    
    tot_br = 0
    geo_br = 0
    imped_br = 0
    t1_br = 0
    t2_br = 0
    t3_br = 0
    km_tot_br = 0.0
    km_geo_br = 0.0
    tempos_br = []
    
    uf_rotas = {}
    mun_rotas = {}
    
    chunksize = 50000
    for chunk in pd.read_csv(csv_path, usecols=cols, chunksize=chunksize, dtype=str):
        has_shape = chunk['shape'].notna() & (chunk['shape'].str.strip() != '') & (chunk['shape'].str.upper() != 'NULL')
        km_vals = pd.to_numeric(chunk['km'].str.replace(',', '.'), errors='coerce').fillna(0.0)
        
        p = (chunk['da_porteira'].str.upper() == 'S')
        m = (chunk['da_mataburro'].str.upper() == 'S')
        c = (chunk['da_colchete'].str.upper() == 'S')
        a = (chunk['da_atoleiro'].str.upper() == 'S')
        pr = (chunk['da_ponterustica'].str.upper() == 'S')
        has_imped = p | m | c | a | pr
        
        t_num = pd.to_numeric(chunk['tempo'].str.replace(',', '.'), errors='coerce')
        t_valid = t_num[(t_num >= 1) & (t_num <= 360)]
        tempos_br.extend(t_valid.tolist()[:500])
        
        tipo_clean = chunk['tipo'].fillna('').str.strip()
        is_t1 = (tipo_clean == '1')
        is_t2 = (tipo_clean == '2')
        is_t3 = (tipo_clean == '3')

        tot_br += len(chunk)
        geo_br += int(has_shape.sum())
        imped_br += int(has_imped.sum())
        t1_br += int(is_t1.sum())
        t2_br += int(is_t2.sum())
        t3_br += int(is_t3.sum())
        km_tot_br += float(km_vals.sum())
        km_geo_br += float(km_vals[has_shape].sum())
        
        for uf, g in chunk.groupby('uf'):
            s = str(uf).lower().strip()
            if s not in uf_rotas:
                uf_rotas[s] = {'rotas': 0, 'geo': 0, 'imped': 0, 't1': 0, 't2': 0, 't3': 0, 'km': 0.0, 'km_geo': 0.0, 'tempos': []}
            u = uf_rotas[s]
            u['rotas'] += len(g)
            u['geo'] += int(has_shape.loc[g.index].sum())
            u['imped'] += int(has_imped.loc[g.index].sum())
            u['t1'] += int(is_t1.loc[g.index].sum())
            u['t2'] += int(is_t2.loc[g.index].sum())
            u['t3'] += int(is_t3.loc[g.index].sum())
            u['km'] += float(km_vals.loc[g.index].sum())
            u['km_geo'] += float(km_vals.loc[g.index[has_shape.loc[g.index]]].sum())
            t_uf_valid = t_num.loc[g.index][(t_num.loc[g.index] >= 1) & (t_num.loc[g.index] <= 360)]
            if len(t_uf_valid) > 0:
                u['tempos'].extend(t_uf_valid.tolist()[:300])
            
        for cod, g in chunk.groupby('codigo_cidade'):
            cd = str(cod).strip()
            if cd not in mun_rotas:
                mun_rotas[cd] = {'rotas': 0, 'geo': 0, 'imped': 0, 't1': 0, 't2': 0, 't3': 0, 'porteira': 0, 'mataburro': 0, 'colchete': 0, 'atoleiro': 0, 'ponte': 0, 'km': 0.0, 'km_geo': 0.0, 'tempos': []}
            mr = mun_rotas[cd]
            mr['rotas'] += len(g)
            mr['geo'] += int(has_shape.loc[g.index].sum())
            mr['imped'] += int(has_imped.loc[g.index].sum())
            mr['t1'] += int(is_t1.loc[g.index].sum())
            mr['t2'] += int(is_t2.loc[g.index].sum())
            mr['t3'] += int(is_t3.loc[g.index].sum())
            mr['porteira'] += int(p.loc[g.index].sum())
            mr['mataburro'] += int(m.loc[g.index].sum())
            mr['colchete'] += int(c.loc[g.index].sum())
            mr['atoleiro'] += int(a.loc[g.index].sum())
            mr['ponte'] += int(pr.loc[g.index].sum())
            mr['km'] += float(km_vals.loc[g.index].sum())
            mr['km_geo'] += float(km_vals.loc[g.index[has_shape.loc[g.index]]].sum())
            t_mun_valid = t_num.loc[g.index][(t_num.loc[g.index] >= 1) & (t_num.loc[g.index] <= 360)]
            if len(t_mun_valid) > 0:
                mr['tempos'].extend(t_mun_valid.tolist())

    prgm_br = round((geo_br / tot_br) * 100, 2) if tot_br > 0 else 0.0
    prio_br = round((imped_br / tot_br) * 100, 2) if tot_br > 0 else 0.0
    med_tempo_br = round(float(np.median(tempos_br)), 1) if tempos_br else 60.0
    
    print(f"  [OK] Rotas Nacional: {tot_br:,} total | PRGM: {geo_br:,} ({prgm_br}%) | PRIO: {imped_br:,} ({prio_br}%) | Extensão: {km_tot_br:,.1f} km | Tempo mediano: {med_tempo_br} min.")
    
    # Formatar dados municipais
    mun_formatado = {}
    for c, d in mun_rotas.items():
        r = d['rotas']
        g = d['geo']
        imp = d['imped']
        k = round(d['km'], 1)
        kg = round(d['km_geo'], 1)
        prgm = round((g / r) * 100, 2) if r > 0 else 0.0
        prio = round((imp / r) * 100, 2) if r > 0 else 0.0
        km_med = round(k / r, 1) if r > 0 else 0.0
        t_arr = d['tempos']
        t_med = round(float(np.median(t_arr)), 1) if t_arr else None
        t_avg = round(float(np.mean(t_arr)), 1) if t_arr else None
        
        mun_formatado[c] = {
            'rotas': r,
            'geo': g,
            'PRGM': prgm,
            'imped': imp,
            'PRIO': prio,
            'porteira': d['porteira'],
            'mataburro': d['mataburro'],
            'colchete': d['colchete'],
            'atoleiro': d['atoleiro'],
            'ponte': d['ponte'],
            'km_total': k,
            'km_geo': kg,
            'km_medio': km_med,
            'tempo_mediano': t_med,
            'tempo_medio': t_avg,
            'has_geo': g > 0,
            'has_imped': imp > 0
        }
        
    return {
        'tot_br': tot_br,
        'geo_br': geo_br,
        'prgm_br': prgm_br,
        'imped_br': imped_br,
        'prio_br': prio_br,
        't1_br': t1_br,
        't2_br': t2_br,
        't3_br': t3_br,
        'km_tot_br': round(km_tot_br, 1),
        'km_geo_br': round(km_geo_br, 1),
        'tempo_med_br': med_tempo_br,
        'uf_rotas': uf_rotas,
        'municipios_rotas': mun_formatado
    }

def processar_veiculos_origem(data_dir='data'):
    """
    Processa script_04_veiculos_consolidado.csv para calcular:
      1) PVP: Percentual de Veículos da Frota Própria (origem == 1)
      2) PVT: Percentual de Veículos da Frota Terceirizada (origem == 2)
      3) Capacidade média e veículos válidos para o IUC
    Computa por Cidade, Estado, Região e Brasil.
    """
    csv_path = os.path.join(data_dir, 'script_04_veiculos_consolidado.csv')
    if not os.path.exists(csv_path):
        print(f"  [AVISO] Arquivo '{csv_path}' não encontrado para cálculo de veículos.")
        return None

    print(f"  [INFO] Processando veículos, frota própria/terceirizada e capacidade em '{csv_path}'...")
    cols = ['codigo_cidade', 'uf', 'origem', 'capacidade']
    tot_br = 0
    vp_br = 0
    vt_br = 0
    n_validos_br = 0
    cap_sum_br = 0.0
    uf_veic = {}
    mun_veic = {}

    chunksize = 50000
    for chunk in pd.read_csv(csv_path, usecols=cols, chunksize=chunksize, dtype=str):
        origem_clean = chunk['origem'].fillna('').str.strip()
        is_p = (origem_clean == '1')
        is_t = (origem_clean == '2')

        cap_num = pd.to_numeric(chunk['capacidade'], errors='coerce')
        is_cap_valida = (cap_num > 0) & (cap_num <= 150)
        cap_valid_vals = cap_num[is_cap_valida]

        tot_br += len(chunk)
        vp_br += int(is_p.sum())
        vt_br += int(is_t.sum())
        n_validos_br += int(is_cap_valida.sum())
        cap_sum_br += float(cap_valid_vals.sum())

        for uf, g in chunk.groupby('uf'):
            s = str(uf).lower().strip()
            if s not in uf_veic:
                uf_veic[s] = {'veiculos': 0, 'vp': 0, 'vt': 0, 'n_validos': 0, 'cap_sum': 0.0}
            g_cap = cap_num.loc[g.index]
            g_cap_val = (g_cap > 0) & (g_cap <= 150)
            uf_veic[s]['veiculos'] += len(g)
            uf_veic[s]['vp'] += int(is_p.loc[g.index].sum())
            uf_veic[s]['vt'] += int(is_t.loc[g.index].sum())
            uf_veic[s]['n_validos'] += int(g_cap_val.sum())
            uf_veic[s]['cap_sum'] += float(g_cap[g_cap_val].sum())

        for cod, g in chunk.groupby('codigo_cidade'):
            cd = str(cod).strip()
            if cd not in mun_veic:
                mun_veic[cd] = {'veiculos': 0, 'vp': 0, 'vt': 0, 'n_validos': 0, 'cap_sum': 0.0}
            g_cap = cap_num.loc[g.index]
            g_cap_val = (g_cap > 0) & (g_cap <= 150)
            mun_veic[cd]['veiculos'] += len(g)
            mun_veic[cd]['vp'] += int(is_p.loc[g.index].sum())
            mun_veic[cd]['vt'] += int(is_t.loc[g.index].sum())
            mun_veic[cd]['n_validos'] += int(g_cap_val.sum())
            mun_veic[cd]['cap_sum'] += float(g_cap[g_cap_val].sum())

    pvp_br = round((vp_br / tot_br) * 100, 2) if tot_br > 0 else 0.0
    pvt_br = round((vt_br / tot_br) * 100, 2) if tot_br > 0 else 0.0
    cap_media_br = round(cap_sum_br / n_validos_br, 2) if n_validos_br > 0 else 0.0
    print(f"  [OK] Veículos Nacional: {tot_br:,} total | Própria: {vp_br:,} ({pvp_br}%) | Terceirizada: {vt_br:,} ({pvt_br}%) | Cap. Válida: {n_validos_br:,} (Média {cap_media_br} lug/veíc).")

    for s, d in uf_veic.items():
        d['cap_media'] = round(d['cap_sum'] / d['n_validos'], 2) if d['n_validos'] > 0 else 0.0

    mun_formatado = {}
    for c, d in mun_veic.items():
        v = d['veiculos']
        vp = d['vp']
        vt = d['vt']
        nv = d['n_validos']
        cm = round(d['cap_sum'] / nv, 2) if nv > 0 else 0.0
        mun_formatado[c] = {
            'veiculos': v,
            'vp': vp,
            'vt': vt,
            'PVP': round((vp / v) * 100, 2) if v > 0 else 0.0,
            'PVT': round((vt / v) * 100, 2) if v > 0 else 0.0,
            'n_validos': nv,
            'cap_sum': round(d['cap_sum'], 1),
            'cap_media': cm
        }

    return {
        'tot_br': tot_br,
        'vp_br': vp_br,
        'vt_br': vt_br,
        'pvp_br': pvp_br,
        'pvt_br': pvt_br,
        'n_validos_br': n_validos_br,
        'cap_sum_br': cap_sum_br,
        'cap_media_br': cap_media_br,
        'uf_veic': uf_veic,
        'municipios_veic': mun_formatado
    }

def processar_profissionais(data_dir='data'):
    """
    Processa script_06_motoristas_consolidado.csv e script_05_monitores_consolidado.csv
    para calcular os indicadores PMVE e PMNVE (Revisados 2026):
      PMVE  = [1 − (Motoristas sem vínculo ÷ Total de motoristas)] × 100
      PMNVE = [1 − (Monitores sem vínculo ÷ Total de monitores)] × 100
      Onde vínculo == 4 representa a opção "Outro" (sem vínculo formal).
      Vínculos 1 (Efetivo), 2 (Comissionado) e 3 (Terceirizado) representam vínculo formal.
    """
    mot_path = os.path.join(data_dir, 'script_06_motoristas_consolidado.csv')
    mon_path = os.path.join(data_dir, 'script_05_monitores_consolidado.csv')

    res_mot = {'tot_br': 0, 'outro_br': 0, 'cv_br': 0, 'uf': {}, 'mun': {}}
    if os.path.exists(mot_path):
        print(f"  [INFO] Processando motoristas e vínculos em '{mot_path}'...")
        chunksize = 50000
        for chunk in pd.read_csv(mot_path, usecols=['codigo_cidade', 'uf', 'vinculo'], chunksize=chunksize, dtype=str):
            v_clean = chunk['vinculo'].astype(str).str.replace(r'\.0$', '', regex=True).str.strip()
            is_valid = v_clean.isin(['1', '2', '3', '4'])
            is_outro = (v_clean == '4')
            is_cv = v_clean.isin(['1', '2', '3'])

            res_mot['tot_br'] += int(is_valid.sum())
            res_mot['outro_br'] += int(is_outro.sum())
            res_mot['cv_br'] += int(is_cv.sum())

            for uf, g in chunk.groupby('uf'):
                s = str(uf).lower().strip()
                if s not in res_mot['uf']:
                    res_mot['uf'][s] = {'tot': 0, 'outro': 0, 'cv': 0}
                idx = g.index
                res_mot['uf'][s]['tot'] += int(is_valid.loc[idx].sum())
                res_mot['uf'][s]['outro'] += int(is_outro.loc[idx].sum())
                res_mot['uf'][s]['cv'] += int(is_cv.loc[idx].sum())

            for cod, g in chunk.groupby('codigo_cidade'):
                cd = str(cod).strip()
                if cd not in res_mot['mun']:
                    res_mot['mun'][cd] = {'tot': 0, 'outro': 0, 'cv': 0}
                idx = g.index
                res_mot['mun'][cd]['tot'] += int(is_valid.loc[idx].sum())
                res_mot['mun'][cd]['outro'] += int(is_outro.loc[idx].sum())
                res_mot['mun'][cd]['cv'] += int(is_cv.loc[idx].sum())

    res_mon = {'tot_br': 0, 'outro_br': 0, 'cv_br': 0, 'uf': {}, 'mun': {}}
    if os.path.exists(mon_path):
        print(f"  [INFO] Processando monitores e vínculos em '{mon_path}'...")
        chunksize = 50000
        for chunk in pd.read_csv(mon_path, usecols=['codigo_cidade', 'uf', 'vinculo'], chunksize=chunksize, dtype=str):
            v_clean = chunk['vinculo'].astype(str).str.replace(r'\.0$', '', regex=True).str.strip()
            is_valid = v_clean.isin(['1', '2', '3', '4'])
            is_outro = (v_clean == '4')
            is_cv = v_clean.isin(['1', '2', '3'])

            res_mon['tot_br'] += int(is_valid.sum())
            res_mon['outro_br'] += int(is_outro.sum())
            res_mon['cv_br'] += int(is_cv.sum())

            for uf, g in chunk.groupby('uf'):
                s = str(uf).lower().strip()
                if s not in res_mon['uf']:
                    res_mon['uf'][s] = {'tot': 0, 'outro': 0, 'cv': 0}
                idx = g.index
                res_mon['uf'][s]['tot'] += int(is_valid.loc[idx].sum())
                res_mon['uf'][s]['outro'] += int(is_outro.loc[idx].sum())
                res_mon['uf'][s]['cv'] += int(is_cv.loc[idx].sum())

            for cod, g in chunk.groupby('codigo_cidade'):
                cd = str(cod).strip()
                if cd not in res_mon['mun']:
                    res_mon['mun'][cd] = {'tot': 0, 'outro': 0, 'cv': 0}
                idx = g.index
                res_mon['mun'][cd]['tot'] += int(is_valid.loc[idx].sum())
                res_mon['mun'][cd]['outro'] += int(is_outro.loc[idx].sum())
                res_mon['mun'][cd]['cv'] += int(is_cv.loc[idx].sum())

    pmve_br = round((1 - (res_mot['outro_br'] / res_mot['tot_br'])) * 100, 2) if res_mot['tot_br'] > 0 else 0.0
    pmnve_br = round((1 - (res_mon['outro_br'] / res_mon['tot_br'])) * 100, 2) if res_mon['tot_br'] > 0 else 0.0
    print(f"  [OK] PMVE Nacional (Motoristas c/ vínculo): {res_mot['cv_br']:,} de {res_mot['tot_br']:,} ({pmve_br}% | sem vínculo: {res_mot['outro_br']:,}).")
    print(f"  [OK] PMNVE Nacional (Monitores c/ vínculo): {res_mon['cv_br']:,} de {res_mon['tot_br']:,} ({pmnve_br}% | sem vínculo: {res_mon['outro_br']:,}).")

    return {
        'motoristas': res_mot,
        'monitores': res_mon,
        'pmve_br': pmve_br,
        'pmnve_br': pmnve_br
    }

def montar_raw_referencia(detalhes_por_uf):
    """
    Monta o RAW_DATA de referência por escopo (nacional, regiões e UFs): valores legados
    que ficavam embutidos no HTML (_FALLBACK_RAW_DATA, até a v.3.1.7) sobrepostos pelos totais das planilhas
    'consolidado *.xlsx'. Os campos calculados a partir dos CSVs brutos são aplicados depois.
    Também é usado por scripts/criar_banco_dados_brutos.py (tabela ref.raw_referencia).
    """
    # Obter dados de base de referência (para indicadores metodológicos de Censo, etc.)
    ref_raw = {}
    ref_data = {}
    
    # Desde a v.3.1.8 o PNITE.html não traz mais esses valores: usa a versão mais recente
    # (raiz ou arquivada em old/) que ainda contém _FALLBACK_RAW_DATA
    raiz_glob = glob.escape(RAIZ)
    arquivos_html = (glob.glob(os.path.join(raiz_glob, 'PNITE.html'))
                     + sorted(glob.glob(os.path.join(raiz_glob, 'old', 'PNITE [[]V.*[]].html')), reverse=True))
    html_alvo, conteudo = None, ''
    for caminho in arquivos_html:
        with open(caminho, 'r', encoding='utf-8', errors='replace') as f:
            texto = f.read()
        if 'const _FALLBACK_RAW_DATA' in texto:
            html_alvo, conteudo = caminho, texto
            break
    if html_alvo:
        try:
            m_raw = re.search(r'const (?:_FALLBACK_RAW_DATA|RAW_DATA)\s*=\s*(\{.*?\});\n', conteudo)
            if m_raw:
                ref_raw = json.loads(m_raw.group(1))
            m_data = re.search(r'const (?:_FALLBACK_DATA|DATA)\s*=\s*(\{.*?\});\n', conteudo)
            if m_data:
                ref_data = json.loads(m_data.group(1))
            print(f"Base de inteligência de referência carregada de '{html_alvo}'.")
        except Exception as e:
            print(f"Aviso ao carregar referência do HTML: {e}")

    raw_data_unificada = {}
    todos_nos = list(UF_LABELS.keys()) + list(REGIOES.keys())
    for no in todos_nos:
        raw_data_unificada[no] = {}
        if no in ref_raw:
            raw_data_unificada[no].update(ref_raw[no])
            
    # Aplica os dados diretos dos Excels para as UFs e Nacional
    for uf, scripts in detalhes_por_uf.items():
        node = raw_data_unificada.setdefault(uf, {})
        
        if 'script_01_alunos' in scripts:
            s1 = scripts['script_01_alunos']
            if s1.get('total_alunos') is not None:
                node['al_cad'] = s1['total_alunos']
        
        if 'script_04_veiculos' in scripts:
            s4 = scripts['script_04_veiculos']
            if s4.get('total_veiculos') is not None:
                node['tot_veic'] = s4['total_veiculos']
            if s4.get('proprio') is not None:
                node['vp'] = s4['proprio']
            if s4.get('terceirizado') is not None:
                node['vt'] = s4['terceirizado']
            if s4.get('caminho_da_escola_total') is not None:
                node['ce_veic'] = s4['caminho_da_escola_total']

        if 'script_05_monitores' in scripts:
            s5 = scripts['script_05_monitores']
            if s5.get('total_monitores') is not None:
                node['tot_mon'] = s5['total_monitores']
            efetivo = s5.get('servidor_efetivo') or 0
            comiss = s5.get('servidor_comissionado') or 0
            if s5.get('servidor_efetivo') is not None or s5.get('servidor_comissionado') is not None:
                node['mon_cv'] = efetivo + comiss

        if 'script_06_motoristas' in scripts:
            s6 = scripts['script_06_motoristas']
            if s6.get('total_motoristas') is not None:
                node['tot_mot_info'] = s6['total_motoristas']
            efetivo = s6.get('servidor_efetivo') or 0
            comiss = s6.get('servidor_comissionado') or 0
            if s6.get('servidor_efetivo') is not None or s6.get('servidor_comissionado') is not None:
                node['mot_cv'] = efetivo + comiss

        if 'script_13_rota_atende_aluno' in scripts:
            s13 = scripts['script_13_rota_atende_aluno']
            if s13.get('total_alunos_distintos') is not None:
                node['al_transp'] = s13['total_alunos_distintos']

        if 'script_15_rota_passa_por_escolas' in scripts:
            s15 = scripts['script_15_rota_passa_por_escolas']
            if s15.get('total_escolas_distintas') is not None:
                node['esc_at'] = s15['total_escolas_distintas']

    return raw_data_unificada

def extrair_e_consolidar_tudo(data_dir=None, html_ref=None):
    """
    Executa a extração completa dos Excels e compõe a base RAW_DATA e DATA.
    """
    if data_dir is None:
        transp_dir = os.path.join(RAIZ, 'data', 'Transporte Escolar')
        data_dir = transp_dir if os.path.isdir(transp_dir) else os.path.join(RAIZ, 'data')
    tabelas = carregar_planilhas(data_dir)
    detalhes_por_uf = extrair_metricas_por_uf(tabelas)
    dados_alunos = processar_alunos(data_dir)
    dados_rotas = processar_rotas_prgm(data_dir)
    dados_veiculos = processar_veiculos_origem(data_dir)
    dados_profissionais = processar_profissionais(data_dir)
    dados_cobertura = processar_censo_e_cobertura(data_dir)

    raw_data_unificada = montar_raw_referencia(detalhes_por_uf)

    # Injetar dados calculados de rotas (PRGM, PRIO/dif, km, tempos)
    if dados_rotas:
        raw_data_unificada['nacional']['tot_rotas'] = dados_rotas['tot_br']
        raw_data_unificada['nacional']['georref'] = dados_rotas['geo_br']
        raw_data_unificada['nacional']['dif'] = dados_rotas['imped_br']
        raw_data_unificada['nacional']['t1'] = dados_rotas.get('t1_br', 0)
        raw_data_unificada['nacional']['t2'] = dados_rotas.get('t2_br', 0)
        raw_data_unificada['nacional']['t3'] = dados_rotas.get('t3_br', 0)
        raw_data_unificada['nacional']['km_total'] = dados_rotas['km_tot_br']
        raw_data_unificada['nacional']['tempo_mediano'] = dados_rotas['tempo_med_br']
        
        for s, d_rot in dados_rotas['uf_rotas'].items():
            if s in raw_data_unificada:
                raw_data_unificada[s]['tot_rotas'] = d_rot['rotas']
                raw_data_unificada[s]['georref'] = d_rot['geo']
                raw_data_unificada[s]['dif'] = d_rot['imped']
                raw_data_unificada[s]['t1'] = d_rot.get('t1', 0)
                raw_data_unificada[s]['t2'] = d_rot.get('t2', 0)
                raw_data_unificada[s]['t3'] = d_rot.get('t3', 0)
                raw_data_unificada[s]['km_total'] = round(d_rot['km'], 1)
                
        for reg, ufs in REGIOES.items():
            reg_rot = sum(dados_rotas['uf_rotas'].get(u, {}).get('rotas', 0) for u in ufs)
            reg_geo = sum(dados_rotas['uf_rotas'].get(u, {}).get('geo', 0) for u in ufs)
            reg_imp = sum(dados_rotas['uf_rotas'].get(u, {}).get('imped', 0) for u in ufs)
            reg_km = sum(dados_rotas['uf_rotas'].get(u, {}).get('km', 0.0) for u in ufs)
            raw_data_unificada[reg]['tot_rotas'] = reg_rot
            raw_data_unificada[reg]['georref'] = reg_geo
            raw_data_unificada[reg]['dif'] = reg_imp
            raw_data_unificada[reg]['t1'] = sum(dados_rotas['uf_rotas'].get(u, {}).get('t1', 0) for u in ufs)
            raw_data_unificada[reg]['t2'] = sum(dados_rotas['uf_rotas'].get(u, {}).get('t2', 0) for u in ufs)
            raw_data_unificada[reg]['t3'] = sum(dados_rotas['uf_rotas'].get(u, {}).get('t3', 0) for u in ufs)
            raw_data_unificada[reg]['km_total'] = round(reg_km, 1)


    # Injetar dados de veículos (tot_veic, vp, vt, n_veic_validos, cap_media, cap_sum)
    if dados_veiculos:
        raw_data_unificada['nacional']['tot_veic'] = dados_veiculos['tot_br']
        raw_data_unificada['nacional']['vp'] = dados_veiculos['vp_br']
        raw_data_unificada['nacional']['vt'] = dados_veiculos['vt_br']
        raw_data_unificada['nacional']['n_veic_validos'] = dados_veiculos['n_validos_br']
        raw_data_unificada['nacional']['cap_sum'] = dados_veiculos['cap_sum_br']
        raw_data_unificada['nacional']['cap_media'] = dados_veiculos['cap_media_br']

        for s, d_v in dados_veiculos['uf_veic'].items():
            if s in raw_data_unificada:
                raw_data_unificada[s]['tot_veic'] = d_v['veiculos']
                raw_data_unificada[s]['vp'] = d_v['vp']
                raw_data_unificada[s]['vt'] = d_v['vt']
                raw_data_unificada[s]['n_veic_validos'] = d_v['n_validos']
                raw_data_unificada[s]['cap_sum'] = d_v['cap_sum']
                raw_data_unificada[s]['cap_media'] = d_v['cap_media']

        for reg, ufs in REGIOES.items():
            raw_data_unificada[reg]['tot_veic'] = sum(dados_veiculos['uf_veic'].get(u, {}).get('veiculos', 0) for u in ufs)
            raw_data_unificada[reg]['vp'] = sum(dados_veiculos['uf_veic'].get(u, {}).get('vp', 0) for u in ufs)
            raw_data_unificada[reg]['vt'] = sum(dados_veiculos['uf_veic'].get(u, {}).get('vt', 0) for u in ufs)
            reg_nv = sum(dados_veiculos['uf_veic'].get(u, {}).get('n_validos', 0) for u in ufs)
            reg_cs = sum(dados_veiculos['uf_veic'].get(u, {}).get('cap_sum', 0.0) for u in ufs)
            raw_data_unificada[reg]['n_veic_validos'] = reg_nv
            raw_data_unificada[reg]['cap_sum'] = reg_cs
            raw_data_unificada[reg]['cap_media'] = round(reg_cs / reg_nv, 2) if reg_nv > 0 else 0.0

    # Injetar dados de PCD (PAD) e Alunos em Impedâncias (PARI)
    if dados_alunos:
        raw_data_unificada['nacional']['al_pcd'] = dados_alunos['pcd_br']
        raw_data_unificada['nacional']['al_dif'] = dados_alunos['pari_br']
        raw_data_unificada['nacional']['al_cad'] = dados_alunos['total_br']
        for s, pcd_val in dados_alunos['est_pcd'].items():
            if s in raw_data_unificada:
                raw_data_unificada[s]['al_pcd'] = pcd_val
                raw_data_unificada[s]['al_dif'] = dados_alunos['est_pari'].get(s, 0)
                raw_data_unificada[s]['al_cad'] = dados_alunos['est_tot'].get(s, raw_data_unificada[s].get('al_cad'))
        for reg, ufs in REGIOES.items():
            reg_pcd = sum(dados_alunos['est_pcd'].get(u, 0) for u in ufs)
            reg_pari = sum(dados_alunos['est_pari'].get(u, 0) for u in ufs)
            reg_cad = sum(dados_alunos['est_tot'].get(u, 0) for u in ufs)
            raw_data_unificada[reg]['al_pcd'] = reg_pcd
            raw_data_unificada[reg]['al_dif'] = reg_pari
            raw_data_unificada[reg]['al_cad'] = reg_cad

    # Injetar dados de Cobertura Censo 2025 x SETE (PCSC) e Alunos Transportados (script 13)
    if dados_cobertura:
        raw_data_unificada['nacional']['al_transp_sete'] = dados_cobertura['sete_br']
        raw_data_unificada['nacional']['demanda_censo'] = dados_cobertura['censo_br']
        raw_data_unificada['nacional']['al_transp'] = dados_cobertura['sete_br']
        for s in UF_LABELS.keys():
            if s != 'nacional' and s in raw_data_unificada:
                raw_data_unificada[s]['al_transp_sete'] = dados_cobertura['sete_uf'].get(s, 0)
                raw_data_unificada[s]['demanda_censo'] = dados_cobertura['censo_uf'].get(s, 0)
                raw_data_unificada[s]['al_transp'] = dados_cobertura['sete_uf'].get(s, 0)
        for reg, ufs in REGIOES.items():
            reg_sete = sum(dados_cobertura['sete_uf'].get(u, 0) for u in ufs)
            reg_censo = sum(dados_cobertura['censo_uf'].get(u, 0) for u in ufs)
            raw_data_unificada[reg]['al_transp_sete'] = reg_sete
            raw_data_unificada[reg]['demanda_censo'] = reg_censo
            raw_data_unificada[reg]['al_transp'] = reg_sete

    # Injetar dados de Profissionais e Vínculos (PMVE e PMNVE Revisados)
    if dados_profissionais:
        dmot = dados_profissionais['motoristas']
        dmon = dados_profissionais['monitores']

        raw_data_unificada['nacional']['tot_mot_info'] = dmot['tot_br']
        raw_data_unificada['nacional']['mot_sem_vinculo'] = dmot['outro_br']
        raw_data_unificada['nacional']['mot_cv'] = dmot['cv_br']
        raw_data_unificada['nacional']['tot_mon'] = dmon['tot_br']
        raw_data_unificada['nacional']['mon_sem_vinculo'] = dmon['outro_br']
        raw_data_unificada['nacional']['mon_cv'] = dmon['cv_br']

        for s in UF_LABELS.keys():
            if s != 'nacional' and s in raw_data_unificada:
                raw_data_unificada[s]['tot_mot_info'] = dmot['uf'].get(s, {}).get('tot', 0)
                raw_data_unificada[s]['mot_sem_vinculo'] = dmot['uf'].get(s, {}).get('outro', 0)
                raw_data_unificada[s]['mot_cv'] = dmot['uf'].get(s, {}).get('cv', 0)
                raw_data_unificada[s]['tot_mon'] = dmon['uf'].get(s, {}).get('tot', 0)
                raw_data_unificada[s]['mon_sem_vinculo'] = dmon['uf'].get(s, {}).get('outro', 0)
                raw_data_unificada[s]['mon_cv'] = dmon['uf'].get(s, {}).get('cv', 0)

        for reg, ufs in REGIOES.items():
            raw_data_unificada[reg]['tot_mot_info'] = sum(dmot['uf'].get(u, {}).get('tot', 0) for u in ufs)
            raw_data_unificada[reg]['mot_sem_vinculo'] = sum(dmot['uf'].get(u, {}).get('outro', 0) for u in ufs)
            raw_data_unificada[reg]['mot_cv'] = sum(dmot['uf'].get(u, {}).get('cv', 0) for u in ufs)
            raw_data_unificada[reg]['tot_mon'] = sum(dmon['uf'].get(u, {}).get('tot', 0) for u in ufs)
            raw_data_unificada[reg]['mon_sem_vinculo'] = sum(dmon['uf'].get(u, {}).get('outro', 0) for u in ufs)
            raw_data_unificada[reg]['mon_cv'] = sum(dmon['uf'].get(u, {}).get('cv', 0) for u in ufs)

    # Recalcular DATA
    def calcular_indicadores(r, label):
        def pct(a, b):
            return round((a / b) * 100, 2) if b and b > 0 and a is not None else None
        
        tr = r.get('tot_rotas')
        tv = r.get('tot_veic')
        nvv = r.get('n_veic_validos')
        cap_m = r.get('cap_media')
        at = r.get('al_transp')
        ea = r.get('esc_at')
        tm = r.get('tot_mon')
        tmi = r.get('tot_mot_info')
        tva_val = r.get('tva')
        dif_val = r.get('dif')
        al_cad_val = r.get('al_cad')
        
        iuc = None
        if at and nvv and cap_m and (nvv * cap_m) > 0:
            iuc = round(at / (nvv * cap_m), 2)
            
        ate = round(at / ea, 2) if (at and ea and ea > 0) else None
        prio_val = pct(dif_val, tr)

        mot_sem = r.get('mot_sem_vinculo', 0)
        pmve_val = round((1 - (mot_sem / tmi)) * 100, 2) if tmi and tmi > 0 else pct(r.get('mot_cv'), tmi)

        mon_sem = r.get('mon_sem_vinculo', 0)
        pmnve_val = round((1 - (mon_sem / tm)) * 100, 2) if tm and tm > 0 else pct(r.get('mon_cv'), tm)

        return {
            'label': label,
            'PRGM': pct(r.get('georref'), tr),
            'PRDAM': prio_val,
            'PRIO': prio_val,
            'PRRM': pct(r.get('t1'), tr),
            'PRHM': pct(r.get('t2'), tr),
            'PRMM': pct(r.get('t3'), tr),
            'PVP': pct(r.get('vp'), tv),
            'PVT': pct(r.get('vt'), tv),
            'PVPCE': pct(r.get('ce_veic'), tv),
            'PECS': pct(r.get('sete_esc'), r.get('cs_esc_transp')),
            'IUC': iuc,
            'PMVE': pmve_val,
            'PMNVE': pmnve_val,
            'MON_CVE': pmnve_val,
            'MOT_CVE': pmve_val,
            'PRPM': None,
            'ATE': ate,
            'TETI': None,
            'IPE': None,
            'TEDC': pct(at, al_cad_val),
            'PATM': pct(r.get('cs_tmun'), r.get('cs_transp')),
            'PATE': pct(r.get('cs_test'), r.get('cs_transp')),
            'IPTE': None,
            'MEDATE': r.get('medate_val'),
            'ICA': None,
            'IMFP': r.get('imfp'),
            'IMFT': r.get('imft'),
            'MIFCE': r.get('mifce'),
            'PAFI': None,
            'PAD': pct(r.get('al_pcd'), al_cad_val),
            'PARI': pct(r.get('al_dif'), al_cad_val or at),
            'PCSC': pct(r.get('al_transp_sete'), r.get('demanda_censo')),
            'PAIH': None,
            'PRPNP': None,
            'DMC': None,
            'PVCED': None,
            'TVA': tva_val
        }

    data_calculada = {
        'nacional': calcular_indicadores(raw_data_unificada.get('nacional', {}), 'Brasil'),
        'regiao': {},
        'estado': {}
    }

    for reg, lbl in REGIOES.items():
        data_calculada['regiao'][reg] = calcular_indicadores(raw_data_unificada.get(reg, {}), REGIAO_LABELS[reg])

    for uf, lbl in UF_LABELS.items():
        if uf != 'nacional':
            data_calculada['estado'][uf] = calcular_indicadores(raw_data_unificada.get(uf, {}), lbl)

    # Monta a estrutura final do pacote consolidado
    pacote_consolidado = {
        'metadados': {
            'data_extracao': datetime.now().strftime('%d/%m/%Y %H:%M:%S'),
            'origem': 'Planilhas Excel e CSVs oficiais da pasta data/',
            'total_planilhas_lidas': len(tabelas),
            'arquivos_processados': [t['arquivo'] for t in tabelas.values()]
        },
        'RAW_DATA': raw_data_unificada,
        'DATA': data_calculada,
        'detalhes_scripts': detalhes_por_uf,
        'municipios_rotas': dados_rotas['municipios_rotas'] if dados_rotas else {},
        'municipios_alunos': dados_alunos['municipios'] if dados_alunos else {},
        'municipios_cobertura': dados_cobertura['municipios'] if dados_cobertura else {},
        'municipios_motoristas': dados_profissionais['motoristas']['mun'] if dados_profissionais else {},
        'municipios_monitores': dados_profissionais['monitores']['mun'] if dados_profissionais else {},
        'municipios_pcd': {c: {'pcd': d['pcd'], 'total': d['total'], 'PAD': d['PAD']} for c, d in dados_alunos['municipios'].items()} if dados_alunos else {}
    }

    json_path = os.path.join(data_dir, 'pnite_dados_consolidados.json')
    with open(json_path, 'w', encoding='utf-8') as f:
        json.dump(pacote_consolidado, f, ensure_ascii=False, indent=2)
    print(f"  [OK] Arquivo JSON exportado com sucesso: '{json_path}' ({os.path.getsize(json_path)//1024} KB)")

    js_path = os.path.join(data_dir, 'pnite_dados_consolidados.js')
    with open(js_path, 'w', encoding='utf-8') as f:
        f.write("/**\n * Dados Consolidados da PNITE extraídos das planilhas Excel em data/\n")
        f.write(f" * Gerado automaticamente em: {pacote_consolidado['metadados']['data_extracao']}\n */\n")
        f.write("window.PNITE_EXCEL_DATA = ")
        json.dump(pacote_consolidado, f, ensure_ascii=False, separators=(',', ':'))
        f.write(";\n")
    print(f"  [OK] Arquivo JS exportado com sucesso: '{js_path}' ({os.path.getsize(js_path)//1024} KB)")

    return pacote_consolidado

if __name__ == '__main__':
    print("=" * 60)
    print("PNITE — Processamento e Extração de Dados das Planilhas Excel")
    print("=" * 60)
    resultado = extrair_e_consolidar_tudo()
    print("\nExtração finalizada com total sucesso!")
