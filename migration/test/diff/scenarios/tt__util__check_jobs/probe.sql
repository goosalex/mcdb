-- probe: steps (closed fixture tickets in n, status histogram in s, error code for failed steps)
SELECT step, code, msg, n, s FROM diff_probe ORDER BY step;

-- probe: ticket rows (dates as flags and windows, never as absolute values)
SELECT id, status_id, type_id,
       CASE WHEN close_date IS NOT NULL THEN 1 ELSE 0 END AS has_close_date,
       CASE WHEN status_valid_until_date IS NOT NULL THEN 1 ELSE 0 END AS has_valid_until,
       CASE WHEN status_valid_until_date > CURRENT_TIMESTAMP + INTERVAL '3' HOUR AND status_valid_until_date < CURRENT_TIMESTAMP + INTERVAL '5' HOUR THEN 1 ELSE 0 END AS valid_until_in_4h,
       CASE WHEN status_valid_until_date > CURRENT_TIMESTAMP + INTERVAL '9' DAY AND status_valid_until_date < CURRENT_TIMESTAMP + INTERVAL '11' DAY THEN 1 ELSE 0 END AS valid_until_in_10d,
       CASE WHEN status_valid_until_date > CURRENT_TIMESTAMP + INTERVAL '19' DAY AND status_valid_until_date < CURRENT_TIMESTAMP + INTERVAL '21' DAY THEN 1 ELSE 0 END AS valid_until_in_20d,
       CASE WHEN last_deferral_date IS NOT NULL THEN 1 ELSE 0 END AS has_last_deferral,
       CASE WHEN last_deferral_date > CURRENT_TIMESTAMP THEN 1 ELSE 0 END AS last_deferral_future,
       CASE WHEN last_resolved_date IS NOT NULL THEN 1 ELSE 0 END AS has_last_resolved
FROM tt.ticket WHERE id BETWEEN 958310 AND 958347 ORDER BY id;

-- probe: events written by the routines (the fixture events 958330-958335 excluded)
SELECT type_id, ticket_id, public_event, details_public, details_private
FROM tt.event WHERE ticket_id BETWEEN 958310 AND 958347 AND id NOT BETWEEN 958330 AND 958335
ORDER BY ticket_id, type_id, details_public, details_private;

-- probe: notifications of the fixture login after the resolved ticket was closed
SELECT COUNT(*) AS n_left FROM tt.event_notification WHERE login_id = 958305;
