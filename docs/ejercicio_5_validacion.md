# Ejercicio 5 - Incorporacion incremental de 2024

Documento generado por `scripts/validate_incremental.py`.

## Cobertura de archivos incorporados

**Objetivo:** Verificar cuantos meses locales existen para cada anio y tipo de taxi.

```sql
WITH archivos AS (
    SELECT file,
           regexp_extract(file, '(yellow|green)', 1) AS tipo_taxi,
           CAST(regexp_extract(file, 'tripdata_(\d{4})-', 1) AS INTEGER) AS anio,
           CAST(regexp_extract(file, '-(\d{2})\.parquet$', 1) AS INTEGER) AS mes
    FROM glob('data/raw/*/*/*.parquet')
)
SELECT anio, tipo_taxi, count(*) AS archivos, min(mes) AS primer_mes,
       max(mes) AS ultimo_mes, count(DISTINCT mes) AS meses_distintos
FROM archivos
WHERE anio IN (2024, 2026)
GROUP BY anio, tipo_taxi ORDER BY anio, tipo_taxi;
```

| anio | tipo_taxi | archivos | primer_mes | ultimo_mes | meses_distintos |
| --- | --- | --- | --- | --- | --- |
| 2024 | green | 12 | 1 | 12 | 12 |
| 2024 | yellow | 12 | 1 | 12 | 12 |
| 2026 | green | 8 | 1 | 8 | 8 |
| 2026 | yellow | 8 | 1 | 8 | 8 |

**Decision:** Para 2024 se esperan doce meses por tipo; para 2026 solo los meses ya publicados por TLC.

## Registros consultados conjuntamente

**Objetivo:** Comprobar con DuckDB que 2024 y 2026 se leen en una sola consulta.

```sql
WITH viajes AS (
    SELECT CAST(regexp_extract(filename, 'tripdata_(\d{4})-', 1) AS INTEGER) AS anio,
           CASE WHEN filename LIKE '%yellow%' THEN 'yellow' ELSE 'green' END AS tipo_taxi
    FROM read_parquet('data/raw/*/*/*.parquet', filename = true, union_by_name = true)
)
SELECT anio, tipo_taxi, count(*) AS registros
FROM viajes WHERE anio IN (2024, 2026)
GROUP BY anio, tipo_taxi
UNION ALL
SELECT anio, 'total', count(*) FROM viajes WHERE anio IN (2024, 2026) GROUP BY anio
ORDER BY anio, tipo_taxi;
```

| anio | tipo_taxi | registros |
| --- | --- | --- |
| 2024 | green | 660218 |
| 2024 | total | 41829938 |
| 2024 | yellow | 41169720 |
| 2026 | green | 337114 |
| 2026 | total | 30040469 |
| 2026 | yellow | 29703355 |

**Decision:** Extraer el anio desde el nombre del archivo evita confiar en fechas atipicas dentro de un archivo mensual.

## Consulta analitica sobre ambos anios

**Objetivo:** Demostrar que las metricas normalizadas funcionan al ampliar el conjunto de archivos.

```sql
WITH viajes AS (
    SELECT CAST(regexp_extract(filename, 'tripdata_(\d{4})-', 1) AS INTEGER) AS anio,
           CASE WHEN filename LIKE '%yellow%' THEN 'yellow' ELSE 'green' END AS tipo_taxi,
           coalesce(tpep_pickup_datetime, lpep_pickup_datetime) AS pickup_datetime,
           trip_distance, total_amount
    FROM read_parquet('data/raw/*/*/*.parquet', filename = true, union_by_name = true)
)
SELECT anio, tipo_taxi, count(*) AS viajes,
       round(avg(trip_distance) FILTER (WHERE trip_distance > 0), 2) AS distancia_media,
       round(avg(total_amount) FILTER (WHERE total_amount >= 0), 2) AS monto_medio
FROM viajes
WHERE anio IN (2024, 2026)
  AND year(pickup_datetime) = anio
GROUP BY anio, tipo_taxi ORDER BY anio, tipo_taxi;
```

| anio | tipo_taxi | viajes | distancia_media | monto_medio |
| --- | --- | --- | --- | --- |
| 2024 | green | 660198 | 17.96 | 24.39 |
| 2024 | yellow | 41169664 | 5.07 | 28.67 |
| 2026 | green | 337100 | 13.85 | 25.61 |
| 2026 | yellow | 29703338 | 5.74 | 30.4 |

**Decision:** Mantener union_by_name y normalizar las fechas con coalesce permite tolerar las diferencias de esquema entre servicios y anios.

## Cambios necesarios en las consultas anteriores

Las preguntas del Ejercicio 4 siguen siendo validas. Para analizarlas sobre ambos
anios se reemplaza el patron `data/raw/<tipo>/2026/*.parquet` por
`data/raw/<tipo>/*/*.parquet`, se agrega `anio` desde `filename` y se sustituye el
filtro fijo de 2026 por el rango o agrupacion anual requerido. No cambian las
formulas ni la normalizacion entre `tpep_*` y `lpep_*`.

## Por que el flujo es incremental

El descargador recibe una lista de anios, construye rutas particionadas por tipo/anio
y valida cada archivo antes de decidir si lo omite. Las consultas usan patrones de
archivos y `union_by_name`; por ello un archivo mensual nuevo entra en el siguiente
analisis sin importacion manual ni cambios en una lista de nombres.
