-- probe: steps (error code of failed steps, ids set for successful newticket_new -- no quotes in labels, PROMPT strips them)
SELECT step, code, msg, s FROM diff_probe ORDER BY step;

-- probe: ticket rows (ids are sequence-generated and differ per engine; never selected)
SELECT subject, type_id, contact_id, company_id, host_id, worker_id, worker_zitadel_id, contact_zitadel_id
FROM tt.ticket WHERE subject LIKE 'signoff %' ORDER BY subject;

-- probe: change requests created by the sign-off rule
SELECT t.subject, cr.change_request_state_id, cr.requester_id, cr.approver_id, cr.requester_zitadel_id, cr.approver_zitadel_id
FROM tt.change_request cr JOIN tt.ticket t ON t.id = cr.ticket_id
WHERE t.subject LIKE 'signoff %' ORDER BY t.subject;

-- probe: the first event of every ticket (its contact is the resolved sender or the worker)
SELECT t.subject, e.type_id, e.contact_id, e.contact_zitadel_id
FROM tt.event e JOIN tt.ticket t ON t.id = e.ticket_id
WHERE t.subject LIKE 'signoff %' AND e.type_id IN (30002, 101002) ORDER BY t.subject, e.type_id;
