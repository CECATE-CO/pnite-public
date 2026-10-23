-- ============================================================================
-- PNITE — 0005: camada de análise (privada)
-- ----------------------------------------------------------------------------
-- 1) Views de leitura limpa (security_invoker): sem campos antigos ("desconsiderar"
--    no dicionário), S/N -> boolean, códigos -> rótulos, idade negativa -> NULL e UF
--    em minúsculas. As regras de limpeza ficam aqui, num só lugar, com a mesma
--    semântica do extrair_dados_excel.py (ex.: 'S' comparado sem diferenciar caixa).
-- 2) mv_base_municipio: só contagens e somas por município — somar municípios
--    reproduz exatamente os totais de UF, região e Brasil.
-- 3) mv_tempo_rotas: mediana e média do tempo das rotas por escopo (não aditivas).
-- ============================================================================

CREATE OR REPLACE FUNCTION analise.sn(v text) RETURNS boolean
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$ SELECT coalesce(upper(trim(v)) = 'S', false) $$;
COMMENT ON FUNCTION analise.sn(text) IS 'Variável binária S/N do SETE -> boolean (NULL/vazio/N = false).';

-- ---------------------------------------------------------------------------
-- Leitura limpa
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW analise.v_alunos WITH (security_invoker = true) AS
SELECT ano_carga, codigo_cidade, lower(uf) AS uf, id_aluno,
       loc_latitude, loc_longitude,
       analise.sn(da_porteira) AS da_porteira, analise.sn(da_mataburro) AS da_mataburro,
       analise.sn(da_colchete) AS da_colchete, analise.sn(da_atoleiro) AS da_atoleiro,
       analise.sn(da_ponterustica) AS da_ponterustica,
       (analise.sn(da_porteira) OR analise.sn(da_mataburro) OR analise.sn(da_colchete)
        OR analise.sn(da_atoleiro) OR analise.sn(da_ponterustica)) AS tem_impedancia,
       CASE WHEN idade >= 0 THEN idade END AS idade,
       sexo, CASE sexo WHEN 1 THEN 'Masculino' WHEN 2 THEN 'Feminino' WHEN 3 THEN 'Não informado' END AS sexo_label,
       cor, CASE cor WHEN 1 THEN 'Branco' WHEN 2 THEN 'Preto' WHEN 3 THEN 'Pardo' WHEN 4 THEN 'Amarelo'
                     WHEN 5 THEN 'Indígena' WHEN 0 THEN 'Não declarada' END AS cor_label,
       grau_responsavel,
       CASE grau_responsavel WHEN -1 THEN 'Não informado' WHEN 0 THEN 'Pai, Mãe, Padrasto ou Madrasta'
                             WHEN 1 THEN 'Avô ou Avó' WHEN 2 THEN 'Irmão ou Irmã' WHEN 4 THEN 'Outro Parente'
       END AS grau_responsavel_label,
       analise.sn(def_caminhar) AS def_caminhar, analise.sn(def_ouvir) AS def_ouvir,
       analise.sn(def_enxergar) AS def_enxergar, analise.sn(def_mental) AS def_mental,
       (analise.sn(def_caminhar) OR analise.sn(def_ouvir) OR analise.sn(def_enxergar)
        OR analise.sn(def_mental)) AS tem_deficiencia,
       turno, CASE turno WHEN 1 THEN 'Manhã' WHEN 2 THEN 'Tarde' WHEN 3 THEN 'Noite'
                         WHEN 4 THEN 'Manhã e Tarde (Integral)' END AS turno_label,
       nivel, CASE nivel WHEN 1 THEN 'Infantil / Pré-escola' WHEN 2 THEN 'Fundamental' WHEN 3 THEN 'Médio'
                         WHEN 4 THEN 'Superior' WHEN 5 THEN 'Outro' END AS nivel_label,
       dt_criacao, dt_alteracao
FROM sete.alunos;

CREATE OR REPLACE VIEW analise.v_rotas WITH (security_invoker = true) AS
SELECT ano_carga, codigo_cidade, lower(uf) AS uf, id_rota, nome, km,
       analise.sn(da_porteira) AS da_porteira, analise.sn(da_mataburro) AS da_mataburro,
       analise.sn(da_colchete) AS da_colchete, analise.sn(da_atoleiro) AS da_atoleiro,
       analise.sn(da_ponterustica) AS da_ponterustica,
       (analise.sn(da_porteira) OR analise.sn(da_mataburro) OR analise.sn(da_colchete)
        OR analise.sn(da_atoleiro) OR analise.sn(da_ponterustica)) AS tem_impedancia,
       analise.sn(turno_matutino) AS turno_matutino, analise.sn(turno_vespertino) AS turno_vespertino,
       analise.sn(turno_noturno) AS turno_noturno,
       tem_shape,
       tempo,
       coalesce(tempo BETWEEN 1 AND 360, false) AS tempo_valido,   -- faixa operacional usada no tempo mediano
       tipo, CASE tipo WHEN 1 THEN 'Rodoviário' WHEN 2 THEN 'Aquaviário' WHEN 3 THEN 'Mista' END AS tipo_label,
       ativo
FROM sete.rotas;

CREATE OR REPLACE VIEW analise.v_veiculos WITH (security_invoker = true) AS
SELECT ano_carga, codigo_cidade, lower(uf) AS uf, id_veiculo, placa, renavam,
       ano AS ano_fabricacao,
       modo, CASE modo WHEN 0 THEN 'Rodoviário' WHEN 1 THEN 'Aquaviário' END AS modo_label,
       origem, CASE origem WHEN 1 THEN 'Veículo Próprio' WHEN 2 THEN 'Veículo Terceirizado' END AS origem_label,
       capacidade,
       coalesce(capacidade > 0 AND capacidade <= 150, false) AS capacidade_valida,  -- faixa usada no IUC
       km_inicial, km_atual,
       tipo, CASE tipo WHEN 1 THEN 'Ônibus' WHEN 2 THEN 'Micro-ônibus' WHEN 3 THEN 'Van' WHEN 4 THEN 'Kombi'
                       WHEN 5 THEN 'Caminhão' WHEN 6 THEN 'Caminhonete' WHEN 7 THEN 'Motocicleta'
                       WHEN 8 THEN 'Animal de tração' WHEN 9 THEN 'Lancha/Voadeira' WHEN 10 THEN 'Barco de Madeira'
                       WHEN 11 THEN 'Barco de alumínio' WHEN 12 THEN 'Canoa motorizada' WHEN 13 THEN 'Canoa a remo'
                       WHEN 14 THEN 'Bicicleta' WHEN 99 THEN 'Outro' END AS tipo_label,
       analise.sn(manutencao) AS manutencao,
       marca,
       ipva, dpvat, seguro_anual, consumo,
       tipo_combustivel,
       CASE upper(tipo_combustivel) WHEN 'G' THEN 'Gasolina' WHEN 'D' THEN 'Diesel' WHEN 'E' THEN 'Etanol'
                                    WHEN 'N' THEN 'Gás Natural' WHEN 'O' THEN 'Outro' END AS tipo_combustivel_label,
       numero_de_pneus, vida_util_do_pneu, preco, potencia_do_motor,
       modelo, CASE modelo WHEN 0 THEN 'Não se aplica' WHEN 1 THEN 'ORE 1' WHEN 2 THEN 'ORE 1 (4x4)'
                           WHEN 3 THEN 'ORE 2' WHEN 4 THEN 'ORE 3' WHEN 6 THEN 'ONUREA'
                           WHEN 7 THEN 'Lancha a Gasolina' WHEN 8 THEN 'Lancha a Diesel' END AS modelo_label,
       coalesce(modelo <> 0, false) AS caminho_da_escola,   -- modelo ≠ 0: veículo do programa Caminho da Escola
       ativo, dt_criacao, dt_alteracao
FROM sete.veiculos;

CREATE OR REPLACE VIEW analise.v_motoristas WITH (security_invoker = true) AS
SELECT ano_carga, codigo_cidade, lower(uf) AS uf,
       CASE WHEN idade >= 0 THEN idade END AS idade,
       sexo, CASE sexo WHEN 1 THEN 'Masculino' WHEN 2 THEN 'Feminino' WHEN 3 THEN 'Não informado' END AS sexo_label,
       analise.sn(tem_cnh_a) AS tem_cnh_a, analise.sn(tem_cnh_b) AS tem_cnh_b, analise.sn(tem_cnh_c) AS tem_cnh_c,
       analise.sn(tem_cnh_d) AS tem_cnh_d, analise.sn(tem_cnh_e) AS tem_cnh_e,
       analise.sn(turno_manha) AS turno_manha, analise.sn(turno_tarde) AS turno_tarde,
       analise.sn(turno_noite) AS turno_noite,
       data_validade_cnh,
       vinculo, CASE vinculo WHEN 1 THEN 'Servidor Efetivo' WHEN 2 THEN 'Servidor Comissionado'
                             WHEN 3 THEN 'Terceirizado' WHEN 4 THEN 'Outro' END AS vinculo_label,
       coalesce(vinculo BETWEEN 1 AND 4, false) AS vinculo_informado,
       coalesce(vinculo IN (1, 2, 3), false)    AS vinculo_formal,
       coalesce(vinculo = 4, false)             AS sem_vinculo,
       salario
FROM sete.motoristas;

CREATE OR REPLACE VIEW analise.v_monitores WITH (security_invoker = true) AS
SELECT ano_carga, codigo_cidade, lower(uf) AS uf,
       CASE WHEN idade >= 0 THEN idade END AS idade,
       sexo, CASE sexo WHEN 1 THEN 'Masculino' WHEN 2 THEN 'Feminino' WHEN 3 THEN 'Não informado' END AS sexo_label,
       analise.sn(turno_manha) AS turno_manha, analise.sn(turno_tarde) AS turno_tarde,
       analise.sn(turno_noite) AS turno_noite,
       vinculo, CASE vinculo WHEN 1 THEN 'Servidor Efetivo' WHEN 2 THEN 'Servidor Comissionado'
                             WHEN 3 THEN 'Terceirizado' WHEN 4 THEN 'Outro' END AS vinculo_label,
       coalesce(vinculo BETWEEN 1 AND 4, false) AS vinculo_informado,
       coalesce(vinculo IN (1, 2, 3), false)    AS vinculo_formal,
       coalesce(vinculo = 4, false)             AS sem_vinculo,
       salario, dt_criacao, dt_alteracao
FROM sete.monitores;

CREATE OR REPLACE VIEW analise.v_escolas WITH (security_invoker = true) AS
SELECT ano_carga, codigo_cidade, lower(uf) AS uf, id_escola, nome, mec_co_entidade, mec_co_uf, mec_co_municipio,
       mec_tp_dependencia,
       CASE mec_tp_dependencia WHEN 1 THEN 'Federal' WHEN 2 THEN 'Estadual' WHEN 3 THEN 'Municipal'
                               WHEN 4 THEN 'Privada/Conveniada' END AS dependencia_label,
       mec_tp_localizacao,
       CASE mec_tp_localizacao WHEN 1 THEN 'Área Urbana' WHEN 2 THEN 'Área Rural' WHEN 3 THEN 'Área de Assentamento'
                               WHEN 4 THEN 'Terra Indígena' WHEN 5 THEN 'Área Remanescente de Quilombo'
                               WHEN 6 THEN 'Outros Povos ou Comunidade Tradicionais' END AS localizacao_label,
       analise.sn(mec_in_regular) AS mec_in_regular, analise.sn(mec_in_eja) AS mec_in_eja,
       analise.sn(mec_in_profissionalizante) AS mec_in_profissionalizante,
       analise.sn(mec_in_especial_exclusiva) AS mec_in_especial_exclusiva,
       loc_latitude, loc_longitude, loc_cep,
       analise.sn(horario_matutino) AS horario_matutino, analise.sn(horario_vespertino) AS horario_vespertino,
       analise.sn(horario_noturno) AS horario_noturno, analise.sn(horario_integral) AS horario_integral,
       analise.sn(ensino_superior) AS ensino_superior, analise.sn(ensino_medio) AS ensino_medio,
       analise.sn(ensino_fundamental) AS ensino_fundamental, analise.sn(ensino_pre_escola) AS ensino_pre_escola,
       informacoes_adicionais, nome_unidade_anexa, tipo_unidade,
       dt_criacao, dt_alteracao
FROM sete.escolas;

-- Censo agregado por município (QT_TRANSP_PUBLICO = demanda declarada de transporte público)
CREATE OR REPLACE VIEW analise.v_censo_municipio WITH (security_invoker = true) AS
SELECT ano_carga, co_municipio::integer AS codigo_cidade, lower(sg_uf) AS uf,
       count(*)                     AS escolas,
       sum(qt_mat_bas)              AS matriculas_basica,
       sum(qt_transp_publico)       AS transp_publico,
       sum(qt_transp_resp_est)      AS transp_resp_estadual,
       sum(qt_transp_resp_mun)      AS transp_resp_municipal
FROM censo.matricula
GROUP BY ano_carga, co_municipio, lower(sg_uf);

-- ---------------------------------------------------------------------------
-- Base municipal (aditiva). ano_carga = ano da carga do SETE; o Censo entra pelo
-- pareamento de ref.cargas. Chave: (ano_carga, codigo_cidade, uf).
-- ---------------------------------------------------------------------------

CREATE MATERIALIZED VIEW IF NOT EXISTS analise.mv_base_municipio AS
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
           coalesce(sum(coalesce(km, 0)) FILTER (WHERE tem_shape), 0) AS km_geo
    FROM analise.v_rotas GROUP BY 1, 2, 3),
vei AS (
    SELECT ano_carga, codigo_cidade, uf,
           count(*)                                   AS tot_veic,
           count(*) FILTER (WHERE origem = 1)         AS vp,
           count(*) FILTER (WHERE origem = 2)         AS vt,
           count(*) FILTER (WHERE capacidade_valida)  AS n_veic_validos,
           coalesce(sum(capacidade) FILTER (WHERE capacidade_valida), 0) AS cap_sum,
           count(*) FILTER (WHERE caminho_da_escola)  AS ce_veic_sete
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
       coalesce(cen.demanda_censo, 0) AS demanda_censo
FROM chaves k
LEFT JOIN al  USING (ano_carga, codigo_cidade, uf)
LEFT JOIN rot USING (ano_carga, codigo_cidade, uf)
LEFT JOIN vei USING (ano_carga, codigo_cidade, uf)
LEFT JOIN mot USING (ano_carga, codigo_cidade, uf)
LEFT JOIN mon USING (ano_carga, codigo_cidade, uf)
LEFT JOIN ate USING (ano_carga, codigo_cidade, uf)
LEFT JOIN esc USING (ano_carga, codigo_cidade, uf)
LEFT JOIN cen USING (ano_carga, codigo_cidade, uf)
WITH NO DATA;

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_base_municipio ON analise.mv_base_municipio (ano_carga, codigo_cidade, uf);
COMMENT ON MATERIALIZED VIEW analise.mv_base_municipio IS
  'Contagens e somas aditivas por município (SETE + Censo pareado). Atualizar com pnite_meta.atualizar_indicadores().';

-- Tempo das rotas (faixa 1–360 min): mediana e média por município, UF, região e Brasil.
CREATE MATERIALIZED VIEW IF NOT EXISTS analise.mv_tempo_rotas AS
SELECT r.ano_carga,
       CASE WHEN GROUPING(r.codigo_cidade) = 0 THEN 'municipio'
            WHEN GROUPING(r.uf) = 0 THEN 'estado'
            WHEN GROUPING(u.regiao) = 0 THEN 'regiao'
            ELSE 'nacional' END AS nivel,
       CASE WHEN GROUPING(r.codigo_cidade) = 0 THEN r.codigo_cidade::text
            WHEN GROUPING(r.uf) = 0 THEN r.uf
            WHEN GROUPING(u.regiao) = 0 THEN u.regiao
            ELSE 'nacional' END AS chave,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY r.tempo)::numeric, 1) AS tempo_mediano,
       round(avg(r.tempo), 1) AS tempo_medio
FROM analise.v_rotas r
JOIN ref.uf u ON u.sigla = r.uf
WHERE r.tempo_valido
GROUP BY GROUPING SETS ((r.ano_carga, r.codigo_cidade, r.uf, u.regiao), (r.ano_carga, r.uf, u.regiao),
                        (r.ano_carga, u.regiao), (r.ano_carga))
WITH NO DATA;

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_tempo_rotas ON analise.mv_tempo_rotas (ano_carga, nivel, chave);
