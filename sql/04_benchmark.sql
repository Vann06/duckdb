-- Plantillas de consultas equivalentes para el benchmark del Ejercicio 6.
-- scripts/run_benchmark.py reemplaza {source} por la lectura normalizada de
-- Parquet o por la tabla `viajes`, y {year_filter} por el escenario medido.

-- name: 01_resumen_mensual
-- title: Resumen mensual
-- objective: Medir una agregacion temporal con conteo, promedio y suma.
SELECT anio, month(pickup_datetime) AS mes, tipo_taxi, count(*) AS viajes,
       avg(trip_distance) AS distancia_media, sum(total_amount) AS monto_total
FROM {source}
WHERE {year_filter}
GROUP BY anio, mes, tipo_taxi
ORDER BY anio, mes, tipo_taxi;

-- name: 02_distribucion_pago
-- title: Distribucion de pagos
-- objective: Medir una agrupacion de baja cardinalidad sobre varias columnas.
SELECT anio, tipo_taxi, payment_type, count(*) AS viajes,
       avg(fare_amount) AS tarifa_media, avg(tip_amount) AS propina_media
FROM {source}
WHERE {year_filter}
GROUP BY anio, tipo_taxi, payment_type
ORDER BY anio, tipo_taxi, viajes DESC;

-- name: 03_rutas_principales
-- title: Rutas principales
-- objective: Medir una agrupacion de mayor cardinalidad y un ranking por ventana.
WITH rutas AS (
    SELECT anio, tipo_taxi, pickup_location_id, dropoff_location_id, count(*) AS viajes
    FROM {source}
    WHERE {year_filter}
    GROUP BY ALL
)
SELECT * FROM rutas
QUALIFY row_number() OVER (PARTITION BY anio, tipo_taxi ORDER BY viajes DESC) <= 20
ORDER BY anio, tipo_taxi, viajes DESC;
