#!/usr/bin/env python3
"""Ejecuta las consultas del Ejercicio 3 y genera documentacion Markdown."""

from __future__ import annotations

import argparse
import os
import re
from dataclasses import dataclass, field
from datetime import date, datetime
from decimal import Decimal
from pathlib import Path
from typing import Any

import duckdb


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SQL = ROOT / "sql" / "01_exploracion_inicial.sql"
DEFAULT_OUTPUT = ROOT / "docs" / "ejercicio_3_resultados.md"
NAME_PATTERN = re.compile(r"^-- name:\s*(.+?)\s*$")
META_PATTERN = re.compile(r"^-- ([a-z_]+):\s*(.*?)\s*$")


@dataclass
class Consulta:
    nombre: str
    metadatos: dict[str, str] = field(default_factory=dict)
    lineas_sql: list[str] = field(default_factory=list)

    @property
    def sql(self) -> str:
        return "\n".join(self.lineas_sql).strip()


def cargar_consultas(ruta: Path) -> list[Consulta]:
    consultas: list[Consulta] = []
    actual: Consulta | None = None
    leyendo_sql = False

    for linea in ruta.read_text(encoding="utf-8").splitlines():
        coincidencia_nombre = NAME_PATTERN.match(linea)
        if coincidencia_nombre:
            if actual is not None:
                consultas.append(actual)
            actual = Consulta(nombre=coincidencia_nombre.group(1))
            leyendo_sql = False
            continue

        if actual is None:
            continue

        coincidencia_meta = META_PATTERN.match(linea)
        if coincidencia_meta and not leyendo_sql:
            clave, valor = coincidencia_meta.groups()
            actual.metadatos[clave] = valor
            continue

        if linea.strip() or leyendo_sql:
            leyendo_sql = True
            actual.lineas_sql.append(linea)

    if actual is not None:
        consultas.append(actual)

    if not consultas:
        raise ValueError(f"No se encontraron consultas nombradas en {ruta}")
    return consultas


def formatear_valor(valor: Any) -> str:
    if valor is None:
        return "NULL"
    if isinstance(valor, (datetime, date)):
        return valor.isoformat(sep=" ") if isinstance(valor, datetime) else valor.isoformat()
    if isinstance(valor, Decimal):
        return format(valor, "f")
    if isinstance(valor, float):
        return f"{valor:.6g}"
    return str(valor).replace("|", "\\|").replace("\n", " ")


def tabla_markdown(columnas: list[str], filas: list[tuple[Any, ...]]) -> str:
    encabezado = "| " + " | ".join(columnas) + " |"
    separador = "| " + " | ".join("---" for _ in columnas) + " |"
    if not filas:
        return "\n".join((encabezado, separador, "| " + " | ".join("Sin filas" for _ in columnas) + " |"))
    cuerpo = [
        "| " + " | ".join(formatear_valor(valor) for valor in fila) + " |"
        for fila in filas
    ]
    return "\n".join((encabezado, separador, *cuerpo))


def generar_documento(
    conexion: duckdb.DuckDBPyConnection,
    consultas: list[Consulta],
) -> str:
    partes = [
        "# Ejercicio 3 - Exploracion inicial con DuckDB",
        "",
        "Documento generado por `scripts/run_exploration.py`. Las consultas leen",
        "directamente los archivos Parquet; no se crea una tabla materializada.",
        "",
        "## Metodo",
        "",
        "DuckDB obtiene el esquema y ejecuta agregaciones sobre Parquet mediante",
        "`read_parquet`. Se usa `union_by_name = true` al combinar Yellow y Green",
        "Taxi porque ambos conjuntos tienen columnas que no coinciden por completo.",
        "",
    ]

    resultados: dict[str, tuple[list[str], list[tuple[Any, ...]]]] = {}

    for consulta in consultas:
        titulo = consulta.metadatos.get("title", consulta.nombre)
        cursor = conexion.execute(consulta.sql)
        columnas = [descripcion[0] for descripcion in cursor.description]
        filas = cursor.fetchall()
        resultados[consulta.nombre] = (columnas, filas)

        partes.extend(
            [
                f"## {titulo}",
                "",
                f"**Identificador:** `{consulta.nombre}`",
                "",
                f"**Objetivo:** {consulta.metadatos.get('objective', 'No especificado.')}",
                "",
                f"**Fuente:** {consulta.metadatos.get('source', 'No especificada.')}",
                "",
                "**Consulta SQL:**",
                "",
                "```sql",
                consulta.sql,
                "```",
                "",
                "**Resultado:**",
                "",
                tabla_markdown(columnas, filas),
                "",
                f"**Decision:** {consulta.metadatos.get('decision', 'No especificada.')}",
                "",
            ]
        )

    columnas_calidad, filas_calidad = resultados["07_calidad_datos"]
    calidad = [dict(zip(columnas_calidad, fila)) for fila in filas_calidad]
    fuera_2026 = sum(fila["pickup_fuera_2026"] for fila in calidad)
    duraciones_negativas = sum(fila["duracion_negativa"] for fila in calidad)
    pasajeros_nulos = sum(fila["pasajeros_nulos"] for fila in calidad)
    distancias_no_positivas = sum(
        fila["distancia_no_positiva"] for fila in calidad
    )
    totales_negativos = sum(fila["total_negativo"] for fila in calidad)

    partes.extend(
        [
            "## Interpretacion inicial",
            "",
            "Los conteos anteriores validan la cobertura de archivos y registros.",
            "Las tablas de esquema muestran que Yellow y Green Taxi usan nombres distintos",
            "para las fechas (`tpep_*` y `lpep_*`) y que Green Taxi contiene campos propios.",
            "",
            "La revision inicial encontro los siguientes problemas que deben considerarse",
            "antes de responder preguntas analiticas:",
            "",
            f"- {fuera_2026:,} registros tienen una fecha de inicio fuera de 2026.",
            f"- {duraciones_negativas:,} registros tienen una fecha de fin anterior al inicio.",
            f"- {pasajeros_nulos:,} registros no informan la cantidad de pasajeros.",
            f"- {distancias_no_positivas:,} registros tienen distancia igual o menor que cero.",
            f"- {totales_negativos:,} registros tienen un monto total negativo.",
            "",
            "Los indicadores de calidad no implican que un registro deba eliminarse de forma",
            "automatica: cada filtro debe justificarse segun la pregunta analitica.",
            "",
            "Consultar Parquet directamente significa que DuckDB interpreta el esquema y lee",
            "los archivos desde su ubicacion original, sin una importacion previa. Esta",
            "estrategia evita duplicar datos y permite aprovechar la lectura por columnas y",
            "el filtrado temprano, lo cual resulta util para conjuntos grandes.",
            "",
        ]
    )
    return "\n".join(partes)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Ejecuta y documenta las consultas del Ejercicio 3."
    )
    parser.add_argument("--sql", type=Path, default=DEFAULT_SQL)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    argumentos = parser.parse_args()

    os.chdir(ROOT)
    archivos = list((ROOT / "data" / "raw").glob("*/2026/*.parquet"))
    if not archivos:
        raise SystemExit(
            "No se encontraron archivos Parquet en data/raw/<tipo>/2026/. "
            "Ejecute primero scripts/download_data.py."
        )

    consultas = cargar_consultas(argumentos.sql.resolve())
    with duckdb.connect(":memory:") as conexion:
        conexion.execute("PRAGMA threads = 4")
        documento = generar_documento(conexion, consultas)

    salida = argumentos.output.resolve()
    salida.parent.mkdir(parents=True, exist_ok=True)
    salida.write_text(documento, encoding="utf-8")
    print(f"Consultas ejecutadas: {len(consultas)}")
    print(f"Archivos Parquet detectados: {len(archivos)}")
    print(f"Resultado: {salida}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
