-- probe: steps (ok for every call -- the routine swallows its own lookup failures, S-ESC-016)
SELECT step, code, msg, s FROM diff_probe ORDER BY step;

-- probe: the escalation tickets opened (one per successful lookup; told apart by their 30005 text)
SELECT t.type_id, t.status_id, t.service_component_id, t.escalation_status_id,
       CASE WHEN t.host_id IS NULL THEN 1 ELSE 0 END AS host_is_null,
       CASE WHEN t.company_id IS NULL THEN 1 ELSE 0 END AS company_is_null,
       CASE WHEN t.contact_id IS NULL THEN 1 ELSE 0 END AS contact_is_null,
       e.details_public AS incident_report
FROM tt.ticket t JOIN tt.event e ON e.ticket_id = t.id AND e.type_id = 30005
WHERE t.subject = 'Critical ISP Outage escalation' ORDER BY e.details_public;

-- probe: all events of the escalation tickets (S-ESC-018 public/private texts, 101001 history event)
SELECT e.type_id, e.public_event, e.details_public, e.details_private,
       CASE WHEN e.host_id IS NULL THEN 1 ELSE 0 END AS host_is_null,
       CASE WHEN e.company_id IS NULL THEN 1 ELSE 0 END AS company_is_null,
       CASE WHEN e.contact_id IS NULL THEN 1 ELSE 0 END AS contact_is_null
FROM tt.event e JOIN tt.ticket t ON t.id = e.ticket_id
WHERE t.subject = 'Critical ISP Outage escalation' ORDER BY e.type_id, e.details_public;

-- probe: the original tickets are untouched (S-ESC-019)
SELECT id, type_id, status_id, escalation_status_id,
       CASE WHEN last_escalation_date IS NULL THEN 1 ELSE 0 END AS escalation_date_is_null,
       (SELECT COUNT(*) FROM tt.event e WHERE e.ticket_id = t.id) AS n_events
FROM tt.ticket t WHERE id IN (957511, 957512, 957513) ORDER BY id;
