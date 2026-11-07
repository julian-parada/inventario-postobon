// =====================================================================
//  SERVIDOR - Inventario Postobón
//  Une la página web (carpeta public) con la base de datos PostgreSQL.
//  El navegador NO puede hablar directo con PostgreSQL: este servidor
//  recibe las peticiones de la página y ejecuta el SQL.
//  Todas las consultas usan parámetros ($1, $2...) -> no hay inyección SQL.
// =====================================================================
const express = require('express');
const path = require('path');
const { Pool, types } = require('pg');
const config = require('./config');
const TABLAS = require('./tablas');

// Fechas y números se devuelven como texto tal cual vienen de PostgreSQL
types.setTypeParser(1082, v => v);   // date
types.setTypeParser(1184, v => v);   // timestamptz
types.setTypeParser(1114, v => v);   // timestamp

const pool = new Pool(config.connectionString
  ? { connectionString: config.connectionString, ssl: config.ssl }
  : { host: config.host, port: config.port, user: config.user, password: config.password,
      database: config.database, ssl: config.ssl });

// Cada conexión trabaja sobre el esquema del proyecto y en hora de Colombia.
// Se fija con SET la primera vez que se usa la conexión (el pooler de Supabase
// no admite el parámetro "options" al conectar).
async function consultar(sql, params) {
  const client = await pool.connect();
  try {
    if (!client.__preparado) {
      await client.query(`SET search_path TO ${config.schema}; SET timezone TO 'America/Bogota'`);
      client.__preparado = true;
    }
    return await client.query(sql, params);
  } finally {
    client.release();
  }
}

const app = express();
app.use(express.json());

// Acceso protegido (opcional): si APP_USUARIO y APP_CLAVE están definidos, el
// navegador pide usuario y contraseña antes de mostrar la página. Se usa al
// publicar la página en internet para que solo entre quien tenga la clave.
// .trim(): el panel de Render es un cuadro de texto y es fácil dejar un espacio o un Enter al final.
const APP_USUARIO = (process.env.APP_USUARIO || '').trim();
const APP_CLAVE = (process.env.APP_CLAVE || '').trim();
if (APP_USUARIO && APP_CLAVE) {
  app.use((req, res, next) => {
    const [tipo, valor] = (req.headers.authorization || '').split(' ');
    if (tipo === 'Basic' && valor) {
      const texto = Buffer.from(valor, 'base64').toString();
      const i = texto.indexOf(':');
      if (texto.slice(0, i).trim().toLowerCase() === APP_USUARIO.toLowerCase() && texto.slice(i + 1).trim() === APP_CLAVE) return next();
    }
    res.set('WWW-Authenticate', 'Basic realm="Inventario Postobon", charset="UTF-8"').status(401).send('Acceso restringido');
  });
}
app.use(express.static(path.join(__dirname, 'public')));

// ---------------------------------------------------------------------
// Traduce los errores de PostgreSQL a un mensaje claro para la página
// ---------------------------------------------------------------------
const TITULOS = {
  '23503': 'Bloqueado por llave foránea (ON DELETE RESTRICT)',
  '23505': 'Valor duplicado (UNIQUE)',
  '23514': 'Regla de la base de datos (CHECK / trigger)',
  '23502': 'Campo obligatorio (NOT NULL)',
  '22001': 'Texto demasiado largo',
  '22P02': 'Tipo de dato inválido',
  '22003': 'Número fuera de rango',
  '22007': 'Fecha inválida',
  '22008': 'Fecha fuera de rango',
  '428C9': 'ID automático (GENERATED ALWAYS)',
  '42501': 'Operación prohibida (trigger de protección)',
  'P0001': 'Regla de negocio (trigger)'
};

function responderError(res, err) {
  if (err.code === 'ECONNREFUSED' || err.code === '28P01' || err.code === '3D000') {
    return res.status(503).json({
      titulo: 'No hay conexión con PostgreSQL',
      mensaje: err.code === '28P01' ? 'Contraseña incorrecta: revise el archivo .env'
             : err.code === '3D000' ? 'La base de datos indicada en .env no existe'
             : 'Revise que PostgreSQL esté encendido y los datos del archivo .env',
      codigo: err.code
    });
  }
  res.status(400).json({
    titulo: TITULOS[err.code] || 'Error de la base de datos',
    mensaje: err.message,
    detalle: err.detail || null,
    restriccion: err.constraint || null,
    codigo: err.code || null
  });
}

function tablaValida(req, res) {
  const t = TABLAS[req.params.tabla];
  if (!t) { res.status(404).json({ titulo: 'Tabla no encontrada', mensaje: req.params.tabla }); return null; }
  return t;
}

// Convierte lo que llega del formulario: '' -> NULL (para que la BD decida)
function valoresDelFormulario(tabla, cuerpo) {
  const cols = [], vals = [];
  for (const c of tabla.campos) {
    if (!(c.nombre in cuerpo)) continue;
    let v = cuerpo[c.nombre];
    if (typeof v === 'string') v = v.trim() === '' ? null : v;
    if (v === null && c.omitirSiVacio) continue;     // deja que actúe el DEFAULT
    if (v !== null && c.tipo === 'datetime-local') v = v + ':00-05:00';  // hora de Colombia
    cols.push(c.nombre); vals.push(v);
  }
  return { cols, vals };
}

// ---------------------------------------------------------------------
// API
// ---------------------------------------------------------------------
// Estructura de las tablas para que la página arme formularios y listados
app.get('/api/config', (req, res) => {
  const salida = {};
  for (const [k, t] of Object.entries(TABLAS)) {
    salida[k] = { titulo: t.titulo, singular: t.singular, femenino: !!t.femenino, pk: t.pk, campos: t.campos,
                  columnas: t.columnas, filtros: t.filtros || [], soloLectura: !!t.soloLectura };
  }
  res.json(salida);
});

// Panel de inicio
app.get('/api/resumen', async (req, res) => {
  try {
    const conteos = await consultar(`
      SELECT (SELECT count(*) FROM category)     AS category,
             (SELECT count(*) FROM product)      AS product,
             (SELECT count(*) FROM supplier)     AS supplier,
             (SELECT count(*) FROM employee)     AS employee,
             (SELECT count(*) FROM supply_order) AS supply_order,
             (SELECT count(*) FROM order_detail) AS order_detail,
             (SELECT count(*) FROM batch)        AS batch,
             (SELECT count(*) FROM batch_detail) AS batch_detail,
             (SELECT count(*) FROM audit_log)    AS audit_log`);
    const estados = await consultar(`
      SELECT status, count(*) AS ordenes, COALESCE(sum(total), 0) AS valor
        FROM supply_order GROUP BY status`);
    const vencer = await consultar(`
      SELECT b.batch_id, b.expiration_date, b.expiration_date - current_date AS dias,
             p.name AS producto, bd.quantity
        FROM batch b JOIN batch_detail bd ON bd.batch_id = b.batch_id
        JOIN product p ON p.product_id = bd.product_id
       WHERE b.expiration_date BETWEEN current_date AND current_date + 30
       ORDER BY b.expiration_date LIMIT 8`);
    const bajo = await consultar(`
      SELECT p.product_id, p.name, p.min_stock, COALESCE(sum(bd.quantity), 0) AS existencia
        FROM product p
        LEFT JOIN batch_detail bd ON bd.product_id = p.product_id
         AND EXISTS (SELECT 1 FROM batch b WHERE b.batch_id = bd.batch_id AND b.expiration_date >= current_date)
       GROUP BY p.product_id, p.name, p.min_stock
      HAVING COALESCE(sum(bd.quantity), 0) < p.min_stock
       ORDER BY existencia, p.name LIMIT 8`);
    const auditoria = await consultar(`
      SELECT audit_id, table_name, operation, record_id, changed_at, db_user
        FROM audit_log ORDER BY audit_id DESC LIMIT 8`);
    res.json({ conteos: conteos.rows[0], estados: estados.rows, vencer: vencer.rows,
               bajo: bajo.rows, auditoria: auditoria.rows });
  } catch (err) { responderError(res, err); }
});

// Opciones de las listas desplegables
app.get('/api/opciones/:tabla', async (req, res) => {
  const sql = TABLAS.OPCIONES[req.params.tabla];
  if (!sql) return res.status(404).json({ titulo: 'Sin opciones', mensaje: req.params.tabla });
  try { res.json((await consultar(sql)).rows); } catch (err) { responderError(res, err); }
});

// Listado con búsqueda, filtros y paginación
app.get('/api/:tabla', async (req, res) => {
  const t = tablaValida(req, res); if (!t) return;
  const pagina = Math.max(1, parseInt(req.query.pagina) || 1);
  const porPagina = Math.min(100, Math.max(5, parseInt(req.query.porPagina) || 20));
  const condiciones = [], params = [];
  if (req.query.buscar) {
    params.push('%' + req.query.buscar + '%');
    condiciones.push(`CAST(q AS text) ILIKE $${params.length}`);
  }
  for (const f of t.filtros || []) {
    if (req.query[f] !== undefined && req.query[f] !== '') {
      params.push(req.query[f]);
      condiciones.push(`q.${f}::text = $${params.length}`);
    }
  }
  const where = condiciones.length ? 'WHERE ' + condiciones.join(' AND ') : '';
  try {
    const total = await consultar(`SELECT count(*) FROM (${t.consulta}) q ${where}`, params);
    params.push(porPagina, (pagina - 1) * porPagina);
    const filas = await consultar(
      `SELECT * FROM (${t.consulta}) q ${where} ORDER BY ${t.orden}
        LIMIT $${params.length - 1} OFFSET $${params.length}`, params);
    res.json({ filas: filas.rows, total: parseInt(total.rows[0].count), pagina, porPagina });
  } catch (err) { responderError(res, err); }
});

// Una fila (para editar)
app.get('/api/:tabla/:id', async (req, res) => {
  const t = tablaValida(req, res); if (!t) return;
  try {
    const r = await consultar(`SELECT * FROM ${req.params.tabla} WHERE ${t.pk} = $1`, [req.params.id]);
    if (!r.rows.length) return res.status(404).json({ titulo: 'No existe', mensaje: `ID ${req.params.id}` });
    res.json(r.rows[0]);
  } catch (err) { responderError(res, err); }
});

// Crear
app.post('/api/:tabla', async (req, res) => {
  const t = tablaValida(req, res); if (!t) return;
  if (t.soloLectura) return res.status(403).json({ titulo: 'Solo lectura', mensaje: 'Esta tabla la llenan los triggers' });
  const { cols, vals } = valoresDelFormulario(t, req.body);
  const sql = cols.length
    ? `INSERT INTO ${req.params.tabla} (${cols.join(', ')}) VALUES (${cols.map((_, i) => '$' + (i + 1)).join(', ')}) RETURNING *`
    : `INSERT INTO ${req.params.tabla} DEFAULT VALUES RETURNING *`;
  try { res.status(201).json((await consultar(sql, vals)).rows[0]); }
  catch (err) { responderError(res, err); }
});

// Actualizar (incluye cambio de estado de una orden)
app.put('/api/:tabla/:id', async (req, res) => {
  const t = tablaValida(req, res); if (!t) return;
  if (t.soloLectura) return res.status(403).json({ titulo: 'Solo lectura', mensaje: 'Esta tabla no se puede modificar' });
  let { cols, vals } = valoresDelFormulario(t, req.body);
  if (req.params.tabla === 'supply_order' && req.body.status) { cols.push('status'); vals.push(req.body.status); }
  if (!cols.length) return res.status(400).json({ titulo: 'Sin cambios', mensaje: 'No llegó ningún campo' });
  vals.push(req.params.id);
  const sql = `UPDATE ${req.params.tabla} SET ${cols.map((c, i) => `${c} = $${i + 1}`).join(', ')}
                WHERE ${t.pk} = $${vals.length} RETURNING *`;
  try {
    const r = await consultar(sql, vals);
    if (!r.rows.length) return res.status(404).json({ titulo: 'No existe', mensaje: `ID ${req.params.id}` });
    res.json(r.rows[0]);
  } catch (err) { responderError(res, err); }
});

// Eliminar (si tiene registros relacionados, la FK RESTRICT lo impide)
app.delete('/api/:tabla/:id', async (req, res) => {
  const t = tablaValida(req, res); if (!t) return;
  if (t.soloLectura) {
    // Se intenta igual para demostrar que el trigger T8 lo bloquea
    try { await consultar(`DELETE FROM audit_log WHERE audit_id = $1`, [req.params.id]); }
    catch (err) { return responderError(res, err); }
  }
  try {
    const r = await consultar(`DELETE FROM ${req.params.tabla} WHERE ${t.pk} = $1`, [req.params.id]);
    if (!r.rowCount) return res.status(404).json({ titulo: 'No existe', mensaje: `ID ${req.params.id}` });
    res.json({ eliminado: true });
  } catch (err) { responderError(res, err); }
});

app.listen(config.puertoWeb, async () => {
  console.log(`\n  Inventario Postobón -> http://localhost:${config.puertoWeb}\n`);
  try {
    await consultar('SELECT 1 FROM category LIMIT 1');
    console.log(`  Conectado a PostgreSQL (esquema "${config.schema}")\n`);
  } catch (err) {
    console.log('  ATENCIÓN: no se pudo conectar a PostgreSQL ->', err.message);
    console.log('  Revise el archivo .env (contraseña, base, servidor) y que hayan corrido sql/01_ddl.sql\n');
  }
});
