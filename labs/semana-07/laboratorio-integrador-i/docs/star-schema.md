# Esquema estrella

## Grano

`GOLD.FCT_TRIPS` contiene **exactamente una fila por viaje Yellow Taxi válido y deduplicado**. El identificador técnico `TRIP_SK` se deriva del archivo y número de fila originales. `TRIP_COUNT` vale 1 y permite agregaciones explícitas.

```mermaid
erDiagram
    DIM_DATE ||--o{ FCT_TRIPS : "pickup_date_key"
    DIM_DATE ||--o{ FCT_TRIPS : "dropoff_date_key"
    DIM_LOCATION ||--o{ FCT_TRIPS : "pickup_location_key"
    DIM_LOCATION ||--o{ FCT_TRIPS : "dropoff_location_key"
    DIM_VENDOR ||--o{ FCT_TRIPS : "vendor_key"
    DIM_PAYMENT_TYPE ||--o{ FCT_TRIPS : "payment_type_key"
    DIM_RATE_CODE ||--o{ FCT_TRIPS : "rate_code_key"

    FCT_TRIPS {
        varchar trip_sk PK
        number pickup_date_key FK
        number dropoff_date_key FK
        number pickup_location_key FK
        number dropoff_location_key FK
        number vendor_key FK
        number payment_type_key FK
        number rate_code_key FK
        number passenger_count
        decimal trip_distance_miles
        decimal trip_duration_minutes
        decimal fare_amount
        decimal tip_amount
        decimal total_amount
        number trip_count
    }
    DIM_DATE {
        number date_key PK
        date date_day
        number year_number
        number month_number
        number iso_day_of_week
        boolean is_weekend
    }
    DIM_LOCATION {
        number location_key PK
        varchar borough
        varchar zone_name
        varchar service_zone
    }
    DIM_VENDOR {
        number vendor_key PK
        varchar vendor_name
    }
    DIM_PAYMENT_TYPE {
        number payment_type_key PK
        varchar payment_type_name
    }
    DIM_RATE_CODE {
        number rate_code_key PK
        varchar rate_code_name
    }
```

## Claves

| Objeto | Primary key lógica | Uso |
|---|---|---|
| `FCT_TRIPS` | `TRIP_SK` | Identifica el viaje cargado desde una fila fuente. |
| `DIM_DATE` | `DATE_KEY` (`YYYYMMDD`) | Fecha de recogida y fecha de llegada. |
| `DIM_LOCATION` | `LOCATION_KEY` | Zona TLC de recogida y llegada. |
| `DIM_VENDOR` | `VENDOR_KEY` | Proveedor TPEP. |
| `DIM_PAYMENT_TYPE` | `PAYMENT_TYPE_KEY` | Forma de pago. |
| `DIM_RATE_CODE` | `RATE_CODE_KEY` | Tarifa final aplicada. |

Snowflake declara restricciones de forma informativa; la integridad se hace exigible mediante los tests `unique`, `not_null` y `relationships` de dbt.

## Métricas y atributos

- Métricas aditivas: viajes, pasajeros reportados, distancia, tarifa, propina, peajes, recargos y total cobrado.
- Métricas derivadas: duración en minutos y porcentaje de propina.
- Atributos de análisis: fecha, hora, zona, borough, proveedor, forma de pago, tarifa, bandera store-and-forward y anomalías de calidad.
- `GOLD.AGG_MONTHLY_KPIS` ofrece una salida mensual lista para revisión.

