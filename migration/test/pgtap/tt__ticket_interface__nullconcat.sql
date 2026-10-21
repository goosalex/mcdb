-- migration/test/pgtap/tt__ticket_interface__nullconcat.sql
--
-- pgTAP verification of migration/spec/tt.ticket_interface.md S-TICKET-064: the status-
-- change event texts built by change_status_event_id_out concatenate the caller's
-- p_details_public / p_details_private with Oracle semantics (NULL || 'x' = 'x').
-- Derived from the live differential run of 2026-10-21 (scenario
-- tt__event_interface__newevent): for TT.EVENT_INTERFACE's change_status(<ticket>, 3,
-- <contact>, NULL, 'new event added') Oracle wrote
--   details_public  = 'New status: hot' || CHR(10) || 'Previous status: open' || CHR(10)
-- while the translation wrote NULL (PostgreSQL || propagates NULL).
--
-- Deliberately SEPARATE from the locked tt__ticket_interface__*.sql files. RED by
-- construction against the pre-fix translation (tests 2 and 5). Every assertion's
-- description starts with the spec clause ID it verifies (HARN-05, trace_lint.py).
-- Fixture ids 9579xx (differential-harness range 956000-957999).

BEGIN;
SET CONSTRAINTS ALL DEFERRED;
SELECT plan(6);

INSERT INTO stop.company (id, name, short) VALUES (957951, 'Nullconcat Co', 'nullcc1');
INSERT INTO stop.contact (id, lastname, firstname, short, company_id) VALUES (957952, 'Caller', 'Null', 'nullcc', 957951);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, subject, last_status_change_date)
    VALUES (957961, 1, 2, 957951, 957952, 'nullconcat public NULL', now() - interval '1 hour');
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, subject, last_status_change_date)
    VALUES (957962, 1, 2, 957951, 957952, 'nullconcat hot reason', now() - interval '1 hour');

-------------------------------------------------------------------------------
-- p_details_public NULL (the TT.EVENT_INTERFACE call shape): the public text keeps the
-- two status lines and ends with the line break Oracle appends before the NULL.
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL tt.ticket_interface_change_status(957961, 3, 957952, NULL, 'new event added')$$,
    'S-TICKET-064: change_status with a NULL p_details_public succeeds'
);

SELECT is(
    (SELECT e.details_public FROM tt.event e WHERE e.ticket_id = 957961 AND e.type_id = 101003),
    'New status: hot' || chr(10) || 'Previous status: open' || chr(10),
    'S-TICKET-064: the 101003 event keeps "New status / Previous status" and the trailing CHR(10) when p_details_public is NULL (Oracle NULL-as-empty concatenation)'
);

SELECT is(
    (SELECT e.details_private FROM tt.event e WHERE e.ticket_id = 957961 AND e.type_id = 101003),
    'new event added',
    'S-TICKET-064: the private text is the caller''s p_details_private unchanged when no hot reason is given'
);

-------------------------------------------------------------------------------
-- p_hot_reason given, p_details_private NULL: the private text is "Hot because: ..." plus
-- the line break, never NULL; the public text carries the caller's text after the lines.
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL tt.ticket_interface_change_status(957962, 3, 957952, 'public text', NULL, p_hot_reason => 'customer called')$$,
    'S-TICKET-064: change_status with a hot reason and a NULL p_details_private succeeds'
);

SELECT is(
    (SELECT e.details_private FROM tt.event e WHERE e.ticket_id = 957962 AND e.type_id = 101003),
    'Hot because: customer called' || chr(10),
    'S-TICKET-064: the private text is "Hot because: <reason>" + CHR(10) when p_details_private is NULL (not NULL)'
);

SELECT is(
    (SELECT e.details_public FROM tt.event e WHERE e.ticket_id = 957962 AND e.type_id = 101003),
    'New status: hot' || chr(10) || 'Previous status: open' || chr(10) || 'public text',
    'S-TICKET-064: a non-NULL p_details_public follows the two status lines after a CHR(10)'
);

SELECT * FROM finish();
ROLLBACK;
