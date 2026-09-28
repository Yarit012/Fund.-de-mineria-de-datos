"""Ingesta reproducible de NYC Yellow Taxi a Snowflake Bronze.

El programa procesa un archivo Parquet por vez. Cada periodo se copia primero a
una tabla temporal y solo después reemplaza el periodo anterior dentro de una
transacción. Así, reejecutar el pipeline no genera duplicados y una descarga o
carga incompleta nunca destruye una versión válida ya existente.
"""

from __future__ import annotations

import csv
import hashlib
import json
import os
import re
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

import requests
import snowflake.connector
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry


TRIP_BASE_URL = "https://d37ci6vzurychx.cloudfront.net/trip-data"
ZONE_URL = "https://d37ci6vzurychx.cloudfront.net/misc/taxi_zone_lookup.csv"
DEFAULT_PERIODS = [
    *(f"2025-{month:02d}" for month in range(1, 13)),
    *(f"2026-{month:02d}" for month in range(1, 9)),
]
PERIOD_PATTERN = re.compile(r"20\d{2}-(0[1-9]|1[0-2])")


def log(event: str, **values: object) -> None:
    print(json.dumps({"event": event, **values}, ensure_ascii=False), flush=True)


def required_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value or value.startswith("TODO_"):
        raise ValueError(f"Falta configurar la variable {name}")
    return value


def boolean_env(name: str, default: bool) -> bool:
    raw_value = os.getenv(name, str(default)).strip().lower()
    if raw_value not in {"true", "false"}:
        raise ValueError(f"{name} debe ser true o false")
    return raw_value == "true"


def configured_periods() -> list[str]:
    raw_periods = os.getenv("NYC_TAXI_PERIODS", ",".join(DEFAULT_PERIODS))
    periods = [value.strip() for value in raw_periods.split(",") if value.strip()]
    invalid = [value for value in periods if not PERIOD_PATTERN.fullmatch(value)]
    if invalid:
        raise ValueError(f"Periodos inválidos (se espera YYYY-MM): {invalid}")
    if len(periods) != len(set(periods)):
        raise ValueError("NYC_TAXI_PERIODS contiene periodos duplicados")
    if not periods:
        raise ValueError("NYC_TAXI_PERIODS no puede estar vacío")
    return periods


def trip_url(period: str) -> str:
    return f"{TRIP_BASE_URL}/yellow_tripdata_{period}.parquet"


def http_session() -> requests.Session:
    retry = Retry(
        total=4,
        connect=4,
        read=4,
        backoff_factor=2,
        status_forcelist=(429, 500, 502, 503, 504),
        allowed_methods=("GET", "HEAD"),
    )
    session = requests.Session()
    session.headers.update({"User-Agent": "nyc-taxi-lab/1.0"})
    session.mount("https://", HTTPAdapter(max_retries=retry))
    return session


def source_exists(session: requests.Session, url: str) -> bool:
    response = session.head(url, allow_redirects=True, timeout=(20, 60))
    # El bucket público de TLC responde 403 (no 404) cuando la clave aún no existe.
    if response.status_code in {403, 404}:
        return False
    response.raise_for_status()
    return True


def download(
    session: requests.Session, url: str, destination: Path
) -> tuple[str, int]:
    digest = hashlib.sha256()
    byte_count = 0
    with session.get(url, stream=True, timeout=(30, 900)) as response:
        response.raise_for_status()
        with destination.open("wb") as output:
            for chunk in response.iter_content(chunk_size=8 * 1024 * 1024):
                if chunk:
                    output.write(chunk)
                    digest.update(chunk)
                    byte_count += len(chunk)
    if byte_count == 0:
        raise RuntimeError(f"La descarga produjo un archivo vacío: {url}")
    return digest.hexdigest(), byte_count


def validate_parquet(path: Path) -> None:
    if path.stat().st_size < 8:
        raise RuntimeError(f"El archivo no puede ser Parquet porque es muy pequeño: {path}")
    with path.open("rb") as source:
        prefix = source.read(4)
        source.seek(-4, 2)
        suffix = source.read(4)
    if prefix != b"PAR1" or suffix != b"PAR1":
        raise RuntimeError(f"La fuente descargada no tiene una firma Parquet válida: {path}")


def validate_zone_csv(path: Path) -> None:
    with path.open("r", encoding="utf-8-sig", newline="") as source:
        header = next(csv.reader(source), [])
    expected = ["LocationID", "Borough", "Zone", "service_zone"]
    if header != expected:
        raise RuntimeError(
            f"El esquema del catálogo de zonas cambió. Esperado={expected}; recibido={header}"
        )


def safe_database_name() -> str:
    database = os.getenv("SNOWFLAKE_DATABASE", "NYC_TAXI_DB").strip().upper()
    if not re.fullmatch(r"[A-Z][A-Z0-9_$]*", database):
        raise ValueError("SNOWFLAKE_DATABASE contiene caracteres no permitidos")
    return database


def snowflake_connection():
    return snowflake.connector.connect(
        account=required_env("SNOWFLAKE_ACCOUNT"),
        user=required_env("SNOWFLAKE_USER"),
        password=required_env("SNOWFLAKE_PASSWORD"),
        role=os.getenv("SNOWFLAKE_ROLE", "NYC_TAXI_ROLE"),
        warehouse=os.getenv("SNOWFLAKE_WAREHOUSE", "NYC_TAXI_WH"),
        database=safe_database_name(),
        schema="BRONZE",
        session_parameters={"QUERY_TAG": "lab_semana07_nyc_taxi_ingestion"},
    )


def ensure_bronze_objects(cursor, database: str) -> None:
    cursor.execute(f"CREATE SCHEMA IF NOT EXISTS {database}.BRONZE")
    cursor.execute(
        f"""
        CREATE TABLE IF NOT EXISTS {database}.BRONZE.YELLOW_TAXI_RAW (
            RAW_RECORD VARIANT NOT NULL,
            SOURCE_FILE VARCHAR NOT NULL,
            SOURCE_PERIOD VARCHAR NOT NULL,
            SOURCE_ROW_NUMBER NUMBER NOT NULL,
            LOADED_AT TIMESTAMP_TZ NOT NULL
        )
        """
    )
    cursor.execute(
        f"""
        CREATE TABLE IF NOT EXISTS {database}.BRONZE.TAXI_ZONE_LOOKUP_RAW (
            LOCATION_ID VARCHAR,
            BOROUGH VARCHAR,
            ZONE VARCHAR,
            SERVICE_ZONE VARCHAR,
            SOURCE_FILE VARCHAR NOT NULL,
            SOURCE_ROW_NUMBER NUMBER NOT NULL,
            LOADED_AT TIMESTAMP_TZ NOT NULL
        )
        """
    )
    cursor.execute(
        f"""
        CREATE TABLE IF NOT EXISTS {database}.BRONZE.INGESTION_AUDIT (
            DATASET VARCHAR NOT NULL,
            SOURCE_PERIOD VARCHAR NOT NULL,
            SOURCE_URL VARCHAR NOT NULL,
            SOURCE_FILE VARCHAR NOT NULL,
            FILE_SHA256 VARCHAR NOT NULL,
            BYTE_COUNT NUMBER NOT NULL,
            ROW_COUNT NUMBER NOT NULL,
            LOADED_AT TIMESTAMP_TZ NOT NULL,
            STATUS VARCHAR NOT NULL,
            PRIMARY KEY (DATASET, SOURCE_PERIOD)
        )
        """
    )
    cursor.execute(f"CREATE STAGE IF NOT EXISTS {database}.BRONZE.NYC_TAXI_STAGE")
    cursor.execute(
        f"""
        CREATE FILE FORMAT IF NOT EXISTS {database}.BRONZE.NYC_TAXI_PARQUET
            TYPE = PARQUET
            USE_LOGICAL_TYPE = TRUE
        """
    )
    cursor.execute(
        f"""
        CREATE FILE FORMAT IF NOT EXISTS {database}.BRONZE.NYC_TAXI_ZONE_CSV
            TYPE = CSV
            FIELD_DELIMITER = ','
            SKIP_HEADER = 1
            FIELD_OPTIONALLY_ENCLOSED_BY = '"'
            NULL_IF = ('', 'NULL', 'null')
            EMPTY_FIELD_AS_NULL = TRUE
            ENCODING = 'UTF8'
            REPLACE_INVALID_CHARACTERS = TRUE
            ERROR_ON_COLUMN_COUNT_MISMATCH = TRUE
        """
    )


def merge_audit(
    cursor,
    database: str,
    dataset: str,
    period: str,
    url: str,
    filename: str,
    sha256: str,
    byte_count: int,
    row_count: int,
) -> None:
    cursor.execute(
        f"""
        MERGE INTO {database}.BRONZE.INGESTION_AUDIT target
        USING (
            SELECT %s DATASET, %s SOURCE_PERIOD, %s SOURCE_URL,
                   %s SOURCE_FILE, %s FILE_SHA256, %s BYTE_COUNT,
                   %s ROW_COUNT, CURRENT_TIMESTAMP() LOADED_AT, 'SUCCESS' STATUS
        ) source
        ON target.DATASET = source.DATASET
           AND target.SOURCE_PERIOD = source.SOURCE_PERIOD
        WHEN MATCHED THEN UPDATE SET
            SOURCE_URL = source.SOURCE_URL,
            SOURCE_FILE = source.SOURCE_FILE,
            FILE_SHA256 = source.FILE_SHA256,
            BYTE_COUNT = source.BYTE_COUNT,
            ROW_COUNT = source.ROW_COUNT,
            LOADED_AT = source.LOADED_AT,
            STATUS = source.STATUS
        WHEN NOT MATCHED THEN INSERT (
            DATASET, SOURCE_PERIOD, SOURCE_URL, SOURCE_FILE, FILE_SHA256,
            BYTE_COUNT, ROW_COUNT, LOADED_AT, STATUS
        ) VALUES (
            source.DATASET, source.SOURCE_PERIOD, source.SOURCE_URL,
            source.SOURCE_FILE, source.FILE_SHA256, source.BYTE_COUNT,
            source.ROW_COUNT, source.LOADED_AT, source.STATUS
        )
        """,
        (dataset, period, url, filename, sha256, byte_count, row_count),
    )


def load_trip_period(
    cursor,
    database: str,
    path: Path,
    period: str,
    url: str,
    sha256: str,
    byte_count: int,
) -> int:
    suffix = period.replace("-", "_")
    temp_table = f"YELLOW_TAXI_LOAD_{suffix}"
    raw_table = f"{database}.BRONZE.YELLOW_TAXI_RAW"
    stage = f"{database}.BRONZE.NYC_TAXI_STAGE"
    file_format = f"{database}.BRONZE.NYC_TAXI_PARQUET"
    stage_path = f"trips/{period}"

    try:
        cursor.execute(f"CREATE OR REPLACE TEMPORARY TABLE {temp_table} LIKE {raw_table}")
        cursor.execute(f"REMOVE @{stage}/{stage_path}")
        cursor.execute(
            f"PUT 'file://{path.as_posix()}' @{stage}/{stage_path} "
            "AUTO_COMPRESS=FALSE OVERWRITE=TRUE PARALLEL=4"
        )
        cursor.execute(
            f"""
            COPY INTO {temp_table} (
                RAW_RECORD,
                SOURCE_FILE,
                SOURCE_PERIOD,
                SOURCE_ROW_NUMBER,
                LOADED_AT
            )
            FROM (
                SELECT
                    $1,
                    METADATA$FILENAME,
                    '{period}',
                    METADATA$FILE_ROW_NUMBER,
                    CURRENT_TIMESTAMP()
                FROM @{stage}/{stage_path} (FILE_FORMAT => '{file_format}')
            )
            ON_ERROR = 'ABORT_STATEMENT'
            """
        )
        cursor.execute(f"SELECT COUNT(*) FROM {temp_table}")
        row_count = int(cursor.fetchone()[0])
        if row_count == 0:
            raise RuntimeError(f"Snowflake no cargó filas para {period}")

        cursor.execute("BEGIN")
        cursor.execute(f"DELETE FROM {raw_table} WHERE SOURCE_PERIOD = %s", (period,))
        cursor.execute(f"INSERT INTO {raw_table} SELECT * FROM {temp_table}")
        merge_audit(
            cursor,
            database,
            "yellow_taxi",
            period,
            url,
            path.name,
            sha256,
            byte_count,
            row_count,
        )
        cursor.execute("COMMIT")
        return row_count
    except Exception:
        try:
            cursor.execute("ROLLBACK")
        except Exception:
            pass
        raise
    finally:
        try:
            cursor.execute(f"REMOVE @{stage}/{stage_path}")
        except Exception as cleanup_error:
            log("stage_cleanup_warning", period=period, error=str(cleanup_error))


def load_zone_lookup(
    cursor,
    database: str,
    path: Path,
    sha256: str,
    byte_count: int,
) -> int:
    raw_table = f"{database}.BRONZE.TAXI_ZONE_LOOKUP_RAW"
    temp_table = "TAXI_ZONE_LOOKUP_LOAD"
    stage = f"{database}.BRONZE.NYC_TAXI_STAGE"
    file_format = f"{database}.BRONZE.NYC_TAXI_ZONE_CSV"
    stage_path = "zones/current"

    try:
        cursor.execute(f"CREATE OR REPLACE TEMPORARY TABLE {temp_table} LIKE {raw_table}")
        cursor.execute(f"REMOVE @{stage}/{stage_path}")
        cursor.execute(
            f"PUT 'file://{path.as_posix()}' @{stage}/{stage_path} "
            "AUTO_COMPRESS=TRUE OVERWRITE=TRUE PARALLEL=2"
        )
        cursor.execute(
            f"""
            COPY INTO {temp_table} (
                LOCATION_ID,
                BOROUGH,
                ZONE,
                SERVICE_ZONE,
                SOURCE_FILE,
                SOURCE_ROW_NUMBER,
                LOADED_AT
            )
            FROM (
                SELECT
                    $1::VARCHAR,
                    $2::VARCHAR,
                    $3::VARCHAR,
                    $4::VARCHAR,
                    METADATA$FILENAME,
                    METADATA$FILE_ROW_NUMBER,
                    CURRENT_TIMESTAMP()
                FROM @{stage}/{stage_path} (FILE_FORMAT => '{file_format}')
            )
            ON_ERROR = 'ABORT_STATEMENT'
            """
        )
        cursor.execute(f"SELECT COUNT(*) FROM {temp_table}")
        row_count = int(cursor.fetchone()[0])
        if row_count == 0:
            raise RuntimeError("Snowflake no cargó filas del catálogo de zonas")

        cursor.execute("BEGIN")
        cursor.execute(f"DELETE FROM {raw_table}")
        cursor.execute(f"INSERT INTO {raw_table} SELECT * FROM {temp_table}")
        merge_audit(
            cursor,
            database,
            "taxi_zone_lookup",
            "CURRENT",
            ZONE_URL,
            path.name,
            sha256,
            byte_count,
            row_count,
        )
        cursor.execute("COMMIT")
        return row_count
    except Exception:
        try:
            cursor.execute("ROLLBACK")
        except Exception:
            pass
        raise
    finally:
        try:
            cursor.execute(f"REMOVE @{stage}/{stage_path}")
        except Exception as cleanup_error:
            log("stage_cleanup_warning", dataset="taxi_zone_lookup", error=str(cleanup_error))


def main() -> None:
    periods = configured_periods()
    fail_on_missing = boolean_env("FAIL_ON_MISSING", True)
    session = http_session()

    log("source_preflight_started", requested_periods=len(periods))
    missing_periods = [
        period for period in periods if not source_exists(session, trip_url(period))
    ]
    if missing_periods and fail_on_missing:
        raise RuntimeError(
            "TLC todavía no publicó todos los archivos requeridos. "
            f"Periodos faltantes: {missing_periods}. "
            "No se ejecutó una carga parcial. Puede usarse FAIL_ON_MISSING=false "
            "solo para una demostración explícitamente incompleta."
        )
    available_periods = [period for period in periods if period not in missing_periods]
    log(
        "source_preflight_complete",
        available=len(available_periods),
        missing=missing_periods,
    )

    database = safe_database_name()
    connection = snowflake_connection()
    cursor = connection.cursor()
    loaded_periods: dict[str, int] = {}
    try:
        ensure_bronze_objects(cursor, database)
        with tempfile.TemporaryDirectory(prefix="nyc_taxi_") as temp_directory:
            temp_path = Path(temp_directory)

            zone_path = temp_path / "taxi_zone_lookup.csv"
            log("download_started", dataset="taxi_zone_lookup", url=ZONE_URL)
            zone_sha256, zone_bytes = download(session, ZONE_URL, zone_path)
            validate_zone_csv(zone_path)
            zone_rows = load_zone_lookup(
                cursor, database, zone_path, zone_sha256, zone_bytes
            )
            log("bronze_load_complete", dataset="taxi_zone_lookup", rows=zone_rows)

            for index, period in enumerate(available_periods, start=1):
                url = trip_url(period)
                parquet_path = temp_path / f"yellow_tripdata_{period}.parquet"
                log(
                    "download_started",
                    dataset="yellow_taxi",
                    period=period,
                    item=index,
                    total=len(available_periods),
                    url=url,
                )
                sha256, byte_count = download(session, url, parquet_path)
                validate_parquet(parquet_path)
                row_count = load_trip_period(
                    cursor,
                    database,
                    parquet_path,
                    period,
                    url,
                    sha256,
                    byte_count,
                )
                loaded_periods[period] = row_count
                parquet_path.unlink(missing_ok=True)
                log(
                    "bronze_load_complete",
                    dataset="yellow_taxi",
                    period=period,
                    rows=row_count,
                    bytes=byte_count,
                    sha256=sha256,
                )
    finally:
        cursor.close()
        connection.close()
        session.close()

    log(
        "ingestion_complete",
        requested_periods=len(periods),
        loaded_periods=len(loaded_periods),
        missing_periods=missing_periods,
        rows_loaded=sum(loaded_periods.values()),
        completed_at_utc=datetime.now(timezone.utc).isoformat(timespec="seconds"),
    )


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        log("pipeline_error", error=type(error).__name__, detail=str(error))
        raise
