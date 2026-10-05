-- Las consultas de este archivo corresponden al Ejercicio 4 y usan 2026,
-- que era el conjunto disponible antes de la incorporacion incremental.

-- name: 01_evolucion_mensual
-- title: Evolucion mensual de la demanda
-- question: Como cambia la cantidad de viajes y la facturacion mensual por tipo de taxi?
-- justification: Permite detectar estacionalidad y comprobar si los dos servicios evolucionan de forma similar.
-- source: Archivos Parquet Yellow y Green Taxi de 2026.
-- interpretation: Los meses deben compararse tambien por promedio diario porque agosto es el ultimo mes disponible al ejecutar este analisis.
WITH viajes AS (
    SELECT 'yellow' AS tipo_taxi, tpep_pickup_datetime AS pickup_datetime, total_amount
    FROM read_parquet('data/raw/yellow/2026/*.parquet', union_by_name = true)
    UNION ALL
    SELECT 'green', lpep_pickup_datetime, total_amount
    FROM read_parquet('data/raw/green/2026/*.parquet', union_by_name = true)
)
SELECT tipo_taxi, month(pickup_datetime) AS mes, count(*) AS viajes,
       round(count(*) / count(DISTINCT CAST(pickup_datetime AS DATE)), 1) AS viajes_por_dia,
       round(sum(CASE WHEN total_amount >= 0 THEN total_amount ELSE 0 END), 2) AS monto_total
FROM viajes
WHERE pickup_datetime >= DATE '2026-01-01' AND pickup_datetime < DATE '2027-01-01'
GROUP BY tipo_taxi, mes
ORDER BY mes, tipo_taxi;

-- name: 02_patron_horario
-- title: Patron por hora y tipo de dia
-- question: En que horas se concentra la demanda entre dias laborales y fines de semana?
-- justification: La hora y el tipo de dia muestran patrones operativos que el total mensual oculta.
-- source: Archivos Parquet Yellow y Green Taxi de 2026.
-- interpretation: Se reporta la participacion dentro de cada tipo de taxi para hacer comparables sus escalas muy diferentes.
WITH viajes AS (
    SELECT 'yellow' AS tipo_taxi, tpep_pickup_datetime AS pickup_datetime
    FROM read_parquet('data/raw/yellow/2026/*.parquet', union_by_name = true)
    UNION ALL
    SELECT 'green', lpep_pickup_datetime
    FROM read_parquet('data/raw/green/2026/*.parquet', union_by_name = true)
), resumen AS (
    SELECT tipo_taxi,
           CASE WHEN dayofweek(pickup_datetime) IN (0, 6) THEN 'fin_semana' ELSE 'laboral' END AS tipo_dia,
           hour(pickup_datetime) AS hora, count(*) AS viajes
    FROM viajes
    WHERE pickup_datetime >= DATE '2026-01-01' AND pickup_datetime < DATE '2027-01-01'
    GROUP BY ALL
)
SELECT *, round(100.0 * viajes / sum(viajes) OVER (PARTITION BY tipo_taxi, tipo_dia), 2) AS porcentaje
FROM resumen
ORDER BY tipo_taxi, tipo_dia, hora;

-- name: 03_caracteristicas_por_tipo
-- title: Caracteristicas de los viajes por tipo de taxi
-- question: Que diferencias existen en distancia, duracion, pasajeros y monto entre Yellow y Green Taxi?
-- justification: Resume las variables operativas principales usando solo viajes plausibles.
-- source: Archivos Parquet Yellow y Green Taxi de 2026.
-- interpretation: La media se acompana con la mediana para reducir el efecto de valores extremos.
WITH viajes AS (
    SELECT 'yellow' AS tipo_taxi, tpep_pickup_datetime AS pickup_datetime,
           tpep_dropoff_datetime AS dropoff_datetime, passenger_count, trip_distance, total_amount
    FROM read_parquet('data/raw/yellow/2026/*.parquet', union_by_name = true)
    UNION ALL
    SELECT 'green', lpep_pickup_datetime, lpep_dropoff_datetime, passenger_count, trip_distance, total_amount
    FROM read_parquet('data/raw/green/2026/*.parquet', union_by_name = true)
), validos AS (
    SELECT *, date_diff('second', pickup_datetime, dropoff_datetime) / 60.0 AS duracion_min
    FROM viajes
    WHERE pickup_datetime >= DATE '2026-01-01' AND pickup_datetime < DATE '2027-01-01'
      AND dropoff_datetime >= pickup_datetime AND trip_distance > 0 AND total_amount >= 0
)
SELECT tipo_taxi, count(*) AS viajes_validos,
       round(avg(trip_distance), 2) AS distancia_media,
       round(median(trip_distance), 2) AS distancia_mediana,
       round(avg(duracion_min), 2) AS duracion_media_min,
       round(median(duracion_min), 2) AS duracion_mediana_min,
       round(avg(passenger_count), 2) AS pasajeros_promedio,
       round(avg(total_amount), 2) AS monto_promedio,
       round(median(total_amount), 2) AS monto_mediano
FROM validos GROUP BY tipo_taxi ORDER BY tipo_taxi;

-- name: 04_formas_pago
-- title: Distribucion de formas de pago
-- question: Que formas de pago utiliza cada tipo de taxi y que proporcion representan?
-- justification: El metodo de pago condiciona variables como la propina registrada.
-- source: Archivos Parquet Yellow y Green Taxi de 2026.
-- interpretation: Los codigos siguen el diccionario TLC; NULL y 0 se conservan como no informados.
WITH viajes AS (
    SELECT 'yellow' AS tipo_taxi, payment_type
    FROM read_parquet('data/raw/yellow/2026/*.parquet', union_by_name = true)
    UNION ALL
    SELECT 'green', payment_type
    FROM read_parquet('data/raw/green/2026/*.parquet', union_by_name = true)
), resumen AS (
    SELECT tipo_taxi,
           CASE payment_type WHEN 1 THEN 'tarjeta' WHEN 2 THEN 'efectivo'
             WHEN 3 THEN 'sin_cargo' WHEN 4 THEN 'disputa' WHEN 5 THEN 'desconocido'
             WHEN 6 THEN 'viaje_anulado' ELSE 'no_informado' END AS forma_pago,
           count(*) AS viajes
    FROM viajes GROUP BY ALL
)
SELECT *, round(100.0 * viajes / sum(viajes) OVER (PARTITION BY tipo_taxi), 2) AS porcentaje
FROM resumen ORDER BY tipo_taxi, viajes DESC;

-- name: 05_propinas_tarjeta
-- title: Propinas en pagos con tarjeta
-- question: Como difiere la propina registrada entre Yellow y Green Taxi en pagos con tarjeta?
-- justification: TLC solo registra automaticamente la propina de tarjeta, por lo que restringir el metodo evita una comparacion sesgada.
-- source: Archivos Parquet Yellow y Green Taxi de 2026.
-- interpretation: La tasa usa fare_amount positivo como denominador y excluye importes negativos.
WITH viajes AS (
    SELECT 'yellow' AS tipo_taxi, fare_amount, tip_amount, payment_type
    FROM read_parquet('data/raw/yellow/2026/*.parquet', union_by_name = true)
    UNION ALL
    SELECT 'green', fare_amount, tip_amount, payment_type
    FROM read_parquet('data/raw/green/2026/*.parquet', union_by_name = true)
)
SELECT tipo_taxi, count(*) AS pagos_tarjeta,
       round(avg(tip_amount), 2) AS propina_promedio,
       round(median(tip_amount), 2) AS propina_mediana,
       round(100.0 * avg(CASE WHEN tip_amount > 0 THEN 1 ELSE 0 END), 2) AS pct_con_propina,
       round(100.0 * sum(tip_amount) / sum(fare_amount), 2) AS propina_sobre_tarifa_pct
FROM viajes
WHERE payment_type = 1 AND fare_amount > 0 AND tip_amount >= 0
GROUP BY tipo_taxi ORDER BY tipo_taxi;

-- name: 06_distribucion
-- title: Percentiles de distancia, duracion y monto
-- question: Cual es la distribucion de los valores relevantes y cuanto se aleja la cola superior del viaje tipico?
-- justification: Los percentiles describen distribuciones asimetricas mejor que unicamente el promedio.
-- source: Archivos Parquet Yellow y Green Taxi de 2026.
-- interpretation: P99 no define por si mismo un error, pero permite fijar umbrales de revision con evidencia.
WITH viajes AS (
    SELECT 'yellow' AS tipo_taxi, tpep_pickup_datetime AS pickup_datetime, tpep_dropoff_datetime AS dropoff_datetime,
           trip_distance, total_amount
    FROM read_parquet('data/raw/yellow/2026/*.parquet', union_by_name = true)
    UNION ALL
    SELECT 'green', lpep_pickup_datetime, lpep_dropoff_datetime, trip_distance, total_amount
    FROM read_parquet('data/raw/green/2026/*.parquet', union_by_name = true)
), validos AS (
    SELECT *, date_diff('second', pickup_datetime, dropoff_datetime) / 60.0 AS duracion_min
    FROM viajes WHERE dropoff_datetime >= pickup_datetime AND trip_distance > 0 AND total_amount >= 0
      AND pickup_datetime >= DATE '2026-01-01' AND pickup_datetime < DATE '2027-01-01'
)
SELECT tipo_taxi, variable, round(p50, 2) AS p50, round(p90, 2) AS p90,
       round(p95, 2) AS p95, round(p99, 2) AS p99, round(maximo, 2) AS maximo
FROM (
    SELECT tipo_taxi, 'distancia_millas' AS variable, approx_quantile(trip_distance, .5) AS p50,
           approx_quantile(trip_distance, .9) AS p90, approx_quantile(trip_distance, .95) AS p95,
           approx_quantile(trip_distance, .99) AS p99, max(trip_distance) AS maximo FROM validos GROUP BY tipo_taxi
    UNION ALL
    SELECT tipo_taxi, 'duracion_min', approx_quantile(duracion_min, .5), approx_quantile(duracion_min, .9),
           approx_quantile(duracion_min, .95), approx_quantile(duracion_min, .99), max(duracion_min) FROM validos GROUP BY tipo_taxi
    UNION ALL
    SELECT tipo_taxi, 'monto_usd', approx_quantile(total_amount, .5), approx_quantile(total_amount, .9),
           approx_quantile(total_amount, .95), approx_quantile(total_amount, .99), max(total_amount) FROM validos GROUP BY tipo_taxi
) ORDER BY tipo_taxi, variable;

-- name: 07_atipicos_inconsistencias
-- title: Valores atipicos e inconsistencias
-- question: Cuantos registros presentan valores imposibles o extremos que requieren revision?
-- justification: Cuantificar cada regla evita eliminar datos silenciosamente y muestra su impacto por servicio.
-- source: Archivos Parquet Yellow y Green Taxi de 2026.
-- interpretation: Los umbrales de 100 millas, 6 horas y USD 500 son banderas de revision, no pruebas automaticas de error.
WITH viajes AS (
    SELECT 'yellow' AS tipo_taxi, tpep_pickup_datetime AS pickup_datetime, tpep_dropoff_datetime AS dropoff_datetime,
           passenger_count, trip_distance, fare_amount, total_amount
    FROM read_parquet('data/raw/yellow/2026/*.parquet', union_by_name = true)
    UNION ALL
    SELECT 'green', lpep_pickup_datetime, lpep_dropoff_datetime, passenger_count, trip_distance, fare_amount, total_amount
    FROM read_parquet('data/raw/green/2026/*.parquet', union_by_name = true)
)
SELECT tipo_taxi, count(*) AS registros,
       count_if(dropoff_datetime < pickup_datetime) AS duracion_negativa,
       count_if(date_diff('hour', pickup_datetime, dropoff_datetime) > 6) AS duracion_mayor_6h,
       count_if(trip_distance <= 0) AS distancia_no_positiva,
       count_if(trip_distance > 100) AS distancia_mayor_100mi,
       count_if(passenger_count <= 0) AS pasajeros_no_positivos,
       count_if(passenger_count > 8) AS pasajeros_mayor_8,
       count_if(fare_amount < 0) AS tarifa_negativa,
       count_if(total_amount < 0) AS total_negativo,
       count_if(total_amount > 500) AS total_mayor_500
FROM viajes
WHERE pickup_datetime >= DATE '2026-01-01' AND pickup_datetime < DATE '2027-01-01'
GROUP BY tipo_taxi ORDER BY tipo_taxi;

-- name: 08_rutas_frecuentes
-- title: Rutas mas frecuentes
-- question: Cuales son los pares de zonas de origen y destino con mayor volumen en cada servicio?
-- justification: Las rutas frecuentes describen la geografia operativa sin requerir cargar geometria espacial.
-- source: Archivos Parquet Yellow y Green Taxi de 2026.
-- interpretation: Se muestran identificadores TLC de zona; pueden unirse posteriormente al Taxi Zone Lookup.
WITH viajes AS (
    SELECT 'yellow' AS tipo_taxi, PULocationID AS origen, DOLocationID AS destino
    FROM read_parquet('data/raw/yellow/2026/*.parquet', union_by_name = true)
    UNION ALL
    SELECT 'green', PULocationID, DOLocationID
    FROM read_parquet('data/raw/green/2026/*.parquet', union_by_name = true)
), rutas AS (
    SELECT tipo_taxi, origen, destino, count(*) AS viajes
    FROM viajes WHERE origen IS NOT NULL AND destino IS NOT NULL GROUP BY ALL
)
SELECT tipo_taxi, origen, destino, viajes
FROM rutas QUALIFY row_number() OVER (PARTITION BY tipo_taxi ORDER BY viajes DESC) <= 10
ORDER BY tipo_taxi, viajes DESC;
