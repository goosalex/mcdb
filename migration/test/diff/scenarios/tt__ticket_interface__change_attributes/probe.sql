-- probe: steps (ok in s, error code for failed steps -- no quotes in labels, PROMPT strips them)
SELECT step, code, msg, s FROM diff_probe ORDER BY step;

-- probe: ticket rows after all steps (references, label, visibility, summaries)
SELECT id, customer_reference, partner_reference, label_id, always_visible,
       summary_private, summary_public, summary_relevant_events_count,
       CASE WHEN last_summary_update IS NOT NULL THEN 1 ELSE 0 END AS has_last_summary_update
FROM tt.ticket WHERE id IN (952010, 952011) ORDER BY id;

-- probe: audit events written (type, visibility, actor, texts; company_id is probed separately)
SELECT ticket_id, type_id, public_event, contact_id, contact_zitadel_id, details_public, details_private
FROM tt.event WHERE ticket_id IN (952010, 952011)
ORDER BY ticket_id, type_id, details_public, details_private;

-- probe: event company_id null or set (S-TICKET-059 correction of the add_status_change_event cust_id bug)
SELECT ticket_id, type_id, CASE WHEN company_id IS NULL THEN 'null' ELSE 'set' END AS event_company, COUNT(*) AS n_events
FROM tt.event WHERE ticket_id IN (952010, 952011)
GROUP BY ticket_id, type_id, CASE WHEN company_id IS NULL THEN 'null' ELSE 'set' END
ORDER BY ticket_id, type_id, 3;
