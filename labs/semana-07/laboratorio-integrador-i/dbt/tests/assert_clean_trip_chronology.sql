select trip_sk, pickup_at, dropoff_at, trip_duration_minutes
from {{ ref('trips_clean') }}
where dropoff_at < pickup_at
   or trip_duration_minutes < 0
   or trip_duration_minutes > 1440

