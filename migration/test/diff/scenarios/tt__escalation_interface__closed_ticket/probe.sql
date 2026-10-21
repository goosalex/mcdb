-- probe: steps (error code of the propagated ticket_closed error -- no quotes in labels)
SELECT step, code, msg, s FROM diff_probe ORDER BY step;

-- probe: the closed tickets after the calls (the pre-error UPDATE survives only on Oracle)
SELECT id, subject, status_id, escalation_status_id,
       CASE WHEN last_escalation_date IS NOT NULL THEN 1 ELSE 0 END AS has_last_escalation_date
FROM tt.ticket WHERE id IN (956911, 956912) ORDER BY id;

-- probe: no 60001 event is ever written for a closed ticket (addevent_new raised before its INSERT)
SELECT ticket_id, type_id, COUNT(*) AS n_events
FROM tt.event WHERE ticket_id IN (956911, 956912) GROUP BY ticket_id, type_id ORDER BY ticket_id, type_id;
