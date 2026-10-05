#!/usr/bin/env python3
"""Compara consultas directas a Parquet y una tabla DuckDB (Ejercicio 6)."""

from __future__ import annotations

import argparse
import csv
import os
import statistics
import time
from pathlib import Path

import duckdb

from run_exploration import cargar_consultas, tabla_markdown


ROOT = Path(__file__).resolve().parents[1]
SQL_PATH = ROOT / "sql" / "04_benchmark.sql"
DB_PATH = ROOT / "data" / "processed" / "taxi_benchmark.duckdb"
CSV_PATH = ROOT / "docs" / "ejercicio_6_benchmark.csv"
MD_PATH = ROOT / "docs" / "ejercicio_6_resultados.md"

PARQUET_SOURCE = """(
    SELECT CAST(regexp_extract(filename, 'tripdata_(\\d{4})-', 1) AS INTEGER) AS anio,
           'yellow' AS tipo_taxi, tpep_pickup_datetime AS pickup_datetime,
           tpep_dropoff_datetime AS dropoff_datetime, passenger_count, trip_distance,
           payment_type, fare_amount, tip_amount, total_amount,
           PULocationID AS pickup_location_id, DOLocationID AS dropoff_location_id
    FROM read_parquet('data/raw/yellow/*/*.parquet', filename = true, union_by_name = true)
    UNION ALL
    SELECT CAST(regexp_extract(filename, 'tripdata_(\\d{4})-', 1) AS INTEGER),
           'green', lpep_pickup_datetime, lpep_dropoff_datetime, passenger_count, trip_distance,
           payment_type, fare_amount, tip_amount, total_amount, PULocationID, DOLocationID
    FROM read_parquet('data/raw/green/*/*.parquet', filename = true, union_by_name = true)
)"""


def materializar(conexion: duckdb.DuckDBPyConnection, anios: list[int]) -> float:
    filtro = ", ".join(map(str, anios))
    inicio = time.perf_counter()
    conexion.execute(f"CREATE OR REPLACE TABLE viajes AS SELECT * FROM {PARQUET_SOURCE} WHERE anio IN ({filtro})")
    conexion.execute("CHECKPOINT")
    return time.perf_counter() - inicio


def medir(conexion: duckdb.DuckDBPyConnection, sql: str, iteraciones: int) -> tuple[float, float, int]:
    tiempos: list[float] = []
    filas = 0
    for _ in range(iteraciones):
        inicio = time.perf_counter()
        resultado = conexion.execute(sql).fetchall()
        tiempos.append(time.perf_counter() - inicio)
        filas = len(resultado)
    posteriores = tiempos[1:] if len(tiempos) > 1 else tiempos
    return tiempos[0], statistics.median(posteriores), filas


def escenarios(anios: list[int]) -> list[tuple[str, str]]:
    items = [(str(anio), f"anio = {anio}") for anio in anios]
    if len(anios) > 1:
        etiqueta = "+".join(map(str, anios))
        items.append((etiqueta, f"anio IN ({', '.join(map(str, anios))})"))
    return items


def escribir_csv(filas: list[dict[str, object]], ruta: Path) -> None:
    ruta.parent.mkdir(parents=True, exist_ok=True)
    with ruta.open("w", newline="", encoding="utf-8") as archivo:
        writer = csv.DictWriter(archivo, fieldnames=list(filas[0]))
        writer.writeheader()
        writer.writerows(filas)


def documento(filas: list[dict[str, object]], materializacion_s: float, iteraciones: int) -> str:
    consultas = cargar_consultas(SQL_PATH)
    columnas = list(filas[0])
    valores = [tuple(fila[c] for c in columnas) for fila in filas]
    pares: dict[tuple[str, str], dict[str, float]] = {}
    for fila in filas:
        pares.setdefault((str(fila["escenario"]), str(fila["consulta"])), {})[str(fila["fuente"])] = float(fila["mediana_s"])
    razones = [p["parquet"] / p["duckdb"] for p in pares.values() if p.get("duckdb", 0) > 0 and "parquet" in p]
    razon = statistics.median(razones) if razones else 0

    partes = [
        "# Ejercicio 6 - Parquet versus tablas DuckDB", "",
        f"La tabla se materializo en {materializacion_s:.3f} s. Cada combinacion se ejecuto {iteraciones} veces;",
        "se registra por separado la primera ejecucion y la mediana de las restantes.", "",
        "## Resultados", "", tabla_markdown(columnas, valores), "",
        "## Consultas utilizadas", "",
    ]
    for consulta in consultas:
        partes.extend([
            f"### {consulta.metadatos.get('title', consulta.nombre)}", "",
            f"{consulta.metadatos.get('objective', '')}", "", "```sql", consulta.sql, "```", "",
        ])
    partes.extend([
        "## Analisis", "",
        f"En la mediana de las combinaciones medidas, Parquet tardo {razon:.2f} veces el tiempo de la tabla DuckDB.",
        "La tabla evita interpretar multiples archivos y sus metadatos en cada consulta, pero exige tiempo y",
        "espacio adicional para materializarse. La primera ejecucion puede incluir calentamiento de paginas y",
        "metadatos; por eso no se mezcla con la mediana de repeticiones posteriores.", "",
        "Consultar Parquet directamente es apropiado para datos que llegan como archivos, exploraciones",
        "ocasionales, seleccion de pocas columnas y flujos donde se quiere evitar duplicar almacenamiento.",
        "Materializar conviene cuando las mismas transformaciones y consultas se repiten, se necesita un esquema",
        "estable o el costo de preparacion se amortiza entre muchos usuarios. El benchmark no incluye el tiempo",
        "de materializacion dentro de cada consulta; debe considerarse por separado al tomar la decision.", "",
    ])
    return "\n".join(partes)


def main() -> int:
    parser = argparse.ArgumentParser(description="Benchmark Parquet versus tabla DuckDB.")
    parser.add_argument("--years", nargs="+", type=int, default=[2024, 2026])
    parser.add_argument("--iterations", type=int, default=3)
    parser.add_argument("--database", type=Path, default=DB_PATH)
    parser.add_argument("--csv", type=Path, default=CSV_PATH)
    parser.add_argument("--output", type=Path, default=MD_PATH)
    args = parser.parse_args()
    if args.iterations < 1:
        parser.error("--iterations debe ser al menos 1")

    anios = list(dict.fromkeys(args.years))
    os.chdir(ROOT)
    faltantes = [anio for anio in anios if not list((ROOT / "data/raw").glob(f"*/{anio}/*.parquet"))]
    if faltantes:
        raise SystemExit(f"Faltan Parquet de {faltantes}. Ejecute scripts/download_data.py --years {' '.join(map(str, faltantes))}.")

    db = args.database.resolve()
    db.parent.mkdir(parents=True, exist_ok=True)
    consultas = cargar_consultas(SQL_PATH)
    filas: list[dict[str, object]] = []
    with duckdb.connect(str(db)) as conexion:
        conexion.execute("PRAGMA threads = 4")
        materializacion_s = materializar(conexion, anios)
        volumenes = dict(conexion.execute("SELECT anio, count(*) FROM viajes GROUP BY anio").fetchall())
        for etiqueta, filtro in escenarios(anios):
            registros = sum(volumenes[a] for a in anios if str(a) in etiqueta.split("+"))
            for consulta in consultas:
                for fuente, source_sql in (("parquet", PARQUET_SOURCE), ("duckdb", "viajes")):
                    sql = consulta.sql.format(source=source_sql, year_filter=filtro)
                    primera, mediana, filas_resultado = medir(conexion, sql, args.iterations)
                    filas.append({
                        "escenario": etiqueta, "registros": registros,
                        "consulta": consulta.nombre, "fuente": fuente,
                        "primera_s": round(primera, 6), "mediana_s": round(mediana, 6),
                        "filas_resultado": filas_resultado,
                    })
                    print(f"{etiqueta:9} {consulta.nombre:24} {fuente:7} {mediana:.3f} s")

    escribir_csv(filas, args.csv.resolve())
    salida = args.output.resolve()
    salida.parent.mkdir(parents=True, exist_ok=True)
    salida.write_text(documento(filas, materializacion_s, args.iterations), encoding="utf-8")
    print(f"Base DuckDB: {db}")
    print(f"Resultados: {salida}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
