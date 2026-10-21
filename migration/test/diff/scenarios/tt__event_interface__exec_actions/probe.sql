-- probe: steps (ok in s, error code for failed steps -- no quotes in labels, PROMPT strips them)
SELECT step, code, msg, s FROM diff_probe ORDER BY step;

-- probe: fixture tickets after dispatch (escalation status, escalation date flag, status unchanged)
SELECT id, subject, status_id, escalation_status_id,
       CASE WHEN last_escalation_date IS NOT NULL THEN 1 ELSE 0 END AS has_last_escalation_date,
       CASE WHEN last_public_event_id IS NOT NULL THEN 1 ELSE 0 END AS has_last_public_event,
       summary_relevant_events_count, todo_relevant_events_count
FROM tt.ticket WHERE id BETWEEN 956101 AND 956110 ORDER BY id;

-- probe: events the dispatched routines wrote on the fixture tickets (fixture event types excluded)
SELECT ticket_id, type_id, host_id, company_id, public_event, contact_id, details_public, details_private
FROM tt.event WHERE ticket_id BETWEEN 956101 AND 956110 AND type_id NOT BETWEEN 956300 AND 956399
ORDER BY ticket_id, type_id, details_private;

-- probe: the hidden ISP outage escalation ticket opened by escalate_isp_outage_to_os (S-ESC-019)
SELECT subject, type_id, status_id, service_component_id, escalation_status_id,
       CASE WHEN host_id IS NULL THEN 1 ELSE 0 END AS host_is_null,
       CASE WHEN company_id IS NULL THEN 1 ELSE 0 END AS company_is_null,
       CASE WHEN contact_id IS NULL THEN 1 ELSE 0 END AS contact_is_null
FROM tt.ticket WHERE subject = 'Critical ISP Outage escalation' ORDER BY subject;

-- probe: events of the ISP outage escalation ticket (S-ESC-018 texts name the ORIGINAL ticket)
SELECT e.type_id, e.public_event, e.details_public, e.details_private,
       CASE WHEN e.host_id IS NULL THEN 1 ELSE 0 END AS host_is_null,
       CASE WHEN e.company_id IS NULL THEN 1 ELSE 0 END AS company_is_null
FROM tt.event e JOIN tt.ticket t ON t.id = e.ticket_id
WHERE t.subject = 'Critical ISP Outage escalation' ORDER BY e.type_id, e.details_public;
