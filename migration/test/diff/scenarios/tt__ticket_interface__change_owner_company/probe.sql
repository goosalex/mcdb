-- probe: steps (ok or event id set in s, error code for failed steps -- no quotes in labels, PROMPT strips them)
SELECT step, code, msg, s FROM diff_probe ORDER BY step;

-- probe: ticket rows after all steps (relations and the UX timeout computed from the fixed 10:00 start)
SELECT id, type_id, company_id, contact_id, contact_zitadel_id, host_id, mss_service_id, service_component_id,
       EXTRACT(DAY FROM CAST(ux_timeout AS TIMESTAMP)) AS ux_day,
       EXTRACT(HOUR FROM CAST(ux_timeout AS TIMESTAMP)) AS ux_hour
FROM tt.ticket WHERE id IN (952110, 952111, 952112) ORDER BY id;

-- probe: audit events written (every routine here resolves the company itself; details compared verbatim)
SELECT ticket_id, type_id, public_event, company_id, contact_id, contact_zitadel_id, details_public, details_private
FROM tt.event WHERE ticket_id IN (952110, 952111, 952112)
ORDER BY ticket_id, type_id, details_public, details_private;

-- probe: event notifications after change_company (customer login row deleted, OSAG login row moved, other ticket untouched)
SELECT id, login_id, ticket_id, company_id FROM tt.event_notification WHERE id IN (952130, 952131, 952132) ORDER BY id;

-- probe: ticket_flow rows created by change_type (updateTicketFlow)
SELECT ticket_id, COUNT(*) AS n_rows FROM tt.ticket_flow WHERE ticket_id IN (952110, 952111, 952112) GROUP BY ticket_id ORDER BY ticket_id;
