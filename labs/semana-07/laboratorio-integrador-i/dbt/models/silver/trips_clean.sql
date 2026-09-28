select
    trip_sk,
    vendor_id,
    pickup_at,
    dropoff_at,
    passenger_count,
    trip_distance_miles,
    trip_duration_minutes,
    rate_code_id,
    store_and_fwd_flag,
    pickup_location_id,
    dropoff_location_id,
    payment_type,
    fare_amount,
    extra_amount,
    mta_tax_amount,
    tip_amount,
    tolls_amount,
    improvement_surcharge_amount,
    total_amount,
    congestion_surcharge_amount,
    airport_fee_amount,
    cbd_congestion_fee_amount,
    has_passenger_count_anomaly,
    has_financial_anomaly,
    source_file,
    source_period,
    source_row_number,
    loaded_at,
    record_hash
from {{ ref('stg_yellow_taxi_trips') }}
where dq_status = 'PASS'
  and duplicate_rank = 1

