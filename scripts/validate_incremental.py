#!/usr/bin/env python3
"""Valida y documenta la incorporacion incremental de 2024 (Ejercicio 5)."""

from __future__ import annotations

import argparse
import os
from pathlib import Path

import duckdb

from run_exploration import cargar_consultas, tabla_markdown


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SQL = ROOT / "sql" / "03_validacion_incremental.sql"
DEFAULT_OUTPUT = ROOT / "docs" / "ejercicio_5_validacion.md"


def main() -> int:
    parser = argparse.ArgumentParser(description="Valida la incorporacion de 2024 y 2026.")
    parser.add_argument("--sql", type=Path, default=DEFAULT_SQL)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    os.chdir(ROOT)

    faltantes = [anio for anio in (2024, 2026) if not list((ROOT / "data/raw").glob(f"*/{anio}/*.parquet"))]
    if faltantes:
        raise SystemExit(
            f"Faltan archivos de {', '.join(map(str, faltantes))}. "
            "Ejecute scripts/download_data.py --years 2024 2026."
        )

    consultas = cargar_consultas(args.sql.resolve())
    partes = [
        "# Ejercicio 5 - Incorporacion incremental de 2024",
        "",
        "Documento generado por `scripts/validate_incremental.py`.",
        "",
    ]
    with duckdb.connect(":memory:") as conexion:
        conexion.execute("PRAGMA threads = 4")
        for consulta in consultas:
            cursor = conexion.execute(consulta.sql)
            columnas = [item[0] for item in cursor.description]
            filas = cursor.fetchall()
            partes.extend([
                f"## {consulta.metadatos.get('title', consulta.nombre)}", "",
                f"**Objetivo:** {consulta.metadatos.get('objective', 'No especificado.')}", "",
                "```sql", consulta.sql, "```", "",
                tabla_markdown(columnas, filas), "",
                f"**Decision:** {consulta.metadatos.get('decision', 'No especificada.')}", "",
            ])

    partes.extend([
        "## Cambios necesarios en las consultas anteriores", "",
        "Las preguntas del Ejercicio 4 siguen siendo validas. Para analizarlas sobre ambos",
        "anios se reemplaza el patron `data/raw/<tipo>/2026/*.parquet` por",
        "`data/raw/<tipo>/*/*.parquet`, se agrega `anio` desde `filename` y se sustituye el",
        "filtro fijo de 2026 por el rango o agrupacion anual requerido. No cambian las",
        "formulas ni la normalizacion entre `tpep_*` y `lpep_*`.", "",
        "## Por que el flujo es incremental", "",
        "El descargador recibe una lista de anios, construye rutas particionadas por tipo/anio",
        "y valida cada archivo antes de decidir si lo omite. Las consultas usan patrones de",
        "archivos y `union_by_name`; por ello un archivo mensual nuevo entra en el siguiente",
        "analisis sin importacion manual ni cambios en una lista de nombres.", "",
    ])

    salida = args.output.resolve()
    salida.parent.mkdir(parents=True, exist_ok=True)
    salida.write_text("\n".join(partes), encoding="utf-8")
    print(f"Consultas ejecutadas: {len(consultas)}")
    print(f"Resultado: {salida}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
