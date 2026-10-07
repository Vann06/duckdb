-- Modelo de datos del Ejercicio 7.
-- scripts/build_indicadores.py ejecuta estos bloques en orden sobre
-- data/processed/taxi.duckdb. Metabase y el notebook 07 leen esa base.
-- Se materializa (en lugar de consultar Parquet) porque el tablero repite las
-- mismas consultas cada vez que se abre: es el escenario en el que el
-- Ejercicio 6 mostro que conviene una tabla DuckDB.

-- name: 01_tabla_viajes
-- title: Tabla viajes (Yellow y Green normalizados)
-- objective: Unificar todos los anios descargados de ambos servicios con nombres de columna comunes.
-- decision: El anio y mes se toman del nombre del archivo; los registros originales no se filtran aqui.
CREATE OR REPLACE TABLE viajes AS
WITH crudo AS (
    SELECT filename, 'yellow' AS tipo_taxi,
           tpep_pickup_datetime AS pickup_datetime, tpep_dropoff_datetime AS dropoff_datetime,
           passenger_count, trip_distance, RatecodeID, payment_type, fare_amount, tip_amount,
           total_amount, cbd_congestion_fee, request_source, PULocationID, DOLocationID
    FROM read_parquet('data/raw/yellow/*/*.parquet', filename = true, union_by_name = true)
    UNION ALL
    SELECT filename, 'green',
           lpep_pickup_datetime, lpep_dropoff_datetime,
           passenger_count, trip_distance, RatecodeID, payment_type, fare_amount, tip_amount,
           total_amount, cbd_congestion_fee, request_source, PULocationID, DOLocationID
    FROM read_parquet('data/raw/green/*/*.parquet', filename = true, union_by_name = true)
)
SELECT
    CAST(regexp_extract(filename, 'tripdata_(\d{4})-', 1) AS INTEGER) AS anio,
    CAST(regexp_extract(filename, '-(\d{2})\.parquet$', 1) AS INTEGER) AS mes,
    tipo_taxi,
    pickup_datetime,
    dropoff_datetime,
    date_diff('second', pickup_datetime, dropoff_datetime) / 60.0 AS duracion_min,
    passenger_count,
    trip_distance,
    RatecodeID AS ratecode_id,
    payment_type,
    fare_amount,
    tip_amount,
    total_amount,
    coalesce(cbd_congestion_fee, 0) AS cbd_congestion_fee,
    request_source,
    PULocationID AS origen_id,
    DOLocationID AS destino_id
FROM crudo;

-- name: 02_tabla_zonas
-- title: Tabla zonas (TLC Taxi Zone Lookup)
-- objective: Traducir los identificadores de zona a barrio y nombre legible.
-- decision: Se carga desde data/raw/zones/taxi_zone_lookup.csv, descargado por scripts/download_data.py.
CREATE OR REPLACE TABLE zonas AS
SELECT LocationID AS zona_id, Borough AS barrio, Zone AS zona, service_zone
FROM read_csv('data/raw/zones/taxi_zone_lookup.csv', header = true);

-- name: 03_vista_viajes_validos
-- title: Vista viajes_validos
-- objective: Centralizar el criterio de viaje plausible usado por los indicadores.
-- decision: Mismo criterio que el Ejercicio 4 (fecha dentro del anio del archivo, distancia positiva, total no negativo) mas duracion entre 0 y 6 horas, umbral que el Ejercicio 4 marco como atipico.
CREATE OR REPLACE VIEW viajes_validos AS
SELECT *
FROM viajes
WHERE year(pickup_datetime) = anio
  AND duracion_min > 0 AND duracion_min <= 360
  AND trip_distance > 0
  AND total_amount >= 0;
