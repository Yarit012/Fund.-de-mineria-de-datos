{{ config(materialized='view') }}

with extracted as (
    select
        raw_record,
        source_file,
        source_period,
        source_row_number,
        loaded_at,
        get_ignore_case(raw_record, 'VendorID')::varchar as vendor_id_raw,
        get_ignore_case(raw_record, 'tpep_pickup_datetime')::varchar as pickup_at_raw,
        get_ignore_case(raw_record, 'tpep_dropoff_datetime')::varchar as dropoff_at_raw,
        get_ignore_case(raw_record, 'passenger_count')::varchar as passenger_count_raw,
        get_ignore_case(raw_record, 'trip_distance')::varchar as trip_distance_raw,
        get_ignore_case(raw_record, 'RatecodeID')::varchar as rate_code_id_raw,
        get_ignore_case(raw_record, 'store_and_fwd_flag')::varchar as store_and_fwd_flag_raw,
        get_ignore_case(raw_record, 'PULocationID')::varchar as pickup_location_id_raw,
        get_ignore_case(raw_record, 'DOLocationID')::varchar as dropoff_location_id_raw,
        get_ignore_case(raw_record, 'payment_type')::varchar as payment_type_raw,
        get_ignore_case(raw_record, 'fare_amount')::varchar as fare_amount_raw,
        get_ignore_case(raw_record, 'extra')::varchar as extra_raw,
        get_ignore_case(raw_record, 'mta_tax')::varchar as mta_tax_raw,
        get_ignore_case(raw_record, 'tip_amount')::varchar as tip_amount_raw,
        get_ignore_case(raw_record, 'tolls_amount')::varchar as tolls_amount_raw,
        get_ignore_case(raw_record, 'improvement_surcharge')::varchar as improvement_surcharge_raw,
        get_ignore_case(raw_record, 'total_amount')::varchar as total_amount_raw,
        get_ignore_case(raw_record, 'congestion_surcharge')::varchar as congestion_surcharge_raw,
        get_ignore_case(raw_record, 'airport_fee')::varchar as airport_fee_raw,
        get_ignore_case(raw_record, 'cbd_congestion_fee')::varchar as cbd_congestion_fee_raw
    from {{ source('bronze', 'yellow_taxi_raw') }}
),

typed as (
    select
        md5(concat(source_file, '|', source_row_number::varchar)) as trip_sk,
        source_file,
        source_period,
        source_row_number,
        loaded_at,
        try_to_date(concat(source_period, '-01')) as source_period_start,
        try_to_number(nullif(trim(vendor_id_raw), ''))::number(3, 0) as vendor_id,
        try_to_timestamp_ntz(nullif(trim(pickup_at_raw), '')) as pickup_at,
        try_to_timestamp_ntz(nullif(trim(dropoff_at_raw), '')) as dropoff_at,
        try_to_number(nullif(trim(passenger_count_raw), ''))::number(5, 0) as passenger_count,
        try_to_decimal(nullif(trim(trip_distance_raw), ''), 14, 3) as trip_distance_miles,
        try_to_number(nullif(trim(rate_code_id_raw), ''))::number(3, 0) as rate_code_id,
        case upper(trim(store_and_fwd_flag_raw))
            when 'Y' then 'Y'
            when 'N' then 'N'
            else null
        end as store_and_fwd_flag,
        try_to_number(nullif(trim(pickup_location_id_raw), ''))::number(5, 0) as pickup_location_id,
        try_to_number(nullif(trim(dropoff_location_id_raw), ''))::number(5, 0) as dropoff_location_id,
        try_to_number(nullif(trim(payment_type_raw), ''))::number(3, 0) as payment_type,
        try_to_decimal(nullif(trim(fare_amount_raw), ''), 14, 2) as fare_amount,
        try_to_decimal(nullif(trim(extra_raw), ''), 14, 2) as extra_amount,
        try_to_decimal(nullif(trim(mta_tax_raw), ''), 14, 2) as mta_tax_amount,
        try_to_decimal(nullif(trim(tip_amount_raw), ''), 14, 2) as tip_amount,
        try_to_decimal(nullif(trim(tolls_amount_raw), ''), 14, 2) as tolls_amount,
        try_to_decimal(nullif(trim(improvement_surcharge_raw), ''), 14, 2) as improvement_surcharge_amount,
        try_to_decimal(nullif(trim(total_amount_raw), ''), 14, 2) as total_amount,
        try_to_decimal(nullif(trim(congestion_surcharge_raw), ''), 14, 2) as congestion_surcharge_amount,
        try_to_decimal(nullif(trim(airport_fee_raw), ''), 14, 2) as airport_fee_amount,
        try_to_decimal(nullif(trim(cbd_congestion_fee_raw), ''), 14, 2) as cbd_congestion_fee_amount
    from extracted
),

derived as (
    select
        *,
        round(datediff('second', pickup_at, dropoff_at) / 60.0, 2) as trip_duration_minutes,
        pickup_at >= source_period_start
            and pickup_at < dateadd('month', 1, source_period_start) as is_source_period_match,
        passenger_count is not null
            and (passenger_count < 0 or passenger_count > 9) as has_passenger_count_anomaly,
        coalesce(fare_amount < 0, false)
            or coalesce(extra_amount < 0, false)
            or coalesce(mta_tax_amount < 0, false)
            or coalesce(tip_amount < 0, false)
            or coalesce(tolls_amount < 0, false)
            or coalesce(total_amount < 0, false) as has_financial_anomaly,
        md5(concat_ws(
            '|',
            coalesce(vendor_id::varchar, '<NULL>'),
            coalesce(pickup_at::varchar, '<NULL>'),
            coalesce(dropoff_at::varchar, '<NULL>'),
            coalesce(passenger_count::varchar, '<NULL>'),
            coalesce(trip_distance_miles::varchar, '<NULL>'),
            coalesce(rate_code_id::varchar, '<NULL>'),
            coalesce(store_and_fwd_flag, '<NULL>'),
            coalesce(pickup_location_id::varchar, '<NULL>'),
            coalesce(dropoff_location_id::varchar, '<NULL>'),
            coalesce(payment_type::varchar, '<NULL>'),
            coalesce(fare_amount::varchar, '<NULL>'),
            coalesce(extra_amount::varchar, '<NULL>'),
            coalesce(mta_tax_amount::varchar, '<NULL>'),
            coalesce(tip_amount::varchar, '<NULL>'),
            coalesce(tolls_amount::varchar, '<NULL>'),
            coalesce(improvement_surcharge_amount::varchar, '<NULL>'),
            coalesce(total_amount::varchar, '<NULL>'),
            coalesce(congestion_surcharge_amount::varchar, '<NULL>'),
            coalesce(airport_fee_amount::varchar, '<NULL>'),
            coalesce(cbd_congestion_fee_amount::varchar, '<NULL>')
        )) as record_hash
    from typed
),

enriched as (
    select
        *,
        case
            when pickup_at is null or dropoff_at is null then 'MISSING_TIMESTAMP'
            when dropoff_at < pickup_at then 'INVALID_CHRONOLOGY'
            when datediff('second', pickup_at, dropoff_at) > 86400 then 'DURATION_OVER_24H'
            when trip_distance_miles is null or trip_distance_miles < 0 then 'INVALID_DISTANCE'
            when pickup_location_id is null or pickup_location_id <= 0
              or dropoff_location_id is null or dropoff_location_id <= 0 then 'MISSING_LOCATION'
            when not is_source_period_match then 'PERIOD_MISMATCH'
            else 'PASS'
        end as dq_status
    from derived
),

ranked as (
    select
        *,
        row_number() over (
            partition by record_hash
            order by source_period, source_file, source_row_number
        ) as duplicate_rank
    from enriched
)

select *
from ranked
