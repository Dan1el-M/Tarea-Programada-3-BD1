from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional, List, Dict, Any
from typing import Tuple 
import pyodbc
import os

# =========================================================
# 1) APP + CORS
# =========================================================
app = FastAPI(title="API Proyecto 3")

API_CORS_ORIGINS = [
    "http://localhost:5173",
    "http://127.0.0.1:5173",
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=API_CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# =========================================================
# 2) CONFIG DB
# =========================================================
DB_SERVER   = os.getenv("DB_SERVER",   "25.4.109.245,1433")
DB_NAMEBD   = os.getenv("DB_NAMEBD",   "Tarea 3 BD1")
DB_USER     = os.getenv("DB_USER",     "admin")
DB_PASSWORD = os.getenv("DB_PASSWORD", "admin")
ODBC_DRIVER = os.getenv("ODBC_DRIVER", "ODBC Driver 17 for SQL Server")


def get_db_connection():
    conn_str = (
        f"DRIVER={{{ODBC_DRIVER}}};"
        f"SERVER={DB_SERVER};"
        f"DATABASE={DB_NAMEBD};"
        f"UID={DB_USER};"
        f"PWD={DB_PASSWORD};"
        "TrustServerCertificate=yes;"
    )
    return pyodbc.connect(conn_str)


def call_sp(sp_name: str, params: list):
    """
    Ejecuta SPs estándar con @outResultCode OUTPUT al final.
    Retorna (recordsets, out_code) donde:

      recordsets = [ [filaDict, ...],  # resultset 1
                     [filaDict, ...],  # resultset 2
                     ...
                   ]

      out_code   = valor de @outResultCode
    """
    conn = get_db_connection()
    try:
        cur = conn.cursor()

        placeholders = ", ".join(["?"] * len(params))
        if placeholders:
            sql = (
                f"DECLARE @outResultCode INT; "
                f"EXEC dbo.{sp_name} {placeholders}, "
                f"@outResultCode=@outResultCode OUTPUT; "
                f"SELECT @outResultCode AS outResultCode;"
            )
        else:
            sql = (
                f"DECLARE @outResultCode INT; "
                f"EXEC dbo.{sp_name} "
                f"@outResultCode=@outResultCode OUTPUT; "
                f"SELECT @outResultCode AS outResultCode;"
            )

        cur.execute(sql, params)

        results: List[List[Dict[str, Any]]] = []
        while True:
            if cur.description:
                cols = [c[0] for c in cur.description]
                rows = cur.fetchall()
                results.append([dict(zip(cols, r)) for r in rows])
            if not cur.nextset():
                break

        conn.commit()

        out_code = 0
        if results and results[-1] and "outResultCode" in results[-1][0]:
            out_code = int(results[-1][0]["outResultCode"])
            results.pop()  # quitamos el set del outResultCode

        return results, out_code

    finally:
        conn.close()


# 🔹 Helper nuevo: factura pendiente más vieja de una finca
def get_oldest_pending_invoice_id(numero_finca: str) -> Optional[int]:
    """
    Devuelve el Id de la factura PENDIENTE más vieja de una finca,
    o None si no hay.
    """
    conn = get_db_connection()
    try:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT TOP (1) Id
            FROM dbo.Factura
            WHERE PropiedadId = ?
              AND EstadoFacturaId = 1
            ORDER BY FechaFactura, Id;
            """,
            (numero_finca,),
        )
        row = cur.fetchone()
        return int(row[0]) if row else None
    finally:
        conn.close()


# =========================================================
# 3) MODELOS
# =========================================================
class LoginIn(BaseModel):
    nombreUsuario: str
    contrasena: str


class PagarFacturaIn(BaseModel):
    numeroFinca: str
    tipoMedioPagoId: int
    numeroReferencia: str
    fechaPago: Optional[str] = None  # 'YYYY-MM-DD' o None


class SimularPagoIn(BaseModel):
    numeroFinca: str
    fechaPago: Optional[str] = None  # 'YYYY-MM-DD' o None


# =========================================================
# 4) ENDPOINTS
# =========================================================
@app.get("/")
def root():
    return {"ok": True, "msg": "API funcionando correctamente"}


# ---- Login Admin
@app.post("/login")
def login(data: LoginIn):
    rs, out_code = call_sp("SP_InicioSesionAdmin",
                           [data.nombreUsuario, data.contrasena])

    if out_code != 0:
        raise HTTPException(status_code=401, detail="Credenciales inválidas")

    usuario = rs[0][0] if rs and rs[0] else None
    return {"ok": 1, "usuario": usuario}


# ---- Listar propiedades (filtro opcional)
@app.get("/propiedades")
def listar_propiedades(q: str = Query(default="")):
    q = (q or "").strip()

    # sin filtro => listar todo
    if q == "":
        rs, out_code = call_sp("SP_ListarPropiedades", [None, None])
        return rs[0] if (out_code == 0 and rs) else []

    # si es número => cédula
    if q.isdigit():
        rs, out_code = call_sp("SP_ListarPropiedades", [None, q])
        return rs[0] if (out_code == 0 and rs) else []

    # si no => finca
    rs, out_code = call_sp("SP_ListarPropiedades", [q, None])
    return rs[0] if (out_code == 0 and rs) else []


# ---- Obtener detalle de una propiedad + propietarios + CC
@app.get("/propiedades/{numero_finca}")
def obtener_propiedad(numero_finca: str):
    rs, out_code = call_sp("SP_ObtenerPropiedad", [numero_finca])

    if out_code != 0:
        raise HTTPException(status_code=404, detail="Propiedad no existe")

    return {
        "propiedad":      rs[0][0] if rs and rs[0] else None,
        "propietarios":   rs[1] if len(rs) > 1 else [],
        "conceptosCobro": rs[2] if len(rs) > 2 else [],
    }


# ---- Facturas por propiedad
@app.get("/propiedades/{numero_finca}/facturas")
def facturas_propiedad(numero_finca: str):
    rs, out_code = call_sp("SP_FacturasPorPropiedad", [numero_finca])

    if out_code != 0:
        return []

    return rs[0] if rs else []


# ---- Detalle de una factura (usa SP_FacturaDetalleCompleto)
@app.get("/facturas/{numero_factura}/detalle")
def detalle_factura(numero_factura: int):
    # SP_FacturaDetalleCompleto(@inNumeroFactura, @inFechaReferencia = NULL)
    rs, out_code = call_sp("SP_FacturaDetalleCompleto", [numero_factura, None])

    if out_code != 0 or not rs or len(rs) < 2:
        raise HTTPException(
            status_code=404,
            detail="No se encontró detalle para la factura",
        )

    header = rs[0][0] if rs[0] else None   # primer resultset: encabezado
    detalle = rs[1]                        # segundo resultset: líneas

    return {
        "header": header,
        "detalle": detalle,
    }


# ---- Pagar factura más vieja (admin)
@app.post("/facturas/pagar")
def pagar_factura(data: PagarFacturaIn):
    params = [
        data.numeroFinca,
        data.tipoMedioPagoId,
        data.numeroReferencia,
        data.fechaPago
    ]

    filas, out_code = call_sp("SP_PagarFacturaAdmin", params)

    if out_code != 0:
        msg = "No se pudo pagar la factura"
        if out_code == 40001:
            msg = "No hay facturas pendientes para esa propiedad"
        raise HTTPException(status_code=400, detail=msg)

    factura = filas[0][0] if filas and filas[0] else None
    detalle = filas[1]      if len(filas) > 1 else []

    return {
        "ok": 1,
        "msg": "Pago realizado correctamente",
        "factura": factura,
        "detalle": detalle
    }


# ---- Simular pago (para el modal de confirmación) usando SP_FacturaDetalleCompleto
@app.post("/facturas/simular-pago")
def simular_pago(data: SimularPagoIn):
    # 1) Buscar factura pendiente más vieja de la finca
    factura_id = get_oldest_pending_invoice_id(data.numeroFinca)
    if factura_id is None:
        raise HTTPException(
            status_code=400,
            detail="No hay facturas pendientes para esa propiedad",
        )

    # 2) Llamar SP_FacturaDetalleCompleto con esa factura y la fechaPago
    rs, out_code = call_sp(
        "SP_FacturaDetalleCompleto",
        [factura_id, data.fechaPago]
    )

    if out_code != 0 or not rs or len(rs) < 2:
        raise HTTPException(
            status_code=500,
            detail="Error al simular el pago de la factura",
        )

    header = rs[0][0] if rs[0] else None  # encabezado (con totales)
    detalle = rs[1]                       # detalle completo (base + extras)

    return {
        "facturaId": factura_id,
        "header": header,
        "detalle": detalle,
    }
