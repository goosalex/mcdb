-- tt__ticket_interface__change_owner_company / setup.sql -- dialect-neutral fixtures (952100-952199).
-- Master data reused from both sides: tt.status 2, tt.ticket_type 1/2, mss.operating_system 2,
-- mss.service_type 6 ('Security Gateway'), mss.service_level 1, mss.service_component 1/2/5
-- (sdp / wan / firewall), tt.event_notification_type 2 (email).
-- TIMESTAMP '...' literals are valid in both dialects (Oracle converts them to the session
-- time zone, +00:00 in the container) and make the UX-timeout results deterministic.
INSERT INTO stop.company (id, name, short) VALUES (952101, 'Diff Owner Co A', 'dfowna');
INSERT INTO stop.company (id, name, short) VALUES (952102, 'Diff Owner Co B', 'dfownb');
INSERT INTO stop.contact (id, lastname, firstname, short, company_id) VALUES (952103, 'Actor', 'Diff', 'dfowac1', 952101);
INSERT INTO stop.contact (id, lastname, firstname, short, company_id) VALUES (952104, 'NewOwner', 'Diff', 'dfowno1', 952102);
-- the OSAG engineer's contact belongs to company 6: Oracle's trigger AUTH.T_LOGIN_SET_COMPANY
-- overwrites auth.login.company_id with the contact's company on INSERT, so the login's
-- company must come from the contact (first live run: the OSAG login became company A and
-- its notification was deleted instead of reassigned)
INSERT INTO stop.contact (id, lastname, firstname, short, company_id) VALUES (952105, 'Osag', 'Engineer', 'dfowos1', 6);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author) VALUES (952106, 'diff-owner-host-a', 2, 952101, 'diff');
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author) VALUES (952107, 'diff-owner-host-b', 2, 952101, 'diff');
INSERT INTO mss.service (id, service_type_id, company_id, service_level_id, name) VALUES (952108, 6, 952101, 1, 'diff-owner-svc-a');
INSERT INTO mss.service (id, service_type_id, company_id, service_level_id, name) VALUES (952109, 6, 952101, 1, 'diff-owner-svc-b');
INSERT INTO mss.host2service (host_id, service_id) VALUES (952106, 952108);
INSERT INTO mss.host2service (host_id, service_id) VALUES (952107, 952109);
-- ticket "full": host, service and service component set
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, mss_service_id, service_component_id, subject,
                       last_status_change_date, ux_timeout_start)
    VALUES (952110, 1, 2, 952101, 952103, 952106, 952108, 1, 'owner ticket full',
            CURRENT_TIMESTAMP - INTERVAL '1' HOUR, TIMESTAMP '2026-01-10 10:00:00');
-- ticket "bare": no host, no service, no service component
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, subject, last_status_change_date, ux_timeout_start)
    VALUES (952111, 1, 2, 952101, 952103, 'owner ticket bare',
            CURRENT_TIMESTAMP - INTERVAL '1' HOUR, TIMESTAMP '2026-01-10 10:00:00');
-- ticket for change_company, with event notifications of a customer login and an OSAG login
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, mss_service_id, subject, last_status_change_date, ux_timeout_start)
    VALUES (952112, 1, 2, 952101, 952103, 952106, 952108, 'owner ticket company',
            CURRENT_TIMESTAMP - INTERVAL '1' HOUR, TIMESTAMP '2026-01-10 10:00:00');
-- logins: a customer login (company A) and an OSAG login (company 6 -- the routine's hard-coded OSAG id)
INSERT INTO auth.login (id, login, contact_id, company_id) VALUES (952120, 'dfown-cust', 952103, 952101);
INSERT INTO auth.login (id, login, contact_id, company_id) VALUES (952121, 'dfown-osag', 952105, 6);
-- notifications: two on the company-change ticket (one per login), one on another ticket (must survive)
INSERT INTO tt.event_notification (id, login_id, event_notification_type_id, ticket_id, company_id) VALUES (952130, 952120, 2, 952112, 952101);
INSERT INTO tt.event_notification (id, login_id, event_notification_type_id, ticket_id, company_id) VALUES (952131, 952121, 2, 952112, 952101);
INSERT INTO tt.event_notification (id, login_id, event_notification_type_id, ticket_id, company_id) VALUES (952132, 952120, 2, 952111, 952101);
