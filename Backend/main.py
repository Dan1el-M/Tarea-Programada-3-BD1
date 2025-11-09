from fastapi import FastAPI, HTTPException
import pyodbc
import os
app = FastAPI(title="API Proyecto 3")


DB_SERVER    = "25.4.109.245,1433"
DB_NAMEBD    = "Tarea 3 BD1"
DB_USER      = "admin"
DB_PASSWORD  = "admin"
ODBC_DRIVER  = "ODBC Driver 17 for SQL Server"
API_CORS_ORIGINS = ["http://localhost:5173"]


# Configurar conexión global
def get_db_connection():
    connection_string = (
        f'DRIVER={{ODBC Driver 17 for SQL Server}};'
        f'SERVER={DB_SERVER};'
        f'DATABASE={DB_NAMEBD};'
        f'UID={DB_USER};'
        f'PWD={DB_PASSWORD}'
    )
    return pyodbc.connect(connection_string)

@app.get("/")
def root():
    return {"ok": True, "msg": "API funcionando correctamente"}