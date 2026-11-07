// =====================================================================
//  DEFINICIÓN DE LAS TABLAS QUE MANEJA LA PÁGINA
//  - campos: lo que aparece en el formulario (se insertan/actualizan)
//  - consulta: lo que se muestra en el listado (con JOIN para ver nombres)
//  - columnas: columnas visibles del listado [campo, título]
// =====================================================================
const UNIDADES = ['UNIDAD', 'PACA', 'CANASTA', 'CAJA', 'SIXPACK', 'FARDO', 'BOLSA'];
const CARGOS = ['AUXILIAR DE BODEGA', 'MONTACARGUISTA', 'JEFE DE BODEGA', 'ANALISTA DE INVENTARIO',
  'COORDINADOR LOGISTICO', 'SUPERVISOR DE CALIDAD', 'DESPACHADOR', 'ADMINISTRADOR'];

module.exports = {
  category: {
    titulo: 'Categorías', singular: 'categoría', femenino: true, pk: 'category_id',
    campos: [
      { nombre: 'category_name', etiqueta: 'Nombre', tipo: 'text' },
      { nombre: 'description', etiqueta: 'Descripción', tipo: 'textarea' }
    ],
    consulta: `SELECT c.category_id, c.category_name, c.description,
                      (SELECT count(*) FROM product p WHERE p.category_id = c.category_id) AS productos
                 FROM category c`,
    orden: 'category_id DESC',
    columnas: [['category_id', 'ID'], ['category_name', 'Nombre'], ['description', 'Descripción'], ['productos', 'Productos']]
  },

  product: {
    titulo: 'Productos', singular: 'producto', pk: 'product_id',
    campos: [
      { nombre: 'category_id', etiqueta: 'Categoría', tipo: 'select', opciones: 'category' },
      { nombre: 'name', etiqueta: 'Nombre', tipo: 'text' },
      { nombre: 'unit_of_measure', etiqueta: 'Unidad de medida', tipo: 'select', lista: UNIDADES },
      { nombre: 'reference_price', etiqueta: 'Precio de referencia', tipo: 'number', paso: '0.01' },
      { nombre: 'min_stock', etiqueta: 'Stock mínimo', tipo: 'number' },
      { nombre: 'max_stock', etiqueta: 'Stock máximo', tipo: 'number' }
    ],
    consulta: `SELECT p.product_id, p.category_id, c.category_name, p.name, p.unit_of_measure,
                      p.reference_price, p.min_stock, p.max_stock
                 FROM product p JOIN category c ON c.category_id = p.category_id`,
    orden: 'product_id DESC',
    columnas: [['product_id', 'ID'], ['name', 'Producto'], ['category_name', 'Categoría'], ['unit_of_measure', 'Unidad'],
      ['reference_price', 'Precio', 'dinero'], ['min_stock', 'Mín.'], ['max_stock', 'Máx.']]
  },

  supplier: {
    titulo: 'Proveedores', singular: 'proveedor', pk: 'supplier_id',
    campos: [
      { nombre: 'name', etiqueta: 'Nombre', tipo: 'text' },
      { nombre: 'tax_id', etiqueta: 'NIT (#########-#)', tipo: 'text' },
      { nombre: 'address', etiqueta: 'Dirección', tipo: 'text' }
    ],
    consulta: `SELECT s.supplier_id, s.name, s.tax_id, s.address,
                      (SELECT count(*) FROM supply_order o WHERE o.supplier_id = s.supplier_id) AS ordenes
                 FROM supplier s`,
    orden: 'supplier_id DESC',
    columnas: [['supplier_id', 'ID'], ['name', 'Proveedor'], ['tax_id', 'NIT'], ['address', 'Dirección'], ['ordenes', 'Órdenes']]
  },

  employee: {
    titulo: 'Empleados', singular: 'empleado', pk: 'employee_id',
    campos: [
      { nombre: 'name', etiqueta: 'Nombre completo', tipo: 'text' },
      { nombre: 'position', etiqueta: 'Cargo', tipo: 'select', lista: CARGOS },
      { nombre: 'username', etiqueta: 'Usuario (minúsculas, sin espacios)', tipo: 'text' }
    ],
    consulta: `SELECT e.employee_id, e.name, e.position, e.username,
                      (SELECT count(*) FROM batch b WHERE b.employee_id = e.employee_id) AS lotes
                 FROM employee e`,
    orden: 'employee_id DESC',
    columnas: [['employee_id', 'ID'], ['name', 'Nombre'], ['position', 'Cargo'], ['username', 'Usuario'], ['lotes', 'Lotes']]
  },

  supply_order: {
    titulo: 'Órdenes de abastecimiento', singular: 'orden', femenino: true, pk: 'order_id',
    campos: [
      { nombre: 'supplier_id', etiqueta: 'Proveedor', tipo: 'select', opciones: 'supplier' },
      { nombre: 'issue_date', etiqueta: 'Fecha de emisión (vacío = ahora)', tipo: 'datetime-local', omitirSiVacio: true }
    ],
    consulta: `SELECT o.order_id, o.supplier_id, s.name AS proveedor, o.issue_date, o.status, o.total,
                      (SELECT count(*) FROM order_detail d WHERE d.order_id = o.order_id) AS productos,
                      (SELECT count(*) FROM batch b WHERE b.order_id = o.order_id) AS lotes
                 FROM supply_order o JOIN supplier s ON s.supplier_id = o.supplier_id`,
    orden: 'order_id DESC',
    filtros: ['status'],
    columnas: [['order_id', 'Orden'], ['proveedor', 'Proveedor'], ['issue_date', 'Fecha', 'fechahora'],
      ['status', 'Estado', 'estado'], ['productos', 'Productos'], ['lotes', 'Lotes'], ['total', 'Total', 'dinero']]
  },

  order_detail: {
    titulo: 'Detalle de órdenes', singular: 'detalle de orden', pk: 'detail_id',
    campos: [
      { nombre: 'order_id', etiqueta: 'Orden', tipo: 'select', opciones: 'supply_order' },
      { nombre: 'product_id', etiqueta: 'Producto', tipo: 'select', opciones: 'product' },
      { nombre: 'requested_quantity', etiqueta: 'Cantidad pedida', tipo: 'number' },
      { nombre: 'unit_price', etiqueta: 'Precio unitario', tipo: 'number', paso: '0.01' }
    ],
    consulta: `SELECT d.detail_id, d.order_id, o.status, d.product_id, p.name AS producto,
                      d.requested_quantity, d.unit_price, d.requested_quantity * d.unit_price AS subtotal
                 FROM order_detail d
                 JOIN supply_order o ON o.order_id = d.order_id
                 JOIN product p ON p.product_id = d.product_id`,
    orden: 'detail_id DESC',
    filtros: ['order_id'],
    columnas: [['detail_id', 'ID'], ['order_id', 'Orden'], ['status', 'Estado orden', 'estado'], ['producto', 'Producto'],
      ['requested_quantity', 'Cantidad'], ['unit_price', 'Precio', 'dinero'], ['subtotal', 'Subtotal', 'dinero']]
  },

  batch: {
    titulo: 'Lotes', singular: 'lote', pk: 'batch_id',
    campos: [
      { nombre: 'order_id', etiqueta: 'Orden (debe estar APROBADA)', tipo: 'select', opciones: 'supply_order' },
      { nombre: 'employee_id', etiqueta: 'Recibido por', tipo: 'select', opciones: 'employee' },
      { nombre: 'expiration_date', etiqueta: 'Fecha de vencimiento', tipo: 'date' },
      { nombre: 'initial_quantity', etiqueta: 'Cantidad inicial', tipo: 'number' }
    ],
    consulta: `SELECT b.batch_id, b.order_id, o.status, b.employee_id, e.name AS empleado,
                      b.expiration_date, b.initial_quantity,
                      (SELECT COALESCE(sum(quantity), 0) FROM batch_detail bd WHERE bd.batch_id = b.batch_id) AS detallado
                 FROM batch b
                 JOIN supply_order o ON o.order_id = b.order_id
                 JOIN employee e ON e.employee_id = b.employee_id`,
    orden: 'batch_id DESC',
    filtros: ['order_id'],
    columnas: [['batch_id', 'Lote'], ['order_id', 'Orden'], ['status', 'Estado orden', 'estado'], ['empleado', 'Recibido por'],
      ['expiration_date', 'Vence', 'fecha'], ['initial_quantity', 'Cant. inicial'], ['detallado', 'Detallado']]
  },

  batch_detail: {
    titulo: 'Detalle de lotes', singular: 'detalle de lote', pk: 'batch_detail_id',
    campos: [
      { nombre: 'batch_id', etiqueta: 'Lote', tipo: 'select', opciones: 'batch' },
      { nombre: 'product_id', etiqueta: 'Producto (debe estar en la orden)', tipo: 'select', opciones: 'product' },
      { nombre: 'quantity', etiqueta: 'Cantidad', tipo: 'number' }
    ],
    consulta: `SELECT bd.batch_detail_id, bd.batch_id, b.order_id, bd.product_id, p.name AS producto,
                      bd.quantity, b.expiration_date
                 FROM batch_detail bd
                 JOIN batch b ON b.batch_id = bd.batch_id
                 JOIN product p ON p.product_id = bd.product_id`,
    orden: 'batch_detail_id DESC',
    filtros: ['batch_id'],
    columnas: [['batch_detail_id', 'ID'], ['batch_id', 'Lote'], ['order_id', 'Orden'], ['producto', 'Producto'],
      ['quantity', 'Cantidad'], ['expiration_date', 'Vence', 'fecha']]
  },

  audit_log: {
    titulo: 'Auditoría', singular: 'registro', pk: 'audit_id', soloLectura: true,
    campos: [],
    consulta: `SELECT audit_id, table_name, operation, record_id, changed_at, db_user, old_data, new_data
                 FROM audit_log`,
    orden: 'audit_id DESC',
    filtros: ['table_name', 'operation'],
    columnas: [['audit_id', 'ID'], ['changed_at', 'Fecha', 'fechahora'], ['table_name', 'Tabla'], ['operation', 'Op.', 'operacion'],
      ['record_id', 'Registro'], ['db_user', 'Usuario BD'], ['cambios', 'Cambios', 'json']]
  }
};

// Textos de las listas desplegables (id -> etiqueta legible)
module.exports.OPCIONES = {
  category: `SELECT category_id AS id, category_name AS texto FROM category ORDER BY category_name`,
  supplier: `SELECT supplier_id AS id, name || ' (' || tax_id || ')' AS texto FROM supplier ORDER BY name`,
  employee: `SELECT employee_id AS id, name || ' - ' || position AS texto FROM employee ORDER BY name`,
  product: `SELECT product_id AS id, name AS texto FROM product ORDER BY name`,
  supply_order: `SELECT o.order_id AS id, '#' || o.order_id || ' · ' || o.status || ' · ' || s.name AS texto
                   FROM supply_order o JOIN supplier s ON s.supplier_id = o.supplier_id ORDER BY o.order_id DESC`,
  batch: `SELECT b.batch_id AS id, 'Lote ' || b.batch_id || ' · orden #' || b.order_id || ' · ' || o.status AS texto
            FROM batch b JOIN supply_order o ON o.order_id = b.order_id ORDER BY b.batch_id DESC`
};
