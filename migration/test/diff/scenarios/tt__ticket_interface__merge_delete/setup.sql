-- tt__ticket_interface__merge_delete / setup.sql -- dialect-neutral fixtures (954300-954399).
-- Every row satisfies the NOT NULL columns of BOTH engines (dba_tab_columns and
-- information_schema, 2026-10-21). Foreign keys to reference tables not present in the
-- PostgreSQL template (mc.mc_file_type, nids/fw rule tables, prx policy types, mcaudit
-- types, mss installation projects) are DEFERRABLE on both sides and never checked because
-- the scenario ends with ROLLBACK; fw.change's FKs are NOT deferrable on Oracle, so its
-- company and ticket rows exist before it is inserted. Reference rows reused from the
-- master data present on both sides: tt.status 2/101, tt.ticket_type 1, tt.event_type
-- 101002/30002, tt.event_notification_type 2, tt.change_request_state 3,
-- mss.operating_system 2, mss.service_type 6, mss.service_level 1.
INSERT INTO stop.company (id, name, short) VALUES (954301, 'Diff Merge Co', 'dfmerge');
INSERT INTO stop.contact (id, lastname, firstname, short, company_id) VALUES (954302, 'Requester', 'DiffMerge', 'dfmergerq', 954301);
INSERT INTO stop.contact (id, lastname, firstname, short, company_id) VALUES (954303, 'Worker', 'DiffMerge', 'dfmergewk', 954301);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author) VALUES (954305, 'diff-merge-host', 2, 954301, 'diff');
INSERT INTO mss.service (id, service_type_id, company_id, service_level_id, name) VALUES (954306, 6, 954301, 1, 'diff-merge-svc');
INSERT INTO mss.host2service (host_id, service_id) VALUES (954305, 954306);
INSERT INTO auth.login (id, login, contact_id, company_id) VALUES (954310, 'dmg-l1', 954302, 954301);
INSERT INTO auth.login (id, login, contact_id, company_id) VALUES (954311, 'dmg-l2', 954303, 954301);

-- SRC (954320): open, partner reference, not fast-resolvable, customer rating, newer last public event
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, worker_id, host_id, subject, last_status_change_date,
                       partner_reference, fast_resolvable, handled_by_mcc, ux_timeout_start)
    VALUES (954320, 1, 2, 954301, 954302, 954303, 954305, 'diff merge SRC', CURRENT_TIMESTAMP - INTERVAL '1' HOUR,
            'SRC-REF', 0, 1, CURRENT_TIMESTAMP - INTERVAL '5' MINUTE);
INSERT INTO tt.event (id, type_id, ticket_id, details_public, public_event, eventdate)
    VALUES (954340, 101002, 954320, 'SRC event old', 1, CURRENT_TIMESTAMP - INTERVAL '20' MINUTE);
INSERT INTO tt.event (id, type_id, ticket_id, details_public, public_event, eventdate)
    VALUES (954341, 101002, 954320, 'SRC event new', 1, CURRENT_TIMESTAMP - INTERVAL '10' MINUTE);
INSERT INTO tt.ticket_rating (id, rating, event_id) VALUES (954331, 4, 954340);
UPDATE tt.ticket SET customer_ticket_rating_id = 954331, last_public_event_id = 954341 WHERE id = 954320;
-- TGT (954321): resolved, no partner reference, fast-resolvable, engineer rating, older last public event
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, worker_id, host_id, subject, last_status_change_date,
                       fast_resolvable, handled_by_mcc, ux_timeout_start)
    VALUES (954321, 1, 101, 954301, 954302, 954303, 954305, 'diff merge TGT', CURRENT_TIMESTAMP - INTERVAL '1' HOUR,
            1, 1, CURRENT_TIMESTAMP - INTERVAL '60' MINUTE);
INSERT INTO tt.event (id, type_id, ticket_id, details_public, public_event, eventdate)
    VALUES (954342, 101002, 954321, 'TGT event', 1, CURRENT_TIMESTAMP - INTERVAL '30' MINUTE);
INSERT INTO tt.ticket_rating (id, rating, event_id) VALUES (954332, 3, 954342);
UPDATE tt.ticket SET engineer_ticket_rating_id = 954332, last_public_event_id = 954342 WHERE id = 954321;
-- notifications: A (SRC, login L1) duplicates B (TGT, login L1) -> deleted; D (SRC, login L2) -> moved
INSERT INTO tt.event_notification (id, login_id, event_notification_type_id, event_type_id, ticket_id) VALUES (954350, 954310, 2, 30002, 954320);
INSERT INTO tt.event_notification (id, login_id, event_notification_type_id, event_type_id, ticket_id) VALUES (954351, 954310, 2, 30002, 954321);
INSERT INTO tt.event_notification (id, login_id, event_notification_type_id, event_type_id, ticket_id) VALUES (954352, 954311, 2, 30002, 954320);
-- a change request and a suppressed signature on SRC -> moved to TGT
INSERT INTO tt.change_request (id, ticket_id, change_request_state_id, creation_date, description)
    VALUES (954360, 954320, 3, CURRENT_TIMESTAMP, 'diff merge change request');
INSERT INTO guma2.suppressed_signature (id, host_id, signature_id, date_start, date_end, ticket_id)
    VALUES (954370, 954305, 1, CURRENT_TIMESTAMP - INTERVAL '1' HOUR, CURRENT_TIMESTAMP + INTERVAL '1' HOUR, 954320);

-- TGT2 (954322) with customer rating 954333, SRC2 (954323) with the higher customer rating id 954334
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, subject, last_status_change_date, fast_resolvable, handled_by_mcc)
    VALUES (954322, 1, 2, 954301, 954302, 954305, 'diff merge TGT2', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, 0, 1);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, subject, last_status_change_date, fast_resolvable, handled_by_mcc)
    VALUES (954323, 1, 2, 954301, 954302, 954305, 'diff merge SRC2', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, 1, 1);
INSERT INTO tt.event (id, type_id, ticket_id, details_public, public_event) VALUES (954343, 101002, 954322, 'TGT2 event', 0);
INSERT INTO tt.event (id, type_id, ticket_id, details_public, public_event) VALUES (954344, 101002, 954323, 'SRC2 event', 0);
INSERT INTO tt.ticket_rating (id, rating, event_id) VALUES (954333, 2, 954343);
INSERT INTO tt.ticket_rating (id, rating, event_id) VALUES (954334, 5, 954344);
UPDATE tt.ticket SET customer_ticket_rating_id = 954333 WHERE id = 954322;
UPDATE tt.ticket SET customer_ticket_rating_id = 954334 WHERE id = 954323;

-- DEL (954325): one dependent row in every table deleteTicket touches; OTHER (954326) points at it
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, subject, last_status_change_date, handled_by_mcc)
    VALUES (954325, 1, 2, 954301, 954302, 954305, 'diff delete DEL', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, 1);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, subject, last_status_change_date, handled_by_mcc, merged_into_ticket_id)
    VALUES (954326, 1, 2, 954301, 954302, 954305, 'diff delete OTHER', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, 1, 954325);
INSERT INTO tt.event (id, type_id, ticket_id, details_public, public_event) VALUES (954345, 101002, 954325, 'DEL event 1', 1);
INSERT INTO tt.event (id, type_id, ticket_id, details_public, public_event) VALUES (954346, 101002, 954325, 'DEL event 2', 1);
INSERT INTO tt.event (id, type_id, ticket_id, details_public, public_event) VALUES (954347, 101002, 954325, 'DEL event 3', 1);
INSERT INTO tt.ticket_rating (id, rating, event_id) VALUES (954335, 1, 954345);
INSERT INTO tt.ticket_rating (id, rating, event_id) VALUES (954336, 5, 954346);
INSERT INTO tt.ticket_rating (id, rating, event_id) VALUES (954337, 3, 954347);
UPDATE tt.ticket SET customer_ticket_rating_id = 954335, engineer_ticket_rating_id = 954336, last_public_event_id = 954345 WHERE id = 954325;
UPDATE tt.ticket SET customer_ticket_rating_id = 954337 WHERE id = 954326;
INSERT INTO tt.ticket2related_ticket (ticket_id, related_ticket_id) VALUES (954325, 954326);
INSERT INTO tt.ticket2related_ticket (ticket_id, related_ticket_id) VALUES (954326, 954325);
INSERT INTO mc.mc_file (id, uploader_id, display_name, description, filename, mime_type, mc_file_type_id)
    VALUES (954380, 954302, 'diff-del.txt', 'diff delete file', 'diff-del.txt', 'text/plain', 954099);
INSERT INTO mc.mc_file_release (id, company_id, mc_file_id) VALUES (954379, 954301, 954380);
INSERT INTO tt.ticket2mc_file (ticket_id, mc_file_id) VALUES (954325, 954380);
INSERT INTO tt.ticket_docs_page (id, ticket_id, page_id, page_version, hot_issue) VALUES (954381, 954325, 700020, 1, 0);
INSERT INTO tt.ticket_flow (id, ticket_id, flow_in_date, open_time) VALUES (954382, 954325, CURRENT_TIMESTAMP - INTERVAL '1' HOUR, 0);
INSERT INTO tt.todo_item (id, ticket_id, seq_no, details, todo_item_status_id, is_public) VALUES (954383, 954325, 0, 'del step', 1, 1);
INSERT INTO tt.ticket_request_classification (id, ticket_id, classification) VALUES (954384, 954325, 2);
INSERT INTO tt.change_request (id, ticket_id, change_request_state_id, creation_date, description)
    VALUES (954385, 954325, 3, CURRENT_TIMESTAMP, 'diff delete change request');
INSERT INTO tt.event_notification (id, login_id, event_notification_type_id, event_type_id, ticket_id) VALUES (954386, 954310, 2, 30002, 954325);
INSERT INTO tt.ticket_time_statistic (id, ticket_id, open_time, waiting_time, third_party_time, deferred_time, resolved_time)
    VALUES (954387, 954325, 10, 0, 0, 0, 0);
INSERT INTO tt.attachment (id, uuid, ticket_id, event_id, name, file_size)
    VALUES (954388, 'diff-del-0000-0000-0000-000000954388', 954325, 954345, 'del-attachment.txt', 12);
INSERT INTO tt.service_window (id, ticket_id, start_date, end_date, company_id)
    VALUES (954389, 954325, CURRENT_TIMESTAMP - INTERVAL '1' HOUR, CURRENT_TIMESTAMP + INTERVAL '1' HOUR, 954301);
INSERT INTO tt.maintenance_window (id, service_window_id) VALUES (954390, 954389);
INSERT INTO tt.cust_maintenance_window (id, service_window_id) VALUES (954391, 954389);
INSERT INTO tt.host2service_window (host_id, service_window_id) VALUES (954305, 954389);
INSERT INTO mss.deleted_host2service_window (deleted_host_id, service_window_id) VALUES (954305, 954389);
INSERT INTO nids.ticket2rule (event_filter_rule_id, ticket_id) VALUES (954392, 954325);
INSERT INTO fw.rule2ticket (rule_id, ticket_id) VALUES (954393, 954325);
INSERT INTO fw.source_nat_rule2ticket (source_nat_rule_id, ticket_id) VALUES (954394, 954325);
INSERT INTO fw.destination_nat_rule2ticket (destination_nat_rule_id, ticket_id) VALUES (954395, 954325);
-- (host_id, signature_id) is unique on both sides (SUPPRESSED_SIGNATURE_UV1): signature 2 here
INSERT INTO guma2.suppressed_signature (id, host_id, signature_id, date_start, date_end, ticket_id)
    VALUES (954371, 954305, 2, CURRENT_TIMESTAMP - INTERVAL '1' HOUR, CURRENT_TIMESTAMP + INTERVAL '1' HOUR, 954325);
INSERT INTO fw.change (id, company_id, summary_blob_name, ticket_id) VALUES (954396, 954301, 'diff-del-summary', 954325);
INSERT INTO prx.prx_policy_item (id, item_value, prx_policy_item_type_id, prx_policy_type_id, ticket_id) VALUES (954397, 'diff-del', 1, 1, 954325);
INSERT INTO mcaudit.record (id, application_id, component_id, message, record_type_id, timestamp, transaction_id, ticket_id)
    VALUES (954398, 1, 1, 'diff delete audit record', 1, CURRENT_TIMESTAMP, 1, 954325);
INSERT INTO mc.isp_link_history (id, isp_link_id, old_isp_link_status_type_id, new_isp_link_status_type_id, change_date, event_id)
    VALUES (954399, 1, 1, 2, CURRENT_TIMESTAMP, 954345);
INSERT INTO mss.installation_project_item (id, installation_project_id, osag_contact_id, project_item_status_id, address_id,
                                           original_completion_date, estimated_completion_date, ticket_id)
    VALUES (954300, 1, 954302, 1, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 954325);
INSERT INTO mc.isp_link_maintenance_history (id, isp_link_id, change_date, new_maintenance_status_id, old_maintenance_status_id, ticket_id)
    VALUES (954312, 1, CURRENT_TIMESTAMP, 2, 1, 954325);
INSERT INTO mc.host_maintenance_history (id, host_id, change_date, new_maintenance_status_id, old_maintenance_status_id, ticket_id)
    VALUES (954313, 954305, CURRENT_TIMESTAMP, 2, 1, 954325);
