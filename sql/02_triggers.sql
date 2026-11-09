-- =====================================================================
--  ARCHIVO 02: FUNCIONES DISPARADORAS Y TRIGGERS (PL/pgSQL)
--  Reglas de negocio + auditoría + protección contra borrados masivos
--  Ejecutar después de 01_ddl.sql
-- =====================================================================
SET search_path TO inventario_postobon;

-- =====================================================================
-- T1. NORMALIZACIÓN DE TEXTO (BEFORE INSERT OR UPDATE, por fila)
--     Quita espacios sobrantes y unifica mayúsculas/minúsculas, para que
--     "  postobon " y "POSTOBON" no se guarden como dos datos distintos.
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_normalizar_texto()
RETURNS trigger AS $$
BEGIN
    IF TG_TABLE_NAME = 'category' THEN
        NEW.category_name := upper(regexp_replace(btrim(NEW.category_name), '\s+', ' ', 'g'));
        NEW.description   := regexp_replace(btrim(NEW.description), '\s+', ' ', 'g');
    ELSIF TG_TABLE_NAME = 'product' THEN
        NEW.name            := upper(regexp_replace(btrim(NEW.name), '\s+', ' ', 'g'));
        NEW.unit_of_measure := upper(btrim(NEW.unit_of_measure));
    ELSIF TG_TABLE_NAME = 'supplier' THEN
        NEW.name    := upper(regexp_replace(btrim(NEW.name), '\s+', ' ', 'g'));
        NEW.tax_id  := btrim(NEW.tax_id);
        NEW.address := upper(regexp_replace(btrim(NEW.address), '\s+', ' ', 'g'));
    ELSIF TG_TABLE_NAME = 'employee' THEN
        NEW.name     := upper(regexp_replace(btrim(NEW.name), '\s+', ' ', 'g'));
        NEW.position := upper(regexp_replace(btrim(NEW.position), '\s+', ' ', 'g'));
        NEW.username := lower(btrim(NEW.username));
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql
SET search_path = inventario_postobon, pg_temp;

CREATE TRIGGER trg_category_normalizar BEFORE INSERT OR UPDATE ON category
    FOR EACH ROW EXECUTE FUNCTION fn_normalizar_texto();
CREATE TRIGGER trg_product_normalizar  BEFORE INSERT OR UPDATE ON product
    FOR EACH ROW EXECUTE FUNCTION fn_normalizar_texto();
CREATE TRIGGER trg_supplier_normalizar BEFORE INSERT OR UPDATE ON supplier
    FOR EACH ROW EXECUTE FUNCTION fn_normalizar_texto();
CREATE TRIGGER trg_employee_normalizar BEFORE INSERT OR UPDATE ON employee
    FOR EACH ROW EXECUTE FUNCTION fn_normalizar_texto();

-- =====================================================================
-- T2. REGLAS DE LA ORDEN DE ABASTECIMIENTO (BEFORE INSERT OR UPDATE)
--   * Toda orden nace en estado PENDIENTE.
--   * La fecha de emisión no puede ser futura.
--   * Ciclo de vida permitido:
--       PENDIENTE -> APROBADA | CANCELADA
--       APROBADA  -> RECIBIDA | CANCELADA
--       RECIBIDA y CANCELADA son estados finales.
--   * Solo se aprueba si tiene detalle; solo se marca RECIBIDA si tiene
--     lotes con productos; no se cancela si ya llegaron lotes.
--   * Proveedor y fecha solo se cambian mientras está PENDIENTE.
--   * TOTAL siempre se recalcula: nadie lo puede falsificar a mano.
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_supply_order_reglas()
RETURNS trigger AS $$
BEGIN
    IF NEW.issue_date > now() + interval '5 minutes' THEN
        RAISE EXCEPTION 'La fecha de emisión (%) no puede ser futura', NEW.issue_date
            USING ERRCODE = 'check_violation';
    END IF;

    IF TG_OP = 'INSERT' THEN
        IF NEW.status <> 'PENDIENTE' THEN
            RAISE EXCEPTION 'Una orden nueva debe crearse en estado PENDIENTE (llegó %)', NEW.status
                USING ERRCODE = 'check_violation';
        END IF;
        NEW.total := 0;               -- todavía no tiene detalle
        RETURN NEW;
    END IF;

    -- ------------------------- UPDATE -------------------------------
    IF OLD.status <> 'PENDIENTE' AND
       (NEW.supplier_id <> OLD.supplier_id OR NEW.issue_date <> OLD.issue_date) THEN
        RAISE EXCEPTION 'La orden % está %: ya no se puede cambiar proveedor ni fecha',
            OLD.order_id, OLD.status USING ERRCODE = 'check_violation';
    END IF;

    IF NEW.status <> OLD.status THEN
        IF NOT (   (OLD.status = 'PENDIENTE' AND NEW.status IN ('APROBADA','CANCELADA'))
                OR (OLD.status = 'APROBADA'  AND NEW.status IN ('RECIBIDA','CANCELADA'))) THEN
            RAISE EXCEPTION 'Cambio de estado no permitido: % -> % (orden %)',
                OLD.status, NEW.status, OLD.order_id USING ERRCODE = 'check_violation';
        END IF;

        IF NEW.status = 'APROBADA' AND NOT EXISTS
           (SELECT 1 FROM order_detail d WHERE d.order_id = NEW.order_id) THEN
            RAISE EXCEPTION 'No se puede aprobar la orden %: no tiene productos', NEW.order_id
                USING ERRCODE = 'check_violation';
        END IF;

        IF NEW.status = 'RECIBIDA' AND NOT EXISTS
           (SELECT 1 FROM batch b JOIN batch_detail bd ON bd.batch_id = b.batch_id
             WHERE b.order_id = NEW.order_id) THEN
            RAISE EXCEPTION 'No se puede marcar RECIBIDA la orden %: no tiene lotes registrados', NEW.order_id
                USING ERRCODE = 'check_violation';
        END IF;

        IF NEW.status = 'CANCELADA' AND EXISTS
           (SELECT 1 FROM batch b WHERE b.order_id = NEW.order_id) THEN
            RAISE EXCEPTION 'No se puede cancelar la orden %: ya tiene lotes recibidos', NEW.order_id
                USING ERRCODE = 'check_violation';
        END IF;
    END IF;

    -- el total nunca se acepta a mano: siempre se calcula del detalle
    SELECT COALESCE(SUM(d.requested_quantity * d.unit_price), 0)
      INTO NEW.total
      FROM order_detail d
     WHERE d.order_id = NEW.order_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql
SET search_path = inventario_postobon, pg_temp;

CREATE TRIGGER trg_supply_order_reglas
    BEFORE INSERT OR UPDATE ON supply_order
    FOR EACH ROW EXECUTE FUNCTION fn_supply_order_reglas();

-- =====================================================================
-- T3. DETALLE DE ORDEN (BEFORE INSERT OR UPDATE OR DELETE)
--     Solo se agregan, cambian o quitan productos si la orden está
--     PENDIENTE. Una orden aprobada, recibida o cancelada queda congelada.
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_order_detail_reglas()
RETURNS trigger AS $$
DECLARE
    v_status supply_order.status%TYPE;
    v_order  INTEGER;
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.order_id <> OLD.order_id THEN
        RAISE EXCEPTION 'No se puede mover un detalle a otra orden (detalle %)', OLD.detail_id
            USING ERRCODE = 'check_violation';
    END IF;

    v_order := CASE WHEN TG_OP = 'DELETE' THEN OLD.order_id ELSE NEW.order_id END;

    -- FOR UPDATE bloquea la orden: dos usuarios no la modifican a la vez
    SELECT status INTO v_status FROM supply_order WHERE order_id = v_order FOR UPDATE;

    IF v_status IS DISTINCT FROM 'PENDIENTE' THEN
        RAISE EXCEPTION 'La orden % está %: su detalle ya no se puede modificar', v_order, v_status
            USING ERRCODE = 'check_violation';
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql
SET search_path = inventario_postobon, pg_temp;

CREATE TRIGGER trg_order_detail_reglas
    BEFORE INSERT OR UPDATE OR DELETE ON order_detail
    FOR EACH ROW EXECUTE FUNCTION fn_order_detail_reglas();

-- =====================================================================
-- T4. TOTAL DE LA ORDEN (AFTER INSERT OR UPDATE OR DELETE en detalle)
--     Mantiene SUPPLY_ORDER.TOTAL actualizado (patrón "tabla resumen").
--     El UPDATE dispara T2, que recalcula la suma.
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_order_detail_total()
RETURNS trigger AS $$
BEGIN
    UPDATE supply_order SET total = 0     -- T2 reemplaza el 0 por la suma real
     WHERE order_id = CASE WHEN TG_OP = 'DELETE' THEN OLD.order_id ELSE NEW.order_id END;
    RETURN NULL;                           -- AFTER: el retorno se ignora
END;
$$ LANGUAGE plpgsql
SET search_path = inventario_postobon, pg_temp;

CREATE TRIGGER trg_order_detail_total
    AFTER INSERT OR UPDATE OR DELETE ON order_detail
    FOR EACH ROW EXECUTE FUNCTION fn_order_detail_total();

-- =====================================================================
-- T5. LOTES (BEFORE INSERT OR UPDATE OR DELETE en batch)
--   * Solo se reciben lotes de órdenes APROBADAS.
--   * El vencimiento debe ser posterior a la fecha de la orden y no
--     mayor a 5 años.
--   * Un lote no se pasa a otra orden.
--   * INITIAL_QUANTITY no puede quedar por debajo de lo ya detallado.
--   * Lotes de órdenes cerradas no se modifican ni se borran.
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_batch_reglas()
RETURNS trigger AS $$
DECLARE
    v_status  supply_order.status%TYPE;
    v_fecha   DATE;
    v_order   INTEGER;
    v_detalle INTEGER;
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.order_id <> OLD.order_id THEN
        RAISE EXCEPTION 'No se puede pasar el lote % a otra orden', OLD.batch_id
            USING ERRCODE = 'check_violation';
    END IF;

    v_order := CASE WHEN TG_OP = 'DELETE' THEN OLD.order_id ELSE NEW.order_id END;

    SELECT status, (issue_date AT TIME ZONE 'America/Bogota')::date
      INTO v_status, v_fecha
      FROM supply_order WHERE order_id = v_order FOR UPDATE;

    IF v_status IS DISTINCT FROM 'APROBADA' THEN
        RAISE EXCEPTION 'La orden % está %: solo se registran o modifican lotes de órdenes APROBADAS',
            v_order, COALESCE(v_status, 'INEXISTENTE') USING ERRCODE = 'check_violation';
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;          -- si el lote tiene detalle, la FK RESTRICT impide el borrado
    END IF;

    IF NEW.expiration_date <= v_fecha THEN
        RAISE EXCEPTION 'Vencimiento % inválido: debe ser posterior a la fecha de la orden (%)',
            NEW.expiration_date, v_fecha USING ERRCODE = 'check_violation';
    END IF;

    IF NEW.expiration_date > v_fecha + interval '5 years' THEN
        RAISE EXCEPTION 'Vencimiento % inválido: supera 5 años desde la orden', NEW.expiration_date
            USING ERRCODE = 'check_violation';
    END IF;

    IF TG_OP = 'UPDATE' THEN
        SELECT COALESCE(SUM(quantity), 0) INTO v_detalle
          FROM batch_detail WHERE batch_id = NEW.batch_id;
        IF NEW.initial_quantity < v_detalle THEN
            RAISE EXCEPTION 'El lote % ya tiene % unidades detalladas; no puede quedar con %',
                NEW.batch_id, v_detalle, NEW.initial_quantity USING ERRCODE = 'check_violation';
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql
SET search_path = inventario_postobon, pg_temp;

CREATE TRIGGER trg_batch_reglas
    BEFORE INSERT OR UPDATE OR DELETE ON batch
    FOR EACH ROW EXECUTE FUNCTION fn_batch_reglas();

-- =====================================================================
-- T6. DETALLE DE LOTE (BEFORE INSERT OR UPDATE OR DELETE)
--   * El producto del lote debe estar en la orden (no se recibe lo que
--     no se pidió).
--   * Lo recibido de un producto, sumando todos los lotes de la orden,
--     no puede superar lo pedido.
--   * La suma de cantidades del lote no puede superar INITIAL_QUANTITY.
--   * Solo mientras la orden está APROBADA.
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_batch_detail_reglas()
RETURNS trigger AS $$
DECLARE
    v_batch     INTEGER;
    v_order     INTEGER;
    v_inicial   INTEGER;
    v_status    supply_order.status%TYPE;
    v_pedido    INTEGER;
    v_recibido  INTEGER;
    v_en_lote   INTEGER;
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.batch_id <> OLD.batch_id THEN
        RAISE EXCEPTION 'No se puede pasar un detalle a otro lote (detalle %)', OLD.batch_detail_id
            USING ERRCODE = 'check_violation';
    END IF;

    v_batch := CASE WHEN TG_OP = 'DELETE' THEN OLD.batch_id ELSE NEW.batch_id END;

    SELECT b.order_id, b.initial_quantity INTO v_order, v_inicial
      FROM batch b WHERE b.batch_id = v_batch;

    SELECT status INTO v_status FROM supply_order WHERE order_id = v_order FOR UPDATE;

    IF v_status IS DISTINCT FROM 'APROBADA' THEN
        RAISE EXCEPTION 'La orden % está %: el detalle de sus lotes no se puede modificar',
            v_order, COALESCE(v_status, 'INEXISTENTE') USING ERRCODE = 'check_violation';
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    -- 1) el producto debe estar pedido en la orden
    SELECT requested_quantity INTO v_pedido
      FROM order_detail WHERE order_id = v_order AND product_id = NEW.product_id;
    IF v_pedido IS NULL THEN
        RAISE EXCEPTION 'El producto % no fue pedido en la orden %', NEW.product_id, v_order
            USING ERRCODE = 'check_violation';
    END IF;

    -- 2) lo recibido en todos los lotes de la orden no supera lo pedido
    SELECT COALESCE(SUM(bd.quantity), 0) INTO v_recibido
      FROM batch_detail bd JOIN batch b ON b.batch_id = bd.batch_id
     WHERE b.order_id = v_order
       AND bd.product_id = NEW.product_id
       AND bd.batch_detail_id <> NEW.batch_detail_id;
    IF v_recibido + NEW.quantity > v_pedido THEN
        RAISE EXCEPTION 'Producto %: se pidieron % y con este lote se recibirían %',
            NEW.product_id, v_pedido, v_recibido + NEW.quantity USING ERRCODE = 'check_violation';
    END IF;

    -- 3) el lote no se llena por encima de su cantidad inicial
    SELECT COALESCE(SUM(quantity), 0) INTO v_en_lote
      FROM batch_detail
     WHERE batch_id = NEW.batch_id AND batch_detail_id <> NEW.batch_detail_id;
    IF v_en_lote + NEW.quantity > v_inicial THEN
        RAISE EXCEPTION 'El lote % tiene capacidad % y quedaría con %',
            NEW.batch_id, v_inicial, v_en_lote + NEW.quantity USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql
SET search_path = inventario_postobon, pg_temp;

CREATE TRIGGER trg_batch_detail_reglas
    BEFORE INSERT OR UPDATE OR DELETE ON batch_detail
    FOR EACH ROW EXECUTE FUNCTION fn_batch_detail_reglas();

-- =====================================================================
-- T7. AUDITORÍA (AFTER INSERT OR UPDATE OR DELETE, por fila)
--     Guarda en AUDIT_LOG la fila anterior (OLD) y la nueva (NEW) en JSON.
--     TG_ARGV[0] = nombre de la columna PK de la tabla auditada.
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_auditar()
RETURNS trigger AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_log (table_name, operation, record_id, new_data)
        VALUES (TG_TABLE_NAME, 'I', (to_jsonb(NEW) ->> TG_ARGV[0])::int, to_jsonb(NEW));
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log (table_name, operation, record_id, old_data, new_data)
        VALUES (TG_TABLE_NAME, 'U', (to_jsonb(NEW) ->> TG_ARGV[0])::int, to_jsonb(OLD), to_jsonb(NEW));
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log (table_name, operation, record_id, old_data)
        VALUES (TG_TABLE_NAME, 'D', (to_jsonb(OLD) ->> TG_ARGV[0])::int, to_jsonb(OLD));
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql
SET search_path = inventario_postobon, pg_temp;

CREATE TRIGGER trg_category_auditar AFTER INSERT OR DELETE ON category
    FOR EACH ROW EXECUTE FUNCTION fn_auditar('category_id');
CREATE TRIGGER trg_category_auditar_upd AFTER UPDATE ON category
    FOR EACH ROW WHEN (OLD.* IS DISTINCT FROM NEW.*) EXECUTE FUNCTION fn_auditar('category_id');

CREATE TRIGGER trg_product_auditar AFTER INSERT OR DELETE ON product
    FOR EACH ROW EXECUTE FUNCTION fn_auditar('product_id');
CREATE TRIGGER trg_product_auditar_upd AFTER UPDATE ON product
    FOR EACH ROW WHEN (OLD.* IS DISTINCT FROM NEW.*) EXECUTE FUNCTION fn_auditar('product_id');

CREATE TRIGGER trg_supplier_auditar AFTER INSERT OR DELETE ON supplier
    FOR EACH ROW EXECUTE FUNCTION fn_auditar('supplier_id');
CREATE TRIGGER trg_supplier_auditar_upd AFTER UPDATE ON supplier
    FOR EACH ROW WHEN (OLD.* IS DISTINCT FROM NEW.*) EXECUTE FUNCTION fn_auditar('supplier_id');

CREATE TRIGGER trg_employee_auditar AFTER INSERT OR DELETE ON employee
    FOR EACH ROW EXECUTE FUNCTION fn_auditar('employee_id');
CREATE TRIGGER trg_employee_auditar_upd AFTER UPDATE ON employee
    FOR EACH ROW WHEN (OLD.* IS DISTINCT FROM NEW.*) EXECUTE FUNCTION fn_auditar('employee_id');

-- En órdenes solo se audita el cambio de estado, proveedor o fecha
-- (el total cambia con cada producto agregado y llenaría la auditoría de ruido)
CREATE TRIGGER trg_supply_order_auditar AFTER INSERT OR DELETE ON supply_order
    FOR EACH ROW EXECUTE FUNCTION fn_auditar('order_id');
CREATE TRIGGER trg_supply_order_auditar_upd AFTER UPDATE OF status, supplier_id, issue_date ON supply_order
    FOR EACH ROW WHEN (OLD.status IS DISTINCT FROM NEW.status
                    OR OLD.supplier_id IS DISTINCT FROM NEW.supplier_id
                    OR OLD.issue_date IS DISTINCT FROM NEW.issue_date)
    EXECUTE FUNCTION fn_auditar('order_id');

-- =====================================================================
-- T8. LA AUDITORÍA ES INALTERABLE
--     Nadie puede editar ni borrar el historial (ni con TRUNCATE).
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_auditoria_inalterable()
RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION 'AUDIT_LOG es de solo lectura: operación % rechazada', TG_OP
        USING ERRCODE = 'insufficient_privilege';
END;
$$ LANGUAGE plpgsql
SET search_path = inventario_postobon, pg_temp;

CREATE TRIGGER trg_audit_log_inalterable BEFORE UPDATE OR DELETE ON audit_log
    FOR EACH ROW EXECUTE FUNCTION fn_auditoria_inalterable();
CREATE TRIGGER trg_audit_log_no_truncate BEFORE TRUNCATE ON audit_log
    FOR EACH STATEMENT EXECUTE FUNCTION fn_auditoria_inalterable();

-- =====================================================================
-- T9. BLOQUEO DE TRUNCATE (por sentencia)
--     TRUNCATE ... CASCADE vaciaría todas las tablas hijas de un golpe,
--     saltándose el ON DELETE RESTRICT. Se prohíbe en todas las tablas.
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_bloquear_truncate()
RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION 'TRUNCATE no está permitido sobre %: elimine filas con DELETE', TG_TABLE_NAME
        USING ERRCODE = 'insufficient_privilege';
END;
$$ LANGUAGE plpgsql
SET search_path = inventario_postobon, pg_temp;

CREATE TRIGGER trg_category_no_truncate     BEFORE TRUNCATE ON category     FOR EACH STATEMENT EXECUTE FUNCTION fn_bloquear_truncate();
CREATE TRIGGER trg_product_no_truncate      BEFORE TRUNCATE ON product      FOR EACH STATEMENT EXECUTE FUNCTION fn_bloquear_truncate();
CREATE TRIGGER trg_supplier_no_truncate     BEFORE TRUNCATE ON supplier     FOR EACH STATEMENT EXECUTE FUNCTION fn_bloquear_truncate();
CREATE TRIGGER trg_employee_no_truncate     BEFORE TRUNCATE ON employee     FOR EACH STATEMENT EXECUTE FUNCTION fn_bloquear_truncate();
CREATE TRIGGER trg_supply_order_no_truncate BEFORE TRUNCATE ON supply_order FOR EACH STATEMENT EXECUTE FUNCTION fn_bloquear_truncate();
CREATE TRIGGER trg_order_detail_no_truncate BEFORE TRUNCATE ON order_detail FOR EACH STATEMENT EXECUTE FUNCTION fn_bloquear_truncate();
CREATE TRIGGER trg_batch_no_truncate        BEFORE TRUNCATE ON batch        FOR EACH STATEMENT EXECUTE FUNCTION fn_bloquear_truncate();
CREATE TRIGGER trg_batch_detail_no_truncate BEFORE TRUNCATE ON batch_detail FOR EACH STATEMENT EXECUTE FUNCTION fn_bloquear_truncate();
