#!/usr/bin/env python3
"""Ejecuta el analisis exploratorio del Ejercicio 4 y documenta resultados."""

from __future__ import annotations

import argparse
import os
from pathlib import Path

import duckdb

from run_exploration import cargar_consultas, tabla_markdown


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SQL = ROOT / "sql" / "02_analisis_exploratorio.sql"
DEFAULT_OUTPUT = ROOT / "docs" / "ejercicio_4_resultados.md"


def generar_hallazgos(resultados: dict[str, tuple[list[str], list[tuple]]]) -> list[str]:
    hallazgos: list[str] = []

    columnas, filas = resultados["01_evolucion_mensual"]
    meses = [dict(zip(columnas, fila)) for fila in filas]
    for tipo in ("yellow", "green"):
        pico = max((fila for fila in meses if fila["tipo_taxi"] == tipo), key=lambda x: x["viajes_por_dia"])
        hallazgos.append(
            f"La mayor demanda diaria de {tipo.capitalize()} ocurre en el mes {pico['mes']}: "
            f"{pico['viajes_por_dia']:,.1f} viajes por dia."
        )

    columnas, filas = resultados["02_patron_horario"]
    horas = [dict(zip(columnas, fila)) for fila in filas]
    for tipo in ("yellow", "green"):
        pico = max(
            (fila for fila in horas if fila["tipo_taxi"] == tipo and fila["tipo_dia"] == "laboral"),
            key=lambda x: x["viajes"],
        )
        hallazgos.append(
            f"En dias laborales, la hora pico de {tipo.capitalize()} es las {pico['hora']:02d}:00 "
            f"({pico['porcentaje']:.2f}% de sus viajes laborales)."
        )

    columnas, filas = resultados["03_caracteristicas_por_tipo"]
    metricas = {dict(zip(columnas, fila))["tipo_taxi"]: dict(zip(columnas, fila)) for fila in filas}
    if {"yellow", "green"} <= metricas.keys():
        y, g = metricas["yellow"], metricas["green"]
        hallazgos.append(
            f"El viaje mediano de Yellow recorre {y['distancia_mediana']:.2f} millas y cuesta "
            f"USD {y['monto_mediano']:.2f}; en Green las medianas son "
            f"{g['distancia_mediana']:.2f} millas y USD {g['monto_mediano']:.2f}."
        )

    columnas, filas = resultados["05_propinas_tarjeta"]
    propinas = [dict(zip(columnas, fila)) for fila in filas]
    for fila in propinas:
        hallazgos.append(
            f"En pagos con tarjeta de {fila['tipo_taxi'].capitalize()}, "
            f"{fila['pct_con_propina']:.2f}% registra propina y la mediana es USD "
            f"{fila['propina_mediana']:.2f}."
        )

    columnas, filas = resultados["04_formas_pago"]
    pagos = [dict(zip(columnas, fila)) for fila in filas]
    for tipo in ("yellow", "green"):
        principal = max((fila for fila in pagos if fila["tipo_taxi"] == tipo), key=lambda x: x["viajes"])
        hallazgos.append(
            f"En {tipo.capitalize()}, la categoria de pago mas frecuente es "
            f"{principal['forma_pago']} ({principal['porcentaje']:.2f}% de los viajes)."
        )

    columnas, filas = resultados["07_atipicos_inconsistencias"]
    calidad = [dict(zip(columnas, fila)) for fila in filas]
    registros = sum(f["registros"] for f in calidad)
    distancias = sum(f["distancia_no_positiva"] for f in calidad)
    negativos = sum(f["total_negativo"] for f in calidad)
    hallazgos.append(
        f"La calidad requiere filtros explicitos: {distancias:,} de {registros:,} registros "
        f"tienen distancia no positiva y {negativos:,} tienen monto total negativo."
    )
    return hallazgos


def generar_documento(conexion: duckdb.DuckDBPyConnection, sql_path: Path) -> str:
    consultas = cargar_consultas(sql_path)
    partes = [
        "# Ejercicio 4 - Analisis exploratorio con DuckDB",
        "",
        "Documento reproducible generado por `scripts/run_eda.py` sobre los Parquet de 2026.",
        "Cada seccion explicita la pregunta, su justificacion, la consulta y la interpretacion.",
        "",
        "## Criterio de analisis",
        "",
        "Se conservan los registros originales. Cuando una metrica exige viajes plausibles,",
        "la consulta aplica y muestra sus filtros. Yellow y Green se normalizan solo dentro",
        "de cada consulta porque sus columnas de fecha tienen nombres diferentes.",
        "",
    ]
    resultados: dict[str, tuple[list[str], list[tuple]]] = {}

    for consulta in consultas:
        print(f"Ejecutando {consulta.nombre}...", flush=True)
        cursor = conexion.execute(consulta.sql)
        columnas = [item[0] for item in cursor.description]
        filas = cursor.fetchall()
        resultados[consulta.nombre] = (columnas, filas)
        meta = consulta.metadatos
        partes.extend([
            f"## {meta.get('title', consulta.nombre)}",
            "",
            f"**Pregunta:** {meta.get('question', 'No especificada.')}",
            "",
            f"**Justificacion:** {meta.get('justification', 'No especificada.')}",
            "",
            f"**Fuente:** {meta.get('source', 'No especificada.')}",
            "",
            "```sql",
            consulta.sql,
            "```",
            "",
            tabla_markdown(columnas, filas),
            "",
            f"**Interpretacion:** {meta.get('interpretation', 'No especificada.')}",
            "",
        ])

    partes.extend(["## Hallazgos relevantes", ""])
    partes.extend(f"- {hallazgo}" for hallazgo in generar_hallazgos(resultados))
    partes.extend([
        "",
        "Los hallazgos son regenerados a partir de los datos disponibles y no estan escritos",
        "como constantes. Por eso pueden cambiar cuando la TLC publique o se incorpore otro mes.",
        "",
    ])
    return "\n".join(partes)


def main() -> int:
    parser = argparse.ArgumentParser(description="Ejecuta el analisis exploratorio del Ejercicio 4.")
    parser.add_argument("--sql", type=Path, default=DEFAULT_SQL)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    os.chdir(ROOT)
    archivos = list((ROOT / "data" / "raw").glob("*/2026/*.parquet"))
    if not archivos:
        raise SystemExit("No hay Parquet de 2026. Ejecute scripts/download_data.py --years 2026.")

    with duckdb.connect(":memory:") as conexion:
        conexion.execute("PRAGMA threads = 4")
        documento = generar_documento(conexion, args.sql.resolve())

    salida = args.output.resolve()
    salida.parent.mkdir(parents=True, exist_ok=True)
    salida.write_text(documento, encoding="utf-8")
    print(f"Consultas ejecutadas: {len(cargar_consultas(args.sql.resolve()))}")
    print(f"Resultado: {salida}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
