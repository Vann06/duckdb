# Lab 8 - DuckDB

Repositorio laboratorio 8 del curso **CC3084 - Data Science**

## Estructura

```text
duckdb/
|
+-- data/
|   +-- raw/
|   +-- processed/
|
+-- notebooks/
|
+-- scripts/
|
+-- sql/
|
+-- docs/
|
+-- Dockerfile
+-- metabase.Dockerfile
+-- docker-compose.yml
+-- README.md
```

## Requisitos

- Docker, con Docker Compose
- Git


## Datos

El repositorio incluye `scripts/download_data.py`, que descarga los archivos de
2024 y 2026 publicados por la TLC (`--help` muestra las opciones disponibles). Los
archivos se guardan en `data/raw/<tipo>/<anio>/`.

Los datos descargados **no deben incluirse en el repositorio Git**. El archivo
`.gitignore` ya contiene las reglas para ignorar los archivos Parquet descargados y
los archivos generados por DuckDB.


Dentro de los contenedores, la carpeta `data/` del proyecto esta montada en
`/workspace/data`. Esa es la ruta que deben usar las herramientas que corren
dentro del ambiente, no la ruta de su computadora.

---

## Como levantar el ambiente

1. Instale y abra Docker Desktop. Espere hasta que el motor de Docker indique
   que esta en ejecucion.
2. Desde la raiz del repositorio construya e inicie los servicios:

   ```bash
   docker compose up --build -d
   ```

3. Verifique que los contenedores `lab8-lab` y `lab8-metabase` esten activos:

   ```bash
   docker compose ps
   ```

4. Abra las herramientas del ambiente:

   - JupyterLab: <http://localhost:8888>
   - Metabase: <http://localhost:3000>

5. Verifique las versiones y bibliotecas principales:

   ```bash
   docker compose exec lab python --version
   docker compose exec lab python -c "import duckdb, pandas, pyarrow, matplotlib, requests; print('Ambiente correcto')"
   ```

6. Para detener los servicios sin eliminar los datos persistentes de Metabase:

   ```bash
   docker compose down
   ```

Si un servicio no inicia, sus registros se consultan con:

```bash
docker compose logs --tail 100 lab
docker compose logs --tail 100 metabase
```

### 1.4. Herramientas disponibles

- **Python 3.11**: lenguaje de automatizacion y analisis.
- **DuckDB**: motor analitico para consultar directamente archivos Parquet.
- **JupyterLab**: ambiente interactivo para notebooks.
- **Pandas y PyArrow**: manipulacion de datos e interoperabilidad con Parquet.
- **Matplotlib**: visualizacion.
- **Requests**: descarga automatizada de archivos.
- **Metabase**: construccion de indicadores y tableros.

### Proposito de los directorios

- `data/raw/`: archivos originales descargados desde la TLC. No se versionan.
- `data/processed/`: datos transformados y bases DuckDB generadas. No se
  versionan.
- `notebooks/`: notebooks de exploracion y analisis.
- `scripts/`: programas reproducibles de descarga, validacion y procesamiento.
- `sql/`: consultas SQL versionadas.
- `docs/`: resultados, decisiones y documentacion de las consultas.


## Como descargar los datos

Sin argumentos, el script descarga los meses publicados de taxis amarillos y
verdes de 2024 y 2026:

```bash
docker compose exec lab python scripts/download_data.py
```

Para reproducir solo el conjunto inicial del Ejercicio 2 o elegir un tipo:

```bash
docker compose exec lab python scripts/download_data.py --years 2026
docker compose exec lab python scripts/download_data.py --taxi yellow
docker compose exec lab python scripts/download_data.py --taxi green
```

Para incorporar 2024 en el Ejercicio 5 conservando 2026:

```bash
docker compose exec lab python scripts/download_data.py --years 2024 2026
```

Los archivos se almacenan en:

```text
data/raw/yellow/2026/yellow_tripdata_2026-MM.parquet
data/raw/green/2026/green_tripdata_2026-MM.parquet
data/raw/yellow/2024/yellow_tripdata_2024-MM.parquet
data/raw/green/2024/green_tripdata_2024-MM.parquet
```

Antes de omitir un archivo existente, el programa valida las firmas Parquet.
Por eso se puede ejecutar varias veces: conserva los archivos validos y solo
descarga los que falten o esten incompletos.

### 2.6. Cambios realizados al script

La version recibida ya recorria los doce meses de 2026, permitia elegir Yellow o
Green Taxi, evitaba repetir archivos existentes y usaba un archivo temporal
durante la descarga. Al revisarla, notamos que consideraba valido cualquier
archivo cuyo tamanio fuera mayor que cero. Eso podia aceptar un archivo
interrumpido o un contenido que no fuera realmente Parquet.

Los cambios realizados en `scripts/download_data.py` fueron:

- agregamos `es_parquet_valido`, que comprueba la firma `PAR1` al inicio y al
  final del archivo;
- cambiamos la condicion que omite archivos existentes para utilizar esa
  validacion y no solamente el tamanio;
- validamos el archivo temporal antes de renombrarlo como `.parquet`;
- si un archivo local no es valido, el script lo informa e intenta descargarlo
  otra vez;
- actualizamos la descripcion inicial del script para explicar el nuevo
  comportamiento.

Con esto seguimos evitando descargas repetidas, pero no conservamos como valido
un archivo que haya quedado incompleto.

### 2.7. Como determinamos que la descarga esta completa

Primero comparamos los archivos locales con la lista publicada por la TLC. Al 2
de octubre de 2026 estaban disponibles los meses de enero a agosto para ambos
tipos de taxi. En `data/raw` encontramos exactamente 8 archivos amarillos y 8
verdes. Septiembre, octubre, noviembre y diciembre no se consideraron faltantes
porque el servidor todavia los reportaba como no publicados.

Luego ejecutamos el descargador por segunda vez. El resumen obtenido fue:

```text
descargados   : 0
ya existian   : 16
no publicados : 8
fallidos      : 0
```

Finalmente, DuckDB pudo abrir todos los archivos y encontro registros en cada
uno. El conjunto completo contiene 30,040,469 viajes: 29,703,355 de Yellow Taxi
y 337,114 de Green Taxi. Estas tres comprobaciones nos permitieron concluir que
la descarga estaba completa con respecto a lo publicado en ese momento.

## Como ejecutar el analisis

El Ejercicio 3 consulta los archivos Parquet directamente, sin importarlos a una
tabla. Todas las consultas se encuentran en `sql/01_exploracion_inicial.sql`.

Ejecute la exploracion completa con:

```bash
docker compose exec -T lab python scripts/run_exploration.py
```

El programa:

1. comprueba que existan archivos Parquet;
2. ejecuta cada consulta con DuckDB;
3. conserva el SQL utilizado;
4. genera `docs/ejercicio_3_resultados.md` con el objetivo, fuente, resultado y
   decision de cada consulta.

El archivo `docs/ejercicio_3_resultados.md` conserva la evidencia tecnica y las
tablas obtenidas. Nuestra interpretacion redactada durante la revision se
encuentra en `docs/ejercicio_3_analisis.md`. Mantuvimos ambos archivos separados
para poder actualizar los resultados cuando aparezcan nuevos datos sin perder
las observaciones escritas.

Para repetir el analisis despues de descargar un nuevo mes se utiliza el mismo
comando. No es necesario importar previamente los datos a una tabla DuckDB.

## Ejercicio 4: analisis exploratorio

Las ocho preguntas, consultas y justificaciones estan versionadas en
`sql/02_analisis_exploratorio.sql`. Incluyen evolucion temporal, patrones por
hora, caracteristicas del viaje, diferencias Yellow/Green, pagos, propinas,
percentiles, valores atipicos y rutas frecuentes.

Ejecute el analisis sobre 2026 con:

```bash
docker compose exec -T lab python scripts/run_eda.py
```

El comando genera `docs/ejercicio_4_resultados.md`, que incluye cada consulta,
su resultado, su interpretacion y al menos tres hallazgos calculados desde los
datos. Se usa 2026 intencionalmente porque este ejercicio precede a la
incorporacion de 2024.

## Ejercicio 5: incorporar y validar 2024

Descargue ambos anios y ejecute la validacion conjunta:

```bash
docker compose exec lab python scripts/download_data.py --years 2024 2026
docker compose exec -T lab python scripts/validate_incremental.py
```

La validacion ejecuta `sql/03_validacion_incremental.sql` y genera
`docs/ejercicio_5_validacion.md`. Comprueba la cobertura mensual, cuenta los
registros de ambos anios en una sola consulta y ejecuta una comparacion anual.
El documento tambien explica los cambios necesarios para ampliar las consultas
del Ejercicio 4.

## Ejercicio 6: benchmark Parquet versus DuckDB

Con los archivos de 2024 y 2026 disponibles, ejecute:

```bash
docker compose exec -T lab python scripts/run_benchmark.py
```

El programa:

1. normaliza y materializa ambos tipos de taxi en
   `data/processed/taxi_benchmark.duckdb`;
2. ejecuta las mismas tres consultas desde Parquet y desde la tabla DuckDB;
3. mide por separado 2024, 2026 y el conjunto 2024+2026;
4. repite cada medicion tres veces y registra la primera ejecucion y la mediana
   de las siguientes;
5. genera `docs/ejercicio_6_benchmark.csv` y
   `docs/ejercicio_6_resultados.md`.

Para cambiar la cantidad de repeticiones o medir un solo anio:

```bash
docker compose exec -T lab python scripts/run_benchmark.py --iterations 5
docker compose exec -T lab python scripts/run_benchmark.py --years 2026
```

La base materializada es un artefacto reproducible y esta ignorada por Git. El
tiempo de construccion se informa por separado: no se incluye artificialmente
dentro del tiempo de cada consulta, pero debe considerarse al decidir entre
ambas estrategias.

## Secuencia completa de los ejercicios 4 al 6

```bash
docker compose up --build -d
docker compose exec lab python scripts/download_data.py --years 2024 2026
docker compose exec -T lab python scripts/run_eda.py
docker compose exec -T lab python scripts/validate_incremental.py
docker compose exec -T lab python scripts/run_benchmark.py
```
