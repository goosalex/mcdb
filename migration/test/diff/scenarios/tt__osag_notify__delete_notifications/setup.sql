-- tt__osag_notify__delete_notifications / setup.sql -- dialect-neutral fixtures (958xxx).
-- Reference rows reused from the master data present on both sides: tt.ticket_type 1,
-- tt.status 2, tt.event_type 101002/20001/20003, tt.event_notification_type 1 (SMS) / 2 (email).
-- stop.company 6 (OSAG) exists in neither container; it is created here so that the
-- OSAG-login branches of delete_ticket_notifications (login company 6) and event_notify's
-- default-company-unit lookup (S-NOTIFY-007 site #8) behave as in production.
-- CURRENT_TIMESTAMP - INTERVAL '1' HOUR is valid in both dialects (SYSDATE/now() are not).
INSERT INTO stop.company (id, name, short) VALUES (6, 'Diff OSAG placeholder', 'dfosag');
INSERT INTO stop.company (id, name, short) VALUES (958001, 'Diff Notify Co', 'dfntf1');
INSERT INTO stop.contact (id, lastname, firstname, short, company_id, mobile, email) VALUES (958002, 'Cust', 'Alpha', 'dfnal', 958001, '+41790000001', 'alpha@diff.invalid');
INSERT INTO stop.contact (id, lastname, firstname, short, company_id, mobile, email) VALUES (958003, 'Cust', 'Beta', 'dfnbe', 958001, NULL, 'beta@diff.invalid');
INSERT INTO stop.contact (id, lastname, firstname, short, company_id, mobile, email) VALUES (958004, 'Staff', 'Osag', 'dfnos', 6, '+41790000004', 'osag@diff.invalid');
INSERT INTO auth.login (id, login, contact_id, company_id) VALUES (958010, 'dfn-alpha', 958002, 958001);
INSERT INTO auth.login (id, login, contact_id, company_id) VALUES (958011, 'dfn-beta', 958003, 958001);
INSERT INTO auth.login (id, login, contact_id, company_id) VALUES (958012, 'dfn-osag', 958004, 6);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, subject, last_status_change_date)
    VALUES (958020, 1, 2, 958001, 958002, 'dfn ticket A', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, subject, last_status_change_date)
    VALUES (958021, 1, 2, 958001, 958002, 'dfn ticket B', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, subject, last_status_change_date)
    VALUES (958022, 1, 2, 6, 958004, 'dfn ticket C osag', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, subject, last_status_change_date)
    VALUES (958023, 1, 2, 958001, 958003, 'dfn ticket D bad type', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
-- notifications (Oracle check constraints C_EVENT_NOTIFICATION_1..6: exactly one of
-- event_type_id / event_type_group_id; a ticket-scoped row carries no service/unit/type ids)
INSERT INTO tt.event_notification (id, login_id, event_notification_type_id, event_type_id, company_id, ticket_id, only_if_worker) VALUES (958030, 958010, 2, 101002, 958001, 958020, 0);
INSERT INTO tt.event_notification (id, login_id, event_notification_type_id, event_type_id, company_id, ticket_id, only_if_worker) VALUES (958031, 958010, 1, 101002, 958001, 958021, 0);
INSERT INTO tt.event_notification (id, login_id, event_notification_type_id, event_type_id, company_id, ticket_id, only_if_worker) VALUES (958032, 958010, 2, 101002, 958001, NULL, 0);
INSERT INTO tt.event_notification (id, login_id, event_notification_type_id, event_type_id, company_id, ticket_id, only_if_worker) VALUES (958033, 958011, 2, 101002, 958001, 958020, 0);
INSERT INTO tt.event_notification (id, login_id, event_notification_type_id, event_type_id, company_id, ticket_id, only_if_worker) VALUES (958034, 958012, 1, 101002, 958001, 958020, 0);
INSERT INTO tt.event_notification (id, login_id, event_notification_type_id, event_type_id, company_id, ticket_id, only_if_worker) VALUES (958035, 958012, 2, 101002, 6, 958022, 0);
-- a notification type that does not exist: get_notification_type_name raises NO_DATA_FOUND
-- inside delete_ticket_notifications' loop (S-NOTIFY-036), swallowed by its handler
INSERT INTO tt.event_notification (id, login_id, event_notification_type_id, event_type_id, company_id, ticket_id, only_if_worker) VALUES (958036, 958011, 958999, 101002, 958001, 958023, 0);
