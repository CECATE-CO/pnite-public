-- ============================================================================
-- PNITE — 0008: indicadores com uma view materializada por nível (cascata)
-- ----------------------------------------------------------------------------
-- Substitui o GROUPING SETS da 0006 por quatro views materializadas, cada uma
-- com um GROUP BY simples sobre o nível imediatamente abaixo:
--
--   analise.mv_base_municipio
--     └─► public.indicadores_municipio   (1 linha por município)
--           └─► public.indicadores_estado     (soma dos municípios da UF)
--                 └─► public.indicadores_regiao    (soma das UFs da região)
--                       └─► public.indicadores_nacional  (soma das regiões)
--
-- Cada view tem os contadores em colunas tipadas (somáveis e consultáveis pela
-- API) e, para o front-end, o mesmo formato de antes: raw (RAW_DATA) e
-- indicadores (DATA). As fórmulas continuam num único lugar
-- (analise.calcular_indicadores) e o empacotamento do raw também
-- (analise.montar_raw). Medianas não se somam: vêm de analise.mv_tempo_rotas,
-- calculada a partir das rotas individuais em cada nível.
--
-- public.indicadores passa a ser uma view comum (UNION ALL das quatro) que
-- mantém a interface anterior (nivel/chave).
-- ============================================================================

DROP MATERIALIZED VIEW IF EXISTS public.indicadores;
DROP MATERIALIZED VIEW IF EXISTS analise.mv_tempo_rotas;

-- ---------------------------------------------------------------------------
-- Tempo das rotas (faixa 1–360 min): mediana e média por nível, uma consulta por nível
-- ---------------------------------------------------------------------------
CREATE MATERIALIZED VIEW analise.mv_tempo_rotas AS
SELECT ano_carga, 'municipio'::text AS nivel, codigo_cidade::text AS chave,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY tempo)::numeric, 1) AS tempo_mediano,
       round(avg(tempo), 1) AS tempo_medio
FROM analise.v_rotas WHERE tempo_valido
GROUP BY ano_carga, codigo_cidade
UNION ALL
SELECT ano_carga, 'estado', uf,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY tempo)::numeric, 1), round(avg(tempo), 1)
FROM analise.v_rotas WHERE tempo_valido
GROUP BY ano_carga, uf
UNION ALL
SELECT r.ano_carga, 'regiao', u.regiao,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY r.tempo)::numeric, 1), round(avg(r.tempo), 1)
FROM analise.v_rotas r JOIN ref.uf u ON u.sigla = r.uf
WHERE r.tempo_valido
GROUP BY r.ano_carga, u.regiao
UNION ALL
SELECT ano_carga, 'nacional', 'nacional',
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY tempo)::numeric, 1), round(avg(tempo), 1)
FROM analise.v_rotas WHERE tempo_valido
GROUP BY ano_carga
WITH NO DATA;

CREATE UNIQUE INDEX idx_mv_tempo_rotas ON analise.mv_tempo_rotas (ano_carga, nivel, chave);

-- ---------------------------------------------------------------------------
-- raw (formato RAW_DATA) a partir dos contadores somados: um único lugar para
-- arredondamentos e campos derivados, usado pelos quatro níveis.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION analise.montar_raw(contadores jsonb, tempo_mediano numeric, tempo_medio numeric)
RETURNS jsonb LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT contadores || jsonb_build_object(
           'km_total',  round(analise.num(contadores, 'km_total'), 1),
           'km_geo',    round(analise.num(contadores, 'km_geo'), 1),
           'km_medio',  CASE WHEN analise.num(contadores, 'tot_rotas') > 0
                             THEN round(round(analise.num(contadores, 'km_total'), 1)
                                        / analise.num(contadores, 'tot_rotas'), 1) END,
           'cap_media', CASE WHEN analise.num(contadores, 'n_veic_validos') > 0
                             THEN round(analise.num(contadores, 'cap_sum')
                                        / analise.num(contadores, 'n_veic_validos'), 2)
                             ELSE 0.0 END,
           'al_transp', contadores -> 'al_transp_sete')
         || jsonb_strip_nulls(jsonb_build_object('tempo_mediano', tempo_mediano, 'tempo_medio', tempo_medio))
$$;
COMMENT ON FUNCTION analise.montar_raw(jsonb, numeric, numeric) IS
  'Monta o raw (formato RAW_DATA) a partir dos contadores somados de um escopo: km arredondado, km_medio, cap_media, al_transp e tempos.';

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
CROSS JOIN LATERAL (
    SELECT analise.montar_raw(to_jsonb(b) - ARRAY['ano_carga', 'codigo_cidade', 'uf'],
                              t.tempo_mediano, t.tempo_medio) AS raw
) r
WITH NO DATA;

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
           sum(demanda_censo) AS demanda_censo
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
LEFT JOIN ref.raw_referencia rr ON rr.ano_carga = s.ano_carga AND rr.chave = s.uf
CROSS JOIN LATERAL (
    -- contadores calculados dos dados brutos sobrepõem os valores de referência (legado + planilhas)
    SELECT coalesce(rr.dados, '{}'::jsonb)
           || analise.montar_raw(to_jsonb(s) - ARRAY['ano_carga', 'uf'], t.tempo_mediano, t.tempo_medio) AS raw
) r
WITH NO DATA;

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
           sum(demanda_censo) AS demanda_censo
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
LEFT JOIN ref.raw_referencia rr ON rr.ano_carga = s.ano_carga AND rr.chave = s.regiao
CROSS JOIN LATERAL (
    SELECT coalesce(rr.dados, '{}'::jsonb)
           || analise.montar_raw(to_jsonb(s) - ARRAY['ano_carga', 'regiao'], t.tempo_mediano, t.tempo_medio) AS raw
) r
WITH NO DATA;

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
           sum(demanda_censo) AS demanda_censo
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
LEFT JOIN ref.raw_referencia rr ON rr.ano_carga = s.ano_carga AND rr.chave = 'nacional'
CROSS JOIN LATERAL (
    SELECT coalesce(rr.dados, '{}'::jsonb)
           || analise.montar_raw(to_jsonb(s) - 'ano_carga', t.tempo_mediano, t.tempo_medio) AS raw
) r
WITH NO DATA;

CREATE UNIQUE INDEX idx_indicadores_nacional ON public.indicadores_nacional (ano_carga);
COMMENT ON MATERIALIZED VIEW public.indicadores_nacional IS
  'PNITE — indicadores do Brasil (soma das regiões). Ex.: /rest/v1/indicadores_nacional?ano_carga=eq.2026';

-- ---------------------------------------------------------------------------
-- Compatibilidade: interface única por (nivel, chave), como na 0006
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

-- Somente leitura para a API (anon/authenticated); nada mais é exposto.
REVOKE ALL ON public.indicadores_municipio, public.indicadores_estado, public.indicadores_regiao,
              public.indicadores_nacional, public.indicadores FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.indicadores_municipio, public.indicadores_estado, public.indicadores_regiao,
                public.indicadores_nacional, public.indicadores TO anon, authenticated;

-- Atualização em cascata (a ordem importa: cada nível lê o anterior)
CREATE OR REPLACE FUNCTION pnite_meta.atualizar_indicadores() RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  mv text;
BEGIN
  FOREACH mv IN ARRAY ARRAY['analise.mv_base_municipio', 'analise.mv_tempo_rotas',
                            'public.indicadores_municipio', 'public.indicadores_estado',
                            'public.indicadores_regiao', 'public.indicadores_nacional'] LOOP
    IF (SELECT ispopulated FROM pg_matviews WHERE schemaname || '.' || matviewname = mv) THEN
      EXECUTE format('REFRESH MATERIALIZED VIEW CONCURRENTLY %s', mv);
    ELSE
      EXECUTE format('REFRESH MATERIALIZED VIEW %s', mv);
    END IF;
  END LOOP;
END
$$;
REVOKE ALL ON FUNCTION pnite_meta.atualizar_indicadores() FROM PUBLIC;
