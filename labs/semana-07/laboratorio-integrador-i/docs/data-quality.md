# Tratamiento y justificación de calidad

| Dimensión | Regla aplicada | Justificación |
|---|---|---|
| Tipos | `TRY_TO_*` convierte timestamps, enteros y decimales. | Un valor mal formado queda nulo y puede medirse sin abortar todo el lote. |
| Nulos obligatorios | Se rechaza para Gold un viaje sin pickup, dropoff, distancia o zonas. | Sin esos campos no puede respetarse el grano ni analizar tiempo, movilidad o ubicación. |
| Nulos opcionales | `passenger_count`, códigos y montos opcionales permanecen nulos. | Imputar cero inventaría información y sesgaría promedios. En dimensiones, códigos desconocidos se asignan al miembro `-1`. |
| Duplicados | Se calcula `RECORD_HASH` con todos los atributos de negocio y se conserva la primera copia exacta. | TLC no publica una clave única de viaje; el hash elimina copias idénticas sin confundir viajes distintos parecidos. |
| Cronología | `dropoff_at >= pickup_at` y duración máxima de 24 horas. | Una llegada anterior es imposible; más de 24 h es incompatible con un viaje de taxi normal y suele indicar timestamp corrupto. |
| Distancia | Debe existir y ser `>= 0`. | Distancias negativas son físicamente inválidas; cero se conserva porque puede representar cancelación, redondeo o viaje sin avance. |
| Período | El pickup debe pertenecer al mes indicado por `SOURCE_PERIOD`. | Evita que fechas corruptas o registros fuera de archivo contaminen el rango solicitado. |
| Nombres | Se eliminan espacios sobrantes/repetidos; borough y service zone se llevan a mayúsculas. | Produce categorías consistentes sin alterar el nombre descriptivo de la zona. |
| Pasajeros | Valores fuera de 0–9 se marcan como anomalía, pero no eliminan el viaje. | Es un campo reportado por el conductor; puede faltar o contener ruido sin invalidar los demás hechos del viaje. |
| Montos negativos | Se marcan como anomalía, pero se conservan. | Pueden representar ajustes, disputas o devoluciones; eliminarlos sesgaría los ingresos. |

`SILVER.DQ_TRIPS_SUMMARY` muestra los conteos por regla y período. Esto evita que las decisiones de limpieza queden ocultas.

## Estado de calidad

Cada fila tipificada recibe un `DQ_STATUS` excluyente:

1. `MISSING_TIMESTAMP`
2. `INVALID_CHRONOLOGY`
3. `DURATION_OVER_24H`
4. `INVALID_DISTANCE`
5. `MISSING_LOCATION`
6. `PERIOD_MISMATCH`
7. `PASS`

Solo `PASS` y `DUPLICATE_RANK = 1` entra en `SILVER.TRIPS_CLEAN` y posteriormente en Gold. Las filas rechazadas siguen disponibles en Bronze y en la vista de staging para auditoría.

