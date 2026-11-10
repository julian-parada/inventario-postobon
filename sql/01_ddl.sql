

CREATE SCHEMA inventario_postobon;
SET search_path TO inventario_postobon;

-- ---------------------------------------------------------------------
-- 1. CATEGORY : categorías de producto (Gaseosas, Aguas, Jugos, ...)
-- ---------------------------------------------------------------------
CREATE TABLE inventario_postobon.category (
    category_id    INTEGER GENERATED ALWAYS AS IDENTITY,
    category_name  VARCHAR(50)  NOT NULL,
    description    VARCHAR(200) NOT NULL,
    CONSTRAINT category_pk PRIMARY KEY (category_id),
    CONSTRAINT category_name_ck CHECK (length(btrim(category_name)) >= 3),
    CONSTRAINT category_desc_ck CHECK (length(btrim(description)) >= 5)
);
-- Nombre único sin importar mayúsculas/minúsculas ("Gaseosas" = "GASEOSAS")
CREATE UNIQUE INDEX category_name_uk ON inventario_postobon.category (upper(category_name));

-- ---------------------------------------------------------------------
-- 2. PRODUCT : referencias que maneja el centro de distribución
-- ---------------------------------------------------------------------
CREATE TABLE inventario_postobon.product (
    product_id       INTEGER GENERATED ALWAYS AS IDENTITY,
    category_id      INTEGER       NOT NULL,
    name             VARCHAR(50)   NOT NULL,
    unit_of_measure  VARCHAR(20)   NOT NULL,
    reference_price  NUMERIC(10,2) NOT NULL,
    min_stock        INTEGER       NOT NULL,
    max_stock        INTEGER       NOT NULL,
    CONSTRAINT product_pk PRIMARY KEY (product_id),
    CONSTRAINT product_category_fk FOREIGN KEY (category_id)
        REFERENCES inventario_postobon.category (category_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT product_name_ck  CHECK (length(btrim(name)) >= 3),
    CONSTRAINT product_unit_ck  CHECK (unit_of_measure IN
        ('UNIDAD','PACA','CANASTA','CAJA','SIXPACK','FARDO','BOLSA')),
    CONSTRAINT product_price_ck CHECK (reference_price > 0),
    CONSTRAINT product_min_ck   CHECK (min_stock >= 0),
    CONSTRAINT product_max_ck   CHECK (max_stock > min_stock)
);
CREATE UNIQUE INDEX product_name_uk ON inventario_postobon.product (upper(name));
CREATE INDEX product_category_ix ON inventario_postobon.product (category_id);

-- ---------------------------------------------------------------------
-- 3. SUPPLIER : proveedores (plantas y terceros)
-- ---------------------------------------------------------------------
CREATE TABLE inventario_postobon.supplier (
    supplier_id  INTEGER GENERATED ALWAYS AS IDENTITY,
    name         VARCHAR(50) NOT NULL,
    tax_id       VARCHAR(20) NOT NULL,
    address      VARCHAR(50) NOT NULL,
    CONSTRAINT supplier_pk PRIMARY KEY (supplier_id),
    CONSTRAINT supplier_tax_id_uk UNIQUE (tax_id),
    CONSTRAINT supplier_name_ck    CHECK (length(btrim(name)) >= 3),
    -- NIT colombiano: 9 dígitos, guion y dígito de verificación (ej. 890903939-5)
    CONSTRAINT supplier_tax_id_ck  CHECK (tax_id ~ '^[0-9]{9}-[0-9]$'),
    CONSTRAINT supplier_address_ck CHECK (length(btrim(address)) >= 5)
);

-- ---------------------------------------------------------------------
-- 4. EMPLOYEE : personal que recibe y registra los lotes
-- ---------------------------------------------------------------------
CREATE TABLE inventario_postobon.employee (
    employee_id  INTEGER GENERATED ALWAYS AS IDENTITY,
    name         VARCHAR(50) NOT NULL,
    position     VARCHAR(50) NOT NULL,
    username     VARCHAR(50) NOT NULL,
    CONSTRAINT employee_pk PRIMARY KEY (employee_id),
    CONSTRAINT employee_username_uk UNIQUE (username),
    CONSTRAINT employee_name_ck CHECK (length(btrim(name)) >= 5),
    CONSTRAINT employee_position_ck CHECK (position IN
        ('AUXILIAR DE BODEGA','MONTACARGUISTA','JEFE DE BODEGA',
         'ANALISTA DE INVENTARIO','COORDINADOR LOGISTICO',
         'SUPERVISOR DE CALIDAD','DESPACHADOR','ADMINISTRADOR')),
    -- usuario en minúscula, empieza por letra, sin espacios ni símbolos raros
    CONSTRAINT employee_username_ck CHECK (username ~ '^[a-z][a-z0-9._]{3,29}$')
);

-- ---------------------------------------------------------------------
-- 5. SUPPLY_ORDER : orden de abastecimiento a un proveedor
--    (en el diagrama original estaba mal escrita: SUPLLY_ORDER)
-- ---------------------------------------------------------------------
CREATE TABLE inventario_postobon.supply_order (
    order_id     INTEGER GENERATED ALWAYS AS IDENTITY,
    supplier_id  INTEGER       NOT NULL,
    issue_date   TIMESTAMPTZ   NOT NULL DEFAULT now(),
    status       VARCHAR(20)   NOT NULL DEFAULT 'PENDIENTE',
    total        NUMERIC(12,2) NOT NULL DEFAULT 0,
    CONSTRAINT supply_order_pk PRIMARY KEY (order_id),
    CONSTRAINT supply_order_supplier_fk FOREIGN KEY (supplier_id)
        REFERENCES inventario_postobon.supplier (supplier_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT supply_order_status_ck CHECK (status IN
        ('PENDIENTE','APROBADA','RECIBIDA','CANCELADA')),
    CONSTRAINT supply_order_total_ck CHECK (total >= 0),
    CONSTRAINT supply_order_date_ck  CHECK (issue_date >= TIMESTAMPTZ '2000-01-01 00:00:00-05')
);
CREATE INDEX supply_order_supplier_ix ON inventario_postobon.supply_order (supplier_id);
CREATE INDEX supply_order_status_ix   ON inventario_postobon.supply_order (status);
CREATE INDEX supply_order_date_ix     ON inventario_postobon.supply_order (issue_date);

-- ---------------------------------------------------------------------
-- 6. ORDER_DETAIL : productos pedidos en cada orden
-- ---------------------------------------------------------------------
CREATE TABLE inventario_postobon.order_detail (
    detail_id           INTEGER GENERATED ALWAYS AS IDENTITY,
    order_id            INTEGER       NOT NULL,
    product_id          INTEGER       NOT NULL,
    requested_quantity  INTEGER       NOT NULL,
    unit_price          NUMERIC(10,2) NOT NULL,
    CONSTRAINT order_detail_pk PRIMARY KEY (detail_id),
    CONSTRAINT order_detail_supply_order_fk FOREIGN KEY (order_id)
        REFERENCES inventario_postobon.supply_order (order_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT order_detail_product_fk FOREIGN KEY (product_id)
        REFERENCES inventario_postobon.product (product_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
    -- un producto aparece una sola vez por orden
    CONSTRAINT order_detail_order_product_uk UNIQUE (order_id, product_id),
    CONSTRAINT order_detail_qty_ck   CHECK (requested_quantity BETWEEN 1 AND 100000),
    CONSTRAINT order_detail_price_ck CHECK (unit_price > 0)
);
CREATE INDEX order_detail_product_ix ON inventario_postobon.order_detail (product_id);

-- ---------------------------------------------------------------------
-- 7. BATCH : lote recibido de una orden, registrado por un empleado
-- ---------------------------------------------------------------------
CREATE TABLE inventario_postobon.batch (
    batch_id          INTEGER GENERATED ALWAYS AS IDENTITY,
    order_id          INTEGER NOT NULL,
    employee_id       INTEGER NOT NULL,
    expiration_date   DATE    NOT NULL,
    initial_quantity  INTEGER NOT NULL,
    CONSTRAINT batch_pk PRIMARY KEY (batch_id),
    CONSTRAINT batch_supply_order_fk FOREIGN KEY (order_id)
        REFERENCES inventario_postobon.supply_order (order_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT batch_employee_fk FOREIGN KEY (employee_id)
        REFERENCES inventario_postobon.employee (employee_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT batch_qty_ck CHECK (initial_quantity BETWEEN 1 AND 1000000)
);
CREATE INDEX batch_order_ix      ON inventario_postobon.batch (order_id);
CREATE INDEX batch_employee_ix   ON inventario_postobon.batch (employee_id);
CREATE INDEX batch_expiration_ix ON inventario_postobon.batch (expiration_date);

-- ---------------------------------------------------------------------
-- 8. BATCH_DETAIL : productos y cantidades que trae cada lote
-- ---------------------------------------------------------------------
CREATE TABLE inventario_postobon.batch_detail (
    batch_detail_id  INTEGER GENERATED ALWAYS AS IDENTITY,
    batch_id         INTEGER NOT NULL,
    product_id       INTEGER NOT NULL,
    quantity         INTEGER NOT NULL,
    CONSTRAINT batch_detail_pk PRIMARY KEY (batch_detail_id),
    CONSTRAINT batch_detail_batch_fk FOREIGN KEY (batch_id)
        REFERENCES inventario_postobon.batch (batch_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT batch_detail_product_fk FOREIGN KEY (product_id)
        REFERENCES inventario_postobon.product (product_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT batch_detail_batch_product_uk UNIQUE (batch_id, product_id),
    CONSTRAINT batch_detail_qty_ck CHECK (quantity > 0)
);
CREATE INDEX batch_detail_product_ix ON inventario_postobon.batch_detail (product_id);

-- ---------------------------------------------------------------------
-- 9. AUDIT_LOG : auditoría de cambios (llenada solo por triggers)
-- ---------------------------------------------------------------------
CREATE TABLE inventario_postobon.audit_log (
    audit_id    BIGINT GENERATED ALWAYS AS IDENTITY,
    table_name  VARCHAR(30) NOT NULL,
    operation   CHAR(1)     NOT NULL,            -- I = Insert, U = Update, D = Delete
    record_id   INTEGER     NOT NULL,
    old_data    JSONB,
    new_data    JSONB,
    changed_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    db_user     VARCHAR(50) NOT NULL DEFAULT current_user,
    CONSTRAINT audit_log_pk PRIMARY KEY (audit_id),
    CONSTRAINT audit_log_operation_ck CHECK (operation IN ('I','U','D'))
);
CREATE INDEX audit_log_table_ix ON inventario_postobon.audit_log (table_name, record_id);

-- ---------------------------------------------------------------------
-- Comentarios (diccionario de datos visible en pgAdmin)
-- ---------------------------------------------------------------------
COMMENT ON TABLE inventario_postobon.category     IS 'Categorías de producto';
COMMENT ON TABLE inventario_postobon.product      IS 'Productos manejados por el centro de distribución';
COMMENT ON TABLE inventario_postobon.supplier     IS 'Proveedores de las órdenes de abastecimiento';
COMMENT ON TABLE inventario_postobon.employee     IS 'Empleados que reciben y registran lotes';
COMMENT ON TABLE inventario_postobon.supply_order IS 'Órdenes de abastecimiento. TOTAL lo calcula un trigger';
COMMENT ON TABLE inventario_postobon.order_detail IS 'Productos pedidos en cada orden';
COMMENT ON TABLE inventario_postobon.batch        IS 'Lotes recibidos por orden';
COMMENT ON TABLE inventario_postobon.batch_detail IS 'Productos y cantidades de cada lote';
COMMENT ON TABLE inventario_postobon.audit_log    IS 'Historial de cambios, solo escritura por triggers';
COMMENT ON COLUMN inventario_postobon.supply_order.status IS 'PENDIENTE -> APROBADA -> RECIBIDA | CANCELADA';
COMMENT ON COLUMN inventario_postobon.supply_order.total  IS 'Suma de requested_quantity * unit_price (automático)';
COMMENT ON COLUMN inventario_postobon.batch.initial_quantity IS 'Unidades totales del lote; la suma de BATCH_DETAIL no puede superarla';
