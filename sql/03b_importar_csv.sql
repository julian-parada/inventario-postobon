
SET search_path TO inventario_postobon;
BEGIN;

-- 1. Tablas de paso (temporales, desaparecen al terminar)
CREATE TEMP TABLE s_category     (category_id int, category_name text, description text) ON COMMIT DROP;
CREATE TEMP TABLE s_supplier     (supplier_id int, name text, tax_id text, address text) ON COMMIT DROP;
CREATE TEMP TABLE s_employee     (employee_id int, name text, position text, username text) ON COMMIT DROP;
CREATE TEMP TABLE s_product      (product_id int, category_id int, name text, unit_of_measure text,
                                  reference_price numeric, min_stock int, max_stock int) ON COMMIT DROP;
CREATE TEMP TABLE s_supply_order (order_id int, supplier_id int, issue_date timestamptz, status text, total numeric) ON COMMIT DROP;
CREATE TEMP TABLE s_order_detail (detail_id int, order_id int, product_id int, requested_quantity int, unit_price numeric) ON COMMIT DROP;
CREATE TEMP TABLE s_batch        (batch_id int, order_id int, employee_id int, expiration_date date, initial_quantity int) ON COMMIT DROP;
CREATE TEMP TABLE s_batch_detail (batch_detail_id int, batch_id int, product_id int, quantity int) ON COMMIT DROP;

-- 2. Lectura de los CSV
COPY s_category     FROM 'C:/Users/Public/postobon/csv/category.csv'     WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
COPY s_supplier     FROM 'C:/Users/Public/postobon/csv/supplier.csv'     WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
COPY s_employee     FROM 'C:/Users/Public/postobon/csv/employee.csv'     WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
COPY s_product      FROM 'C:/Users/Public/postobon/csv/product.csv'      WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
COPY s_supply_order FROM 'C:/Users/Public/postobon/csv/supply_order.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
COPY s_order_detail FROM 'C:/Users/Public/postobon/csv/order_detail.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
COPY s_batch        FROM 'C:/Users/Public/postobon/csv/batch.csv'        WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
COPY s_batch_detail FROM 'C:/Users/Public/postobon/csv/batch_detail.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

-- 3. Tablas base y productos
INSERT INTO category OVERRIDING SYSTEM VALUE SELECT * FROM s_category ORDER BY category_id;
INSERT INTO supplier OVERRIDING SYSTEM VALUE SELECT * FROM s_supplier ORDER BY supplier_id;
INSERT INTO employee OVERRIDING SYSTEM VALUE SELECT * FROM s_employee ORDER BY employee_id;
INSERT INTO product  OVERRIDING SYSTEM VALUE SELECT * FROM s_product  ORDER BY product_id;

-- 4. Órdenes: nacen PENDIENTES (total lo calcula el trigger)
INSERT INTO supply_order (order_id, supplier_id, issue_date) OVERRIDING SYSTEM VALUE
SELECT order_id, supplier_id, issue_date FROM s_supply_order ORDER BY order_id;

INSERT INTO order_detail OVERRIDING SYSTEM VALUE SELECT * FROM s_order_detail ORDER BY detail_id;

-- 5. Aprobar las que en el Excel están APROBADA o RECIBIDA, y las CANCELADAS que ya tienen lotes
--    (una orden cancelada con lotes fue aprobada antes; no puede cancelarse si ya recibió algo,
--     así que en los datos no existen canceladas con lotes)
UPDATE supply_order o SET status = 'APROBADA'
  FROM s_supply_order s
 WHERE s.order_id = o.order_id AND s.status IN ('APROBADA', 'RECIBIDA');

-- 6. Lotes y su detalle (solo se aceptan sobre órdenes APROBADAS: trigger T5 y T6)
INSERT INTO batch        OVERRIDING SYSTEM VALUE SELECT * FROM s_batch        ORDER BY batch_id;
INSERT INTO batch_detail OVERRIDING SYSTEM VALUE SELECT * FROM s_batch_detail ORDER BY batch_detail_id;

-- 7. Estados finales
UPDATE supply_order o SET status = 'RECIBIDA'
  FROM s_supply_order s
 WHERE s.order_id = o.order_id AND s.status = 'RECIBIDA';
UPDATE supply_order o SET status = 'CANCELADA'
  FROM s_supply_order s
 WHERE s.order_id = o.order_id AND s.status = 'CANCELADA';

-- 8. Ajustar las secuencias de identidad al último ID importado
SELECT setval(pg_get_serial_sequence('inventario_postobon.category', 'category_id'),     (SELECT MAX(category_id) FROM category));
SELECT setval(pg_get_serial_sequence('inventario_postobon.supplier', 'supplier_id'),     (SELECT MAX(supplier_id) FROM supplier));
SELECT setval(pg_get_serial_sequence('inventario_postobon.employee', 'employee_id'),     (SELECT MAX(employee_id) FROM employee));
SELECT setval(pg_get_serial_sequence('inventario_postobon.product', 'product_id'),       (SELECT MAX(product_id) FROM product));
SELECT setval(pg_get_serial_sequence('inventario_postobon.supply_order', 'order_id'),    (SELECT MAX(order_id) FROM supply_order));
SELECT setval(pg_get_serial_sequence('inventario_postobon.order_detail', 'detail_id'),   (SELECT MAX(detail_id) FROM order_detail));
SELECT setval(pg_get_serial_sequence('inventario_postobon.batch', 'batch_id'),           (SELECT MAX(batch_id) FROM batch));
SELECT setval(pg_get_serial_sequence('inventario_postobon.batch_detail', 'batch_detail_id'), (SELECT MAX(batch_detail_id) FROM batch_detail));

-- 9. Comprobación: el Excel y la base deben coincidir
SELECT 'supply_order' AS tabla,
       (SELECT count(*) FROM s_supply_order) AS filas_csv,
       (SELECT count(*) FROM supply_order)   AS filas_bd,
       (SELECT count(*) FROM supply_order o JOIN s_supply_order s USING (order_id)
         WHERE o.status <> s.status OR o.total <> s.total) AS diferencias;

COMMIT;
