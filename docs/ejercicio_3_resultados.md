# Ejercicio 3 - Exploracion inicial con DuckDB


## Cantidad de archivos disponibles

**Identificador:** `01_cantidad_archivos`

**Objetivo:** Verificar cuantos archivos Parquet de 2026 existen para cada tipo de taxi.

**Fuente:** data/raw/yellow/2026/*.parquet y data/raw/green/2026/*.parquet

**Consulta SQL:**

```sql
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
```

**Resultado:**

| tipo_taxi | cantidad_archivos | primer_mes | ultimo_mes |
| --- | --- | --- | --- |
| green | 8 | 01 | 08 |
| total | 16 | 01 | 08 |
| yellow | 8 | 01 | 08 |


## Cantidad de registros disponibles

**Identificador:** `02_cantidad_registros`

**Objetivo:** Contar los viajes disponibles por tipo de taxi y en total.

**Fuente:** Todos los archivos Parquet de taxis amarillos y verdes de 2026.

**Consulta SQL:**

```sql
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
```

**Resultado:**

| tipo_taxi | cantidad_registros |
| --- | --- |
| green | 337114 |
| yellow | 29703355 |
| total | 30040469 |

**Decision:** Usar union_by_name porque los dos tipos de taxi no poseen exactamente el mismo esquema.

## Registros por archivo mensual

**Identificador:** `03_registros_por_archivo`

**Objetivo:** Confirmar que cada archivo puede leerse y conocer su aporte al total.

**Fuente:** Todos los archivos Parquet de taxis amarillos y verdes de 2026.

**Consulta SQL:**

```sql
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
```

**Resultado:**

| tipo_taxi | archivo | cantidad_registros |
| --- | --- | --- |
| green | green_tripdata_2026-01.parquet | 40272 |
| green | green_tripdata_2026-02.parquet | 37373 |
| green | green_tripdata_2026-03.parquet | 44208 |
| green | green_tripdata_2026-04.parquet | 44238 |
| green | green_tripdata_2026-05.parquet | 44921 |
| green | green_tripdata_2026-06.parquet | 44163 |
| green | green_tripdata_2026-07.parquet | 41252 |
| green | green_tripdata_2026-08.parquet | 40687 |
| yellow | yellow_tripdata_2026-01.parquet | 3724889 |
| yellow | yellow_tripdata_2026-02.parquet | 3399866 |
| yellow | yellow_tripdata_2026-03.parquet | 3952451 |
| yellow | yellow_tripdata_2026-04.parquet | 3831240 |
| yellow | yellow_tripdata_2026-05.parquet | 4090836 |
| yellow | yellow_tripdata_2026-06.parquet | 3837248 |
| yellow | yellow_tripdata_2026-07.parquet | 3530109 |
| yellow | yellow_tripdata_2026-08.parquet | 3336716 |

**Decision:** Mantener el nombre del archivo en los resultados para facilitar la deteccion de meses vacios o atipicos.

## Columnas y tipos de datos de Yellow Taxi

**Identificador:** `04_esquema_yellow`

**Objetivo:** Identificar el esquema inferido por DuckDB para los archivos de taxis amarillos.

**Fuente:** data/raw/yellow/2026/*.parquet

**Consulta SQL:**

```sql
DESCRIBE
SELECT *
FROM read_parquet(
    'data/raw/yellow/2026/*.parquet',
    union_by_name = true
);
```

**Resultado:**

| column_name | column_type | null | key | default | extra |
| --- | --- | --- | --- | --- | --- |
| VendorID | INTEGER | YES | NULL | NULL | NULL |
| tpep_pickup_datetime | TIMESTAMP | YES | NULL | NULL | NULL |
| tpep_dropoff_datetime | TIMESTAMP | YES | NULL | NULL | NULL |
| passenger_count | BIGINT | YES | NULL | NULL | NULL |
| trip_distance | DOUBLE | YES | NULL | NULL | NULL |
| RatecodeID | BIGINT | YES | NULL | NULL | NULL |
| store_and_fwd_flag | VARCHAR | YES | NULL | NULL | NULL |
| PULocationID | INTEGER | YES | NULL | NULL | NULL |
| DOLocationID | INTEGER | YES | NULL | NULL | NULL |
| payment_type | BIGINT | YES | NULL | NULL | NULL |
| fare_amount | DOUBLE | YES | NULL | NULL | NULL |
| extra | DOUBLE | YES | NULL | NULL | NULL |
| mta_tax | DOUBLE | YES | NULL | NULL | NULL |
| tip_amount | DOUBLE | YES | NULL | NULL | NULL |
| tolls_amount | DOUBLE | YES | NULL | NULL | NULL |
| improvement_surcharge | DOUBLE | YES | NULL | NULL | NULL |
| total_amount | DOUBLE | YES | NULL | NULL | NULL |
| congestion_surcharge | DOUBLE | YES | NULL | NULL | NULL |
| Airport_fee | DOUBLE | YES | NULL | NULL | NULL |
| cbd_congestion_fee | DOUBLE | YES | NULL | NULL | NULL |
| request_source | VARCHAR | YES | NULL | NULL | NULL |

**Decision:** Conservar los nombres originales y normalizar solamente en consultas que combinen tipos de taxi.

## Columnas y tipos de datos de Green Taxi

**Identificador:** `05_esquema_green`

**Objetivo:** Identificar el esquema inferido por DuckDB para los archivos de taxis verdes.

**Fuente:** data/raw/green/2026/*.parquet

**Consulta SQL:**

```sql
DESCRIBE
SELECT *
FROM read_parquet(
    'data/raw/green/2026/*.parquet',
    union_by_name = true
);
```

**Resultado:**

| column_name | column_type | null | key | default | extra |
| --- | --- | --- | --- | --- | --- |
| VendorID | INTEGER | YES | NULL | NULL | NULL |
| lpep_pickup_datetime | TIMESTAMP | YES | NULL | NULL | NULL |
| lpep_dropoff_datetime | TIMESTAMP | YES | NULL | NULL | NULL |
| store_and_fwd_flag | VARCHAR | YES | NULL | NULL | NULL |
| RatecodeID | BIGINT | YES | NULL | NULL | NULL |
| PULocationID | INTEGER | YES | NULL | NULL | NULL |
| DOLocationID | INTEGER | YES | NULL | NULL | NULL |
| passenger_count | BIGINT | YES | NULL | NULL | NULL |
| trip_distance | DOUBLE | YES | NULL | NULL | NULL |
| fare_amount | DOUBLE | YES | NULL | NULL | NULL |
| extra | DOUBLE | YES | NULL | NULL | NULL |
| mta_tax | DOUBLE | YES | NULL | NULL | NULL |
| tip_amount | DOUBLE | YES | NULL | NULL | NULL |
| tolls_amount | DOUBLE | YES | NULL | NULL | NULL |
| ehail_fee | DOUBLE | YES | NULL | NULL | NULL |
| improvement_surcharge | DOUBLE | YES | NULL | NULL | NULL |
| total_amount | DOUBLE | YES | NULL | NULL | NULL |
| payment_type | BIGINT | YES | NULL | NULL | NULL |
| trip_type | BIGINT | YES | NULL | NULL | NULL |
| congestion_surcharge | DOUBLE | YES | NULL | NULL | NULL |
| cbd_congestion_fee | DOUBLE | YES | NULL | NULL | NULL |
| request_source | VARCHAR | YES | NULL | NULL | NULL |

**Decision:** Usar lpep_pickup_datetime y lpep_dropoff_datetime para Green Taxi, en lugar de asumir los nombres de Yellow Taxi.

## Muestra de registros

**Identificador:** `06_muestra_registros`

**Objetivo:** Observar valores representativos de ambos tipos de taxi con columnas comparables.

**Fuente:** Todos los archivos Parquet de taxis amarillos y verdes de 2026.

**Consulta SQL:**

```sql
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
```

**Resultado:**

| tipo_taxi | pickup_datetime | dropoff_datetime | passenger_count | trip_distance | fare_amount | total_amount | payment_type |
| --- | --- | --- | --- | --- | --- | --- | --- |
| green | 2026-01-01 00:03:27 | 2026-01-01 00:48:45 | NULL | 23.58 | 2.9 | 57.95 | NULL |
| green | 2026-01-01 00:04:26 | 2026-01-01 00:26:02 | 1 | 4.79 | 26.1 | 28.6 | 1 |
| green | 2026-01-01 00:08:25 | 2026-01-01 00:18:15 | 1 | 1.35 | 11.4 | 19.98 | 1 |
| green | 2026-01-01 00:08:56 | 2026-01-01 00:40:38 | 1 | 15.07 | 60.4 | 62.9 | 2 |
| green | 2026-01-01 00:09:37 | 2026-01-01 00:19:42 | 1 | 2.47 | 13.5 | 19.2 | 1 |
| yellow | 2026-01-01 00:00:00 | 2026-01-01 00:16:00 | NULL | 4.38 | 22.39 | 32.57 | 0 |
| yellow | 2026-01-01 00:00:02 | 2026-01-01 01:34:24 | 2 | 2.8 | 51.3 | 57.05 | 4 |
| yellow | 2026-01-01 00:00:09 | 2026-01-01 00:11:24 | 1 | 3.7 | 18.4 | 39.15 | 1 |
| yellow | 2026-01-01 00:00:10 | 2026-01-01 00:25:57 | 3 | 2.93 | 22.6 | 32.35 | 1 |
| yellow | 2026-01-01 00:00:11 | 2026-01-01 00:13:33 | NULL | 2.46 | 14.83 | 18.83 | 0 |

**Decision:** Unificar los nombres de las fechas solo en la salida analitica y conservar los archivos originales sin modificaciones.

## Revision inicial de calidad de datos

**Identificador:** `07_calidad_datos`

**Objetivo:** Cuantificar valores nulos, fechas inconsistentes y valores no plausibles antes del analisis exploratorio.

**Fuente:** Todos los archivos Parquet de taxis amarillos y verdes de 2026.

**Consulta SQL:**

```sql
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
```

**Resultado:**

| tipo_taxi | registros | pickup_nulo | dropoff_nulo | pickup_fuera_2026 | duracion_negativa | pasajeros_nulos | pasajeros_no_positivos | distancia_nula | distancia_no_positiva | tarifa_negativa | total_negativo |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| green | 337114 | 0 | 0 | 14 | 5 | 48775 | 4527 | 0 | 12212 | 999 | 1023 |
| yellow | 29703355 | 0 | 0 | 17 | 10 | 7716688 | 91359 | 0 | 952231 | 157364 | 161835 |

**Decision:** No eliminar automaticamente registros; documentar los problemas y aplicar filtros explicitos segun la pregunta analitica.

## Interpretacion inicial

Los conteos anteriores validan la cobertura de archivos y registros.
Las tablas de esquema muestran que Yellow y Green Taxi usan nombres distintos
para las fechas (`tpep_*` y `lpep_*`) y que Green Taxi contiene campos propios.

La revision inicial encontro los siguientes problemas que deben considerarse
antes de responder preguntas analiticas:

- 31 registros tienen una fecha de inicio fuera de 2026.
- 15 registros tienen una fecha de fin anterior al inicio.
- 7,765,463 registros no informan la cantidad de pasajeros.
- 964,443 registros tienen distancia igual o menor que cero.
- 162,858 registros tienen un monto total negativo.

Los indicadores de calidad no implican que un registro deba eliminarse de forma
automatica: cada filtro debe justificarse segun la pregunta analitica.

Consultar Parquet directamente significa que DuckDB interpreta el esquema y lee
los archivos desde su ubicacion original, sin una importacion previa. Esta
estrategia evita duplicar datos y permite aprovechar la lectura por columnas y
el filtrado temprano, lo cual resulta util para conjuntos grandes.
