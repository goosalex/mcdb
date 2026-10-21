-- probe: steps (ok / event id set for successful calls, error code for failed ones -- no quotes in labels)
SELECT step, code, msg, s FROM diff_probe ORDER BY step;

-- probe: history events written by add_history_event (ids are sequence-generated; selected by text)
SELECT ticket_id, type_id, public_event, contact_id, host_id, company_id, details_public, details_private, demoted
FROM tt.event WHERE details_public IN ('history text', 'private history', 'orphan history')
ORDER BY details_public;

-- probe: fixture events after demote / promote / moveevent (ticket_id is what moveevent changes)
SELECT id, ticket_id, type_id, demoted, details_public
FROM tt.event WHERE id BETWEEN 957321 AND 957324 ORDER BY id;

-- probe: event counts per fixture ticket after the moves
SELECT ticket_id, COUNT(*) AS n_events FROM tt.event WHERE ticket_id IN (957311, 957312, 957313) GROUP BY ticket_id ORDER BY ticket_id;
