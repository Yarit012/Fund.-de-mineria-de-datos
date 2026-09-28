with normalized as (
    select
        try_to_number(nullif(trim(location_id), ''))::number(5, 0) as location_id,
        upper(regexp_replace(trim(borough), '\\s+', ' ')) as borough,
        regexp_replace(trim(zone), '\\s+', ' ') as zone_name,
        upper(regexp_replace(trim(service_zone), '\\s+', ' ')) as service_zone,
        source_file,
        source_row_number,
        loaded_at
    from {{ source('bronze', 'taxi_zone_lookup_raw') }}
)

select *
from normalized
where location_id is not null
qualify row_number() over (
    partition by location_id
    order by loaded_at desc, source_row_number
) = 1

