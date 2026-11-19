-- ============================================================================
-- PNITE — 0022: várias cargas do SETE no mesmo ano (maio/2026 e novembro/2026)
-- ----------------------------------------------------------------------------
-- Até aqui cada carga era identificada só pelo ano (ano_carga = 2026). Para manter a carga
-- atual (extraída em maio de 2026) ao lado da nova (novembro de 2026) e compará-las:
--   * coluna carga (AAAAMM da data de referência) em todas as tabelas do SETE, em
--     ref.raw_referencia, ref.detalhes_scripts e pnite_meta.cargas_log. A carga existente
--     passa a ser 202605 ("Maio/2026"). ano_carga continua sendo o ano de referência,
--     usado no cálculo da idade da frota;
--   * ref.cargas passa a ter uma linha por carga (chave carga), com rótulo, data de
--     referência e o Censo pareado;
--   * todas as views de análise e da API passam a ser chaveadas por carga, e as views
--     públicas ganham a coluna carga (filtro da interface: carga=eq.202605);
--   * public.cargas_sete lista as cargas com dados (rótulo, data, atual = a mais recente);
--   * nos níveis UF, região e Brasil, os valores que vinham só de ref.raw_referencia
--     (planilhas consolidadas da carga de maio) passam a ter um equivalente calculado dos
--     dados brutos (analise.referencia_calculada), usado quando a carga não tem planilha.
--     A referência legada continua prevalecendo onde existe, então a carga de maio não muda.
--     Conferido: PVPCE, IMFP, IMFT, MIFCE, MEDATE, PATM e PATE calculados são iguais aos
--     legados; o ATE de UF/Brasil usa esc_at, que no legado (27.751 escolas) difere da
--     contagem do SETE (29.525) — divergência registrada para decisão.
-- Índices das tabelas brutas: migração 0023.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Dependentes que serão recriados por carga
-- ---------------------------------------------------------------------------
DROP VIEW public.indicadores;
DROP MATERIALIZED VIEW public.sete_municipios;
DROP MATERIALIZED VIEW analise.mv_sete_municipio;
DROP MATERIALIZED VIEW public.indicadores_municipio_complemento;
DROP MATERIALIZED VIEW analise.mv_complemento_municipio;
DROP MATERIALIZED VIEW public.indicadores_nacional;
DROP MATERIALIZED VIEW public.indicadores_regiao;
DROP MATERIALIZED VIEW public.indicadores_estado;
DROP MATERIALIZED VIEW public.indicadores_municipio;
DROP MATERIALIZED VIEW analise.mv_base_municipio;
DROP MATERIALIZED VIEW analise.mv_rotas_estatisticas;
DROP MATERIALIZED VIEW analise.mv_tempo_rotas;
DROP MATERIALIZED VIEW public.rotas_tracado;

-- ---------------------------------------------------------------------------
-- 2. Registro das cargas
-- ---------------------------------------------------------------------------
ALTER TABLE ref.cargas ADD COLUMN carga integer, ADD COLUMN rotulo text, ADD COLUMN data_referencia date;
UPDATE ref.cargas SET carga = 202605, rotulo = 'Maio/2026', data_referencia = DATE '2026-05-01',
                      descricao = 'SETE extraído em maio de 2026 × Censo Escolar 2025'
 WHERE ano_carga_sete = 2026;
ALTER TABLE ref.cargas DROP CONSTRAINT cargas_pkey;
ALTER TABLE ref.cargas ALTER COLUMN carga SET NOT NULL, ALTER COLUMN rotulo SET NOT NULL,
                       ALTER COLUMN data_referencia SET NOT NULL;
ALTER TABLE ref.cargas ADD PRIMARY KEY (carga);
ALTER TABLE ref.cargas ADD CONSTRAINT cargas_carga_aaaamm
    CHECK (carga % 100 BETWEEN 1 AND 12 AND carga / 100 = ano_carga_sete
           AND data_referencia = make_date(carga / 100, carga % 100, 1));
COMMENT ON TABLE ref.cargas IS 'Cargas do SETE: uma linha por extração (carga AAAAMM), com rótulo, data de referência e o Censo pareado.';
COMMENT ON COLUMN ref.cargas.carga IS 'Identificador da carga: AAAAMM da data de referência (ex.: 202605 = maio de 2026).';
COMMENT ON COLUMN ref.cargas.rotulo IS 'Rótulo exibido na interface (ex.: Maio/2026).';
COMMENT ON COLUMN ref.cargas.data_referencia IS 'Primeiro dia do mês de referência da extração do SETE.';
COMMENT ON COLUMN ref.cargas.ano_carga_sete IS 'Ano de referência da carga (ano_carga das tabelas do SETE; base da idade da frota).';

-- ---------------------------------------------------------------------------
-- 3. Coluna carga nas tabelas da carga (linhas existentes = 202605)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pg_temp.coluna_carga(p_tabela text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_nome text := replace(split_part(p_tabela, '.', 2), '"', '');
BEGIN
    EXECUTE format('ALTER TABLE %s ADD COLUMN carga integer NOT NULL DEFAULT 202605', p_tabela);
    EXECUTE format('ALTER TABLE %s ALTER COLUMN carga DROP DEFAULT', p_tabela);
    EXECUTE format('ALTER TABLE %s ADD CONSTRAINT %I FOREIGN KEY (carga) REFERENCES ref.cargas (carga) NOT VALID',
                   p_tabela, v_nome || '_carga_fk');
    EXECUTE format('COMMENT ON COLUMN %s.carga IS %L', p_tabela,
                   'Carga do SETE (AAAAMM da data de referência; ver ref.cargas). Com o código do município e o id, forma a chave lógica.');
END $$;

SELECT pg_temp.coluna_carga(t) FROM unnest(ARRAY[
    'sete.alunos', 'sete.escolas', 'sete.rotas', 'sete.veiculos', 'sete.monitores', 'sete.motoristas',
    'sete.normas', 'sete.fornecedores', 'sete.ordem_servico', 'sete.escola_tem_aluno', 'sete.rota_atende_aluno',
    'sete.rota_passa_por_escolas', 'sete.rota_possui_veiculo', 'sete.rota_dirigida_por_motorista',
    'sete.rota_shape', 'ref.raw_referencia', 'ref.detalhes_scripts']) AS t;

ALTER TABLE ref.raw_referencia DROP CONSTRAINT raw_referencia_pkey, ADD PRIMARY KEY (carga, chave);
ALTER TABLE ref.detalhes_scripts DROP CONSTRAINT detalhes_scripts_pkey, ADD PRIMARY KEY (carga, chave, script);
COMMENT ON TABLE ref.raw_referencia IS 'Valores de referência por escopo das planilhas consolidadas (só a carga de maio/2026); prevalecem sobre analise.referencia_calculada.';

ALTER TABLE pnite_meta.cargas_log ADD COLUMN carga integer;
UPDATE pnite_meta.cargas_log SET carga = 202605 WHERE tabela LIKE 'sete.%' AND ano_carga = 2026;
COMMENT ON COLUMN pnite_meta.cargas_log.carga IS 'Carga do SETE (AAAAMM); NULL para o Censo.';

-- ---------------------------------------------------------------------------
-- 4. Views de leitura limpa: + carga (mesmas regras da 0014)
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
       dt_criacao, dt_alteracao,
       carga
FROM sete.alunos
WHERE codigo_cidade BETWEEN 1000000 AND 9999999;

CREATE OR REPLACE VIEW analise.v_rotas WITH (security_invoker = true) AS
SELECT ano_carga, codigo_cidade, lower(uf) AS uf, id_rota, nome,
       CASE WHEN km <= 2000 THEN km END AS km,                       -- acima de 2.000 km: erro de cadastro
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
       ativo,
       km AS km_informado,                                           -- valor original do cadastro
       carga
FROM sete.rotas
WHERE codigo_cidade BETWEEN 1000000 AND 9999999;

CREATE OR REPLACE VIEW analise.v_veiculos WITH (security_invoker = true) AS
SELECT ano_carga, codigo_cidade, lower(uf) AS uf, id_veiculo, placa, renavam,
       ano AS ano_fabricacao,
       modo, CASE modo WHEN 0 THEN 'Rodoviário' WHEN 1 THEN 'Aquaviário' END AS modo_label,
       origem, CASE origem WHEN 1 THEN 'Veículo Próprio' WHEN 2 THEN 'Veículo Terceirizado' END AS origem_label,
       capacidade,
       coalesce(capacidade > 0 AND capacidade <= 100, false) AS capacidade_valida,  -- 1 a 100 lugares: capacidade média e IUC
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
       ativo, dt_criacao, dt_alteracao,
       carga
FROM sete.veiculos
WHERE codigo_cidade BETWEEN 1000000 AND 9999999;

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
       salario,
       carga
FROM sete.motoristas
WHERE codigo_cidade BETWEEN 1000000 AND 9999999;

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
       salario, dt_criacao, dt_alteracao,
       carga
FROM sete.monitores
WHERE codigo_cidade BETWEEN 1000000 AND 9999999;

CREATE OR REPLACE VIEW analise.v_escolas WITH (security_invoker = true) AS
SELECT ano_carga, codigo_cidade, lower(uf::text) AS uf, id_escola, nome,
       mec_co_entidade, mec_co_uf, mec_co_municipio, mec_tp_dependencia,
       CASE mec_tp_dependencia WHEN 1 THEN 'Federal' WHEN 2 THEN 'Estadual' WHEN 3 THEN 'Municipal'
                               WHEN 4 THEN 'Privada/Conveniada' END AS dependencia_label,
       mec_tp_localizacao,
       CASE mec_tp_localizacao WHEN 1 THEN 'Área Urbana' WHEN 2 THEN 'Área Rural' WHEN 3 THEN 'Área de Assentamento'
                               WHEN 4 THEN 'Terra Indígena' WHEN 5 THEN 'Área Remanescente de Quilombo'
                               WHEN 6 THEN 'Outros Povos ou Comunidade Tradicionais' END AS localizacao_label,
       analise.sn(mec_in_regular::text) AS mec_in_regular, analise.sn(mec_in_eja::text) AS mec_in_eja,
       analise.sn(mec_in_profissionalizante::text) AS mec_in_profissionalizante,
       analise.sn(mec_in_especial_exclusiva::text) AS mec_in_especial_exclusiva,
       loc_latitude, loc_longitude, loc_cep,
       analise.sn(horario_matutino::text) AS horario_matutino, analise.sn(horario_vespertino::text) AS horario_vespertino,
       analise.sn(horario_noturno::text) AS horario_noturno, analise.sn(horario_integral::text) AS horario_integral,
       analise.sn(ensino_superior::text) AS ensino_superior, analise.sn(ensino_medio::text) AS ensino_medio,
       analise.sn(ensino_fundamental::text) AS ensino_fundamental, analise.sn(ensino_pre_escola::text) AS ensino_pre_escola,
       informacoes_adicionais, nome_unidade_anexa, tipo_unidade, dt_criacao, dt_alteracao,
       carga
FROM sete.escolas;

-- Censo por município (0011) + escolas com transporte público (referência calculada do ATE/MEDATE)
CREATE OR REPLACE VIEW analise.v_censo_municipio WITH (security_invoker = true) AS
SELECT c.ano_carga, c.co_municipio::integer AS codigo_cidade,
       coalesce(lower(nullif(trim(c.sg_uf), '')), m.uf) AS uf,
       count(*) AS escolas,
       sum(c.qt_mat_bas) AS matriculas_basica,
       sum(c.qt_transp_publico) AS transp_publico,
       sum(c.qt_transp_resp_est) AS transp_resp_estadual,
       sum(c.qt_transp_resp_mun) AS transp_resp_municipal,
       count(*) FILTER (WHERE c.qt_transp_publico > 0) AS escolas_transp
FROM censo.matricula c
LEFT JOIN ref.municipios m ON m.codigo_ibge = c.co_municipio
GROUP BY c.ano_carga, c.co_municipio, coalesce(lower(nullif(trim(c.sg_uf), '')), m.uf);

-- ---------------------------------------------------------------------------
-- 5. Estatísticas não aditivas por nível (tempo, km, medianas de referência)
-- ---------------------------------------------------------------------------
CREATE MATERIALIZED VIEW analise.mv_tempo_rotas AS
SELECT carga, 'municipio'::text AS nivel, codigo_cidade::text AS chave,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY tempo)::numeric, 1) AS tempo_mediano,
       round(avg(tempo), 1) AS tempo_medio
FROM analise.v_rotas WHERE tempo_valido
GROUP BY carga, codigo_cidade
UNION ALL
SELECT carga, 'estado', uf,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY tempo)::numeric, 1), round(avg(tempo), 1)
FROM analise.v_rotas WHERE tempo_valido
GROUP BY carga, uf
UNION ALL
SELECT r.carga, 'regiao', u.regiao,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY r.tempo)::numeric, 1), round(avg(r.tempo), 1)
FROM analise.v_rotas r JOIN ref.uf u ON u.sigla = r.uf
WHERE r.tempo_valido
GROUP BY r.carga, u.regiao
UNION ALL
SELECT carga, 'nacional', 'nacional',
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY tempo)::numeric, 1), round(avg(tempo), 1)
FROM analise.v_rotas WHERE tempo_valido
GROUP BY carga;

CREATE UNIQUE INDEX idx_mv_tempo_rotas ON analise.mv_tempo_rotas (carga, nivel, chave);
COMMENT ON MATERIALIZED VIEW analise.mv_tempo_rotas IS 'Mediana e média do tempo das rotas válidas (1 a 360 min) por carga e nível.';

CREATE MATERIALIZED VIEW analise.mv_rotas_estatisticas AS
WITH r AS (
    SELECT v.carga, v.codigo_cidade, v.uf, u.regiao,
           CASE WHEN v.km > 0 THEN v.km END AS km,
           CASE WHEN v.tempo_valido THEN v.tempo END AS tempo
    FROM analise.v_rotas v JOIN ref.uf u ON u.sigla = v.uf),
g AS (
    SELECT carga,
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
    GROUP BY GROUPING SETS ((carga, codigo_cidade, uf, regiao), (carga, uf, regiao), (carga, regiao), (carga)))
SELECT carga, nivel, chave,
       jsonb_strip_nulls(jsonb_build_object(
         'km_mediana', round(km_p[2]::numeric, 1), 'km_p5', round(km_p[1]::numeric, 1),
         'km_p95', round(km_p[3]::numeric, 1), 'km_min', km_min, 'km_max', km_max,
         'tempo_p5', round(tempo_p[1]::numeric, 1), 'tempo_p95', round(tempo_p[2]::numeric, 1),
         'tempo_min', tempo_min, 'tempo_max', tempo_max)) AS estat
FROM g;

CREATE UNIQUE INDEX idx_mv_rotas_estatisticas ON analise.mv_rotas_estatisticas (carga, nivel, chave);
COMMENT ON MATERIALIZED VIEW analise.mv_rotas_estatisticas IS
  'MQT: mediana, P5, P95, mínimo e máximo do km (0 < km ≤ 2.000) e P5, P95, mínimo e máximo do tempo (1 a 360 min) das rotas, por carga e nível.';

-- Medianas de referência em UF, região e Brasil (MIFCE da frota do SETE e MEDATE do Censo pareado)
CREATE MATERIALIZED VIEW analise.mv_medianas_nivel AS
WITH fro AS (
    SELECT v.carga, v.uf, u.regiao, (v.ano_carga - v.ano_fabricacao) AS idade
    FROM analise.v_veiculos v JOIN ref.uf u ON u.sigla = v.uf
    WHERE v.caminho_da_escola AND v.ano_fabricacao BETWEEN 1930 AND v.ano_carga),
cen AS (
    SELECT c.carga, x.uf, u.regiao, x.qt
    FROM (SELECT m.ano_carga, coalesce(lower(nullif(trim(m.sg_uf), '')), mu.uf) AS uf, m.qt_transp_publico AS qt
          FROM censo.matricula m LEFT JOIN ref.municipios mu ON mu.codigo_ibge = m.co_municipio
          WHERE m.qt_transp_publico > 0) x
    JOIN ref.cargas c ON c.ano_carga_censo = x.ano_carga
    JOIN ref.uf u ON u.sigla = x.uf),
f AS (
    SELECT carga,
           CASE WHEN GROUPING(uf) = 0 THEN 'estado' WHEN GROUPING(regiao) = 0 THEN 'regiao' ELSE 'nacional' END AS nivel,
           CASE WHEN GROUPING(uf) = 0 THEN uf WHEN GROUPING(regiao) = 0 THEN regiao ELSE 'nacional' END AS chave,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY idade) AS mifce
    FROM fro GROUP BY GROUPING SETS ((carga, uf, regiao), (carga, regiao), (carga))),
e AS (
    SELECT carga,
           CASE WHEN GROUPING(uf) = 0 THEN 'estado' WHEN GROUPING(regiao) = 0 THEN 'regiao' ELSE 'nacional' END AS nivel,
           CASE WHEN GROUPING(uf) = 0 THEN uf WHEN GROUPING(regiao) = 0 THEN regiao ELSE 'nacional' END AS chave,
           ceil(percentile_cont(0.5) WITHIN GROUP (ORDER BY qt)) AS medate
    FROM cen GROUP BY GROUPING SETS ((carga, uf, regiao), (carga, regiao), (carga)))
SELECT coalesce(f.carga, e.carga) AS carga, coalesce(f.nivel, e.nivel) AS nivel, coalesce(f.chave, e.chave) AS chave,
       f.mifce::numeric AS mifce, e.medate::numeric AS medate
FROM f FULL JOIN e ON e.carga = f.carga AND e.nivel = f.nivel AND e.chave = f.chave;

CREATE UNIQUE INDEX idx_mv_medianas_nivel ON analise.mv_medianas_nivel (carga, nivel, chave);
COMMENT ON MATERIALIZED VIEW analise.mv_medianas_nivel IS
  'Medianas de referência por carga em UF, região e Brasil: MIFCE (idade do Caminho da Escola) e MEDATE (teto da mediana de transportados por escola no Censo pareado).';

-- ---------------------------------------------------------------------------
-- 6. Base municipal aditiva (0021) por carga + contadores da referência calculada
-- ---------------------------------------------------------------------------
CREATE MATERIALIZED VIEW analise.mv_base_municipio AS
WITH
al AS (
    SELECT carga, codigo_cidade, uf,
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
    SELECT carga, codigo_cidade, uf,
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
    SELECT carga, codigo_cidade, uf,
           count(*)                                   AS tot_veic,
           count(*) FILTER (WHERE origem = 1)         AS vp,
           count(*) FILTER (WHERE origem = 2)         AS vt,
           count(*) FILTER (WHERE capacidade_valida)  AS n_veic_validos,
           coalesce(sum(capacidade) FILTER (WHERE capacidade_valida), 0) AS cap_sum,
           count(*) FILTER (WHERE caminho_da_escola)  AS ce_veic_sete,
           -- PAFI: idade = ano de carga − ano de fabricação (1930 até o ano de carga)
           count(*) FILTER (WHERE ano_fabricacao BETWEEN 1930 AND ano_carga) AS veic_ano_valido,
           count(*) FILTER (WHERE ano_fabricacao BETWEEN 1930 AND ano_carga
                              AND ano_carga - ano_fabricacao <= analise.vida_util_frota_anos()) AS veic_vida_util,
           -- IMFP / IMFT de referência (UF, região e Brasil sem planilha consolidada)
           coalesce(sum(ano_carga - ano_fabricacao) FILTER (WHERE origem = 1 AND ano_fabricacao BETWEEN 1930 AND ano_carga), 0) AS idade_prop_soma,
           count(*) FILTER (WHERE origem = 1 AND ano_fabricacao BETWEEN 1930 AND ano_carga) AS idade_prop_n,
           coalesce(sum(ano_carga - ano_fabricacao) FILTER (WHERE origem = 2 AND ano_fabricacao BETWEEN 1930 AND ano_carga), 0) AS idade_terc_soma,
           count(*) FILTER (WHERE origem = 2 AND ano_fabricacao BETWEEN 1930 AND ano_carga) AS idade_terc_n
    FROM analise.v_veiculos GROUP BY 1, 2, 3),
mot AS (
    SELECT carga, codigo_cidade, uf,
           count(*) FILTER (WHERE vinculo_informado)  AS tot_mot_info,
           count(*) FILTER (WHERE sem_vinculo)        AS mot_sem_vinculo,
           count(*) FILTER (WHERE vinculo_formal)     AS mot_cv
    FROM analise.v_motoristas GROUP BY 1, 2, 3),
mon AS (
    SELECT carga, codigo_cidade, uf,
           count(*) FILTER (WHERE vinculo_informado)  AS tot_mon,
           count(*) FILTER (WHERE sem_vinculo)        AS mon_sem_vinculo,
           count(*) FILTER (WHERE vinculo_formal)     AS mon_cv
    FROM analise.v_monitores GROUP BY 1, 2, 3),
-- Alunos transportados: ids distintos por município (o id do SETE não é global)
ate AS (
    SELECT carga, codigo_cidade, lower(uf) AS uf, count(DISTINCT id_aluno) AS al_transp_sete
    FROM sete.rota_atende_aluno GROUP BY 1, 2, 3),
-- Alunos transportados com impedância (PARI) e em rotas aquaviárias (PAIH): impedância marcada
-- na rota OU no cadastro do aluno. No PAIH só contam as rotas aquaviárias (tipo 2) do aluno.
hid AS (
    SELECT carga, codigo_cidade, uf,
           count(*) FILTER (WHERE imp)       AS al_transp_imp,
           count(*) FILTER (WHERE hidro)     AS al_hidro,
           count(*) FILTER (WHERE hidro_imp) AS al_hidro_imp
    FROM (
        SELECT a.carga, a.codigo_cidade, r.uf, a.id_aluno,
               bool_or(r.tem_impedancia OR coalesce(v.tem_impedancia, false))               AS imp,
               bool_or(r.tipo = 2)                                                          AS hidro,
               bool_or(r.tipo = 2 AND (r.tem_impedancia OR coalesce(v.tem_impedancia, false))) AS hidro_imp
        FROM sete.rota_atende_aluno a
        JOIN analise.v_rotas r ON r.carga = a.carga AND r.codigo_cidade = a.codigo_cidade
                              AND r.id_rota = a.id_rota
        LEFT JOIN analise.v_alunos v ON v.carga = a.carga AND v.codigo_cidade = a.codigo_cidade
                                    AND v.id_aluno = a.id_aluno
        GROUP BY 1, 2, 3, 4) x
    GROUP BY 1, 2, 3),
esc AS (
    SELECT carga, codigo_cidade, lower(uf) AS uf, count(DISTINCT id_escola) AS esc_at_sete
    FROM sete.rota_passa_por_escolas GROUP BY 1, 2, 3),
-- Censo pareado a cada carga (ref.cargas)
cen AS (
    SELECT c.carga, m.codigo_cidade, m.uf, m.transp_publico AS demanda_censo,
           m.transp_resp_municipal AS censo_mun, m.transp_resp_estadual AS censo_est,
           m.escolas_transp AS censo_esc_transp
    FROM analise.v_censo_municipio m JOIN ref.cargas c ON c.ano_carga_censo = m.ano_carga),
chaves AS (
    SELECT carga, codigo_cidade, uf FROM al  UNION SELECT carga, codigo_cidade, uf FROM rot
    UNION SELECT carga, codigo_cidade, uf FROM vei UNION SELECT carga, codigo_cidade, uf FROM mot
    UNION SELECT carga, codigo_cidade, uf FROM mon UNION SELECT carga, codigo_cidade, uf FROM ate
    UNION SELECT carga, codigo_cidade, uf FROM esc UNION SELECT carga, codigo_cidade, uf FROM cen)
SELECT rc.ano_carga_sete AS ano_carga, k.carga, k.codigo_cidade, k.uf,
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
       coalesce(hid.al_hidro, 0) AS al_hidro, coalesce(hid.al_hidro_imp, 0) AS al_hidro_imp,
       coalesce(hid.al_transp_imp, 0) AS al_transp_imp,
       coalesce(cen.censo_mun, 0) AS censo_mun, coalesce(cen.censo_est, 0) AS censo_est,
       coalesce(cen.censo_esc_transp, 0) AS censo_esc_transp,
       coalesce(vei.idade_prop_soma, 0) AS idade_prop_soma, coalesce(vei.idade_prop_n, 0) AS idade_prop_n,
       coalesce(vei.idade_terc_soma, 0) AS idade_terc_soma, coalesce(vei.idade_terc_n, 0) AS idade_terc_n
FROM chaves k
LEFT JOIN al  USING (carga, codigo_cidade, uf)
LEFT JOIN rot USING (carga, codigo_cidade, uf)
LEFT JOIN vei USING (carga, codigo_cidade, uf)
LEFT JOIN mot USING (carga, codigo_cidade, uf)
LEFT JOIN mon USING (carga, codigo_cidade, uf)
LEFT JOIN ate USING (carga, codigo_cidade, uf)
LEFT JOIN hid USING (carga, codigo_cidade, uf)
LEFT JOIN esc USING (carga, codigo_cidade, uf)
LEFT JOIN cen USING (carga, codigo_cidade, uf)
JOIN ref.cargas rc ON rc.carga = k.carga;

CREATE UNIQUE INDEX idx_mv_base_municipio ON analise.mv_base_municipio (carga, codigo_cidade, uf);
COMMENT ON MATERIALIZED VIEW analise.mv_base_municipio IS
  'Contagens e somas aditivas por carga e município (SETE + Censo pareado). Atualizar com pnite_meta.atualizar_indicadores().';

-- Equivalentes calculados dos valores de ref.raw_referencia (UF, região e Brasil). A referência
-- legada da carga, quando existe, prevalece (aplicada depois no raw).
CREATE OR REPLACE FUNCTION analise.referencia_calculada(c jsonb, mifce numeric, medate numeric) RETURNS jsonb
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT jsonb_strip_nulls(jsonb_build_object(
    'ce_veic',              c -> 'ce_veic_sete',
    'esc_at',               c -> 'esc_at_sete',
    'cs_tmun',              c -> 'censo_mun',
    'cs_test',              c -> 'censo_est',
    'cs_transp',            analise.num(c, 'censo_mun') + analise.num(c, 'censo_est'),
    'cs_escolas_atendidas', c -> 'censo_esc_transp',
    'medate_n',             c -> 'censo_esc_transp',
    'medate_val',           medate,
    'imfp', CASE WHEN analise.num(c, 'idade_prop_n') > 0
                 THEN analise.round_par((analise.num(c, 'idade_prop_soma') / analise.num(c, 'idade_prop_n'))::float8, 1) END,
    'imft', CASE WHEN analise.num(c, 'idade_terc_n') > 0
                 THEN analise.round_par((analise.num(c, 'idade_terc_soma') / analise.num(c, 'idade_terc_n'))::float8, 1) END,
    'mifce', mifce))
$$;
COMMENT ON FUNCTION analise.referencia_calculada(jsonb, numeric, numeric) IS
  'Valores de referência (ce_veic, esc_at, cs_*, medate_*, imfp, imft, mifce) calculados dos contadores somados de um nível; usados nas cargas sem planilha consolidada.';

-- ---------------------------------------------------------------------------
-- 7. Indicadores por nível (0021) por carga
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
       ON t.carga = b.carga AND t.nivel = 'municipio' AND t.chave = b.codigo_cidade::text
LEFT JOIN analise.mv_rotas_estatisticas e
       ON e.carga = b.carga AND e.nivel = 'municipio' AND e.chave = b.codigo_cidade::text
CROSS JOIN LATERAL (
    SELECT analise.montar_raw(to_jsonb(b) - ARRAY['ano_carga', 'carga', 'codigo_cidade', 'uf'],
                              t.tempo_mediano, t.tempo_medio)
           || coalesce(e.estat, '{}'::jsonb) AS raw
) r;

CREATE UNIQUE INDEX idx_indicadores_municipio ON public.indicadores_municipio (carga, codigo_cidade, uf);
CREATE INDEX idx_indicadores_municipio_uf ON public.indicadores_municipio (carga, uf);
COMMENT ON MATERIALIZED VIEW public.indicadores_municipio IS
  'PNITE — indicadores por carga e município. Ex.: /rest/v1/indicadores_municipio?carga=eq.202605&uf=eq.go';

CREATE MATERIALIZED VIEW public.indicadores_estado AS
WITH s AS (
    SELECT ano_carga, carga, uf,
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
           sum(al_hidro) AS al_hidro, sum(al_hidro_imp) AS al_hidro_imp, sum(al_transp_imp) AS al_transp_imp,
           sum(censo_mun) AS censo_mun, sum(censo_est) AS censo_est, sum(censo_esc_transp) AS censo_esc_transp,
           sum(idade_prop_soma) AS idade_prop_soma, sum(idade_prop_n) AS idade_prop_n,
           sum(idade_terc_soma) AS idade_terc_soma, sum(idade_terc_n) AS idade_terc_n
    FROM public.indicadores_municipio
    GROUP BY ano_carga, carga, uf
)
SELECT s.*,
       u.nome, u.regiao,
       u.nome AS label,
       t.tempo_mediano, t.tempo_medio,
       r.raw,
       analise.calcular_indicadores(r.raw, u.nome) AS indicadores,
       (SELECT jsonb_object_agg(d.script, d.dados) FROM ref.detalhes_scripts d
         WHERE d.carga = s.carga AND d.chave = s.uf) AS detalhes,
       now() AS atualizado_em
FROM s
JOIN ref.uf u ON u.sigla = s.uf
LEFT JOIN analise.mv_tempo_rotas t ON t.carga = s.carga AND t.nivel = 'estado' AND t.chave = s.uf
LEFT JOIN analise.mv_rotas_estatisticas e ON e.carga = s.carga AND e.nivel = 'estado' AND e.chave = s.uf
LEFT JOIN analise.mv_medianas_nivel md ON md.carga = s.carga AND md.nivel = 'estado' AND md.chave = s.uf
LEFT JOIN ref.raw_referencia rr ON rr.carga = s.carga AND rr.chave = s.uf
CROSS JOIN LATERAL (
    -- referência calculada < planilha consolidada da carga (quando houver) < contadores calculados
    SELECT analise.referencia_calculada(to_jsonb(s), md.mifce, md.medate)
           || coalesce(rr.dados, '{}'::jsonb)
           || analise.montar_raw(to_jsonb(s) - ARRAY['ano_carga', 'carga', 'uf'], t.tempo_mediano, t.tempo_medio)
           || coalesce(e.estat, '{}'::jsonb) AS raw
) r;

CREATE UNIQUE INDEX idx_indicadores_estado ON public.indicadores_estado (carga, uf);
COMMENT ON MATERIALIZED VIEW public.indicadores_estado IS
  'PNITE — indicadores por carga e UF (soma dos municípios). Ex.: /rest/v1/indicadores_estado?carga=eq.202605&uf=eq.go';

CREATE MATERIALIZED VIEW public.indicadores_regiao AS
WITH s AS (
    SELECT ano_carga, carga, regiao,
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
           sum(al_hidro) AS al_hidro, sum(al_hidro_imp) AS al_hidro_imp, sum(al_transp_imp) AS al_transp_imp,
           sum(censo_mun) AS censo_mun, sum(censo_est) AS censo_est, sum(censo_esc_transp) AS censo_esc_transp,
           sum(idade_prop_soma) AS idade_prop_soma, sum(idade_prop_n) AS idade_prop_n,
           sum(idade_terc_soma) AS idade_terc_soma, sum(idade_terc_n) AS idade_terc_n
    FROM public.indicadores_estado
    GROUP BY ano_carga, carga, regiao
)
SELECT s.*,
       rg.regiao_label AS label,
       t.tempo_mediano, t.tempo_medio,
       r.raw,
       analise.calcular_indicadores(r.raw, rg.regiao_label) AS indicadores,
       now() AS atualizado_em
FROM s
JOIN (SELECT DISTINCT regiao, regiao_label FROM ref.uf) rg ON rg.regiao = s.regiao
LEFT JOIN analise.mv_tempo_rotas t ON t.carga = s.carga AND t.nivel = 'regiao' AND t.chave = s.regiao
LEFT JOIN analise.mv_rotas_estatisticas e ON e.carga = s.carga AND e.nivel = 'regiao' AND e.chave = s.regiao
LEFT JOIN analise.mv_medianas_nivel md ON md.carga = s.carga AND md.nivel = 'regiao' AND md.chave = s.regiao
LEFT JOIN ref.raw_referencia rr ON rr.carga = s.carga AND rr.chave = s.regiao
CROSS JOIN LATERAL (
    SELECT analise.referencia_calculada(to_jsonb(s), md.mifce, md.medate)
           || coalesce(rr.dados, '{}'::jsonb)
           || analise.montar_raw(to_jsonb(s) - ARRAY['ano_carga', 'carga', 'regiao'], t.tempo_mediano, t.tempo_medio)
           || coalesce(e.estat, '{}'::jsonb) AS raw
) r;

CREATE UNIQUE INDEX idx_indicadores_regiao ON public.indicadores_regiao (carga, regiao);
COMMENT ON MATERIALIZED VIEW public.indicadores_regiao IS
  'PNITE — indicadores por carga e região (soma das UFs). Ex.: /rest/v1/indicadores_regiao?carga=eq.202605&regiao=eq.centro-oeste';

CREATE MATERIALIZED VIEW public.indicadores_nacional AS
WITH s AS (
    SELECT ano_carga, carga,
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
           sum(al_hidro) AS al_hidro, sum(al_hidro_imp) AS al_hidro_imp, sum(al_transp_imp) AS al_transp_imp,
           sum(censo_mun) AS censo_mun, sum(censo_est) AS censo_est, sum(censo_esc_transp) AS censo_esc_transp,
           sum(idade_prop_soma) AS idade_prop_soma, sum(idade_prop_n) AS idade_prop_n,
           sum(idade_terc_soma) AS idade_terc_soma, sum(idade_terc_n) AS idade_terc_n
    FROM public.indicadores_regiao
    GROUP BY ano_carga, carga
)
SELECT s.*,
       'Brasil'::text AS label,
       t.tempo_mediano, t.tempo_medio,
       r.raw,
       analise.calcular_indicadores(r.raw, 'Brasil') AS indicadores,
       (SELECT jsonb_object_agg(d.script, d.dados) FROM ref.detalhes_scripts d
         WHERE d.carga = s.carga AND d.chave = 'nacional') AS detalhes,
       now() AS atualizado_em
FROM s
LEFT JOIN analise.mv_tempo_rotas t ON t.carga = s.carga AND t.nivel = 'nacional' AND t.chave = 'nacional'
LEFT JOIN analise.mv_rotas_estatisticas e ON e.carga = s.carga AND e.nivel = 'nacional' AND e.chave = 'nacional'
LEFT JOIN analise.mv_medianas_nivel md ON md.carga = s.carga AND md.nivel = 'nacional' AND md.chave = 'nacional'
LEFT JOIN ref.raw_referencia rr ON rr.carga = s.carga AND rr.chave = 'nacional'
CROSS JOIN LATERAL (
    SELECT analise.referencia_calculada(to_jsonb(s), md.mifce, md.medate)
           || coalesce(rr.dados, '{}'::jsonb)
           || analise.montar_raw(to_jsonb(s) - ARRAY['ano_carga', 'carga'], t.tempo_mediano, t.tempo_medio)
           || coalesce(e.estat, '{}'::jsonb) AS raw
) r;

CREATE UNIQUE INDEX idx_indicadores_nacional ON public.indicadores_nacional (carga);
COMMENT ON MATERIALIZED VIEW public.indicadores_nacional IS
  'PNITE — indicadores do Brasil por carga (soma das regiões). Ex.: /rest/v1/indicadores_nacional?carga=eq.202605';

CREATE VIEW public.indicadores WITH (security_invoker = true) AS
SELECT ano_carga, carga, 'municipio'::text AS nivel, codigo_cidade::text AS chave, uf, regiao, label,
       raw, indicadores, NULL::jsonb AS detalhes, atualizado_em
FROM public.indicadores_municipio
UNION ALL
SELECT ano_carga, carga, 'estado', uf, uf, regiao, label, raw, indicadores, detalhes, atualizado_em
FROM public.indicadores_estado
UNION ALL
SELECT ano_carga, carga, 'regiao', regiao, NULL, regiao, label, raw, indicadores, NULL, atualizado_em
FROM public.indicadores_regiao
UNION ALL
SELECT ano_carga, carga, 'nacional', 'nacional', NULL, NULL, label, raw, indicadores, detalhes, atualizado_em
FROM public.indicadores_nacional;
COMMENT ON VIEW public.indicadores IS
  'PNITE — todos os níveis numa interface única (carga, nivel, chave). Ex.: /rest/v1/indicadores?carga=eq.202605&nivel=eq.estado&chave=eq.go';

-- ---------------------------------------------------------------------------
-- 8. Traçado das rotas (0010) por carga
-- ---------------------------------------------------------------------------
CREATE MATERIALIZED VIEW public.rotas_tracado AS
SELECT r.ano_carga, r.carga,
       r.codigo_cidade,
       lower(r.uf) AS uf,
       r.id_rota,
       r.nome,
       r.tipo,
       CASE r.tipo WHEN 1 THEN 'Rodoviário' WHEN 2 THEN 'Aquaviário' WHEN 3 THEN 'Mista' END AS tipo_label,
       r.km,
       r.tempo,
       s.geometria
FROM sete.rota_shape s
JOIN sete.rotas r ON r.carga = s.carga AND r.codigo_cidade = s.codigo_cidade AND r.id_rota = s.id_rota;

CREATE INDEX idx_rotas_tracado_cidade ON public.rotas_tracado (carga, codigo_cidade);
COMMENT ON MATERIALIZED VIEW public.rotas_tracado IS
  'PNITE — traçado simplificado das rotas (EPSG:4326) por carga. Ex.: /rest/v1/rotas_tracado?carga=eq.202605&codigo_cidade=eq.5212501';

-- ---------------------------------------------------------------------------
-- 9. Complementos municipais (0013) por carga
-- ---------------------------------------------------------------------------
CREATE MATERIALIZED VIEW analise.mv_complemento_municipio AS
WITH
cen AS (
    SELECT c.carga, m.co_municipio::integer AS codigo_cidade,
           sum(m.qt_transp_publico)   AS transp,
           sum(m.qt_transp_resp_mun)  AS mun,
           sum(m.qt_transp_resp_est)  AS est,
           count(*) FILTER (WHERE m.qt_transp_publico > 0) AS esc_at,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY m.qt_transp_publico)
               FILTER (WHERE m.qt_transp_publico > 0) AS mediana
    FROM censo.matricula m
    JOIN ref.cargas c ON c.ano_carga_censo = m.ano_carga
    GROUP BY 1, 2),
fro AS (
    SELECT carga, codigo_cidade,
           count(*)                             AS tot_veic,
           count(*) FILTER (WHERE origem = 1)   AS vp,
           count(*) FILTER (WHERE origem = 2)   AS vt,
           count(*) FILTER (WHERE modelo <> 0)  AS ce_veic,
           avg((ano_carga - ano)::float8) FILTER (WHERE origem = 1 AND ano BETWEEN 1930 AND ano_carga) AS idade_propria,
           avg((ano_carga - ano)::float8) FILTER (WHERE origem = 2 AND ano BETWEEN 1930 AND ano_carga) AS idade_terceirizada,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY ano_carga - ano)
               FILTER (WHERE modelo <> 0 AND ano BETWEEN 1930 AND ano_carga) AS mediana_ce
    FROM sete.veiculos
    GROUP BY 1, 2),
chaves AS (SELECT carga, codigo_cidade FROM cen UNION SELECT carga, codigo_cidade FROM fro)
SELECT rc.ano_carga_sete AS ano_carga, k.carga, k.codigo_cidade, lower(mu.uf) AS uf,
       CASE WHEN cen.codigo_cidade IS NOT NULL THEN jsonb_build_object(
           'ATE',    CASE WHEN cen.esc_at > 0 THEN ceil(cen.transp::numeric / cen.esc_at) END,
           'MEDATE', ceil(cen.mediana),
           'PATM',   analise.pct_par(cen.mun, cen.mun + cen.est),
           'PATE',   analise.pct_par(cen.est, cen.mun + cen.est),
           'transp', cen.transp, 'esc_at', cen.esc_at, 'mun', cen.mun, 'est', cen.est) END AS censo,
       CASE WHEN fro.codigo_cidade IS NOT NULL THEN jsonb_build_object(
           'PVPCE',  analise.pct_par(fro.ce_veic, fro.tot_veic),
           'IMFP',   analise.round_par(fro.idade_propria, 1),
           'IMFT',   analise.round_par(fro.idade_terceirizada, 1),
           'MIFCE',  fro.mediana_ce,
           'ce_veic', fro.ce_veic, 'tot_veic', fro.tot_veic, 'vp', fro.vp, 'vt', fro.vt) END AS frota
FROM chaves k
JOIN ref.cargas rc ON rc.carga = k.carga
JOIN ref.municipios mu ON mu.codigo_ibge = k.codigo_cidade AND mu.codigo_ibge < 10000000
LEFT JOIN cen ON cen.carga = k.carga AND cen.codigo_cidade = k.codigo_cidade
LEFT JOIN fro ON fro.carga = k.carga AND fro.codigo_cidade = k.codigo_cidade;

CREATE UNIQUE INDEX idx_mv_complemento_municipio ON analise.mv_complemento_municipio (carga, codigo_cidade);
COMMENT ON MATERIALIZED VIEW analise.mv_complemento_municipio IS
  'Indicadores municipais do Censo (ATE, MEDATE, PATM, PATE) e da frota (PVPCE, IMFP, IMFT, MIFCE) por carga, com as regras das antigas bases embutidas.';

CREATE MATERIALIZED VIEW public.indicadores_municipio_complemento AS
SELECT ano_carga, carga, codigo_cidade, uf, censo, frota
FROM analise.mv_complemento_municipio;

CREATE UNIQUE INDEX idx_indicadores_municipio_complemento ON public.indicadores_municipio_complemento (carga, codigo_cidade);
COMMENT ON MATERIALIZED VIEW public.indicadores_municipio_complemento IS
  'PNITE — complemento municipal por carga: {censo: ATE, MEDATE, PATM, PATE}, {frota: PVPCE, IMFP, IMFT, MIFCE}. Ex.: /rest/v1/indicadores_municipio_complemento?carga=eq.202605&codigo_cidade=eq.5208707';

-- ---------------------------------------------------------------------------
-- 10. Tabela "Dados SETE" (0021) por carga
-- ---------------------------------------------------------------------------
CREATE MATERIALIZED VIEW analise.mv_sete_municipio AS
WITH
esc AS (SELECT carga, codigo_cidade, count(*) AS n FROM sete.escolas GROUP BY 1, 2),
rk  AS (SELECT carga, codigo_cidade, count(*) FILTER (WHERE km > 0) AS n
        FROM analise.v_rotas GROUP BY 1, 2),
mot AS (SELECT carga, codigo_cidade, count(*) AS n FROM analise.v_motoristas GROUP BY 1, 2),
fo  AS (SELECT carga, codigo_cidade, count(*) AS n FROM sete.fornecedores GROUP BY 1, 2),
os  AS (SELECT carga, codigo_cidade, count(*) AS n FROM sete.ordem_servico GROUP BY 1, 2),
nm  AS (SELECT carga, codigo_cidade, count(*) AS n FROM sete.normas GROUP BY 1, 2),
eta AS (SELECT carga, codigo_cidade, count(*) AS n FROM sete.escola_tem_aluno GROUP BY 1, 2),
rpe AS (SELECT carga, codigo_cidade, count(*) AS n FROM sete.rota_passa_por_escolas GROUP BY 1, 2),
rpv AS (SELECT carga, codigo_cidade, count(*) AS n FROM sete.rota_possui_veiculo GROUP BY 1, 2),
rdm AS (SELECT carga, codigo_cidade, count(*) AS n FROM sete.rota_dirigida_por_motorista GROUP BY 1, 2),
-- Rotas com veículo adequado (ônibus, micro-ônibus ou van) e alunos atendidos por elas (TETI)
adequada AS (
    SELECT DISTINCT p.carga, p.codigo_cidade, p.id_rota
    FROM sete.rota_possui_veiculo p
    JOIN sete.veiculos v ON v.carga = p.carga AND v.codigo_cidade = p.codigo_cidade AND v.id_veiculo = p.id_veiculo
    WHERE v.tipo IN (1, 2, 3)),
al_adeq AS (
    SELECT a.carga, a.codigo_cidade, count(DISTINCT a.id_aluno) AS n
    FROM sete.rota_atende_aluno a
    JOIN adequada r ON r.carga = a.carga AND r.codigo_cidade = a.codigo_cidade AND r.id_rota = a.id_rota
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
    LEFT JOIN esc     USING (carga, codigo_cidade)
    LEFT JOIN rk      USING (carga, codigo_cidade)
    LEFT JOIN mot     USING (carga, codigo_cidade)
    LEFT JOIN fo      USING (carga, codigo_cidade)
    LEFT JOIN os      USING (carga, codigo_cidade)
    LEFT JOIN nm      USING (carga, codigo_cidade)
    LEFT JOIN eta     USING (carga, codigo_cidade)
    LEFT JOIN rpe     USING (carga, codigo_cidade)
    LEFT JOIN rpv     USING (carga, codigo_cidade)
    LEFT JOIN rdm     USING (carga, codigo_cidade)
    LEFT JOIN al_adeq USING (carga, codigo_cidade)
    -- valores do painel principal: mesma definição de km, capacidade, IUC e vínculo
    LEFT JOIN public.indicadores_municipio i ON i.carga = b.carga AND i.codigo_cidade = b.codigo_cidade AND i.uf = b.uf)
SELECT base.ano_carga, base.carga, base.codigo_cidade, base.uf, base.nome,
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
       (base.ind ->> 'MQT')::numeric   AS mqt,
       (base.ind ->> 'PARI')::numeric  AS pari,
       base.al_transp_imp              AS alunos_imped
FROM base
WHERE base.al_cad > 0 OR base.tot_rotas > 0 OR base.tot_veic > 0 OR base.escolas > 0
   OR base.tot_mon > 0 OR base.motoristas > 0;

CREATE UNIQUE INDEX idx_mv_sete_municipio ON analise.mv_sete_municipio (carga, codigo_cidade);
COMMENT ON MATERIALIZED VIEW analise.mv_sete_municipio IS
  'Tabela "Dados SETE" por carga e município; km_total, cap_media, IUC, MON_CVE, MOT_CVE, PAIH, PAFI, TVA, MQT e PARI iguais aos do painel (public.indicadores_municipio).';

CREATE MATERIALIZED VIEW public.sete_municipios AS
SELECT s.ano_carga, s.carga,
       jsonb_build_object(
         'cols', jsonb_build_array('cod', 'mun', 'uf', 'alunos', 'al_transp', 'escolas', 'rotas', 'km_total', 'rotas_com_km',
                                   'rotas_t1', 'rotas_t2', 'rotas_t3', 'veiculos', 'veic_origem1', 'veic_origem2', 'cap_media',
                                   'monitores', 'motoristas', 'fornecedores', 'ordens_servico', 'normas', 'vinc_escola_aluno',
                                   'vinc_rota_escola', 'vinc_rota_veiculo', 'vinc_rota_motorista', 'PRGM', 'PRDAM', 'PRRM', 'PRHM',
                                   'PRMM', 'PVP', 'PVT', 'MON_CVE', 'MOT_CVE', 'ATE', 'MEDATE', 'IUC', 'TEDC', 'TETI', 'PATE', 'PATM',
                                   'PVPCE', 'IMFP', 'IMFT', 'MIFCE', 'PAIH', 'PAFI', 'TVA', 'MQT', 'PARI', 'alunos_imped'),
         'municipios', (
           SELECT jsonb_agg(jsonb_build_array(
                    m.codigo_cidade, m.nome, upper(m.uf), m.al_cad, m.al_transp_sete, m.escolas, m.tot_rotas, m.km_total, m.rotas_com_km,
                    m.t1, m.t2, m.t3, m.tot_veic, m.vp, m.vt, m.cap_media,
                    m.tot_mon, m.motoristas, m.fornecedores, m.ordens_servico, m.normas, m.v_eta,
                    m.v_rpe, m.v_rpv, m.v_rdm, m.prgm, m.prdam, m.prrm, m.prhm,
                    m.prmm, m.pvp, m.pvt, m.mon_cve, m.mot_cve, c.censo -> 'ATE', c.censo -> 'MEDATE', m.iuc, m.tedc, m.teti,
                    c.censo -> 'PATE', c.censo -> 'PATM',
                    c.frota -> 'PVPCE', c.frota -> 'IMFP', c.frota -> 'IMFT', c.frota -> 'MIFCE',
                    m.paih, m.pafi, m.tva, m.mqt, m.pari, m.alunos_imped) ORDER BY m.codigo_cidade)
           FROM analise.mv_sete_municipio m
           LEFT JOIN analise.mv_complemento_municipio c USING (carga, codigo_cidade)
           WHERE m.carga = s.carga),
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
             WHERE m.carga = s.carga
             GROUP BY m.uf) u
           JOIN ref.uf uf ON uf.sigla = u.uf)
       ) AS dados
FROM (SELECT DISTINCT ano_carga, carga FROM analise.mv_sete_municipio) s;
CREATE UNIQUE INDEX idx_sete_municipios ON public.sete_municipios (carga);
COMMENT ON MATERIALIZED VIEW public.sete_municipios IS
  'Tabela "Dados SETE": {cols, municipios (linhas por município), ufs (resumo por UF)} por carga (lida pela interface PNITE).';

-- ---------------------------------------------------------------------------
-- 11. Cargas disponíveis para a interface
-- ---------------------------------------------------------------------------
CREATE MATERIALIZED VIEW public.cargas_sete AS
SELECT c.carga, c.rotulo, c.data_referencia, c.ano_carga_sete AS ano_carga, c.ano_carga_censo AS ano_censo,
       c.descricao, c.carga = max(c.carga) OVER () AS atual
FROM ref.cargas c
WHERE EXISTS (SELECT 1 FROM public.indicadores_nacional n WHERE n.carga = c.carga);
CREATE UNIQUE INDEX idx_cargas_sete ON public.cargas_sete (carga);
COMMENT ON MATERIALIZED VIEW public.cargas_sete IS
  'PNITE — cargas do SETE com dados (rótulo, data de referência, Censo pareado; atual = a mais recente). Ex.: /rest/v1/cargas_sete?order=carga';

-- Somente leitura para a API (anon/authenticated); nada mais é exposto.
REVOKE ALL ON public.indicadores_municipio, public.indicadores_estado, public.indicadores_regiao,
              public.indicadores_nacional, public.indicadores, public.sete_municipios, public.rotas_tracado,
              public.indicadores_municipio_complemento, public.cargas_sete FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.indicadores_municipio, public.indicadores_estado, public.indicadores_regiao,
                public.indicadores_nacional, public.indicadores, public.sete_municipios, public.rotas_tracado,
                public.indicadores_municipio_complemento, public.cargas_sete TO anon, authenticated;

-- Atualização em cascata (a ordem importa: cada nível lê o anterior)
CREATE OR REPLACE FUNCTION pnite_meta.atualizar_indicadores() RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  mv text;
BEGIN
  FOREACH mv IN ARRAY ARRAY['analise.mv_base_municipio', 'analise.mv_tempo_rotas', 'analise.mv_rotas_estatisticas',
                            'analise.mv_medianas_nivel',
                            'public.indicadores_municipio', 'public.indicadores_estado',
                            'public.indicadores_regiao', 'public.indicadores_nacional',
                            'public.rotas_tracado',
                            'analise.mv_complemento_municipio', 'analise.mv_sete_municipio',
                            'public.indicadores_municipio_complemento', 'public.sete_municipios',
                            'public.cargas_sete'] LOOP
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
