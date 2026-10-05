# Ejercicio 4 - Analisis exploratorio con DuckDB

Documento reproducible generado por `scripts/run_eda.py` sobre los Parquet de 2026.
Cada seccion explicita la pregunta, su justificacion, la consulta y la interpretacion.

## Criterio de analisis

Se conservan los registros originales. Cuando una metrica exige viajes plausibles,
la consulta aplica y muestra sus filtros. Yellow y Green se normalizan solo dentro
de cada consulta porque sus columnas de fecha tienen nombres diferentes.

## Evolucion mensual de la demanda

**Pregunta:** Como cambia la cantidad de viajes y la facturacion mensual por tipo de taxi?

**Justificacion:** Permite detectar estacionalidad y comprobar si los dos servicios evolucionan de forma similar.

**Fuente:** Archivos Parquet Yellow y Green Taxi de 2026.

```sql
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
```

| tipo_taxi | mes | viajes | viajes_por_dia | monto_total |
| --- | --- | --- | --- | --- |
| green | 1 | 40258 | 1298.6 | 975385 |
| yellow | 1 | 3724894 | 120158 | 1.099e+08 |
| green | 2 | 37388 | 1335.3 | 908060 |
| yellow | 2 | 3399866 | 121424 | 1.03185e+08 |
| green | 3 | 44203 | 1425.9 | 1.10263e+06 |
| yellow | 3 | 3952443 | 127498 | 1.19557e+08 |
| green | 4 | 44243 | 1474.8 | 1.12617e+06 |
| yellow | 4 | 3831256 | 127708 | 1.15359e+08 |
| green | 5 | 44925 | 1449.2 | 1.16689e+06 |
| yellow | 5 | 4090824 | 131962 | 1.25127e+08 |
| green | 6 | 44156 | 1471.9 | 1.16147e+06 |
| yellow | 6 | 3837239 | 127908 | 1.17511e+08 |
| green | 7 | 41249 | 1330.6 | 1.084e+06 |
| yellow | 7 | 3530077 | 113874 | 1.06494e+08 |
| green | 8 | 40678 | 1312.2 | 1.08303e+06 |
| yellow | 8 | 3336739 | 107637 | 1.00781e+08 |

**Interpretacion:** Los meses deben compararse tambien por promedio diario porque agosto es el ultimo mes disponible al ejecutar este analisis.

## Patron por hora y tipo de dia

**Pregunta:** En que horas se concentra la demanda entre dias laborales y fines de semana?

**Justificacion:** La hora y el tipo de dia muestran patrones operativos que el total mensual oculta.

**Fuente:** Archivos Parquet Yellow y Green Taxi de 2026.

```sql
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
```

| tipo_taxi | tipo_dia | hora | viajes | porcentaje |
| --- | --- | --- | --- | --- |
| green | fin_semana | 0 | 2435 | 3.07 |
| green | fin_semana | 1 | 1813 | 2.28 |
| green | fin_semana | 2 | 1548 | 1.95 |
| green | fin_semana | 3 | 1430 | 1.8 |
| green | fin_semana | 4 | 1136 | 1.43 |
| green | fin_semana | 5 | 680 | 0.86 |
| green | fin_semana | 6 | 722 | 0.91 |
| green | fin_semana | 7 | 1324 | 1.67 |
| green | fin_semana | 8 | 1837 | 2.32 |
| green | fin_semana | 9 | 2925 | 3.69 |
| green | fin_semana | 10 | 3471 | 4.37 |
| green | fin_semana | 11 | 4121 | 5.19 |
| green | fin_semana | 12 | 4940 | 6.23 |
| green | fin_semana | 13 | 4979 | 6.28 |
| green | fin_semana | 14 | 5325 | 6.71 |
| green | fin_semana | 15 | 5585 | 7.04 |
| green | fin_semana | 16 | 5657 | 7.13 |
| green | fin_semana | 17 | 5418 | 6.83 |
| green | fin_semana | 18 | 5724 | 7.21 |
| green | fin_semana | 19 | 4813 | 6.07 |
| green | fin_semana | 20 | 4015 | 5.06 |
| green | fin_semana | 21 | 3581 | 4.51 |
| green | fin_semana | 22 | 3189 | 4.02 |
| green | fin_semana | 23 | 2676 | 3.37 |
| green | laboral | 0 | 2860 | 1.11 |
| green | laboral | 1 | 1561 | 0.61 |
| green | laboral | 2 | 911 | 0.35 |
| green | laboral | 3 | 613 | 0.24 |
| green | laboral | 4 | 921 | 0.36 |
| green | laboral | 5 | 1975 | 0.77 |
| green | laboral | 6 | 6090 | 2.36 |
| green | laboral | 7 | 12892 | 5 |
| green | laboral | 8 | 16074 | 6.24 |
| green | laboral | 9 | 15896 | 6.17 |
| green | laboral | 10 | 14825 | 5.75 |
| green | laboral | 11 | 14115 | 5.48 |
| green | laboral | 12 | 14767 | 5.73 |
| green | laboral | 13 | 14362 | 5.57 |
| green | laboral | 14 | 16279 | 6.32 |
| green | laboral | 15 | 17809 | 6.91 |
| green | laboral | 16 | 19671 | 7.63 |
| green | laboral | 17 | 20815 | 8.08 |
| green | laboral | 18 | 18990 | 7.37 |
| green | laboral | 19 | 13742 | 5.33 |
| green | laboral | 20 | 10241 | 3.97 |
| green | laboral | 21 | 9125 | 3.54 |
| green | laboral | 22 | 7844 | 3.04 |
| green | laboral | 23 | 5378 | 2.09 |
| yellow | fin_semana | 0 | 494860 | 5.83 |
| yellow | fin_semana | 1 | 390208 | 4.59 |
| yellow | fin_semana | 2 | 282825 | 3.33 |
| yellow | fin_semana | 3 | 206688 | 2.43 |
| yellow | fin_semana | 4 | 138391 | 1.63 |
| yellow | fin_semana | 5 | 71291 | 0.84 |
| yellow | fin_semana | 6 | 90011 | 1.06 |
| yellow | fin_semana | 7 | 115693 | 1.36 |
| yellow | fin_semana | 8 | 167972 | 1.98 |
| yellow | fin_semana | 9 | 255612 | 3.01 |
| yellow | fin_semana | 10 | 325845 | 3.84 |
| yellow | fin_semana | 11 | 387482 | 4.56 |
| yellow | fin_semana | 12 | 435155 | 5.12 |
| yellow | fin_semana | 13 | 464861 | 5.47 |
| yellow | fin_semana | 14 | 474988 | 5.59 |
| yellow | fin_semana | 15 | 471249 | 5.55 |
| yellow | fin_semana | 16 | 488618 | 5.75 |
| yellow | fin_semana | 17 | 507339 | 5.97 |
| yellow | fin_semana | 18 | 526883 | 6.2 |
| yellow | fin_semana | 19 | 490471 | 5.77 |
| yellow | fin_semana | 20 | 433719 | 5.11 |
| yellow | fin_semana | 21 | 427535 | 5.03 |
| yellow | fin_semana | 22 | 438157 | 5.16 |
| yellow | fin_semana | 23 | 408402 | 4.81 |
| yellow | laboral | 0 | 438739 | 2.07 |
| yellow | laboral | 1 | 231563 | 1.09 |
| yellow | laboral | 2 | 132371 | 0.62 |
| yellow | laboral | 3 | 92188 | 0.43 |
| yellow | laboral | 4 | 106647 | 0.5 |
| yellow | laboral | 5 | 198649 | 0.94 |
| yellow | laboral | 6 | 414465 | 1.95 |
| yellow | laboral | 7 | 764305 | 3.6 |
| yellow | laboral | 8 | 1014616 | 4.78 |
| yellow | laboral | 9 | 986220 | 4.65 |
| yellow | laboral | 10 | 932839 | 4.4 |
| yellow | laboral | 11 | 970577 | 4.58 |
| yellow | laboral | 12 | 1034221 | 4.88 |
| yellow | laboral | 13 | 1072851 | 5.06 |
| yellow | laboral | 14 | 1192305 | 5.62 |
| yellow | laboral | 15 | 1253580 | 5.91 |
| yellow | laboral | 16 | 1285752 | 6.06 |
| yellow | laboral | 17 | 1490442 | 7.03 |
| yellow | laboral | 18 | 1564120 | 7.37 |
| yellow | laboral | 19 | 1350426 | 6.37 |
| yellow | laboral | 20 | 1265536 | 5.97 |
| yellow | laboral | 21 | 1331813 | 6.28 |
| yellow | laboral | 22 | 1194525 | 5.63 |
| yellow | laboral | 23 | 890333 | 4.2 |

**Interpretacion:** Se reporta la participacion dentro de cada tipo de taxi para hacer comparables sus escalas muy diferentes.

## Caracteristicas de los viajes por tipo de taxi

**Pregunta:** Que diferencias existen en distancia, duracion, pasajeros y monto entre Yellow y Green Taxi?

**Justificacion:** Resume las variables operativas principales usando solo viajes plausibles.

**Fuente:** Archivos Parquet Yellow y Green Taxi de 2026.

```sql
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
```

| tipo_taxi | viajes_validos | distancia_media | distancia_mediana | duracion_media_min | duracion_mediana_min | pasajeros_promedio | monto_promedio | monto_mediano |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| green | 324331 | 13.87 | 2.15 | 21.27 | 13.35 | 1.3 | 25.55 | 20.52 |
| yellow | 28604878 | 5.75 | 1.92 | 17.75 | 13.95 | 1.25 | 30.2 | 23.58 |

**Interpretacion:** La media se acompana con la mediana para reducir el efecto de valores extremos.

## Distribucion de formas de pago

**Pregunta:** Que formas de pago utiliza cada tipo de taxi y que proporcion representan?

**Justificacion:** El metodo de pago condiciona variables como la propina registrada.

**Fuente:** Archivos Parquet Yellow y Green Taxi de 2026.

```sql
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
```

| tipo_taxi | forma_pago | viajes | porcentaje |
| --- | --- | --- | --- |
| green | tarjeta | 219980 | 65.25 |
| green | efectivo | 65921 | 19.55 |
| green | no_informado | 48775 | 14.47 |
| green | sin_cargo | 1688 | 0.5 |
| green | disputa | 750 | 0.22 |
| yellow | tarjeta | 18941008 | 63.77 |
| yellow | no_informado | 7716688 | 25.98 |
| yellow | efectivo | 2708031 | 9.12 |
| yellow | disputa | 239488 | 0.81 |
| yellow | sin_cargo | 98138 | 0.33 |
| yellow | desconocido | 2 | 0 |

**Interpretacion:** Los codigos siguen el diccionario TLC; NULL y 0 se conservan como no informados.

## Propinas en pagos con tarjeta

**Pregunta:** Como difiere la propina registrada entre Yellow y Green Taxi en pagos con tarjeta?

**Justificacion:** TLC solo registra automaticamente la propina de tarjeta, por lo que restringir el metodo evita una comparacion sesgada.

**Fuente:** Archivos Parquet Yellow y Green Taxi de 2026.

```sql
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
```

| tipo_taxi | pagos_tarjeta | propina_promedio | propina_mediana | pct_con_propina | propina_sobre_tarifa_pct |
| --- | --- | --- | --- | --- | --- |
| green | 219842 | 3.84 | 3.08 | 90.45 | 20.93 |
| yellow | 18937340 | 4.28 | 3.29 | 91.1 | 21.53 |

**Interpretacion:** La tasa usa fare_amount positivo como denominador y excluye importes negativos.

## Percentiles de distancia, duracion y monto

**Pregunta:** Cual es la distribucion de los valores relevantes y cuanto se aleja la cola superior del viaje tipico?

**Justificacion:** Los percentiles describen distribuciones asimetricas mejor que unicamente el promedio.

**Fuente:** Archivos Parquet Yellow y Green Taxi de 2026.

```sql
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
```

| tipo_taxi | variable | p50 | p90 | p95 | p99 | maximo |
| --- | --- | --- | --- | --- | --- | --- |
| green | distancia_millas | 2.15 | 7.55 | 10.69 | 17.91 | 179831 |
| green | duracion_min | 13.35 | 33.13 | 45.35 | 84.05 | 1638.28 |
| green | monto_usd | 20.54 | 44.88 | 56.98 | 96.19 | 1678.2 |
| yellow | distancia_millas | 1.93 | 8.67 | 12.64 | 19.62 | 328522 |
| yellow | duracion_min | 13.96 | 33.31 | 44 | 71.65 | 17165.4 |
| yellow | monto_usd | 23.57 | 54.6 | 77.29 | 105.1 | 7053.5 |

**Interpretacion:** P99 no define por si mismo un error, pero permite fijar umbrales de revision con evidencia.

## Valores atipicos e inconsistencias

**Pregunta:** Cuantos registros presentan valores imposibles o extremos que requieren revision?

**Justificacion:** Cuantificar cada regla evita eliminar datos silenciosamente y muestra su impacto por servicio.

**Fuente:** Archivos Parquet Yellow y Green Taxi de 2026.

```sql
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
```

| tipo_taxi | registros | duracion_negativa | duracion_mayor_6h | distancia_no_positiva | distancia_mayor_100mi | pasajeros_no_positivos | pasajeros_mayor_8 | tarifa_negativa | total_negativo | total_mayor_500 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| green | 337100 | 5 | 1089 | 12208 | 72 | 4527 | 31 | 999 | 1023 | 21 |
| yellow | 29703338 | 10 | 7101 | 952231 | 1223 | 91359 | 6 | 157363 | 161834 | 791 |

**Interpretacion:** Los umbrales de 100 millas, 6 horas y USD 500 son banderas de revision, no pruebas automaticas de error.

## Rutas mas frecuentes

**Pregunta:** Cuales son los pares de zonas de origen y destino con mayor volumen en cada servicio?

**Justificacion:** Las rutas frecuentes describen la geografia operativa sin requerir cargar geometria espacial.

**Fuente:** Archivos Parquet Yellow y Green Taxi de 2026.

```sql
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
```

| tipo_taxi | origen | destino | viajes |
| --- | --- | --- | --- |
| green | 74 | 75 | 14016 |
| green | 74 | 236 | 10323 |
| green | 75 | 74 | 7367 |
| green | 74 | 166 | 6150 |
| green | 95 | 95 | 5473 |
| green | 74 | 263 | 5171 |
| green | 74 | 238 | 5138 |
| green | 74 | 41 | 4715 |
| green | 74 | 74 | 4222 |
| green | 74 | 42 | 3890 |
| yellow | 237 | 236 | 186524 |
| yellow | 236 | 237 | 159254 |
| yellow | 237 | 237 | 130529 |
| yellow | 236 | 236 | 122664 |
| yellow | 161 | 237 | 86401 |
| yellow | 237 | 161 | 80884 |
| yellow | 161 | 236 | 70343 |
| yellow | 237 | 162 | 66623 |
| yellow | 142 | 239 | 65952 |
| yellow | 239 | 238 | 65216 |

**Interpretacion:** Se muestran identificadores TLC de zona; pueden unirse posteriormente al Taxi Zone Lookup.

## Hallazgos relevantes

- La mayor demanda diaria de Yellow ocurre en el mes 5: 131,962.1 viajes por dia.
- La mayor demanda diaria de Green ocurre en el mes 4: 1,474.8 viajes por dia.
- En dias laborales, la hora pico de Yellow es las 18:00 (7.37% de sus viajes laborales).
- En dias laborales, la hora pico de Green es las 17:00 (8.08% de sus viajes laborales).
- El viaje mediano de Yellow recorre 1.92 millas y cuesta USD 23.58; en Green las medianas son 2.15 millas y USD 20.52.
- En pagos con tarjeta de Green, 90.45% registra propina y la mediana es USD 3.08.
- En pagos con tarjeta de Yellow, 91.10% registra propina y la mediana es USD 3.29.
- En Yellow, la categoria de pago mas frecuente es tarjeta (63.77% de los viajes).
- En Green, la categoria de pago mas frecuente es tarjeta (65.25% de los viajes).
- La calidad requiere filtros explicitos: 964,439 de 30,040,438 registros tienen distancia no positiva y 162,857 tienen monto total negativo.

Los hallazgos son regenerados a partir de los datos disponibles y no estan escritos
como constantes. Por eso pueden cambiar cuando la TLC publique o se incorpore otro mes.
