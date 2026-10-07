#!/usr/bin/env python3
"""Construye la base DuckDB de indicadores y documenta el Ejercicio 7.

1. Ejecuta sql/05_modelo_indicadores.sql sobre data/processed/taxi.duckdb
   (tabla `viajes`, tabla `zonas` y vista `viajes_validos`).
2. Ejecuta cada indicador de sql/06_indicadores.sql.
3. Genera docs/ejercicio_7_indicadores.md con pregunta, justificacion,
   consulta, resultado e interpretacion de cada indicador.

Metabase abre la misma base. Si Metabase la tiene abierta, DuckDB no permite
reconstruirla: detenga el servicio, ejecute el script y vuelva a iniciarlo.

    docker compose stop metabase
    docker compose exec -T lab python scripts/build_indicadores.py
    docker compose start metabase
"""

from __future__ import annotations

import argparse
import os
import time
from pathlib import Path

import duckdb

from run_exploration import cargar_consultas, tabla_markdown


ROOT = Path(__file__).resolve().parents[1]
MODELO_SQL = ROOT / "sql" / "05_modelo_indicadores.sql"
INDICADORES_SQL = ROOT / "sql" / "06_indicadores.sql"
DB_PATH = ROOT / "data" / "processed" / "taxi.duckdb"
DOC_PATH = ROOT / "docs" / "ejercicio_7_indicadores.md"
MAX_FILAS_DOC = 40


def construir_modelo(conexion: duckdb.DuckDBPyConnection, ejecutar: bool) -> list[str]:
    partes = ["## Modelo de datos", ""]
    for consulta in cargar_consultas(MODELO_SQL):
        meta = consulta.metadatos
        partes.extend([
            f"### {meta.get('title', consulta.nombre)}", "",
            f"**Objetivo:** {meta.get('objective', '')}", "",
            f"**Decision:** {meta.get('decision', '')}", "",
            "```sql", consulta.sql, "```", "",
        ])
        if ejecutar:
            print(f"Ejecutando {consulta.nombre}...", flush=True)
            inicio = time.perf_counter()
            conexion.execute(consulta.sql)
            partes.extend([f"Tiempo de ejecucion: {time.perf_counter() - inicio:.1f} s.", ""])
    if ejecutar:
        conexion.execute("CHECKPOINT")

    resumen = conexion.execute("""
        SELECT v.anio, v.tipo_taxi, v.registros, coalesce(w.validos, 0) AS validos,
               round(100.0 * coalesce(w.validos, 0) / v.registros, 2) AS pct_validos
        FROM (SELECT anio, tipo_taxi, count(*) AS registros FROM viajes GROUP BY ALL) AS v
        LEFT JOIN (SELECT anio, tipo_taxi, count(*) AS validos FROM viajes_validos GROUP BY ALL) AS w
          USING (anio, tipo_taxi)
        ORDER BY anio, tipo_taxi
    """).fetchall()
    partes.extend([
        "### Registros cargados y registros validos", "",
        tabla_markdown(["anio", "tipo_taxi", "registros", "validos", "pct_validos"], resumen), "",
    ])
    return partes


def documentar_indicadores(conexion: duckdb.DuckDBPyConnection) -> list[str]:
    partes = ["## Indicadores", ""]
    for numero, consulta in enumerate(cargar_consultas(INDICADORES_SQL), start=1):
        print(f"Indicador {consulta.nombre}...", flush=True)
        cursor = conexion.execute(consulta.sql)
        columnas = [item[0] for item in cursor.description]
        filas = cursor.fetchall()
        meta = consulta.metadatos
        partes.extend([
            f"### {numero}. {meta.get('title', consulta.nombre)}", "",
            f"**Pregunta:** {meta.get('question', '')}", "",
            f"**Justificacion:** {meta.get('justification', '')}", "",
            f"**Indicador:** {meta.get('indicator', '')}", "",
            f"**Visualizacion:** grafico `{meta.get('display', 'table')}` con "
            f"`{meta.get('dimensions', '')}` como ejes y `{meta.get('metrics', '')}` como valores.", "",
            "```sql", consulta.sql, "```", "",
            tabla_markdown(columnas, filas[:MAX_FILAS_DOC]), "",
        ])
        if len(filas) > MAX_FILAS_DOC:
            partes.extend([f"_Se muestran {MAX_FILAS_DOC} de {len(filas)} filas; el resto esta en el notebook 07._", ""])
        partes.extend([f"**Interpretacion:** {meta.get('interpretation', 'Pendiente.')}", ""])
    return partes


def main() -> int:
    parser = argparse.ArgumentParser(description="Construye la base y la documentacion de indicadores.")
    parser.add_argument("--solo-documento", action="store_true",
                        help="no reconstruye la base; solo vuelve a ejecutar los indicadores")
    args = parser.parse_args()

    os.chdir(ROOT)
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    try:
        if not args.solo_documento and DB_PATH.exists():
            # Abrirla en escritura falla si otro proceso la usa: se comprueba
            # antes de borrarla. La base es un derivado de los Parquet y se recrea
            # desde cero porque CREATE OR REPLACE no devuelve el espacio al disco.
            duckdb.connect(str(DB_PATH)).close()
            for ruta in (DB_PATH, DB_PATH.with_name(DB_PATH.name + ".wal")):
                ruta.unlink(missing_ok=True)
        conexion = duckdb.connect(str(DB_PATH), read_only=args.solo_documento)
    except duckdb.IOException as error:
        raise SystemExit(
            f"No se pudo abrir {DB_PATH.relative_to(ROOT)}: {error}\n"
            "Si Metabase o un notebook la tienen abierta, detengalos "
            "(docker compose stop metabase) y vuelva a intentarlo."
        )

    partes = [
        "# Ejercicio 7 - Indicadores y tablero", "",
        "Documento generado por `scripts/build_indicadores.py`. Los indicadores se calculan sobre",
        "`data/processed/taxi.duckdb`, que materializa los Parquet descargados, y se visualizan en",
        "Metabase (<http://localhost:3000>) y en `notebooks/07_indicadores.ipynb`.", "",
    ]
    with conexion:
        partes.extend(construir_modelo(conexion, ejecutar=not args.solo_documento))
        partes.extend(documentar_indicadores(conexion))

    DOC_PATH.write_text("\n".join(partes), encoding="utf-8")
    print(f"Base: {DB_PATH.relative_to(ROOT)}")
    print(f"Documento: {DOC_PATH.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
