-- probe: steps (post-step status, valid-until set/null and OUT event id flag in s; error code for failed steps -- no quotes in labels)
SELECT step, code, msg, s FROM diff_probe ORDER BY step;

-- probe: ticket rows after all steps (escalation, recoverable status, deferral flags, resolved flag, UX start re-anchored flag)
SELECT id, status_id, escalation_status_id, recoverable_status_id, last_deferral_escalated,
       CASE WHEN status_valid_until_date IS NOT NULL THEN 1 ELSE 0 END AS has_valid_until,
       EXTRACT(DAY FROM last_deferral_date) AS last_deferral_day,
       CASE WHEN last_resolved_date IS NOT NULL THEN 1 ELSE 0 END AS has_last_resolved,
       CASE WHEN last_escalation_date IS NOT NULL THEN 1 ELSE 0 END AS has_last_escalation,
       CASE WHEN ux_timeout_start > TIMESTAMP '2026-01-10 10:00:00' THEN 1 ELSE 0 END AS ux_start_moved,
       CASE WHEN ux_timeout IS NOT NULL THEN 1 ELSE 0 END AS has_ux_timeout
FROM tt.ticket WHERE id BETWEEN 952310 AND 952316 ORDER BY id;

-- probe: events written by the routines (status change, hot non-MCC, escalation start/end; texts compared verbatim)
SELECT ticket_id, type_id, public_event, contact_id, contact_zitadel_id, details_public, details_private
FROM tt.event WHERE ticket_id BETWEEN 952310 AND 952316
ORDER BY ticket_id, type_id, details_public, details_private;

-- probe: ticket_time_statistic rows (presence and which counters are non-zero)
SELECT ticket_id,
       CASE WHEN open_time > 0 THEN 1 ELSE 0 END AS has_open_time,
       CASE WHEN waiting_time > 0 THEN 1 ELSE 0 END AS has_waiting_time,
       CASE WHEN deferred_time > 0 THEN 1 ELSE 0 END AS has_deferred_time,
       CASE WHEN resolved_time > 0 THEN 1 ELSE 0 END AS has_resolved_time
FROM tt.ticket_time_statistic WHERE ticket_id BETWEEN 952310 AND 952316 ORDER BY ticket_id;

-- probe: ticket_flow rows (open queue entries and closed ones per ticket)
SELECT ticket_id, CASE WHEN flow_out_date IS NULL THEN 0 ELSE 1 END AS flow_closed, COUNT(*) AS n_rows
FROM tt.ticket_flow WHERE ticket_id BETWEEN 952310 AND 952316
GROUP BY ticket_id, CASE WHEN flow_out_date IS NULL THEN 0 ELSE 1 END
ORDER BY ticket_id, 2;
