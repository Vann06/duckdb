# Ejercicio 3 - Analisis de la exploracion inicial

Antes de plantear preguntas mas complejas, revisamos cuantos datos teniamos, que
columnas estaban disponibles y que problemas podian afectar el analisis. En esta
etapa trabajamos directamente con los Parquet, sin crear una tabla permanente.
Las consultas y sus resultados completos estan en
`docs/ejercicio_3_resultados.md`; aqui dejamos nuestra interpretacion.

## 3.1. Cantidad de archivos disponibles

Encontramos 16 archivos de enero a agosto de 2026: 8 de Yellow Taxi y 8 de
Green Taxi. Esta cantidad coincide con los meses que la TLC tenia publicados al
momento de la descarga. Por eso no tomamos la ausencia de septiembre a diciembre
como un error del programa.

Tambien ejecutamos el descargador una segunda vez. Los 16 archivos aparecieron
como existentes, no se descargo ninguno de nuevo y no hubo fallos. Esto confirma
que el proceso puede repetirse sin duplicar trabajo.

## 3.2. Cantidad de registros

En total encontramos 30,040,469 viajes:

- Yellow Taxi: 29,703,355 registros.
- Green Taxi: 337,114 registros.

La diferencia entre ambos grupos es considerable: mas del 98 % de los registros
pertenece a Yellow Taxi. En ejercicios posteriores no seria suficiente comparar
solo cantidades absolutas, porque el tamanio de Yellow Taxi dominaria el
resultado. Para una comparacion mas justa conviene usar promedios, porcentajes o
indicadores calculados por viaje.

Revisamos tambien el total de filas de cada archivo. Ningun mes estaba vacio.
Los archivos de Yellow Taxi contienen aproximadamente entre 3.3 y 4.1 millones
de viajes, mientras los de Green Taxi contienen entre 37 mil y 45 mil.

## 3.3 y 3.4. Columnas y tipos de datos

Ambos conjuntos incluyen distancia, pasajeros, lugares de inicio y fin, forma
de pago, tarifa, propina y monto total. Sin embargo, no tienen exactamente el
mismo esquema. La diferencia mas evidente esta en las fechas:

- Yellow Taxi usa `tpep_pickup_datetime` y `tpep_dropoff_datetime`.
- Green Taxi usa `lpep_pickup_datetime` y `lpep_dropoff_datetime`.

Green Taxi tambien contiene `ehail_fee` y `trip_type`, mientras Yellow Taxi
incluye `Airport_fee`. Por esta razon usamos `union_by_name = true` al leer los
dos tipos juntos. De lo contrario podriamos asumir incorrectamente que una
columna ocupa la misma posicion en ambos archivos.

DuckDB reconocio las fechas como `TIMESTAMP`, los identificadores como `INTEGER`
o `BIGINT`, los montos y distancias como `DOUBLE`, y las banderas de texto como
`VARCHAR`. Para la exploracion inicial decidimos conservar esos tipos.

## 3.5. Muestra de registros

Tomamos cinco registros de cada tipo de taxi y presentamos las fechas con un
nombre comun para facilitar la lectura. La muestra contiene distintas
distancias, cantidades de pasajeros y formas de pago. Tambien aparecen valores
nulos en `passenger_count` y codigos de pago iguales a cero. Esto nos indico que
un archivo legible no necesariamente tiene todas sus variables completas.

En la muestra mostramos viajes cuya fecha de inicio pertenece a 2026 para que
fuera facil de interpretar. Las fechas fuera del anio no se ignoraron: se
contaron por separado en la consulta de calidad.

## 3.6. Problemas de calidad observados

La revision inicial encontro lo siguiente:

1. 31 viajes tienen una fecha de inicio fuera de 2026, aunque estan guardados en
   archivos identificados como 2026.
2. 15 registros tienen una fecha de fin anterior a la fecha de inicio.
3. En 7,765,463 registros falta la cantidad de pasajeros.
4. Hay 964,443 viajes con distancia igual o menor que cero.
5. Hay 162,858 registros con un monto total negativo.

No todos estos casos significan lo mismo. Un total negativo podria representar
una correccion o un reembolso, mientras una fecha final anterior a la inicial
parece una inconsistencia. Por eso decidimos no eliminar registros de manera
automatica. Cada consulta posterior debera indicar que filtro aplica y por que.

La cantidad de pasajeros merece atencion especial porque tiene muchos valores
nulos, principalmente en Yellow Taxi. Si construimos un indicador de ocupacion,
deberemos reportar cuantos viajes quedaron fuera en vez de reemplazar los nulos
por cero sin justificacion.

## 3.7 y 3.8. Consultas y documentacion

Las consultas estan en `sql/01_exploracion_inicial.sql`. Para cada una se
documento el objetivo, la fuente, el resultado y la decision tomada. El analisis
se reproduce con:

```bash
docker compose exec -T lab python scripts/run_exploration.py
```

Ese comando actualiza `docs/ejercicio_3_resultados.md`. Separamos los resultados
reproducibles de esta interpretacion para poder incorporar un nuevo mes sin
sobrescribir las observaciones que fuimos escribiendo.

## 3.9. Que significa consultar directamente Parquet

Consultar directamente Parquet significa que DuckDB utiliza los archivos como
la fuente de una consulta SQL. En nuestro caso, `read_parquet` abre los archivos
de `data/raw`, interpreta su esquema y entrega las columnas solicitadas sin que
primero tengamos que copiar todos los viajes a una tabla. Los Parquet originales
siguen siendo la fuente del analisis.

Esto es util cuando el volumen es grande porque Parquet almacena los datos por
columnas. Si una consulta usa solamente la fecha, la distancia y el monto total,
DuckDB puede evitar leer muchas columnas que no necesita. Tambien puede usar los
metadatos y los filtros de la consulta para descartar partes del archivo. Como
resultado se reduce la lectura de disco, no se duplica todo el conjunto y no es
necesario cargarlo completo en la memoria de Python.

En este laboratorio hay otra ventaja: los datos llegan en archivos mensuales.
El patron `data/raw/*/2026/*.parquet` permite agregar un mes y consultarlo junto
con los anteriores sin reconstruir manualmente una tabla. Esto hace que el flujo
sea incremental y facil de repetir.

La consulta directa tampoco resuelve todos los escenarios. Si una transformacion
costosa se repite muchas veces, si necesitamos imponer un esquema ya limpio o si
varias herramientas consultaran exactamente el mismo resultado, podria ser mas
conveniente materializar una tabla en DuckDB. Esa diferencia se medira en el
Ejercicio 6. Para esta exploracion, consultar Parquet directamente evito un paso
de carga que todavia no era necesario.
