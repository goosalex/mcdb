-- probe: steps (event id set for successful calls, error code for failed ones -- no quotes in labels)
SELECT step, code, msg, s FROM diff_probe ORDER BY step;

-- probe: tickets opened by newevent_new (ids are sequence-generated; selected by host/company, ordered by subject)
SELECT subject, type_id, status_id, contact_id, company_id, host_id, mss_service_id, contact_zitadel_id,
       service_confirmed, type_confirmed, fast_resolvable, recoverable_status_id, service_component_id,
       summary_relevant_events_count, todo_relevant_events_count,
       CASE WHEN last_public_event_id IS NOT NULL THEN 1 ELSE 0 END AS has_last_public_event,
       CASE WHEN ux_timeout_start IS NOT NULL THEN 1 ELSE 0 END AS has_ux_timeout_start
FROM tt.ticket
WHERE (host_id IN (957005, 957007, 957011) OR company_id = 957001) AND id NOT BETWEEN 957100 AND 957199
ORDER BY subject, type_id;

-- probe: tickets opened by newevent_new whose subject is NULL (S-EVENT-048: single-line details, Oracle SUBSTR length -1)
SELECT COUNT(*) AS n_null_subject_tickets, MIN(type_id) AS type_id
FROM tt.ticket
WHERE subject IS NULL AND host_id = 957005 AND id NOT BETWEEN 957100 AND 957199;

-- probe: events of the tickets opened by newevent_new
SELECT t.subject, e.type_id, e.public_event, e.contact_id, e.contact_zitadel_id, e.company_id, e.host_id, e.details_public, e.details_private
FROM tt.event e JOIN tt.ticket t ON t.id = e.ticket_id
WHERE (t.host_id IN (957005, 957007, 957011) OR t.company_id = 957001) AND t.id NOT BETWEEN 957100 AND 957199
ORDER BY t.subject, e.type_id, e.details_public;

-- probe: fixture tickets after addevent_new / the append path
SELECT id, subject, type_id, status_id, fast_resolvable, recoverable_status_id,
       summary_relevant_events_count, todo_relevant_events_count,
       CASE WHEN last_public_event_id IS NOT NULL THEN 1 ELSE 0 END AS has_last_public_event,
       CASE WHEN last_status_change_date > CURRENT_TIMESTAMP - INTERVAL '30' MINUTE THEN 1 ELSE 0 END AS status_changed_now
FROM tt.ticket WHERE id BETWEEN 957101 AND 957108 ORDER BY id;

-- probe: events written on the fixture tickets (fixture events 9572xx excluded)
SELECT ticket_id, type_id, public_event, contact_id, host_id, company_id, pinned, org_ticket_id, details_public, details_private
FROM tt.event WHERE ticket_id BETWEEN 957101 AND 957108 AND id NOT BETWEEN 957200 AND 957299
ORDER BY ticket_id, type_id, details_public;
