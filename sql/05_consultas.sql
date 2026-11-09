-- =====================================================================
--  ARCHIVO 05: VISTAS Y CONSULTAS DE VERIFICACIÓN
--  Ejecutar después de 03_datos.sql
-- =====================================================================
SET search_path TO inventario_postobon;

-- ---------------------------------------------------------------------
-- Vista 1: existencias vigentes por producto (lotes recibidos y no vencidos)
--          comparadas con el stock mínimo y máximo.
--          Nota: el modelo no tiene tabla de salidas/despachos, por eso la
--          existencia se calcula como lo recibido en lotes aún vigentes.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_existencias AS
SELECT p.product_id,
       p.name                         AS producto,
       c.category_name                AS categoria,
       p.unit_of_measure              AS unidad,
       p.min_stock,
       p.max_stock,
       COALESCE(SUM(bd.quantity), 0)  AS existencia_vigente,
       CASE
           WHEN COALESCE(SUM(bd.quantity), 0) = 0          THEN 'SIN EXISTENCIA'
           WHEN COALESCE(SUM(bd.quantity), 0) < p.min_stock THEN 'BAJO EL MINIMO'
           WHEN COALESCE(SUM(bd.quantity), 0) > p.max_stock THEN 'SOBRE EL MAXIMO'
           ELSE 'NORMAL'
       END                            AS estado
  FROM product p
  JOIN category c          ON c.category_id = p.category_id
  LEFT JOIN batch_detail bd ON bd.product_id = p.product_id
                           AND EXISTS (SELECT 1 FROM batch b
                                        WHERE b.batch_id = bd.batch_id
                                          AND b.expiration_date >= current_date)
 GROUP BY p.product_id, p.name, c.category_name, p.unit_of_measure, p.min_stock, p.max_stock;

-- ---------------------------------------------------------------------
-- Vista 2: lotes que vencen en los próximos 60 días
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_lotes_por_vencer AS
SELECT b.batch_id,
       b.expiration_date,
       b.expiration_date - current_date AS dias_restantes,
       p.name                           AS producto,
       bd.quantity,
       s.name                           AS proveedor,
       e.name                           AS recibido_por
  FROM batch b
  JOIN batch_detail bd ON bd.batch_id   = b.batch_id
  JOIN product p       ON p.product_id  = bd.product_id
  JOIN supply_order o  ON o.order_id    = b.order_id
  JOIN supplier s      ON s.supplier_id = o.supplier_id
  JOIN employee e      ON e.employee_id = b.employee_id
 WHERE b.expiration_date BETWEEN current_date AND current_date + 60;

-- ---------------------------------------------------------------------
-- Vista 3: cumplimiento de proveedores (pedido vs recibido)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_cumplimiento_proveedor AS
WITH pedido AS (
    SELECT o.supplier_id, SUM(d.requested_quantity) AS unidades_pedidas
      FROM supply_order o JOIN order_detail d ON d.order_id = o.order_id
     WHERE o.status = 'RECIBIDA'
     GROUP BY o.supplier_id
), recibido AS (
    SELECT o.supplier_id, SUM(bd.quantity) AS unidades_recibidas
      FROM supply_order o
      JOIN batch b         ON b.order_id = o.order_id
      JOIN batch_detail bd ON bd.batch_id = b.batch_id
     WHERE o.status = 'RECIBIDA'
     GROUP BY o.supplier_id
)
SELECT s.supplier_id, s.name AS proveedor, s.tax_id AS nit,
       p.unidades_pedidas, r.unidades_recibidas,
       round(100.0 * r.unidades_recibidas / p.unidades_pedidas, 2) AS porcentaje_cumplimiento
  FROM supplier s
  JOIN pedido p   ON p.supplier_id = s.supplier_id
  JOIN recibido r ON r.supplier_id = s.supplier_id;

-- =====================================================================
-- CONSULTAS DE VERIFICACIÓN
-- =====================================================================

-- C1. Filas por tabla
SELECT 'category' AS tabla, count(*) AS filas FROM category
UNION ALL SELECT 'product',      count(*) FROM product
UNION ALL SELECT 'supplier',     count(*) FROM supplier
UNION ALL SELECT 'employee',     count(*) FROM employee
UNION ALL SELECT 'supply_order', count(*) FROM supply_order
UNION ALL SELECT 'order_detail', count(*) FROM order_detail
UNION ALL SELECT 'batch',        count(*) FROM batch
UNION ALL SELECT 'batch_detail', count(*) FROM batch_detail
UNION ALL SELECT 'audit_log',    count(*) FROM audit_log;

-- C2. Órdenes por estado
SELECT status, count(*) AS ordenes, sum(total) AS valor_total
  FROM supply_order GROUP BY status ORDER BY ordenes DESC;

-- C3. Ninguna llave foránea tiene ON DELETE CASCADE (debe devolver 0 filas)
SELECT conrelid::regclass AS tabla, conname AS fk, confdeltype
  FROM pg_constraint
 WHERE contype = 'f'
   AND connamespace = 'inventario_postobon'::regnamespace
   AND confdeltype <> 'r';           -- 'r' = RESTRICT

-- C4. Integridad del total: órdenes cuyo total no cuadra con el detalle (0 filas)
SELECT o.order_id, o.total, sum(d.requested_quantity * d.unit_price) AS calculado
  FROM supply_order o LEFT JOIN order_detail d ON d.order_id = o.order_id
 GROUP BY o.order_id, o.total
HAVING o.total <> COALESCE(sum(d.requested_quantity * d.unit_price), 0);

-- C5. Nada recibido de más (0 filas)
SELECT d.order_id, d.product_id, d.requested_quantity, sum(bd.quantity) AS recibido
  FROM order_detail d
  JOIN batch b         ON b.order_id = d.order_id
  JOIN batch_detail bd ON bd.batch_id = b.batch_id AND bd.product_id = d.product_id
 GROUP BY d.order_id, d.product_id, d.requested_quantity
HAVING sum(bd.quantity) > d.requested_quantity;

-- C6. Top 10 productos más pedidos
SELECT p.name, sum(d.requested_quantity) AS unidades, count(DISTINCT d.order_id) AS ordenes
  FROM order_detail d JOIN product p ON p.product_id = d.product_id
 GROUP BY p.name ORDER BY unidades DESC LIMIT 10;

-- C7. Compras por mes (últimos 12 meses)
SELECT date_trunc('month', issue_date)::date AS mes, count(*) AS ordenes, sum(total) AS valor
  FROM supply_order
 WHERE status = 'RECIBIDA' AND issue_date >= now() - interval '12 months'
 GROUP BY 1 ORDER BY 1;

-- C8. Empleados que más lotes han recibido
SELECT e.name, e.position, count(*) AS lotes
  FROM batch b JOIN employee e ON e.employee_id = b.employee_id
 GROUP BY e.name, e.position ORDER BY lotes DESC LIMIT 10;

-- C9. Estado de existencias
SELECT estado, count(*) AS productos FROM v_existencias GROUP BY estado ORDER BY productos DESC;

-- C10. Lotes por vencer
SELECT * FROM v_lotes_por_vencer ORDER BY dias_restantes LIMIT 20;

-- C11. Proveedores con menor cumplimiento
SELECT * FROM v_cumplimiento_proveedor ORDER BY porcentaje_cumplimiento LIMIT 10;

-- C12. Últimos movimientos de auditoría
SELECT audit_id, table_name, operation, record_id, changed_at, db_user
  FROM audit_log ORDER BY audit_id DESC LIMIT 20;

-- C13. Compras por proveedor: solo órdenes RECIBIDAS (RI-05)
SELECT s.name AS proveedor, count(o.order_id) AS ordenes, sum(o.total) AS total_comprado
  FROM supplier s JOIN supply_order o ON o.supplier_id = s.supplier_id
 WHERE o.status = 'RECIBIDA'
 GROUP BY s.name ORDER BY total_comprado DESC;

-- C14. Proveedor y empleado de cada lote (RI-07)
SELECT b.batch_id, b.expiration_date, e.name AS recibido_por, o.order_id, s.name AS proveedor
  FROM batch b
  JOIN employee e     ON e.employee_id = b.employee_id
  JOIN supply_order o ON o.order_id = b.order_id
  JOIN supplier s     ON s.supplier_id = o.supplier_id
 ORDER BY b.batch_id;
