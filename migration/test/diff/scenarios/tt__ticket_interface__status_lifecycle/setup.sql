-- tt__ticket_interface__status_lifecycle / setup.sql -- dialect-neutral fixtures.
-- Minimal set that works on PostgreSQL (mirrors migration/test/pgtap/tt__ticket_interface__lifecycle.sql)
-- and satisfies Oracle's NOT NULL columns (ddl/generated/schema.oracle.sql: MSS.HOST needs
-- NAME, OPERATING_SYSTEM_ID, SERVICE_COMPANY_ID, AUTHOR). Reference rows reused from the
-- master data present on both sides: tt.status 2/3/11/102, tt.ticket_type 1,
-- tt.event_type 101002, mss.operating_system 2. Ids in the 950xxx range.
-- CURRENT_TIMESTAMP - INTERVAL '1' HOUR is valid in both dialects (SYSDATE/now() are not).
INSERT INTO stop.company (id, name, short) VALUES (950001, 'Diff Ticket Co', 'dfftick1');
INSERT INTO stop.contact (id, lastname, firstname, short, company_id) VALUES (950002, 'Requester', 'Diff', 'dffrq1', 950001);
INSERT INTO stop.contact (id, lastname, firstname, short, company_id) VALUES (950003, 'Worker', 'Diff', 'dffwk1', 950001);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author) VALUES (950005, 'diff-ti-host', 2, 950001, 'diff');
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, worker_id, host_id, subject, last_status_change_date)
    VALUES (950010, 1, 2, 950001, 950002, 950003, 950005, 'initial subject', CURRENT_TIMESTAMP - INTERVAL '1' HOUR);
INSERT INTO tt.event (id, type_id, ticket_id, details_public) VALUES (950011, 101002, 950010, 'fixture event');
