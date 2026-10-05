-- Consultas de validacion para el Ejercicio 5.

-- name: 01_archivos_por_anio_tipo
-- title: Cobertura de archivos incorporados
-- objective: Verificar cuantos meses locales existen para cada anio y tipo de taxi.
-- decision: Para 2024 se esperan doce meses por tipo; para 2026 solo los meses ya publicados por TLC.
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

-- name: 02_registros_conjuntos
-- title: Registros consultados conjuntamente
-- objective: Comprobar con DuckDB que 2024 y 2026 se leen en una sola consulta.
-- decision: Extraer el anio desde el nombre del archivo evita confiar en fechas atipicas dentro de un archivo mensual.
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

-- name: 03_comparacion_anual
-- title: Consulta analitica sobre ambos anios
-- objective: Demostrar que las metricas normalizadas funcionan al ampliar el conjunto de archivos.
-- decision: Mantener union_by_name y normalizar las fechas con coalesce permite tolerar las diferencias de esquema entre servicios y anios.
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
