-- ============================================================================
-- PNITE — 0003: dados brutos do SETE (gerado por scripts/criar_banco_dados_brutos.py --gerar-ddl)
-- Colunas = cabeçalho dos CSVs; tipos e descrições = dicionário do SETE.
-- ============================================================================

-- Normas municipais de transporte escolar cadastradas no SETE.
CREATE TABLE IF NOT EXISTS sete.normas (
    ano_carga smallint NOT NULL DEFAULT 2026,
    id integer,
    codigo_cidade integer,
    nome_cidade text,
    uf varchar(2),
    estado text,
    numero_norma text,
    titulo text,
    data_norma timestamp,
    id_tipo smallint,
    tipo_veiculo smallint,
    outro_tipo text
);
COMMENT ON TABLE sete.normas IS 'Normas municipais de transporte escolar cadastradas no SETE. Fonte: data/Transporte Escolar/script_09_normas_consolidado.csv.';
COMMENT ON COLUMN sete.normas.ano_carga IS 'Ano de referência da carga do dado.';
CREATE INDEX IF NOT EXISTS idx_sete_normas_uf ON sete.normas (ano_carga, uf);
CREATE INDEX IF NOT EXISTS idx_sete_normas_0 ON sete.normas (ano_carga, codigo_cidade, id);

-- Fornecedores (mecânica, combustível, seguro) cadastrados no SETE.
CREATE TABLE IF NOT EXISTS sete.fornecedores (
    ano_carga smallint NOT NULL DEFAULT 2026,
    codigo_cidade integer,
    nome_cidade text,
    uf varchar(2),
    estado text,
    id_fornecedor integer,
    ramo_mecanica char(1),
    ramo_combustivel char(1),
    ramo_seguro char(1),
    dt_criacao timestamp,
    dt_alteracao timestamp
);
COMMENT ON TABLE sete.fornecedores IS 'Fornecedores (mecânica, combustível, seguro) cadastrados no SETE. Fonte: data/Transporte Escolar/script_10_fornecedores_consolidado.csv.';
COMMENT ON COLUMN sete.fornecedores.ano_carga IS 'Ano de referência da carga do dado.';
CREATE INDEX IF NOT EXISTS idx_sete_fornecedores_uf ON sete.fornecedores (ano_carga, uf);
CREATE INDEX IF NOT EXISTS idx_sete_fornecedores_0 ON sete.fornecedores (ano_carga, codigo_cidade, id_fornecedor);

-- Monitores do transporte escolar cadastrados no SETE.
CREATE TABLE IF NOT EXISTS sete.monitores (
    ano_carga smallint NOT NULL DEFAULT 2026,
    codigo_cidade integer,
    nome_cidade text,
    uf varchar(2),
    estado text,
    idade integer,
    sexo smallint,
    vinculo smallint,
    salario numeric,
    turno_manha char(1),
    turno_tarde char(1),
    turno_noite char(1),
    loc_latitude double precision,
    loc_longitude double precision,
    dt_criacao timestamp,
    dt_alteracao timestamp
);
COMMENT ON TABLE sete.monitores IS 'Monitores do transporte escolar cadastrados no SETE. Fonte: data/Transporte Escolar/script_05_monitores_consolidado.csv.';
COMMENT ON COLUMN sete.monitores.ano_carga IS 'Ano de referência da carga do dado.';
COMMENT ON COLUMN sete.monitores.codigo_cidade IS 'ID numérico (7 dígitos) do município no IBGE';
COMMENT ON COLUMN sete.monitores.dt_alteracao IS 'Quando o dado do aluno foi alterado. Os dados anteriores a 2024 estão NULOS';
COMMENT ON COLUMN sete.monitores.dt_criacao IS 'Quando o dado do monitor foi criado. Os dados anteriores a 2024 estão NULOS';
COMMENT ON COLUMN sete.monitores.idade IS 'Variável numérica que representa a idade do monitor. Pode ter valores negativo devido a erros.';
COMMENT ON COLUMN sete.monitores.loc_latitude IS 'Campo antigo (desconsiderar)';
COMMENT ON COLUMN sete.monitores.loc_longitude IS 'Campo antigo (desconsiderar)';
COMMENT ON COLUMN sete.monitores.salario IS 'Salário do motorista.';
COMMENT ON COLUMN sete.monitores.sexo IS 'Variável numérica que representa o sexo do motorista. Valores possíveis: 1 = Masculino 2 = Feminino 3 = Não Informado';
COMMENT ON COLUMN sete.monitores.turno_manha IS 'Variável binária (S/N) que indica se o motorista trabalho no turno da manhã';
COMMENT ON COLUMN sete.monitores.turno_noite IS 'Variável binária (S/N) que indica se o motorista trabalho no turno da noite';
COMMENT ON COLUMN sete.monitores.turno_tarde IS 'Variável binária (S/N) que indica se o motorista trabalho no turno da tarde';
COMMENT ON COLUMN sete.monitores.vinculo IS 'Variável numérica que representa o vínculo trabalhista do motorista. Valores possíveis: 1 = Servidor Efetivo 2 = Servidor Comissionado 3 = Terceirizado 4 = Outro';
CREATE INDEX IF NOT EXISTS idx_sete_monitores_uf ON sete.monitores (ano_carga, uf);
CREATE INDEX IF NOT EXISTS idx_sete_monitores_0 ON sete.monitores (ano_carga, codigo_cidade);

-- Vínculo rota × veículo (chave: codigo_cidade + id_rota / id_veiculo).
CREATE TABLE IF NOT EXISTS sete.rota_possui_veiculo (
    ano_carga smallint NOT NULL DEFAULT 2026,
    id_rota integer,
    id_veiculo integer,
    codigo_cidade integer,
    nome_cidade text,
    uf varchar(2),
    estado text
);
COMMENT ON TABLE sete.rota_possui_veiculo IS 'Vínculo rota × veículo (chave: codigo_cidade + id_rota / id_veiculo). Fonte: data/Transporte Escolar/script_16_rota_possui_veiculo_consolidado.csv.';
COMMENT ON COLUMN sete.rota_possui_veiculo.ano_carga IS 'Ano de referência da carga do dado.';
CREATE INDEX IF NOT EXISTS idx_sete_rota_possui_veiculo_uf ON sete.rota_possui_veiculo (ano_carga, uf);
CREATE INDEX IF NOT EXISTS idx_sete_rota_possui_veiculo_0 ON sete.rota_possui_veiculo (ano_carga, codigo_cidade, id_rota);
CREATE INDEX IF NOT EXISTS idx_sete_rota_possui_veiculo_1 ON sete.rota_possui_veiculo (ano_carga, codigo_cidade, id_veiculo);

-- Vínculo rota × motorista (chave: codigo_cidade + id_rota / cpf_motorista).
CREATE TABLE IF NOT EXISTS sete.rota_dirigida_por_motorista (
    ano_carga smallint NOT NULL DEFAULT 2026,
    id_rota integer,
    cpf_motorista text,
    codigo_cidade integer,
    nome_cidade text,
    uf varchar(2),
    estado text
);
COMMENT ON TABLE sete.rota_dirigida_por_motorista IS 'Vínculo rota × motorista (chave: codigo_cidade + id_rota / cpf_motorista). Fonte: data/Transporte Escolar/script_17_rota_dirigida_por_motorista_consolidado.csv.';
COMMENT ON COLUMN sete.rota_dirigida_por_motorista.ano_carga IS 'Ano de referência da carga do dado.';
CREATE INDEX IF NOT EXISTS idx_sete_rota_dirigida_por_motorista_uf ON sete.rota_dirigida_por_motorista (ano_carga, uf);
CREATE INDEX IF NOT EXISTS idx_sete_rota_dirigida_por_motorista_0 ON sete.rota_dirigida_por_motorista (ano_carga, codigo_cidade, id_rota);

-- Motoristas do transporte escolar cadastrados no SETE.
CREATE TABLE IF NOT EXISTS sete.motoristas (
    ano_carga smallint NOT NULL DEFAULT 2026,
    codigo_cidade integer,
    nome_cidade text,
    uf varchar(2),
    estado text,
    idade integer,
    sexo smallint,
    tem_cnh_a char(1),
    tem_cnh_b char(1),
    tem_cnh_c char(1),
    tem_cnh_d char(1),
    tem_cnh_e char(1),
    turno_manha char(1),
    turno_tarde char(1),
    turno_noite char(1),
    data_validade_cnh date,
    vinculo smallint,
    salario numeric
);
COMMENT ON TABLE sete.motoristas IS 'Motoristas do transporte escolar cadastrados no SETE. Fonte: data/Transporte Escolar/script_06_motoristas_consolidado.csv.';
COMMENT ON COLUMN sete.motoristas.ano_carga IS 'Ano de referência da carga do dado.';
COMMENT ON COLUMN sete.motoristas.codigo_cidade IS 'ID numérico (7 dígitos) do município no IBGE';
COMMENT ON COLUMN sete.motoristas.data_validade_cnh IS 'Data de validade da CNH do motorista. Há casos em que a variável é NULA';
COMMENT ON COLUMN sete.motoristas.idade IS 'Variável numérica que representa a idade do motorista. Pode ter valores negativo devido a erros.';
COMMENT ON COLUMN sete.motoristas.salario IS 'Salário do motorista.';
COMMENT ON COLUMN sete.motoristas.sexo IS 'Variável numérica que representa o sexo do motorista. Valores possíveis: 1 = Masculino 2 = Feminino 3 = Não Informado';
COMMENT ON COLUMN sete.motoristas.tem_cnh_a IS 'Variável binária (S/N) que indica se o motorista tem ou não CNH A';
COMMENT ON COLUMN sete.motoristas.tem_cnh_b IS 'Variável binária (S/N) que indica se o motorista tem ou não CNH B';
COMMENT ON COLUMN sete.motoristas.tem_cnh_c IS 'Variável binária (S/N) que indica se o motorista tem ou não CNH C';
COMMENT ON COLUMN sete.motoristas.tem_cnh_d IS 'Variável binária (S/N) que indica se o motorista tem ou não CNH D';
COMMENT ON COLUMN sete.motoristas.tem_cnh_e IS 'Variável binária (S/N) que indica se o motorista tem ou não CNH E';
COMMENT ON COLUMN sete.motoristas.turno_manha IS 'Variável binária (S/N) que indica se o motorista trabalho no turno da manhã';
COMMENT ON COLUMN sete.motoristas.turno_noite IS 'Variável binária (S/N) que indica se o motorista trabalho no turno da noite';
COMMENT ON COLUMN sete.motoristas.turno_tarde IS 'Variável binária (S/N) que indica se o motorista trabalho no turno da tarde';
COMMENT ON COLUMN sete.motoristas.vinculo IS 'Variável numérica que representa o vínculo trabalhista do motorista. Valores possíveis: 1 = Servidor Efetivo 2 = Servidor Comissionado 3 = Terceirizado 4 = Outro';
CREATE INDEX IF NOT EXISTS idx_sete_motoristas_uf ON sete.motoristas (ano_carga, uf);
CREATE INDEX IF NOT EXISTS idx_sete_motoristas_0 ON sete.motoristas (ano_carga, codigo_cidade);

-- Frota (veículos) do transporte escolar cadastrada no SETE.
CREATE TABLE IF NOT EXISTS sete.veiculos (
    ano_carga smallint NOT NULL DEFAULT 2026,
    codigo_cidade integer,
    nome_cidade text,
    uf varchar(2),
    estado text,
    id_veiculo integer,
    placa text,
    ano integer,
    modo smallint,
    origem smallint,
    km_inicial numeric,
    capacidade numeric,
    km_atual numeric,
    tipo smallint,
    renavam text,
    manutencao char(1),
    marca smallint,
    id_firebase text,
    ipva numeric,
    dpvat numeric,
    seguro_anual numeric,
    consumo numeric,
    tipo_combustivel char(1),
    numero_de_pneus integer,
    vida_util_do_pneu numeric,
    preco numeric,
    potencia_do_motor numeric,
    modelo smallint,
    outro_tipo_text text,
    is_state text,
    historico text,
    ativo smallint,
    dt_criacao timestamp,
    criado_id integer,
    dt_alteracao timestamp,
    alterado_id integer
);
COMMENT ON TABLE sete.veiculos IS 'Frota (veículos) do transporte escolar cadastrada no SETE. Fonte: data/Transporte Escolar/script_04_veiculos_consolidado.csv.';
COMMENT ON COLUMN sete.veiculos.ano_carga IS 'Ano de referência da carga do dado.';
COMMENT ON COLUMN sete.veiculos.alterado_id IS 'Campo antigo (desconsiderar)';
COMMENT ON COLUMN sete.veiculos.ano IS 'Ano do veículo (variável numérica)';
COMMENT ON COLUMN sete.veiculos.ativo IS 'Valor numérico que indica se o veículo está ativo ou não. 1 = Ativo 0 = Não ativo';
COMMENT ON COLUMN sete.veiculos.capacidade IS 'Variável numérica que representa a capacidade do veículo (lugares)';
COMMENT ON COLUMN sete.veiculos.codigo_cidade IS 'ID numérico (7 dígitos) do município no IBGE';
COMMENT ON COLUMN sete.veiculos.consumo IS 'Variável numérica que indica o consumo de combustível do veículo em km/L';
COMMENT ON COLUMN sete.veiculos.criado_id IS 'Campo antigo (desconsiderar)';
COMMENT ON COLUMN sete.veiculos.dpvat IS 'Variável numérica que indica o valor do DPVAT. Pode ser nula ou igual a 0.';
COMMENT ON COLUMN sete.veiculos.dt_alteracao IS 'Quando o dado do aluno foi alterado. Os dados anteriores a 2024 estão NULOS';
COMMENT ON COLUMN sete.veiculos.dt_criacao IS 'Quando o dado do veículo foi criado. Os dados anteriores a 2024 estão NULOS';
COMMENT ON COLUMN sete.veiculos.historico IS 'Campo antigo (desconsiderar)';
COMMENT ON COLUMN sete.veiculos.id_firebase IS 'Campo antigo (desconsiderar)';
COMMENT ON COLUMN sete.veiculos.id_veiculo IS 'ID interno do SETE para representar um determinado veículo de um município. Não é global, isto é, tem que ser combinado com o ID da cidade para representar de forma inequívoca um veículo.';
COMMENT ON COLUMN sete.veiculos.ipva IS 'Variável numérica que indica o valor do IPVA. Pode ser nula ou igual a 0.';
COMMENT ON COLUMN sete.veiculos.is_state IS 'Campo antigo (desconsiderar)';
COMMENT ON COLUMN sete.veiculos.km_atual IS 'Variável numérica que representa a quilometragem atual do veículo';
COMMENT ON COLUMN sete.veiculos.km_inicial IS 'Variável numérica que representa a quilometragem inicial do veículo';
COMMENT ON COLUMN sete.veiculos.manutencao IS 'Variável binária (S/N) que indica se o veículo está ou não em manutenção';
COMMENT ON COLUMN sete.veiculos.marca IS 'Variável numérica que indica a marca do veículo. Possíveis valores: 1 = Iveco 2 = Mercedes-Benz 3 = Renault 4 = Volkswagen 5 = Volare 6 = EMGEPRON (Empresa Gerencial de Projetos Navais) 7 = ESTALEIRO B3 8 = Yamaha 10 = Outra 11 = SCANIA 12 = MAN 12 = CHEVROLET 14 = FIAT 15 = FORD 16 = HYUNDAI 17 = KIA 18 = TOYOTA 19 = AGRALE 20 = VOLVO';
COMMENT ON COLUMN sete.veiculos.modelo IS 'Variável numérica que indica o modelo do veículo (incluindo veículos do programa Caminho da Escola). Todos os valores diferente de 0 indicam veículos do programa Caminho da Escola. Valores possíveis 0 = Não se aplica 1 = ORE 1 2 = ORE 1 (4x4) 3 = ORE 2 4= ORE 3 6 = ONUREA 7 = Lancha a Gasolina 8 = Lancha a Diesel';
COMMENT ON COLUMN sete.veiculos.modo IS 'Variável numérica que representa o modo do Veículo. Possíveis valores: 0 = Rodoviário 1 = Aquaviário';
COMMENT ON COLUMN sete.veiculos.numero_de_pneus IS 'Variável numérica que indica o número de pneus';
COMMENT ON COLUMN sete.veiculos.origem IS 'Variável numérica que representa quem é dono do Veículo. Possíveis valores: 1 = Veículo Próprio 2 = Veículo Terceirizado';
COMMENT ON COLUMN sete.veiculos.placa IS 'Placa do Veículo (Caracteres)';
COMMENT ON COLUMN sete.veiculos.potencia_do_motor IS 'Variável numérica que indica a potência do motor em cavalos';
COMMENT ON COLUMN sete.veiculos.preco IS 'Variável numérica que indica o preço do veículo';
COMMENT ON COLUMN sete.veiculos.renavam IS 'Variável mista, com números e caracteres, com o renavam do veículo';
COMMENT ON COLUMN sete.veiculos.seguro_anual IS 'Variável numérica que indica o valor do seguro. Pode ser nula ou igual a 0.';
COMMENT ON COLUMN sete.veiculos.tipo IS 'Variável numérica que representa o tipo do veículo. Valores possíveis são: 1 = Ônibus 2 = Micro-ônibus 3 = Van 4 = Kombi 5 = Caminhão 6 = Caminhonete 7 = Motocicleta 8 = Animal de tração 9 = Lancha/Voadeira 10 = Barco de Madeira 11 = Barco de alumínio 12 = Canoa motorizada 13 = Canoa a remo 14 = Bicicleta 99 = Outro';
COMMENT ON COLUMN sete.veiculos.tipo_combustivel IS 'Variável categórica que indica o tipo de veículo utilizado. Possíveis valores: G = Gasolina D = Diesel E = Etanol N = Gás Natural O = Outro';
COMMENT ON COLUMN sete.veiculos.vida_util_do_pneu IS 'Variável numérica que indica a vida útil dos pneus em km rodado';
CREATE INDEX IF NOT EXISTS idx_sete_veiculos_uf ON sete.veiculos (ano_carga, uf);
CREATE INDEX IF NOT EXISTS idx_sete_veiculos_0 ON sete.veiculos (ano_carga, codigo_cidade, id_veiculo);

-- Vínculo rota × escola (chave: codigo_cidade + id_rota / id_escola).
CREATE TABLE IF NOT EXISTS sete.rota_passa_por_escolas (
    ano_carga smallint NOT NULL DEFAULT 2026,
    id_rota integer,
    id_escola integer,
    codigo_cidade integer,
    nome_cidade text,
    uf varchar(2),
    estado text
);
COMMENT ON TABLE sete.rota_passa_por_escolas IS 'Vínculo rota × escola (chave: codigo_cidade + id_rota / id_escola). Fonte: data/Transporte Escolar/script_15_rota_passa_por_escolas_consolidado.csv.';
COMMENT ON COLUMN sete.rota_passa_por_escolas.ano_carga IS 'Ano de referência da carga do dado.';
CREATE INDEX IF NOT EXISTS idx_sete_rota_passa_por_escolas_uf ON sete.rota_passa_por_escolas (ano_carga, uf);
CREATE INDEX IF NOT EXISTS idx_sete_rota_passa_por_escolas_0 ON sete.rota_passa_por_escolas (ano_carga, codigo_cidade, id_rota);
CREATE INDEX IF NOT EXISTS idx_sete_rota_passa_por_escolas_1 ON sete.rota_passa_por_escolas (ano_carga, codigo_cidade, id_escola);

-- Ordens de serviço (manutenção, combustível etc.) vinculadas a veículos e fornecedores.
CREATE TABLE IF NOT EXISTS sete.ordem_servico (
    ano_carga smallint NOT NULL DEFAULT 2026,
    codigo_cidade integer,
    nome_cidade text,
    uf varchar(2),
    estado text,
    id_fornecedor integer,
    id_veiculo integer,
    termino char(1),
    data timestamp,
    tipo_servico smallint,
    comentario text,
    id_ordem integer,
    id_firebase text,
    is_state text
);
COMMENT ON TABLE sete.ordem_servico IS 'Ordens de serviço (manutenção, combustível etc.) vinculadas a veículos e fornecedores. Fonte: data/Transporte Escolar/script_11_ordem_servico_consolidado.csv.';
COMMENT ON COLUMN sete.ordem_servico.ano_carga IS 'Ano de referência da carga do dado.';
CREATE INDEX IF NOT EXISTS idx_sete_ordem_servico_uf ON sete.ordem_servico (ano_carga, uf);
CREATE INDEX IF NOT EXISTS idx_sete_ordem_servico_0 ON sete.ordem_servico (ano_carga, codigo_cidade, id_ordem);
CREATE INDEX IF NOT EXISTS idx_sete_ordem_servico_1 ON sete.ordem_servico (ano_carga, codigo_cidade, id_veiculo);

-- Escolas atendidas pelo transporte escolar cadastradas no SETE.
CREATE TABLE IF NOT EXISTS sete.escolas (
    ano_carga smallint NOT NULL DEFAULT 2026,
    codigo_cidade integer,
    nome_cidade text,
    uf varchar(2),
    estado text,
    id_escola integer,
    nome text,
    mec_co_entidade bigint,
    mec_co_uf smallint,
    mec_co_municipio integer,
    mec_no_entidade text,
    mec_tp_dependencia smallint,
    mec_tp_localizacao smallint,
    mec_in_regular char(1),
    mec_in_eja char(1),
    mec_in_profissionalizante char(1),
    mec_in_especial_exclusiva char(1),
    loc_latitude double precision,
    loc_longitude double precision,
    loc_cep text,
    loc_endereco text,
    contato_responsavel text,
    contato_telefone text,
    contato_email text,
    horario_matutino char(1),
    horario_vespertino char(1),
    horario_noturno char(1),
    ensino_superior char(1),
    ensino_medio char(1),
    ensino_fundamental char(1),
    ensino_pre_escola char(1),
    mec_tp_localizacao_diferenciada smallint,
    codigo_escola_firebase text,
    alterado_por text,
    dt_criacao timestamp,
    criado_por text,
    dt_alteracao timestamp,
    horario_integral char(1),
    informacoes_adicionais jsonb,
    nome_unidade_anexa text,
    tipo_unidade text
);
COMMENT ON TABLE sete.escolas IS 'Escolas atendidas pelo transporte escolar cadastradas no SETE. Fonte: data/Transporte Escolar/script_02_escolas_consolidado.csv.';
COMMENT ON COLUMN sete.escolas.ano_carga IS 'Ano de referência da carga do dado.';
COMMENT ON COLUMN sete.escolas.alterado_por IS 'Email do usuário que alterou os dados da escola';
COMMENT ON COLUMN sete.escolas.codigo_cidade IS 'ID numérico (7 dígitos) do município no IBGE';
COMMENT ON COLUMN sete.escolas.codigo_escola_firebase IS 'Campo antigo (desconsiderar)';
COMMENT ON COLUMN sete.escolas.contato_responsavel IS 'Nome do responsável';
COMMENT ON COLUMN sete.escolas.contato_telefone IS 'Telefone do responsável';
COMMENT ON COLUMN sete.escolas.criado_por IS 'Email do usuário que registrou os dados da escola no sistema';
COMMENT ON COLUMN sete.escolas.dt_alteracao IS 'Quando a escola foi alterada. Os dados anteriores a 2024 estão NULOS';
COMMENT ON COLUMN sete.escolas.dt_criacao IS 'Quando a escola foi criada. Os dados anteriores a 2024 estão NULOS';
COMMENT ON COLUMN sete.escolas.ensino_fundamental IS 'Variável binária (S/N) que indica se a escola fornece ensino fundamental';
COMMENT ON COLUMN sete.escolas.ensino_medio IS 'Variável binária (S/N) que indica se a escola fornece ensino médio';
COMMENT ON COLUMN sete.escolas.ensino_pre_escola IS 'Variável binária (S/N) que indica se a escola fornece ensino infantil';
COMMENT ON COLUMN sete.escolas.ensino_superior IS 'Variável binária (S/N) que indica se a escola fornece ensino superior';
COMMENT ON COLUMN sete.escolas.horario_integral IS 'Variável binária (S/N) que indica se a escola funciona de forma integral';
COMMENT ON COLUMN sete.escolas.horario_matutino IS 'Variável binária (S/N) que indica se a escola funciona pela manhã';
COMMENT ON COLUMN sete.escolas.horario_noturno IS 'Variável binária (S/N) que indica se a escola funciona a noite';
COMMENT ON COLUMN sete.escolas.horario_vespertino IS 'Variável binária (S/N) que indica se a escola funciona pela tarde';
COMMENT ON COLUMN sete.escolas.id_escola IS 'ID interno do SETE para representar uma determinada escola de um município. Não é global, isto é, tem que ser combinado com o ID da cidade para representar de forma inequívoca uma escola.';
COMMENT ON COLUMN sete.escolas.informacoes_adicionais IS 'Campo texto com JSON indicando se a escola possui regime de ensino para quilombola, indígena e educação no campo, bem como outras modalidades de ensino (“ensino_outro”) além de fundunamental, médio ou superior.';
COMMENT ON COLUMN sete.escolas.loc_cep IS 'CEP da escola';
COMMENT ON COLUMN sete.escolas.loc_latitude IS 'Latitude da escola';
COMMENT ON COLUMN sete.escolas.loc_longitude IS 'Longitude da escola';
COMMENT ON COLUMN sete.escolas.mec_co_entidade IS 'Código INEP da escola (8 dígitos)';
COMMENT ON COLUMN sete.escolas.mec_co_municipio IS 'ID numérico (7 dígitos) do município, equivalente a codigo_cidade';
COMMENT ON COLUMN sete.escolas.mec_co_uf IS 'Código INEP da unidade da federação';
COMMENT ON COLUMN sete.escolas.mec_in_eja IS 'Variável binária (S/N) que indica se a escola possui o regime de ensino EJA';
COMMENT ON COLUMN sete.escolas.mec_in_especial_exclusiva IS 'Variável binária (S/N) que indica se a escola possui o regime de ensino para crianças especiasi';
COMMENT ON COLUMN sete.escolas.mec_in_profissionalizante IS 'Variável binária (S/N) que indica se a escola possui o regime de ensino profissionalizante';
COMMENT ON COLUMN sete.escolas.mec_in_regular IS 'Variável binária (S/N) que indica se a escola possui o regime de ensino regular';
COMMENT ON COLUMN sete.escolas.mec_no_entidade IS 'Nome da escola (texto), equivalente ao campo nome';
COMMENT ON COLUMN sete.escolas.mec_tp_dependencia IS 'Tipo da dependência da escola. Campo numérico com um dos seguintes valores: 1 = Federal 2 = Estadual 3 = Municipal 4 = Privada/Conveniada';
COMMENT ON COLUMN sete.escolas.mec_tp_localizacao IS 'Localização da escola. Campo numérico com um dos seguintes valores: 1 = Área Urbana 2 = Área Rural 3 = Área de Assentamento 4 = Terra Indígena 5 = Área Remanescente de Quilombo 6 = Outros Povos ou Comunidade Tradicionais';
COMMENT ON COLUMN sete.escolas.mec_tp_localizacao_diferenciada IS 'Campo antigo (desconsiderar)';
COMMENT ON COLUMN sete.escolas.nome IS 'Nome da escola (texto)';
COMMENT ON COLUMN sete.escolas.nome_unidade_anexa IS 'Nome da unidade anexa, caso a escola seja uma unidade anexa';
COMMENT ON COLUMN sete.escolas.tipo_unidade IS 'Campo que identifica se a unidade escolar é a MATRIZ ou ANEXA.';
CREATE INDEX IF NOT EXISTS idx_sete_escolas_uf ON sete.escolas (ano_carga, uf);
CREATE INDEX IF NOT EXISTS idx_sete_escolas_0 ON sete.escolas (ano_carga, codigo_cidade, id_escola);

-- Vínculo rota × aluno (chave: codigo_cidade + id_rota / id_aluno).
CREATE TABLE IF NOT EXISTS sete.rota_atende_aluno (
    ano_carga smallint NOT NULL DEFAULT 2026,
    id_rota integer,
    id_aluno integer,
    codigo_cidade integer,
    nome_cidade text,
    uf varchar(2),
    estado text
);
COMMENT ON TABLE sete.rota_atende_aluno IS 'Vínculo rota × aluno (chave: codigo_cidade + id_rota / id_aluno). Fonte: data/Transporte Escolar/script_13_rota_atende_aluno_consolidado.csv.';
COMMENT ON COLUMN sete.rota_atende_aluno.ano_carga IS 'Ano de referência da carga do dado.';
CREATE INDEX IF NOT EXISTS idx_sete_rota_atende_aluno_uf ON sete.rota_atende_aluno (ano_carga, uf);
CREATE INDEX IF NOT EXISTS idx_sete_rota_atende_aluno_0 ON sete.rota_atende_aluno (ano_carga, codigo_cidade, id_rota);
CREATE INDEX IF NOT EXISTS idx_sete_rota_atende_aluno_1 ON sete.rota_atende_aluno (ano_carga, codigo_cidade, id_aluno);

-- Vínculo escola × aluno (chave: codigo_cidade + id_escola / id_aluno).
CREATE TABLE IF NOT EXISTS sete.escola_tem_aluno (
    ano_carga smallint NOT NULL DEFAULT 2026,
    id_escola integer,
    id_aluno integer,
    codigo_cidade integer,
    nome_cidade text,
    uf varchar(2),
    estado text
);
COMMENT ON TABLE sete.escola_tem_aluno IS 'Vínculo escola × aluno (chave: codigo_cidade + id_escola / id_aluno). Fonte: data/Transporte Escolar/script_12_escola_tem_aluno_consolidado.csv.';
COMMENT ON COLUMN sete.escola_tem_aluno.ano_carga IS 'Ano de referência da carga do dado.';
CREATE INDEX IF NOT EXISTS idx_sete_escola_tem_aluno_uf ON sete.escola_tem_aluno (ano_carga, uf);
CREATE INDEX IF NOT EXISTS idx_sete_escola_tem_aluno_0 ON sete.escola_tem_aluno (ano_carga, codigo_cidade, id_escola);
CREATE INDEX IF NOT EXISTS idx_sete_escola_tem_aluno_1 ON sete.escola_tem_aluno (ano_carga, codigo_cidade, id_aluno);

-- Alunos usuários do transporte escolar cadastrados no SETE.
CREATE TABLE IF NOT EXISTS sete.alunos (
    ano_carga smallint NOT NULL DEFAULT 2026,
    codigo_cidade integer,
    nome_cidade text,
    uf varchar(2),
    estado text,
    id_aluno integer,
    loc_latitude double precision,
    loc_longitude double precision,
    da_porteira char(1),
    da_mataburro char(1),
    da_colchete char(1),
    da_atoleiro char(1),
    da_ponterustica char(1),
    idade integer,
    sexo smallint,
    cor smallint,
    grau_responsavel smallint,
    def_caminhar char(1),
    def_ouvir char(1),
    def_enxergar char(1),
    def_mental char(1),
    turno smallint,
    nivel smallint,
    dt_criacao timestamp,
    dt_alteracao timestamp
);
COMMENT ON TABLE sete.alunos IS 'Alunos usuários do transporte escolar cadastrados no SETE. Fonte: data/Transporte Escolar/script_01_alunos_consolidado.csv.';
COMMENT ON COLUMN sete.alunos.ano_carga IS 'Ano de referência da carga do dado.';
COMMENT ON COLUMN sete.alunos.codigo_cidade IS 'ID numérico (7 dígitos) do município no IBGE';
COMMENT ON COLUMN sete.alunos.cor IS 'Variável numérica que indica a cor do estudante. Valores possíveis: 1 = Branco 2 = Preto 3 = Pardo 4 = Amarelo 5 = Indígena 0 = Não declarada';
COMMENT ON COLUMN sete.alunos.da_atoleiro IS 'Variável binária (S/N) que indica se há dificuldade de acesso (atoleiro) para o aluno';
COMMENT ON COLUMN sete.alunos.da_colchete IS 'Variável binária (S/N) que indica se há dificuldade de acesso (colchete) para o aluno';
COMMENT ON COLUMN sete.alunos.da_mataburro IS 'Variável binária (S/N) que indica se há dificuldade de acesso (mata-burro) para o aluno';
COMMENT ON COLUMN sete.alunos.da_ponterustica IS 'Variável binária (S/N) que indica se há dificuldade de acesso (ponte rústica) para o aluno';
COMMENT ON COLUMN sete.alunos.da_porteira IS 'Variável binária (S/N) que indica se há dificuldade de acesso (porteira) para o aluno';
COMMENT ON COLUMN sete.alunos.def_caminhar IS 'Variável binária (S/N) que indica se o discente tem deficiência física';
COMMENT ON COLUMN sete.alunos.def_enxergar IS 'Variável binária (S/N) que indica se o discente tem deficiência visual';
COMMENT ON COLUMN sete.alunos.def_mental IS 'Variável binária (S/N) que indica se o discente tem deficiência mental ou';
COMMENT ON COLUMN sete.alunos.def_ouvir IS 'Variável binária (S/N) que indica se o discente tem deficiência auditiva';
COMMENT ON COLUMN sete.alunos.dt_alteracao IS 'Quando o dado do aluno foi alterado. Os dados anteriores a 2024 estão NULOS';
COMMENT ON COLUMN sete.alunos.dt_criacao IS 'Quando o dado do aluno foi criado. Os dados anteriores a 2024 estão NULOS';
COMMENT ON COLUMN sete.alunos.grau_responsavel IS 'Variável numérica indicando o grau de parentesco do responsável pelo estudante. Valores possíveis: -1 = Não informado 0 = Pai, Mãe, Padrasto ou Madrasta 1 = Avô ou Avó 2 = Irmão ou Irmã 4 = Outro Parente';
COMMENT ON COLUMN sete.alunos.id_aluno IS 'ID interno do SETE para representar um determinado aluno de um município. Não é global, isto é, tem que ser combinado com o ID da cidade para representar de forma inequívoca um discente.';
COMMENT ON COLUMN sete.alunos.idade IS 'Variável numérica indicando a Idade do estudante. Note que há campos com erros, tendo algumas idades negativas.';
COMMENT ON COLUMN sete.alunos.loc_latitude IS 'Latitude do aluno';
COMMENT ON COLUMN sete.alunos.loc_longitude IS 'Longitude do aluno';
COMMENT ON COLUMN sete.alunos.nivel IS 'Variável numérica que indica o nível do estudante. Valores possíveis: 1 = Infantil / Pré-escola 2 = Fundamental 3 = Médio 4 = Superior 5 = Outro';
COMMENT ON COLUMN sete.alunos.sexo IS 'Variável numérica que indica o sexo do estudante. Valores possíveis: 1 = Masculino 2 = Feminino 3 = Não informado';
COMMENT ON COLUMN sete.alunos.turno IS 'Variável numérica que indica o turno do estudante. Valores possíveis: 1 = Manhã 2 = Tarde 3 = Noite 4 = Manhã e Tarde (Integral)';
CREATE INDEX IF NOT EXISTS idx_sete_alunos_uf ON sete.alunos (ano_carga, uf);
CREATE INDEX IF NOT EXISTS idx_sete_alunos_0 ON sete.alunos (ano_carga, codigo_cidade, id_aluno);

-- Rotas do transporte escolar cadastradas no SETE (o traçado fica em sete.rota_shape).
CREATE TABLE IF NOT EXISTS sete.rotas (
    ano_carga smallint NOT NULL DEFAULT 2026,
    codigo_cidade integer,
    nome_cidade text,
    uf varchar(2),
    estado text,
    id_rota integer,
    nome text,
    km numeric,
    da_porteira char(1),
    da_mataburro char(1),
    da_colchete char(1),
    da_atoleiro char(1),
    da_ponterustica char(1),
    turno_matutino char(1),
    turno_vespertino char(1),
    turno_noturno char(1),
    tempo numeric,
    tipo smallint,
    ativo smallint,
    tem_shape boolean
);
COMMENT ON TABLE sete.rotas IS 'Rotas do transporte escolar cadastradas no SETE (o traçado fica em sete.rota_shape). Fonte: data/Transporte Escolar/script_03_rotas_consolidado.csv.';
COMMENT ON COLUMN sete.rotas.ano_carga IS 'Ano de referência da carga do dado.';
COMMENT ON COLUMN sete.rotas.ativo IS 'Valor numérico que indica se a rota está ativa ou não. 1 = Ativa 0 = Não ativa';
COMMENT ON COLUMN sete.rotas.codigo_cidade IS 'ID numérico (7 dígitos) do município no IBGE';
COMMENT ON COLUMN sete.rotas.da_atoleiro IS 'Variável binária (S/N) que indica se há dificuldade de acesso (atoleiro) para a rota';
COMMENT ON COLUMN sete.rotas.da_colchete IS 'Variável binária (S/N) que indica se há dificuldade de acesso (colchete) para a rota';
COMMENT ON COLUMN sete.rotas.da_mataburro IS 'Variável binária (S/N) que indica se há dificuldade de acesso (mata-burro) para a rota';
COMMENT ON COLUMN sete.rotas.da_ponterustica IS 'Variável binária (S/N) que indica se há dificuldade de acesso (ponte rústica) para a rota';
COMMENT ON COLUMN sete.rotas.da_porteira IS 'Variável binária (S/N) que indica se há dificuldade de acesso (porteira) para a rota';
COMMENT ON COLUMN sete.rotas.id_rota IS 'ID interno do SETE para representar uma determinada rota de um município. Não é global, isto é, tem que ser combinado com o ID da cidade para representar de forma inequívoca uma rota.';
COMMENT ON COLUMN sete.rotas.km IS 'Quilometragem da rota';
COMMENT ON COLUMN sete.rotas.nome IS 'Nome da Rota';
COMMENT ON COLUMN sete.rotas.tempo IS 'Tempo da rota em minutos';
COMMENT ON COLUMN sete.rotas.tipo IS 'Variável numérica que indica o tipo da rota. Tipo da Rota: 1 = Rodoviário 2 = Aquaviário 3 = Mista';
COMMENT ON COLUMN sete.rotas.turno_matutino IS 'Variável binária (S/N) que indica se a rota funciona pela manhã';
COMMENT ON COLUMN sete.rotas.turno_noturno IS 'Variável binária (S/N) que indica se a rota funciona a noite';
COMMENT ON COLUMN sete.rotas.turno_vespertino IS 'Variável binária (S/N) que indica se a rota funciona pela tarde';
COMMENT ON COLUMN sete.rotas.tem_shape IS 'Rota georreferenciada: shape não nulo, não vazio e diferente de NULL (regra do PRGM).';
CREATE INDEX IF NOT EXISTS idx_sete_rotas_uf ON sete.rotas (ano_carga, uf);
CREATE INDEX IF NOT EXISTS idx_sete_rotas_0 ON sete.rotas (ano_carga, codigo_cidade, id_rota);

-- Traçado (GeoJSON) das rotas, separado por volume (~1,9 GB no CSV).
CREATE TABLE IF NOT EXISTS sete.rota_shape (
    ano_carga smallint NOT NULL DEFAULT 2026,
    codigo_cidade integer,
    uf varchar(2),
    id_rota integer,
    shape text
);
ALTER TABLE sete.rota_shape ALTER COLUMN shape SET COMPRESSION lz4;
COMMENT ON TABLE sete.rota_shape IS 'Traçado GeoJSON das rotas do SETE (coluna shape de script_03_rotas).';
CREATE INDEX IF NOT EXISTS idx_sete_rota_shape_0 ON sete.rota_shape (ano_carga, codigo_cidade, id_rota);
CREATE INDEX IF NOT EXISTS idx_sete_rota_shape_uf ON sete.rota_shape (ano_carga, uf);
