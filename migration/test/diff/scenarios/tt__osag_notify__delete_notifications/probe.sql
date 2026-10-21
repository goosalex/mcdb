-- probe: steps (surviving fixture notifications in n after each step, error code for failed steps)
SELECT step, code, msg, n, s FROM diff_probe ORDER BY step;

-- probe: surviving event_notification rows of the fixture logins
SELECT id, login_id, event_notification_type_id, ticket_id
FROM tt.event_notification WHERE login_id IN (958010, 958011, 958012) ORDER BY id;

-- probe: events written by the routines (100003 via change_notification, 20001/20003 via add_notification_event)
SELECT type_id, ticket_id, public_event, contact_id, peer_contact_id, company_id, details_public, details_private,
       CASE WHEN eventdate IS NOT NULL THEN 1 ELSE 0 END AS has_eventdate
FROM tt.event WHERE ticket_id IN (958020, 958021, 958022, 958023)
ORDER BY ticket_id, type_id, details_public, details_private;

-- probe: ticket notify counters untouched (no listener matched for the 100003 events)
SELECT id, event_notify_count, event_notify_count_osag FROM tt.ticket WHERE id IN (958020, 958021, 958022, 958023) ORDER BY id;
