-- tt__ticket_interface__todo_docs / setup.sql -- dialect-neutral fixtures (954100-954199).
-- Reference rows reused from the master data present on both sides: tt.status 2,
-- tt.ticket_type 1, tt.todo_item_status 1 TODO / 2 DONE / 3 ACTIVE / 4 SKIPPED,
-- mss.operating_system 2, mss.service_type 6, mss.service_level 1. The counters the
-- routines increment are set explicitly (not left to column defaults).
INSERT INTO stop.company (id, name, short) VALUES (954101, 'Diff Todo Co', 'dftodo');
INSERT INTO stop.contact (id, lastname, firstname, short, company_id) VALUES (954102, 'Requester', 'DiffTodo', 'dftodorq', 954101);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author) VALUES (954105, 'diff-todo-host', 2, 954101, 'diff');
INSERT INTO mss.service (id, service_type_id, company_id, service_level_id, name) VALUES (954106, 6, 954101, 1, 'diff-todo-svc');
INSERT INTO mss.host2service (host_id, service_id) VALUES (954105, 954106);
-- TD: the docs-page / todo / classification ticket (with a host, so history events carry host_id)
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, subject, last_status_change_date,
                       steps_total, steps_completed, todo_relevant_events_count)
    VALUES (954110, 1, 2, 954101, 954102, 954105, 'diff todo TD', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, 0, 0, 5);
-- TD2: classification with NULL (insert path), no host
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, subject, last_status_change_date,
                       steps_total, steps_completed, todo_relevant_events_count)
    VALUES (954111, 1, 2, 954101, 954102, 'diff todo TD2', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, 0, 0, 0);
-- TD3: a public todo item whose status update fails on a bad new status id (site #72)
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, subject, last_status_change_date,
                       steps_total, steps_completed, todo_relevant_events_count)
    VALUES (954112, 1, 2, 954101, 954102, 'diff todo TD3', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, 1, 0, 3);
INSERT INTO tt.todo_item (id, ticket_id, seq_no, details, todo_item_status_id, is_public)
    VALUES (954120, 954112, 0, 'td3 public step', 1, 1);
-- TD4: clear_todo_list without history event on a ticket with two items
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, subject, last_status_change_date,
                       steps_total, steps_completed, todo_relevant_events_count)
    VALUES (954113, 1, 2, 954101, 954102, 'diff todo TD4', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, 2, 1, 4);
INSERT INTO tt.todo_item (id, ticket_id, seq_no, details, todo_item_status_id, is_public)
    VALUES (954121, 954113, 0, 'td4 step a', 2, 1);
INSERT INTO tt.todo_item (id, ticket_id, seq_no, details, todo_item_status_id, is_public)
    VALUES (954122, 954113, 1, 'td4 step b', 1, 1);
-- a pre-existing docs page on TD, removed by step 04
INSERT INTO tt.ticket_docs_page (id, ticket_id, page_id, page_version, hot_issue) VALUES (954130, 954110, 700001, 3, 0);
