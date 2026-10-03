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
2026 publicados por la TLC (`--help` muestra las opciones disponibles). Los
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

El script inicial descarga los meses publicados de taxis amarillos y verdes de
2026:

```bash
docker compose exec lab python scripts/download_data.py
```

Tambien es posible descargar un solo tipo de taxi:

```bash
docker compose exec lab python scripts/download_data.py --taxi yellow
docker compose exec lab python scripts/download_data.py --taxi green
```

Los archivos se almacenan en:

```text
data/raw/yellow/2026/yellow_tripdata_2026-MM.parquet
data/raw/green/2026/green_tripdata_2026-MM.parquet
```

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
