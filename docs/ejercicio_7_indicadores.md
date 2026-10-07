# Ejercicio 7 - Indicadores y tablero

Documento generado por `scripts/build_indicadores.py`. Los indicadores se calculan sobre
`data/processed/taxi.duckdb`, que materializa los Parquet descargados, y se visualizan en
Metabase (<http://localhost:3000>) y en `notebooks/07_indicadores.ipynb`.

## Modelo de datos

### Tabla viajes (Yellow y Green normalizados)

**Objetivo:** Unificar todos los anios descargados de ambos servicios con nombres de columna comunes.

**Decision:** El anio y mes se toman del nombre del archivo; los registros originales no se filtran aqui.

```sql
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
```

### Tabla zonas (TLC Taxi Zone Lookup)

**Objetivo:** Traducir los identificadores de zona a barrio y nombre legible.

**Decision:** Se carga desde data/raw/zones/taxi_zone_lookup.csv, descargado por scripts/download_data.py.

```sql
CREATE OR REPLACE TABLE zonas AS
SELECT LocationID AS zona_id, Borough AS barrio, Zone AS zona, service_zone
FROM read_csv('data/raw/zones/taxi_zone_lookup.csv', header = true);
```

### Vista viajes_validos

**Objetivo:** Centralizar el criterio de viaje plausible usado por los indicadores.

**Decision:** Mismo criterio que el Ejercicio 4 (fecha dentro del anio del archivo, distancia positiva, total no negativo) mas duracion entre 0 y 6 horas, umbral que el Ejercicio 4 marco como atipico.

```sql
CREATE OR REPLACE VIEW viajes_validos AS
SELECT *
FROM viajes
WHERE year(pickup_datetime) = anio
  AND duracion_min > 0 AND duracion_min <= 360
  AND trip_distance > 0
  AND total_amount >= 0;
```

### Registros cargados y registros validos

| anio | tipo_taxi | registros | validos | pct_validos |
| --- | --- | --- | --- | --- |
| 2024 | green | 660218 | 621641 | 94.16 |
| 2024 | yellow | 41169720 | 39810674 | 96.7 |
| 2025 | green | 591375 | 561980 | 95.03 |
| 2025 | yellow | 48722602 | 45873800 | 94.15 |
| 2026 | green | 337114 | 323240 | 95.88 |
| 2026 | yellow | 29703355 | 28237465 | 95.06 |

## Indicadores

### 1. Duracion del viaje segun numero de pasajeros

**Pregunta:** Llevar mas pasajeros aumenta el tiempo de viaje?

**Justificacion:** Si la duracion cambia con los pasajeros puede deberse a paradas extra o a que los grupos hacen viajes mas largos; por eso se reporta tambien la distancia y los minutos por milla, que aislan el efecto de la distancia.

**Indicador:** Duracion mediana (min), distancia media y minutos por milla por numero de pasajeros (1 a 6).

**Visualizacion:** grafico `bar` con `pasajeros` como ejes y `duracion_mediana_min, min_por_milla` como valores.

```sql
SELECT passenger_count AS pasajeros,
       count(*) AS viajes,
       round(avg(duracion_min), 2) AS duracion_media_min,
       round(median(duracion_min), 2) AS duracion_mediana_min,
       round(avg(trip_distance), 2) AS distancia_media,
       round(sum(duracion_min) / sum(trip_distance), 2) AS min_por_milla
FROM viajes_validos
WHERE passenger_count BETWEEN 1 AND 6
GROUP BY passenger_count
ORDER BY pasajeros;
```

| pasajeros | viajes | duracion_media_min | duracion_mediana_min | distancia_media | min_por_milla |
| --- | --- | --- | --- | --- | --- |
| 1 | 74460304 | 16.69 | 12.62 | 3.41 | 4.89 |
| 2 | 12852953 | 18.31 | 13.58 | 4.01 | 4.57 |
| 3 | 2980410 | 18.18 | 13.78 | 3.87 | 4.69 |
| 4 | 1916642 | 19.31 | 14.63 | 4.2 | 4.6 |
| 5 | 574878 | 15.43 | 11.93 | 3.18 | 4.86 |
| 6 | 368713 | 15.65 | 11.97 | 3.08 | 5.08 |

**Interpretacion:** Con 2024-2026 la duracion mediana sube de 12.6 min con 1 pasajero a 14.6 min con 4, pero la distancia media tambien sube (3.4 a 4.2 millas) y los minutos por milla bajan (4.89 a 4.60). Los grupos no viajan mas lento: hacen viajes mas largos. Con 5 y 6 pasajeros (vehiculos grandes) los viajes vuelven a ser cortos (12 min). No hay evidencia de que llevar mas pasajeros aumente el tiempo por si mismo.

### 2. Duracion promedio del viaje por mes

**Pregunta:** Cuanto dura en promedio un viaje y como cambia entre meses, anios y servicios?

**Justificacion:** La duracion (hora final menos hora inicial) resume congestion y tipo de recorrido; verla por mes permite comparar anios.

**Indicador:** Duracion media y mediana (min) por mes y tipo de taxi.

**Visualizacion:** grafico `line` con `fecha, tipo_taxi` como ejes y `duracion_mediana_min` como valores.

```sql
SELECT make_date(anio, mes, 1) AS fecha,
       tipo_taxi,
       count(*) AS viajes,
       round(avg(duracion_min), 2) AS duracion_media_min,
       round(median(duracion_min), 2) AS duracion_mediana_min
FROM viajes_validos
GROUP BY ALL
ORDER BY fecha, tipo_taxi;
```

| fecha | tipo_taxi | viajes | duracion_media_min | duracion_mediana_min |
| --- | --- | --- | --- | --- |
| 2024-01-01 | green | 53363 | 13.88 | 11.45 |
| 2024-01-01 | yellow | 2870280 | 14.97 | 11.72 |
| 2024-02-01 | green | 50429 | 14.04 | 11.47 |
| 2024-02-01 | yellow | 2904700 | 15.36 | 12.07 |
| 2024-03-01 | green | 54128 | 14.26 | 11.65 |
| 2024-03-01 | yellow | 3452875 | 16.11 | 12.55 |
| 2024-04-01 | green | 52961 | 14.29 | 11.72 |
| 2024-04-01 | yellow | 3426737 | 16.45 | 12.9 |
| 2024-05-01 | green | 57505 | 15.34 | 12.42 |
| 2024-05-01 | yellow | 3627413 | 17.49 | 13.43 |
| 2024-06-01 | green | 51713 | 15.07 | 12.25 |
| 2024-06-01 | yellow | 3439723 | 17.01 | 13.05 |
| 2024-07-01 | green | 48538 | 14.46 | 11.8 |
| 2024-07-01 | yellow | 2980825 | 16.65 | 12.92 |
| 2024-08-01 | green | 48729 | 14.95 | 12 |
| 2024-08-01 | yellow | 2871194 | 16.78 | 12.87 |
| 2024-09-01 | green | 51339 | 15.91 | 12.73 |
| 2024-09-01 | yellow | 3498663 | 18.19 | 13.98 |
| 2024-10-01 | green | 53200 | 15.2 | 12.37 |
| 2024-10-01 | yellow | 3693666 | 17.81 | 13.95 |
| 2024-11-01 | green | 49113 | 14.98 | 12.13 |
| 2024-11-01 | yellow | 3519080 | 17.28 | 13.48 |
| 2024-12-01 | green | 50623 | 14.95 | 11.87 |
| 2024-12-01 | yellow | 3525518 | 18.19 | 13.9 |
| 2025-01-01 | green | 45317 | 13.56 | 11.28 |
| 2025-01-01 | yellow | 3323270 | 14.69 | 11.73 |
| 2025-02-01 | green | 43686 | 14.13 | 11.55 |
| 2025-02-01 | yellow | 3420914 | 15.1 | 12.25 |
| 2025-03-01 | green | 48118 | 15.08 | 12.13 |
| 2025-03-01 | yellow | 3954951 | 15.74 | 12.57 |
| 2025-04-01 | green | 48556 | 15.37 | 12.38 |
| 2025-04-01 | yellow | 3776169 | 16.4 | 13.07 |
| 2025-05-01 | green | 51971 | 15.79 | 12.73 |
| 2025-05-01 | yellow | 4284379 | 17.83 | 14.07 |
| 2025-06-01 | green | 47051 | 16.01 | 12.78 |
| 2025-06-01 | yellow | 4051320 | 17.43 | 13.83 |
| 2025-07-01 | green | 46422 | 16.35 | 12.88 |
| 2025-07-01 | yellow | 3648227 | 17.15 | 13.77 |
| 2025-08-01 | green | 44563 | 16.66 | 13.27 |
| 2025-08-01 | yellow | 3339491 | 17.25 | 13.68 |

_Se muestran 40 de 64 filas; el resto esta en el notebook 07._

**Interpretacion:** La duracion mediana anual de Yellow sube de 13.1 min (2024) a 13.7 (2025) y 14.1 (2026), y Green muestra la misma tendencia (enero: 11.5, 11.3 y 13.1 min). Parte del aumento se debe a que crecen los registros sin datos del taximetro, que son viajes mas largos: en viajes con tarifa estandar (enero-agosto) la duracion mediana casi no cambia entre 2024 y 2025 (11.9 y 11.7 min) y sube en 2026 (12.2 min) porque la velocidad baja de 9.2 a 8.7 mph (ver Ejercicio 8). En 2024 y 2025 la duracion crece de enero a mayo y alcanza sus maximos entre septiembre y diciembre.

### 3. Tarifa base segun forma de pago

**Pregunta:** Con que forma de pago la tarifa base es mas alta?

**Justificacion:** Si una forma de pago se asocia a viajes mas caros, la mezcla de pagos influye en los ingresos; la distancia media ayuda a explicar la diferencia.

**Indicador:** Tarifa base media y mediana (USD) y distancia media por forma de pago y anio.

**Visualizacion:** grafico `bar` con `forma_pago, anio` como ejes y `tarifa_base_media` como valores.

```sql
SELECT CAST(anio AS VARCHAR) AS anio,
       CASE payment_type
           WHEN 1 THEN 'tarjeta' WHEN 2 THEN 'efectivo' WHEN 3 THEN 'sin_cargo'
           WHEN 4 THEN 'disputa' WHEN 0 THEN 'sin_dato (0)' ELSE 'otro'
       END AS forma_pago,
       count(*) AS viajes,
       round(avg(fare_amount), 2) AS tarifa_base_media,
       round(median(fare_amount), 2) AS tarifa_base_mediana,
       round(avg(trip_distance), 2) AS distancia_media
FROM viajes_validos
WHERE fare_amount > 0
GROUP BY ALL
ORDER BY anio, viajes DESC;
```

| anio | forma_pago | viajes | tarifa_base_media | tarifa_base_mediana | distancia_media |
| --- | --- | --- | --- | --- | --- |
| 2024 | tarjeta | 30598065 | 19.7 | 13.5 | 3.56 |
| 2024 | efectivo | 5444711 | 19.55 | 12.8 | 3.39 |
| 2024 | sin_dato (0) | 3693052 | 20.53 | 18.08 | 19.32 |
| 2024 | disputa | 386503 | 22.25 | 12.8 | 3.85 |
| 2024 | sin_cargo | 158033 | 21.75 | 11.4 | 3.24 |
| 2024 | otro | 23693 | 25.69 | 20.36 | 388.19 |
| 2025 | tarjeta | 30714956 | 19.67 | 13.5 | 3.56 |
| 2025 | sin_dato (0) | 8846293 | 21.24 | 18.79 | 18.66 |
| 2025 | efectivo | 4416197 | 19.62 | 12.8 | 3.42 |
| 2025 | disputa | 532174 | 25.3 | 13.5 | 4.49 |
| 2025 | sin_cargo | 162079 | 20.99 | 11.4 | 3.33 |
| 2025 | otro | 45510 | 14.53 | 5.8 | 209.3 |
| 2026 | tarjeta | 18668082 | 19.7 | 13.5 | 3.39 |
| 2026 | sin_dato (0) | 7037578 | 25.86 | 23.19 | 12.87 |
| 2026 | efectivo | 2618143 | 20.22 | 13.5 | 3.56 |
| 2026 | disputa | 118306 | 22.72 | 12.8 | 3.91 |
| 2026 | sin_cargo | 56974 | 18.6 | 11.4 | 2.96 |
| 2026 | otro | 43099 | 10.48 | 3 | 85.49 |

**Interpretacion:** Tarjeta y efectivo tienen practicamente la misma tarifa base en los tres anios (mediana USD 12.80-13.50): la forma de pago no determina el precio. La tarifa mas alta esta en el codigo 0 (mediana USD 18.08, 18.79 y 23.19 en 2024, 2025 y 2026), que agrupa registros sin datos del taximetro, incluidos los viajes por plataforma, que son mas largos; ademas este grupo crecio de 3.7 a 8.8 millones de viajes entre 2024 y 2025. Disputa tiene la media mas alta entre los codigos normales, pero su mediana (USD 12.80-13.50) no supera a la de tarjeta: la diferencia la producen pocos viajes caros.

### 4. Tarifa base segun origen de la solicitud

**Pregunta:** Los viajes pedidos por plataforma (Uber, Lyft u otras) tienen una tarifa base mas alta que los demas?

**Justificacion:** request_source existe solo en Yellow desde junio de 2026; HV0003 y HV0005 son las licencias TLC de Uber y Lyft. Se usa la tarifa por milla para separar el precio de la distancia. No se compara propina porque en viajes por plataforma no se registra (llega como 0).

**Indicador:** Participacion y medianas de tarifa base, distancia, duracion y tarifa por milla por origen de solicitud.

**Visualizacion:** grafico `bar` con `origen` como ejes y `tarifa_base_mediana, tarifa_por_milla_mediana` como valores.

```sql
WITH periodo AS (
    SELECT * FROM viajes_validos
    WHERE tipo_taxi = 'yellow'
      AND make_date(anio, mes, 1) >= (
          SELECT min(make_date(anio, mes, 1)) FROM viajes WHERE request_source IS NOT NULL)
)
SELECT CASE request_source
           WHEN 'HV0003' THEN 'Uber' WHEN 'HV0005' THEN 'Lyft'
           ELSE CASE WHEN request_source IS NULL THEN 'sin plataforma' ELSE 'otras plataformas' END
       END AS origen,
       count(*) AS viajes,
       round(100.0 * count(*) / sum(count(*)) OVER (), 2) AS pct_viajes,
       round(median(fare_amount), 2) AS tarifa_base_mediana,
       round(median(trip_distance), 2) AS distancia_mediana,
       round(median(duracion_min), 2) AS duracion_mediana_min,
       round(median(fare_amount / trip_distance), 2) AS tarifa_por_milla_mediana,
       round(avg(trip_distance), 2) AS distancia_media
FROM periodo
WHERE fare_amount > 0
GROUP BY origen
ORDER BY viajes DESC;
```

| origen | viajes | pct_viajes | tarifa_base_mediana | distancia_mediana | duracion_mediana_min | tarifa_por_milla_mediana | distancia_media |
| --- | --- | --- | --- | --- | --- | --- | --- |
| sin plataforma | 7516388 | 74.03 | 13.5 | 1.7 | 12.88 | 7.53 | 3.34 |
| Uber | 2092550 | 20.61 | 22.98 | 3.03 | 17.13 | 7.17 | 12.14 |
| otras plataformas | 381679 | 3.76 | 21.66 | 3.6 | 20.55 | 5.92 | 9.87 |
| Lyft | 162333 | 1.6 | 23.36 | 4.88 | 22.98 | 4.68 | 5.98 |

**Interpretacion:** request_source solo trae datos desde junio de 2026 (en 2024 y 2025 no existe). En junio-agosto de 2026, el 26 % de los viajes Yellow llego por plataforma (Uber 20.6 %, Lyft 1.6 %, otras 3.8 %). Su tarifa base mediana es mucho mayor (Uber USD 22.98 vs USD 13.50 sin plataforma), pero porque son viajes mas largos (3.0 vs 1.7 millas): la tarifa por milla de Uber (USD 7.17) es incluso algo menor que la de los viajes sin plataforma (USD 7.53). Las medias de distancia de las plataformas estan infladas por valores extremos, por eso se usan medianas.

### 5. Propina segun distancia del viaje

**Pregunta:** Los pasajeros dejan proporcionalmente mas propina en viajes cortos o largos?

**Justificacion:** Reemplaza la comparacion de propina por origen, que no es posible porque las plataformas no registran propina. Solo se usan pagos con tarjeta, unicos con propina registrada.

**Indicador:** Propina como porcentaje de la tarifa y porcentaje de viajes con propina por rango de distancia.

**Visualizacion:** grafico `bar` con `rango_distancia, anio` como ejes y `propina_pct_tarifa` como valores.

```sql
SELECT CAST(anio AS VARCHAR) AS anio,
       CASE
           WHEN trip_distance < 1 THEN '1) < 1 mi'
           WHEN trip_distance < 2 THEN '2) 1-2 mi'
           WHEN trip_distance < 5 THEN '3) 2-5 mi'
           WHEN trip_distance < 10 THEN '4) 5-10 mi'
           WHEN trip_distance < 20 THEN '5) 10-20 mi'
           ELSE '6) 20+ mi'
       END AS rango_distancia,
       count(*) AS viajes,
       round(avg(tip_amount), 2) AS propina_media,
       round(100.0 * sum(tip_amount) / sum(fare_amount), 2) AS propina_pct_tarifa,
       round(100.0 * avg(CASE WHEN tip_amount > 0 THEN 1 ELSE 0 END), 2) AS pct_con_propina
FROM viajes_validos
WHERE payment_type = 1 AND fare_amount > 0 AND tip_amount >= 0
GROUP BY ALL
ORDER BY anio, rango_distancia;
```

| anio | rango_distancia | viajes | propina_media | propina_pct_tarifa | pct_con_propina |
| --- | --- | --- | --- | --- | --- |
| 2024 | 1) < 1 mi | 6729621 | 2.33 | 28.72 | 95.09 |
| 2024 | 2) 1-2 mi | 10353704 | 2.98 | 24.89 | 95.9 |
| 2024 | 3) 2-5 mi | 8317760 | 4.21 | 21.67 | 95.02 |
| 2024 | 4) 5-10 mi | 2585661 | 7.36 | 20.74 | 90.17 |
| 2024 | 5) 10-20 mi | 2284599 | 11.95 | 19.31 | 88.36 |
| 2024 | 6) 20+ mi | 326720 | 15.34 | 17.05 | 88.02 |
| 2025 | 1) < 1 mi | 6997591 | 2.42 | 29.27 | 94.49 |
| 2025 | 2) 1-2 mi | 10305095 | 3.04 | 25.43 | 95.18 |
| 2025 | 3) 2-5 mi | 8137573 | 4.23 | 21.79 | 93.47 |
| 2025 | 4) 5-10 mi | 2671914 | 7.13 | 19.96 | 85.67 |
| 2025 | 5) 10-20 mi | 2301666 | 11.33 | 18.44 | 83.03 |
| 2025 | 6) 20+ mi | 301117 | 15.04 | 16.26 | 83.28 |
| 2026 | 1) < 1 mi | 4423741 | 2.47 | 28.99 | 94.03 |
| 2026 | 2) 1-2 mi | 6203059 | 3.08 | 25.26 | 94.46 |
| 2026 | 3) 2-5 mi | 4833993 | 4.22 | 21.36 | 91.42 |
| 2026 | 4) 5-10 mi | 1656675 | 6.87 | 19.23 | 81.48 |
| 2026 | 5) 10-20 mi | 1369066 | 10.91 | 17.95 | 79 |
| 2026 | 6) 20+ mi | 181548 | 14.5 | 15.92 | 78.69 |

**Interpretacion:** La propina en proporcion a la tarifa disminuye con la distancia: cerca de 29 % en viajes de menos de 1 milla y 16-17 % en viajes de mas de 20 millas, aunque en dolares crece. La proporcion de viajes con propina cae ano a ano en viajes medios y largos: en 5-10 millas pasa de 90.2 % (2024) a 85.7 % (2025) y 81.5 % (2026), y en mas de 20 millas de 88.0 % a 78.7 %, mientras en viajes de menos de 1 milla se mantiene en 94-95 %.

### 6. Uso y costo de cada tipo de tarifa

**Pregunta:** Que tipos de tarifa (estandar, aeropuertos, negociada) se usan y cual tiene la tarifa base mas alta?

**Justificacion:** Reemplaza la relacion tipo de tarifa - origen de solicitud, que no es medible porque los viajes por plataforma no informan RatecodeID. Las tarifas especiales explican buena parte de los viajes caros.

**Indicador:** Porcentaje de viajes, tarifa base media, distancia y duracion media por tipo de tarifa.

**Visualizacion:** grafico `bar` con `tipo_tarifa, anio` como ejes y `tarifa_base_media` como valores.

```sql
WITH resumen AS (
    SELECT CAST(anio AS VARCHAR) AS anio,
           CASE ratecode_id
               WHEN 1 THEN '1 estandar' WHEN 2 THEN '2 JFK' WHEN 3 THEN '3 Newark'
               WHEN 4 THEN '4 Nassau/Westchester' WHEN 5 THEN '5 negociada'
               WHEN 6 THEN '6 grupal' ELSE '99 desconocida'
           END AS tipo_tarifa,
           count(*) AS viajes,
           round(avg(fare_amount), 2) AS tarifa_base_media,
           round(avg(trip_distance), 2) AS distancia_media,
           round(avg(duracion_min), 2) AS duracion_media_min
    FROM viajes_validos
    WHERE ratecode_id IS NOT NULL AND fare_amount > 0
    GROUP BY ALL
)
SELECT anio, tipo_tarifa, viajes,
       round(100.0 * viajes / sum(viajes) OVER (PARTITION BY anio), 2) AS pct_viajes,
       tarifa_base_media, distancia_media, duracion_media_min
FROM resumen
ORDER BY anio, tipo_tarifa;
```

| anio | tipo_tarifa | viajes | pct_viajes | tarifa_base_media | distancia_media | duracion_media_min |
| --- | --- | --- | --- | --- | --- | --- |
| 2024 | 1 estandar | 34416810 | 94.07 | 16.79 | 2.69 | 14.88 |
| 2024 | 2 JFK | 1331954 | 3.64 | 70 | 17.92 | 51.74 |
| 2024 | 3 Newark | 116552 | 0.32 | 87.73 | 16.58 | 39.75 |
| 2024 | 4 Nassau/Westchester | 96721 | 0.26 | 114.41 | 22.06 | 42.95 |
| 2024 | 5 negociada | 185856 | 0.51 | 75.43 | 11.65 | 25.5 |
| 2024 | 6 grupal | 22 | 0 | 3.86 | 2.68 | 14.7 |
| 2024 | 99 desconocida | 439418 | 1.2 | 33.8 | 15.37 | 49.49 |
| 2025 | 1 estandar | 33307702 | 92.97 | 16.55 | 2.63 | 14.64 |
| 2025 | 2 JFK | 1207472 | 3.37 | 70.54 | 17.75 | 52.53 |
| 2025 | 3 Newark | 125522 | 0.35 | 78.79 | 14.13 | 36.07 |
| 2025 | 4 Nassau/Westchester | 108481 | 0.3 | 114.4 | 24.34 | 44.06 |
| 2025 | 5 negociada | 290184 | 0.81 | 73.93 | 10.34 | 25.5 |
| 2025 | 6 grupal | 19 | 0 | 2.97 | 2.15 | 4.56 |
| 2025 | 99 desconocida | 786045 | 2.19 | 34.69 | 13.82 | 50.63 |
| 2026 | 1 estandar | 19726107 | 91.91 | 16.59 | 2.61 | 14.85 |
| 2026 | 2 JFK | 661056 | 3.08 | 70 | 17.72 | 51.52 |
| 2026 | 3 Newark | 81433 | 0.38 | 76.19 | 13.35 | 35.43 |
| 2026 | 4 Nassau/Westchester | 64865 | 0.3 | 114.21 | 23.18 | 43.14 |
| 2026 | 5 negociada | 167011 | 0.78 | 76.11 | 8.37 | 22.28 |
| 2026 | 6 grupal | 5 | 0 | 2.7 | 2.7 | 2.08 |
| 2026 | 99 desconocida | 761028 | 3.55 | 32.33 | 7.93 | 45.57 |

**Interpretacion:** La tarifa estandar cubre la gran mayoria de los viajes, pero su participacion baja de 94.1 % a 93.0 % y 91.9 % entre 2024 y 2026. JFK se mantiene cerca de USD 70 (tarifa fija) y Nassau/Westchester es la mas cara (USD 114). Newark bajo de USD 87.7 a 78.8 y 76.2. La categoria desconocida (99) crece cada anio (1.2 %, 2.2 % y 3.6 %), lo que indica una perdida de calidad en este campo.

### 7. Zonas de destino con mayor y menor propina

**Pregunta:** Hay destinos donde los pasajeros dejan una propina mas alta?

**Justificacion:** El destino refleja el tipo de viaje (aeropuerto, oficinas, ocio, zonas residenciales). Solo pagos con tarjeta y zonas con al menos 10,000 viajes para evitar porcentajes inestables. Se muestran ambos extremos porque el contraste esta entre ellos.

**Indicador:** Propina como porcentaje de la tarifa por zona de destino (10 mas altas y 10 mas bajas).

**Visualizacion:** grafico `row` con `destino` como ejes y `propina_pct_tarifa` como valores.

```sql
WITH por_destino AS (
    SELECT z.zona || ' (' || z.barrio || ')' AS destino,
           count(*) AS viajes,
           round(avg(v.tip_amount), 2) AS propina_media,
           round(100.0 * sum(v.tip_amount) / sum(v.fare_amount), 2) AS propina_pct_tarifa
    FROM viajes_validos AS v
    JOIN zonas AS z ON z.zona_id = v.destino_id
    WHERE v.payment_type = 1 AND v.fare_amount > 0 AND v.tip_amount >= 0
      AND z.zona NOT IN ('N/A', 'Outside of NYC')
    GROUP BY destino
    HAVING count(*) >= 10000
), ranking AS (
    SELECT *,
           row_number() OVER (ORDER BY propina_pct_tarifa DESC) AS desde_arriba,
           row_number() OVER (ORDER BY propina_pct_tarifa) AS desde_abajo
    FROM por_destino
)
SELECT CASE WHEN desde_arriba <= 10 THEN 'mas alta' ELSE 'mas baja' END AS grupo,
       destino, viajes, propina_media, propina_pct_tarifa
FROM ranking
WHERE desde_arriba <= 10 OR desde_abajo <= 10
ORDER BY propina_pct_tarifa DESC;
```

| grupo | destino | viajes | propina_media | propina_pct_tarifa |
| --- | --- | --- | --- | --- |
| mas alta | Upper East Side South (Manhattan) | 3688100 | 3.31 | 24.96 |
| mas alta | Upper West Side South (Manhattan) | 2359661 | 3.88 | 24.62 |
| mas alta | Lincoln Square East (Manhattan) | 2298378 | 3.69 | 24.58 |
| mas alta | Greenwich Village North (Manhattan) | 1064685 | 3.95 | 24.58 |
| mas alta | Upper East Side North (Manhattan) | 3899870 | 3.42 | 24.56 |
| mas alta | West Village (Manhattan) | 1444357 | 3.57 | 24.43 |
| mas alta | Penn Station/Madison Sq West (Manhattan) | 1654700 | 3.84 | 24.39 |
| mas alta | Central Park (Manhattan) | 886708 | 3.67 | 24.36 |
| mas alta | Flatiron (Manhattan) | 1194768 | 3.81 | 24.28 |
| mas alta | Union Sq (Manhattan) | 2008257 | 3.53 | 24.28 |
| mas baja | Williamsbridge/Olinville (Bronx) | 14435 | 2.46 | 5.09 |
| mas baja | Morrisania/Melrose (Bronx) | 11644 | 1.82 | 4.89 |
| mas baja | University Heights/Morris Heights (Bronx) | 13015 | 1.83 | 4.62 |
| mas baja | Co-Op City (Bronx) | 19336 | 2.14 | 4.43 |
| mas baja | Hammels/Arverne (Queens) | 14474 | 2.27 | 4.34 |
| mas baja | East Tremont (Bronx) | 10920 | 1.68 | 4.09 |
| mas baja | East New York/Pennsylvania Avenue (Brooklyn) | 15137 | 1.38 | 3.92 |
| mas baja | East New York (Brooklyn) | 61448 | 1.21 | 3.56 |
| mas baja | Brownsville (Brooklyn) | 31739 | 1.03 | 3.03 |
| mas baja | Starrett City (Brooklyn) | 15835 | 0.73 | 2.03 |

**Interpretacion:** Las 10 zonas con mayor propina estan todas en Manhattan (Upper East/West Side, Village, Midtown), con 24.3-25.0 % de la tarifa y muy poca variacion entre ellas. El contraste esta en el otro extremo: en destinos de Brooklyn, Bronx y Queens como Starrett City (2.0 %), Brownsville (3.0 %) o East New York (3.6 %) la propina registrada es 5 a 12 veces menor. El destino si se asocia con la propina, y la diferencia es entre Manhattan y zonas perifericas.

### 8. Demanda mensual de viajes

**Pregunta:** Como evoluciona la cantidad de viajes por mes y anio en Yellow y Green?

**Justificacion:** Es el indicador base de actividad; se usa viajes por dia para comparar meses de distinta longitud y meses parciales.

**Indicador:** Viajes por dia por mes y tipo de taxi (todos los registros con fecha dentro del anio del archivo).

**Visualizacion:** grafico `line` con `fecha, tipo_taxi` como ejes y `viajes_por_dia` como valores.

```sql
WITH mensual AS (
    SELECT make_date(anio, mes, 1) AS fecha, tipo_taxi, count(*) AS viajes
    FROM viajes
    WHERE year(pickup_datetime) = anio
    GROUP BY ALL
)
SELECT fecha, tipo_taxi, viajes,
       round(viajes / day(last_day(fecha)), 1) AS viajes_por_dia
FROM mensual
ORDER BY fecha, tipo_taxi;
```

| fecha | tipo_taxi | viajes | viajes_por_dia |
| --- | --- | --- | --- |
| 2024-01-01 | green | 56549 | 1824.2 |
| 2024-01-01 | yellow | 2964609 | 95632.5 |
| 2024-02-01 | green | 53577 | 1847.5 |
| 2024-02-01 | yellow | 3007524 | 103708 |
| 2024-03-01 | green | 57455 | 1853.4 |
| 2024-03-01 | yellow | 3582626 | 115569 |
| 2024-04-01 | green | 56471 | 1882.4 |
| 2024-04-01 | yellow | 3514285 | 117143 |
| 2024-05-01 | green | 61001 | 1967.8 |
| 2024-05-01 | yellow | 3723826 | 120123 |
| 2024-06-01 | green | 54748 | 1824.9 |
| 2024-06-01 | yellow | 3539187 | 117973 |
| 2024-07-01 | green | 51837 | 1672.2 |
| 2024-07-01 | yellow | 3076900 | 99254.8 |
| 2024-08-01 | green | 51771 | 1670 |
| 2024-08-01 | yellow | 2979181 | 96102.6 |
| 2024-09-01 | green | 54439 | 1814.6 |
| 2024-09-01 | yellow | 3633027 | 121101 |
| 2024-10-01 | green | 56147 | 1811.2 |
| 2024-10-01 | yellow | 3833770 | 123670 |
| 2024-11-01 | green | 52222 | 1740.7 |
| 2024-11-01 | yellow | 3646366 | 121546 |
| 2024-12-01 | green | 53981 | 1741.3 |
| 2024-12-01 | yellow | 3668363 | 118334 |
| 2025-01-01 | green | 48320 | 1558.7 |
| 2025-01-01 | yellow | 3475205 | 112103 |
| 2025-02-01 | green | 46621 | 1665 |
| 2025-02-01 | yellow | 3577543 | 127769 |
| 2025-03-01 | green | 51539 | 1662.5 |
| 2025-03-01 | yellow | 4145255 | 133718 |
| 2025-04-01 | green | 52132 | 1737.7 |
| 2025-04-01 | yellow | 3970553 | 132352 |
| 2025-05-01 | green | 55399 | 1787.1 |
| 2025-05-01 | yellow | 4591844 | 148124 |
| 2025-06-01 | green | 49390 | 1646.3 |
| 2025-06-01 | yellow | 4322960 | 144099 |
| 2025-07-01 | green | 48205 | 1555 |
| 2025-07-01 | yellow | 3898962 | 125773 |
| 2025-08-01 | green | 46306 | 1493.7 |
| 2025-08-01 | yellow | 3574090 | 115293 |

_Se muestran 40 de 64 filas; el resto esta en el notebook 07._

**Interpretacion:** El total de Yellow alcanza su maximo en 2025: cada mes supera al mismo mes de 2024 (mayo: 148 mil vs 120 mil viajes por dia) y de febrero a agosto de 2026 queda por debajo de 2025 (mayo: 132 mil). Ese crecimiento no proviene de viajes con taximetro, que solo suben 2 % en 2025 y caen 9 % en 2026 (enero-agosto), sino de los registros sin datos del taximetro, que se triplican (ver Ejercicio 8). Green cae de forma continua: cada mes de 2025 es menor que el de 2024 y cada mes de 2026 menor que el de 2025 (agosto: 1,670, 1,494 y 1,312 viajes por dia). En los tres anios la demanda baja en julio-agosto.

### 9. Demanda por hora y dia de la semana

**Pregunta:** En que horas y dias se concentra la demanda?

**Justificacion:** Muestra los picos operativos que el total mensual oculta. Se usa el porcentaje dentro de cada dia para comparar la forma de la curva.

**Indicador:** Porcentaje de los viajes de cada dia de la semana que ocurre en cada hora.

**Visualizacion:** grafico `line` con `hora, dia_semana` como ejes y `pct_del_dia` como valores.

```sql
WITH conteo AS (
    SELECT isodow(pickup_datetime) AS dow, hour(pickup_datetime) AS hora, count(*) AS viajes
    FROM viajes_validos
    GROUP BY ALL
)
SELECT hora,
       ['1 Lun', '2 Mar', '3 Mie', '4 Jue', '5 Vie', '6 Sab', '7 Dom'][dow] AS dia_semana,
       viajes,
       round(100.0 * viajes / sum(viajes) OVER (PARTITION BY dow), 2) AS pct_del_dia
FROM conteo
ORDER BY dia_semana, hora;
```

| hora | dia_semana | viajes | pct_del_dia |
| --- | --- | --- | --- |
| 0 | 1 Lun | 265496 | 1.88 |
| 1 | 1 Lun | 135280 | 0.96 |
| 2 | 1 Lun | 77157 | 0.55 |
| 3 | 1 Lun | 57584 | 0.41 |
| 4 | 1 Lun | 75089 | 0.53 |
| 5 | 1 Lun | 134444 | 0.95 |
| 6 | 1 Lun | 291843 | 2.07 |
| 7 | 1 Lun | 541459 | 3.84 |
| 8 | 1 Lun | 714131 | 5.07 |
| 9 | 1 Lun | 701748 | 4.98 |
| 10 | 1 Lun | 685987 | 4.87 |
| 11 | 1 Lun | 714556 | 5.07 |
| 12 | 1 Lun | 769985 | 5.46 |
| 13 | 1 Lun | 799142 | 5.67 |
| 14 | 1 Lun | 877691 | 6.23 |
| 15 | 1 Lun | 917569 | 6.51 |
| 16 | 1 Lun | 877118 | 6.22 |
| 17 | 1 Lun | 970963 | 6.89 |
| 18 | 1 Lun | 976414 | 6.93 |
| 19 | 1 Lun | 827412 | 5.87 |
| 20 | 1 Lun | 817741 | 5.8 |
| 21 | 1 Lun | 810490 | 5.75 |
| 22 | 1 Lun | 645845 | 4.58 |
| 23 | 1 Lun | 412950 | 2.93 |
| 0 | 2 Mar | 230736 | 1.43 |
| 1 | 2 Mar | 104557 | 0.65 |
| 2 | 2 Mar | 53125 | 0.33 |
| 3 | 2 Mar | 35168 | 0.22 |
| 4 | 2 Mar | 49167 | 0.3 |
| 5 | 2 Mar | 116326 | 0.72 |
| 6 | 2 Mar | 291179 | 1.8 |
| 7 | 2 Mar | 599023 | 3.71 |
| 8 | 2 Mar | 818412 | 5.07 |
| 9 | 2 Mar | 813146 | 5.04 |
| 10 | 2 Mar | 772664 | 4.79 |
| 11 | 2 Mar | 793097 | 4.92 |
| 12 | 2 Mar | 842848 | 5.22 |
| 13 | 2 Mar | 865026 | 5.36 |
| 14 | 2 Mar | 949007 | 5.88 |
| 15 | 2 Mar | 991235 | 6.14 |

_Se muestran 40 de 168 filas; el resto esta en el notebook 07._

**Interpretacion:** De lunes a viernes hay un pico matutino a las 8 h (5 % de los viajes del dia) y el maximo entre las 17 y 18 h (7 %). Sabado y domingo no tienen pico matutino y concentran viajes en la madrugada: el domingo entre 0 y 2 h ocurre 15 % de sus viajes, frente a 2 % del martes, porque recoge la salida nocturna del sabado. Jueves a sabado mantienen demanda alta hasta las 23 h.

### 10. Peaje de congestion del centro de Manhattan

**Pregunta:** Que proporcion de viajes paga el peaje de congestion del centro y cuanto recauda por mes?

**Justificacion:** El peaje (cbd_congestion_fee) empezo en enero de 2025; comparar anios muestra el efecto de la politica en los viajes de taxi.

**Indicador:** Porcentaje de viajes con cbd_congestion_fee > 0 y recaudacion mensual (USD) por tipo de taxi.

**Visualizacion:** grafico `line` con `fecha, tipo_taxi` como ejes y `pct_viajes_con_cargo` como valores.

```sql
SELECT make_date(anio, mes, 1) AS fecha,
       tipo_taxi,
       count(*) AS viajes,
       round(100.0 * avg(CASE WHEN cbd_congestion_fee > 0 THEN 1 ELSE 0 END), 2) AS pct_viajes_con_cargo,
       round(sum(cbd_congestion_fee), 2) AS recaudacion_usd
FROM viajes
WHERE year(pickup_datetime) = anio
GROUP BY ALL
ORDER BY fecha, tipo_taxi;
```

| fecha | tipo_taxi | viajes | pct_viajes_con_cargo | recaudacion_usd |
| --- | --- | --- | --- | --- |
| 2024-01-01 | green | 56549 | 0 | 0 |
| 2024-01-01 | yellow | 2964609 | 0 | 0 |
| 2024-02-01 | green | 53577 | 0 | 0 |
| 2024-02-01 | yellow | 3007524 | 0 | 0 |
| 2024-03-01 | green | 57455 | 0 | 0 |
| 2024-03-01 | yellow | 3582626 | 0 | 0 |
| 2024-04-01 | green | 56471 | 0 | 0 |
| 2024-04-01 | yellow | 3514285 | 0 | 0 |
| 2024-05-01 | green | 61001 | 0 | 0 |
| 2024-05-01 | yellow | 3723826 | 0 | 0 |
| 2024-06-01 | green | 54748 | 0 | 0 |
| 2024-06-01 | yellow | 3539187 | 0 | 0 |
| 2024-07-01 | green | 51837 | 0 | 0 |
| 2024-07-01 | yellow | 3076900 | 0 | 0 |
| 2024-08-01 | green | 51771 | 0 | 0 |
| 2024-08-01 | yellow | 2979181 | 0 | 0 |
| 2024-09-01 | green | 54439 | 0 | 0 |
| 2024-09-01 | yellow | 3633027 | 0 | 0 |
| 2024-10-01 | green | 56147 | 0 | 0 |
| 2024-10-01 | yellow | 3833770 | 0 | 0 |
| 2024-11-01 | green | 52222 | 0 | 0 |
| 2024-11-01 | yellow | 3646366 | 0 | 0 |
| 2024-12-01 | green | 53981 | 0 | 0 |
| 2024-12-01 | yellow | 3668363 | 0 | 0 |
| 2025-01-01 | green | 48320 | 6.84 | 2480.25 |
| 2025-01-01 | yellow | 3475205 | 64.64 | 1.67996e+06 |
| 2025-02-01 | green | 46621 | 8.26 | 2888.25 |
| 2025-02-01 | yellow | 3577543 | 72.68 | 1.92228e+06 |
| 2025-03-01 | green | 51539 | 9.37 | 3620.25 |
| 2025-03-01 | yellow | 4145255 | 72.66 | 2.22363e+06 |
| 2025-04-01 | green | 52132 | 9.75 | 3809.25 |
| 2025-04-01 | yellow | 3970553 | 72.26 | 2.11379e+06 |
| 2025-05-01 | green | 55399 | 9.97 | 4140.75 |
| 2025-05-01 | yellow | 4591844 | 71.53 | 2.42391e+06 |
| 2025-06-01 | green | 49390 | 9.94 | 3681.75 |
| 2025-06-01 | yellow | 4322960 | 72.25 | 2.30514e+06 |
| 2025-07-01 | green | 48205 | 9.61 | 3473.25 |
| 2025-07-01 | yellow | 3898962 | 72.73 | 2.08847e+06 |
| 2025-08-01 | green | 46306 | 10.49 | 3641.25 |
| 2025-08-01 | yellow | 3574090 | 71.93 | 1.88952e+06 |

_Se muestran 40 de 64 filas; el resto esta en el notebook 07._

**Interpretacion:** El peaje no existe en 2024 (0 %) y aparece en enero de 2025, cuando ya lo paga el 64.6 % de los viajes Yellow (empezo el 5 de enero); desde febrero de 2025 se estabiliza en 71-73 % y en julio-agosto de 2026 sube a 77 %. Recauda en Yellow entre USD 1.7 y 2.4 millones por mes. En Green solo lo paga 7-10 % de los viajes (unos USD 2-4 mil por mes), coherente con que opera principalmente fuera del centro de Manhattan.
