-- probe: steps (ok in s; error code only if something propagated -- these routines swallow)
SELECT step, code, msg, n, s FROM diff_probe ORDER BY step;

-- probe: related ticket rows touching the fixture tickets
SELECT ticket_id, related_ticket_id
FROM tt.ticket2related_ticket
WHERE ticket_id IN (954010, 954011, 954012) OR related_ticket_id IN (954010, 954011, 954012)
ORDER BY ticket_id, related_ticket_id;

-- probe: related file rows of the fixture tickets
SELECT ticket_id, mc_file_id
FROM tt.ticket2mc_file
WHERE ticket_id IN (954010, 954011, 954012)
ORDER BY ticket_id, mc_file_id;

-- probe: relation history events written by the routines
SELECT type_id, ticket_id, public_event, company_id, host_id, contact_id, details_public, details_private
FROM tt.event
WHERE ticket_id IN (954010, 954011, 954012) AND type_id IN (100016, 100017, 100018, 100019)
ORDER BY ticket_id, type_id, details_private;

-- probe: ticket rows after the private history events (addevent_new side effects)
SELECT id, status_id, fast_resolvable, recoverable_status_id, summary_relevant_events_count, todo_relevant_events_count,
       CASE WHEN last_public_event_id IS NOT NULL THEN 1 ELSE 0 END AS has_last_public_event
FROM tt.ticket WHERE id IN (954010, 954011, 954012) ORDER BY id;
