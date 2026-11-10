-- =====================================================================
--  ARCHIVO 07: SEGURIDAD - ROLES Y PERMISOS (pruebas SEC-01 y SEC-02)
--  Los usuarios de registro y de consulta NO deben usar el superusuario
--  postgres: con él se pueden desactivar triggers o borrar tablas.
-- =====================================================================
SET search_path TO inventario_postobon;

-- Rol de solo consulta (reportes, analistas)
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'consulta_inventario') THEN
    EXECUTE 'DROP OWNED BY consulta_inventario';     -- quita sus permisos anteriores
    EXECUTE 'DROP ROLE consulta_inventario';
  END IF;
END $$;
CREATE ROLE consulta_inventario LOGIN PASSWORD 'Consulta2026';
GRANT USAGE ON SCHEMA inventario_postobon TO consulta_inventario;
GRANT SELECT ON inventario_postobon.category, inventario_postobon.product, inventario_postobon.supplier, inventario_postobon.employee, 
                inventario_postobon.supply_order, inventario_postobon.order_detail, inventario_postobon.batch, inventario_postobon.batch_detail TO consulta_inventario;
-- audit_log NO se comparte: solo la ve el administrador.

-- Rol de registro (personal de bodega): lee y escribe datos, pero no cambia la estructura
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_inventario') THEN
    EXECUTE 'DROP OWNED BY app_inventario';     -- quita sus permisos anteriores
    EXECUTE 'DROP ROLE app_inventario';
  END IF;
END $$;
CREATE ROLE app_inventario LOGIN PASSWORD 'App2026*';
GRANT USAGE ON SCHEMA inventario_postobon TO app_inventario;
GRANT SELECT, INSERT, UPDATE, DELETE ON inventario_postobon.category, inventario_postobon.product, inventario_postobon.supplier, inventario_postobon.employee, 
      inventario_postobon.supply_order, inventario_postobon.order_detail, inventario_postobon.batch, inventario_postobon.batch_detail TO app_inventario;
GRANT SELECT ON inventario_postobon.audit_log TO app_inventario;
GRANT INSERT ON inventario_postobon.audit_log TO app_inventario;                 -- la usan los triggers
GRANT USAGE ON ALL SEQUENCES IN SCHEMA inventario_postobon TO app_inventario;

-- Comprobación (conectarse como consulta_inventario):
--   SELECT count(*) FROM product;            -> permitido
--   SELECT * FROM audit_log;                 -> ERROR permiso denegado
--   DELETE FROM product WHERE product_id = 1;-> ERROR permiso denegado
--   ALTER TABLE product DISABLE TRIGGER ALL; -> ERROR debe ser dueño de la tabla
