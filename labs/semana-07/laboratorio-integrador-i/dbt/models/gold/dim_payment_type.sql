select
    column1::number(3, 0) as payment_type_key,
    column2::varchar as payment_type_name
from values
    (-1, 'Unknown or unmapped'),
    (0, 'Flex Fare trip'),
    (1, 'Credit card'),
    (2, 'Cash'),
    (3, 'No charge'),
    (4, 'Dispute'),
    (5, 'Unknown'),
    (6, 'Voided trip')

