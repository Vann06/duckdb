#!/usr/bin/env python3
"""Crea o actualiza en Metabase el tablero de indicadores del Ejercicio 7.

Usa la API de Metabase para:
  1. conectar la base data/processed/taxi.duckdb (solo lectura);
  2. crear una pregunta SQL nativa por cada indicador de sql/06_indicadores.sql,
     con el grafico definido en sus metadatos (display, dimensions, metrics);
  3. organizar todas las preguntas en un tablero.

Si se ejecuta de nuevo, actualiza las preguntas existentes en lugar de
duplicarlas. Las credenciales se pasan por variables de entorno:

    docker compose exec -T -e MB_EMAIL=correo@ejemplo.com -e MB_PASSWORD=... \\
        lab python scripts/setup_metabase.py

Si Metabase aun no tiene una cuenta de administrador, el script la crea con
esas credenciales.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import requests

from run_exploration import cargar_consultas


ROOT = Path(__file__).resolve().parents[1]
INDICADORES_SQL = ROOT / "sql" / "06_indicadores.sql"
MB_URL = os.environ.get("MB_URL", "http://metabase:3000").rstrip("/")
URL_PUBLICA = os.environ.get("MB_URL_PUBLICA", "http://localhost:3000")
NOMBRE_BASE = "NYC Taxi (DuckDB)"
ARCHIVO_BASE = "/workspace/data/processed/taxi.duckdb"
NOMBRE_COLECCION = "Lab 8 - Indicadores"
NOMBRE_TABLERO = "Indicadores NYC Taxi"
ANCHO, ALTO = 12, 8   # cada tarjeta ocupa media fila de la grilla de 24 columnas


class Metabase:
    def __init__(self, url: str) -> None:
        self.url = url
        self.sesion = requests.Session()

    def llamar(self, metodo: str, ruta: str, **kwargs):
        respuesta = self.sesion.request(metodo, f"{self.url}/api{ruta}", timeout=120, **kwargs)
        if not respuesta.ok:
            raise SystemExit(f"{metodo} {ruta} -> {respuesta.status_code}: {respuesta.text[:500]}")
        return respuesta.json() if respuesta.content else None

    def iniciar_sesion(self, correo: str, clave: str) -> None:
        propiedades = self.llamar("GET", "/session/properties")
        if not propiedades.get("has-user-setup"):
            print("Metabase sin configurar: se crea la cuenta de administrador.")
            datos = self.llamar("POST", "/setup", json={
                "token": propiedades["setup-token"],
                "user": {"email": correo, "password": clave,
                         "first_name": "Lab", "last_name": "8", "site_name": "Lab 8 DuckDB"},
                "prefs": {"site_name": "Lab 8 DuckDB", "site_locale": "es", "allow_tracking": False},
            })
        else:
            datos = self.llamar("POST", "/session", json={"username": correo, "password": clave})
        self.sesion.headers["X-Metabase-Session"] = datos["id"]


def asegurar_base(mb: Metabase) -> int:
    for base in mb.llamar("GET", "/database")["data"]:
        if base["name"] == NOMBRE_BASE:
            return base["id"]
    print(f"Conectando {ARCHIVO_BASE}...")
    base = mb.llamar("POST", "/database", json={
        "engine": "duckdb",
        "name": NOMBRE_BASE,
        "details": {"database_file": ARCHIVO_BASE, "read_only": True, "memory_limit": "2GB"},
    })
    return base["id"]


def asegurar_coleccion(mb: Metabase) -> int:
    for coleccion in mb.llamar("GET", "/collection"):
        if coleccion.get("name") == NOMBRE_COLECCION and not coleccion.get("archived"):
            return coleccion["id"]
    return mb.llamar("POST", "/collection", json={"name": NOMBRE_COLECCION})["id"]


def items(mb: Metabase, coleccion: int, modelo: str) -> dict[str, int]:
    datos = mb.llamar("GET", f"/collection/{coleccion}/items", params={"models": modelo})
    return {item["name"]: item["id"] for item in datos["data"]}


def visualizacion(meta: dict[str, str]) -> dict:
    dims = [d.strip() for d in meta.get("dimensions", "").split(",") if d.strip()]
    metricas = [m.strip() for m in meta.get("metrics", "").split(",") if m.strip()]
    ajustes = {"graph.dimensions": dims, "graph.metrics": metricas}
    if dims and dims[0] in ("pasajeros", "hora"):
        ajustes["graph.x_axis.scale"] = "ordinal"
    if meta.get("display") == "row":
        # Metabase agrupa las barras de mas en "Other"; el indicador 7 necesita
        # ver por separado las zonas con menor propina.
        ajustes["graph.max_categories_enabled"] = False
    if dims and dims[0] == "fecha":
        # Sin datos de un periodo (p. ej. 2025), la linea se corta en vez de unir los puntos.
        ajustes["series_settings"] = {s: {"line.missing": "none"} for s in ("yellow", "green")}
    return ajustes


def main() -> int:
    correo, clave = os.environ.get("MB_EMAIL"), os.environ.get("MB_PASSWORD")
    if not correo or not clave:
        raise SystemExit("Defina MB_EMAIL y MB_PASSWORD (ver la ayuda al inicio del script).")

    mb = Metabase(MB_URL)
    mb.iniciar_sesion(correo, clave)
    base = asegurar_base(mb)
    coleccion = asegurar_coleccion(mb)
    existentes = items(mb, coleccion, "card")

    tarjetas = []
    for numero, consulta in enumerate(cargar_consultas(INDICADORES_SQL), start=1):
        meta = consulta.metadatos
        nombre = f"{numero:02d}. {meta.get('title', consulta.nombre)}"
        cuerpo = {
            "name": nombre,
            "description": f"{meta.get('question', '')}\n\n{meta.get('interpretation', '')}",
            "display": meta.get("display", "table"),
            "collection_id": coleccion,
            "dataset_query": {"type": "native", "database": base,
                              "native": {"query": consulta.sql, "template-tags": {}}},
            "visualization_settings": visualizacion(meta),
        }
        if nombre in existentes:
            tarjeta = mb.llamar("PUT", f"/card/{existentes[nombre]}", json=cuerpo)
            print(f"Actualizada: {nombre}")
        else:
            tarjeta = mb.llamar("POST", "/card", json=cuerpo)
            print(f"Creada:      {nombre}")
        tarjetas.append(tarjeta["id"])

    tableros = items(mb, coleccion, "dashboard")
    if NOMBRE_TABLERO in tableros:
        tablero = tableros[NOMBRE_TABLERO]
    else:
        tablero = mb.llamar("POST", "/dashboard", json={
            "name": NOMBRE_TABLERO, "collection_id": coleccion,
            "description": "Ejercicio 7: indicadores calculados con DuckDB sobre los viajes de taxi de NYC.",
        })["id"]

    mb.llamar("PUT", f"/dashboard/{tablero}", json={"dashcards": [
        {"id": -indice, "card_id": tarjeta,
         "row": (indice - 1) // 2 * ALTO, "col": (indice - 1) % 2 * ANCHO,
         "size_x": ANCHO, "size_y": ALTO,
         "parameter_mappings": [], "series": [], "visualization_settings": {}}
        for indice, tarjeta in enumerate(tarjetas, start=1)
    ]})
    print(f"\nTablero listo: {URL_PUBLICA}/dashboard/{tablero}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
