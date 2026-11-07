-- =====================================================================
--  ARCHIVO 04: PRUEBAS DE RESISTENCIA ("intentar reventar la base")
--  Ejecutar completo en pgAdmin (F5) después de cargar los datos.
--
--  Cómo funciona: cada ataque se ejecuta dentro de pg_temp.probar(), que
--  lo corre en una subtransacción, captura el error y DESHACE todo.
--  La base queda exactamente igual después de correr este archivo.
--    BLOQUEADO  = la base rechazó el ataque (lo esperado)
--    VULNERABLE = la base aceptó algo que no debía
--  Las verificaciones (V) comprueban que una regla automática funcionó.
-- =====================================================================
SET search_path TO inventario_postobon;

-- ---------- funciones auxiliares de prueba (temporales, solo esta sesión)
CREATE OR REPLACE FUNCTION pg_temp.probar(p_n TEXT, p_prueba TEXT, p_sql TEXT)
RETURNS TABLE (n TEXT, prueba TEXT, resultado TEXT, mensaje TEXT) AS $$
BEGIN
    n := p_n; prueba := p_prueba;
    BEGIN
        EXECUTE p_sql;
        RAISE EXCEPTION '__ACEPTADO__';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = '__ACEPTADO__' THEN
            resultado := 'VULNERABLE'; mensaje := 'La sentencia se aceptó';
        ELSE
            resultado := 'BLOQUEADO'; mensaje := SQLERRM;
        END IF;
    END;
    RETURN NEXT;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pg_temp.verificar(p_n TEXT, p_prueba TEXT, p_sql TEXT, p_check TEXT)
RETURNS TABLE (n TEXT, prueba TEXT, resultado TEXT, mensaje TEXT) AS $$
DECLARE v_ok BOOLEAN;
BEGIN
    n := p_n; prueba := p_prueba;
    BEGIN
        EXECUTE p_sql;
        EXECUTE p_check INTO v_ok;
        RAISE EXCEPTION '__FIN__%', CASE WHEN v_ok THEN 'OK' ELSE 'FALLO' END;
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = '__FIN__OK' THEN resultado := 'OK'; mensaje := 'La regla automática funcionó';
        ELSIF SQLERRM = '__FIN__FALLO' THEN resultado := 'FALLO'; mensaje := 'El resultado no fue el esperado';
        ELSE resultado := 'ERROR'; mensaje := SQLERRM;
        END IF;
    END;
    RETURN NEXT;
END;
$$ LANGUAGE plpgsql;

-- ---------- IDs reales sobre los que se ataca
DROP TABLE IF EXISTS pg_temp.ids;   -- por si el archivo se ejecuta dos veces en la misma sesión
CREATE TEMP TABLE ids AS
SELECT
  (SELECT min(order_id) FROM supply_order WHERE status = 'PENDIENTE')  AS pendiente,
  (SELECT min(order_id) FROM supply_order WHERE status = 'RECIBIDA')   AS recibida,
  (SELECT min(order_id) FROM supply_order WHERE status = 'CANCELADA')  AS cancelada,
  (SELECT min(o.order_id) FROM supply_order o
    WHERE o.status = 'APROBADA' AND EXISTS (SELECT 1 FROM batch b WHERE b.order_id = o.order_id)) AS aprobada_con_lote,
  (SELECT min(b.batch_id) FROM batch b JOIN supply_order o USING (order_id) WHERE o.status = 'RECIBIDA') AS lote_cerrado,
  (SELECT min(b.batch_id) FROM batch b JOIN supply_order o USING (order_id) WHERE o.status = 'APROBADA') AS lote_abierto,
  (SELECT min(employee_id) FROM employee e WHERE EXISTS (SELECT 1 FROM batch b WHERE b.employee_id = e.employee_id)) AS empleado_con_lotes,
  (SELECT min(product_id) FROM product p WHERE EXISTS (SELECT 1 FROM order_detail d WHERE d.product_id = p.product_id)) AS producto_usado,
  (SELECT min(category_id) FROM category c WHERE EXISTS (SELECT 1 FROM product p WHERE p.category_id = c.category_id)) AS cat1,
  (SELECT min(supplier_id) FROM supplier) AS sup1,
  (SELECT max(supplier_id) FROM supplier) AS sup2,
  (SELECT min(employee_id) FROM employee) AS emp1,
  (SELECT min(product_id) FROM product) AS prod1,
  (SELECT min(product_id) FROM product WHERE product_id > (SELECT min(product_id) FROM product)) AS prod2;

DROP TABLE IF EXISTS pg_temp.resultados;
CREATE TEMP TABLE resultados AS
-- ===================== CATEGORY =====================
          SELECT * FROM pg_temp.probar('01','Categoría con nombre NULL',
  $q$INSERT INTO category (category_name, description) VALUES (NULL, 'sin nombre')$q$)
UNION ALL SELECT * FROM pg_temp.probar('02','Categoría con nombre en blanco',
  $q$INSERT INTO category (category_name, description) VALUES ('    ', 'nombre vacío')$q$)
UNION ALL SELECT * FROM pg_temp.probar('03','Categoría duplicada cambiando mayúsculas y espacios',
  $q$INSERT INTO category (category_name, description)
     SELECT '  ' || replace(lower(category_name), ' ', '    ') || ' ', 'duplicado disfrazado'
       FROM category WHERE category_id = (SELECT cat1 FROM ids)$q$)
UNION ALL SELECT * FROM pg_temp.probar('04','Nombre de categoría de más de 50 caracteres',
  $q$INSERT INTO category (category_name, description) VALUES (repeat('X', 51), 'demasiado largo')$q$)
UNION ALL SELECT * FROM pg_temp.probar('05','Inventar el ID de una categoría',
  $q$INSERT INTO category (category_id, category_name, description) VALUES (1, 'ID MANUAL', 'forzar id')$q$)
UNION ALL SELECT * FROM pg_temp.probar('06','Cambiar la llave primaria de una categoría',
  $q$UPDATE category SET category_id = 9999 WHERE category_id = (SELECT cat1 FROM ids)$q$)
UNION ALL SELECT * FROM pg_temp.probar('07','Borrar una categoría que tiene productos',
  $q$DELETE FROM category WHERE category_id = (SELECT cat1 FROM ids)$q$)
UNION ALL SELECT * FROM pg_temp.probar('08','DROP TABLE de una tabla padre',
  $q$DROP TABLE category$q$)
-- ===================== PRODUCT =====================
UNION ALL SELECT * FROM pg_temp.probar('09','Producto con precio negativo',
  $q$INSERT INTO product (category_id, name, unit_of_measure, reference_price, min_stock, max_stock)
     VALUES ((SELECT cat1 FROM ids), 'PRUEBA NEGATIVA', 'UNIDAD', -500, 10, 100)$q$)
UNION ALL SELECT * FROM pg_temp.probar('10','Producto con precio cero',
  $q$INSERT INTO product (category_id, name, unit_of_measure, reference_price, min_stock, max_stock)
     VALUES ((SELECT cat1 FROM ids), 'PRUEBA CERO', 'UNIDAD', 0, 10, 100)$q$)
UNION ALL SELECT * FROM pg_temp.probar('11','Stock máximo menor que el mínimo',
  $q$INSERT INTO product (category_id, name, unit_of_measure, reference_price, min_stock, max_stock)
     VALUES ((SELECT cat1 FROM ids), 'PRUEBA STOCK', 'UNIDAD', 2000, 500, 100)$q$)
UNION ALL SELECT * FROM pg_temp.probar('12','Stock mínimo negativo',
  $q$INSERT INTO product (category_id, name, unit_of_measure, reference_price, min_stock, max_stock)
     VALUES ((SELECT cat1 FROM ids), 'PRUEBA MIN', 'UNIDAD', 2000, -5, 100)$q$)
UNION ALL SELECT * FROM pg_temp.probar('13','Unidad de medida inexistente',
  $q$INSERT INTO product (category_id, name, unit_of_measure, reference_price, min_stock, max_stock)
     VALUES ((SELECT cat1 FROM ids), 'PRUEBA UNIDAD', 'LITRO', 2000, 10, 100)$q$)
UNION ALL SELECT * FROM pg_temp.probar('14','Producto con categoría que no existe',
  $q$INSERT INTO product (category_id, name, unit_of_measure, reference_price, min_stock, max_stock)
     VALUES (99999, 'PRUEBA HUERFANO', 'UNIDAD', 2000, 10, 100)$q$)
UNION ALL SELECT * FROM pg_temp.probar('15','Precio que desborda NUMERIC(10,2)',
  $q$INSERT INTO product (category_id, name, unit_of_measure, reference_price, min_stock, max_stock)
     VALUES ((SELECT cat1 FROM ids), 'PRUEBA OVERFLOW', 'UNIDAD', 999999999999, 10, 100)$q$)
UNION ALL SELECT * FROM pg_temp.probar('16','Texto en un campo numérico',
  $q$INSERT INTO product (category_id, name, unit_of_measure, reference_price, min_stock, max_stock)
     VALUES ((SELECT cat1 FROM ids), 'PRUEBA TEXTO', 'UNIDAD', 'abc', 10, 100)$q$)
UNION ALL SELECT * FROM pg_temp.probar('17','Producto duplicado en minúsculas',
  $q$INSERT INTO product (category_id, name, unit_of_measure, reference_price, min_stock, max_stock)
     SELECT category_id, lower(name), unit_of_measure, reference_price, min_stock, max_stock
       FROM product WHERE product_id = (SELECT prod1 FROM ids)$q$)
UNION ALL SELECT * FROM pg_temp.probar('18','Borrar un producto que está en órdenes',
  $q$DELETE FROM product WHERE product_id = (SELECT producto_usado FROM ids)$q$)
-- ===================== SUPPLIER =====================
UNION ALL SELECT * FROM pg_temp.probar('19','NIT con formato inválido',
  $q$INSERT INTO supplier (name, tax_id, address) VALUES ('PROVEEDOR MALO', '123', 'CL 1 # 2-3 OCAÑA')$q$)
UNION ALL SELECT * FROM pg_temp.probar('20','NIT con letras',
  $q$INSERT INTO supplier (name, tax_id, address) VALUES ('PROVEEDOR MALO', '89090ABC9-5', 'CL 1 # 2-3 OCAÑA')$q$)
UNION ALL SELECT * FROM pg_temp.probar('21','NIT duplicado (con espacios alrededor)',
  $q$INSERT INTO supplier (name, tax_id, address)
     SELECT 'COPIA', '  ' || tax_id || '  ', 'CL 1 # 2-3 OCAÑA' FROM supplier WHERE supplier_id = (SELECT sup1 FROM ids)$q$)
UNION ALL SELECT * FROM pg_temp.probar('22','Borrar un proveedor que tiene órdenes',
  $q$DELETE FROM supplier WHERE supplier_id = (SELECT supplier_id FROM supply_order LIMIT 1)$q$)
-- ===================== EMPLOYEE =====================
UNION ALL SELECT * FROM pg_temp.probar('23','Usuario con espacios',
  $q$INSERT INTO employee (name, position, username) VALUES ('PEDRO PRUEBA', 'AUXILIAR DE BODEGA', 'pedro prueba')$q$)
UNION ALL SELECT * FROM pg_temp.probar('24','Usuario duplicado escrito en MAYÚSCULAS',
  $q$INSERT INTO employee (name, position, username)
     SELECT 'OTRA PERSONA', 'AUXILIAR DE BODEGA', upper(username) FROM employee WHERE employee_id = (SELECT emp1 FROM ids)$q$)
UNION ALL SELECT * FROM pg_temp.probar('25','Cargo que no existe',
  $q$INSERT INTO employee (name, position, username) VALUES ('PEDRO PRUEBA', 'GERENTE SUPREMO', 'pprueba')$q$)
UNION ALL SELECT * FROM pg_temp.probar('26','Borrar un empleado que registró lotes',
  $q$DELETE FROM employee WHERE employee_id = (SELECT empleado_con_lotes FROM ids)$q$)
-- ===================== SUPPLY_ORDER =====================
UNION ALL SELECT * FROM pg_temp.probar('27','Crear una orden directamente RECIBIDA',
  $q$INSERT INTO supply_order (supplier_id, status) VALUES ((SELECT sup1 FROM ids), 'RECIBIDA')$q$)
UNION ALL SELECT * FROM pg_temp.probar('28','Estado inventado',
  $q$ALTER TABLE supply_order DISABLE TRIGGER trg_supply_order_reglas;
     INSERT INTO supply_order (supplier_id, status) VALUES ((SELECT sup1 FROM ids), 'ENVIADA')$q$)
UNION ALL SELECT * FROM pg_temp.probar('29','Orden con fecha futura',
  $q$INSERT INTO supply_order (supplier_id, issue_date) VALUES ((SELECT sup1 FROM ids), now() + interval '30 days')$q$)
UNION ALL SELECT * FROM pg_temp.probar('30','Orden con proveedor inexistente',
  $q$INSERT INTO supply_order (supplier_id) VALUES (99999)$q$)
UNION ALL SELECT * FROM pg_temp.probar('31','Devolver una orden RECIBIDA a PENDIENTE',
  $q$UPDATE supply_order SET status = 'PENDIENTE' WHERE order_id = (SELECT recibida FROM ids)$q$)
UNION ALL SELECT * FROM pg_temp.probar('32','Revivir una orden CANCELADA',
  $q$UPDATE supply_order SET status = 'APROBADA' WHERE order_id = (SELECT cancelada FROM ids)$q$)
UNION ALL SELECT * FROM pg_temp.probar('33','Saltar de PENDIENTE a RECIBIDA',
  $q$UPDATE supply_order SET status = 'RECIBIDA' WHERE order_id = (SELECT pendiente FROM ids)$q$)
UNION ALL SELECT * FROM pg_temp.probar('34','Aprobar una orden sin productos',
  $q$INSERT INTO supply_order (supplier_id) VALUES ((SELECT sup1 FROM ids));
     UPDATE supply_order SET status = 'APROBADA'
      WHERE order_id = currval(pg_get_serial_sequence('inventario_postobon.supply_order','order_id'))$q$)
UNION ALL SELECT * FROM pg_temp.probar('35','Cancelar una orden que ya tiene lotes',
  $q$UPDATE supply_order SET status = 'CANCELADA' WHERE order_id = (SELECT aprobada_con_lote FROM ids)$q$)
UNION ALL SELECT * FROM pg_temp.probar('36','Cambiar el proveedor de una orden RECIBIDA',
  $q$UPDATE supply_order SET supplier_id = (SELECT sup2 FROM ids) WHERE order_id = (SELECT recibida FROM ids)$q$)
UNION ALL SELECT * FROM pg_temp.probar('37','Borrar una orden que tiene detalle',
  $q$DELETE FROM supply_order WHERE order_id = (SELECT recibida FROM ids)$q$)
UNION ALL SELECT * FROM pg_temp.probar('38','Borrar TODAS las órdenes',
  $q$DELETE FROM supply_order$q$)
-- ===================== ORDER_DETAIL =====================
UNION ALL SELECT * FROM pg_temp.probar('39','Agregar producto a una orden RECIBIDA',
  $q$INSERT INTO order_detail (order_id, product_id, requested_quantity, unit_price)
     SELECT (SELECT recibida FROM ids), p.product_id, 10, 1000 FROM product p
      WHERE NOT EXISTS (SELECT 1 FROM order_detail d WHERE d.order_id = (SELECT recibida FROM ids)
                          AND d.product_id = p.product_id) LIMIT 1$q$)
UNION ALL SELECT * FROM pg_temp.probar('40','Cantidad pedida en cero',
  $q$INSERT INTO order_detail (order_id, product_id, requested_quantity, unit_price)
     VALUES ((SELECT pendiente FROM ids), (SELECT prod1 FROM ids), 0, 1000)$q$)
UNION ALL SELECT * FROM pg_temp.probar('41','Cantidad que desborda INTEGER',
  $q$INSERT INTO order_detail (order_id, product_id, requested_quantity, unit_price)
     VALUES ((SELECT pendiente FROM ids), (SELECT prod1 FROM ids), 3000000000, 1000)$q$)
UNION ALL SELECT * FROM pg_temp.probar('42','Mismo producto dos veces en la orden',
  $q$INSERT INTO order_detail (order_id, product_id, requested_quantity, unit_price)
     SELECT order_id, product_id, 5, unit_price FROM order_detail
      WHERE order_id = (SELECT pendiente FROM ids) LIMIT 1$q$)
UNION ALL SELECT * FROM pg_temp.probar('43','Quitar un producto de una orden RECIBIDA',
  $q$DELETE FROM order_detail WHERE detail_id =
     (SELECT min(detail_id) FROM order_detail WHERE order_id = (SELECT recibida FROM ids))$q$)
UNION ALL SELECT * FROM pg_temp.probar('44','Cambiar el precio de una orden RECIBIDA',
  $q$UPDATE order_detail SET unit_price = 1 WHERE order_id = (SELECT recibida FROM ids)$q$)
-- ===================== BATCH =====================
UNION ALL SELECT * FROM pg_temp.probar('45','Registrar lote de una orden PENDIENTE',
  $q$INSERT INTO batch (order_id, employee_id, expiration_date, initial_quantity)
     VALUES ((SELECT pendiente FROM ids), (SELECT emp1 FROM ids), current_date + 200, 50)$q$)
UNION ALL SELECT * FROM pg_temp.probar('46','Registrar lote de una orden ya RECIBIDA',
  $q$INSERT INTO batch (order_id, employee_id, expiration_date, initial_quantity)
     VALUES ((SELECT recibida FROM ids), (SELECT emp1 FROM ids), current_date + 200, 50)$q$)
UNION ALL SELECT * FROM pg_temp.probar('47','Lote que vence antes de la fecha de la orden',
  $q$INSERT INTO batch (order_id, employee_id, expiration_date, initial_quantity)
     VALUES ((SELECT aprobada_con_lote FROM ids), (SELECT emp1 FROM ids), DATE '2000-01-01', 50)$q$)
UNION ALL SELECT * FROM pg_temp.probar('48','Lote que vence en 20 años',
  $q$INSERT INTO batch (order_id, employee_id, expiration_date, initial_quantity)
     VALUES ((SELECT aprobada_con_lote FROM ids), (SELECT emp1 FROM ids), current_date + 7300, 50)$q$)
UNION ALL SELECT * FROM pg_temp.probar('49','Lote con cantidad negativa',
  $q$INSERT INTO batch (order_id, employee_id, expiration_date, initial_quantity)
     VALUES ((SELECT aprobada_con_lote FROM ids), (SELECT emp1 FROM ids), current_date + 200, -10)$q$)
UNION ALL SELECT * FROM pg_temp.probar('50','Pasar un lote a otra orden',
  $q$UPDATE batch SET order_id = (SELECT pendiente FROM ids) WHERE batch_id = (SELECT lote_abierto FROM ids)$q$)
UNION ALL SELECT * FROM pg_temp.probar('51','Borrar un lote de una orden cerrada',
  $q$DELETE FROM batch WHERE batch_id = (SELECT lote_cerrado FROM ids)$q$)
UNION ALL SELECT * FROM pg_temp.probar('52','Bajar la cantidad del lote por debajo de su detalle',
  $q$UPDATE batch SET initial_quantity = 1 WHERE batch_id = (SELECT lote_abierto FROM ids)$q$)
-- ===================== BATCH_DETAIL =====================
UNION ALL SELECT * FROM pg_temp.probar('53','Recibir un producto que no se pidió',
  $q$INSERT INTO batch_detail (batch_id, product_id, quantity)
     SELECT (SELECT lote_abierto FROM ids), p.product_id, 1 FROM product p
      WHERE NOT EXISTS (SELECT 1 FROM order_detail d
                         WHERE d.order_id = (SELECT aprobada_con_lote FROM ids) AND d.product_id = p.product_id)
        AND NOT EXISTS (SELECT 1 FROM order_detail d JOIN batch b ON b.order_id = d.order_id
                         WHERE b.batch_id = (SELECT lote_abierto FROM ids) AND d.product_id = p.product_id)
      LIMIT 1$q$)
UNION ALL SELECT * FROM pg_temp.probar('54','Recibir más de lo pedido',
  $q$INSERT INTO batch (order_id, employee_id, expiration_date, initial_quantity)
     VALUES ((SELECT aprobada_con_lote FROM ids), (SELECT emp1 FROM ids), current_date + 200, 1000000);
     INSERT INTO batch_detail (batch_id, product_id, quantity)
     SELECT currval(pg_get_serial_sequence('inventario_postobon.batch','batch_id')),
            product_id, requested_quantity + 1
       FROM order_detail WHERE order_id = (SELECT aprobada_con_lote FROM ids) LIMIT 1$q$)
UNION ALL SELECT * FROM pg_temp.probar('55','Llenar un lote por encima de su capacidad',
  $q$UPDATE supply_order SET status = 'APROBADA' WHERE order_id = (SELECT pendiente FROM ids);
     INSERT INTO batch (order_id, employee_id, expiration_date, initial_quantity)
     VALUES ((SELECT pendiente FROM ids), (SELECT emp1 FROM ids), current_date + 200, 5);
     INSERT INTO batch_detail (batch_id, product_id, quantity)
     SELECT currval(pg_get_serial_sequence('inventario_postobon.batch','batch_id')), product_id, 6
       FROM order_detail WHERE order_id = (SELECT pendiente FROM ids) LIMIT 1$q$)
UNION ALL SELECT * FROM pg_temp.probar('56','Detalle de lote con cantidad cero',
  $q$INSERT INTO batch_detail (batch_id, product_id, quantity)
     SELECT b.batch_id, d.product_id, 0 FROM batch b JOIN order_detail d ON d.order_id = b.order_id
      WHERE b.batch_id = (SELECT lote_abierto FROM ids) LIMIT 1$q$)
UNION ALL SELECT * FROM pg_temp.probar('57','Modificar el detalle de un lote cerrado',
  $q$UPDATE batch_detail SET quantity = quantity + 1 WHERE batch_id = (SELECT lote_cerrado FROM ids)$q$)
-- ===================== BORRADOS MASIVOS Y AUDITORÍA =====================
UNION ALL SELECT * FROM pg_temp.probar('58','TRUNCATE category CASCADE (borrado en cascada)',
  $q$TRUNCATE category CASCADE$q$)
UNION ALL SELECT * FROM pg_temp.probar('59','TRUNCATE de la tabla hija batch_detail',
  $q$TRUNCATE batch_detail$q$)
UNION ALL SELECT * FROM pg_temp.probar('60','Borrar el historial de auditoría',
  $q$DELETE FROM audit_log$q$)
UNION ALL SELECT * FROM pg_temp.probar('61','Alterar el historial de auditoría',
  $q$UPDATE audit_log SET db_user = 'nadie'$q$)
UNION ALL SELECT * FROM pg_temp.probar('62','TRUNCATE del historial de auditoría',
  $q$TRUNCATE audit_log$q$)
-- ===================== VERIFICACIONES DE REGLAS AUTOMÁTICAS =====================
UNION ALL SELECT * FROM pg_temp.verificar('V1','Normaliza texto: "  agua   mineral " se guarda "AGUA MINERAL"',
  $q$INSERT INTO category (category_name, description) VALUES ('  agua   mineral ', 'prueba de normalización')$q$,
  $q$SELECT EXISTS (SELECT 1 FROM category WHERE category_name = 'AGUA MINERAL')$q$)
UNION ALL SELECT * FROM pg_temp.verificar('V2','Falsificar el total a mano no tiene efecto',
  $q$UPDATE supply_order SET total = 1 WHERE order_id = (SELECT recibida FROM ids)$q$,
  $q$SELECT total = (SELECT sum(requested_quantity * unit_price) FROM order_detail
                      WHERE order_id = (SELECT recibida FROM ids))
       FROM supply_order WHERE order_id = (SELECT recibida FROM ids)$q$)
UNION ALL SELECT * FROM pg_temp.verificar('V3','Inyección SQL en un nombre se guarda como texto inofensivo',
  $q$INSERT INTO category (category_name, description) VALUES ('X''); DROP TABLE product; --', 'inyección')$q$,
  $q$SELECT to_regclass('inventario_postobon.product') IS NOT NULL
        AND EXISTS (SELECT 1 FROM category WHERE category_name LIKE 'X%DROP TABLE%')$q$)
UNION ALL SELECT * FROM pg_temp.verificar('V4','Ciclo completo: crear, aprobar, recibir lote y cerrar orden',
  $q$INSERT INTO supply_order (supplier_id) VALUES ((SELECT sup1 FROM ids));
     INSERT INTO order_detail (order_id, product_id, requested_quantity, unit_price)
     VALUES (currval(pg_get_serial_sequence('inventario_postobon.supply_order','order_id')), (SELECT prod1 FROM ids), 100, 2500),
            (currval(pg_get_serial_sequence('inventario_postobon.supply_order','order_id')), (SELECT prod2 FROM ids), 50, 4000);
     UPDATE supply_order SET status = 'APROBADA'
      WHERE order_id = currval(pg_get_serial_sequence('inventario_postobon.supply_order','order_id'));
     INSERT INTO batch (order_id, employee_id, expiration_date, initial_quantity)
     VALUES (currval(pg_get_serial_sequence('inventario_postobon.supply_order','order_id')), (SELECT emp1 FROM ids), current_date + 180, 150);
     INSERT INTO batch_detail (batch_id, product_id, quantity)
     VALUES (currval(pg_get_serial_sequence('inventario_postobon.batch','batch_id')), (SELECT prod1 FROM ids), 100),
            (currval(pg_get_serial_sequence('inventario_postobon.batch','batch_id')), (SELECT prod2 FROM ids), 50);
     UPDATE supply_order SET status = 'RECIBIDA'
      WHERE order_id = currval(pg_get_serial_sequence('inventario_postobon.supply_order','order_id'))$q$,
  $q$SELECT status = 'RECIBIDA' AND total = 450000
       FROM supply_order
      WHERE order_id = currval(pg_get_serial_sequence('inventario_postobon.supply_order','order_id'))$q$)
UNION ALL SELECT * FROM pg_temp.verificar('V5','La auditoría registra quién borró un producto sin movimientos',
  $q$INSERT INTO product (category_id, name, unit_of_measure, reference_price, min_stock, max_stock)
     VALUES ((SELECT cat1 FROM ids), 'PRODUCTO TEMPORAL AUDITORIA', 'UNIDAD', 1000, 1, 10);
     DELETE FROM product WHERE name = 'PRODUCTO TEMPORAL AUDITORIA'$q$,
  $q$SELECT EXISTS (SELECT 1 FROM audit_log WHERE table_name = 'product' AND operation = 'D'
                    AND old_data ->> 'name' = 'PRODUCTO TEMPORAL AUDITORIA' AND db_user = current_user)$q$);

-- ---------- Resultado de cada prueba
SELECT * FROM resultados ORDER BY n;

-- ---------- Resumen
SELECT resultado, count(*) AS pruebas FROM resultados GROUP BY resultado ORDER BY resultado;
