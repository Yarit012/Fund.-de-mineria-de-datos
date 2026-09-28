select
    source_period,
    count(*) as raw_row_count,
    count_if(dq_status = 'PASS' and duplicate_rank = 1) as usable_row_count,
    count_if(duplicate_rank > 1) as exact_duplicate_count,
    count_if(dq_status = 'MISSING_TIMESTAMP') as missing_timestamp_count,
    count_if(dq_status = 'INVALID_CHRONOLOGY') as invalid_chronology_count,
    count_if(dq_status = 'DURATION_OVER_24H') as excessive_duration_count,
    count_if(dq_status = 'INVALID_DISTANCE') as invalid_distance_count,
    count_if(dq_status = 'MISSING_LOCATION') as missing_location_count,
    count_if(dq_status = 'PERIOD_MISMATCH') as period_mismatch_count,
    count_if(has_passenger_count_anomaly) as passenger_count_anomaly_count,
    count_if(has_financial_anomaly) as financial_anomaly_count,
    round(
        100.0 * count_if(dq_status = 'PASS' and duplicate_rank = 1)
        / nullif(count(*), 0),
        2
    ) as usable_percentage,
    max(loaded_at) as latest_load_at
from {{ ref('stg_yellow_taxi_trips') }}
group by source_period

