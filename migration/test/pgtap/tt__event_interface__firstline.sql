-- migration/test/pgtap/tt__event_interface__firstline.sql
--
-- pgTAP verification of migration/spec/tt.event_interface.md S-EVENT-048: the four
-- "first line of the details" extractions (SUBSTR(x, 1, INSTR(x, CHR(10)) - 1)) must
-- behave like Oracle's SUBSTR when the details contain NO newline -- length -1 returns
-- NULL, the routine continues. Derived from the live differential run of 2026-10-21
-- (scenario tt__event_interface__newevent): Oracle opened a ticket with subject NULL for
-- newevent_new(30002, 'single line mail subject') and kept the event of
-- newevent_new(10004, 'single line hardware notification'); the pre-fix translation
-- raised 22011 for the first and SILENTLY LOST the second (22011 swallowed inside
-- addevent_new's outer handler after p_event_id was assigned).
--
-- This file is deliberately SEPARATE from tt__event_interface__spec.sql so the locked
-- suite is not edited. RED by construction against the pre-fix translation (tests 1, 2
-- and 5). Every assertion's description starts with the spec clause ID it verifies
-- (HARN-05, trace_lint.py). Fixture ids 9579xx (the differential harness's 956000-957999
-- range, disjoint from the 9006xx / 9106xx ranges of the other event_interface files).

BEGIN;
SET CONSTRAINTS ALL DEFERRED;
SELECT plan(6);

-------------------------------------------------------------------------------
-- Fixtures: a company, an active host with exactly one service (idx_h2s_host_un), and
-- an open incident ticket for the addevent_new case. Reference rows from master data:
-- tt.event_type 30002 (email from customer, source 3) and 10004 (hardware notification,
-- source 1, an alerting-log type), tt.status 2, tt.ticket_type 1, mss.operating_system 2,
-- mss.service_type 6, mss.service_level 1.
-------------------------------------------------------------------------------

INSERT INTO stop.company (id, name, short) VALUES (957901, 'Firstline Co', 'frstln1');
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author, active)
    VALUES (957905, 'firstline-host', 2, 957901, 'pilot', 1);
INSERT INTO mss.service (id, service_type_id, company_id, service_level_id, name)
    VALUES (957907, 6, 957901, 1, 'firstline-svc');
INSERT INTO mss.host2service (host_id, service_id) VALUES (957905, 957907);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, mss_service_id, subject, last_status_change_date)
    VALUES (957911, 1, 2, 957901, 957905, 957907, 'firstline add target', now() - interval '1 hour');

-------------------------------------------------------------------------------
-- newevent_new, subject branch (lines 352-353): no newline -> subject NULL, ticket opened.
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL tt.event_interface_newevent_new(NULL, 30002, 957905, 'single line mail subject')$$,
    'S-EVENT-048: newevent_new(30002) with single-line details does not raise (Oracle SUBSTR(x, 1, -1) is NULL, not an error)'
);

SELECT is(
    (SELECT count(*) FROM tt.ticket t
     WHERE t.host_id = 957905 AND t.type_id = 2 AND t.subject IS NULL
       AND EXISTS (SELECT 1 FROM tt.event e WHERE e.ticket_id = t.id AND e.type_id = 30002
                   AND e.details_public = 'single line mail subject')),
    1::bigint,
    'S-EVENT-048: the ticket opened for single-line 30002 details has subject NULL (Oracle SUBSTR with length -1) and carries the 30002 event'
);

-------------------------------------------------------------------------------
-- newevent_new, alerting-log branch (line 441) -- reached on the new-ticket path for a
-- 10004 on a host whose only open ticket is the type-2 ticket just created (its first
-- event is source 3, so the recent-ticket search does not append to it).
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL tt.event_interface_newevent_new(NULL, 10004, 957905, 'single line hardware notification')$$,
    'S-EVENT-048: newevent_new(10004) with single-line details does not raise (alerting-log v_msg_firstline is NULL, not an error)'
);

SELECT is(
    (SELECT count(*) FROM tt.event WHERE type_id = 10004 AND details_public = 'single line hardware notification'),
    1::bigint,
    'S-EVENT-048: the single-line 10004 event row exists after newevent_new (the event is not lost)'
);

-------------------------------------------------------------------------------
-- addevent_new, alerting-log branch (line 657): the swallowing outer handler must not be
-- what "handles" a 22011 -- the event row must exist.
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL tt.event_interface_addevent_new(NULL, 957911, 10004, 957905, 'single line via addevent')$$,
    'S-EVENT-048: addevent_new(10004) with single-line details does not raise'
);

SELECT is(
    (SELECT count(*) FROM tt.event WHERE ticket_id = 957911 AND type_id = 10004 AND details_public = 'single line via addevent'),
    1::bigint,
    'S-EVENT-048: addevent_new wrote the single-line 10004 event row (a 22011 swallowed by the outer handler would leave none)'
);

SELECT * FROM finish();
ROLLBACK;
