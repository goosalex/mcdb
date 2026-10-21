-- probe: steps
SELECT step, code, msg, s FROM diff_probe ORDER BY step;

-- probe: dev instance condition as the routine evaluates it (S-UTIL-011; PostgreSQL twin in probe.pg.sql)
SELECT COUNT(*) AS is_dev FROM v$instance WHERE host_name LIKE '%-dev-%';

-- probe: fixture tickets untouched (eligible 958400 keeps its status on a non-dev instance; 958402 is closed, not open: deferred check C_TICKET_2)
SELECT id, status_id, handled_by_mcc,
       CASE WHEN open_date < CURRENT_TIMESTAMP - INTERVAL '30' DAY THEN 1 ELSE 0 END AS older_than_30d,
       CASE WHEN close_date IS NOT NULL THEN 1 ELSE 0 END AS has_close_date
FROM tt.ticket WHERE id BETWEEN 958400 AND 958402 ORDER BY id;

-- probe: no event written for the fixture tickets
SELECT type_id, ticket_id, details_public FROM tt.event WHERE ticket_id BETWEEN 958400 AND 958402 ORDER BY ticket_id, type_id;
