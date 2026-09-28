select
    -1::number(5, 0) as location_key,
    'UNKNOWN'::varchar as borough,
    'Unknown or unmapped'::varchar as zone_name,
    'UNKNOWN'::varchar as service_zone

union all

select
    location_id as location_key,
    borough,
    zone_name,
    coalesce(service_zone, 'UNKNOWN') as service_zone
from {{ ref('taxi_zones_clean') }}

