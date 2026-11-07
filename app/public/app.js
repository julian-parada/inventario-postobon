// =====================================================================
//  PÁGINA - Inventario Postobón
//  Pide los datos al servidor (server.js) con fetch y arma la interfaz.
// =====================================================================
const $ = sel => document.querySelector(sel);
const estado = { config: null, tabla: 'inicio', pagina: 1, buscar: '', filtros: {}, editando: null, conteos: {} };
const ESTADOS = ['PENDIENTE', 'APROBADA', 'RECIBIDA', 'CANCELADA'];
const COLORES_ESTADO = { PENDIENTE: '#f28c00', APROBADA: '#1556c4', RECIBIDA: '#1f9d55', CANCELADA: '#94a3b8' };
const MENU = [
  ['General', [['inicio', 'Inicio']]],
  ['Catálogos', [['category', 'Categorías'], ['product', 'Productos'], ['supplier', 'Proveedores'], ['employee', 'Empleados']]],
  ['Operación', [['supply_order', 'Órdenes'], ['order_detail', 'Detalle de órdenes'], ['batch', 'Lotes'], ['batch_detail', 'Detalle de lotes']]],
  ['Control', [['audit_log', 'Auditoría']]]
];
const NOMBRES_TABLA = { category: 'Categorías', product: 'Productos', supplier: 'Proveedores', employee: 'Empleados',
  supply_order: 'Órdenes', order_detail: 'Detalle de órdenes', batch: 'Lotes', batch_detail: 'Detalle de lotes', audit_log: 'Auditoría' };

// ---------------------------------------------------------------- utilidades
const esc = v => String(v ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const dinero = v => { if (v == null) return ''; const n = Number(v), d = Number.isInteger(n) ? 0 : 2;
  return '$' + n.toLocaleString('es-CO', { minimumFractionDigits: d, maximumFractionDigits: d }); };
const dineroCorto = v => '$' + Math.round(Number(v)).toLocaleString('es-CO');
const nuevo = t => (t.femenino ? 'Nueva ' : 'Nuevo ') + t.singular;
const mayus = s => s[0].toUpperCase() + s.slice(1);
const entero = v => Number(v).toLocaleString('es-CO');
const fecha = v => v ? String(v).slice(0, 10).split('-').reverse().join('/') : '';
const fechaHora = v => v ? fecha(v) + ' ' + String(v).slice(11, 16) : '';

async function api(metodo, ruta, cuerpo) {
  const r = await fetch('/api/' + ruta, {
    method: metodo,
    headers: cuerpo ? { 'Content-Type': 'application/json' } : {},
    body: cuerpo ? JSON.stringify(cuerpo) : undefined
  });
  const datos = await r.json().catch(() => ({ titulo: 'Respuesta inválida', mensaje: r.statusText }));
  if (!r.ok) { const e = new Error(datos.mensaje); e.datos = datos; throw e; }
  return datos;
}

// ---------------------------------------------------------------- avisos y bitácora
function aviso(tipo, titulo, lineas = [], extra = '') {
  const div = document.createElement('div');
  div.className = 'aviso ' + tipo;
  div.innerHTML = `<button class="cerrar" aria-label="Cerrar">×</button><strong>${esc(titulo)}</strong>` +
    lineas.filter(Boolean).map(l => `<p>${esc(l)}</p>`).join('') + (extra ? `<p class="extra">${esc(extra)}</p>` : '');
  div.querySelector('.cerrar').onclick = () => div.remove();
  $('#avisos').prepend(div);
  while ($('#avisos').children.length > 3) $('#avisos').lastElementChild.remove();
  setTimeout(() => div.remove(), tipo === 'error' ? 12000 : 3000);
}

function registrar(ok, accion, titulo, mensaje, extra) {
  const li = document.createElement('li');
  li.className = ok ? '' : 'error';
  const hora = new Date().toLocaleTimeString('es-CO');
  li.innerHTML = `<small>${hora} · ${esc(accion)}</small><strong>${ok ? 'ACEPTADO' : 'RECHAZADO'}</strong> ${esc(titulo)}` +
    (mensaje ? `<div>${esc(mensaje)}</div>` : '') + (extra ? `<code>${esc(extra)}</code>` : '');
  $('#listaBitacora').prepend(li);
  $('#contadorBitacora').textContent = $('#listaBitacora').children.length;
}

function mostrarError(err, accion) {
  const d = err.datos || { titulo: 'Sin conexión con el servidor', mensaje: 'Revise que "npm start" siga corriendo' };
  const extra = [d.restriccion && 'restricción: ' + d.restriccion, d.codigo && 'código: ' + d.codigo].filter(Boolean).join(' · ');
  aviso('error', d.titulo, [d.mensaje, d.detalle], extra);
  registrar(false, accion, d.titulo, d.mensaje, extra);
}

// ---------------------------------------------------------------- menú
function pintarMenu() {
  $('#menu').innerHTML = MENU.map(([grupo, items]) =>
    `<div class="grupo-menu">${grupo}</div>` + items.map(([id, texto]) =>
      `<a href="#${id}" data-tabla="${id}" class="${estado.tabla === id ? 'activo' : ''}">
         <span>${texto}</span><span class="cuenta">${estado.conteos[id] != null ? entero(estado.conteos[id]) : ''}</span></a>`
    ).join('')).join('');
}

function ir(tabla, filtros = {}) {
  estado.tabla = tabla; estado.pagina = 1; estado.buscar = ''; estado.filtros = filtros;
  history.replaceState(null, '', '#' + tabla);
  $('#lateral').classList.remove('abierto');
  pintarMenu();
  tabla === 'inicio' ? pintarInicio() : pintarTabla();
}

// ---------------------------------------------------------------- inicio
const SABORES = ['#e3001b', '#f28c00', '#ffc20e', '#1f9d55', '#1556c4', '#7b3fc4'];

// Botella genérica dibujada en SVG (decoración, no es un logo)
const botella = (color, alto) => `<svg width="${Math.round(alto * .38)}" height="${alto}" viewBox="0 0 40 110" aria-hidden="true">
  <path d="M15 2h10v14c0 6 9 10 9 22v64a6 6 0 0 1-6 6H12a6 6 0 0 1-6-6V38c0-12 9-16 9-22z" fill="${color}" stroke="rgba(255,255,255,.75)" stroke-width="2"/>
  <rect x="6" y="54" width="28" height="24" fill="rgba(255,255,255,.88)"/><rect x="13" y="0" width="14" height="6" rx="2" fill="#fff"/>
  <path d="M11 40c0-8 5-12 6-18" stroke="rgba(255,255,255,.45)" stroke-width="3" fill="none" stroke-linecap="round"/></svg>`;

function portadaInicio(conteos) {
  const burbujas = [[62, 8, 30], [70, 58, 58], [88, 12, 26], [96, 70, 18], [56, 74, 16], [80, 34, 14]]
    .map(([x, y, s], i) => `<i class="burbuja" style="left:${x}%;top:${y}%;width:${s}px;height:${s}px;animation-delay:-${i * 1.3}s"></i>`).join('');
  const lotes = entero(conteos.batch || 0), ordenes = entero(conteos.supply_order || 0);
  return `<section class="hero">${burbujas}
    <div class="texto">
      <span class="chip-hero">Datos en vivo · PostgreSQL</span>
      <h2>Centro de distribución <span>Ocaña</span></h2>
      <p>Control de inventario de bebidas: ${ordenes} órdenes de compra y ${lotes} lotes recibidos, validados por la base de datos.</p>
    </div>
    <div class="botellas">${[['#e3001b', 86], ['#f28c00', 104], ['#7b3fc4', 76], ['#1f9d55', 96], ['#ffc20e', 82]].map(([c, a]) => botella(c, a)).join('')}</div>
  </section>`;
}

async function pintarInicio() {
  $('#tituloVista').textContent = 'Inicio';
  $('#subtituloVista').textContent = 'Resumen del inventario en PostgreSQL';
  $('#vista').innerHTML = '<p class="sub">Cargando…</p>';
  try {
    const r = await api('GET', 'resumen');
    estado.conteos = r.conteos; pintarMenu();
    const maxEstado = Math.max(1, ...r.estados.map(e => +e.ordenes));
    const porEstado = Object.fromEntries(r.estados.map(e => [e.status, e]));
    $('#vista').innerHTML = `
      ${portadaInicio(r.conteos)}
      <div class="kpis">
        ${Object.entries(r.conteos).map(([t, n], i) =>
          `<div class="kpi" data-ir="${t}" style="--color:${SABORES[i % SABORES.length]}"><span>${NOMBRES_TABLA[t]}</span><strong>${entero(n)}</strong></div>`).join('')}
      </div>
      <div class="rejilla">
        <div class="tarjeta">
          <h3>Órdenes por estado</h3><p class="sub">Cantidad de órdenes y valor total</p>
          <div class="barras">${ESTADOS.map(s => {
            const e = porEstado[s] || { ordenes: 0, valor: 0 };
            return `<div class="fila-barra"><span class="estado ${s}">${s}</span>
              <div class="pista"><div class="relleno" style="width:${(e.ordenes / maxEstado) * 100}%;background:${COLORES_ESTADO[s]}"></div></div>
              <span class="valor">${entero(e.ordenes)} · ${dineroCorto(e.valor)}</span></div>`;
          }).join('')}</div>
        </div>
        <div class="tarjeta">
          <h3>Lotes que vencen en 30 días</h3><p class="sub">Lotes vigentes ordenados por fecha</p>
          <ul class="lista-simple">${r.vencer.length ? r.vencer.map(v =>
            `<li><span>Lote ${v.batch_id} · ${esc(v.producto)}</span><span>${fecha(v.expiration_date)} (${v.dias} d)</span></li>`).join('')
            : '<li class="vacio">Ninguno</li>'}</ul>
        </div>
        <div class="tarjeta">
          <h3>Productos bajo el stock mínimo</h3><p class="sub">Existencia en lotes vigentes vs. mínimo</p>
          <ul class="lista-simple">${r.bajo.length ? r.bajo.map(p =>
            `<li><span>${esc(p.name)}</span><span>${entero(p.existencia)} / mín. ${entero(p.min_stock)}</span></li>`).join('')
            : '<li class="vacio">Ninguno</li>'}</ul>
        </div>
        <div class="tarjeta">
          <h3>Últimos cambios (auditoría)</h3><p class="sub">Registrados automáticamente por triggers</p>
          <ul class="lista-simple">${r.auditoria.length ? r.auditoria.map(a =>
            `<li><span><span class="op ${a.operation}">${a.operation}</span> ${esc(NOMBRES_TABLA[a.table_name] || a.table_name)} #${a.record_id}</span>
             <span>${fechaHora(a.changed_at)}</span></li>`).join('') : '<li class="vacio">Sin registros</li>'}</ul>
        </div>
      </div>`;
    $('#vista').querySelectorAll('[data-ir]').forEach(k => k.onclick = () => ir(k.dataset.ir));
  } catch (err) {
    mostrarError(err, 'Cargar resumen');
    $('#vista').innerHTML = `<div class="tarjeta"><h3>No hay conexión con la base de datos</h3>
      <p class="sub">${esc(err.datos?.mensaje || 'El servidor no responde')}</p></div>`;
  }
}

// ---------------------------------------------------------------- listado
function celda(fila, [campo, , tipo]) {
  const v = fila[campo];
  switch (tipo) {
    case 'dinero': return `<td class="num">${dinero(v)}</td>`;
    case 'fecha': return `<td>${fecha(v)}</td>`;
    case 'fechahora': return `<td>${fechaHora(v)}</td>`;
    case 'estado': return `<td><span class="estado ${esc(v)}">${esc(v)}</span></td>`;
    case 'operacion': return `<td><span class="op ${esc(v)}">${esc(v)}</span></td>`;
    case 'json': return `<td class="json">${resumenCambios(fila)}</td>`;
    default: return typeof v === 'number' || /^-?\d+(\.\d+)?$/.test(v ?? '') && campo !== 'tax_id'
      ? `<td class="num">${esc(v)}</td>` : `<td>${esc(v)}</td>`;
  }
}

function resumenCambios(f) {
  const nuevo = f.new_data || {}, viejo = f.old_data || {};
  const nombre = d => d.name || d.category_name || d.status || '';
  if (f.operation === 'I') return `<div>Creado: <ins>${esc(nombre(nuevo))}</ins></div>`;
  if (f.operation === 'D') return `<div>Eliminado: <del>${esc(nombre(viejo))}</del></div>`;
  const difs = Object.keys(nuevo).filter(k => JSON.stringify(nuevo[k]) !== JSON.stringify(viejo[k]));
  return difs.map(k => `<div>${esc(k)}: <del>${esc(viejo[k])}</del> → <ins>${esc(nuevo[k])}</ins></div>`).join('') || '<div>Sin cambios</div>';
}

function accionesFila(t, fila) {
  const id = fila[t.pk];
  let html = '';
  if (estado.tabla === 'supply_order') {
    html += `<select class="cambio-estado" data-id="${id}" title="Cambiar estado (lo valida el trigger)">
      <option value="">Estado…</option>${ESTADOS.filter(s => s !== fila.status).map(s => `<option>${s}</option>`).join('')}</select>
      <button class="boton fantasma chico" data-ver="order_detail" data-filtro="order_id" data-id="${id}">Productos</button>
      <button class="boton fantasma chico" data-ver="batch" data-filtro="order_id" data-id="${id}">Lotes</button>`;
  }
  if (estado.tabla === 'batch') {
    html += `<button class="boton fantasma chico" data-ver="batch_detail" data-filtro="batch_id" data-id="${id}">Productos</button>`;
  }
  if (!t.soloLectura) html += `<button class="boton fantasma chico" data-editar="${id}">Editar</button>`;
  html += `<button class="boton peligro chico" data-eliminar="${id}">Eliminar</button>`;
  return `<td class="acciones">${html}</td>`;
}

async function pintarTabla() {
  const t = estado.config[estado.tabla];
  $('#tituloVista').textContent = t.titulo;
  $('#subtituloVista').textContent = t.soloLectura
    ? 'Solo lectura: la llenan los triggers y nadie puede editarla ni borrarla'
    : 'Crear, editar y eliminar registros directamente en PostgreSQL';

  const filtrosHtml = (t.filtros || []).map(f => {
    if (f === 'status') return `<select data-filtro="status"><option value="">Todos los estados</option>
      ${ESTADOS.map(s => `<option ${estado.filtros.status === s ? 'selected' : ''}>${s}</option>`).join('')}</select>`;
    if (f === 'operation') return `<select data-filtro="operation"><option value="">Todas las operaciones</option>
      ${[['I', 'Insert'], ['U', 'Update'], ['D', 'Delete']].map(([v, n]) => `<option value="${v}" ${estado.filtros.operation === v ? 'selected' : ''}>${n}</option>`).join('')}</select>`;
    if (f === 'table_name') return `<select data-filtro="table_name"><option value="">Todas las tablas</option>
      ${['category', 'product', 'supplier', 'employee', 'supply_order'].map(v => `<option value="${v}" ${estado.filtros.table_name === v ? 'selected' : ''}>${NOMBRES_TABLA[v]}</option>`).join('')}</select>`;
    if (estado.filtros[f]) return `<span class="chip">${f === 'order_id' ? 'Orden' : 'Lote'} #${esc(estado.filtros[f])}
      <button data-quitar="${f}" aria-label="Quitar filtro">×</button></span>`;
    return '';
  }).join('');

  $('#vista').innerHTML = `
    <div class="herramientas">
      <input type="search" id="buscar" placeholder="Buscar en ${t.titulo.toLowerCase()}…" value="${esc(estado.buscar)}">
      ${filtrosHtml}
      <span class="espacio"></span>
      ${t.soloLectura ? '' : `<button class="boton primario" id="botonNuevo">+ ${nuevo(t)}</button>`}
    </div>
    <div class="contenedor-tabla"><table>
      <thead><tr>${t.columnas.map(([c, n, tipo]) => `<th class="${tipo === 'dinero' ? 'num' : ''}">${n}</th>`).join('')}<th></th></tr></thead>
      <tbody id="cuerpo"><tr><td class="vacia" colspan="99">Cargando…</td></tr></tbody>
    </table></div>
    <div class="paginacion" id="paginacion"></div>`;

  let espera;
  $('#buscar').oninput = e => { clearTimeout(espera); espera = setTimeout(() => { estado.buscar = e.target.value; estado.pagina = 1; cargarFilas(); }, 300); };
  $('#vista').querySelectorAll('select[data-filtro]').forEach(s => s.onchange = () => {
    estado.filtros[s.dataset.filtro] = s.value; estado.pagina = 1; cargarFilas(); });
  $('#vista').querySelectorAll('[data-quitar]').forEach(b => b.onclick = () => { delete estado.filtros[b.dataset.quitar]; pintarTabla(); });
  if ($('#botonNuevo')) $('#botonNuevo').onclick = () => abrirFormulario(null);
  cargarFilas();
}

async function cargarFilas() {
  const t = estado.config[estado.tabla];
  const q = new URLSearchParams({ pagina: estado.pagina, porPagina: 20, buscar: estado.buscar });
  for (const [k, v] of Object.entries(estado.filtros)) if (v) q.set(k, v);
  try {
    const r = await api('GET', `${estado.tabla}?${q}`);
    $('#cuerpo').innerHTML = r.filas.length
      ? r.filas.map(f => `<tr>${t.columnas.map(c => celda(f, c)).join('')}${accionesFila(t, f)}</tr>`).join('')
      : `<tr><td class="vacia" colspan="99">No hay registros${estado.buscar ? ' que coincidan con la búsqueda' : ''}</td></tr>`;
    const paginas = Math.max(1, Math.ceil(r.total / r.porPagina));
    $('#paginacion').innerHTML = `<span>${entero(r.total)} registros · página ${r.pagina} de ${paginas}</span>
      <div><button class="boton fantasma chico" id="anterior" ${r.pagina <= 1 ? 'disabled' : ''}>← Anterior</button>
      <button class="boton fantasma chico" id="siguiente" ${r.pagina >= paginas ? 'disabled' : ''}>Siguiente →</button></div>`;
    $('#anterior').onclick = () => { estado.pagina--; cargarFilas(); };
    $('#siguiente').onclick = () => { estado.pagina++; cargarFilas(); };
    conectarAcciones();
  } catch (err) {
    mostrarError(err, 'Listar ' + t.titulo);
    $('#cuerpo').innerHTML = `<tr><td class="vacia" colspan="99">No se pudieron cargar los datos</td></tr>`;
  }
}

function conectarAcciones() {
  const v = $('#vista');
  v.querySelectorAll('[data-editar]').forEach(b => b.onclick = () => abrirFormulario(b.dataset.editar));
  v.querySelectorAll('[data-eliminar]').forEach(b => b.onclick = () => eliminar(b.dataset.eliminar));
  v.querySelectorAll('[data-ver]').forEach(b => b.onclick = () => ir(b.dataset.ver, { [b.dataset.filtro]: b.dataset.id }));
  v.querySelectorAll('select.cambio-estado').forEach(s => s.onchange = () => cambiarEstado(s.dataset.id, s.value));
}

// ---------------------------------------------------------------- formulario
const cacheOpciones = {};
async function opciones(tabla) {
  if (!cacheOpciones[tabla]) cacheOpciones[tabla] = await api('GET', 'opciones/' + tabla);
  return cacheOpciones[tabla];
}

function valorParaInput(campo, v) {
  if (v == null) return '';
  if (campo.tipo === 'date') return String(v).slice(0, 10);
  if (campo.tipo === 'datetime-local') return String(v).slice(0, 16).replace(' ', 'T');
  return v;
}

async function abrirFormulario(id) {
  const t = estado.config[estado.tabla];
  estado.editando = id;
  $('#tituloModal').textContent = id ? `Editar ${t.singular} #${id}` : nuevo(t);
  $('#camposModal').innerHTML = '<p class="sub">Cargando…</p>';
  $('#modal').showModal();
  try {
    const fila = id ? await api('GET', `${estado.tabla}/${id}`) : {};
    // valores sugeridos al crear desde un filtro (ej. agregar producto a la orden #5)
    if (!id) for (const [k, v] of Object.entries(estado.filtros)) if (t.campos.some(c => c.nombre === k)) fila[k] = v;
    const html = [];
    for (const c of t.campos) {
      const v = valorParaInput(c, fila[c.nombre]);
      let control;
      if (c.tipo === 'select') {
        const ops = c.lista ? c.lista.map(x => ({ id: x, texto: x })) : await opciones(c.opciones);
        control = `<select name="${c.nombre}"><option value="">— Seleccione —</option>
          ${ops.map(o => `<option value="${esc(o.id)}" ${String(o.id) === String(v) ? 'selected' : ''}>${esc(o.texto)}</option>`).join('')}</select>`;
      } else if (c.tipo === 'textarea') {
        control = `<textarea name="${c.nombre}">${esc(v)}</textarea>`;
      } else {
        control = `<input name="${c.nombre}" type="${c.tipo}" value="${esc(v)}" ${c.paso ? `step="${c.paso}"` : ''}>`;
      }
      html.push(`<label>${esc(c.etiqueta)}${control}</label>`);
    }
    $('#camposModal').innerHTML = html.join('');
    $('#camposModal').querySelector('input, select, textarea')?.focus();
  } catch (err) {
    $('#modal').close();
    mostrarError(err, 'Abrir formulario');
  }
}

$('#formulario').onsubmit = async e => {
  e.preventDefault();
  const t = estado.config[estado.tabla];
  const datos = Object.fromEntries(new FormData($('#formulario')));
  const id = estado.editando;
  const accion = `${id ? 'Editar' : 'Crear'} ${t.singular}${id ? ' #' + id : ''}`;
  $('#botonGuardar').disabled = true;
  try {
    const fila = await api(id ? 'PUT' : 'POST', id ? `${estado.tabla}/${id}` : estado.tabla, datos);
    $('#modal').close();
    aviso('ok', id ? 'Cambios guardados' : `${mayus(t.singular)} ${t.femenino ? 'creada' : 'creado'}`, [`ID ${fila[t.pk]}`]);
    registrar(true, accion, `ID ${fila[t.pk]}`);
    limpiarCache(); cargarFilas(); actualizarConteos();
  } catch (err) {
    mostrarError(err, accion);   // el formulario sigue abierto para corregir
  } finally {
    $('#botonGuardar').disabled = false;
  }
};

document.querySelectorAll('[data-cerrar]').forEach(b => b.onclick = () => $('#modal').close());

// ---------------------------------------------------------------- eliminar y estados
function confirmar(titulo, texto) {
  return new Promise(resolver => {
    $('#tituloConfirmar').textContent = titulo;
    $('#textoConfirmar').textContent = texto;
    $('#confirmar').returnValue = '';
    $('#confirmar').onclose = () => resolver($('#confirmar').returnValue === 'si');
    $('#confirmar').showModal();
  });
}

async function eliminar(id) {
  const t = estado.config[estado.tabla];
  const ok = await confirmar(`¿Eliminar ${t.singular} #${id}?`,
    'Si tiene registros relacionados, la base de datos lo impedirá (ON DELETE RESTRICT, sin cascada).');
  if (!ok) return;
  const accion = `Eliminar ${t.singular} #${id}`;
  try {
    await api('DELETE', `${estado.tabla}/${id}`);
    aviso('ok', 'Registro eliminado', [`${t.singular} #${id}`]);
    registrar(true, accion, 'Eliminado');
    limpiarCache(); cargarFilas(); actualizarConteos();
  } catch (err) { mostrarError(err, accion); }
}

async function cambiarEstado(id, nuevo) {
  if (!nuevo) return;
  const accion = `Orden #${id} → ${nuevo}`;
  try {
    await api('PUT', `supply_order/${id}`, { status: nuevo });
    aviso('ok', 'Estado actualizado', [accion]);
    registrar(true, accion, 'Estado cambiado');
    limpiarCache();
  } catch (err) { mostrarError(err, accion); }
  cargarFilas();
}

function limpiarCache() { for (const k in cacheOpciones) delete cacheOpciones[k]; }

async function actualizarConteos() {
  try { estado.conteos = (await api('GET', 'resumen')).conteos; pintarMenu(); } catch { /* sin conexión */ }
}

// ---------------------------------------------------------------- arranque
$('#botonBitacora').onclick = () => $('#bitacora').classList.add('abierta');
$('#cerrarBitacora').onclick = () => $('#bitacora').classList.remove('abierta');
$('#botonMenu').onclick = () => $('#lateral').classList.toggle('abierto');
$('#menu').onclick = e => { const a = e.target.closest('a[data-tabla]'); if (a) { e.preventDefault(); ir(a.dataset.tabla); } };

(async function iniciar() {
  try {
    estado.config = await api('GET', 'config');
    const r = await api('GET', 'resumen');
    estado.conteos = r.conteos;
    $('#conexion').className = 'conexion ok';
    $('#conexion').lastElementChild.textContent = 'Conectado a PostgreSQL';
  } catch (err) {
    $('#conexion').className = 'conexion error';
    $('#conexion').lastElementChild.textContent = 'Sin conexión';
    if (!estado.config) { mostrarError(err, 'Iniciar'); return; }
  }
  const inicial = location.hash.slice(1);
  ir(estado.config[inicial] ? inicial : 'inicio');
})();
