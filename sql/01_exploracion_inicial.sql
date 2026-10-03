-- name: 01_cantidad_archivos
-- title: Cantidad de archivos disponibles
-- objective: Verificar cuantos archivos Parquet de 2026 existen para cada tipo de taxi.
-- source: data/raw/yellow/2026/*.parquet y data/raw/green/2026/*.parquet
-- decision: Comparar el conteo local con los meses publicados por la TLC; un mes aun no publicado no se considera faltante.
WITH archivos AS (
    SELECT
        file,
        CASE
            WHEN file LIKE '%/yellow/%' THEN 'yellow'
            WHEN file LIKE '%/green/%' THEN 'green'
            ELSE 'desconocido'
        END AS tipo_taxi,
        regexp_extract(file, '2026-(\d{2})\.parquet$', 1) AS mes
    FROM glob('data/raw/*/2026/*.parquet')
)
SELECT
    tipo_taxi,
    count(*) AS cantidad_archivos,
    min(mes) AS primer_mes,
    max(mes) AS ultimo_mes
FROM archivos
GROUP BY tipo_taxi
UNION ALL
SELECT
    'total' AS tipo_taxi,
    count(*) AS cantidad_archivos,
    min(mes) AS primer_mes,
    max(mes) AS ultimo_mes
FROM archivos
ORDER BY tipo_taxi;

-- name: 02_cantidad_registros
-- title: Cantidad de registros disponibles
-- objective: Contar los viajes disponibles por tipo de taxi y en total.
-- source: Todos los archivos Parquet de taxis amarillos y verdes de 2026.
-- decision: Usar union_by_name porque los dos tipos de taxi no poseen exactamente el mismo esquema.
WITH viajes AS (
    SELECT
        CASE
            WHEN filename LIKE '%yellow%' THEN 'yellow'
            WHEN filename LIKE '%green%' THEN 'green'
            ELSE 'desconocido'
        END AS tipo_taxi
    FROM read_parquet(
        'data/raw/*/2026/*.parquet',
        filename = true,
        union_by_name = true
    )
)
SELECT
    coalesce(tipo_taxi, 'total') AS tipo_taxi,
    count(*) AS cantidad_registros
FROM viajes
GROUP BY GROUPING SETS ((tipo_taxi), ());

-- name: 03_registros_por_archivo
-- title: Registros por archivo mensual
-- objective: Confirmar que cada archivo puede leerse y conocer su aporte al total.
-- source: Todos los archivos Parquet de taxis amarillos y verdes de 2026.
-- decision: Mantener el nombre del archivo en los resultados para facilitar la deteccion de meses vacios o atipicos.
SELECT
    CASE
        WHEN filename LIKE '%yellow%' THEN 'yellow'
        WHEN filename LIKE '%green%' THEN 'green'
        ELSE 'desconocido'
    END AS tipo_taxi,
    regexp_extract(filename, '([^/]+)\.parquet$', 1) || '.parquet' AS archivo,
    count(*) AS cantidad_registros
FROM read_parquet(
    'data/raw/*/2026/*.parquet',
    filename = true,
    union_by_name = true
)
GROUP BY tipo_taxi, archivo
ORDER BY tipo_taxi, archivo;

-- name: 04_esquema_yellow
-- title: Columnas y tipos de datos de Yellow Taxi
-- objective: Identificar el esquema inferido por DuckDB para los archivos de taxis amarillos.
-- source: data/raw/yellow/2026/*.parquet
-- decision: Conservar los nombres originales y normalizar solamente en consultas que combinen tipos de taxi.
DESCRIBE
SELECT *
FROM read_parquet(
    'data/raw/yellow/2026/*.parquet',
    union_by_name = true
);

-- name: 05_esquema_green
-- title: Columnas y tipos de datos de Green Taxi
-- objective: Identificar el esquema inferido por DuckDB para los archivos de taxis verdes.
-- source: data/raw/green/2026/*.parquet
-- decision: Usar lpep_pickup_datetime y lpep_dropoff_datetime para Green Taxi, en lugar de asumir los nombres de Yellow Taxi.
DESCRIBE
SELECT *
FROM read_parquet(
    'data/raw/green/2026/*.parquet',
    union_by_name = true
);

-- name: 06_muestra_registros
-- title: Muestra de registros
-- objective: Observar valores representativos de ambos tipos de taxi con columnas comparables.
-- source: Todos los archivos Parquet de taxis amarillos y verdes de 2026.
-- decision: Unificar los nombres de las fechas solo en la salida analitica y conservar los archivos originales sin modificaciones.
WITH muestra AS (
    SELECT
        'yellow' AS tipo_taxi,
        tpep_pickup_datetime AS pickup_datetime,
        tpep_dropoff_datetime AS dropoff_datetime,
        passenger_count,
        trip_distance,
        fare_amount,
        total_amount,
        payment_type
    FROM read_parquet('data/raw/yellow/2026/*.parquet', union_by_name = true)

    UNION ALL

    SELECT
        'green' AS tipo_taxi,
        lpep_pickup_datetime AS pickup_datetime,
        lpep_dropoff_datetime AS dropoff_datetime,
        passenger_count,
        trip_distance,
        fare_amount,
        total_amount,
        payment_type
    FROM read_parquet('data/raw/green/2026/*.parquet', union_by_name = true)
)
SELECT *
FROM muestra
WHERE pickup_datetime >= TIMESTAMP '2026-01-01'
  AND pickup_datetime < TIMESTAMP '2027-01-01'
QUALIFY row_number() OVER (
    PARTITION BY tipo_taxi
    ORDER BY pickup_datetime, dropoff_datetime
) <= 5
ORDER BY tipo_taxi, pickup_datetime;

-- name: 07_calidad_datos
-- title: Revision inicial de calidad de datos
-- objective: Cuantificar valores nulos, fechas inconsistentes y valores no plausibles antes del analisis exploratorio.
-- source: Todos los archivos Parquet de taxis amarillos y verdes de 2026.
-- decision: No eliminar automaticamente registros; documentar los problemas y aplicar filtros explicitos segun la pregunta analitica.
WITH viajes AS (
    SELECT
        CASE
            WHEN filename LIKE '%yellow%' THEN 'yellow'
            WHEN filename LIKE '%green%' THEN 'green'
            ELSE 'desconocido'
        END AS tipo_taxi,
        coalesce(tpep_pickup_datetime, lpep_pickup_datetime) AS pickup_datetime,
        coalesce(tpep_dropoff_datetime, lpep_dropoff_datetime) AS dropoff_datetime,
        passenger_count,
        trip_distance,
        fare_amount,
        total_amount
    FROM read_parquet(
        'data/raw/*/2026/*.parquet',
        filename = true,
        union_by_name = true
    )
)
SELECT
    tipo_taxi,
    count(*) AS registros,
    count_if(pickup_datetime IS NULL) AS pickup_nulo,
    count_if(dropoff_datetime IS NULL) AS dropoff_nulo,
    count_if(
        pickup_datetime < TIMESTAMP '2026-01-01'
        OR pickup_datetime >= TIMESTAMP '2027-01-01'
    ) AS pickup_fuera_2026,
    count_if(dropoff_datetime < pickup_datetime) AS duracion_negativa,
    count_if(passenger_count IS NULL) AS pasajeros_nulos,
    count_if(passenger_count <= 0) AS pasajeros_no_positivos,
    count_if(trip_distance IS NULL) AS distancia_nula,
    count_if(trip_distance <= 0) AS distancia_no_positiva,
    count_if(fare_amount < 0) AS tarifa_negativa,
    count_if(total_amount < 0) AS total_negativo
FROM viajes
GROUP BY tipo_taxi
ORDER BY tipo_taxi;
