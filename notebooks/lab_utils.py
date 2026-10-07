"""Utilidades compartidas por los notebooks del laboratorio.

Los notebooks no duplican SQL: leen las consultas nombradas de `sql/*.sql`
con el mismo parser que usan los scripts, de modo que notebook y script
siempre ejecutan exactamente la misma consulta.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import duckdb
import pandas as pd
from IPython.display import Markdown, display

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
# Las consultas usan rutas relativas a la raiz (data/raw/...).
os.chdir(ROOT)

from run_exploration import Consulta, cargar_consultas  # noqa: E402

ETIQUETAS = {
    "question": "Pregunta",
    "objective": "Objetivo",
    "justification": "Justificacion",
    "source": "Fuente",
    "decision": "Decision",
    "indicator": "Indicador",
    "interpretation": "Interpretacion",
}

pd.set_option("display.max_rows", 100)
pd.set_option("display.float_format", lambda valor: f"{valor:,.2f}")


BASE_INDICADORES = ROOT / "data" / "processed" / "taxi.duckdb"
SQL_INDICADORES = "06_indicadores.sql"


def conectar(base: Path | None = None) -> duckdb.DuckDBPyConnection:
    """Sin `base`, conexion en memoria que lee los Parquet directamente.

    Con `base`, abre esa base DuckDB en solo lectura, de modo que Metabase
    pueda leerla al mismo tiempo.
    """
    # El contenedor comparte ~8 GB con Metabase; con un limite, DuckDB usa disco
    # para consultas pesadas (p. ej. varias medianas) en lugar de agotar la memoria.
    config = {"memory_limit": "3GB"}
    if base:
        return duckdb.connect(str(base), read_only=True, config=config)
    return duckdb.connect(config=config)


def consultas(archivo: str) -> dict[str, Consulta]:
    return {c.nombre: c for c in cargar_consultas(ROOT / "sql" / archivo)}


def ejecutar(
    conexion: duckdb.DuckDBPyConnection,
    archivo: str,
    nombre: str,
    mostrar_sql: bool = True,
    **plantilla: str,
) -> pd.DataFrame:
    """Ejecuta la consulta `nombre` de `sql/<archivo>` y devuelve un DataFrame.

    Muestra antes los metadatos documentados (objetivo, fuente, decision...)
    y el SQL. `plantilla` reemplaza marcadores como {source} del benchmark.
    """
    consulta = consultas(archivo)[nombre]
    sql = consulta.sql.format(**plantilla) if plantilla else consulta.sql
    if mostrar_sql:
        meta = consulta.metadatos
        lineas = [f"**{meta.get('title', nombre)}** (`{archivo}` - `{nombre}`)", ""]
        for clave, etiqueta in ETIQUETAS.items():
            if clave in meta:
                lineas.append(f"- **{etiqueta}:** {meta[clave]}")
        lineas.extend(["", "```sql", sql, "```"])
        display(Markdown("\n".join(lineas)))
    df = conexion.execute(sql).df()
    # sum()/count() de DuckDB pueden llegar como float64 (HUGEINT); se
    # devuelven a entero cuando todos los valores son enteros.
    for columna in df.select_dtypes("float").columns:
        valores = df[columna].dropna()
        if len(valores) and (valores % 1 == 0).all():
            df[columna] = df[columna].astype("Int64")
    return df


# --------------------------------------------------------------------------
# Ejercicio 7: indicadores y tablero
# --------------------------------------------------------------------------

def _lista(meta: dict[str, str], clave: str) -> list[str]:
    return [valor.strip() for valor in meta.get(clave, "").split(",") if valor.strip()]


def graficar(nombre: str, df: pd.DataFrame, ax=None):
    """Dibuja un indicador segun sus metadatos display/dimensions/metrics."""
    import matplotlib.pyplot as plt

    meta = consultas(SQL_INDICADORES)[nombre].metadatos
    dims, metricas = _lista(meta, "dimensions"), _lista(meta, "metrics")
    tipo = meta.get("display", "bar")
    ax = ax or plt.subplots(figsize=(10, 4))[1]
    titulo = meta.get("title", nombre)

    if nombre == "09_hora_dia_semana":
        tabla = df.pivot(index=dims[1], columns=dims[0], values=metricas[0])
        imagen = ax.imshow(tabla, aspect="auto", cmap="viridis")
        ax.set_yticks(range(len(tabla.index)), tabla.index)
        ax.set_xticks(range(0, 24, 2), range(0, 24, 2))
        ax.set_xlabel("hora")
        ax.figure.colorbar(imagen, ax=ax, label="% de los viajes del dia")
    else:
        if len(dims) == 2:
            datos = df.pivot(index=dims[0], columns=dims[1], values=metricas[0])
        else:
            datos = df.set_index(dims[0])[metricas]
        if tipo == "line":
            if dims[0] == "fecha":
                # Los meses sin datos (p. ej. 2025 antes de descargarlo) quedan
                # como hueco en lugar de una linea que los atraviesa.
                datos.index = pd.to_datetime(datos.index)
                datos = datos.reindex(pd.date_range(datos.index.min(), datos.index.max(), freq="MS"))
            # Green tiene ~1 % del volumen de Yellow: eje secundario para verlo.
            secundario = ["green"] if nombre == "08_demanda_mensual" else None
            datos.plot(ax=ax, marker=".", secondary_y=secundario)
        elif tipo == "row":
            datos.iloc[::-1].plot.barh(ax=ax, legend=False)
        else:
            datos.plot.bar(ax=ax, rot=0 if len(datos) <= 6 else 25)
        ax.set_ylabel(", ".join(metricas) if len(dims) == 2 or tipo == "row" else "")
    ax.set_title(titulo)
    return ax


def indicador(conexion: duckdb.DuckDBPyConnection, nombre: str) -> pd.DataFrame:
    """Muestra pregunta, SQL, resultado, grafico e interpretacion de un indicador."""
    import matplotlib.pyplot as plt

    consulta = consultas(SQL_INDICADORES)[nombre]
    meta = consulta.metadatos
    display(Markdown("\n".join([
        f"**Pregunta:** {meta.get('question', '')}", "",
        f"**Justificacion:** {meta.get('justification', '')}", "",
        f"**Indicador:** {meta.get('indicator', '')}", "",
        "<details><summary>Consulta SQL</summary>", "",
        "```sql", consulta.sql, "```", "</details>",
    ])))
    df = ejecutar(conexion, SQL_INDICADORES, nombre, mostrar_sql=False)
    display(df if len(df) <= 30 else df.head(30))
    graficar(nombre, df)
    plt.tight_layout()
    plt.show()
    display(Markdown(f"**Interpretacion:** {meta.get('interpretation', 'Pendiente.')}"))
    return df


def tablero(resultados: dict[str, pd.DataFrame], columnas: int = 2):
    """Une todos los indicadores en una sola figura, como el tablero de Metabase."""
    import math
    import matplotlib.pyplot as plt

    filas = math.ceil(len(resultados) / columnas)
    fig, ejes = plt.subplots(filas, columnas, figsize=(9 * columnas, 4.2 * filas))
    for ax, (nombre, df) in zip(ejes.flat, resultados.items()):
        graficar(nombre, df, ax=ax)
    for ax in list(ejes.flat)[len(resultados):]:
        ax.set_visible(False)
    fig.suptitle("Tablero de indicadores - NYC Taxi", fontsize=16)
    fig.tight_layout(rect=(0, 0, 1, 0.98))
    return fig
