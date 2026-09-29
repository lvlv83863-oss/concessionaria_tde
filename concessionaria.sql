DROP VIEW  IF EXISTS vw_os_pecas            CASCADE;
DROP VIEW  IF EXISTS vw_mecanico_veiculo    CASCADE;
DROP VIEW  IF EXISTS vw_historico_veiculo   CASCADE;
DROP VIEW  IF EXISTS vw_ordens_servico      CASCADE;
DROP VIEW  IF EXISTS vw_clientes_perfil     CASCADE;
DROP VIEW  IF EXISTS vw_faturas             CASCADE;
DROP VIEW  IF EXISTS vw_vendas              CASCADE;

DROP TABLE IF EXISTS hmn_historico_manutencao CASCADE;
DROP TABLE IF EXISTS osp_os_peca              CASCADE;
DROP TABLE IF EXISTS osm_os_mecanico          CASCADE;
DROP TABLE IF EXISTS ors_ordem_servico        CASCADE;
DROP TABLE IF EXISTS fat_fatura               CASCADE;
DROP TABLE IF EXISTS vnd_venda                CASCADE;
DROP TABLE IF EXISTS pec_peca                 CASCADE;
DROP TABLE IF EXISTS vei_veiculo              CASCADE;
DROP TABLE IF EXISTS mec_mecanico             CASCADE;
DROP TABLE IF EXISTS ven_vendedor             CASCADE;
DROP TABLE IF EXISTS cli_cliente              CASCADE;

-- [[PG-ONLY-BEGIN]]
DROP FUNCTION IF EXISTS fn_vnd_valida_veiculo()     CASCADE;
DROP FUNCTION IF EXISTS fn_ors_valida_conclusao()   CASCADE;
DROP FUNCTION IF EXISTS fn_hmn_gera_sequencia()     CASCADE;
-- [[PG-ONLY-END]]


-- =====================================================================
-- 1. TABELAS INDEPENDENTES
-- =====================================================================

-- Clientes: compradores de veículos e/ou clientes exclusivos da oficina
CREATE TABLE cli_cliente (
    cli_id            SERIAL        PRIMARY KEY,
    cli_nome          VARCHAR(80)   NOT NULL,
    cli_cpf           CHAR(11)      NOT NULL,
    cli_dtnascimento  DATE,
    cli_fone          VARCHAR(20)   NOT NULL,
    cli_email         VARCHAR(80),
    cli_endereco      VARCHAR(200),
    cli_dtcadastro    DATE          NOT NULL DEFAULT CURRENT_DATE,
    CONSTRAINT uk_cliente_cpf   UNIQUE (cli_cpf),
    CONSTRAINT uk_cliente_email UNIQUE (cli_email),
    CONSTRAINT ck_cliente_cpf   CHECK (cli_cpf ~ '^[0-9]{11}$'),
    CONSTRAINT ck_cliente_email CHECK (cli_email LIKE '%_@_%')
);

-- Vendedores: emitem as faturas e realizam as vendas
CREATE TABLE ven_vendedor (
    ven_id            SMALLSERIAL   PRIMARY KEY,
    ven_nome          VARCHAR(80)   NOT NULL,
    ven_cpf           CHAR(11)      NOT NULL,
    ven_fone          VARCHAR(20)   NOT NULL,
    ven_email         VARCHAR(80),
    ven_dtadmissao    DATE          NOT NULL,
    ven_percomissao   DECIMAL(5,2)  NOT NULL DEFAULT 0,
    CONSTRAINT uk_vendedor_cpf   UNIQUE (ven_cpf),
    CONSTRAINT uk_vendedor_email UNIQUE (ven_email),
    CONSTRAINT ck_vendedor_cpf   CHECK (ven_cpf ~ '^[0-9]{11}$'),
    CONSTRAINT ck_vendedor_comissao
        CHECK (ven_percomissao BETWEEN 0 AND 100)
);

-- Mecânicos: executam as ordens de serviço
CREATE TABLE mec_mecanico (
    mec_id            SMALLSERIAL   PRIMARY KEY,
    mec_nome          VARCHAR(80)   NOT NULL,
    mec_cpf           CHAR(11)      NOT NULL,
    mec_fone          VARCHAR(20)   NOT NULL,
    mec_email         VARCHAR(80),
    mec_especialidade VARCHAR(40),
    mec_dtadmissao    DATE          NOT NULL,
    CONSTRAINT uk_mecanico_cpf   UNIQUE (mec_cpf),
    CONSTRAINT uk_mecanico_email UNIQUE (mec_email),
    CONSTRAINT ck_mecanico_cpf   CHECK (mec_cpf ~ '^[0-9]{11}$')
);

-- Veículos: estoque (novos/usados), vendidos e de clientes só da oficina.
-- O número de série (chassi, 17 caracteres) é a chave primária, pois
-- identifica o veículo e o seu histórico de manutenção.
CREATE TABLE vei_veiculo (
    vei_numserie      CHAR(17)      PRIMARY KEY,
    vei_marca         VARCHAR(30)   NOT NULL,
    vei_modelo        VARCHAR(40)   NOT NULL,
    vei_anofabricacao SMALLINT      NOT NULL,
    vei_anomodelo     SMALLINT      NOT NULL,
    vei_cor           VARCHAR(20)   NOT NULL,
    vei_placa         CHAR(7),
    vei_condicao      VARCHAR(5)    NOT NULL,
    vei_km            INTEGER       NOT NULL DEFAULT 0,
    vei_precotabela   DECIMAL(12,2),
    vei_situacao      VARCHAR(15)   NOT NULL DEFAULT 'Disponível',
    vei_dtcadastro    DATE          NOT NULL DEFAULT CURRENT_DATE,
    CONSTRAINT uk_veiculo_placa    UNIQUE (vei_placa),
    CONSTRAINT ck_veiculo_numserie CHECK (char_length(vei_numserie) = 17),
    CONSTRAINT ck_veiculo_placa
        CHECK (vei_placa IS NULL OR vei_placa ~ '^[A-Z]{3}[0-9][A-Z0-9][0-9]{2}$'),
    CONSTRAINT ck_veiculo_anofab   CHECK (vei_anofabricacao >= 1950),
    CONSTRAINT ck_veiculo_anomodelo
        CHECK (vei_anomodelo BETWEEN vei_anofabricacao AND vei_anofabricacao + 1),
    CONSTRAINT ck_veiculo_condicao CHECK (vei_condicao IN ('Novo', 'Usado')),
    CONSTRAINT ck_veiculo_km       CHECK (vei_km >= 0),
    CONSTRAINT ck_veiculo_preco
        CHECK (vei_precotabela IS NULL OR vei_precotabela > 0),
    CONSTRAINT ck_veiculo_situacao
        CHECK (vei_situacao IN ('Disponível', 'Vendido', 'Externo'))
);

-- Peças utilizadas nas ordens de serviço
CREATE TABLE pec_peca (
    pec_id            SERIAL        PRIMARY KEY,
    pec_codigo        VARCHAR(20)   NOT NULL,
    pec_nome          VARCHAR(60)   NOT NULL,
    pec_descricao     VARCHAR(200),
    pec_fabricante    VARCHAR(40),
    pec_precounit     DECIMAL(10,2) NOT NULL,
    pec_qtdestoque    INTEGER       NOT NULL DEFAULT 0,
    CONSTRAINT uk_peca_codigo   UNIQUE (pec_codigo),
    CONSTRAINT ck_peca_preco    CHECK (pec_precounit >= 0),
    CONSTRAINT ck_peca_estoque  CHECK (pec_qtdestoque >= 0)
);


-- =====================================================================
-- 2. VENDAS E FATURAMENTO
-- =====================================================================

-- Venda (negociação): liga UM veículo a UM cliente e UM vendedor
CREATE TABLE vnd_venda (
    vnd_id             SERIAL        PRIMARY KEY,
    vnd_vei_numserie   CHAR(17)      NOT NULL,
    vnd_cli_id         INTEGER       NOT NULL,
    vnd_ven_id         SMALLINT      NOT NULL,
    vnd_dtvenda        DATE          NOT NULL,
    vnd_valor          DECIMAL(12,2) NOT NULL,
    vnd_formapagamento VARCHAR(20)   NOT NULL,
    CONSTRAINT fk_venda_veiculo
        FOREIGN KEY (vnd_vei_numserie) REFERENCES vei_veiculo (vei_numserie),
    CONSTRAINT fk_venda_cliente
        FOREIGN KEY (vnd_cli_id)       REFERENCES cli_cliente (cli_id),
    CONSTRAINT fk_venda_vendedor
        FOREIGN KEY (vnd_ven_id)       REFERENCES ven_vendedor (ven_id),
    -- cada carro é vendido para um único cliente e por um único vendedor
    CONSTRAINT uk_venda_veiculo UNIQUE (vnd_vei_numserie),
    CONSTRAINT ck_venda_valor   CHECK (vnd_valor > 0),
    CONSTRAINT ck_venda_pagamento
        CHECK (vnd_formapagamento IN
               ('À Vista', 'Financiamento', 'Consórcio', 'Cartão de Crédito'))
);

-- Fatura: uma única fatura por venda, entregue ao cliente da venda
CREATE TABLE fat_fatura (
    fat_id            SERIAL        PRIMARY KEY,
    fat_numero        VARCHAR(20)   NOT NULL,
    fat_vnd_id        INTEGER       NOT NULL,
    fat_dtemissao     DATE          NOT NULL,
    fat_valortotal    DECIMAL(12,2) NOT NULL,
    fat_situacao      VARCHAR(15)   NOT NULL DEFAULT 'Emitida',
    fat_dtentrega     DATE,
    CONSTRAINT fk_fatura_venda
        FOREIGN KEY (fat_vnd_id) REFERENCES vnd_venda (vnd_id),
    CONSTRAINT uk_fatura_numero UNIQUE (fat_numero),
    CONSTRAINT uk_fatura_venda  UNIQUE (fat_vnd_id),          -- 1 venda : 1 fatura
    CONSTRAINT ck_fatura_valor  CHECK (fat_valortotal > 0),
    CONSTRAINT ck_fatura_situacao
        CHECK (fat_situacao IN ('Emitida', 'Paga', 'Cancelada')),
    CONSTRAINT ck_fatura_entrega
        CHECK (fat_dtentrega IS NULL OR fat_dtentrega >= fat_dtemissao)
);


-- =====================================================================
-- 3. OFICINA: ORDENS DE SERVIÇO, MECÂNICOS, PEÇAS E HISTÓRICO
-- =====================================================================

-- Ordem de serviço: uma para CADA veículo atendido
CREATE TABLE ors_ordem_servico (
    ors_id            SERIAL        PRIMARY KEY,
    ors_cli_id        INTEGER       NOT NULL,
    ors_vei_numserie  CHAR(17)      NOT NULL,
    ors_dtabertura    DATE          NOT NULL DEFAULT CURRENT_DATE,
    ors_dtprevisao    DATE,
    ors_dtconclusao   DATE,
    ors_situacao      VARCHAR(15)   NOT NULL DEFAULT 'Aberta',
    ors_descproblema  VARCHAR(300)  NOT NULL,
    ors_kmentrada     INTEGER       NOT NULL,
    ors_vlrmaodeobra  DECIMAL(10,2) NOT NULL DEFAULT 0,
    CONSTRAINT fk_os_cliente
        FOREIGN KEY (ors_cli_id)       REFERENCES cli_cliente (cli_id),
    CONSTRAINT fk_os_veiculo
        FOREIGN KEY (ors_vei_numserie) REFERENCES vei_veiculo (vei_numserie),
    -- permite a chave estrangeira composta do histórico (mesmo veículo da OS)
    CONSTRAINT uk_os_id_veiculo UNIQUE (ors_id, ors_vei_numserie),
    CONSTRAINT ck_os_situacao
        CHECK (ors_situacao IN ('Aberta', 'Em Andamento', 'Concluída', 'Cancelada')),
    CONSTRAINT ck_os_km          CHECK (ors_kmentrada >= 0),
    CONSTRAINT ck_os_maodeobra   CHECK (ors_vlrmaodeobra >= 0),
    CONSTRAINT ck_os_previsao
        CHECK (ors_dtprevisao IS NULL OR ors_dtprevisao >= ors_dtabertura),
    CONSTRAINT ck_os_conclusao
        CHECK (ors_dtconclusao IS NULL OR ors_dtconclusao >= ors_dtabertura),
    -- data de conclusão preenchida se, e somente se, a OS estiver concluída
    CONSTRAINT ck_os_situacao_conclusao
        CHECK ((ors_situacao = 'Concluída' AND ors_dtconclusao IS NOT NULL)
            OR (ors_situacao <> 'Concluída' AND ors_dtconclusao IS NULL))
);

-- Mecânicos que atuam em cada OS (N:M) -> relaciona mecânicos e veículos
CREATE TABLE osm_os_mecanico (
    osm_ors_id        INTEGER       NOT NULL,
    osm_mec_id        SMALLINT      NOT NULL,
    osm_funcao        VARCHAR(40),
    osm_horas         DECIMAL(5,2),
    CONSTRAINT pk_os_mecanico PRIMARY KEY (osm_ors_id, osm_mec_id),
    CONSTRAINT fk_osm_os
        FOREIGN KEY (osm_ors_id) REFERENCES ors_ordem_servico (ors_id),
    CONSTRAINT fk_osm_mecanico
        FOREIGN KEY (osm_mec_id) REFERENCES mec_mecanico (mec_id),
    CONSTRAINT ck_osm_horas CHECK (osm_horas IS NULL OR osm_horas > 0)
);

-- Peças usadas em cada OS (N:M OPCIONAL: uma OS pode não ter nenhuma linha aqui)
CREATE TABLE osp_os_peca (
    osp_ors_id        INTEGER       NOT NULL,
    osp_pec_id        INTEGER       NOT NULL,
    osp_quantidade    INTEGER       NOT NULL,
    osp_precounit     DECIMAL(10,2) NOT NULL,    -- preço praticado na data da OS
    CONSTRAINT pk_os_peca PRIMARY KEY (osp_ors_id, osp_pec_id),
    CONSTRAINT fk_osp_os
        FOREIGN KEY (osp_ors_id) REFERENCES ors_ordem_servico (ors_id),
    CONSTRAINT fk_osp_peca
        FOREIGN KEY (osp_pec_id) REFERENCES pec_peca (pec_id),
    CONSTRAINT ck_osp_quantidade CHECK (osp_quantidade > 0),
    CONSTRAINT ck_osp_preco      CHECK (osp_precounit >= 0)
);

-- Histórico de manutenção: entidade fraca identificada pelo número de série
-- do veículo + sequência. Cada registro nasce de uma OS.
CREATE TABLE hmn_historico_manutencao (
    hmn_vei_numserie  CHAR(17)      NOT NULL,
    hmn_seq           INTEGER       NOT NULL,
    hmn_ors_id        INTEGER       NOT NULL,
    hmn_tipo          VARCHAR(20)   NOT NULL,
    hmn_descricao     VARCHAR(300)  NOT NULL,
    hmn_dtservico     DATE          NOT NULL,
    hmn_km            INTEGER       NOT NULL,
    CONSTRAINT pk_historico PRIMARY KEY (hmn_vei_numserie, hmn_seq),
    CONSTRAINT fk_hmn_veiculo
        FOREIGN KEY (hmn_vei_numserie) REFERENCES vei_veiculo (vei_numserie),
    -- garante que a OS informada pertence ao MESMO veículo do histórico
    CONSTRAINT fk_hmn_os
        FOREIGN KEY (hmn_ors_id, hmn_vei_numserie)
        REFERENCES ors_ordem_servico (ors_id, ors_vei_numserie),
    CONSTRAINT uk_hmn_os   UNIQUE (hmn_ors_id),                -- 1 OS : 1 registro
    CONSTRAINT ck_hmn_seq  CHECK (hmn_seq > 0),
    CONSTRAINT ck_hmn_tipo
        CHECK (hmn_tipo IN ('Revisão', 'Reparo', 'Ajuste', 'Limpeza', 'Outro')),
    CONSTRAINT ck_hmn_km   CHECK (hmn_km >= 0)
);


-- =====================================================================
-- 4. ÍNDICES (colunas de chave estrangeira e consultas frequentes)
-- =====================================================================

CREATE INDEX idx_venda_cliente    ON vnd_venda (vnd_cli_id);
CREATE INDEX idx_venda_vendedor   ON vnd_venda (vnd_ven_id);
CREATE INDEX idx_os_cliente       ON ors_ordem_servico (ors_cli_id);
CREATE INDEX idx_os_veiculo       ON ors_ordem_servico (ors_vei_numserie);
CREATE INDEX idx_os_situacao      ON ors_ordem_servico (ors_situacao);
CREATE INDEX idx_osm_mecanico     ON osm_os_mecanico (osm_mec_id);
CREATE INDEX idx_osp_peca         ON osp_os_peca (osp_pec_id);
CREATE INDEX idx_veiculo_situacao ON vei_veiculo (vei_situacao);


-- =====================================================================
-- 5. REGRAS DE NEGÓCIO QUE O CHECK NÃO COBRE (funções e gatilhos)
-- =====================================================================
-- [[PG-ONLY-BEGIN]]

-- 5.1 Só é possível vender veículo "Disponível"; após a venda ele passa a "Vendido"
CREATE OR REPLACE FUNCTION fn_vnd_valida_veiculo()
RETURNS TRIGGER AS $$
DECLARE
    v_situacao VARCHAR(15);
BEGIN
    SELECT vei_situacao INTO v_situacao
      FROM vei_veiculo
     WHERE vei_numserie = NEW.vnd_vei_numserie;

    IF v_situacao IS DISTINCT FROM 'Disponível' THEN
        RAISE EXCEPTION 'Veículo % não está disponível para venda (situação: %).',
            NEW.vnd_vei_numserie, COALESCE(v_situacao, 'inexistente');
    END IF;

    UPDATE vei_veiculo
       SET vei_situacao = 'Vendido'
     WHERE vei_numserie = NEW.vnd_vei_numserie;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_vnd_valida_veiculo
    BEFORE INSERT ON vnd_venda
    FOR EACH ROW EXECUTE FUNCTION fn_vnd_valida_veiculo();


-- 5.2 Uma OS só pode ser concluída se ao menos um mecânico tiver atuado nela
CREATE OR REPLACE FUNCTION fn_ors_valida_conclusao()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.ors_situacao = 'Concluída'
       AND NOT EXISTS (SELECT 1
                         FROM osm_os_mecanico
                        WHERE osm_ors_id = NEW.ors_id) THEN
        RAISE EXCEPTION
            'A ordem de serviço % não pode ser concluída sem ao menos um mecânico.',
            NEW.ors_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_ors_valida_conclusao
    BEFORE INSERT OR UPDATE ON ors_ordem_servico
    FOR EACH ROW EXECUTE FUNCTION fn_ors_valida_conclusao();


-- 5.3 Numeração sequencial do histórico por veículo (quando não informada)
CREATE OR REPLACE FUNCTION fn_hmn_gera_sequencia()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.hmn_seq IS NULL THEN
        SELECT COALESCE(MAX(hmn_seq), 0) + 1
          INTO NEW.hmn_seq
          FROM hmn_historico_manutencao
         WHERE hmn_vei_numserie = NEW.hmn_vei_numserie;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_hmn_gera_sequencia
    BEFORE INSERT ON hmn_historico_manutencao
    FOR EACH ROW EXECUTE FUNCTION fn_hmn_gera_sequencia();

-- [[PG-ONLY-END]]


-- =====================================================================
-- 6. VISÕES (consultas e acompanhamento pedidos no enunciado)
-- =====================================================================

-- 6.1 Vendas de veículos: veículo x vendedor x cliente (+ fatura)
CREATE VIEW vw_vendas AS
SELECT v.vnd_id,
       v.vnd_dtvenda,
       ve.vei_numserie,
       ve.vei_marca,
       ve.vei_modelo,
       ve.vei_condicao,
       c.cli_id,
       c.cli_nome,
       vd.ven_id,
       vd.ven_nome,
       v.vnd_valor,
       v.vnd_formapagamento,
       f.fat_numero,
       f.fat_situacao
  FROM vnd_venda v
  JOIN vei_veiculo ve ON ve.vei_numserie = v.vnd_vei_numserie
  JOIN cli_cliente c  ON c.cli_id        = v.vnd_cli_id
  JOIN ven_vendedor vd ON vd.ven_id      = v.vnd_ven_id
  LEFT JOIN fat_fatura f ON f.fat_vnd_id = v.vnd_id;

-- 6.2 Faturamento: faturas e a negociação associada
CREATE VIEW vw_faturas AS
SELECT f.fat_id,
       f.fat_numero,
       f.fat_dtemissao,
       f.fat_dtentrega,
       f.fat_valortotal,
       f.fat_situacao,
       v.vnd_id,
       v.vnd_dtvenda,
       ve.vei_numserie,
       ve.vei_marca,
       ve.vei_modelo,
       vd.ven_nome AS vendedor_emissor,
       c.cli_nome  AS cliente_destinatario
  FROM fat_fatura f
  JOIN vnd_venda v     ON v.vnd_id       = f.fat_vnd_id
  JOIN vei_veiculo ve  ON ve.vei_numserie = v.vnd_vei_numserie
  JOIN ven_vendedor vd ON vd.ven_id      = v.vnd_ven_id
  JOIN cli_cliente c   ON c.cli_id       = v.vnd_cli_id;

-- 6.3 Clientes: compradores, somente oficina, ambos ou sem movimentação
CREATE VIEW vw_clientes_perfil AS
SELECT t.cli_id,
       t.cli_nome,
       t.qtd_veiculos_comprados,
       t.qtd_ordens_servico,
       CASE
           WHEN t.qtd_veiculos_comprados > 0 AND t.qtd_ordens_servico > 0 THEN 'Comprador e Oficina'
           WHEN t.qtd_veiculos_comprados > 0                              THEN 'Somente Comprador'
           WHEN t.qtd_ordens_servico > 0                                  THEN 'Somente Oficina'
           ELSE 'Sem Movimentação'
       END AS cli_perfil
  FROM (SELECT c.cli_id,
               c.cli_nome,
               (SELECT COUNT(*) FROM vnd_venda v
                 WHERE v.vnd_cli_id = c.cli_id)  AS qtd_veiculos_comprados,
               (SELECT COUNT(*) FROM ors_ordem_servico o
                 WHERE o.ors_cli_id = c.cli_id)  AS qtd_ordens_servico
          FROM cli_cliente c) t;

-- 6.4 Ordens de serviço: da abertura à conclusão, com totais calculados
CREATE VIEW vw_ordens_servico AS
SELECT o.ors_id,
       o.ors_dtabertura,
       o.ors_dtprevisao,
       o.ors_dtconclusao,
       o.ors_situacao,
       c.cli_nome,
       ve.vei_numserie,
       ve.vei_marca,
       ve.vei_modelo,
       o.ors_descproblema,
       COALESCE(m.qtd_mecanicos, 0)                          AS qtd_mecanicos,
       CASE WHEN p.qtd_itens IS NULL THEN 'Não' ELSE 'Sim' END AS usa_pecas,
       o.ors_vlrmaodeobra,
       COALESCE(p.total_pecas, 0)                            AS total_pecas,
       o.ors_vlrmaodeobra + COALESCE(p.total_pecas, 0)       AS total_os
  FROM ors_ordem_servico o
  JOIN cli_cliente c  ON c.cli_id        = o.ors_cli_id
  JOIN vei_veiculo ve ON ve.vei_numserie = o.ors_vei_numserie
  LEFT JOIN (SELECT osp_ors_id,
                    COUNT(*)                          AS qtd_itens,
                    SUM(osp_quantidade * osp_precounit) AS total_pecas
               FROM osp_os_peca
              GROUP BY osp_ors_id) p ON p.osp_ors_id = o.ors_id
  LEFT JOIN (SELECT osm_ors_id,
                    COUNT(*) AS qtd_mecanicos
               FROM osm_os_mecanico
              GROUP BY osm_ors_id) m ON m.osm_ors_id = o.ors_id;

-- 6.5 Histórico de manutenção de cada veículo ao longo do tempo
CREATE VIEW vw_historico_veiculo AS
SELECT h.hmn_vei_numserie AS vei_numserie,
       ve.vei_marca,
       ve.vei_modelo,
       h.hmn_seq,
       h.hmn_dtservico,
       h.hmn_tipo,
       h.hmn_descricao,
       h.hmn_km,
       o.ors_id
  FROM hmn_historico_manutencao h
  JOIN vei_veiculo ve      ON ve.vei_numserie = h.hmn_vei_numserie
  JOIN ors_ordem_servico o ON o.ors_id        = h.hmn_ors_id;

-- 6.6 Atuação dos mecânicos: mecânico x veículo x OS
CREATE VIEW vw_mecanico_veiculo AS
SELECT m.mec_id,
       m.mec_nome,
       ve.vei_numserie,
       ve.vei_marca,
       ve.vei_modelo,
       o.ors_id,
       o.ors_situacao,
       om.osm_funcao,
       om.osm_horas
  FROM osm_os_mecanico om
  JOIN mec_mecanico m      ON m.mec_id        = om.osm_mec_id
  JOIN ors_ordem_servico o ON o.ors_id        = om.osm_ors_id
  JOIN vei_veiculo ve      ON ve.vei_numserie = o.ors_vei_numserie;

-- 6.7 Peças por OS (as OS sem peças aparecem com peça NULL)
CREATE VIEW vw_os_pecas AS
SELECT o.ors_id,
       o.ors_situacao,
       ve.vei_numserie,
       p.pec_codigo,
       p.pec_nome,
       op.osp_quantidade,
       op.osp_precounit,
       op.osp_quantidade * op.osp_precounit AS subtotal
  FROM ors_ordem_servico o
  JOIN vei_veiculo ve ON ve.vei_numserie = o.ors_vei_numserie
  LEFT JOIN osp_os_peca op ON op.osp_ors_id = o.ors_id
  LEFT JOIN pec_peca p     ON p.pec_id      = op.osp_pec_id;


-- =====================================================================
-- 7. DADOS DE EXEMPLO
-- =====================================================================

INSERT INTO cli_cliente (cli_nome, cli_cpf, cli_dtnascimento, cli_fone, cli_email, cli_endereco) VALUES
('Ana Souza',      '11111111111', '1990-04-12', '(31) 98888-0001', 'ana.souza@email.com',   'Rua das Acácias, 120 - Contagem/MG'),
('Bruno Lima',     '22222222222', '1985-09-30', '(31) 98888-0002', 'bruno.lima@email.com',  'Av. João César de Oliveira, 500 - Contagem/MG'),
('Carla Mendes',   '33333333333', '1993-01-18', '(31) 98888-0003', NULL,                    'Rua Minas Gerais, 45 - Betim/MG'),
('Diego Ferreira', '44444444444', '1979-11-05', '(31) 98888-0004', 'diego.f@email.com',     NULL),
('Elaine Rocha',   '55555555555', NULL,         '(31) 98888-0005', 'elaine.rocha@email.com', NULL);

INSERT INTO ven_vendedor (ven_nome, ven_cpf, ven_fone, ven_email, ven_dtadmissao, ven_percomissao) VALUES
('Marcos Vieira',  '66666666666', '(31) 97777-0001', 'marcos.vieira@concessionaria.com',  '2020-03-01', 2.50),
('Patrícia Nunes', '77777777777', '(31) 97777-0002', 'patricia.nunes@concessionaria.com', '2021-07-15', 3.00),
('Rafael Costa',   '88888888888', '(31) 97777-0003', NULL,                                '2023-01-10', 2.00);

INSERT INTO mec_mecanico (mec_nome, mec_cpf, mec_fone, mec_email, mec_especialidade, mec_dtadmissao) VALUES
('José Almeida',  '99999999991', '(31) 96666-0001', 'jose.almeida@concessionaria.com', 'Motor e injeção',      '2018-05-02'),
('Luís Pereira',  '99999999992', '(31) 96666-0002', NULL,                              'Freios e suspensão',   '2019-09-20'),
('Sérgio Ramos',  '99999999993', '(31) 96666-0003', NULL,                              'Carburação',           '2015-02-11'),
('Tiago Barbosa', '99999999994', '(31) 96666-0004', 'tiago.barbosa@concessionaria.com', 'Elétrica e injeção',   '2022-06-06');

-- Veículos entram como "Disponível"; o gatilho muda para "Vendido" na venda.
INSERT INTO vei_veiculo (vei_numserie, vei_marca, vei_modelo, vei_anofabricacao, vei_anomodelo, vei_cor, vei_placa, vei_condicao, vei_km, vei_precotabela, vei_situacao) VALUES
('9BGKS48A0PG100001', 'Chevrolet',  'Onix',      2023, 2024, 'Branco',   NULL,      'Novo',  0,      89900.00,  'Disponível'),
('9BR53ZEC4K8500002', 'Toyota',     'Corolla',   2019, 2019, 'Prata',    'RIO2A34', 'Usado', 48200,  89000.00,  'Disponível'),
('9BHBG51CAKP600003', 'Hyundai',    'HB20',      2019, 2019, 'Vermelho', 'QWE1F56', 'Usado', 61500,  52000.00,  'Disponível'),
('9BGEA48A0PB700004', 'Chevrolet',  'Tracker',   2024, 2024, 'Cinza',    NULL,      'Novo',  0,      139900.00, 'Disponível'),
('9BWAB45U0JT800005', 'Volkswagen', 'Gol',       2018, 2018, 'Preto',    'PQR3D78', 'Usado', 72300,  41500.00,  'Disponível'),
-- veículos de clientes que utilizam somente a oficina
('9BD15822764900006', 'Fiat',       'Uno Mille', 1999, 2000, 'Azul',     'GKZ4B12', 'Usado', 158000, NULL,      'Externo'),
('93HGD5850CZ100007', 'Honda',      'Fit',       2012, 2012, 'Prata',    'HMD5C34', 'Usado', 121000, NULL,      'Externo'),
('9BD178120A0200008', 'Fiat',       'Palio',     2010, 2010, 'Branco',   'JKL6E56', 'Usado', 134000, NULL,      'Externo');

INSERT INTO pec_peca (pec_codigo, pec_nome, pec_descricao, pec_fabricante, pec_precounit, pec_qtdestoque) VALUES
('PEC-0001', 'Filtro de óleo',               'Filtro de óleo do motor',           'Tecfil', 35.90,  40),
('PEC-0002', 'Óleo 5W30 sintético (1 L)',    'Óleo lubrificante sintético',       'Mobil',  48.00,  120),
('PEC-0003', 'Pastilha de freio dianteira',  'Jogo de pastilhas dianteiras',      'Cobreq', 129.90, 25),
('PEC-0004', 'Filtro de ar',                 'Filtro de ar do motor',             'Mann',   42.50,  30),
('PEC-0005', 'Vela de ignição',              'Vela de ignição (unidade)',         'NGK',    27.00,  80);

-- Vendas (ids 1 a 3) e respectivas faturas
INSERT INTO vnd_venda (vnd_vei_numserie, vnd_cli_id, vnd_ven_id, vnd_dtvenda, vnd_valor, vnd_formapagamento) VALUES
('9BGKS48A0PG100001', 1, 1, '2024-02-10', 89000.00, 'Financiamento'),
('9BR53ZEC4K8500002', 2, 2, '2024-03-05', 87500.00, 'À Vista'),
('9BHBG51CAKP600003', 2, 1, '2024-04-20', 51000.00, 'Cartão de Crédito');

INSERT INTO fat_fatura (fat_numero, fat_vnd_id, fat_dtemissao, fat_valortotal, fat_situacao, fat_dtentrega) VALUES
('FAT-2024-0001', 1, '2024-02-10', 89000.00, 'Paga',    '2024-02-12'),
('FAT-2024-0002', 2, '2024-03-05', 87500.00, 'Paga',    '2024-03-05'),
('FAT-2024-0003', 3, '2024-04-20', 51000.00, 'Emitida', NULL);

-- Ordens de serviço (ids 1 a 5): abertas/em andamento; as conclusões vêm depois
INSERT INTO ors_ordem_servico (ors_cli_id, ors_vei_numserie, ors_dtabertura, ors_dtprevisao, ors_situacao, ors_descproblema, ors_kmentrada, ors_vlrmaodeobra) VALUES
(1, '9BGKS48A0PG100001', '2024-08-05', '2024-08-05', 'Em Andamento', 'Revisão dos 10.000 km',                              10200,  180.00),
(3, '9BD15822764900006', '2024-08-10', '2024-08-12', 'Em Andamento', 'Motor falhando; ajuste do carburador',                158100, 220.00),
(4, '93HGD5850CZ100007', '2024-09-02', '2024-09-04', 'Em Andamento', 'Barulho ao frear; troca das pastilhas dianteiras',    121300, 150.00),
(4, '9BD178120A0200008', '2024-09-02', '2024-09-03', 'Em Andamento', 'Marcha lenta irregular; limpeza do bico injetor',     134200, 200.00),
(2, '9BR53ZEC4K8500002', '2024-09-20', NULL,         'Aberta',       'Revisão dos 50.000 km',                                50100,  0.00);

-- Mecânicos por OS (a OS 5 ainda não tem mecânico designado)
INSERT INTO osm_os_mecanico (osm_ors_id, osm_mec_id, osm_funcao, osm_horas) VALUES
(1, 1, 'Responsável', 1.50),
(1, 2, 'Auxiliar',    1.00),
(2, 3, 'Responsável', 3.00),
(2, 1, 'Auxiliar',    2.00),
(3, 2, 'Responsável', 2.50),
(4, 4, 'Responsável', 2.00),
(4, 3, 'Auxiliar',    1.00);

-- Peças por OS: as OS 2 e 4 foram concluídas SEM uso de peças
INSERT INTO osp_os_peca (osp_ors_id, osp_pec_id, osp_quantidade, osp_precounit) VALUES
(1, 1, 1, 35.90),
(1, 2, 4, 48.00),
(1, 4, 1, 42.50),
(3, 3, 1, 129.90);

-- Conclusão das OS 1, 2 e 4 (o gatilho exige ao menos um mecânico)
UPDATE ors_ordem_servico SET ors_situacao = 'Concluída', ors_dtconclusao = '2024-08-05' WHERE ors_id = 1;
UPDATE ors_ordem_servico SET ors_situacao = 'Concluída', ors_dtconclusao = '2024-08-11' WHERE ors_id = 2;
UPDATE ors_ordem_servico SET ors_situacao = 'Concluída', ors_dtconclusao = '2024-09-03' WHERE ors_id = 4;

-- Histórico de manutenção (hmn_seq pode ser omitido: o gatilho numera por veículo)
INSERT INTO hmn_historico_manutencao (hmn_vei_numserie, hmn_seq, hmn_ors_id, hmn_tipo, hmn_descricao, hmn_dtservico, hmn_km) VALUES
('9BGKS48A0PG100001', 1, 1, 'Revisão', 'Revisão dos 10.000 km: troca de óleo, filtro de óleo e filtro de ar.',        '2024-08-05', 10200),
('9BD15822764900006', 1, 2, 'Ajuste',  'Ajuste do carburador, sem substituição de peças.',                            '2024-08-11', 158100),
('9BD178120A0200008', 1, 4, 'Limpeza', 'Limpeza do bico injetor de combustível, sem substituição de peças.',         '2024-09-03', 134200);
