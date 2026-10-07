-- Consultas del Ejercicio 8: incorporacion de 2025 y analisis de 2024-2026.
-- scripts/run_ejercicio_8.py las ejecuta en una conexion en memoria que lee los
-- Parquet directamente y adjunta data/processed/taxi.duckdb como `taxi`.

-- name: 01_cobertura
-- title: Cobertura de archivos por anio y tipo
-- objective: Verificar que existen los doce meses de 2024 y 2025 y los meses publicados de 2026 para ambos servicios (8.1, 8.2).
-- source: glob sobre data/raw/*/*/*.parquet
-- decision: Se esperan 12, 12 y 8 archivos por tipo; septiembre a diciembre de 2026 aun no estaban publicados.
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

-- name: 02_parquet_vs_tabla
-- title: Registros en Parquet y en la tabla materializada
-- objective: Comprobar que la consulta directa sobre los tres anios funciona y que la tabla `viajes` contiene exactamente los mismos registros (8.3).
-- source: data/raw/*/*/*.parquet y taxi.viajes
-- decision: Una diferencia distinta de cero indicaria que la base de indicadores no se reconstruyo despues de descargar 2025.
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

-- name: 03_cambios_esquema
-- title: Columnas que no estan presentes en todos los anios
-- objective: Identificar cambios de esquema entre anios que podrian romper consultas que asumen columnas fijas (8.3).
-- source: parquet_schema sobre data/raw/*/*/*.parquet
-- decision: Las consultas usan union_by_name, que completa con NULL las columnas ausentes; por eso estos cambios no rompen el flujo, pero hay que tenerlos en cuenta al interpretar.
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

-- name: 04_comparacion_enero_agosto
-- title: Evolucion anual en un periodo comparable (enero a agosto)
-- objective: Comparar los tres anios con los mismos meses, porque 2026 solo tiene enero a agosto (8.5).
-- source: taxi.viajes y taxi.viajes_validos
-- decision: Comparar anios completos contra un anio parcial exageraria la caida de 2026; por eso se restringe a enero-agosto.
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

-- name: 05_control_composicion
-- title: Control por composicion (Yellow, enero a agosto)
-- objective: Separar los cambios reales de comportamiento y precio del efecto de que cada anio haya mas registros sin datos del taximetro (codigo de pago 0, sin RatecodeID), que son viajes mas largos e incluyen los pedidos por plataforma (8.5, 8.6).
-- source: taxi.viajes_validos
-- decision: Las metricas de precio y velocidad se comparan solo en viajes con tarifa estandar (RatecodeID = 1); la preferencia de pago se mide solo entre tarjeta y efectivo.
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

-- name: 06_demanda_por_tipo_registro
-- title: Demanda Yellow segun tipo de registro (enero a agosto)
-- objective: Comprobar si el crecimiento de la demanda de 2025 proviene de viajes con taximetro o de registros sin datos del taximetro (codigo de pago 0) (8.6).
-- source: taxi.viajes
-- decision: Si el crecimiento se concentra en los registros sin taximetro, el aumento de demanda refleja en buena parte un canal de solicitud nuevo y no mas viajes de taxi tradicionales.
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
