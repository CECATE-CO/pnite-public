-- ============================================================================
-- PNITE — 0024: índices das tabelas do SETE pela carga
-- ----------------------------------------------------------------------------
-- Com duas cargas no mesmo ano, (ano_carga, ...) deixa de identificar a carga. Os índices
-- passam a começar por carga (mesmos nomes e colunas seguintes). Cada CREATE INDEX lê a
-- tabela inteira; o conjunto passa do tempo do gateway (~30 s), e o supabase_migrar.py
-- aguarda o término no banco.
-- ============================================================================

DROP INDEX sete.idx_sete_alunos_0;
CREATE INDEX idx_sete_alunos_0 ON sete.alunos USING btree (carga, codigo_cidade, id_aluno);
DROP INDEX sete.idx_sete_alunos_uf;
CREATE INDEX idx_sete_alunos_uf ON sete.alunos USING btree (carga, uf);
DROP INDEX sete.idx_sete_escola_tem_aluno_0;
CREATE INDEX idx_sete_escola_tem_aluno_0 ON sete.escola_tem_aluno USING btree (carga, codigo_cidade, id_escola);
DROP INDEX sete.idx_sete_escola_tem_aluno_1;
CREATE INDEX idx_sete_escola_tem_aluno_1 ON sete.escola_tem_aluno USING btree (carga, codigo_cidade, id_aluno);
DROP INDEX sete.idx_sete_escola_tem_aluno_uf;
CREATE INDEX idx_sete_escola_tem_aluno_uf ON sete.escola_tem_aluno USING btree (carga, uf);
DROP INDEX sete.idx_sete_escolas_0;
CREATE INDEX idx_sete_escolas_0 ON sete.escolas USING btree (carga, codigo_cidade, id_escola);
DROP INDEX sete.idx_sete_escolas_uf;
CREATE INDEX idx_sete_escolas_uf ON sete.escolas USING btree (carga, uf);
DROP INDEX sete.idx_sete_fornecedores_0;
CREATE INDEX idx_sete_fornecedores_0 ON sete.fornecedores USING btree (carga, codigo_cidade, id_fornecedor);
DROP INDEX sete.idx_sete_fornecedores_uf;
CREATE INDEX idx_sete_fornecedores_uf ON sete.fornecedores USING btree (carga, uf);
DROP INDEX sete.idx_sete_monitores_0;
CREATE INDEX idx_sete_monitores_0 ON sete.monitores USING btree (carga, codigo_cidade);
DROP INDEX sete.idx_sete_monitores_uf;
CREATE INDEX idx_sete_monitores_uf ON sete.monitores USING btree (carga, uf);
DROP INDEX sete.idx_sete_motoristas_0;
CREATE INDEX idx_sete_motoristas_0 ON sete.motoristas USING btree (carga, codigo_cidade);
DROP INDEX sete.idx_sete_motoristas_uf;
CREATE INDEX idx_sete_motoristas_uf ON sete.motoristas USING btree (carga, uf);
DROP INDEX sete.idx_sete_normas_0;
CREATE INDEX idx_sete_normas_0 ON sete.normas USING btree (carga, codigo_cidade, id);
DROP INDEX sete.idx_sete_normas_uf;
CREATE INDEX idx_sete_normas_uf ON sete.normas USING btree (carga, uf);
DROP INDEX sete.idx_sete_ordem_servico_0;
CREATE INDEX idx_sete_ordem_servico_0 ON sete.ordem_servico USING btree (carga, codigo_cidade, id_ordem);
DROP INDEX sete.idx_sete_ordem_servico_1;
CREATE INDEX idx_sete_ordem_servico_1 ON sete.ordem_servico USING btree (carga, codigo_cidade, id_veiculo);
DROP INDEX sete.idx_sete_ordem_servico_uf;
CREATE INDEX idx_sete_ordem_servico_uf ON sete.ordem_servico USING btree (carga, uf);
DROP INDEX sete.idx_sete_rota_atende_aluno_0;
CREATE INDEX idx_sete_rota_atende_aluno_0 ON sete.rota_atende_aluno USING btree (carga, codigo_cidade, id_rota);
DROP INDEX sete.idx_sete_rota_atende_aluno_1;
CREATE INDEX idx_sete_rota_atende_aluno_1 ON sete.rota_atende_aluno USING btree (carga, codigo_cidade, id_aluno);
DROP INDEX sete.idx_sete_rota_atende_aluno_uf;
CREATE INDEX idx_sete_rota_atende_aluno_uf ON sete.rota_atende_aluno USING btree (carga, uf);
DROP INDEX sete.idx_sete_rota_dirigida_por_motorista_0;
CREATE INDEX idx_sete_rota_dirigida_por_motorista_0 ON sete.rota_dirigida_por_motorista USING btree (carga, codigo_cidade, id_rota);
DROP INDEX sete.idx_sete_rota_dirigida_por_motorista_uf;
CREATE INDEX idx_sete_rota_dirigida_por_motorista_uf ON sete.rota_dirigida_por_motorista USING btree (carga, uf);
DROP INDEX sete.idx_sete_rota_passa_por_escolas_0;
CREATE INDEX idx_sete_rota_passa_por_escolas_0 ON sete.rota_passa_por_escolas USING btree (carga, codigo_cidade, id_rota);
DROP INDEX sete.idx_sete_rota_passa_por_escolas_1;
CREATE INDEX idx_sete_rota_passa_por_escolas_1 ON sete.rota_passa_por_escolas USING btree (carga, codigo_cidade, id_escola);
DROP INDEX sete.idx_sete_rota_passa_por_escolas_uf;
CREATE INDEX idx_sete_rota_passa_por_escolas_uf ON sete.rota_passa_por_escolas USING btree (carga, uf);
DROP INDEX sete.idx_sete_rota_possui_veiculo_0;
CREATE INDEX idx_sete_rota_possui_veiculo_0 ON sete.rota_possui_veiculo USING btree (carga, codigo_cidade, id_rota);
DROP INDEX sete.idx_sete_rota_possui_veiculo_1;
CREATE INDEX idx_sete_rota_possui_veiculo_1 ON sete.rota_possui_veiculo USING btree (carga, codigo_cidade, id_veiculo);
DROP INDEX sete.idx_sete_rota_possui_veiculo_uf;
CREATE INDEX idx_sete_rota_possui_veiculo_uf ON sete.rota_possui_veiculo USING btree (carga, uf);
DROP INDEX sete.idx_sete_rota_shape_0;
CREATE INDEX idx_sete_rota_shape_0 ON sete.rota_shape USING btree (carga, codigo_cidade, id_rota);
DROP INDEX sete.idx_sete_rota_shape_uf;
CREATE INDEX idx_sete_rota_shape_uf ON sete.rota_shape USING btree (carga, uf);
DROP INDEX sete.idx_sete_rotas_0;
CREATE INDEX idx_sete_rotas_0 ON sete.rotas USING btree (carga, codigo_cidade, id_rota);
DROP INDEX sete.idx_sete_rotas_uf;
CREATE INDEX idx_sete_rotas_uf ON sete.rotas USING btree (carga, uf);
DROP INDEX sete.idx_sete_veiculos_0;
CREATE INDEX idx_sete_veiculos_0 ON sete.veiculos USING btree (carga, codigo_cidade, id_veiculo);
DROP INDEX sete.idx_sete_veiculos_uf;
CREATE INDEX idx_sete_veiculos_uf ON sete.veiculos USING btree (carga, uf);
