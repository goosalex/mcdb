-- probe: steps (ux day/hour after each successful call in s, error code for failed steps -- no quotes in labels)
SELECT step, code, msg, s FROM diff_probe ORDER BY step;

-- probe: ticket rows after all steps (status, emergency ratchet, deferral dates as day-of-month, final UX timeout)
SELECT id, status_id, emergency, was_emergency,
       EXTRACT(DAY FROM status_valid_until_date) AS valid_until_day,
       EXTRACT(DAY FROM last_deferral_date) AS last_deferral_day,
       EXTRACT(DAY FROM CAST(ux_timeout AS TIMESTAMP)) AS ux_day,
       EXTRACT(HOUR FROM CAST(ux_timeout AS TIMESTAMP)) AS ux_hour
FROM tt.ticket WHERE id BETWEEN 952210 AND 952221 ORDER BY id;

-- probe: events written (the deferral event carries the ticket host; emergency events via add_status_change_event)
SELECT ticket_id, type_id, public_event, contact_id, host_id, contact_zitadel_id, details_public, details_private
FROM tt.event WHERE ticket_id BETWEEN 952210 AND 952221
ORDER BY ticket_id, type_id, details_public, details_private;

-- probe: event company_id null or set (S-TICKET-059 correction of the add_status_change_event cust_id bug)
SELECT ticket_id, type_id, CASE WHEN company_id IS NULL THEN 'null' ELSE 'set' END AS event_company, COUNT(*) AS n_events
FROM tt.event WHERE ticket_id BETWEEN 952210 AND 952221
GROUP BY ticket_id, type_id, CASE WHEN company_id IS NULL THEN 'null' ELSE 'set' END
ORDER BY ticket_id, type_id, 3;
