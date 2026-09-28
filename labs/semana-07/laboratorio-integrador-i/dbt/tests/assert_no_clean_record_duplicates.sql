select record_hash, count(*) as duplicate_count
from {{ ref('trips_clean') }}
group by record_hash
having count(*) > 1

