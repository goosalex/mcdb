-- probe: steps (id set for OUT ids, ok otherwise; error code for failed steps)
SELECT step, code, msg, n, s FROM diff_probe ORDER BY step;

-- probe: docs pages (ids are sequence-generated and never selected)
SELECT ticket_id, page_id, page_version, hot_issue
FROM tt.ticket_docs_page
WHERE ticket_id IN (954110, 954111, 954112, 954113, 954099999)
ORDER BY ticket_id, page_id;

-- probe: todo items (ids are sequence-generated and never selected)
SELECT ticket_id, seq_no, details, todo_item_status_id, is_public
FROM tt.todo_item
WHERE ticket_id IN (954110, 954111, 954112, 954113, 954099999, 954099998)
ORDER BY ticket_id, seq_no;

-- probe: step counters of the fixture tickets
SELECT id, steps_total, steps_completed, todo_relevant_events_count, summary_relevant_events_count,
       CASE WHEN last_public_event_id IS NOT NULL THEN 1 ELSE 0 END AS has_last_public_event
FROM tt.ticket WHERE id IN (954110, 954111, 954112, 954113) ORDER BY id;

-- probe: request classifications (one row per ticket; the nonexistent ticket row stays until commit)
SELECT ticket_id, classification
FROM tt.ticket_request_classification
WHERE ticket_id IN (954110, 954111, 954112, 954113, 954099997)
ORDER BY ticket_id;

-- probe: history events written by the routines
SELECT type_id, ticket_id, public_event, company_id, host_id, contact_id, details_public, details_private
FROM tt.event
WHERE ticket_id IN (954110, 954111, 954112, 954113, 954099999, 954099998, 954099997)
  AND type_id IN (100009, 100010, 100013, 100015, 100021)
ORDER BY ticket_id, type_id, details_public, details_private;
