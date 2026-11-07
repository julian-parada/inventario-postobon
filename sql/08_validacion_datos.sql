-- =====================================================================
--  ARCHIVO 08: VALIDACIÓN SQL DE LOS DATOS IMPORTADOS (Anexo 1, E8)
--  Cada consulta indica el resultado esperado.
-- =====================================================================
SET search_path TO inventario_postobon;

-- V1. Volumen por tabla (esperado: 100, 1000, 1500, 500, 500)
SELECT 'product' AS tabla, count(*) FROM product UNION ALL
SELECT 'supply_order', count(*) FROM supply_order UNION ALL
SELECT 'order_detail', count(*) FROM order_detail UNION ALL
SELECT 'batch', count(*) FROM batch UNION ALL
SELECT 'batch_detail', count(*) FROM batch_detail;

-- V2. Huérfanos: detalles sin orden o sin producto (esperado: 0)
SELECT count(*) AS huerfanos FROM order_detail d
LEFT JOIN supply_order o ON o.order_id = d.order_id
LEFT JOIN product p ON p.product_id = d.product_id
WHERE o.order_id IS NULL OR p.product_id IS NULL;

-- V3. Totales de orden que no cuadran con su detalle (esperado: 0)
SELECT count(*) AS totales_mal FROM supply_order o
WHERE o.total <> (SELECT COALESCE(sum(requested_quantity * unit_price), 0) FROM order_detail d WHERE d.order_id = o.order_id);

-- V4. Productos recibidos de más (esperado: 0)
SELECT count(*) AS excesos FROM (
  SELECT d.order_id, d.product_id FROM order_detail d
  JOIN batch b ON b.order_id = d.order_id
  JOIN batch_detail bd ON bd.batch_id = b.batch_id AND bd.product_id = d.product_id
  GROUP BY d.order_id, d.product_id, d.requested_quantity
  HAVING sum(bd.quantity) > d.requested_quantity) x;

-- V5. Lotes en órdenes que no estén APROBADA o RECIBIDA (esperado: 0)
SELECT count(*) AS lotes_invalidos FROM batch b JOIN supply_order o ON o.order_id = b.order_id
WHERE o.status NOT IN ('APROBADA', 'RECIBIDA');

-- V6. Órdenes RECIBIDAS sin lotes, o APROBADAS sin productos (esperado: 0)
SELECT count(*) AS estados_incoherentes FROM supply_order o
WHERE (o.status = 'RECIBIDA' AND NOT EXISTS (SELECT 1 FROM batch b WHERE b.order_id = o.order_id))
   OR (o.status IN ('APROBADA','RECIBIDA') AND NOT EXISTS (SELECT 1 FROM order_detail d WHERE d.order_id = o.order_id));

-- V7. Vencimientos fuera de rango: antes de la orden o a más de 5 años (esperado: 0)
SELECT count(*) AS vencimientos_mal FROM batch b JOIN supply_order o ON o.order_id = b.order_id
WHERE b.expiration_date <= o.issue_date::date OR b.expiration_date > o.issue_date::date + 1826;

-- V8. Lotes llenados por encima de su cantidad inicial (esperado: 0)
SELECT count(*) AS lotes_excedidos FROM batch b
WHERE b.initial_quantity < (SELECT COALESCE(sum(quantity),0) FROM batch_detail bd WHERE bd.batch_id = b.batch_id);

-- V9. Duplicados de nombre de producto sin importar mayúsculas (esperado: 0)
SELECT upper(name), count(*) FROM product GROUP BY upper(name) HAVING count(*) > 1;

-- V10. Fechas futuras (esperado: 0) y rango de fechas cargadas
SELECT count(*) FILTER (WHERE issue_date > now()) AS futuras,
       min(issue_date)::date AS primera, max(issue_date)::date AS ultima
FROM supply_order;

-- V11. Distribución de estados (esperado: 370 RECIBIDA, 250 PENDIENTE, 190 APROBADA, 190 CANCELADA)
SELECT status, count(*) FROM supply_order GROUP BY status ORDER BY 2 DESC;

-- V12. Lotes vigentes y por vencer en 60 días (deben existir ambos para probar los reportes)
SELECT count(*) FILTER (WHERE expiration_date >= current_date) AS vigentes,
       count(*) FILTER (WHERE expiration_date BETWEEN current_date AND current_date + 60) AS por_vencer_60d
FROM batch;
