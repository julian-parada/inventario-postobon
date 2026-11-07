"""
Generador de datos de prueba - Inventario Postobón Ocaña.
Produce 03_datos.sql (y 03a_datos_base_ejemplo.sql) con INSERTs que respetan TODAS las restricciones y
triggers (el script se carga de punta a punta sin desactivar nada).

Uso:  python3 generar_datos.py
Semilla fija -> siempre genera exactamente los mismos datos.
"""
import random
import unicodedata
import datetime as dt
from decimal import Decimal, ROUND_HALF_UP

random.seed(20261027)

N_SUPPLIERS_EJEMPLO = 50
N_EMPLOYEES_EJEMPLO = 50
N_PRODUCTS = 100
N_ORDERS = 1000
FECHA_INI = dt.datetime(2023, 1, 2, 7, 0)
FECHA_FIN = dt.datetime(2026, 10, 24, 17, 0)


def q(s):
    """Literal SQL con comillas escapadas."""
    return "'" + str(s).replace("'", "''") + "'"


def sin_tildes(t):
    """El CHECK de username solo acepta a-z: se quitan tildes y la Ñ."""
    return "".join(c for c in unicodedata.normalize("NFD", t) if unicodedata.category(c) != "Mn")


def money(x):
    return Decimal(x).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


out = []
w = out.append


def bulk(table, cols, rows, chunk=500, overriding=True):
    ov = " OVERRIDING SYSTEM VALUE" if overriding else ""
    for i in range(0, len(rows), chunk):
        part = rows[i:i + chunk]
        w(f"INSERT INTO {table} ({', '.join(cols)}){ov} VALUES")
        w(",\n".join("(" + ", ".join(r) + ")" for r in part) + ";")


# ------------------------------------------------------------------ CATEGORY
categorias = [
    ("GASEOSAS DE SABORES", "Bebidas carbonatadas de sabores a frutas: Postobón, Colombiana, Bretaña, Kola Román"),
    ("GASEOSAS COLA", "Bebidas carbonatadas tipo cola: Pepsi, Pepsi Black, Freskola"),
    ("GASEOSAS LIMA LIMON", "Bebidas carbonatadas lima-limón: 7Up, Bretaña"),
    ("GASEOSAS CERO AZUCAR", "Versiones sin azúcar de la línea de gaseosas"),
    ("AGUA NATURAL", "Agua potable tratada sin gas: Cristal, Oasis"),
    ("AGUA CON GAS", "Agua potable carbonatada"),
    ("AGUA SABORIZADA", "Agua con sabor y baja en calorías: H2Oh!"),
    ("JUGOS DE FRUTA", "Bebidas a base de pulpa de fruta: Hit"),
    ("REFRESCOS DE FRUTA", "Refrescos con jugo de fruta: Tutti Frutti, Frutiño listo"),
    ("TES LISTOS", "Té listo para tomar: Mr. Tea, Lipton"),
    ("BEBIDAS HIDRATANTES", "Bebidas con electrolitos: Gatorade, Squash"),
    ("BEBIDAS ENERGIZANTES", "Bebidas con cafeína y taurina: Speed Max, Peak"),
    ("MALTAS", "Bebidas de malta sin alcohol"),
    ("BEBIDAS FUNCIONALES", "Bebidas con vitaminas o fibra adicionada"),
    ("ENVASE RETORNABLE VIDRIO", "Producto en botella de vidrio retornable que exige devolución de envase"),
    ("FORMATO FAMILIAR", "Presentaciones de 2 litros o más para consumo en hogar"),
    ("FORMATO PERSONAL", "Presentaciones individuales de hasta 600 ml"),
    ("LATAS", "Presentaciones en lata de aluminio"),
    ("INSTITUCIONAL", "Formatos para restaurantes, colegios y casinos"),
    ("PROMOCIONES", "Empaques promocionales y combos de temporada"),
]
CAT = {n: i + 1 for i, (n, _) in enumerate(categorias)}

# ------------------------------------------------------------------ PRODUCT
# marca, sabores, categoría base, vida útil (días), precio base por litro
lineas = [
    ("POSTOBÓN", ["MANZANA", "UVA", "NARANJA", "PIÑA", "LIMÓN"], "GASEOSAS DE SABORES", 270, 3200),
    ("COLOMBIANA", ["ORIGINAL", "CERO"], "GASEOSAS DE SABORES", 270, 3200),
    ("KOLA ROMÁN", ["ORIGINAL"], "GASEOSAS DE SABORES", 270, 3000),
    ("POPULAR", ["KOLA", "UVA", "NARANJA"], "GASEOSAS DE SABORES", 270, 2400),
    ("PEPSI", ["REGULAR", "BLACK", "LIGHT"], "GASEOSAS COLA", 270, 3300),
    ("FRESKOLA", ["ORIGINAL"], "GASEOSAS COLA", 270, 2300),
    ("7UP", ["REGULAR", "FREE"], "GASEOSAS LIMA LIMON", 270, 3300),
    ("BRETAÑA", ["SODA", "LIMÓN"], "GASEOSAS LIMA LIMON", 360, 3000),
    ("CRISTAL", ["NATURAL", "CON GAS"], "AGUA NATURAL", 540, 1800),
    ("OASIS", ["NATURAL"], "AGUA NATURAL", 540, 1500),
    ("H2OH", ["LIMÓN", "MARACUYÁ", "MANDARINA", "TORONJA"], "AGUA SABORIZADA", 300, 2800),
    ("HIT", ["MANGO", "MORA", "LULO", "TROPICAL", "NARANJA PIÑA", "GUANÁBANA"], "JUGOS DE FRUTA", 180, 4200),
    ("TUTTI FRUTTI", ["MANGO", "MORA", "NARANJA", "MANZANA", "DURAZNO"], "REFRESCOS DE FRUTA", 180, 3600),
    ("MR TEA", ["LIMÓN", "DURAZNO", "VERDE"], "TES LISTOS", 240, 4000),
    ("LIPTON", ["LIMÓN", "DURAZNO"], "TES LISTOS", 240, 4400),
    ("GATORADE", ["MANDARINA", "UVA", "MARACUYÁ", "TROPICAL", "LIMÓN", "FRUTOS ROJOS"], "BEBIDAS HIDRATANTES", 300, 6000),
    ("SQUASH", ["MANDARINA", "MORA"], "BEBIDAS HIDRATANTES", 300, 4500),
    ("SPEED MAX", ["ORIGINAL", "CERO"], "BEBIDAS ENERGIZANTES", 360, 7000),
    ("PEAK", ["ORIGINAL", "MANGO"], "BEBIDAS ENERGIZANTES", 360, 8000),
    ("NATUMALTA", ["ORIGINAL"], "MALTAS", 240, 4500),
    ("VITAL", ["VITAMINAS", "FIBRA"], "BEBIDAS FUNCIONALES", 240, 5500),
]
# presentación, litros, envase
presentaciones = [
    ("250 ML", 0.25, "PET"), ("300 ML", 0.30, "VIDRIO"), ("350 ML", 0.35, "PET"),
    ("400 ML", 0.40, "PET"), ("500 ML", 0.50, "PET"), ("600 ML", 0.60, "PET"),
    ("1 L", 1.0, "PET"), ("1.5 L", 1.5, "PET"), ("2.5 L", 2.5, "PET"), ("3 L", 3.0, "PET"),
    ("LATA 269 ML", 0.269, "LATA"), ("LATA 355 ML", 0.355, "LATA"),
]
# empaque: unidad de medida, unidades por empaque, sufijo
empaques = [("UNIDAD", 1, ""), ("PACA", 6, " X6"), ("PACA", 12, " X12"), ("PACA", 24, " X24"),
            ("SIXPACK", 6, " SIXPACK"), ("CANASTA", 30, " CANASTA X30"), ("FARDO", 12, " FARDO X12")]

productos = []  # (id, nombre, cat_id, unidad, precio, min, max, vida)
nombres = set()
pid = 0
for marca, sabores, cat, vida, base in lineas:
    for sabor in sabores:
        for pres, litros, envase in presentaciones:
            if envase == "VIDRIO" and cat not in ("GASEOSAS DE SABORES", "GASEOSAS COLA",
                                                  "GASEOSAS LIMA LIMON", "MALTAS"):
                continue
            if envase == "LATA" and cat in ("AGUA NATURAL", "JUGOS DE FRUTA", "REFRESCOS DE FRUTA"):
                continue
            if litros >= 2.5 and cat in ("BEBIDAS ENERGIZANTES", "BEBIDAS HIDRATANTES", "BEBIDAS FUNCIONALES", "MALTAS"):
                continue
            for unidad, n, suf in empaques:
                if envase == "VIDRIO" and unidad not in ("CANASTA", "UNIDAD"):
                    continue
                if envase != "VIDRIO" and unidad == "CANASTA":
                    continue
                if envase == "LATA" and unidad not in ("UNIDAD", "SIXPACK", "PACA"):
                    continue
                if envase != "LATA" and unidad == "SIXPACK":
                    continue
                if litros >= 1.5 and n > 12:
                    continue
                if unidad == "FARDO" and litros < 1:
                    continue
                nombre = f"{marca} {sabor} {pres}{'' if envase in ('LATA',) else ' ' + envase}{suf}"
                if len(nombre) > 50 or nombre in nombres:
                    continue
                nombres.add(nombre)
                pid += 1
                # categoría: algunas presentaciones caen en categorías de formato
                c = cat
                if sabor in ("CERO", "FREE", "LIGHT") and cat.startswith("GASEOSAS"):
                    c = "GASEOSAS CERO AZUCAR"
                elif envase == "VIDRIO":
                    c = "ENVASE RETORNABLE VIDRIO"
                elif envase == "LATA" and random.random() < 0.5:
                    c = "LATAS"
                elif litros >= 2.5 and random.random() < 0.5:
                    c = "FORMATO FAMILIAR"
                elif unidad == "FARDO" and random.random() < 0.4:
                    c = "INSTITUCIONAL"
                elif litros <= 0.4 and random.random() < 0.15:
                    c = "FORMATO PERSONAL"
                elif random.random() < 0.02:
                    c = "PROMOCIONES"
                precio_unit = base * litros * (1.25 if envase == "LATA" else 1.0)
                precio = money(max(600, round(precio_unit * n * random.uniform(0.95, 1.08), -1)))
                mn = random.choice([20, 30, 40, 50, 60, 80, 100, 120, 150, 200])
                if unidad == "UNIDAD":
                    mn *= 4
                mx = mn * random.choice([4, 5, 6, 8, 10])
                productos.append((pid, nombre, CAT[c], unidad, precio, mn, mx, vida))


# ======================================================================
#  ARCHIVO OPCIONAL 03a: datos base de ejemplo (CATEGORY, SUPPLIER, EMPLOYEE)
#  Ustedes llenan estas tablas; este archivo solo sirve para probar.
# ======================================================================
w("-- =====================================================================")
w("--  ARCHIVO 03a (OPCIONAL): DATOS BASE DE EJEMPLO")
w("--  CATEGORY, SUPPLIER y EMPLOYEE los llena el equipo. Este archivo solo")
w("--  sirve para probar 03_datos.sql si todavía no han cargado los suyos.")
w("--  NO lo ejecuten si ya llenaron esas tablas.")
w("-- =====================================================================")
w("SET search_path TO inventario_postobon;")
w("")
w("-- CATEGORY (en este orden: 03_datos.sql reparte los productos por posición)")
bulk("category", ["category_name", "description"], [[q(n), q(d)] for n, d in categorias], overriding=False)
# ------------------------------------------------------------------ SUPPLIER
def dv_nit(nit9: str) -> int:
    """Dígito de verificación DIAN."""
    pesos = [3, 7, 13, 17, 19, 23, 29, 37, 41]
    s = sum(int(d) * p for d, p in zip(reversed(nit9), pesos))
    r = s % 11
    return r if r in (0, 1) else 11 - r


pref = ["DISTRIBUIDORA", "COMERCIALIZADORA", "INVERSIONES", "LOGÍSTICA", "ENVASES", "TRANSPORTES",
        "INDUSTRIAS", "SUMINISTROS", "AGROINDUSTRIAL", "PLASTICOS", "ETIQUETAS", "EMBOTELLADORA",
        "SERVICIOS", "CARTONES", "REPRESENTACIONES"]
nucleo = ["DEL NORTE", "SANTANDER", "CATATUMBO", "ORIENTE", "LOS ANDES", "LA PROVINCIA", "EL CARIBE",
          "CENTRAL", "GALÁN", "EL LLANO", "LA FRONTERA", "SAN JOSÉ", "LAS PALMAS", "EL TARRA",
          "TORCOROMA", "ÁBREGO", "PAMPLONA", "LA PLAYA", "CONVENCIÓN", "HACARÍ", "MAGDALENA",
          "SAN MARTIN", "AGUACHICA", "LOS PATIOS", "VILLA DEL ROSARIO", "EL ZULIA", "TIBÚ",
          "SARDINATA", "BUCARAMANGA", "LA ESPERANZA", "GAMARRA", "EL CARMEN", "TEORAMA", "CHINACOTA"]
suf = ["S.A.S.", "S.A.", "LTDA", "& CIA S.A.S.", "Y CIA LTDA", "SAS ZOMAC"]
ciudades = ["OCAÑA", "CÚCUTA", "BUCARAMANGA", "AGUACHICA", "PAMPLONA", "ÁBREGO", "BOGOTÁ",
            "MEDELLÍN", "BARRANQUILLA", "MALAMBO", "YUMBO", "VALLEDUPAR", "TIBÚ", "SARDINATA"]
vias = ["CL", "CR", "AV", "DG", "TV", "KM"]

proveedores = []
nits = set()
noms = set()
for sid in range(1, N_SUPPLIERS_EJEMPLO + 1):
    while True:
        nombre = f"{random.choice(pref)} {random.choice(nucleo)} {random.choice(suf)}"
        if len(nombre) <= 50 and nombre not in noms:
            break
        if len(nombre) <= 50 and random.random() < 0.6:  # se permiten homónimos con NIT distinto
            break
    noms.add(nombre)
    while True:
        base9 = str(random.randint(800000000, 901999999))
        if base9 not in nits:
            nits.add(base9)
            break
    nit = f"{base9}-{dv_nit(base9)}"
    v = random.choice(vias)
    if v == "KM":
        dirc = f"KM {random.randint(1, 30)} VÍA OCAÑA {random.choice(['ÁBREGO', 'AGUACHICA', 'CÚCUTA', 'LA PLAYA', 'CONVENCIÓN'])}"
    else:
        dirc = f"{v} {random.randint(1, 120)} # {random.randint(1, 99)}-{random.randint(1, 99)} {random.choice(ciudades)}"
    dirc = dirc[:50]
    proveedores.append([q(nombre), q(nit), q(dirc)])
w("")
w(f"-- SUPPLIER ({len(proveedores)} filas)")
bulk("supplier", ["name", "tax_id", "address"], proveedores, overriding=False)

# ------------------------------------------------------------------ EMPLOYEE
hombres = ["JUAN", "CARLOS", "LUIS", "JORGE", "ANDRÉS", "DIEGO", "JOSÉ", "MIGUEL", "DAVID", "SEBASTIÁN",
           "JULIÁN", "KEVIN", "BRAYAN", "JHON", "ÓSCAR", "EDWIN", "FABIÁN", "HERNÁN", "WILMER", "YEISON", "DAIRO"]
mujeres = ["MARÍA", "ANA", "LAURA", "PAOLA", "DIANA", "YULIANA", "CAMILA", "VALENTINA", "SANDRA", "LUZ",
           "CLAUDIA", "MÓNICA", "ANGÉLICA", "KAREN", "LEIDY", "YICETH", "NATALIA", "DANIELA", "MARCELA", "ADRIANA"]
segundo_h = ["", "", "", "ALBERTO", "ANDRÉS", "DAVID", "FERNANDO", "JOSÉ", "CAMILO", "ESTEBAN", "MAURICIO", "ANTONIO"]
segundo_m = ["", "", "", "ALEJANDRA", "PATRICIA", "FERNANDA", "MARCELA", "CAROLINA", "ISABEL", "ANDREA", "MILENA"]
apellidos = ["PARADA", "REYES", "SÁNCHEZ", "TORRES", "VELÁSQUEZ", "GÓMEZ", "QUINTERO", "PACHECO", "ARENGAS",
             "CLARO", "NAVARRO", "BAYONA", "RINCÓN", "ASCANIO", "ARÉVALO", "JÁCOME", "CARRASCAL", "PÉREZ",
             "RODRÍGUEZ", "MARTÍNEZ", "GARCÍA", "LÓPEZ", "HERNÁNDEZ", "DÍAZ", "ROJAS", "VERGEL", "LOBO",
             "GUERRERO", "SALAZAR", "OVALLE", "PÁEZ", "TRIGOS", "SARABIA", "LEÓN", "ORTEGA", "PALLARES",
             "PINO", "BARBOSA", "CASTILLA", "ANGARITA", "DURÁN", "MANOSALVA", "SOTO", "MORA", "CUESTA"]
cargos = (["AUXILIAR DE BODEGA"] * 40 + ["MONTACARGUISTA"] * 15 + ["DESPACHADOR"] * 15 +
          ["ANALISTA DE INVENTARIO"] * 10 + ["SUPERVISOR DE CALIDAD"] * 8 + ["JEFE DE BODEGA"] * 5 +
          ["COORDINADOR LOGISTICO"] * 5 + ["ADMINISTRADOR"] * 2)
empleados = []
users = set()
for eid in range(1, N_EMPLOYEES_EJEMPLO + 1):
    if random.random() < 0.5:
        n1, n2 = random.choice(hombres), random.choice(segundo_h)
    else:
        n1, n2 = random.choice(mujeres), random.choice(segundo_m)
    if n2 == n1:
        n2 = ""
    a1, a2 = random.sample(apellidos, 2)
    nombre = " ".join(x for x in (n1, n2, a1, a2) if x)
    base = sin_tildes(f"{n1[0]}{(n2[0] if n2 else '')}{a1}{a2[0]}").lower()
    u = base
    k = 1
    while u in users:
        k += 1
        u = f"{base}{k}"
    users.add(u)
    empleados.append([q(nombre), q(random.choice(cargos)), q(u)])
w("")
w(f"-- EMPLOYEE ({len(empleados)} filas)")
bulk("employee", ["name", "position", "username"], empleados, overriding=False)

ejemplo = "\n".join(out)
out.clear()

# ======================================================================
#  ARCHIVO 03: datos de PRODUCT, SUPPLY_ORDER, ORDER_DETAIL, BATCH, BATCH_DETAIL
# ======================================================================
# Productos: 100 elegidos del portafolio, al menos uno por línea de marca
por_linea = {}
for p in productos:
    por_linea.setdefault(p[1].split(" ")[0], []).append(p)
elegidos = [random.choice(v) for v in por_linea.values()]
resto = [p for p in productos if p not in elegidos]
elegidos += random.sample(resto, N_PRODUCTS - len(elegidos))
random.shuffle(elegidos)
productos = [(i + 1,) + p[1:] for i, p in enumerate(elegidos)]   # product_id 1..100

w("-- =====================================================================")
w("--  ARCHIVO 03: CARGA DE DATOS (generado por generador/generar_datos.py)")
w("--  PRODUCT 100 | SUPPLY_ORDER 1000 | ORDER_DETAIL 1500 | BATCH 500 | BATCH_DETAIL 500")
w("--")
w("--  REQUISITO: CATEGORY, SUPPLIER y EMPLOYEE ya deben tener datos (los llena")
w("--  el equipo). Este script NO usa IDs fijos de esas tablas: los toma de lo")
w("--  que exista, repartiéndolos en orden (por eso sirve con cualquier dato).")
w("--  Para que las categorías tengan sentido, cree las categorías en el orden de")
w("--  03a_datos_base_ejemplo.sql (si hay menos de 20, se reparten en ciclo).")
w("--")
w("--  Todo va en una transacción y con los triggers ACTIVOS.")
w("-- =====================================================================")
w("SET search_path TO inventario_postobon;")
w("BEGIN;")
w("")
w("-- Validación previa: si falta alguna tabla base, se detiene con un mensaje claro")
w("""DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM category) THEN RAISE EXCEPTION 'Primero llene CATEGORY'; END IF;
    IF NOT EXISTS (SELECT 1 FROM supplier) THEN RAISE EXCEPTION 'Primero llene SUPPLIER'; END IF;
    IF NOT EXISTS (SELECT 1 FROM employee) THEN RAISE EXCEPTION 'Primero llene EMPLOYEE'; END IF;
END $$;""")
w("")
w("-- Tablas puente temporales: posición (1, 2, 3...) -> ID real")
for t, c in [("category", "category_id"), ("supplier", "supplier_id"), ("employee", "employee_id")]:
    w(f"CREATE TEMP TABLE map_{t} ON COMMIT DROP AS")
    w(f"  SELECT row_number() OVER (ORDER BY {c}) AS pos, {c} AS id FROM {t};")
w("")


def bulk_map(table, cols, map_table, map_col, rows, chunk=500):
    """INSERT ... SELECT que traduce una posición (columna 'pos') al ID real."""
    vcols = [("pos" if c == map_col else c) for c in cols]
    sel = [("m.id" if c == map_col else f"v.{c}") for c in cols]
    for i in range(0, len(rows), chunk):
        part = rows[i:i + chunk]
        w(f"INSERT INTO {table} ({', '.join(cols)}) OVERRIDING SYSTEM VALUE")
        w(f"SELECT {', '.join(sel)} FROM (VALUES")
        w(",\n".join("(" + ", ".join(r) + ")" for r in part))
        w(f") AS v ({', '.join(vcols)})")
        w(f"JOIN map_{map_table} m ON m.pos = ((v.pos - 1) % (SELECT count(*) FROM map_{map_table})) + 1;")


w(f"-- PRODUCT ({len(productos)} filas)")
bulk_map("product", ["product_id", "category_id", "name", "unit_of_measure", "reference_price", "min_stock", "max_stock"],
         "category", "category_id",
         [[str(p[0]), str(p[2]), q(p[1]), q(p[3]), str(p[4]) + "::numeric", str(p[5]), str(p[6])] for p in productos])

# ---------------------------------------------------------------- plan de órdenes
# Las cantidades exactas pedidas se logran con este reparto:
#   RECIBIDA  280 órdenes de 1 producto  -> 280 lotes
#   RECIBIDA   90 órdenes de 2 productos -> 180 lotes (un lote por producto)
#   APROBADA   40 órdenes de 2 productos ->  40 lotes (llegó solo uno: recepción parcial)
#   resto     590 órdenes: 370 de 2 productos y 220 de 1 -> PENDIENTE / APROBADA / CANCELADA
#   detalle = 280 + 180 + 80 + 740 + 220 = 1500 | lotes = 500 | detalle de lote = 500
plan = ([("RECIBIDA", 1, 1)] * 280 + [("RECIBIDA", 2, 2)] * 90 + [("APROBADA", 2, 1)] * 40)
resto_n = [2] * 370 + [1] * 220
random.shuffle(resto_n)
resto_est = ["CANCELADA_P"] * 140 + ["CANCELADA_A"] * 50 + ["APROBADA"] * 150 + ["PENDIENTE"] * 250
random.shuffle(resto_est)
plan += [(e, n, 0) for e, n in zip(resto_est, resto_n)]

# Fecha de cada orden según su estado (corrección v3, ver documento):
#   PENDIENTE: últimos 45 días | APROBADA: últimos 120 días
#   RECIBIDA: 40 % en los últimos 10 meses (lotes vigentes) y el resto en todo el periodo
#   CANCELADA: todo el periodo
# En la v2 las fechas se asignaban en orden y todas las RECIBIDAS quedaban en
# 2023-2024: la validación mostró 0 lotes vigentes y 100 productos "SIN EXISTENCIA".
def fecha_en(dias_desde, dias_hasta):
    ini = FECHA_FIN - dt.timedelta(days=dias_desde)
    fin = FECHA_FIN - dt.timedelta(days=dias_hasta)
    return ini + dt.timedelta(seconds=random.random() * (fin - ini).total_seconds())

TOTAL_DIAS = (FECHA_FIN - FECHA_INI).days
def fecha_para(estado):
    if estado == "PENDIENTE":
        return fecha_en(45, 0)
    if estado == "APROBADA":
        return fecha_en(120, 0)
    if estado == "RECIBIDA" and random.random() < 0.4:
        return fecha_en(300, 15)
    return fecha_en(TOTAL_DIAS, 15)

random.shuffle(plan)
plan_fechas = sorted(((fecha_para(p[0]), p) for p in plan), key=lambda x: x[0])
fechas = [f for f, _ in plan_fechas]
plan = [p for _, p in plan_fechas]
N_SUP_POS = 50  # posiciones de proveedor a repartir (cíclico sobre los que existan)

ordenes = []
for oid, (f, (est, nprod, nlotes)) in enumerate(zip(fechas, plan), start=1):
    ordenes.append((oid, random.randint(1, N_SUP_POS), f, est, nprod, nlotes))

w("")
w(f"-- SUPPLY_ORDER ({len(ordenes)} filas) - todas nacen PENDIENTE (regla del trigger T2)")
bulk_map("supply_order", ["order_id", "supplier_id", "issue_date"], "supplier", "supplier_id",
         [[str(o[0]), str(o[1]), q(o[2].strftime("%Y-%m-%d %H:%M:%S") + "-05") + "::timestamptz"] for o in ordenes])

detalles = []
det_por_orden = {}
did = 0
for oid, sid, f, est, nprod, nlotes in ordenes:
    lst = []
    for p in random.sample(productos, nprod):
        did += 1
        qty = random.choice([10, 12, 15, 20, 24, 25, 30, 36, 40, 48, 50, 60, 72, 80, 100, 120, 150, 200])
        if p[3] == "UNIDAD":
            qty *= random.choice([2, 4, 5])
        precio = money(p[4] * Decimal(str(round(random.uniform(0.88, 1.04), 3))))
        detalles.append((did, oid, p[0], qty, precio))
        lst.append((p[0], qty, p[7]))
    det_por_orden[oid] = lst
w("")
w(f"-- ORDER_DETAIL ({len(detalles)} filas) - el trigger T4 calcula SUPPLY_ORDER.TOTAL")
bulk("order_detail", ["detail_id", "order_id", "product_id", "requested_quantity", "unit_price"],
     [[str(d[0]), str(d[1]), str(d[2]), str(d[3]), str(d[4])] for d in detalles])


def update_in(sql_set, ids, chunk=1000):
    for i in range(0, len(ids), chunk):
        w(f"UPDATE supply_order SET {sql_set} WHERE order_id IN ({', '.join(map(str, ids[i:i + chunk]))});")


aprobar = [o[0] for o in ordenes if o[3] in ("APROBADA", "RECIBIDA", "CANCELADA_A")]
w("")
w("-- Ciclo de vida: PENDIENTE -> APROBADA / PENDIENTE -> CANCELADA")
update_in("status = 'APROBADA'", aprobar)
update_in("status = 'CANCELADA'", [o[0] for o in ordenes if o[3] == "CANCELADA_P"])

lotes, lote_det = [], []
bid = 0
N_EMP_POS = 50
for oid, sid, f, est, nprod, nlotes in ordenes:
    items = det_por_orden[oid][:nlotes]
    for pid_, qty, vida in items:
        bid += 1
        llega = qty if random.random() < 0.85 else max(1, int(qty * random.uniform(0.6, 0.98)))
        venc = (f + dt.timedelta(days=random.randint(int(vida * 0.6), vida))).date()
        holgura = 0 if random.random() < 0.8 else random.randint(1, 20)
        lotes.append((bid, oid, random.randint(1, N_EMP_POS), venc, llega + holgura))
        lote_det.append((bid, bid, pid_, llega))

w("")
w(f"-- BATCH ({len(lotes)} filas) - solo para órdenes APROBADAS (trigger T5)")
bulk_map("batch", ["batch_id", "order_id", "employee_id", "expiration_date", "initial_quantity"],
         "employee", "employee_id",
         [[str(b[0]), str(b[1]), str(b[2]), q(b[3].isoformat()) + "::date", str(b[4])] for b in lotes])
w("")
w(f"-- BATCH_DETAIL ({len(lote_det)} filas) - validado contra lo pedido (trigger T6)")
bulk("batch_detail", ["batch_detail_id", "batch_id", "product_id", "quantity"],
     [[str(d[0]), str(d[1]), str(d[2]), str(d[3])] for d in lote_det])

w("")
w("-- Ciclo de vida: APROBADA -> RECIBIDA / APROBADA -> CANCELADA")
update_in("status = 'RECIBIDA'", [o[0] for o in ordenes if o[3] == "RECIBIDA"])
update_in("status = 'CANCELADA'", [o[0] for o in ordenes if o[3] == "CANCELADA_A"])

w("")
w("-- Se insertaron IDs explícitos (OVERRIDING SYSTEM VALUE); se ajustan las")
w("-- secuencias para que el próximo INSERT siga desde el último ID.")
for t, c in [("product", "product_id"), ("supply_order", "order_id"), ("order_detail", "detail_id"),
             ("batch", "batch_id"), ("batch_detail", "batch_detail_id")]:
    w(f"SELECT setval(pg_get_serial_sequence('inventario_postobon.{t}', '{c}'), (SELECT MAX({c}) FROM {t}));")
w("")
w("COMMIT;")

open("../03a_datos_base_ejemplo.sql", "w", encoding="utf8").write(ejemplo + "\n")
open("../03_datos.sql", "w", encoding="utf8").write("\n".join(out) + "\n")
print(f"product={len(productos)} orders={len(ordenes)} details={len(detalles)} "
      f"batch={len(lotes)} batch_detail={len(lote_det)}")
