-- tt__util__check_jobs / setup.sql -- dialect-neutral fixtures (9583xx).
-- Reference rows reused from the master data present on both sides: tt.ticket_type 1 and 5,
-- tt.status 2/11/12/60/61/101/102, tt.event_type 10020 (customer id notification) and 101002,
-- tt.event_notification_type 2, mss.operating_system 2.
-- All dates are relative to CURRENT_TIMESTAMP inside the row's own INSERT (one statement clock).
INSERT INTO stop.company (id, name, short) VALUES (958301, 'Diff Util Co', 'dfutl1');
INSERT INTO stop.contact (id, lastname, firstname, short, company_id, email) VALUES (958302, 'Requester', 'Util', 'dfutrq', 958301, 'util@diff.invalid');
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author) VALUES (958303, 'diff-util-host', 2, 958301, 'diff');
INSERT INTO auth.login (id, login, contact_id, company_id) VALUES (958305, 'dfu-requester', 958302, 958301);

-- check_resolved_tickets: A eligible (resolved 15 days ago), B too recent, C never resolved
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, subject, last_status_change_date, last_resolved_date)
    VALUES (958310, 1, 101, 958301, 958302, 958303, 'dfu resolved 15d', CURRENT_TIMESTAMP - INTERVAL '15' DAY, CURRENT_TIMESTAMP - INTERVAL '15' DAY);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, subject, last_status_change_date, last_resolved_date)
    VALUES (958311, 1, 101, 958301, 958302, 958303, 'dfu resolved 5d', CURRENT_TIMESTAMP - INTERVAL '5' DAY, CURRENT_TIMESTAMP - INTERVAL '5' DAY);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, subject, last_status_change_date, last_resolved_date)
    VALUES (958312, 1, 101, 958301, 958302, 958303, 'dfu resolved null date', CURRENT_TIMESTAMP - INTERVAL '20' DAY, NULL);
-- a notification on ticket A: deleted when the job closes the ticket (100003 event)
INSERT INTO tt.event_notification (id, login_id, event_notification_type_id, event_type_id, company_id, ticket_id, only_if_worker)
    VALUES (958306, 958305, 2, 101002, 958301, 958310, 0);

-- check_ticket_status: D waiting expired (24h between last change and expiry), E deferred
-- expired, F waiting not yet expired, G waiting-for-signoff expired, H third party expired
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, subject, last_status_change_date, status_valid_until_date)
    VALUES (958313, 1, 11, 958301, 958302, 958303, 'dfu waiting expired', CURRENT_TIMESTAMP - INTERVAL '2' DAY, CURRENT_TIMESTAMP - INTERVAL '1' DAY);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, subject, last_status_change_date, status_valid_until_date)
    VALUES (958314, 1, 60, 958301, 958302, 958303, 'dfu deferred expired', CURRENT_TIMESTAMP - INTERVAL '3' DAY, CURRENT_TIMESTAMP - INTERVAL '1' DAY);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, subject, last_status_change_date, status_valid_until_date)
    VALUES (958315, 1, 11, 958301, 958302, 958303, 'dfu waiting future', CURRENT_TIMESTAMP - INTERVAL '1' DAY, CURRENT_TIMESTAMP + INTERVAL '1' DAY);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, subject, last_status_change_date, status_valid_until_date)
    VALUES (958316, 1, 61, 958301, 958302, 958303, 'dfu signoff expired', CURRENT_TIMESTAMP - INTERVAL '1' DAY - INTERVAL '12' HOUR, CURRENT_TIMESTAMP - INTERVAL '1' DAY);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, subject, last_status_change_date, status_valid_until_date)
    VALUES (958317, 1, 12, 958301, 958302, 958303, 'dfu third party expired', CURRENT_TIMESTAMP - INTERVAL '2' DAY, CURRENT_TIMESTAMP - INTERVAL '1' HOUR);

-- check_dnids_tickets_to_resolve: type 5 tickets whose last public event is a 10020 event
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, subject, last_status_change_date, last_public_event_id)
    VALUES (958320, 5, 2, 958301, 958302, 958303, 'dfu dnids allclean recent', CURRENT_TIMESTAMP - INTERVAL '1' DAY, 958330);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, subject, last_status_change_date, last_public_event_id)
    VALUES (958321, 5, 2, 958301, 958302, 958303, 'dfu dnids found old', CURRENT_TIMESTAMP - INTERVAL '10' DAY, 958331);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, subject, last_status_change_date, last_public_event_id)
    VALUES (958322, 5, 2, 958301, 958302, 958303, 'dfu dnids found recent', CURRENT_TIMESTAMP - INTERVAL '1' DAY, 958332);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, subject, last_status_change_date, last_public_event_id)
    VALUES (958323, 1, 2, 958301, 958302, 958303, 'dfu dnids allclean wrong type', CURRENT_TIMESTAMP - INTERVAL '1' DAY, 958333);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, subject, last_status_change_date, last_public_event_id, last_resolved_date)
    VALUES (958324, 5, 101, 958301, 958302, 958303, 'dfu dnids already resolved', CURRENT_TIMESTAMP - INTERVAL '1' DAY, 958334, CURRENT_TIMESTAMP - INTERVAL '1' DAY);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, subject, last_status_change_date, last_public_event_id)
    VALUES (958325, 5, 3, 958301, 958302, 958303, 'dfu dnips allclean second line', CURRENT_TIMESTAMP - INTERVAL '1' DAY, 958335);
INSERT INTO tt.event (id, type_id, ticket_id, eventdate, details_public) VALUES (958330, 10020, 958320, CURRENT_TIMESTAMP - INTERVAL '1' DAY, 'DNIDS:SCAN:INFO:ALLCLEAN nothing found');
INSERT INTO tt.event (id, type_id, ticket_id, eventdate, details_public) VALUES (958331, 10020, 958321, CURRENT_TIMESTAMP - INTERVAL '10' DAY, 'DNIDS:SCAN:INFO:FOUND something');
INSERT INTO tt.event (id, type_id, ticket_id, eventdate, details_public) VALUES (958332, 10020, 958322, CURRENT_TIMESTAMP - INTERVAL '1' DAY, 'DNIDS:SCAN:INFO:FOUND something');
INSERT INTO tt.event (id, type_id, ticket_id, eventdate, details_public) VALUES (958333, 10020, 958323, CURRENT_TIMESTAMP - INTERVAL '1' DAY, 'DNIDS:SCAN:INFO:ALLCLEAN nothing found');
INSERT INTO tt.event (id, type_id, ticket_id, eventdate, details_public) VALUES (958334, 10020, 958324, CURRENT_TIMESTAMP - INTERVAL '1' DAY, 'DNIDS:SCAN:INFO:ALLCLEAN nothing found');
INSERT INTO tt.event (id, type_id, ticket_id, eventdate, details_public) VALUES (958335, 10020, 958325, CURRENT_TIMESTAMP - INTERVAL '1' DAY, 'scan report' || CHR(10) || 'DNIPS:SLOWDOWN:ALLCLEAN done');

-- update_status_valid_until cases (all end with a future or NULL valid-until date so that
-- check_ticket_status, run afterwards, ignores them)
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, subject, last_status_change_date, emergency)
    VALUES (958340, 1, 11, 958301, 958302, 958303, 'dfu usvu waiting default', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, 0);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, subject, last_status_change_date, emergency)
    VALUES (958341, 1, 11, 958301, 958302, 958303, 'dfu usvu waiting emergency default', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, 1);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, subject, last_status_change_date, emergency)
    VALUES (958342, 1, 12, 958301, 958302, 958303, 'dfu usvu third party explicit 10d', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, 0);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, subject, last_status_change_date, emergency)
    VALUES (958343, 1, 11, 958301, 958302, 958303, 'dfu usvu waiting explicit 90d over cap', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, 0);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, subject, last_status_change_date, emergency)
    VALUES (958344, 1, 11, 958301, 958302, 958303, 'dfu usvu emergency explicit 2d over cap', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, 1);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, subject, last_status_change_date, emergency, status_valid_until_date)
    VALUES (958345, 1, 60, 958301, 958302, 958303, 'dfu usvu deferred untouched', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, 0, CURRENT_TIMESTAMP + INTERVAL '5' DAY);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, subject, last_status_change_date, emergency, status_valid_until_date, last_deferral_date)
    VALUES (958346, 1, 2, 958301, 958302, 958303, 'dfu usvu open reset', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, 0, CURRENT_TIMESTAMP + INTERVAL '5' DAY, CURRENT_TIMESTAMP - INTERVAL '1' DAY);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, subject, last_status_change_date, emergency)
    VALUES (958347, 1, 11, 958301, 958302, 958303, 'dfu usvu waiting explicit past', CURRENT_TIMESTAMP - INTERVAL '1' HOUR, 0);
