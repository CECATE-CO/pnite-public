-- ============================================================================
-- PNITE — 0011: UF do Censo pelo código do município quando SG_UF vem vazio
-- ----------------------------------------------------------------------------
-- No microdado 2025 há escola com SG_UF em branco (ex.: Sapiranga/RS, 4319901,
-- 30 alunos com transporte público). Sem UF, a linha não se ligava a ref.uf e
-- saía de todos os níveis. A UF passa a vir de SG_UF e, na falta, do cadastro
-- IBGE do município (ref.municipios), mantendo a demanda no município, na UF e no Brasil.
-- ============================================================================

CREATE OR REPLACE VIEW analise.v_censo_municipio WITH (security_invoker = true) AS
SELECT c.ano_carga, c.co_municipio::integer AS codigo_cidade,
       coalesce(lower(nullif(trim(c.sg_uf), '')), m.uf) AS uf,
       count(*)                     AS escolas,
       sum(c.qt_mat_bas)            AS matriculas_basica,
       sum(c.qt_transp_publico)     AS transp_publico,
       sum(c.qt_transp_resp_est)    AS transp_resp_estadual,
       sum(c.qt_transp_resp_mun)    AS transp_resp_municipal
FROM censo.matricula c
LEFT JOIN ref.municipios m ON m.codigo_ibge = c.co_municipio
GROUP BY c.ano_carga, c.co_municipio, coalesce(lower(nullif(trim(c.sg_uf), '')), m.uf);
