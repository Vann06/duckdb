# Ejercicio 8 - Incorporacion de 2025 y analisis 2024-2026

Documento generado por `scripts/run_ejercicio_8.py`. Las consultas estan en
`sql/07_ejercicio_8.sql` y el recorrido paso a paso en
`notebooks/08_incorporacion_2025.ipynb`.

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

## 8.7 Consultas de validacion y analisis

### Cobertura de archivos por anio y tipo

**Objetivo:** Verificar que existen los doce meses de 2024 y 2025 y los meses publicados de 2026 para ambos servicios (8.1, 8.2).

**Fuente:** glob sobre data/raw/*/*/*.parquet

```sql
WITH archivos AS (
    SELECT regexp_extract(file, '(yellow|green)', 1) AS tipo_taxi,
           CAST(regexp_extract(file, 'tripdata_(\d{4})-', 1) AS INTEGER) AS anio,
           CAST(regexp_extract(file, '-(\d{2})\.parquet$', 1) AS INTEGER) AS mes
    FROM glob('data/raw/*/*/*.parquet')
)
SELECT anio, tipo_taxi, count(*) AS archivos, min(mes) AS primer_mes, max(mes) AS ultimo_mes
FROM archivos
GROUP BY ALL
ORDER BY anio, tipo_taxi;
```

| anio | tipo_taxi | archivos | primer_mes | ultimo_mes |
| --- | --- | --- | --- | --- |
| 2024 | green | 12 | 1 | 12 |
| 2024 | yellow | 12 | 1 | 12 |
| 2025 | green | 12 | 1 | 12 |
| 2025 | yellow | 12 | 1 | 12 |
| 2026 | green | 8 | 1 | 8 |
| 2026 | yellow | 8 | 1 | 8 |

**Decision:** Se esperan 12, 12 y 8 archivos por tipo; septiembre a diciembre de 2026 aun no estaban publicados.

### Registros en Parquet y en la tabla materializada

**Objetivo:** Comprobar que la consulta directa sobre los tres anios funciona y que la tabla `viajes` contiene exactamente los mismos registros (8.3).

**Fuente:** data/raw/*/*/*.parquet y taxi.viajes

```sql
WITH parquet AS (
    SELECT CAST(regexp_extract(filename, 'tripdata_(\d{4})-', 1) AS INTEGER) AS anio,
           CASE WHEN filename LIKE '%yellow%' THEN 'yellow' ELSE 'green' END AS tipo_taxi,
           count(*) AS registros_parquet
    FROM read_parquet('data/raw/*/*/*.parquet', filename = true, union_by_name = true)
    GROUP BY ALL
), tabla AS (
    SELECT anio, tipo_taxi, count(*) AS registros_tabla
    FROM taxi.viajes
    GROUP BY ALL
)
SELECT anio, tipo_taxi, registros_parquet, registros_tabla,
       registros_parquet - registros_tabla AS diferencia
FROM parquet FULL JOIN tabla USING (anio, tipo_taxi)
ORDER BY anio, tipo_taxi;
```

| anio | tipo_taxi | registros_parquet | registros_tabla | diferencia |
| --- | --- | --- | --- | --- |
| 2024 | green | 660218 | 660218 | 0 |
| 2024 | yellow | 41169720 | 41169720 | 0 |
| 2025 | green | 591375 | 591375 | 0 |
| 2025 | yellow | 48722602 | 48722602 | 0 |
| 2026 | green | 337114 | 337114 | 0 |
| 2026 | yellow | 29703355 | 29703355 | 0 |

**Decision:** Una diferencia distinta de cero indicaria que la base de indicadores no se reconstruyo despues de descargar 2025.

### Columnas que no estan presentes en todos los anios

**Objetivo:** Identificar cambios de esquema entre anios que podrian romper consultas que asumen columnas fijas (8.3).

**Fuente:** parquet_schema sobre data/raw/*/*/*.parquet

```sql
WITH columnas AS (
    SELECT regexp_extract(file_name, '(yellow|green)', 1) AS tipo_taxi,
           regexp_extract(file_name, 'tripdata_(\d{4}-\d{2})', 1) AS periodo,
           name AS columna
    FROM parquet_schema('data/raw/*/*/*.parquet')
    WHERE name <> 'schema'
), totales AS (
    SELECT tipo_taxi, count(DISTINCT periodo) AS archivos_tipo FROM columnas GROUP BY tipo_taxi
)
SELECT c.tipo_taxi, c.columna,
       count(DISTINCT c.periodo) AS archivos_con_columna,
       t.archivos_tipo,
       min(c.periodo) AS desde,
       max(c.periodo) AS hasta
FROM columnas AS c
JOIN totales AS t USING (tipo_taxi)
GROUP BY c.tipo_taxi, c.columna, t.archivos_tipo
HAVING count(DISTINCT c.periodo) < t.archivos_tipo
ORDER BY c.tipo_taxi, desde, c.columna;
```

| tipo_taxi | columna | archivos_con_columna | archivos_tipo | desde | hasta |
| --- | --- | --- | --- | --- | --- |
| green | cbd_congestion_fee | 20 | 32 | 2025-01 | 2026-08 |
| green | request_source | 3 | 32 | 2026-06 | 2026-08 |
| yellow | cbd_congestion_fee | 20 | 32 | 2025-01 | 2026-08 |
| yellow | request_source | 3 | 32 | 2026-06 | 2026-08 |

**Decision:** Las consultas usan union_by_name, que completa con NULL las columnas ausentes; por eso estos cambios no rompen el flujo, pero hay que tenerlos en cuenta al interpretar.

### Evolucion anual en un periodo comparable (enero a agosto)

**Objetivo:** Comparar los tres anios con los mismos meses, porque 2026 solo tiene enero a agosto (8.5).

**Fuente:** taxi.viajes y taxi.viajes_validos

```sql
WITH base AS (
    SELECT anio, tipo_taxi,
           count(*) / count(DISTINCT CAST(pickup_datetime AS DATE)) AS viajes_por_dia,
           round(100.0 * avg(CASE WHEN cbd_congestion_fee > 0 THEN 1 ELSE 0 END), 2) AS pct_con_peaje
    FROM taxi.viajes
    WHERE mes <= 8 AND year(pickup_datetime) = anio
    GROUP BY ALL
), validos AS (
    SELECT anio, tipo_taxi,
           round(median(duracion_min), 2) AS duracion_mediana_min,
           round(median(trip_distance), 2) AS distancia_mediana,
           round(median(fare_amount), 2) AS tarifa_base_mediana,
           round(100.0 * avg(CASE WHEN payment_type = 1 THEN 1 ELSE 0 END), 2) AS pct_tarjeta,
           round(100.0 * avg(CASE WHEN tip_amount > 0 THEN 1 ELSE 0 END)
                 FILTER (WHERE payment_type = 1), 2) AS pct_tarjeta_con_propina
    FROM taxi.viajes_validos
    WHERE mes <= 8
    GROUP BY ALL
)
SELECT anio, tipo_taxi, round(viajes_por_dia, 0) AS viajes_por_dia,
       duracion_mediana_min, distancia_mediana, tarifa_base_mediana,
       pct_tarjeta, pct_tarjeta_con_propina, pct_con_peaje
FROM base JOIN validos USING (anio, tipo_taxi)
ORDER BY tipo_taxi DESC, anio;
```

| anio | tipo_taxi | viajes_por_dia | duracion_mediana_min | distancia_mediana | tarifa_base_mediana | pct_tarjeta | pct_tarjeta_con_propina | pct_con_peaje |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2024 | yellow | 107269 | 12.7 | 1.8 | 13.5 | 75.7 | 94.45 | 0 |
| 2025 | yellow | 129330 | 13.12 | 1.9 | 13.5 | 66.16 | 93.39 | 71.43 |
| 2026 | yellow | 122236 | 14.1 | 1.93 | 15.6 | 65.36 | 91.13 | 71.76 |
| 2024 | green | 1810 | 11.85 | 1.96 | 13.5 | 67.73 | 91.24 | 0 |
| 2025 | green | 1631 | 12.37 | 2.02 | 13.5 | 69.51 | 91.14 | 9.3 |
| 2026 | green | 1387 | 13.32 | 2.15 | 13.5 | 65.51 | 91.39 | 8.32 |

**Decision:** Comparar anios completos contra un anio parcial exageraria la caida de 2026; por eso se restringe a enero-agosto.

### Control por composicion (Yellow, enero a agosto)

**Objetivo:** Separar los cambios reales de comportamiento y precio del efecto de que cada anio haya mas registros sin datos del taximetro (codigo de pago 0, sin RatecodeID), que son viajes mas largos e incluyen los pedidos por plataforma (8.5, 8.6).

**Fuente:** taxi.viajes_validos

```sql
WITH base AS (
    SELECT * FROM taxi.viajes_validos
    WHERE tipo_taxi = 'yellow' AND mes <= 8
), composicion AS (
    SELECT anio,
           round(100.0 * avg(CASE WHEN payment_type = 0 THEN 1 ELSE 0 END), 2) AS pct_sin_taximetro,
           round(median(trip_distance) FILTER (WHERE payment_type = 0), 2) AS distancia_mediana_sin_taximetro,
           round(100.0 * count(*) FILTER (WHERE payment_type = 1)
                 / count(*) FILTER (WHERE payment_type IN (1, 2)), 2) AS pct_tarjeta_vs_efectivo
    FROM base
    GROUP BY anio
), estandar AS (
    SELECT anio,
           round(median(fare_amount), 2) AS tarifa_mediana_estandar,
           round(median(fare_amount / trip_distance), 2) AS usd_por_milla_estandar,
           round(median(trip_distance), 2) AS distancia_mediana_estandar,
           round(median(duracion_min), 2) AS duracion_mediana_estandar,
           round(median(trip_distance / (duracion_min / 60)), 2) AS mph_mediana_estandar
    FROM base
    WHERE ratecode_id = 1 AND fare_amount > 0
    GROUP BY anio
)
SELECT *
FROM composicion JOIN estandar USING (anio)
ORDER BY anio;
```

| anio | pct_sin_taximetro | distancia_mediana_sin_taximetro | pct_tarjeta_vs_efectivo | tarifa_mediana_estandar | usd_por_milla_estandar | distancia_mediana_estandar | duracion_mediana_estandar | mph_mediana_estandar |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2024 | 9.25 | 2.41 | 84.63 | 12.8 | 7.42 | 1.65 | 11.85 | 9.23 |
| 2025 | 22.6 | 2.69 | 87.29 | 12.8 | 7.45 | 1.61 | 11.67 | 9.18 |
| 2026 | 24.95 | 2.9 | 87.82 | 12.8 | 7.75 | 1.59 | 12.18 | 8.66 |

**Decision:** Las metricas de precio y velocidad se comparan solo en viajes con tarifa estandar (RatecodeID = 1); la preferencia de pago se mide solo entre tarjeta y efectivo.

### Demanda Yellow segun tipo de registro (enero a agosto)

**Objetivo:** Comprobar si el crecimiento de la demanda de 2025 proviene de viajes con taximetro o de registros sin datos del taximetro (codigo de pago 0) (8.6).

**Fuente:** taxi.viajes

```sql
WITH diario AS (
    SELECT anio,
           CASE WHEN payment_type = 0 THEN 'sin taximetro (codigo 0)' ELSE 'con taximetro' END AS tipo_registro,
           count(*) AS viajes,
           count(DISTINCT CAST(pickup_datetime AS DATE)) AS dias
    FROM taxi.viajes
    WHERE tipo_taxi = 'yellow' AND mes <= 8 AND year(pickup_datetime) = anio
    GROUP BY ALL
)
SELECT anio, tipo_registro, round(viajes / dias, 0) AS viajes_por_dia,
       round(100.0 * viajes / sum(viajes) OVER (PARTITION BY anio), 2) AS pct_del_anio
FROM diario
ORDER BY tipo_registro, anio;
```

| anio | tipo_registro | viajes_por_dia | pct_del_anio |
| --- | --- | --- | --- |
| 2024 | con taximetro | 97051 | 90.47 |
| 2025 | con taximetro | 99233 | 76.73 |
| 2026 | con taximetro | 90480 | 74.02 |
| 2024 | sin taximetro (codigo 0) | 10302 | 9.53 |
| 2025 | sin taximetro (codigo 0) | 30221 | 23.27 |
| 2026 | sin taximetro (codigo 0) | 31756 | 25.98 |

**Decision:** Si el crecimiento se concentra en los registros sin taximetro, el aumento de demanda refleja en buena parte un canal de solicitud nuevo y no mas viajes de taxi tradicionales.

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

## Por que no fue necesario cambiar el flujo de analisis

- Las rutas usan comodines (`data/raw/<tipo>/*/*.parquet`): un anio nuevo es solo
  una carpeta mas.
- El anio se obtiene del nombre del archivo y todas las metricas agrupan por `anio`.
- `union_by_name` tolera columnas nuevas, como `cbd_congestion_fee` (2025) y
  `request_source` (2026).
- La documentacion y los tableros se generan desde los mismos archivos SQL, de modo
  que reflejan los datos nuevos al volver a ejecutarlos.
