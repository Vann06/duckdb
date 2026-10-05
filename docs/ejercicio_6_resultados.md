# Ejercicio 6 - Parquet versus tablas DuckDB

La tabla se materializo en 58.195 s. Cada combinacion se ejecuto 2 veces;
se registra por separado la primera ejecucion y la mediana de las restantes.

## Resultados

| escenario | registros | consulta | fuente | primera_s | mediana_s | filas_resultado |
| --- | --- | --- | --- | --- | --- | --- |
| 2024 | 41829938 | 01_resumen_mensual | parquet | 4.68022 | 2.76292 | 24 |
| 2024 | 41829938 | 01_resumen_mensual | duckdb | 3.40062 | 1.02793 | 24 |
| 2024 | 41829938 | 02_distribucion_pago | parquet | 0.853827 | 0.867064 | 12 |
| 2024 | 41829938 | 02_distribucion_pago | duckdb | 0.764309 | 0.686316 | 12 |
| 2024 | 41829938 | 03_rutas_principales | parquet | 1.08374 | 0.933616 | 40 |
| 2024 | 41829938 | 03_rutas_principales | duckdb | 0.848408 | 0.752428 | 40 |
| 2026 | 30040469 | 01_resumen_mensual | parquet | 1.49494 | 1.28424 | 18 |
| 2026 | 30040469 | 01_resumen_mensual | duckdb | 0.684602 | 0.623734 | 18 |
| 2026 | 30040469 | 02_distribucion_pago | parquet | 0.766217 | 0.626485 | 11 |
| 2026 | 30040469 | 02_distribucion_pago | duckdb | 1.10073 | 0.53543 | 11 |
| 2026 | 30040469 | 03_rutas_principales | parquet | 1.00494 | 0.764737 | 40 |
| 2026 | 30040469 | 03_rutas_principales | duckdb | 0.632761 | 0.624936 | 40 |
| 2024+2026 | 71870407 | 01_resumen_mensual | parquet | 6.31035 | 2.84032 | 42 |
| 2024+2026 | 71870407 | 01_resumen_mensual | duckdb | 1.93404 | 1.8407 | 42 |
| 2024+2026 | 71870407 | 02_distribucion_pago | parquet | 1.41115 | 1.36981 | 23 |
| 2024+2026 | 71870407 | 02_distribucion_pago | duckdb | 1.28883 | 1.32537 | 23 |
| 2024+2026 | 71870407 | 03_rutas_principales | parquet | 1.74695 | 2.0013 | 80 |
| 2024+2026 | 71870407 | 03_rutas_principales | duckdb | 1.80302 | 1.6401 | 80 |

## Consultas utilizadas

### Resumen mensual

Medir una agregacion temporal con conteo, promedio y suma.

```sql
SELECT anio, month(pickup_datetime) AS mes, tipo_taxi, count(*) AS viajes,
       avg(trip_distance) AS distancia_media, sum(total_amount) AS monto_total
FROM {source}
WHERE {year_filter}
GROUP BY anio, mes, tipo_taxi
ORDER BY anio, mes, tipo_taxi;
```

### Distribucion de pagos

Medir una agrupacion de baja cardinalidad sobre varias columnas.

```sql
SELECT anio, tipo_taxi, payment_type, count(*) AS viajes,
       avg(fare_amount) AS tarifa_media, avg(tip_amount) AS propina_media
FROM {source}
WHERE {year_filter}
GROUP BY anio, tipo_taxi, payment_type
ORDER BY anio, tipo_taxi, viajes DESC;
```

### Rutas principales

Medir una agrupacion de mayor cardinalidad y un ranking por ventana.

```sql
WITH rutas AS (
    SELECT anio, tipo_taxi, pickup_location_id, dropoff_location_id, count(*) AS viajes
    FROM {source}
    WHERE {year_filter}
    GROUP BY ALL
)
SELECT * FROM rutas
QUALIFY row_number() OVER (PARTITION BY anio, tipo_taxi ORDER BY viajes DESC) <= 20
ORDER BY anio, tipo_taxi, viajes DESC;
```

## Analisis

En la mediana de las combinaciones medidas, Parquet tardo 1.24 veces el tiempo de la tabla DuckDB.
La tabla evita interpretar multiples archivos y sus metadatos en cada consulta, pero exige tiempo y
espacio adicional para materializarse. La primera ejecucion puede incluir calentamiento de paginas y
metadatos; por eso no se mezcla con la mediana de repeticiones posteriores.

Consultar Parquet directamente es apropiado para datos que llegan como archivos, exploraciones
ocasionales, seleccion de pocas columnas y flujos donde se quiere evitar duplicar almacenamiento.
Materializar conviene cuando las mismas transformaciones y consultas se repiten, se necesita un esquema
estable o el costo de preparacion se amortiza entre muchos usuarios. El benchmark no incluye el tiempo
de materializacion dentro de cada consulta; debe considerarse por separado al tomar la decision.
