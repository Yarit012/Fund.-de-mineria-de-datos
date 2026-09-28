with generated as (
    select row_number() over (order by seq4()) - 1 as day_offset
    from table(generator(rowcount => 1461))
),

dates as (
    select dateadd('day', day_offset, to_date('2024-01-01')) as date_day
    from generated
)

select
    to_number(to_char(date_day, 'YYYYMMDD')) as date_key,
    date_day,
    year(date_day) as year_number,
    quarter(date_day) as quarter_number,
    month(date_day) as month_number,
    monthname(date_day) as month_name,
    weekiso(date_day) as iso_week_number,
    day(date_day) as day_of_month,
    dayofweekiso(date_day) as iso_day_of_week,
    dayname(date_day) as day_name,
    dayofweekiso(date_day) in (6, 7) as is_weekend
from dates

