# Laboratorio Integrador I — NYC Yellow Taxi

Tubería ELT reproducible para enero–diciembre de 2025 y enero–agosto de 2026: **20 meses** de datos oficiales de NYC Yellow Taxi.

## Qué entrega este proyecto

- Ingesta automática desde los Parquet oficiales de NYC TLC.
- Catálogo oficial de Taxi Zones.
- Snowflake con capas `BRONZE`, `SILVER` y `GOLD`.
- Transformaciones y pruebas en dbt.
- Orquestación, reintentos y logs en Kestra.
- Esquema estrella con una tabla de hechos y cinco dimensiones.
- Carga idempotente por período: reejecutar no duplica datos.
- Diagramas y decisiones de calidad documentados.

## Requisitos

- Docker Desktop en ejecución, usando contenedores Linux.
- 8 GB de RAM son suficientes; el pipeline procesa un archivo por vez.
- Una cuenta Snowflake y un usuario al que se pueda asignar el rol del laboratorio.
- PowerShell y Git.

Los datos masivos no quedan en el disco de Docker: cada Parquet se elimina tras subirlo y el almacenamiento definitivo está en Snowflake.

## 1. Preparar Snowflake

1. Abre Snowsight con un rol administrador.
2. Abre [`snowflake/setup.sql`](snowflake/setup.sql).
3. Reemplaza `TU_USUARIO_SNOWFLAKE` por tu usuario real.
4. Ejecuta todo el archivo una sola vez.

Esto crea un warehouse `XSMALL` con suspensión automática, la base, las tres capas y un rol limitado al laboratorio.

## 2. Configurar credenciales

Desde PowerShell, en la raíz de este laboratorio:

```powershell
Copy-Item .env.example .env
notepad .env
```

Completa estos valores:

```dotenv
SNOWFLAKE_ACCOUNT=ORGANIZACION-CUENTA
SNOWFLAKE_USER=TU_USUARIO
SNOWFLAKE_PASSWORD=TU_PASSWORD
SNOWFLAKE_ROLE=NYC_TAXI_ROLE
SNOWFLAKE_WAREHOUSE=NYC_TAXI_WH
SNOWFLAKE_DATABASE=NYC_TAXI_DB
```

En `SNOWFLAKE_ACCOUNT` no incluyas `https://` ni `.snowflakecomputing.com`. `.env` y `.env.kestra` están ignorados por Git y no deben subirse.

Si tu contraseña contiene `$`, `#`, espacios u otros caracteres especiales, colócala entre comillas simples, por ejemplo `SNOWFLAKE_PASSWORD='Mi$Clave#Segura'`.

## 3. Levantar la infraestructura

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\start.ps1
```

El script valida la configuración, construye las imágenes de ingesta/dbt y levanta:

- Kestra: <http://localhost:8080>
- PostgreSQL interno de Kestra, sin puerto público.

Comprueba el entorno con:

```powershell
.\scripts\smoke-test.ps1
```

## 4. Ejecutar el pipeline completo

1. Abre <http://localhost:8080>.
2. En **Flows**, entra a `labs.semana07` → `nyc_taxi_end_to_end`.
3. Presiona **Execute**.
4. Para la ejecución final conserva `fail_on_missing = true` y `enforce_20_periods = true`.

La primera tarea hace preflight de las 20 URLs, carga el catálogo y procesa cada mes secuencialmente. La segunda ejecuta `dbt build`, que construye Silver/Gold y corre las pruebas.

### Disponibilidad de agosto de 2026

La fuente TLC se publica mensualmente y normalmente tiene un retraso aproximado de dos meses. Al momento de preparar este laboratorio, la página oficial muestra 2026 hasta julio y agosto aún no aparece listado. El pipeline **sí contiene `2026-08`**, pero con `fail_on_missing = true` se detiene antes de cargar parcialmente si el archivo todavía responde 403/404.

Para una demostración temporal con lo disponible ejecuta desde la UI con:

```text
fail_on_missing = false
enforce_20_periods = false
```

El segundo valor omite únicamente `assert_20_periods_loaded`; las demás pruebas siguen activas. Esto permite demostrar el pipeline completo con 19 meses sin fingir que la entrega ya contiene 20. Para la entrega final devuelve ambos valores a `true`.

## 5. Validar la entrega

Cuando Kestra termine en `SUCCESS`:

1. Revisa que todos los tests de `dbt build` estén en verde.
2. Ejecuta [`snowflake/validation.sql`](snowflake/validation.sql) en Snowsight.
3. Confirma 20 filas exitosas de `yellow_taxi` en `BRONZE.INGESTION_AUDIT`.
4. Ejecuta nuevamente el flujo: los conteos deben permanecer iguales, no duplicarse.

## Ejecución directa para depurar

Si necesitas aislar Kestra, puedes ejecutar las mismas imágenes manualmente:

```powershell
.\scripts\configure-env.ps1
docker compose --profile jobs build pipeline-ingest pipeline-dbt
docker compose --profile jobs run --rm pipeline-ingest
docker compose --profile jobs run --rm pipeline-dbt dbt debug --project-dir /opt/dbt --profiles-dir /opt/dbt
docker compose --profile jobs run --rm pipeline-dbt
```

Para probar solo los meses ya publicados, cambia temporalmente en `.env`:

```dotenv
FAIL_ON_MISSING=false
ENFORCE_20_PERIODS=false
```

Devuelve ambos valores a `true` antes de la ejecución final.

## Modelado

- **Bronze:** fila original como `VARIANT`, archivo, período, número de fila, carga y auditoría SHA-256.
- **Silver:** tipos, estandarización, reglas de validez, deduplicación y resumen de calidad.
- **Gold:** `FCT_TRIPS` a grano de un viaje y dimensiones de fecha, ubicación, proveedor, pago y tarifa.

Consulta:

- [Diagrama de arquitectura](docs/architecture.md)
- [Diagrama del esquema estrella](docs/star-schema.md)
- [Decisiones de calidad](docs/data-quality.md)

## Pruebas dbt

Se incluyen pruebas genéricas `not_null`, `unique` y `relationships`, además de pruebas singulares para:

- verificar que estén cargados exactamente los 20 períodos requeridos;
- reconciliar los conteos de auditoría con Bronze;
- impedir cronologías inválidas en Silver limpio;
- impedir duplicados exactos en Silver limpio.

## Idempotencia

Para cada período, la ingesta sigue este orden:

1. descarga y validación de firma Parquet;
2. `PUT` a un stage interno;
3. `COPY` a una tabla temporal;
4. verificación de que existan filas;
5. `DELETE` + `INSERT` + auditoría dentro de una transacción;
6. eliminación del archivo del stage y del disco temporal.

Por eso una reejecución reemplaza el mes y una falla antes del paso 5 conserva la versión anterior.

## Comandos operativos

```powershell
# Estado
docker compose ps

# Logs
docker compose logs -f kestra

# Detener sin borrar metadata
docker compose stop

# Detener y retirar contenedores; conserva volúmenes
docker compose down

# Borrar también la metadata local de Kestra (acción destructiva)
docker compose down -v
```

## Fuentes oficiales

- [TLC Trip Record Data](https://www.nyc.gov/site/tlc/about/tlc-trip-record-data.page)
- [Yellow Taxi Trip Records Data Dictionary](https://www.nyc.gov/assets/tlc/downloads/pdf/data_dictionary_trip_records_yellow.pdf)
- [Taxi Zone Lookup Table](https://d37ci6vzurychx.cloudfront.net/misc/taxi_zone_lookup.csv)

## Estructura para entregar

La carpeta ya tiene la ruta solicitada:

```text
labs/semana-07/laboratorio-integrador-i/
```

Agrégala al repo de la clase, haz commit/push y entrega el enlace de GitHub a esta carpeta. No subas `.env`, `.env.kestra`, contraseñas, datos Parquet, `target/` ni logs.

## Uso de IA

Se utilizó IA para proponer la estructura, revisar idempotencia y generar una primera versión del código y la documentación. El equipo debe ejecutar el pipeline, revisar los resultados de calidad y poder explicar cada decisión antes de entregarlo.
