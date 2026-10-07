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
2024, 2025 y 2026 publicados por la TLC (`--help` muestra las opciones disponibles).
Los archivos se guardan en `data/raw/<tipo>/<anio>/`. Tambien descarga la tabla de
zonas TLC en `data/raw/zones/taxi_zone_lookup.csv`.

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

### 1.6. Importancia de un ambiente reproducible

En un proyecto de analisis de datos los resultados dependen tanto de los datos
como del software que los procesa. Un cambio de version en DuckDB, Pandas o
PyArrow puede alterar tipos de datos, funciones disponibles o incluso resultados
numericos. Usar Docker con versiones fijadas en `requirements.txt` y en las
imagenes base nos da varias ventajas:

- **Mismos resultados para todos**: cada integrante, el docente o cualquier
  revisor ejecuta exactamente el mismo Python, las mismas bibliotecas y la misma
  version del driver de DuckDB en Metabase. Las cifras de los documentos se
  pueden volver a obtener con los mismos comandos.
- **Evita el "en mi maquina si funciona"**: el ambiente no depende del sistema
  operativo ni de lo que cada persona tenga instalado localmente.
- **Puesta en marcha rapida**: un solo `docker compose up --build -d` deja
  listos JupyterLab, DuckDB y Metabase, sin instalaciones manuales.
- **Compatibilidad entre herramientas**: DuckDB en Python y el driver de
  Metabase deben usar la misma version para leer la misma base; fijarlas evita
  errores de formato.
- **Trazabilidad**: el ambiente queda versionado en Git junto con el codigo y
  las consultas, de modo que cualquier resultado se puede asociar a la
  configuracion exacta que lo produjo.
- **Aislamiento**: las dependencias del laboratorio no interfieren con otros
  proyectos instalados en la computadora.

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
verdes de 2024, 2025 y 2026, ademas de la tabla de zonas:

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

## Ejercicio 7: indicadores y tablero

Los diez indicadores (pregunta, justificacion, consulta, grafico e
interpretacion) estan en `sql/06_indicadores.sql`. Se calculan sobre una base
DuckDB materializada, porque el tablero repite las mismas consultas cada vez
que se abre:

```bash
# 1. Construye data/processed/taxi.duckdb y docs/ejercicio_7_indicadores.md
docker compose stop metabase
docker compose exec -T lab python scripts/build_indicadores.py
docker compose start metabase

# 2. Crea o actualiza las preguntas y el tablero en Metabase
docker compose exec -T -e MB_EMAIL=<correo> -e MB_PASSWORD=<clave> lab python scripts/setup_metabase.py
```

- Modelo de datos: `sql/05_modelo_indicadores.sql` (tabla `viajes`, tabla
  `zonas` y vista `viajes_validos`).
- Tablero: Metabase en <http://localhost:3000>, coleccion "Lab 8 - Indicadores".
- Registro de consultas y tablero en notebook: `notebooks/07_indicadores.ipynb`.
- Documentacion generada: `docs/ejercicio_7_indicadores.md`.

Metabase abre la base en modo solo lectura. DuckDB no permite reconstruirla
mientras otro proceso la tiene abierta; por eso se detiene Metabase antes del
paso 1. La tabla de zonas (`data/raw/zones/taxi_zone_lookup.csv`) la descarga
`scripts/download_data.py`.

## Ejercicio 8: incorporar 2025

El descargador usa por defecto 2024, 2025 y 2026. Los indicadores no requieren
cambios de SQL: basta con reconstruir la base y volver a generar el tablero.

```bash
docker compose exec lab python scripts/download_data.py
docker compose stop metabase
docker compose exec -T lab python scripts/build_indicadores.py
docker compose start metabase
docker compose exec -T lab python scripts/run_ejercicio_8.py
docker compose exec -T -e MB_EMAIL=<correo> -e MB_PASSWORD=<clave> lab python scripts/setup_metabase.py
```

- Validacion y analisis: `sql/07_ejercicio_8.sql`.
- Resultados y patrones 2024-2026: `docs/ejercicio_8_resultados.md`.
- Notebook: `notebooks/08_incorporacion_2025.ipynb`.
- Registros de las dos ejecuciones del descargador: `docs/ejercicio_8_descarga*.log`.

## Ejercicio 9: discusion

Las respuestas a las preguntas 9.1 a 9.8 estan en `docs/ejercicio_9_discusion.md`.

## Entregables por ejercicio

| Ejercicio | Consultas | Scripts | Resultados | Notebook |
|---|---|---|---|---|
| 1 | - | - | `README.md` (1.4 a 1.6) | `01_ambiente_y_descarga` |
| 2 | - | `download_data.py` | `README.md` (2.6 y 2.7) | `01_ambiente_y_descarga` |
| 3 | `sql/01_exploracion_inicial.sql` | `run_exploration.py` | `docs/ejercicio_3_*.md` | `03_exploracion_parquet` |
| 4 | `sql/02_analisis_exploratorio.sql` | `run_eda.py` | `docs/ejercicio_4_resultados.md` | `04_analisis_exploratorio` |
| 5 | `sql/03_validacion_incremental.sql` | `validate_incremental.py` | `docs/ejercicio_5_validacion.md` | `05_incorporacion_2024` |
| 6 | `sql/04_benchmark.sql` | `run_benchmark.py` | `docs/ejercicio_6_*` | `06_benchmark_parquet_vs_duckdb` |
| 7 | `sql/05_modelo_indicadores.sql`, `sql/06_indicadores.sql` | `build_indicadores.py`, `setup_metabase.py` | `docs/ejercicio_7_indicadores.md`, tablero en Metabase | `07_indicadores` |
| 8 | `sql/07_ejercicio_8.sql` | `run_ejercicio_8.py` | `docs/ejercicio_8_*` | `08_incorporacion_2025` |
| 9 | - | - | `docs/ejercicio_9_discusion.md` | - |

Los notebooks estan en `notebooks/` y se abren en JupyterLab
(<http://localhost:8888>). No duplican SQL: leen las mismas consultas de `sql/`
mediante `notebooks/lab_utils.py`.

## Secuencia completa

Los ejercicios 5 y 6 se ejecutaron originalmente con 2024 y 2026; sus scripts
siguen limitados a esos anios para conservar esa etapa.

```bash
docker compose up --build -d
docker compose exec lab python scripts/download_data.py          # 2024, 2025 y 2026
docker compose exec -T lab python scripts/run_exploration.py     # Ejercicio 3
docker compose exec -T lab python scripts/run_eda.py             # Ejercicio 4
docker compose exec -T lab python scripts/validate_incremental.py  # Ejercicio 5
docker compose exec -T lab python scripts/run_benchmark.py       # Ejercicio 6
docker compose stop metabase
docker compose exec -T lab python scripts/build_indicadores.py   # Ejercicio 7
docker compose start metabase
docker compose exec -T lab python scripts/run_ejercicio_8.py     # Ejercicio 8
docker compose exec -T -e MB_EMAIL=<correo> -e MB_PASSWORD=<clave> lab python scripts/setup_metabase.py
```
