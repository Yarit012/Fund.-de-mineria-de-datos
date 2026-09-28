select
    column1::number(3, 0) as vendor_key,
    column2::varchar as vendor_name
from values
    (-1, 'Unknown or unmapped'),
    (1, 'Creative Mobile Technologies, LLC'),
    (2, 'Curb Mobility, LLC'),
    (6, 'Myle Technologies Inc'),
    (7, 'Helix')

