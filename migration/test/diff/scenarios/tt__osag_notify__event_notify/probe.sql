-- probe: steps (customer counter in n and osag counter in s after each notify step, suppressor flag in n, error code for failed steps)
SELECT step, code, msg, n, s FROM diff_probe ORDER BY step;

-- probe: ticket notify counters
SELECT id, event_notify_count, event_notify_count_osag FROM tt.ticket WHERE id BETWEEN 958120 AND 958125 ORDER BY id;

-- probe: events written by the routines (the fixture events 958130-958136 excluded)
SELECT type_id, ticket_id, public_event, contact_id, peer_contact_id, details_public, details_private
FROM tt.event WHERE ticket_id BETWEEN 958120 AND 958125 AND id NOT BETWEEN 958130 AND 958136
ORDER BY ticket_id, type_id, details_public;
