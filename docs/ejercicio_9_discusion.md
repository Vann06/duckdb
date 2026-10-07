# Ejercicio 9 - Discusion

Borrador de respuestas basado en lo que hicimos en los ejercicios 1 a 8.

## 9.1. Que caracteristicas de DuckDB resultaron mas utiles durante el laboratorio?

Lo mas util fue poder leer los Parquet con SQL sin cargarlos antes. Con
`read_parquet('data/raw/*/*/*.parquet')` consultamos todos los meses y anios a la vez,
y opciones como `filename = true` y `union_by_name = true` nos resolvieron dos
problemas: sacar el anio del nombre del archivo y juntar Yellow y Green aunque sus
columnas no coinciden. Tambien nos sirvio que DuckDB corre dentro de Python, sin un
servidor aparte, y que maneja bien consultas pesadas: medianas, percentiles y
funciones de ventana sobre mas de 120 millones de viajes en un contenedor con 8 GB de
memoria. Por ultimo, `ATTACH` nos dejo comparar en la misma consulta los Parquet con la
tabla materializada.

## 9.2. Que ventajas y limitaciones encontro al consultar directamente archivos Parquet?

La ventaja principal es que no hay paso de carga: descargar un mes nuevo es suficiente
para que aparezca en la siguiente consulta. Ademas, como Parquet guarda los datos por
columna, DuckDB solo lee lo que la consulta necesita, y no duplicamos el
almacenamiento.

La limitacion es que cada consulta vuelve a leer los archivos y a normalizar las
columnas. En el benchmark del Ejercicio 6 esto hizo que Parquet fuera entre 1.03 y 2.7
veces mas lento que la tabla, segun la consulta. Tambien tuvimos que manejar a mano
las diferencias entre archivos: nombres distintos para las fechas (`tpep_*` y
`lpep_*`) y columnas que aparecen con el tiempo, como `cbd_congestion_fee` en 2025 y
`request_source` en 2026.

## 9.3. Que ventajas y limitaciones observo al utilizar tablas materializadas en DuckDB?

La tabla fue mas rapida y nos dio un esquema limpio y unico para Yellow y Green, que
simplifico mucho las consultas de los indicadores. Tambien fue la mejor opcion para
Metabase, que repite las mismas consultas cada vez que se abre el tablero.

Las limitaciones fueron el costo de construirla (un minuto y medio para 121 millones de
viajes), el espacio extra (3.7 GB) y que se desactualiza: cada vez que llegan datos
nuevos hay que reconstruirla. Ademas, DuckDB solo permite un proceso escribiendo, asi
que para reconstruirla hay que detener Metabase. Y nos encontramos con que
`CREATE OR REPLACE` no libera el espacio de la tabla anterior (el archivo llego a
5.9 GB), por eso el script la recrea desde cero.

## 9.4. Que ventajas ofrece este flujo de trabajo frente a cargar todos los datos utilizando una herramienta como Pandas?

Con Pandas habria que cargar todo en memoria antes de calcular cualquier cosa. Solo las
17 columnas de la tabla de viajes para 121 millones de filas ocuparian bastante mas que
los 8 GB del contenedor. DuckDB procesa los datos por partes, lee solo las columnas que
usa y, si no le alcanza la memoria, usa disco temporal. Nos paso en el Ejercicio 8: una
consulta con varias medianas agoto la memoria y bastaba con ponerle un limite para que
terminara. En nuestro flujo Pandas solo recibe el resultado final, que son unas pocas
filas, y ahi si es comodo para graficar.

## 9.5. Que caracteristicas del sistema desarrollado permiten incorporar nuevos datos con cambios minimos?

- Las rutas usan comodines (`data/raw/<tipo>/*/*.parquet`), asi que un anio nuevo es
  solo otra carpeta.
- El anio se saca del nombre del archivo y todas las metricas agrupan por anio.
- `union_by_name` tolera columnas nuevas o faltantes.
- El descargador recibe una lista de anios, no repite archivos y valida cada uno.
- Las consultas viven en archivos `.sql` y de ahi salen los documentos, los notebooks y
  el tablero.

La prueba fue el Ejercicio 8: agregar 2025 requirio cambiar una sola linea del
descargador y ninguna consulta de indicadores.

## 9.6. Que parte del proceso considera que deberia automatizarse en un sistema de produccion?

Primero, la descarga: un proceso programado que revise cada mes si la TLC publico datos
nuevos. Despues, que la misma ejecucion valide los archivos, reconstruya la base y
actualice el tablero sin intervencion. Tambien automatizariamos los controles que hoy
revisamos a mano: que la tabla tenga los mismos registros que los Parquet, avisar
cuando aparece o desaparece una columna y vigilar indicadores de calidad, como el
porcentaje de registros sin datos del taximetro o con tarifa desconocida. Esos dos
crecieron cada anio y, sin un aviso, pueden distorsionar el analisis sin que nadie lo
note.

## 9.7. Que decisiones de diseno fueron importantes para mantener el proyecto reproducible?

- Docker con versiones fijas, incluida la misma version de DuckDB en Python y en el
  driver de Metabase.
- No subir los datos a Git, pero si el script que los descarga de la fuente original.
- Guardar todas las consultas en archivos SQL versionados, con su objetivo y decision.
- Generar los documentos y el tablero desde esas consultas en lugar de copiar
  resultados a mano.
- Scripts que se pueden ejecutar varias veces sin efectos raros: el descargador omite
  lo que ya existe y la base se recrea desde cero.
- Tratar la base DuckDB como un derivado de los Parquet, que siempre se puede volver a
  construir.

## 9.8. Que aprendio sobre el manejo de datos que no habria sido evidente trabajando unicamente con conjuntos de datos pequenos?

Que los datos cambian con el tiempo y eso puede parecer un cambio de comportamiento.
Los registros sin datos del taximetro pasaron de 9.5 % a 26 % de los viajes Yellow, y
eso por si solo hacia parecer que la demanda crecia 21 %, que la tarifa subia y que se
pagaba menos con tarjeta. Al separar por tipo de registro vimos que no era asi. Tambien
aprendimos que con dos anios se pueden ver tendencias que no existen, que los
promedios confunden cuando hay valores extremos (viajes de 300 mil millas, o Uber con 12 millas
de promedio pero 3 de mediana) y que hasta una consulta que parece simple puede agotar
la memoria si no se piensa en el volumen.
