select
    source_period,
    count(*) as trip_count,
    sum(coalesce(passenger_count, 0)) as reported_passenger_count,
    round(sum(trip_distance_miles), 2) as total_distance_miles,
    round(avg(trip_distance_miles), 2) as avg_distance_miles,
    round(avg(trip_duration_minutes), 2) as avg_duration_minutes,
    round(sum(total_amount), 2) as total_revenue_amount,
    round(sum(tip_amount), 2) as total_tip_amount,
    round(avg(tip_percentage), 2) as avg_tip_percentage,
    count_if(payment_type_key = 1) as credit_card_trip_count,
    count_if(has_financial_anomaly) as financial_anomaly_count
from {{ ref('fct_trips') }}
group by source_period

