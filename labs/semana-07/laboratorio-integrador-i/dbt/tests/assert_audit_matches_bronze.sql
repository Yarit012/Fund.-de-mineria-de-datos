with bronze_counts as (
    select source_period, count(*) as row_count
    from {{ source('bronze', 'yellow_taxi_raw') }}
    group by source_period
),

audit_counts as (
    select source_period, row_count
    from {{ source('bronze', 'ingestion_audit') }}
    where dataset = 'yellow_taxi'
      and status = 'SUCCESS'
)

select
    coalesce(bronze_counts.source_period, audit_counts.source_period) as source_period,
    bronze_counts.row_count as bronze_row_count,
    audit_counts.row_count as audit_row_count
from bronze_counts
full outer join audit_counts using (source_period)
where bronze_counts.row_count is distinct from audit_counts.row_count

