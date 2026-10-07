#!/usr/bin/env python3
"""Valida la incorporacion de 2025 y documenta el analisis 2024-2026 (Ejercicio 8).

Ejecuta sql/07_ejercicio_8.sql en una conexion en memoria que lee los Parquet
directamente y adjunta data/processed/taxi.duckdb (solo lectura) como `taxi`,
y genera docs/ejercicio_8_resultados.md.

Requisitos previos:
    docker compose exec lab python scripts/download_data.py      # 2024, 2025 y 2026
    docker compose stop metabase
    docker compose exec -T lab python scripts/build_indicadores.py
    docker compose start metabase
"""

from __future__ import annotations

import os
from pathlib import Path

import duckdb

from run_exploration import cargar_consultas, tabla_markdown


ROOT = Path(__file__).resolve().parents[1]
SQL_PATH = ROOT / "sql" / "07_ejercicio_8.sql"
DB_PATH = ROOT / "data" / "processed" / "taxi.duckdb"
DOC_PATH = ROOT / "docs" / "ejercicio_8_resultados.md"
ANIOS = (2024, 2025, 2026)

CAMBIOS = """\
## 8.1 Cambios al sistema de descarga

El unico cambio necesario fue agregar 2025 a los anios predeterminados de
`scripts/download_data.py` (y su texto de ayuda):

```python
ANIOS_PREDETERMINADOS = (2024, 2025, 2026)
```

El descargador ya recibia una lista de anios, construia las rutas
`data/raw/<tipo>/<anio>/` y validaba cada archivo antes de omitirlo, por lo que no
hubo que modificar su logica. Tampoco cambio ninguna consulta de indicadores: el
modelo (`sql/05_modelo_indicadores.sql`) lee `data/raw/<tipo>/*/*.parquet` y todas
las consultas agrupan por `anio`.

## 8.2 Archivos existentes no se descargan de nuevo

La primera ejecucion (`docs/ejercicio_8_descarga.log`) termino con:

```text
descargados   : 24
ya existian   : 40
no publicados : 8
fallidos      : 0
```

Los 24 archivos son los doce meses de 2025 de cada tipo; los 40 existentes (2024 y
2026) se omitieron. Una segunda ejecucion (`docs/ejercicio_8_descarga_repetida.log`)
reporto `descargados: 0` y `ya existian: 64`.
"""

VERIFICACION = """\
## 8.3 Las consultas siguen funcionando

Ademas de las consultas anteriores, se volvieron a ejecutar sin modificaciones los
notebooks `01` a `07` y `scripts/build_indicadores.py` sobre el conjunto ampliado.
Todos terminaron sin errores. Las consultas de los ejercicios 3 y 4 leen
`data/raw/<tipo>/2026/*.parquet` a proposito, porque esos ejercicios analizaban 2026;
los indicadores del Ejercicio 7 incorporan 2025 automaticamente.

## 8.4 Indicadores y visualizaciones actualizados

La base `data/processed/taxi.duckdb` se reconstruyo con 121 millones de viajes y
`docs/ejercicio_7_indicadores.md`, `notebooks/07_indicadores.ipynb` y el tablero de
Metabase (`scripts/setup_metabase.py`) muestran ahora 2024, 2025 y 2026. Las
interpretaciones de `sql/06_indicadores.sql` se reescribieron con las cifras de los
tres anios.
"""

PATRONES = """\
## 8.6 Cambios y patrones visibles con 2024, 2025 y 2026

1. **El peaje de congestion aparece como un escalon en enero de 2025.** Ningun viaje
   lo paga en 2024; en enero de 2025 ya lo paga el 64.6 % de los viajes Yellow y desde
   febrero se estabiliza en 71-73 %, nivel que se mantiene en 2026 (71.8 % en
   enero-agosto). En Green alcanza solo 8-9 %. Con dos anios no se distinguia si el
   cambio fue gradual; con los tres se ve que fue inmediato y luego estable.
2. **Los registros de Yellow sin datos del taximetro se triplican.** Los viajes con
   codigo de pago 0 (sin RatecodeID ni pasajeros) pasan de 10.3 mil por dia en
   enero-agosto de 2024 (9.5 % del total) a 30.2 mil en 2025 (23.3 %) y 31.8 mil en 2026
   (26.0 %). Son viajes mas largos (distancia mediana de 2.4 a 2.9 millas) e incluyen
   los pedidos por plataforma, que `request_source` identifica desde junio de 2026.
   Este cambio de composicion es la clave para interpretar los demas indicadores.
3. **El maximo de 2025 no fue de taxis tradicionales.** El total de Yellow paso de 107
   mil viajes por dia (2024) a 129 mil (2025, +21 %) y 122 mil (2026), lo que con dos
   anios parecia un crecimiento sostenido. Pero los viajes con taximetro solo pasan de
   97.1 mil a 99.2 mil (+2 %) y caen a 90.5 mil en 2026 (-9 %): el crecimiento viene de
   los registros sin taximetro. Green cae todos los anios (1,810, 1,631 y 1,387 viajes
   por dia).
4. **El precio se mantiene y la velocidad cae en 2026.** La duracion y la tarifa
   medianas de todos los viajes Yellow suben cada anio (12.7, 13.1 y 14.1 min; USD
   13.50, 13.50 y 15.60), pero en buena parte por la mezcla de viajes. Comparando solo
   viajes con tarifa estandar, la tarifa mediana es USD 12.80 en los tres anios (USD
   7.42, 7.45 y 7.75 por milla) y la velocidad mediana es igual en 2024 y 2025 (9.2 mph)
   y baja a 8.7 mph en 2026 (-6 %). La desaceleracion real es de 2026, no gradual.
5. **La tarjeta gana frente al efectivo, pero se registra menos propina.** La caida del
   porcentaje de viajes pagados con tarjeta (75.7 % a 65.4 %) se debe a los registros con
   codigo 0. Entre los pagos conocidos, la tarjeta sube de 84.6 % a 87.3 % y 87.8 % frente
   al efectivo. En cambio, los pagos con tarjeta que registran propina bajan de 94.5 % a
   93.4 % y 91.1 %, sobre todo en viajes largos.

**Leccion metodologica:** con dos anios y metricas agregadas, tres de estos cambios se
habrian interpretado como cambios de comportamiento o de precio. Al agregar 2025 y
segmentar por tipo de registro y tipo de tarifa, se ve que en buena parte reflejan un
cambio en como se registran los viajes.
"""

DISENO = """\
## Por que no fue necesario cambiar el flujo de analisis

- Las rutas usan comodines (`data/raw/<tipo>/*/*.parquet`): un anio nuevo es solo
  una carpeta mas.
- El anio se obtiene del nombre del archivo y todas las metricas agrupan por `anio`.
- `union_by_name` tolera columnas nuevas, como `cbd_congestion_fee` (2025) y
  `request_source` (2026).
- La documentacion y los tableros se generan desde los mismos archivos SQL, de modo
  que reflejan los datos nuevos al volver a ejecutarlos.
"""


def main() -> int:
    os.chdir(ROOT)
    faltantes = [a for a in ANIOS if not list((ROOT / "data/raw").glob(f"*/{a}/*.parquet"))]
    if faltantes:
        raise SystemExit(f"Faltan Parquet de {faltantes}. Ejecute scripts/download_data.py.")
    if not DB_PATH.exists():
        raise SystemExit("Falta data/processed/taxi.duckdb. Ejecute scripts/build_indicadores.py.")

    # Limite de memoria: varias medianas exactas sobre ~90 M filas agotan el
    # contenedor; con el limite DuckDB usa disco temporal.
    conexion = duckdb.connect(config={"memory_limit": "3GB"})
    conexion.execute(f"ATTACH '{DB_PATH.relative_to(ROOT).as_posix()}' AS taxi (READ_ONLY)")

    partes = [
        "# Ejercicio 8 - Incorporacion de 2025 y analisis 2024-2026", "",
        "Documento generado por `scripts/run_ejercicio_8.py`. Las consultas estan en",
        "`sql/07_ejercicio_8.sql` y el recorrido paso a paso en",
        "`notebooks/08_incorporacion_2025.ipynb`.", "",
        CAMBIOS, VERIFICACION,
        "## 8.7 Consultas de validacion y analisis", "",
    ]
    for consulta in cargar_consultas(SQL_PATH):
        print(f"Ejecutando {consulta.nombre}...", flush=True)
        cursor = conexion.execute(consulta.sql)
        columnas = [item[0] for item in cursor.description]
        meta = consulta.metadatos
        partes.extend([
            f"### {meta.get('title', consulta.nombre)}", "",
            f"**Objetivo:** {meta.get('objective', '')}", "",
            f"**Fuente:** {meta.get('source', '')}", "",
            "```sql", consulta.sql, "```", "",
            tabla_markdown(columnas, cursor.fetchall()), "",
            f"**Decision:** {meta.get('decision', '')}", "",
        ])
    conexion.close()
    partes.extend([PATRONES, DISENO])

    DOC_PATH.write_text("\n".join(partes), encoding="utf-8")
    print(f"Documento: {DOC_PATH.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
