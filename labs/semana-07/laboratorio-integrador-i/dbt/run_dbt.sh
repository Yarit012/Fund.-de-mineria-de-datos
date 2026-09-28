#!/usr/bin/env bash
set -euo pipefail

dbt deps --project-dir /opt/dbt --profiles-dir /opt/dbt

arguments=(
  build
  --project-dir /opt/dbt
  --profiles-dir /opt/dbt
  --no-partial-parse
)

if [[ "${ENFORCE_20_PERIODS:-true}" != "true" ]]; then
  echo "Modo demostración: se omite únicamente assert_20_periods_loaded."
  arguments+=(--exclude assert_20_periods_loaded)
fi

dbt "${arguments[@]}"
