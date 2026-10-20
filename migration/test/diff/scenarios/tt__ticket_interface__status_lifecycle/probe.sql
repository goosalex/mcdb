-- probe: steps (post-step status in n, valid-until set/null in s; error code for failed steps)
SELECT step, code, msg, n, s FROM diff_probe ORDER BY step;

-- probe: ticket row
SELECT id, type_id, status_id, subject, recoverable_status_id, escalation_status_id, handled_by_mcc,
       CASE WHEN last_status_change_date IS NOT NULL THEN 1 ELSE 0 END AS has_last_status_change,
       CASE WHEN status_valid_until_date IS NOT NULL THEN 1 ELSE 0 END AS has_valid_until,
       CASE WHEN last_resolved_date IS NOT NULL THEN 1 ELSE 0 END AS has_last_resolved,
       CASE WHEN last_public_event_id IS NOT NULL THEN 1 ELSE 0 END AS has_last_public_event
FROM tt.ticket WHERE id = 950010 ORDER BY id;

-- probe: events written by the routines (the fixture event 950011 excluded)
SELECT type_id, ticket_id, public_event, company_id, contact_id, details_public, details_private
FROM tt.event WHERE ticket_id = 950010 AND id <> 950011 ORDER BY type_id, details_public;

-- probe: ticket_flow rows
SELECT ticket_id, CASE WHEN flow_out_date IS NULL THEN 0 ELSE 1 END AS flow_closed, COUNT(*) AS n_rows
FROM tt.ticket_flow WHERE ticket_id = 950010 GROUP BY ticket_id, CASE WHEN flow_out_date IS NULL THEN 0 ELSE 1 END
ORDER BY 2;

-- probe: ticket_time_statistic rows (presence and which counters are non-zero)
SELECT ticket_id,
       CASE WHEN open_time > 0 THEN 1 ELSE 0 END AS has_open_time,
       CASE WHEN waiting_time > 0 THEN 1 ELSE 0 END AS has_waiting_time,
       CASE WHEN third_party_time > 0 THEN 1 ELSE 0 END AS has_third_party_time,
       CASE WHEN deferred_time > 0 THEN 1 ELSE 0 END AS has_deferred_time,
       CASE WHEN resolved_time > 0 THEN 1 ELSE 0 END AS has_resolved_time
FROM tt.ticket_time_statistic WHERE ticket_id = 950010 ORDER BY ticket_id;
