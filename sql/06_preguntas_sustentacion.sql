-- =====================================================================
--  ARCHIVO 06: BANCO DE PREGUNTAS PARA LA SUSTENTACIÓN INDIVIDUAL
--  Proyecto: Inventario Postobón | Esquema: inventario_postobon
--
--  Cómo practicar: lee la PREGUNTA, intenta escribir la consulta tú solo,
--  y después compara con la respuesta. Ejecuta cada bloque por separado
--  (selecciona sus líneas y F5).
--
--  Parte A: lo que el profe hará para "reventar" la base (INSERT, UPDATE, DELETE)
--  Parte B: JOIN (ejercicio 1 de la evaluación)
--  Parte C: funciones agregadas, GROUP BY y HAVING (ejercicio 2)
--  Parte D: plantillas para memorizar
-- =====================================================================

-- Siempre ejecuta esto primero en un Query Tool nuevo:
SET search_path TO inventario_postobon;
-- Así puedes escribir "product" en vez de "inventario_postobon.product".


-- #####################################################################
--  PARTE A. INTENTOS DE ROMPER LA BASE
--  Lo que debes decir en cada caso: QUÉ error sale y QUÉ regla lo detuvo.
-- #####################################################################

-- ---------------------------------------------------------------------
-- A1. "Agrégueme un producto con precio negativo."
-- Resultado: ERROR, viola la restricción product_price_ck (CHECK precio > 0).
-- ---------------------------------------------------------------------
INSERT INTO product (category_id, name, unit_of_measure, reference_price, min_stock, max_stock)
VALUES (1, 'PRUEBA NEGATIVO', 'UNIDAD', -2500, 10, 100);

-- ---------------------------------------------------------------------
-- A2. "Ahora agréguelo bien." (así se inserta un producto válido)
-- No se escribe product_id: lo genera la base (GENERATED ALWAYS AS IDENTITY).
-- El trigger T1 lo guarda en MAYÚSCULAS y sin espacios de más.
-- ---------------------------------------------------------------------
INSERT INTO product (category_id, name, unit_of_measure, reference_price, min_stock, max_stock)
VALUES (1, 'gaseosa prueba 400 ml', 'UNIDAD', 2500, 10, 100);

SELECT * FROM product WHERE name = 'GASEOSA PRUEBA 400 ML';   -- ya quedó en mayúsculas

-- ---------------------------------------------------------------------
-- A3. "Agregue un producto con stock máximo menor que el mínimo."
-- Resultado: ERROR product_max_ck (max_stock > min_stock).
-- ---------------------------------------------------------------------
INSERT INTO product (category_id, name, unit_of_measure, reference_price, min_stock, max_stock)
VALUES (1, 'PRUEBA STOCK', 'UNIDAD', 2500, 500, 100);

-- ---------------------------------------------------------------------
-- A4. "Agregue un producto a una categoría que no existe."
-- Resultado: ERROR de llave foránea product_category_fk.
-- ---------------------------------------------------------------------
INSERT INTO product (category_id, name, unit_of_measure, reference_price, min_stock, max_stock)
VALUES (99999, 'PRUEBA HUERFANO', 'UNIDAD', 2500, 10, 100);

-- ---------------------------------------------------------------------
-- A5. "Agregue un producto con una unidad de medida que no existe (LITRO)."
-- Resultado: ERROR product_unit_ck. Unidades válidas:
-- UNIDAD, PACA, CANASTA, CAJA, SIXPACK, FARDO, BOLSA.
-- ---------------------------------------------------------------------
INSERT INTO product (category_id, name, unit_of_measure, reference_price, min_stock, max_stock)
VALUES (1, 'PRUEBA UNIDAD', 'LITRO', 2500, 10, 100);

-- ---------------------------------------------------------------------
-- A6. "Agregue un producto que ya existe pero en minúsculas."
-- Resultado: ERROR product_name_uk (nombre único sin importar mayúsculas).
-- ---------------------------------------------------------------------
INSERT INTO product (category_id, name, unit_of_measure, reference_price, min_stock, max_stock)
VALUES (1, 'gaseosa prueba 400 ml', 'UNIDAD', 3000, 10, 100);

-- ---------------------------------------------------------------------
-- A7. "Agregue un producto inventándose el ID."
-- Resultado: ERROR: no se puede insertar un valor no DEFAULT en la
-- columna «product_id» (GENERATED ALWAYS).
-- ---------------------------------------------------------------------
INSERT INTO product (product_id, category_id, name, unit_of_measure, reference_price, min_stock, max_stock)
VALUES (5000, 1, 'PRUEBA ID', 'UNIDAD', 2500, 10, 100);

-- ---------------------------------------------------------------------
-- A8. "Elimine una categoría completa."
-- Resultado: ERROR de llave foránea: la categoría tiene productos y la FK
-- es ON DELETE RESTRICT (no hay cascada). Los productos quedan intactos.
-- ---------------------------------------------------------------------
DELETE FROM category WHERE category_id = 1;

-- ---------------------------------------------------------------------
-- A9. "¿Y una categoría sin productos sí se puede borrar?"  -> SÍ.
-- RESTRICT solo impide borrar lo que tiene hijos.
-- ---------------------------------------------------------------------
INSERT INTO category (category_name, description) VALUES ('CATEGORIA TEMPORAL', 'para probar el borrado');
DELETE FROM category WHERE category_name = 'CATEGORIA TEMPORAL';   -- funciona

-- ---------------------------------------------------------------------
-- A10. "Borre todos los productos."  /  "Vacíe la tabla con TRUNCATE CASCADE."
-- Resultado: ERROR en los dos. El DELETE lo frena la FK de order_detail;
-- el TRUNCATE lo bloquea el trigger T9.
-- ---------------------------------------------------------------------
DELETE FROM product;
TRUNCATE category CASCADE;

-- ---------------------------------------------------------------------
-- A11. "Borre el producto que usted acabó de crear."  -> SÍ se puede,
-- porque no está en ninguna orden. Y queda registrado en la auditoría.
-- ---------------------------------------------------------------------
DELETE FROM product WHERE name = 'GASEOSA PRUEBA 400 ML';

SELECT operation, old_data ->> 'name' AS producto, changed_at, db_user
FROM audit_log
WHERE table_name = 'product'
ORDER BY audit_id DESC
LIMIT 3;

-- ---------------------------------------------------------------------
-- A12. "Cambie el precio de un producto a 0."  (UPDATE)
-- Resultado: ERROR product_price_ck.
-- ---------------------------------------------------------------------
UPDATE product SET reference_price = 0 WHERE product_id = 1;

-- A12b. Un UPDATE válido (subir 10 % el precio del producto 1):
UPDATE product SET reference_price = reference_price * 1.10 WHERE product_id = 1;

-- ---------------------------------------------------------------------
-- A13. "Agregue un proveedor con NIT inválido" y luego uno válido.
-- El NIT debe tener 9 dígitos, guion y 1 dígito: 900123456-7
-- ---------------------------------------------------------------------
INSERT INTO supplier (name, tax_id, address) VALUES ('PROVEEDOR MALO', '123', 'CL 10 # 5-20 OCAÑA');      -- ERROR
INSERT INTO supplier (name, tax_id, address) VALUES ('PROVEEDOR PRUEBA', '900123456-7', 'CL 10 # 5-20 OCAÑA'); -- OK

-- ---------------------------------------------------------------------
-- A14. "Agregue un empleado."  (cargo de la lista, usuario en minúsculas)
-- ---------------------------------------------------------------------
INSERT INTO employee (name, position, username) VALUES ('PEDRO PRUEBA', 'GERENTE', 'pprueba');            -- ERROR cargo
INSERT INTO employee (name, position, username) VALUES ('PEDRO PRUEBA', 'AUXILIAR DE BODEGA', 'pprueba'); -- OK

-- ---------------------------------------------------------------------
-- A15. "Cree una orden, agréguele productos y apruébela."  (ciclo completo)
-- ---------------------------------------------------------------------
INSERT INTO supply_order (supplier_id) VALUES (1)
RETURNING order_id;                         -- la base devuelve el número de la orden nueva

-- (SELECT max(order_id) FROM supply_order) = la orden que acabamos de crear.
-- También puedes escribir directamente el número que devolvió el RETURNING.
INSERT INTO order_detail (order_id, product_id, requested_quantity, unit_price)
VALUES ((SELECT max(order_id) FROM supply_order), 2, 100, 12000),
       ((SELECT max(order_id) FROM supply_order), 3, 50, 8000);

SELECT order_id, status, total FROM supply_order
WHERE order_id = (SELECT max(order_id) FROM supply_order);   -- total = 1.600.000 (lo calculó el trigger)

UPDATE supply_order SET status = 'APROBADA'
WHERE order_id = (SELECT max(order_id) FROM supply_order);

-- ---------------------------------------------------------------------
-- A16. "Devuelva una orden RECIBIDA a PENDIENTE." / "Falsifique el total."
-- Resultado: ERROR del trigger T2 / el total se recalcula solo.
-- ---------------------------------------------------------------------
UPDATE supply_order SET status = 'PENDIENTE'
WHERE order_id = (SELECT min(order_id) FROM supply_order WHERE status = 'RECIBIDA');

UPDATE supply_order SET total = 1 WHERE order_id = (SELECT max(order_id) FROM supply_order);
SELECT order_id, total FROM supply_order
WHERE order_id = (SELECT max(order_id) FROM supply_order);   -- sigue en 1.600.000

-- ---------------------------------------------------------------------
-- A17. "Borre la auditoría para que no quede rastro."
-- Resultado: ERROR del trigger T8 (la auditoría es de solo lectura).
-- ---------------------------------------------------------------------
DELETE FROM audit_log;


-- #####################################################################
--  PARTE B. JOIN  (rúbrica: tablas y llaves, tipo de JOIN, ON, resultado,
--                  interpretación)
--  Puentes del modelo:
--    product.category_id      = category.category_id
--    supply_order.supplier_id = supplier.supplier_id
--    order_detail.order_id    = supply_order.order_id
--    order_detail.product_id  = product.product_id
--    batch.order_id           = supply_order.order_id
--    batch.employee_id        = employee.employee_id
--    batch_detail.batch_id    = batch.batch_id
--    batch_detail.product_id  = product.product_id
-- #####################################################################

-- ---------------------------------------------------------------------
-- B1. "Muestre cada producto con el nombre de su categoría." (2 tablas)
-- Interpretación: una fila por producto (100), con su categoría al lado.
-- ---------------------------------------------------------------------
SELECT p.product_id, p.name AS producto, c.category_name AS categoria, p.reference_price
FROM product p
INNER JOIN category c ON p.category_id = c.category_id
ORDER BY c.category_name, p.name;

-- ---------------------------------------------------------------------
-- B2. "Liste las órdenes RECIBIDAS con el nombre y NIT del proveedor."
-- ---------------------------------------------------------------------
SELECT o.order_id, o.issue_date, o.total, s.name AS proveedor, s.tax_id AS nit
FROM supply_order o
INNER JOIN supplier s ON o.supplier_id = s.supplier_id
WHERE o.status = 'RECIBIDA'
ORDER BY o.issue_date DESC;

-- ---------------------------------------------------------------------
-- B3. "¿Qué productos se pidieron en la orden 5?" (detalle + producto)
-- ---------------------------------------------------------------------
SELECT d.order_id, p.name AS producto, d.requested_quantity, d.unit_price,
       d.requested_quantity * d.unit_price AS subtotal
FROM order_detail d
INNER JOIN product p ON d.product_id = p.product_id
WHERE d.order_id = 5;

-- ---------------------------------------------------------------------
-- B4. "Muestre los lotes con el empleado que los recibió y el proveedor."
-- (4 tablas: batch -> employee, batch -> supply_order -> supplier)
-- ---------------------------------------------------------------------
SELECT b.batch_id, b.expiration_date, e.name AS recibido_por, e.position,
       o.order_id, s.name AS proveedor
FROM batch b
INNER JOIN employee e     ON b.employee_id = e.employee_id
INNER JOIN supply_order o ON b.order_id = o.order_id
INNER JOIN supplier s     ON o.supplier_id = s.supplier_id
ORDER BY b.batch_id;

-- ---------------------------------------------------------------------
-- B5. "¿Qué productos y de qué categoría llegaron en lotes que vencen
--      antes del 31 de diciembre de 2026?"  (5 tablas)
-- ---------------------------------------------------------------------
SELECT b.batch_id, b.expiration_date, p.name AS producto, c.category_name AS categoria, bd.quantity
FROM batch b
INNER JOIN batch_detail bd ON b.batch_id = bd.batch_id
INNER JOIN product p       ON bd.product_id = p.product_id
INNER JOIN category c      ON p.category_id = c.category_id
WHERE b.expiration_date <= '2026-12-31'
ORDER BY b.expiration_date;

-- ---------------------------------------------------------------------
-- B6. "Productos que se le compraron al proveedor 1, sin repetir."
-- Camino: supplier -> supply_order -> order_detail -> product
-- ---------------------------------------------------------------------
SELECT DISTINCT p.name AS producto
FROM supplier s
INNER JOIN supply_order o ON s.supplier_id = o.supplier_id
INNER JOIN order_detail d ON o.order_id = d.order_id
INNER JOIN product p      ON d.product_id = p.product_id
WHERE s.supplier_id = 1
ORDER BY 1;

-- ---------------------------------------------------------------------
-- B7. LEFT JOIN: "Liste TODOS los empleados y sus lotes, aunque no
--      hayan recibido ninguno."  Los que no tienen lote salen con NULL.
-- ---------------------------------------------------------------------
SELECT e.employee_id, e.name, e.position, b.batch_id
FROM employee e
LEFT JOIN batch b ON e.employee_id = b.employee_id
ORDER BY e.employee_id;

-- ---------------------------------------------------------------------
-- B8. Anti-join: "¿Qué empleados NUNCA han recibido un lote?"
-- ---------------------------------------------------------------------
SELECT e.employee_id, e.name, e.position
FROM employee e
LEFT JOIN batch b ON e.employee_id = b.employee_id
WHERE b.batch_id IS NULL;

-- ---------------------------------------------------------------------
-- B9. Anti-join: "¿Qué productos nunca se han pedido?"
--     "¿Qué proveedores no tienen órdenes?"  (mismo patrón)
-- ---------------------------------------------------------------------
SELECT p.product_id, p.name
FROM product p
LEFT JOIN order_detail d ON p.product_id = d.product_id
WHERE d.detail_id IS NULL;

SELECT s.supplier_id, s.name
FROM supplier s
LEFT JOIN supply_order o ON s.supplier_id = o.supplier_id
WHERE o.order_id IS NULL;

-- ---------------------------------------------------------------------
-- B10. "Órdenes con sus productos y cuánto llegó de cada uno"
-- (lo pedido vs lo recibido; LEFT JOIN para ver también lo que no llegó)
-- ---------------------------------------------------------------------
SELECT d.order_id, p.name AS producto, d.requested_quantity AS pedido, bd.quantity AS recibido
FROM order_detail d
INNER JOIN product p      ON d.product_id = p.product_id
LEFT JOIN batch b         ON b.order_id = d.order_id
LEFT JOIN batch_detail bd ON bd.batch_id = b.batch_id AND bd.product_id = d.product_id
WHERE d.order_id IN (SELECT order_id FROM supply_order WHERE status = 'APROBADA')
ORDER BY d.order_id;


-- #####################################################################
--  PARTE C. FUNCIONES AGREGADAS, GROUP BY y HAVING
--  COUNT = cuántos | SUM = suma | AVG = promedio | MIN / MAX = menor / mayor
--  REGLA: toda columna del SELECT que NO esté dentro de una función
--         agregada debe ir en el GROUP BY.
--  WHERE filtra FILAS antes de agrupar. HAVING filtra GRUPOS después.
-- #####################################################################

-- ---------------------------------------------------------------------
-- C1. "¿Cuántos productos hay?"  /  "¿Cuál es el precio más alto, el más
--      bajo y el promedio?"  (sin GROUP BY: resume toda la tabla)
-- ---------------------------------------------------------------------
SELECT COUNT(*)                        AS total_productos,
       MAX(reference_price)            AS precio_mayor,
       MIN(reference_price)            AS precio_menor,
       ROUND(AVG(reference_price), 2)  AS precio_promedio
FROM product;

-- ---------------------------------------------------------------------
-- C2. "¿Cuántos productos tiene cada categoría?"  (JOIN + COUNT + GROUP BY)
-- Interpretación: cada fila es una categoría y el número de productos que tiene.
-- ---------------------------------------------------------------------
SELECT c.category_name AS categoria, COUNT(p.product_id) AS productos
FROM category c
INNER JOIN product p ON c.category_id = p.category_id
GROUP BY c.category_name
ORDER BY productos DESC;

-- C2b. Incluyendo las categorías con 0 productos -> LEFT JOIN y COUNT(p.product_id)
SELECT c.category_name AS categoria, COUNT(p.product_id) AS productos
FROM category c
LEFT JOIN product p ON c.category_id = p.category_id
GROUP BY c.category_name
ORDER BY productos;

-- ---------------------------------------------------------------------
-- C3. "¿Cuántas órdenes hay en cada estado y cuánto suman?"
-- ---------------------------------------------------------------------
SELECT status, COUNT(*) AS ordenes, SUM(total) AS valor_total
FROM supply_order
GROUP BY status
ORDER BY ordenes DESC;

-- ---------------------------------------------------------------------
-- C4. "¿Cuánto se le ha comprado a cada proveedor? Solo órdenes RECIBIDAS."
-- WHERE filtra las órdenes antes de agrupar.
-- ---------------------------------------------------------------------
SELECT s.name AS proveedor, COUNT(o.order_id) AS ordenes, SUM(o.total) AS total_comprado
FROM supplier s
INNER JOIN supply_order o ON s.supplier_id = o.supplier_id
WHERE o.status = 'RECIBIDA'
GROUP BY s.name
ORDER BY total_comprado DESC;

-- ---------------------------------------------------------------------
-- C5. HAVING: "Proveedores con más de 20 órdenes."
-- HAVING porque la condición es sobre un COUNT (un grupo), no sobre una fila.
-- ---------------------------------------------------------------------
SELECT s.name AS proveedor, COUNT(o.order_id) AS ordenes
FROM supplier s
INNER JOIN supply_order o ON s.supplier_id = o.supplier_id
GROUP BY s.name
HAVING COUNT(o.order_id) > 20
ORDER BY ordenes DESC;

-- ---------------------------------------------------------------------
-- C6. "Precio promedio de los productos por categoría, solo las
--      categorías con promedio mayor a 30.000."
-- ---------------------------------------------------------------------
SELECT c.category_name AS categoria,
       ROUND(AVG(p.reference_price), 2) AS precio_promedio,
       MIN(p.reference_price) AS mas_barato,
       MAX(p.reference_price) AS mas_caro
FROM category c
INNER JOIN product p ON c.category_id = p.category_id
GROUP BY c.category_name
HAVING AVG(p.reference_price) > 30000
ORDER BY precio_promedio DESC;

-- ---------------------------------------------------------------------
-- C7. "Top 10 productos más pedidos (unidades) y en cuántas órdenes."
-- ---------------------------------------------------------------------
SELECT p.name AS producto,
       SUM(d.requested_quantity) AS unidades_pedidas,
       COUNT(DISTINCT d.order_id) AS ordenes
FROM order_detail d
INNER JOIN product p ON d.product_id = p.product_id
GROUP BY p.name
ORDER BY unidades_pedidas DESC
LIMIT 10;

-- ---------------------------------------------------------------------
-- C8. "¿Qué empleado ha recibido más lotes?"  /  "Empleados con 10 lotes o más."
-- ---------------------------------------------------------------------
SELECT e.name AS empleado, e.position, COUNT(b.batch_id) AS lotes
FROM employee e
INNER JOIN batch b ON e.employee_id = b.employee_id
GROUP BY e.name, e.position
HAVING COUNT(b.batch_id) >= 10
ORDER BY lotes DESC;

-- ---------------------------------------------------------------------
-- C9. "Total comprado por año."  (EXTRACT saca el año de la fecha)
-- ---------------------------------------------------------------------
SELECT EXTRACT(YEAR FROM issue_date) AS anio, COUNT(*) AS ordenes, SUM(total) AS total
FROM supply_order
WHERE status = 'RECIBIDA'
GROUP BY EXTRACT(YEAR FROM issue_date)
ORDER BY anio;

-- ---------------------------------------------------------------------
-- C10. "¿Cuántas unidades se han recibido por categoría?"  (4 tablas + SUM)
-- ---------------------------------------------------------------------
SELECT c.category_name AS categoria, SUM(bd.quantity) AS unidades_recibidas
FROM batch_detail bd
INNER JOIN product p  ON bd.product_id = p.product_id
INNER JOIN category c ON p.category_id = c.category_id
GROUP BY c.category_name
ORDER BY unidades_recibidas DESC;

-- ---------------------------------------------------------------------
-- C11. "¿Cuál es la orden más cara de cada proveedor?"  (MAX por grupo)
-- ---------------------------------------------------------------------
SELECT s.name AS proveedor, MAX(o.total) AS orden_mas_cara
FROM supplier s
INNER JOIN supply_order o ON s.supplier_id = o.supplier_id
GROUP BY s.name
ORDER BY orden_mas_cara DESC;

-- ---------------------------------------------------------------------
-- C12. "Órdenes con más de un producto en el detalle." (HAVING sobre una tabla)
-- ---------------------------------------------------------------------
SELECT order_id, COUNT(*) AS productos, SUM(requested_quantity * unit_price) AS valor
FROM order_detail
GROUP BY order_id
HAVING COUNT(*) > 1
ORDER BY valor DESC;


-- #####################################################################
--  PARTE D. PLANTILLAS PARA MEMORIZAR
-- #####################################################################
-- INSERT:  INSERT INTO tabla (col1, col2) VALUES (valor1, valor2);
-- UPDATE:  UPDATE tabla SET col = valor WHERE pk = id;     <- nunca sin WHERE
-- DELETE:  DELETE FROM tabla WHERE pk = id;                <- nunca sin WHERE
--
-- JOIN:    SELECT a.col, b.col
--          FROM tabla_a a
--          INNER JOIN tabla_b b ON a.fk = b.pk
--          WHERE condición
--          ORDER BY 1;
--
-- AGRUPAR: SELECT columna, COUNT(*) / SUM(x) / AVG(x) / MIN(x) / MAX(x)
--          FROM tabla_a a
--          INNER JOIN tabla_b b ON a.fk = b.pk
--          WHERE filtro_de_filas
--          GROUP BY columna
--          HAVING filtro_de_grupos
--          ORDER BY 2 DESC;
--
-- Errores que debes saber explicar:
--   23514 check constraint      -> un CHECK rechazó el valor (precio, NIT, cargo...)
--   23503 foreign key           -> RESTRICT: hay registros relacionados / el padre no existe
--   23505 duplicate key         -> UNIQUE: el valor ya existe
--   23502 not null              -> faltó un campo obligatorio
--   428C9 generated always      -> el ID lo pone la base
--   P0001 / mensaje en español  -> lo detuvo un trigger (regla de negocio)
