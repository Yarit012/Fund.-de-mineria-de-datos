select
    column1::number(3, 0) as rate_code_key,
    column2::varchar as rate_code_name
from values
    (-1, 'Unknown or unmapped'),
    (1, 'Standard rate'),
    (2, 'JFK'),
    (3, 'Newark'),
    (4, 'Nassau or Westchester'),
    (5, 'Negotiated fare'),
    (6, 'Group ride'),
    (99, 'Null or unknown')

