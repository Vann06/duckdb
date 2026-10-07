-- Indicadores del Ejercicio 7.
-- Se ejecutan sobre data/processed/taxi.duckdb (ver sql/05_modelo_indicadores.sql).
-- Metadatos adicionales:
--   display / dimensions / metrics: tipo de grafico y ejes que usan el notebook 07
--   y scripts/setup_metabase.py para construir la visualizacion.

-- name: 01_pasajeros_duracion
-- title: Duracion del viaje segun numero de pasajeros
-- question: Llevar mas pasajeros aumenta el tiempo de viaje?
-- justification: Si la duracion cambia con los pasajeros puede deberse a paradas extra o a que los grupos hacen viajes mas largos; por eso se reporta tambien la distancia y los minutos por milla, que aislan el efecto de la distancia.
-- indicator: Duracion mediana (min), distancia media y minutos por milla por numero de pasajeros (1 a 6).
-- display: bar
-- dimensions: pasajeros
-- metrics: duracion_mediana_min, min_por_milla
-- interpretation: Con 2024-2026 la duracion mediana sube de 12.6 min con 1 pasajero a 14.6 min con 4, pero la distancia media tambien sube (3.4 a 4.2 millas) y los minutos por milla bajan (4.89 a 4.60). Los grupos no viajan mas lento: hacen viajes mas largos. Con 5 y 6 pasajeros (vehiculos grandes) los viajes vuelven a ser cortos (12 min). No hay evidencia de que llevar mas pasajeros aumente el tiempo por si mismo.
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

-- name: 02_duracion_mensual
-- title: Duracion promedio del viaje por mes
-- question: Cuanto dura en promedio un viaje y como cambia entre meses, anios y servicios?
-- justification: La duracion (hora final menos hora inicial) resume congestion y tipo de recorrido; verla por mes permite comparar anios.
-- indicator: Duracion media y mediana (min) por mes y tipo de taxi.
-- display: line
-- dimensions: fecha, tipo_taxi
-- metrics: duracion_mediana_min
-- interpretation: La duracion mediana anual de Yellow sube de 13.1 min (2024) a 13.7 (2025) y 14.1 (2026), y Green muestra la misma tendencia (enero: 11.5, 11.3 y 13.1 min). Parte del aumento se debe a que crecen los registros sin datos del taximetro, que son viajes mas largos: en viajes con tarifa estandar (enero-agosto) la duracion mediana casi no cambia entre 2024 y 2025 (11.9 y 11.7 min) y sube en 2026 (12.2 min) porque la velocidad baja de 9.2 a 8.7 mph (ver Ejercicio 8). En 2024 y 2025 la duracion crece de enero a mayo y alcanza sus maximos entre septiembre y diciembre.
SELECT make_date(anio, mes, 1) AS fecha,
       tipo_taxi,
       count(*) AS viajes,
       round(avg(duracion_min), 2) AS duracion_media_min,
       round(median(duracion_min), 2) AS duracion_mediana_min
FROM viajes_validos
GROUP BY ALL
ORDER BY fecha, tipo_taxi;

-- name: 03_pago_tarifa
-- title: Tarifa base segun forma de pago
-- question: Con que forma de pago la tarifa base es mas alta?
-- justification: Si una forma de pago se asocia a viajes mas caros, la mezcla de pagos influye en los ingresos; la distancia media ayuda a explicar la diferencia.
-- indicator: Tarifa base media y mediana (USD) y distancia media por forma de pago y anio.
-- display: bar
-- dimensions: forma_pago, anio
-- metrics: tarifa_base_media
-- interpretation: Tarjeta y efectivo tienen practicamente la misma tarifa base en los tres anios (mediana USD 12.80-13.50): la forma de pago no determina el precio. La tarifa mas alta esta en el codigo 0 (mediana USD 18.08, 18.79 y 23.19 en 2024, 2025 y 2026), que agrupa registros sin datos del taximetro, incluidos los viajes por plataforma, que son mas largos; ademas este grupo crecio de 3.7 a 8.8 millones de viajes entre 2024 y 2025. Disputa tiene la media mas alta entre los codigos normales, pero su mediana (USD 12.80-13.50) no supera a la de tarjeta: la diferencia la producen pocos viajes caros.
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

-- name: 04_origen_solicitud
-- title: Tarifa base segun origen de la solicitud
-- question: Los viajes pedidos por plataforma (Uber, Lyft u otras) tienen una tarifa base mas alta que los demas?
-- justification: request_source existe solo en Yellow desde junio de 2026; HV0003 y HV0005 son las licencias TLC de Uber y Lyft. Se usa la tarifa por milla para separar el precio de la distancia. No se compara propina porque en viajes por plataforma no se registra (llega como 0).
-- indicator: Participacion y medianas de tarifa base, distancia, duracion y tarifa por milla por origen de solicitud.
-- display: bar
-- dimensions: origen
-- metrics: tarifa_base_mediana, tarifa_por_milla_mediana
-- interpretation: request_source solo trae datos desde junio de 2026 (en 2024 y 2025 no existe). En junio-agosto de 2026, el 26 % de los viajes Yellow llego por plataforma (Uber 20.6 %, Lyft 1.6 %, otras 3.8 %). Su tarifa base mediana es mucho mayor (Uber USD 22.98 vs USD 13.50 sin plataforma), pero porque son viajes mas largos (3.0 vs 1.7 millas): la tarifa por milla de Uber (USD 7.17) es incluso algo menor que la de los viajes sin plataforma (USD 7.53). Las medias de distancia de las plataformas estan infladas por valores extremos, por eso se usan medianas.
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

-- name: 05_propina_distancia
-- title: Propina segun distancia del viaje
-- question: Los pasajeros dejan proporcionalmente mas propina en viajes cortos o largos?
-- justification: Reemplaza la comparacion de propina por origen, que no es posible porque las plataformas no registran propina. Solo se usan pagos con tarjeta, unicos con propina registrada.
-- indicator: Propina como porcentaje de la tarifa y porcentaje de viajes con propina por rango de distancia.
-- display: bar
-- dimensions: rango_distancia, anio
-- metrics: propina_pct_tarifa
-- interpretation: La propina en proporcion a la tarifa disminuye con la distancia: cerca de 29 % en viajes de menos de 1 milla y 16-17 % en viajes de mas de 20 millas, aunque en dolares crece. La proporcion de viajes con propina cae ano a ano en viajes medios y largos: en 5-10 millas pasa de 90.2 % (2024) a 85.7 % (2025) y 81.5 % (2026), y en mas de 20 millas de 88.0 % a 78.7 %, mientras en viajes de menos de 1 milla se mantiene en 94-95 %.
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

-- name: 06_tipo_tarifa
-- title: Uso y costo de cada tipo de tarifa
-- question: Que tipos de tarifa (estandar, aeropuertos, negociada) se usan y cual tiene la tarifa base mas alta?
-- justification: Reemplaza la relacion tipo de tarifa - origen de solicitud, que no es medible porque los viajes por plataforma no informan RatecodeID. Las tarifas especiales explican buena parte de los viajes caros.
-- indicator: Porcentaje de viajes, tarifa base media, distancia y duracion media por tipo de tarifa.
-- display: bar
-- dimensions: tipo_tarifa, anio
-- metrics: tarifa_base_media
-- interpretation: La tarifa estandar cubre la gran mayoria de los viajes, pero su participacion baja de 94.1 % a 93.0 % y 91.9 % entre 2024 y 2026. JFK se mantiene cerca de USD 70 (tarifa fija) y Nassau/Westchester es la mas cara (USD 114). Newark bajo de USD 87.7 a 78.8 y 76.2. La categoria desconocida (99) crece cada anio (1.2 %, 2.2 % y 3.6 %), lo que indica una perdida de calidad en este campo.
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

-- name: 07_destino_propina
-- title: Zonas de destino con mayor y menor propina
-- question: Hay destinos donde los pasajeros dejan una propina mas alta?
-- justification: El destino refleja el tipo de viaje (aeropuerto, oficinas, ocio, zonas residenciales). Solo pagos con tarjeta y zonas con al menos 10,000 viajes para evitar porcentajes inestables. Se muestran ambos extremos porque el contraste esta entre ellos.
-- indicator: Propina como porcentaje de la tarifa por zona de destino (10 mas altas y 10 mas bajas).
-- display: row
-- dimensions: destino
-- metrics: propina_pct_tarifa
-- interpretation: Las 10 zonas con mayor propina estan todas en Manhattan (Upper East/West Side, Village, Midtown), con 24.3-25.0 % de la tarifa y muy poca variacion entre ellas. El contraste esta en el otro extremo: en destinos de Brooklyn, Bronx y Queens como Starrett City (2.0 %), Brownsville (3.0 %) o East New York (3.6 %) la propina registrada es 5 a 12 veces menor. El destino si se asocia con la propina, y la diferencia es entre Manhattan y zonas perifericas.
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

-- name: 08_demanda_mensual
-- title: Demanda mensual de viajes
-- question: Como evoluciona la cantidad de viajes por mes y anio en Yellow y Green?
-- justification: Es el indicador base de actividad; se usa viajes por dia para comparar meses de distinta longitud y meses parciales.
-- indicator: Viajes por dia por mes y tipo de taxi (todos los registros con fecha dentro del anio del archivo).
-- display: line
-- dimensions: fecha, tipo_taxi
-- metrics: viajes_por_dia
-- interpretation: El total de Yellow alcanza su maximo en 2025: cada mes supera al mismo mes de 2024 (mayo: 148 mil vs 120 mil viajes por dia) y de febrero a agosto de 2026 queda por debajo de 2025 (mayo: 132 mil). Ese crecimiento no proviene de viajes con taximetro, que solo suben 2 % en 2025 y caen 9 % en 2026 (enero-agosto), sino de los registros sin datos del taximetro, que se triplican (ver Ejercicio 8). Green cae de forma continua: cada mes de 2025 es menor que el de 2024 y cada mes de 2026 menor que el de 2025 (agosto: 1,670, 1,494 y 1,312 viajes por dia). En los tres anios la demanda baja en julio-agosto.
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

-- name: 09_hora_dia_semana
-- title: Demanda por hora y dia de la semana
-- question: En que horas y dias se concentra la demanda?
-- justification: Muestra los picos operativos que el total mensual oculta. Se usa el porcentaje dentro de cada dia para comparar la forma de la curva.
-- indicator: Porcentaje de los viajes de cada dia de la semana que ocurre en cada hora.
-- display: line
-- dimensions: hora, dia_semana
-- metrics: pct_del_dia
-- interpretation: De lunes a viernes hay un pico matutino a las 8 h (5 % de los viajes del dia) y el maximo entre las 17 y 18 h (7 %). Sabado y domingo no tienen pico matutino y concentran viajes en la madrugada: el domingo entre 0 y 2 h ocurre 15 % de sus viajes, frente a 2 % del martes, porque recoge la salida nocturna del sabado. Jueves a sabado mantienen demanda alta hasta las 23 h.
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

-- name: 10_cargo_congestion
-- title: Peaje de congestion del centro de Manhattan
-- question: Que proporcion de viajes paga el peaje de congestion del centro y cuanto recauda por mes?
-- justification: El peaje (cbd_congestion_fee) empezo en enero de 2025; comparar anios muestra el efecto de la politica en los viajes de taxi.
-- indicator: Porcentaje de viajes con cbd_congestion_fee > 0 y recaudacion mensual (USD) por tipo de taxi.
-- display: line
-- dimensions: fecha, tipo_taxi
-- metrics: pct_viajes_con_cargo
-- interpretation: El peaje no existe en 2024 (0 %) y aparece en enero de 2025, cuando ya lo paga el 64.6 % de los viajes Yellow (empezo el 5 de enero); desde febrero de 2025 se estabiliza en 71-73 % y en julio-agosto de 2026 sube a 77 %. Recauda en Yellow entre USD 1.7 y 2.4 millones por mes. En Green solo lo paga 7-10 % de los viajes (unos USD 2-4 mil por mes), coherente con que opera principalmente fuera del centro de Manhattan.
SELECT make_date(anio, mes, 1) AS fecha,
       tipo_taxi,
       count(*) AS viajes,
       round(100.0 * avg(CASE WHEN cbd_congestion_fee > 0 THEN 1 ELSE 0 END), 2) AS pct_viajes_con_cargo,
       round(sum(cbd_congestion_fee), 2) AS recaudacion_usd
FROM viajes
WHERE year(pickup_datetime) = anio
GROUP BY ALL
ORDER BY fecha, tipo_taxi;
