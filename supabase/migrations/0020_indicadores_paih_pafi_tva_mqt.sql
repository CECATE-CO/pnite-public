-- ============================================================================
-- PNITE — 0020: PAIH, PAFI, TVA e MQT calculados; km médio pelas rotas com km válido
-- ----------------------------------------------------------------------------
-- Decisões do usuário (19/11/2026), após a revisão dos indicadores em construção:
--   PAIH  alunos transportados em rotas aquaviárias (tipo 2) com impedância marcada na
--         rota OU no cadastro do aluno ÷ alunos transportados em rotas aquaviárias.
--   PAFI  veículos com até 15 anos de fabricação ÷ veículos com ano de fabricação válido
--         (1930 até o ano de carga, mesma regra de IMFP/IMFT). Limite provisório, num só
--         lugar: analise.vida_util_frota_anos().
--   TVA   média do tempo das rotas aquaviárias (tipo 2) com tempo válido (1 a 360 min).
--   MQT   km médio por rota (valor principal) e, no raw, média, mediana, P5, P95, mínimo e
--         máximo do km e do tempo das rotas (estatísticas não aditivas por escopo).
--   Mapa  sem número mínimo de rotas/alunos por enquanto.
-- Regra dos 2.000 km aplicada também ao denominador do km médio: km_total ÷ rotas com km
-- válido (0 < km ≤ 2.000), em vez de ÷ todas as rotas (que contava as 125 rotas acima de
-- 2.000 km e as 46 com km = 0 como 0 km). Nacional: 53,0 → 53,1 km/rota.
--
-- mv_base_municipio ganha contadores aditivos; os quatro níveis, a tabela "Dados SETE" e a
-- view public.indicadores são recriados (mesmas definições da 0008/0014 com as colunas novas).
-- A tabela "Dados SETE" passa a trazer PAIH, PAFI, TVA e MQT (valores do painel), usados pelo
-- mapa municipal.
-- ============================================================================

DROP VIEW public.indicadores;
DROP MATERIALIZED VIEW public.sete_municipios;
DROP MATERIALIZED VIEW analise.mv_sete_municipio;
DROP MATERIALIZED VIEW public.indicadores_nacional;
DROP MATERIALIZED VIEW public.indicadores_regiao;
DROP MATERIALIZED VIEW public.indicadores_estado;
DROP MATERIALIZED VIEW public.indicadores_municipio;
DROP MATERIALIZED VIEW analise.mv_base_municipio;

-- Vida útil adotada no PAFI (anos). Provisório: alterar aqui e rodar pnite_meta.atualizar_indicadores().
CREATE OR REPLACE FUNCTION analise.vida_util_frota_anos() RETURNS integer
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$ SELECT 15 $$;
COMMENT ON FUNCTION analise.vida_util_frota_anos() IS
  'Limite de vida útil (anos) do PAFI. Provisório (15 anos, decisão de 19/11/2026) até a definição da referência normativa.';

-- ---------------------------------------------------------------------------
-- Base municipal aditiva (0005) + contadores de PAIH, PAFI, TVA e km médio
-- ---------------------------------------------------------------------------
CREATE MATERIALIZED VIEW analise.mv_base_municipio AS
WITH
al AS (
    SELECT ano_carga, codigo_cidade, uf,
           count(*)                                   AS al_cad,
           count(*) FILTER (WHERE tem_deficiencia)    AS al_pcd,
           count(*) FILTER (WHERE tem_impedancia)     AS al_dif,
           count(*) FILTER (WHERE da_porteira)        AS al_porteira,
           count(*) FILTER (WHERE da_mataburro)       AS al_mataburro,
           count(*) FILTER (WHERE da_colchete)        AS al_colchete,
           count(*) FILTER (WHERE da_atoleiro)        AS al_atoleiro,
           count(*) FILTER (WHERE da_ponterustica)    AS al_ponte
    FROM analise.v_alunos GROUP BY 1, 2, 3),
rot AS (
    SELECT ano_carga, codigo_cidade, uf,
           count(*)                                   AS tot_rotas,
           count(*) FILTER (WHERE tem_shape)          AS georref,
           count(*) FILTER (WHERE tem_impedancia)     AS dif,
           count(*) FILTER (WHERE tipo = 1)           AS t1,
           count(*) FILTER (WHERE tipo = 2)           AS t2,
           count(*) FILTER (WHERE tipo = 3)           AS t3,
           count(*) FILTER (WHERE da_porteira)        AS rot_porteira,
           count(*) FILTER (WHERE da_mataburro)       AS rot_mataburro,
           count(*) FILTER (WHERE da_colchete)        AS rot_colchete,
           count(*) FILTER (WHERE da_atoleiro)        AS rot_atoleiro,
           count(*) FILTER (WHERE da_ponterustica)    AS rot_ponte,
           sum(coalesce(km, 0))                       AS km_total,
           coalesce(sum(coalesce(km, 0)) FILTER (WHERE tem_shape), 0) AS km_geo,
           count(*) FILTER (WHERE km > 0)             AS rotas_com_km,       -- km válido: 0 < km ≤ 2.000
           count(*) FILTER (WHERE tipo = 2 AND tempo_valido) AS t2_tempo_n,  -- TVA
           coalesce(sum(tempo) FILTER (WHERE tipo = 2 AND tempo_valido), 0) AS t2_tempo_soma
    FROM analise.v_rotas GROUP BY 1, 2, 3),
vei AS (
    SELECT ano_carga, codigo_cidade, uf,
           count(*)                                   AS tot_veic,
           count(*) FILTER (WHERE origem = 1)         AS vp,
           count(*) FILTER (WHERE origem = 2)         AS vt,
           count(*) FILTER (WHERE capacidade_valida)  AS n_veic_validos,
           coalesce(sum(capacidade) FILTER (WHERE capacidade_valida), 0) AS cap_sum,
           count(*) FILTER (WHERE caminho_da_escola)  AS ce_veic_sete,
           -- PAFI: idade = ano de carga − ano de fabricação (1930 até o ano de carga)
           count(*) FILTER (WHERE ano_fabricacao BETWEEN 1930 AND ano_carga) AS veic_ano_valido,
           count(*) FILTER (WHERE ano_fabricacao BETWEEN 1930 AND ano_carga
                              AND ano_carga - ano_fabricacao <= analise.vida_util_frota_anos()) AS veic_vida_util
    FROM analise.v_veiculos GROUP BY 1, 2, 3),
mot AS (
    SELECT ano_carga, codigo_cidade, uf,
           count(*) FILTER (WHERE vinculo_informado)  AS tot_mot_info,
           count(*) FILTER (WHERE sem_vinculo)        AS mot_sem_vinculo,
           count(*) FILTER (WHERE vinculo_formal)     AS mot_cv
    FROM analise.v_motoristas GROUP BY 1, 2, 3),
mon AS (
    SELECT ano_carga, codigo_cidade, uf,
           count(*) FILTER (WHERE vinculo_informado)  AS tot_mon,
           count(*) FILTER (WHERE sem_vinculo)        AS mon_sem_vinculo,
           count(*) FILTER (WHERE vinculo_formal)     AS mon_cv
    FROM analise.v_monitores GROUP BY 1, 2, 3),
-- Alunos transportados: ids distintos por município (o id do SETE não é global)
ate AS (
    SELECT ano_carga, codigo_cidade, lower(uf) AS uf, count(DISTINCT id_aluno) AS al_transp_sete
    FROM sete.rota_atende_aluno GROUP BY 1, 2, 3),
-- PAIH: alunos transportados em rotas aquaviárias (tipo 2); impedância na rota ou no cadastro do aluno
hid AS (
    SELECT ano_carga, codigo_cidade, uf,
           count(*)                    AS al_hidro,
           count(*) FILTER (WHERE imp) AS al_hidro_imp
    FROM (
        SELECT a.ano_carga, a.codigo_cidade, r.uf, a.id_aluno,
               bool_or(r.tem_impedancia OR coalesce(v.tem_impedancia, false)) AS imp
        FROM sete.rota_atende_aluno a
        JOIN analise.v_rotas r ON r.ano_carga = a.ano_carga AND r.codigo_cidade = a.codigo_cidade
                              AND r.id_rota = a.id_rota AND r.tipo = 2
        LEFT JOIN analise.v_alunos v ON v.ano_carga = a.ano_carga AND v.codigo_cidade = a.codigo_cidade
                                    AND v.id_aluno = a.id_aluno
        GROUP BY 1, 2, 3, 4) x
    GROUP BY 1, 2, 3),
esc AS (
    SELECT ano_carga, codigo_cidade, lower(uf) AS uf, count(DISTINCT id_escola) AS esc_at_sete
    FROM sete.rota_passa_por_escolas GROUP BY 1, 2, 3),
cen AS (
    SELECT c.ano_carga_sete AS ano_carga, m.codigo_cidade, m.uf, m.transp_publico AS demanda_censo
    FROM analise.v_censo_municipio m JOIN ref.cargas c ON c.ano_carga_censo = m.ano_carga),
chaves AS (
    SELECT ano_carga, codigo_cidade, uf FROM al  UNION SELECT ano_carga, codigo_cidade, uf FROM rot
    UNION SELECT ano_carga, codigo_cidade, uf FROM vei UNION SELECT ano_carga, codigo_cidade, uf FROM mot
    UNION SELECT ano_carga, codigo_cidade, uf FROM mon UNION SELECT ano_carga, codigo_cidade, uf FROM ate
    UNION SELECT ano_carga, codigo_cidade, uf FROM esc UNION SELECT ano_carga, codigo_cidade, uf FROM cen)
SELECT k.ano_carga, k.codigo_cidade, k.uf,
       coalesce(al.al_cad, 0) AS al_cad, coalesce(al.al_pcd, 0) AS al_pcd, coalesce(al.al_dif, 0) AS al_dif,
       coalesce(al.al_porteira, 0) AS al_porteira, coalesce(al.al_mataburro, 0) AS al_mataburro,
       coalesce(al.al_colchete, 0) AS al_colchete, coalesce(al.al_atoleiro, 0) AS al_atoleiro,
       coalesce(al.al_ponte, 0) AS al_ponte,
       coalesce(rot.tot_rotas, 0) AS tot_rotas, coalesce(rot.georref, 0) AS georref, coalesce(rot.dif, 0) AS dif,
       coalesce(rot.t1, 0) AS t1, coalesce(rot.t2, 0) AS t2, coalesce(rot.t3, 0) AS t3,
       coalesce(rot.rot_porteira, 0) AS rot_porteira, coalesce(rot.rot_mataburro, 0) AS rot_mataburro,
       coalesce(rot.rot_colchete, 0) AS rot_colchete, coalesce(rot.rot_atoleiro, 0) AS rot_atoleiro,
       coalesce(rot.rot_ponte, 0) AS rot_ponte,
       coalesce(rot.km_total, 0) AS km_total, coalesce(rot.km_geo, 0) AS km_geo,
       coalesce(vei.tot_veic, 0) AS tot_veic, coalesce(vei.vp, 0) AS vp, coalesce(vei.vt, 0) AS vt,
       coalesce(vei.n_veic_validos, 0) AS n_veic_validos, coalesce(vei.cap_sum, 0) AS cap_sum,
       coalesce(vei.ce_veic_sete, 0) AS ce_veic_sete,
       coalesce(mot.tot_mot_info, 0) AS tot_mot_info, coalesce(mot.mot_sem_vinculo, 0) AS mot_sem_vinculo,
       coalesce(mot.mot_cv, 0) AS mot_cv,
       coalesce(mon.tot_mon, 0) AS tot_mon, coalesce(mon.mon_sem_vinculo, 0) AS mon_sem_vinculo,
       coalesce(mon.mon_cv, 0) AS mon_cv,
       coalesce(ate.al_transp_sete, 0) AS al_transp_sete,
       coalesce(esc.esc_at_sete, 0) AS esc_at_sete,
       coalesce(cen.demanda_censo, 0) AS demanda_censo,
       coalesce(rot.rotas_com_km, 0) AS rotas_com_km,
       coalesce(rot.t2_tempo_n, 0) AS t2_tempo_n, coalesce(rot.t2_tempo_soma, 0) AS t2_tempo_soma,
       coalesce(vei.veic_ano_valido, 0) AS veic_ano_valido, coalesce(vei.veic_vida_util, 0) AS veic_vida_util,
       coalesce(hid.al_hidro, 0) AS al_hidro, coalesce(hid.al_hidro_imp, 0) AS al_hidro_imp
FROM chaves k
LEFT JOIN al  USING (ano_carga, codigo_cidade, uf)
LEFT JOIN rot USING (ano_carga, codigo_cidade, uf)
LEFT JOIN vei USING (ano_carga, codigo_cidade, uf)
LEFT JOIN mot USING (ano_carga, codigo_cidade, uf)
LEFT JOIN mon USING (ano_carga, codigo_cidade, uf)
LEFT JOIN ate USING (ano_carga, codigo_cidade, uf)
LEFT JOIN hid USING (ano_carga, codigo_cidade, uf)
LEFT JOIN esc USING (ano_carga, codigo_cidade, uf)
LEFT JOIN cen USING (ano_carga, codigo_cidade, uf);

CREATE UNIQUE INDEX idx_mv_base_municipio ON analise.mv_base_municipio (ano_carga, codigo_cidade, uf);
COMMENT ON MATERIALIZED VIEW analise.mv_base_municipio IS
  'Contagens e somas aditivas por município (SETE + Censo pareado). Atualizar com pnite_meta.atualizar_indicadores().';

-- ---------------------------------------------------------------------------
-- MQT: estatísticas não aditivas das rotas por nível (km válido: 0 < km ≤ 2.000;
-- tempo válido: 1 a 360 min). Média e mediana do tempo continuam em mv_tempo_rotas.
-- ---------------------------------------------------------------------------
CREATE MATERIALIZED VIEW analise.mv_rotas_estatisticas AS
WITH r AS (
    SELECT v.ano_carga, v.codigo_cidade, v.uf, u.regiao,
           CASE WHEN v.km > 0 THEN v.km END AS km,
           CASE WHEN v.tempo_valido THEN v.tempo END AS tempo
    FROM analise.v_rotas v JOIN ref.uf u ON u.sigla = v.uf),
g AS (
    SELECT ano_carga,
           CASE WHEN GROUPING(codigo_cidade) = 0 THEN 'municipio'
                WHEN GROUPING(uf) = 0 THEN 'estado'
                WHEN GROUPING(regiao) = 0 THEN 'regiao'
                ELSE 'nacional' END AS nivel,
           CASE WHEN GROUPING(codigo_cidade) = 0 THEN codigo_cidade::text
                WHEN GROUPING(uf) = 0 THEN uf
                WHEN GROUPING(regiao) = 0 THEN regiao
                ELSE 'nacional' END AS chave,
           percentile_cont(ARRAY[0.05, 0.5, 0.95]) WITHIN GROUP (ORDER BY km)    AS km_p,
           min(km) AS km_min, max(km) AS km_max,
           percentile_cont(ARRAY[0.05, 0.95])      WITHIN GROUP (ORDER BY tempo) AS tempo_p,
           min(tempo) AS tempo_min, max(tempo) AS tempo_max
    FROM r
    GROUP BY GROUPING SETS ((ano_carga, codigo_cidade, uf, regiao), (ano_carga, uf, regiao),
                            (ano_carga, regiao), (ano_carga)))
SELECT ano_carga, nivel, chave,
       jsonb_strip_nulls(jsonb_build_object(
         'km_mediana', round(km_p[2]::numeric, 1), 'km_p5', round(km_p[1]::numeric, 1),
         'km_p95', round(km_p[3]::numeric, 1), 'km_min', km_min, 'km_max', km_max,
         'tempo_p5', round(tempo_p[1]::numeric, 1), 'tempo_p95', round(tempo_p[2]::numeric, 1),
         'tempo_min', tempo_min, 'tempo_max', tempo_max)) AS estat
FROM g;

CREATE UNIQUE INDEX idx_mv_rotas_estatisticas ON analise.mv_rotas_estatisticas (ano_carga, nivel, chave);
COMMENT ON MATERIALIZED VIEW analise.mv_rotas_estatisticas IS
  'MQT: mediana, P5, P95, mínimo e máximo do km (0 < km ≤ 2.000) e P5, P95, mínimo e máximo do tempo (1 a 360 min) das rotas, por nível.';

-- ---------------------------------------------------------------------------
-- raw: km médio pelas rotas com km válido (regra dos 2.000 km também no denominador)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION analise.montar_raw(contadores jsonb, tempo_mediano numeric, tempo_medio numeric)
RETURNS jsonb LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT contadores || jsonb_build_object(
           'km_total',  round(analise.num(contadores, 'km_total'), 1),
           'km_geo',    round(analise.num(contadores, 'km_geo'), 1),
           'km_medio',  CASE WHEN analise.num(contadores, 'rotas_com_km') > 0
                             THEN round(round(analise.num(contadores, 'km_total'), 1)
                                        / analise.num(contadores, 'rotas_com_km'), 1) END,
           'cap_media', CASE WHEN analise.num(contadores, 'n_veic_validos') > 0
                             THEN round(analise.num(contadores, 'cap_sum')
                                        / analise.num(contadores, 'n_veic_validos'), 2)
                             ELSE 0.0 END,
           'al_transp', contadores -> 'al_transp_sete')
         || jsonb_strip_nulls(jsonb_build_object('tempo_mediano', tempo_mediano, 'tempo_medio', tempo_medio))
$$;
COMMENT ON FUNCTION analise.montar_raw(jsonb, numeric, numeric) IS
  'Monta o raw (formato RAW_DATA) a partir dos contadores somados de um escopo: km arredondado, km_medio (÷ rotas com km válido), cap_media, al_transp e tempos.';

-- ---------------------------------------------------------------------------
-- Indicadores (0006) com PAIH, PAFI, TVA e MQT calculados
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION analise.calcular_indicadores(r jsonb, label text) RETURNS jsonb
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  WITH v AS (
    SELECT analise.num(r, 'tot_rotas') AS tr, analise.num(r, 'tot_veic') AS tv,
           analise.num(r, 'n_veic_validos') AS nvv, analise.num(r, 'cap_media') AS cap_m,
           analise.num(r, 'al_transp') AS at, analise.num(r, 'esc_at') AS ea,
           analise.num(r, 'tot_mon') AS tm, analise.num(r, 'tot_mot_info') AS tmi,
           analise.num(r, 'dif') AS dif, analise.num(r, 'al_cad') AS al_cad,
           coalesce(analise.num(r, 'mot_sem_vinculo'), 0) AS mot_sem,
           coalesce(analise.num(r, 'mon_sem_vinculo'), 0) AS mon_sem,
           analise.num(r, 't2_tempo_n') AS t2n, analise.num(r, 't2_tempo_soma') AS t2s
  ), c AS (
    SELECT v.*,
           analise.pct(dif, tr) AS prio,
           CASE WHEN tmi > 0 THEN round((1 - mot_sem / tmi) * 100, 2)
                ELSE analise.pct(analise.num(r, 'mot_cv'), tmi) END AS pmve,
           CASE WHEN tm > 0 THEN round((1 - mon_sem / tm) * 100, 2)
                ELSE analise.pct(analise.num(r, 'mon_cv'), tm) END AS pmnve,
           CASE WHEN at <> 0 AND nvv <> 0 AND cap_m <> 0 AND nvv * cap_m > 0
                THEN round(at / (nvv * cap_m), 2) END AS iuc,
           CASE WHEN at <> 0 AND ea > 0 THEN round(at / ea, 2) END AS ate
    FROM v
  )
  SELECT jsonb_build_object(
    'label', label,
    'PRGM',  analise.pct(analise.num(r, 'georref'), tr),
    'PRDAM', prio,
    'PRIO',  prio,
    'PRRM',  analise.pct(analise.num(r, 't1'), tr),
    'PRHM',  analise.pct(analise.num(r, 't2'), tr),
    'PRMM',  analise.pct(analise.num(r, 't3'), tr),
    'PVP',   analise.pct(analise.num(r, 'vp'), tv),
    'PVT',   analise.pct(analise.num(r, 'vt'), tv),
    'PVPCE', analise.pct(analise.num(r, 'ce_veic'), tv),
    'PECS',  analise.pct(analise.num(r, 'sete_esc'), analise.num(r, 'cs_esc_transp')),
    'IUC',   iuc,
    'PMVE',  pmve,
    'PMNVE', pmnve,
    'MON_CVE', pmnve,
    'MOT_CVE', pmve,
    'PRPM',  NULL,
    'ATE',   ate,
    'TETI',  NULL,
    'IPE',   NULL,
    'TEDC',  analise.pct(at, al_cad),
    'PATM',  analise.pct(analise.num(r, 'cs_tmun'), analise.num(r, 'cs_transp')),
    'PATE',  analise.pct(analise.num(r, 'cs_test'), analise.num(r, 'cs_transp')),
    'IPTE',  NULL,
    'MEDATE', r -> 'medate_val',
    'ICA',   NULL,
    'IMFP',  r -> 'imfp',
    'IMFT',  r -> 'imft',
    'MIFCE', r -> 'mifce',
    'PAFI',  analise.pct(analise.num(r, 'veic_vida_util'), analise.num(r, 'veic_ano_valido')),
    'PAD',   analise.pct(analise.num(r, 'al_pcd'), al_cad),
    'PARI',  analise.pct(analise.num(r, 'al_dif'), coalesce(nullif(al_cad, 0), at)),
    'PCSC',  analise.pct(analise.num(r, 'al_transp_sete'), analise.num(r, 'demanda_censo')),
    'PAIH',  analise.pct(analise.num(r, 'al_hidro_imp'), analise.num(r, 'al_hidro')),
    'PRPNP', NULL,
    'DMC',   NULL,
    'PVCED', NULL,
    'TVA',   CASE WHEN t2n > 0 THEN round(t2s / t2n, 1) END,
    'MQT',   analise.num(r, 'km_medio')
  )
  FROM c
$$;
COMMENT ON FUNCTION analise.calcular_indicadores(jsonb, text) IS
  'Indicadores (formato DATA) a partir dos contadores (formato RAW_DATA). PAIH, PAFI, TVA e MQT calculados desde a 0020.';

-- ---------------------------------------------------------------------------
-- Nível 1 — município
-- ---------------------------------------------------------------------------
CREATE MATERIALIZED VIEW public.indicadores_municipio AS
SELECT b.*,
       m.nome,
       u.regiao,
       coalesce(m.nome, 'Município ' || b.codigo_cidade) || ' (' || upper(b.uf) || ')' AS label,
       t.tempo_mediano, t.tempo_medio,
       r.raw,
       analise.calcular_indicadores(r.raw, coalesce(m.nome, 'Município ' || b.codigo_cidade)
                                           || ' (' || upper(b.uf) || ')') AS indicadores,
       now() AS atualizado_em
FROM analise.mv_base_municipio b
JOIN ref.uf u ON u.sigla = b.uf
LEFT JOIN ref.municipios m ON m.codigo_ibge = b.codigo_cidade
LEFT JOIN analise.mv_tempo_rotas t
       ON t.ano_carga = b.ano_carga AND t.nivel = 'municipio' AND t.chave = b.codigo_cidade::text
LEFT JOIN analise.mv_rotas_estatisticas e
       ON e.ano_carga = b.ano_carga AND e.nivel = 'municipio' AND e.chave = b.codigo_cidade::text
CROSS JOIN LATERAL (
    SELECT analise.montar_raw(to_jsonb(b) - ARRAY['ano_carga', 'codigo_cidade', 'uf'],
                              t.tempo_mediano, t.tempo_medio)
           || coalesce(e.estat, '{}'::jsonb) AS raw
) r;

CREATE UNIQUE INDEX idx_indicadores_municipio ON public.indicadores_municipio (ano_carga, codigo_cidade, uf);
CREATE INDEX idx_indicadores_municipio_uf ON public.indicadores_municipio (ano_carga, uf);
COMMENT ON MATERIALIZED VIEW public.indicadores_municipio IS
  'PNITE — indicadores por município. Ex.: /rest/v1/indicadores_municipio?ano_carga=eq.2026&uf=eq.go';

-- ---------------------------------------------------------------------------
-- Nível 2 — estado: soma dos municípios da UF
-- ---------------------------------------------------------------------------
CREATE MATERIALIZED VIEW public.indicadores_estado AS
WITH s AS (
    SELECT ano_carga, uf,
           sum(al_cad) AS al_cad, sum(al_pcd) AS al_pcd, sum(al_dif) AS al_dif,
           sum(al_porteira) AS al_porteira, sum(al_mataburro) AS al_mataburro, sum(al_colchete) AS al_colchete,
           sum(al_atoleiro) AS al_atoleiro, sum(al_ponte) AS al_ponte,
           sum(tot_rotas) AS tot_rotas, sum(georref) AS georref, sum(dif) AS dif,
           sum(t1) AS t1, sum(t2) AS t2, sum(t3) AS t3,
           sum(rot_porteira) AS rot_porteira, sum(rot_mataburro) AS rot_mataburro, sum(rot_colchete) AS rot_colchete,
           sum(rot_atoleiro) AS rot_atoleiro, sum(rot_ponte) AS rot_ponte,
           sum(km_total) AS km_total, sum(km_geo) AS km_geo,
           sum(tot_veic) AS tot_veic, sum(vp) AS vp, sum(vt) AS vt,
           sum(n_veic_validos) AS n_veic_validos, sum(cap_sum) AS cap_sum, sum(ce_veic_sete) AS ce_veic_sete,
           sum(tot_mot_info) AS tot_mot_info, sum(mot_sem_vinculo) AS mot_sem_vinculo, sum(mot_cv) AS mot_cv,
           sum(tot_mon) AS tot_mon, sum(mon_sem_vinculo) AS mon_sem_vinculo, sum(mon_cv) AS mon_cv,
           sum(al_transp_sete) AS al_transp_sete, sum(esc_at_sete) AS esc_at_sete,
           sum(demanda_censo) AS demanda_censo,
           sum(rotas_com_km) AS rotas_com_km, sum(t2_tempo_n) AS t2_tempo_n, sum(t2_tempo_soma) AS t2_tempo_soma,
           sum(veic_ano_valido) AS veic_ano_valido, sum(veic_vida_util) AS veic_vida_util,
           sum(al_hidro) AS al_hidro, sum(al_hidro_imp) AS al_hidro_imp
    FROM public.indicadores_municipio
    GROUP BY ano_carga, uf
)
SELECT s.*,
       u.nome, u.regiao,
       u.nome AS label,
       t.tempo_mediano, t.tempo_medio,
       r.raw,
       analise.calcular_indicadores(r.raw, u.nome) AS indicadores,
       (SELECT jsonb_object_agg(d.script, d.dados) FROM ref.detalhes_scripts d
         WHERE d.ano_carga = s.ano_carga AND d.chave = s.uf) AS detalhes,
       now() AS atualizado_em
FROM s
JOIN ref.uf u ON u.sigla = s.uf
LEFT JOIN analise.mv_tempo_rotas t ON t.ano_carga = s.ano_carga AND t.nivel = 'estado' AND t.chave = s.uf
LEFT JOIN analise.mv_rotas_estatisticas e ON e.ano_carga = s.ano_carga AND e.nivel = 'estado' AND e.chave = s.uf
LEFT JOIN ref.raw_referencia rr ON rr.ano_carga = s.ano_carga AND rr.chave = s.uf
CROSS JOIN LATERAL (
    -- contadores calculados dos dados brutos sobrepõem os valores de referência (legado + planilhas)
    SELECT coalesce(rr.dados, '{}'::jsonb)
           || analise.montar_raw(to_jsonb(s) - ARRAY['ano_carga', 'uf'], t.tempo_mediano, t.tempo_medio)
           || coalesce(e.estat, '{}'::jsonb) AS raw
) r;

CREATE UNIQUE INDEX idx_indicadores_estado ON public.indicadores_estado (ano_carga, uf);
COMMENT ON MATERIALIZED VIEW public.indicadores_estado IS
  'PNITE — indicadores por UF (soma dos municípios). Ex.: /rest/v1/indicadores_estado?ano_carga=eq.2026&uf=eq.go';

-- ---------------------------------------------------------------------------
-- Nível 3 — região: soma das UFs da região
-- ---------------------------------------------------------------------------
CREATE MATERIALIZED VIEW public.indicadores_regiao AS
WITH s AS (
    SELECT ano_carga, regiao,
           sum(al_cad) AS al_cad, sum(al_pcd) AS al_pcd, sum(al_dif) AS al_dif,
           sum(al_porteira) AS al_porteira, sum(al_mataburro) AS al_mataburro, sum(al_colchete) AS al_colchete,
           sum(al_atoleiro) AS al_atoleiro, sum(al_ponte) AS al_ponte,
           sum(tot_rotas) AS tot_rotas, sum(georref) AS georref, sum(dif) AS dif,
           sum(t1) AS t1, sum(t2) AS t2, sum(t3) AS t3,
           sum(rot_porteira) AS rot_porteira, sum(rot_mataburro) AS rot_mataburro, sum(rot_colchete) AS rot_colchete,
           sum(rot_atoleiro) AS rot_atoleiro, sum(rot_ponte) AS rot_ponte,
           sum(km_total) AS km_total, sum(km_geo) AS km_geo,
           sum(tot_veic) AS tot_veic, sum(vp) AS vp, sum(vt) AS vt,
           sum(n_veic_validos) AS n_veic_validos, sum(cap_sum) AS cap_sum, sum(ce_veic_sete) AS ce_veic_sete,
           sum(tot_mot_info) AS tot_mot_info, sum(mot_sem_vinculo) AS mot_sem_vinculo, sum(mot_cv) AS mot_cv,
           sum(tot_mon) AS tot_mon, sum(mon_sem_vinculo) AS mon_sem_vinculo, sum(mon_cv) AS mon_cv,
           sum(al_transp_sete) AS al_transp_sete, sum(esc_at_sete) AS esc_at_sete,
           sum(demanda_censo) AS demanda_censo,
           sum(rotas_com_km) AS rotas_com_km, sum(t2_tempo_n) AS t2_tempo_n, sum(t2_tempo_soma) AS t2_tempo_soma,
           sum(veic_ano_valido) AS veic_ano_valido, sum(veic_vida_util) AS veic_vida_util,
           sum(al_hidro) AS al_hidro, sum(al_hidro_imp) AS al_hidro_imp
    FROM public.indicadores_estado
    GROUP BY ano_carga, regiao
)
SELECT s.*,
       rg.regiao_label AS label,
       t.tempo_mediano, t.tempo_medio,
       r.raw,
       analise.calcular_indicadores(r.raw, rg.regiao_label) AS indicadores,
       now() AS atualizado_em
FROM s
JOIN (SELECT DISTINCT regiao, regiao_label FROM ref.uf) rg ON rg.regiao = s.regiao
LEFT JOIN analise.mv_tempo_rotas t ON t.ano_carga = s.ano_carga AND t.nivel = 'regiao' AND t.chave = s.regiao
LEFT JOIN analise.mv_rotas_estatisticas e ON e.ano_carga = s.ano_carga AND e.nivel = 'regiao' AND e.chave = s.regiao
LEFT JOIN ref.raw_referencia rr ON rr.ano_carga = s.ano_carga AND rr.chave = s.regiao
CROSS JOIN LATERAL (
    SELECT coalesce(rr.dados, '{}'::jsonb)
           || analise.montar_raw(to_jsonb(s) - ARRAY['ano_carga', 'regiao'], t.tempo_mediano, t.tempo_medio)
           || coalesce(e.estat, '{}'::jsonb) AS raw
) r;

CREATE UNIQUE INDEX idx_indicadores_regiao ON public.indicadores_regiao (ano_carga, regiao);
COMMENT ON MATERIALIZED VIEW public.indicadores_regiao IS
  'PNITE — indicadores por região (soma das UFs). Ex.: /rest/v1/indicadores_regiao?ano_carga=eq.2026&regiao=eq.centro-oeste';

-- ---------------------------------------------------------------------------
-- Nível 4 — nacional: soma das regiões
-- ---------------------------------------------------------------------------
CREATE MATERIALIZED VIEW public.indicadores_nacional AS
WITH s AS (
    SELECT ano_carga,
           sum(al_cad) AS al_cad, sum(al_pcd) AS al_pcd, sum(al_dif) AS al_dif,
           sum(al_porteira) AS al_porteira, sum(al_mataburro) AS al_mataburro, sum(al_colchete) AS al_colchete,
           sum(al_atoleiro) AS al_atoleiro, sum(al_ponte) AS al_ponte,
           sum(tot_rotas) AS tot_rotas, sum(georref) AS georref, sum(dif) AS dif,
           sum(t1) AS t1, sum(t2) AS t2, sum(t3) AS t3,
           sum(rot_porteira) AS rot_porteira, sum(rot_mataburro) AS rot_mataburro, sum(rot_colchete) AS rot_colchete,
           sum(rot_atoleiro) AS rot_atoleiro, sum(rot_ponte) AS rot_ponte,
           sum(km_total) AS km_total, sum(km_geo) AS km_geo,
           sum(tot_veic) AS tot_veic, sum(vp) AS vp, sum(vt) AS vt,
           sum(n_veic_validos) AS n_veic_validos, sum(cap_sum) AS cap_sum, sum(ce_veic_sete) AS ce_veic_sete,
           sum(tot_mot_info) AS tot_mot_info, sum(mot_sem_vinculo) AS mot_sem_vinculo, sum(mot_cv) AS mot_cv,
           sum(tot_mon) AS tot_mon, sum(mon_sem_vinculo) AS mon_sem_vinculo, sum(mon_cv) AS mon_cv,
           sum(al_transp_sete) AS al_transp_sete, sum(esc_at_sete) AS esc_at_sete,
           sum(demanda_censo) AS demanda_censo,
           sum(rotas_com_km) AS rotas_com_km, sum(t2_tempo_n) AS t2_tempo_n, sum(t2_tempo_soma) AS t2_tempo_soma,
           sum(veic_ano_valido) AS veic_ano_valido, sum(veic_vida_util) AS veic_vida_util,
           sum(al_hidro) AS al_hidro, sum(al_hidro_imp) AS al_hidro_imp
    FROM public.indicadores_regiao
    GROUP BY ano_carga
)
SELECT s.*,
       'Brasil'::text AS label,
       t.tempo_mediano, t.tempo_medio,
       r.raw,
       analise.calcular_indicadores(r.raw, 'Brasil') AS indicadores,
       (SELECT jsonb_object_agg(d.script, d.dados) FROM ref.detalhes_scripts d
         WHERE d.ano_carga = s.ano_carga AND d.chave = 'nacional') AS detalhes,
       now() AS atualizado_em
FROM s
LEFT JOIN analise.mv_tempo_rotas t ON t.ano_carga = s.ano_carga AND t.nivel = 'nacional' AND t.chave = 'nacional'
LEFT JOIN analise.mv_rotas_estatisticas e ON e.ano_carga = s.ano_carga AND e.nivel = 'nacional' AND e.chave = 'nacional'
LEFT JOIN ref.raw_referencia rr ON rr.ano_carga = s.ano_carga AND rr.chave = 'nacional'
CROSS JOIN LATERAL (
    SELECT coalesce(rr.dados, '{}'::jsonb)
           || analise.montar_raw(to_jsonb(s) - 'ano_carga', t.tempo_mediano, t.tempo_medio)
           || coalesce(e.estat, '{}'::jsonb) AS raw
) r;

CREATE UNIQUE INDEX idx_indicadores_nacional ON public.indicadores_nacional (ano_carga);
COMMENT ON MATERIALIZED VIEW public.indicadores_nacional IS
  'PNITE — indicadores do Brasil (soma das regiões). Ex.: /rest/v1/indicadores_nacional?ano_carga=eq.2026';

-- ---------------------------------------------------------------------------
-- Interface única por (nivel, chave), como na 0008
-- ---------------------------------------------------------------------------
CREATE VIEW public.indicadores WITH (security_invoker = true) AS
SELECT ano_carga, 'municipio'::text AS nivel, codigo_cidade::text AS chave, uf, regiao, label,
       raw, indicadores, NULL::jsonb AS detalhes, atualizado_em
FROM public.indicadores_municipio
UNION ALL
SELECT ano_carga, 'estado', uf, uf, regiao, label, raw, indicadores, detalhes, atualizado_em
FROM public.indicadores_estado
UNION ALL
SELECT ano_carga, 'regiao', regiao, NULL, regiao, label, raw, indicadores, NULL, atualizado_em
FROM public.indicadores_regiao
UNION ALL
SELECT ano_carga, 'nacional', 'nacional', NULL, NULL, label, raw, indicadores, detalhes, atualizado_em
FROM public.indicadores_nacional;
COMMENT ON VIEW public.indicadores IS
  'PNITE — todos os níveis numa interface única (nivel, chave). Ex.: /rest/v1/indicadores?ano_carga=eq.2026&nivel=eq.estado&chave=eq.go';

-- ---------------------------------------------------------------------------
-- Tabela "Dados SETE" (0014) + PAIH, PAFI, TVA e MQT (valores do painel)
-- ---------------------------------------------------------------------------
CREATE MATERIALIZED VIEW analise.mv_sete_municipio AS
WITH
esc AS (SELECT ano_carga, codigo_cidade, count(*) AS n FROM sete.escolas GROUP BY 1, 2),
rk  AS (SELECT ano_carga, codigo_cidade, count(*) FILTER (WHERE km > 0) AS n
        FROM analise.v_rotas GROUP BY 1, 2),
mot AS (SELECT ano_carga, codigo_cidade, count(*) AS n FROM analise.v_motoristas GROUP BY 1, 2),
fo  AS (SELECT ano_carga, codigo_cidade, count(*) AS n FROM sete.fornecedores GROUP BY 1, 2),
os  AS (SELECT ano_carga, codigo_cidade, count(*) AS n FROM sete.ordem_servico GROUP BY 1, 2),
nm  AS (SELECT ano_carga, codigo_cidade, count(*) AS n FROM sete.normas GROUP BY 1, 2),
eta AS (SELECT ano_carga, codigo_cidade, count(*) AS n FROM sete.escola_tem_aluno GROUP BY 1, 2),
rpe AS (SELECT ano_carga, codigo_cidade, count(*) AS n FROM sete.rota_passa_por_escolas GROUP BY 1, 2),
rpv AS (SELECT ano_carga, codigo_cidade, count(*) AS n FROM sete.rota_possui_veiculo GROUP BY 1, 2),
rdm AS (SELECT ano_carga, codigo_cidade, count(*) AS n FROM sete.rota_dirigida_por_motorista GROUP BY 1, 2),
-- Rotas com veículo adequado (ônibus, micro-ônibus ou van) e alunos atendidos por elas (TETI)
adequada AS (
    SELECT DISTINCT p.ano_carga, p.codigo_cidade, p.id_rota
    FROM sete.rota_possui_veiculo p
    JOIN sete.veiculos v ON v.ano_carga = p.ano_carga AND v.codigo_cidade = p.codigo_cidade AND v.id_veiculo = p.id_veiculo
    WHERE v.tipo IN (1, 2, 3)),
al_adeq AS (
    SELECT a.ano_carga, a.codigo_cidade, count(DISTINCT a.id_aluno) AS n
    FROM sete.rota_atende_aluno a
    JOIN adequada r ON r.ano_carga = a.ano_carga AND r.codigo_cidade = a.codigo_cidade AND r.id_rota = a.id_rota
    GROUP BY 1, 2),
base AS (
    SELECT b.*, mu.nome,
           coalesce(esc.n, 0) AS escolas, coalesce(rk.n, 0) AS rotas_com_km_sete,
           coalesce(mot.n, 0) AS motoristas,
           i.indicadores AS ind,
           coalesce(fo.n, 0) AS fornecedores, coalesce(os.n, 0) AS ordens_servico, coalesce(nm.n, 0) AS normas,
           coalesce(eta.n, 0) AS v_eta, coalesce(rpe.n, 0) AS v_rpe, coalesce(rpv.n, 0) AS v_rpv, coalesce(rdm.n, 0) AS v_rdm,
           coalesce(al_adeq.n, 0) AS al_adequado
    FROM analise.mv_base_municipio b
    JOIN ref.municipios mu ON mu.codigo_ibge = b.codigo_cidade AND mu.codigo_ibge < 10000000
    LEFT JOIN esc     USING (ano_carga, codigo_cidade)
    LEFT JOIN rk      USING (ano_carga, codigo_cidade)
    LEFT JOIN mot     USING (ano_carga, codigo_cidade)
    LEFT JOIN fo      USING (ano_carga, codigo_cidade)
    LEFT JOIN os      USING (ano_carga, codigo_cidade)
    LEFT JOIN nm      USING (ano_carga, codigo_cidade)
    LEFT JOIN eta     USING (ano_carga, codigo_cidade)
    LEFT JOIN rpe     USING (ano_carga, codigo_cidade)
    LEFT JOIN rpv     USING (ano_carga, codigo_cidade)
    LEFT JOIN rdm     USING (ano_carga, codigo_cidade)
    LEFT JOIN al_adeq USING (ano_carga, codigo_cidade)
    -- valores do painel principal: mesma definição de km, capacidade, IUC e vínculo
    LEFT JOIN public.indicadores_municipio i ON i.ano_carga = b.ano_carga AND i.codigo_cidade = b.codigo_cidade AND i.uf = b.uf)
SELECT base.ano_carga, base.codigo_cidade, base.uf, base.nome,
       base.al_cad, base.al_transp_sete, base.escolas, base.tot_rotas,
       round(base.km_total, 1) AS km_total, base.km_total AS km_bruto, base.rotas_com_km_sete AS rotas_com_km,
       base.t1, base.t2, base.t3, base.tot_veic, base.vp, base.vt,
       CASE WHEN base.n_veic_validos > 0 THEN round(base.cap_sum / base.n_veic_validos, 2) END AS cap_media,
       base.cap_sum, base.n_veic_validos,
       base.tot_mon, base.motoristas, base.fornecedores, base.ordens_servico, base.normas,
       base.v_eta, base.v_rpe, base.v_rpv, base.v_rdm,
       analise.pct_par(base.georref, base.tot_rotas) AS prgm,
       analise.pct_par(base.dif, base.tot_rotas)     AS prdam,
       analise.pct_par(base.t1, base.tot_rotas)      AS prrm,
       analise.pct_par(base.t2, base.tot_rotas)      AS prhm,
       analise.pct_par(base.t3, base.tot_rotas)      AS prmm,
       analise.pct_par(base.vp, base.tot_veic)       AS pvp,
       analise.pct_par(base.vt, base.tot_veic)       AS pvt,
       (base.ind ->> 'PMNVE')::numeric AS mon_cve,
       (base.ind ->> 'PMVE')::numeric  AS mot_cve,
       (base.ind ->> 'IUC')::numeric   AS iuc,
       analise.pct_par(base.al_transp_sete, base.al_cad) AS tedc,
       analise.pct_par(base.al_adequado, base.al_transp_sete) AS teti,
       (base.ind ->> 'PAIH')::numeric  AS paih,
       (base.ind ->> 'PAFI')::numeric  AS pafi,
       (base.ind ->> 'TVA')::numeric   AS tva,
       (base.ind ->> 'MQT')::numeric   AS mqt
FROM base
WHERE base.al_cad > 0 OR base.tot_rotas > 0 OR base.tot_veic > 0 OR base.escolas > 0
   OR base.tot_mon > 0 OR base.motoristas > 0;

CREATE UNIQUE INDEX idx_mv_sete_municipio ON analise.mv_sete_municipio (ano_carga, codigo_cidade);
COMMENT ON MATERIALIZED VIEW analise.mv_sete_municipio IS
  'Tabela "Dados SETE" por município; km_total, cap_media, IUC, MON_CVE, MOT_CVE, PAIH, PAFI, TVA e MQT iguais aos do painel (public.indicadores_municipio).';

CREATE MATERIALIZED VIEW public.sete_municipios AS
SELECT s.ano_carga,
       jsonb_build_object(
         'cols', jsonb_build_array('cod', 'mun', 'uf', 'alunos', 'al_transp', 'escolas', 'rotas', 'km_total', 'rotas_com_km',
                                   'rotas_t1', 'rotas_t2', 'rotas_t3', 'veiculos', 'veic_origem1', 'veic_origem2', 'cap_media',
                                   'monitores', 'motoristas', 'fornecedores', 'ordens_servico', 'normas', 'vinc_escola_aluno',
                                   'vinc_rota_escola', 'vinc_rota_veiculo', 'vinc_rota_motorista', 'PRGM', 'PRDAM', 'PRRM', 'PRHM',
                                   'PRMM', 'PVP', 'PVT', 'MON_CVE', 'MOT_CVE', 'ATE', 'MEDATE', 'IUC', 'TEDC', 'TETI', 'PATE', 'PATM',
                                   'PVPCE', 'IMFP', 'IMFT', 'MIFCE', 'PAIH', 'PAFI', 'TVA', 'MQT'),
         'municipios', (
           SELECT jsonb_agg(jsonb_build_array(
                    m.codigo_cidade, m.nome, upper(m.uf), m.al_cad, m.al_transp_sete, m.escolas, m.tot_rotas, m.km_total, m.rotas_com_km,
                    m.t1, m.t2, m.t3, m.tot_veic, m.vp, m.vt, m.cap_media,
                    m.tot_mon, m.motoristas, m.fornecedores, m.ordens_servico, m.normas, m.v_eta,
                    m.v_rpe, m.v_rpv, m.v_rdm, m.prgm, m.prdam, m.prrm, m.prhm,
                    m.prmm, m.pvp, m.pvt, m.mon_cve, m.mot_cve, c.censo -> 'ATE', c.censo -> 'MEDATE', m.iuc, m.tedc, m.teti,
                    c.censo -> 'PATE', c.censo -> 'PATM',
                    c.frota -> 'PVPCE', c.frota -> 'IMFP', c.frota -> 'IMFT', c.frota -> 'MIFCE',
                    m.paih, m.pafi, m.tva, m.mqt) ORDER BY m.codigo_cidade)
           FROM analise.mv_sete_municipio m
           LEFT JOIN analise.mv_complemento_municipio c USING (ano_carga, codigo_cidade)
           WHERE m.ano_carga = s.ano_carga),
         'ufs', (
           SELECT jsonb_object_agg(upper(u.uf), jsonb_build_object(
                    'nome', uf.nome, 'mun', u.mun, 'alunos', u.alunos, 'at', u.at, 'escolas', u.escolas, 'rotas', u.rotas,
                    'km', u.km, 'km_n', u.km_n, 'rt1', u.rt1, 'rt2', u.rt2, 'rt3', u.rt3, 'veiculos', u.veiculos,
                    'vp', u.vp, 'vt', u.vt, 'cap', u.cap, 'monitores', u.monitores, 'motoristas', u.motoristas,
                    'fornecedores', u.fornecedores, 'ordens', u.ordens, 'normas', u.normas,
                    'v_eta', u.v_eta, 'v_rpe', u.v_rpe, 'v_rpv', u.v_rpv, 'v_rdm', u.v_rdm))
           FROM (
             SELECT m.uf, count(*) AS mun, sum(m.al_cad) AS alunos, sum(m.al_transp_sete) AS at, sum(m.escolas) AS escolas,
                    sum(m.tot_rotas) AS rotas, analise.round_par(sum(m.km_bruto), 1) AS km, sum(m.rotas_com_km) AS km_n,
                    sum(m.t1) AS rt1, sum(m.t2) AS rt2, sum(m.t3) AS rt3, sum(m.tot_veic) AS veiculos,
                    sum(m.vp) AS vp, sum(m.vt) AS vt,
                    round(sum(m.cap_sum) / nullif(sum(m.n_veic_validos), 0), 2) AS cap,
                    sum(m.tot_mon) AS monitores, sum(m.motoristas) AS motoristas, sum(m.fornecedores) AS fornecedores,
                    sum(m.ordens_servico) AS ordens, sum(m.normas) AS normas,
                    sum(m.v_eta) AS v_eta, sum(m.v_rpe) AS v_rpe, sum(m.v_rpv) AS v_rpv, sum(m.v_rdm) AS v_rdm
             FROM analise.mv_sete_municipio m
             WHERE m.ano_carga = s.ano_carga
             GROUP BY m.uf) u
           JOIN ref.uf uf ON uf.sigla = u.uf)
       ) AS dados
FROM (SELECT DISTINCT ano_carga FROM analise.mv_sete_municipio) s;
CREATE UNIQUE INDEX idx_sete_municipios ON public.sete_municipios (ano_carga);
COMMENT ON MATERIALIZED VIEW public.sete_municipios IS
  'Tabela "Dados SETE": {cols, municipios (linhas por município), ufs (resumo por UF)} por ano de carga (lida pela interface PNITE).';

-- Somente leitura para a API (anon/authenticated); nada mais é exposto.
REVOKE ALL ON public.indicadores_municipio, public.indicadores_estado, public.indicadores_regiao,
              public.indicadores_nacional, public.indicadores, public.sete_municipios FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.indicadores_municipio, public.indicadores_estado, public.indicadores_regiao,
                public.indicadores_nacional, public.indicadores, public.sete_municipios TO anon, authenticated;

-- Atualização em cascata (a ordem importa: cada nível lê o anterior); lista da 0013 + estatísticas das rotas
CREATE OR REPLACE FUNCTION pnite_meta.atualizar_indicadores() RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  mv text;
BEGIN
  FOREACH mv IN ARRAY ARRAY['analise.mv_base_municipio', 'analise.mv_tempo_rotas', 'analise.mv_rotas_estatisticas',
                            'public.indicadores_municipio', 'public.indicadores_estado',
                            'public.indicadores_regiao', 'public.indicadores_nacional',
                            'public.rotas_tracado',
                            'analise.mv_complemento_municipio', 'analise.mv_sete_municipio',
                            'public.indicadores_municipio_complemento', 'public.sete_municipios'] LOOP
    IF (SELECT ispopulated FROM pg_matviews WHERE schemaname || '.' || matviewname = mv)
       AND EXISTS (SELECT 1 FROM pg_indexes i JOIN pg_index x ON x.indexrelid = (i.schemaname || '.' || i.indexname)::regclass
                   WHERE i.schemaname || '.' || i.tablename = mv AND x.indisunique) THEN
      EXECUTE format('REFRESH MATERIALIZED VIEW CONCURRENTLY %s', mv);
    ELSE
      EXECUTE format('REFRESH MATERIALIZED VIEW %s', mv);
    END IF;
  END LOOP;
END
$$;
REVOKE ALL ON FUNCTION pnite_meta.atualizar_indicadores() FROM PUBLIC;
