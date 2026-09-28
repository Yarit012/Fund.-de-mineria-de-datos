with trips as (
    select *
    from {{ ref('trips_clean') }}
),

known_locations as (
    select location_id
    from {{ ref('taxi_zones_clean') }}
)

select
    trips.trip_sk,
    to_number(to_char(to_date(trips.pickup_at), 'YYYYMMDD')) as pickup_date_key,
    to_number(to_char(to_date(trips.dropoff_at), 'YYYYMMDD')) as dropoff_date_key,
    case when pickup_zone.location_id is null then -1
         else trips.pickup_location_id end as pickup_location_key,
    case when dropoff_zone.location_id is null then -1
         else trips.dropoff_location_id end as dropoff_location_key,
    case when trips.vendor_id in (1, 2, 6, 7) then trips.vendor_id else -1 end as vendor_key,
    case when trips.payment_type in (0, 1, 2, 3, 4, 5, 6)
         then trips.payment_type else -1 end as payment_type_key,
    case when trips.rate_code_id in (1, 2, 3, 4, 5, 6, 99)
         then trips.rate_code_id else -1 end as rate_code_key,
    hour(trips.pickup_at) as pickup_hour,
    hour(trips.dropoff_at) as dropoff_hour,
    trips.store_and_fwd_flag,
    trips.passenger_count,
    trips.trip_distance_miles,
    trips.trip_duration_minutes,
    trips.fare_amount,
    trips.extra_amount,
    trips.mta_tax_amount,
    trips.tip_amount,
    trips.tolls_amount,
    trips.improvement_surcharge_amount,
    trips.total_amount,
    trips.congestion_surcharge_amount,
    trips.airport_fee_amount,
    trips.cbd_congestion_fee_amount,
    case
        when trips.fare_amount > 0 then round(100 * trips.tip_amount / trips.fare_amount, 2)
        else null
    end as tip_percentage,
    1::number as trip_count,
    trips.has_passenger_count_anomaly,
    trips.has_financial_anomaly,
    trips.source_period,
    trips.source_file,
    trips.source_row_number,
    trips.loaded_at
from trips
left join known_locations pickup_zone
    on trips.pickup_location_id = pickup_zone.location_id
left join known_locations dropoff_zone
    on trips.dropoff_location_id = dropoff_zone.location_id

