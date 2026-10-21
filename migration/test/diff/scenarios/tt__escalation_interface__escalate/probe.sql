-- probe: steps (ok in s, error code for failed steps -- no quotes in labels, PROMPT strips them)
SELECT step, code, msg, s FROM diff_probe ORDER BY step;

-- probe: ticket rows after the calls (escalation status, date flags, addevent_new rollups)
SELECT id, subject, status_id, escalation_status_id,
       CASE WHEN last_escalation_date IS NULL THEN 'null'
            WHEN last_escalation_date = TIMESTAMP '2020-01-01 00:00:00' THEN 'fixture' ELSE 'set' END AS last_escalation_date_state,
       CASE WHEN last_public_event_id IS NOT NULL THEN 1 ELSE 0 END AS has_last_public_event,
       summary_relevant_events_count, todo_relevant_events_count, fast_resolvable
FROM tt.ticket WHERE id BETWEEN 956711 AND 956732 ORDER BY id;

-- probe: events written by the routines (fixture events 9568xx excluded)
SELECT ticket_id, type_id, host_id, company_id, public_event, contact_id, pinned, details_public, details_private
FROM tt.event WHERE ticket_id BETWEEN 956711 AND 956732 AND id NOT BETWEEN 956800 AND 956899
ORDER BY ticket_id, type_id;
