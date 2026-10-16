-- migration/test/pgtap/ticketevolution__calculator__spec.sql
--
-- pgTAP verification of migration/spec/ticketevolution.calculator.md (materialize_tickev
-- only -- materialize_incremental COMMITs and lives in
-- migration/test/regress/sql/ticketevolution__calculator__txn.sql, exercised via a
-- top-level CALL). RED by construction: ticketevolution.calculator_* does not exist yet.
-- Every assertion's description begins with the spec clause ID it verifies (HARN-05,
-- trace_lint.py). Expected values come from the SPEC ONLY -- never from
-- pg_migration/output/ and never from a PL/pgSQL translation.
--
-- Two clauses assert CORRECTED behaviour (S-TICKEV-009, S-TICKEV-011); the assertions
-- below would FAIL against a literal port of the Oracle body, by design.
--
-- Fixture ids live in the 909xxx range (disjoint from every pilot package's 900xxx-905xxx
-- ranges). Reference rows reused from the template's masterdata: tt.ticket_type 1
-- (incident) / 11 (problem); tt.status 1 new / 2 open / 3 hot / 110 merged;
-- tt.event_type 100003 / 100004 / 100005 / 101002 / 101003 / 101110. No company, host or
-- contact is needed -- tt.ticket's FKs to those are all nullable.

BEGIN;
SET CONSTRAINTS ALL DEFERRED;
SELECT plan(62);

-------------------------------------------------------------------------------
-- Existence / kind (name-map.csv: both pg_kind=procedure)
-------------------------------------------------------------------------------

SELECT ok(
    EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'ticketevolution' AND p.proname = 'calculator_materialize_tickev' AND p.prokind = 'p'),
    'S-TICKEV-001: ticketevolution.calculator_materialize_tickev exists as a PostgreSQL PROCEDURE (prokind=p)'
);

SELECT ok(
    EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'ticketevolution' AND p.proname = 'calculator_materialize_incremental' AND p.prokind = 'p'),
    'S-TICKEV-018: ticketevolution.calculator_materialize_incremental exists as a PostgreSQL PROCEDURE (prokind=p) -- the COMMIT-bearing scheduled entry point'
);

-------------------------------------------------------------------------------
-- Fixtures
-------------------------------------------------------------------------------

-- Ticket A (909001): the full event history. CURRENT type is 'problem' (11) so that the
-- first type-change event's rewrite of earlier rows (S-TICKEV-015) is observable.
INSERT INTO tt.ticket (id, type_id, status_id) VALUES (909001, 11, 110);

INSERT INTO tt.event (id, type_id, ticket_id, eventdate, db_date, details_private, details_public, org_ticket_id) VALUES
 (909011, 101002, 909001, timestamp '2024-03-01 10:00:00', timestamp '2024-03-01 10:00:00', NULL, 'New status: open', NULL),
 (909012, 100003, 909001, timestamp '2024-03-01 10:01:00', timestamp '2024-03-01 10:01:00', 'Engineer changed to: jho (non-MCC). Was: jho (MCC).', NULL, NULL),
 (909013, 101003, 909001, timestamp '2024-03-01 10:02:00', timestamp '2024-03-01 10:02:00', NULL, 'New status: hot', NULL),
 (909014, 101003, 909001, timestamp '2024-03-01 10:03:00', timestamp '2024-03-01 10:03:00', NULL, 'New status: hot', NULL),
 (909015, 100003, 909001, timestamp '2024-03-01 10:04:00', timestamp '2024-03-01 10:04:00', NULL, 'ticket changed to emergency', NULL),
 (909016, 100003, 909001, timestamp '2024-03-01 10:05:00', timestamp '2024-03-01 10:05:00', 'Ticket label Dispatch added', NULL, NULL),
 (909017, 100005, 909001, timestamp '2024-03-01 10:06:00', timestamp '2024-03-01 10:06:00', NULL, 'type changed from incident to change', NULL),
 (909018, 100005, 909001, timestamp '2024-03-01 10:07:00', timestamp '2024-03-01 10:07:00', NULL, 'type changed from change to problem', NULL),
 (909019, 100003, 909001, timestamp '2024-03-01 10:08:00', timestamp '2024-03-01 10:08:00', NULL, 'ticket changed to non-emergency', NULL),
 (909020, 100003, 909001, timestamp '2024-03-01 10:09:00', timestamp '2024-03-01 10:09:00', NULL, 'emergency flag reviewed', NULL),
 (909021, 100003, 909001, timestamp '2024-03-01 10:10:00', timestamp '2024-03-01 10:10:00', 'Ticket label changed to SOC', NULL, NULL),
 (909022, 100003, 909001, timestamp '2024-03-01 10:11:00', timestamp '2024-03-01 10:11:00', 'Ticket label removed SOC', NULL, NULL),
 (909023, 100003, 909001, timestamp '2024-03-01 10:12:00', timestamp '2024-03-01 10:12:00', 'Engineer changed to: MCC (MCC). Was: jho (non-MCC).', NULL, NULL),
 (909024, 101110, 909001, timestamp '2024-03-01 10:13:00', timestamp '2024-03-01 10:13:00', NULL, 'New status: merged', NULL),
 (909025, 100004, 909001, timestamp '2024-03-01 10:14:00', timestamp '2024-03-01 10:14:00', NULL, NULL, NULL),
 (909026, 101002, 909001, timestamp '2024-03-01 10:15:00', timestamp '2024-03-01 10:15:00', NULL, 'New status: open', 909001);

-- Ticket B (909002): first event is an engineer change (first row is 'new', no pseudo-row);
-- an emergency flag 30 s after the first row (folded in place, S-TICKEV-011); then a
-- status change; then two events that fall through every branch (S-TICKEV-017).
INSERT INTO tt.ticket (id, type_id, status_id) VALUES (909002, 1, 2);
INSERT INTO tt.event (id, type_id, ticket_id, eventdate, db_date, details_private, details_public) VALUES
 (909031, 100003, 909002, timestamp '2024-03-01 10:00:00', timestamp '2024-03-01 10:00:00', 'Engineer changed to: abc (MCC). Was: MCC (MCC).', NULL),
 (909032, 100003, 909002, timestamp '2024-03-01 10:00:30', timestamp '2024-03-01 10:00:30', NULL, 'ticket changed to emergency'),
 (909033, 101002, 909002, timestamp '2024-03-01 10:10:00', timestamp '2024-03-01 10:10:00', NULL, 'New status: open'),
 (909034, 101003, 909002, timestamp '2024-03-01 10:11:00', timestamp '2024-03-01 10:11:00', NULL, 'Status set to hot'),
 (909035, 100003, 909002, timestamp '2024-03-01 10:12:00', timestamp '2024-03-01 10:12:00', NULL, 'Priority changed');

-- Ticket C (909003): emergency flag 5 MINUTES after the first row -- outside the
-- corrected 60-second margin (inside Oracle's literal 60-DAY one).
INSERT INTO tt.ticket (id, type_id, status_id) VALUES (909003, 1, 2);
INSERT INTO tt.event (id, type_id, ticket_id, eventdate, db_date, details_private, details_public) VALUES
 (909041, 100003, 909003, timestamp '2024-03-01 10:00:00', timestamp '2024-03-01 10:00:00', 'Engineer changed to: abc (MCC). Was: MCC (MCC).', NULL),
 (909042, 100003, 909003, timestamp '2024-03-01 10:05:00', timestamp '2024-03-01 10:05:00', NULL, 'ticket changed to emergency');

-- Ticket D (909004): no qualifying events, but a stale live tickev row from an earlier
-- generation (so "zero live rows afterwards" is not a tautology).
INSERT INTO tt.ticket (id, type_id, status_id) VALUES (909004, 1, 2);
INSERT INTO ticketevolution.tickev (event_id, ticket_id, ticket_status, emergency_state, mcc_state, ticket_type, date_from, date_to, deleted, ticket_status_id)
    VALUES (909049, 909004, 'open', 'non-emergency', 'MCC', 'incident', timestamp '2024-01-01 00:00:00', timestamp '2024-01-01 00:00:00', 0, 2);

-- Ticket E (909005): lone 'ticket merged' (100004) event, merge workflow 2.
INSERT INTO tt.ticket (id, type_id, status_id) VALUES (909005, 1, 110);
INSERT INTO tt.event (id, type_id, ticket_id, eventdate, db_date, details_private, details_public) VALUES
 (909051, 100004, 909005, timestamp '2024-03-01 10:00:00', timestamp '2024-03-01 10:00:00', NULL, NULL);

-- Ticket F (909006): NULL type_id -> the S-TICKEV-001 lookup finds no row.
INSERT INTO tt.ticket (id, type_id, status_id) VALUES (909006, NULL, 2);

-------------------------------------------------------------------------------
-- S-TICKEV-001: unhandled NO_DATA_FOUND
-------------------------------------------------------------------------------

SELECT throws_ok(
    $$CALL ticketevolution.calculator_materialize_tickev(909099999)$$,
    'P0002',
    NULL,
    'S-TICKEV-001: materialize_tickev propagates NO_DATA_FOUND unhandled for a nonexistent ticket id (type lookup, no EXCEPTION section anywhere in the routine)'
);

SELECT throws_ok(
    $$CALL ticketevolution.calculator_materialize_tickev(909006)$$,
    'P0002',
    NULL,
    'S-TICKEV-001: materialize_tickev propagates NO_DATA_FOUND unhandled for a ticket whose type_id is NULL (inner join to tt.ticket_type finds no row)'
);

-------------------------------------------------------------------------------
-- Ticket A: the full replay
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL ticketevolution.calculator_materialize_tickev(909001)$$,
    'S-TICKEV-004: materialize_tickev replays a 16-event history without error'
);

-- S-TICKEV-005: every emitted row, in chain order. Projected to text so the VALUES side
-- needs no per-column type juggling (varchar vs text would otherwise abort results_eq).
SELECT results_eq(
    $$SELECT event_id::text, ticket_status::text, emergency_state::text, assigned_engineer::text,
             mcc_state::text, ticket_type::text, ticket_label::text, date_from::text, date_to::text,
             ticket_status_id::text
      FROM ticketevolution.tickev
      WHERE ticket_id = 909001 AND deleted = 0
      ORDER BY date_from, date_to, event_id, ticket_status$$,
    $$VALUES
      ('909011'::text, 'new'::text,    'non-emergency'::text, NULL::text, 'MCC'::text,     'incident'::text, NULL::text,       '2024-03-01 10:00:00'::text, '2024-03-01 10:00:00'::text, '1'::text),
      ('909011', 'open',   'non-emergency', NULL,  'MCC',     'incident', NULL,       '2024-03-01 10:00:00', '2024-03-01 10:01:00', '2'),
      ('909012', 'open',   'non-emergency', 'jho', 'non-MCC', 'incident', NULL,       '2024-03-01 10:01:00', '2024-03-01 10:02:00', '2'),
      ('909013', 'hot',    'non-emergency', 'jho', 'non-MCC', 'incident', NULL,       '2024-03-01 10:02:00', '2024-03-01 10:04:00', '3'),
      ('909015', 'hot',    'emergency',     'jho', 'non-MCC', 'incident', NULL,       '2024-03-01 10:04:00', '2024-03-01 10:05:00', '3'),
      ('909016', 'hot',    'emergency',     'jho', 'non-MCC', 'incident', 'Dispatch', '2024-03-01 10:05:00', '2024-03-01 10:06:00', '3'),
      ('909017', 'hot',    'emergency',     'jho', 'non-MCC', 'change',   'Dispatch', '2024-03-01 10:06:00', '2024-03-01 10:07:00', '3'),
      ('909018', 'hot',    'emergency',     'jho', 'non-MCC', 'problem',  'Dispatch', '2024-03-01 10:07:00', '2024-03-01 10:08:00', '3'),
      ('909019', 'hot',    'non-emergency', 'jho', 'non-MCC', 'problem',  'Dispatch', '2024-03-01 10:08:00', '2024-03-01 10:10:00', '3'),
      ('909021', 'hot',    'non-emergency', 'jho', 'non-MCC', 'problem',  'SOC',      '2024-03-01 10:10:00', '2024-03-01 10:11:00', '3'),
      ('909022', 'hot',    'non-emergency', 'jho', 'non-MCC', 'problem',  NULL,       '2024-03-01 10:11:00', '2024-03-01 10:12:00', '3'),
      ('909023', 'hot',    'non-emergency', NULL,  'MCC',     'problem',  NULL,       '2024-03-01 10:12:00', '2024-03-01 10:13:00', '3'),
      ('909024', 'merged', 'non-emergency', NULL,  'MCC',     'problem',  NULL,       '2024-03-01 10:13:00', '2024-03-01 10:13:00', '110')$$,
    'S-TICKEV-005: the live generation for ticket A is exactly the 13 spec-derived rows (date_from = date_to for the last row, ticket_status_id resolved by status name)'
);

-- S-TICKEV-003: the org_ticket_id event is invisible to the replay.
SELECT ok(
    NOT EXISTS(SELECT 1 FROM ticketevolution.tickev WHERE ticket_id = 909001 AND event_id = 909026),
    'S-TICKEV-003: an event with a non-NULL org_ticket_id emits no tickev row'
);

SELECT is(
    (SELECT count(*) FROM ticketevolution.tickev WHERE ticket_id = 909001 AND deleted = 0),
    13::bigint,
    'S-TICKEV-003: 16 events, 13 live rows -- the duplicate status, the lone merge, the unrecognised emergency text and the org_ticket_id event emit nothing'
);

-- S-TICKEV-009: the pseudo 'new' row (first qualifying event is a status change).
SELECT is(
    (SELECT count(*) FROM ticketevolution.tickev WHERE ticket_id = 909001 AND deleted = 0 AND event_id = 909011),
    2::bigint,
    'S-TICKEV-009: the first event (a status change) emits two live rows sharing its event_id -- the pseudo ''new'' row and the real ''open'' row'
);

SELECT is(
    (SELECT date_to FROM ticketevolution.tickev WHERE ticket_id = 909001 AND deleted = 0 AND event_id = 909011 AND ticket_status = 'new'),
    timestamp '2024-03-01 10:00:00',
    'S-TICKEV-009: the pseudo ''new'' row keeps date_to = the first event''s db_date -- it is NOT stretched by the next event''s chaining update (corrected: Oracle would give 10:01:00)'
);

SELECT is(
    (SELECT date_from FROM ticketevolution.tickev WHERE ticket_id = 909001 AND deleted = 0 AND event_id = 909011 AND ticket_status = 'new'),
    timestamp '2024-03-01 10:00:00',
    'S-TICKEV-009: the pseudo ''new'' row starts at v_first_event_date = the first event''s db_date'
);

SELECT is(
    (SELECT ticket_status_id FROM ticketevolution.tickev WHERE ticket_id = 909001 AND deleted = 0 AND event_id = 909011 AND ticket_status = 'new'),
    1::numeric,
    'S-TICKEV-009: the pseudo ''new'' row resolves ticket_status_id via MIN(id) of tt.status ''new'''
);

-- S-TICKEV-008: date chaining.
SELECT is(
    (SELECT date_to FROM ticketevolution.tickev WHERE ticket_id = 909001 AND deleted = 0 AND event_id = 909011 AND ticket_status = 'open'),
    timestamp '2024-03-01 10:01:00',
    'S-TICKEV-008: the real first row''s date_to is closed by the next emitted event''s db_date'
);

SELECT is(
    (SELECT date_to FROM ticketevolution.tickev WHERE ticket_id = 909001 AND deleted = 0 AND event_id = 909013),
    timestamp '2024-03-01 10:04:00',
    'S-TICKEV-008: a row followed by a non-emitting event (duplicate hot at 10:03) is closed only by the next EMITTING event (10:04)'
);

SELECT is(
    (SELECT count(*) FROM ticketevolution.tickev a
     WHERE a.ticket_id = 909001 AND a.deleted = 0 AND a.ticket_status <> 'new'
       AND a.date_to <> a.date_from
       AND NOT EXISTS (SELECT 1 FROM ticketevolution.tickev b
                       WHERE b.ticket_id = 909001 AND b.deleted = 0 AND b.date_from = a.date_to)),
    0::bigint,
    'S-TICKEV-008: every closed live row''s date_to is some other live row''s date_from (contiguous chain, no gaps)'
);

SELECT ok(
    (SELECT date_from = date_to FROM ticketevolution.tickev WHERE ticket_id = 909001 AND deleted = 0 AND event_id = 909024),
    'S-TICKEV-005: the most recently emitted row has date_from = date_to (nothing has closed it yet)'
);

-- S-TICKEV-006 / S-TICKEV-007: status gate.
SELECT ok(
    NOT EXISTS(SELECT 1 FROM ticketevolution.tickev WHERE ticket_id = 909001 AND event_id = 909014),
    'S-TICKEV-006: a repeated status-change event to the same status (hot after hot) emits no row'
);

SELECT is(
    (SELECT ticket_status FROM ticketevolution.tickev WHERE ticket_id = 909001 AND deleted = 0 AND event_id = 909013),
    'hot'::varchar,
    'S-TICKEV-006: the status is the remainder of the first line after ''New status: '''
);

SELECT is(
    (SELECT count(*) FROM ticketevolution.tickev WHERE ticket_id = 909001 AND deleted = 0 AND ticket_status = 'merged'),
    1::bigint,
    'S-TICKEV-007: merge workflow 1 (101110 ''New status: merged'' + 100004) yields exactly one merged row'
);

SELECT ok(
    NOT EXISTS(SELECT 1 FROM ticketevolution.tickev WHERE ticket_id = 909001 AND event_id = 909025),
    'S-TICKEV-007: the 100004 event following a 101110 merged event emits nothing (status unchanged)'
);

SELECT is(
    (SELECT ticket_status_id FROM ticketevolution.tickev WHERE ticket_id = 909001 AND deleted = 0 AND event_id = 909024),
    110::numeric,
    'S-TICKEV-007: the merged row resolves ticket_status_id to tt.status ''merged'''
);

-- S-TICKEV-010: engineer change.
SELECT is(
    (SELECT assigned_engineer FROM ticketevolution.tickev WHERE ticket_id = 909001 AND deleted = 0 AND event_id = 909012),
    'jho'::varchar,
    'S-TICKEV-010: assigned_engineer is the first token after ''Engineer changed to: '''
);

SELECT is(
    (SELECT mcc_state FROM ticketevolution.tickev WHERE ticket_id = 909001 AND deleted = 0 AND event_id = 909012),
    'non-MCC'::varchar,
    'S-TICKEV-010: mcc_state is the parenthesised (non-)MCC marker of the new engineer'
);

SELECT is(
    (SELECT mcc_state FROM ticketevolution.tickev WHERE ticket_id = 909001 AND deleted = 0 AND event_id = 909023),
    'MCC'::varchar,
    'S-TICKEV-010: an engineer token of literally ''MCC'' sets mcc_state to ''MCC'''
);

SELECT ok(
    (SELECT assigned_engineer IS NULL FROM ticketevolution.tickev WHERE ticket_id = 909001 AND deleted = 0 AND event_id = 909023),
    'S-TICKEV-010: an engineer token of literally ''MCC'' clears assigned_engineer to NULL'
);

-- S-TICKEV-012 / S-TICKEV-013: emergency on a non-new ticket.
SELECT is(
    (SELECT emergency_state FROM ticketevolution.tickev WHERE ticket_id = 909001 AND deleted = 0 AND event_id = 909015),
    'emergency'::varchar,
    'S-TICKEV-012: ''ticket changed to emergency'' while the status is not ''new'' emits a row with emergency_state = emergency'
);

SELECT is(
    (SELECT emergency_state FROM ticketevolution.tickev WHERE ticket_id = 909001 AND deleted = 0 AND event_id = 909013),
    'non-emergency'::varchar,
    'S-TICKEV-012: the row preceding the emergency event is left non-emergency (no in-place update on a non-new ticket)'
);

SELECT is(
    (SELECT emergency_state FROM ticketevolution.tickev WHERE ticket_id = 909001 AND deleted = 0 AND event_id = 909019),
    'non-emergency'::varchar,
    'S-TICKEV-013: ''ticket changed to non-emergency'' emits a row with emergency_state = non-emergency'
);

SELECT ok(
    NOT EXISTS(SELECT 1 FROM ticketevolution.tickev WHERE ticket_id = 909001 AND event_id = 909020),
    'S-TICKEV-013: a 100003 event whose details_public merely contains ''emergency'' emits nothing'
);

-- S-TICKEV-014: label changes.
SELECT is(
    (SELECT ticket_label FROM ticketevolution.tickev WHERE ticket_id = 909001 AND deleted = 0 AND event_id = 909016),
    'Dispatch'::varchar,
    'S-TICKEV-014: ''Ticket label X added'' sets ticket_label = X'
);

SELECT is(
    (SELECT ticket_label FROM ticketevolution.tickev WHERE ticket_id = 909001 AND deleted = 0 AND event_id = 909021),
    'SOC'::varchar,
    'S-TICKEV-014: ''Ticket label changed to X'' sets ticket_label = X'
);

SELECT ok(
    (SELECT ticket_label IS NULL FROM ticketevolution.tickev WHERE ticket_id = 909001 AND deleted = 0 AND event_id = 909022),
    'S-TICKEV-014: ''Ticket label removed ...'' clears ticket_label to NULL (and still emits a row)'
);

-- S-TICKEV-015: type change.
SELECT is(
    (SELECT count(*) FROM ticketevolution.tickev WHERE ticket_id = 909001 AND deleted = 0 AND date_from < timestamp '2024-03-01 10:06:00' AND ticket_type = 'incident'),
    6::bigint,
    'S-TICKEV-015: the first type-change event rewrites ticket_type of ALL earlier live rows to the ''from'' type (incident), replacing the ticket''s current type (problem) they were seeded with'
);

SELECT is(
    (SELECT ticket_type FROM ticketevolution.tickev WHERE ticket_id = 909001 AND deleted = 0 AND event_id = 909017),
    'change'::varchar,
    'S-TICKEV-015: the type-change event''s own row carries the ''to'' type'
);

SELECT is(
    (SELECT count(*) FROM ticketevolution.tickev WHERE ticket_id = 909001 AND deleted = 0 AND ticket_type = 'change'),
    1::bigint,
    'S-TICKEV-015: the SECOND type-change event does not rewrite earlier rows (only one row ever carries ''change'')'
);

SELECT is(
    (SELECT ticket_type FROM ticketevolution.tickev WHERE ticket_id = 909001 AND deleted = 0 AND event_id = 909018),
    'problem'::varchar,
    'S-TICKEV-015: the second type-change event''s row carries its own ''to'' type'
);

-- S-TICKEV-016: Oracle '' is NULL.
SELECT ok(
    (SELECT assigned_engineer IS NULL FROM ticketevolution.tickev WHERE ticket_id = 909001 AND deleted = 0 AND event_id = 909011 AND ticket_status = 'new'),
    'S-TICKEV-016: the pseudo ''new'' row''s assigned_engineer (Oracle literal '''') is SQL NULL'
);

SELECT ok(
    (SELECT assigned_engineer IS NULL AND ticket_label IS NULL FROM ticketevolution.tickev WHERE ticket_id = 909001 AND deleted = 0 AND event_id = 909011 AND ticket_status = 'open'),
    'S-TICKEV-016: the initial engineer and label (Oracle v_eng := '''', v_label := '''') are SQL NULL, never the empty string'
);

SELECT is(
    (SELECT count(*) FROM ticketevolution.tickev WHERE ticket_id = 909001 AND (assigned_engineer = '' OR ticket_label = '')),
    0::bigint,
    'S-TICKEV-016: no tickev row of ticket A carries an empty-string engineer or label'
);

-- S-TICKEV-005: ticket_status_id resolution.
SELECT is(
    (SELECT ticket_status_id FROM ticketevolution.tickev WHERE ticket_id = 909001 AND deleted = 0 AND event_id = 909012),
    2::numeric,
    'S-TICKEV-005: ticket_status_id = MIN(id) of tt.status whose name equals the row''s ticket_status (open -> 2)'
);

-------------------------------------------------------------------------------
-- S-TICKEV-002: re-run soft-deletes the previous generation and rebuilds identically
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL ticketevolution.calculator_materialize_tickev(909001)$$,
    'S-TICKEV-002: materialize_tickev can be re-run on an unchanged ticket'
);

SELECT is(
    (SELECT count(*) FROM ticketevolution.tickev WHERE ticket_id = 909001 AND deleted = 1),
    13::bigint,
    'S-TICKEV-002: the previous generation is kept with deleted = 1 (13 rows), never physically removed'
);

SELECT is(
    (SELECT count(*) FROM ticketevolution.tickev WHERE ticket_id = 909001 AND deleted = 0),
    13::bigint,
    'S-TICKEV-002: the re-run produces a fresh live generation of 13 rows'
);

SELECT results_eq(
    $$SELECT event_id, ticket_status, emergency_state, assigned_engineer, mcc_state, ticket_type, ticket_label, date_from, date_to, ticket_status_id
      FROM ticketevolution.tickev WHERE ticket_id = 909001 AND deleted = 0
      ORDER BY date_from, date_to, event_id, ticket_status$$,
    $$SELECT event_id, ticket_status, emergency_state, assigned_engineer, mcc_state, ticket_type, ticket_label, date_from, date_to, ticket_status_id
      FROM ticketevolution.tickev WHERE ticket_id = 909001 AND deleted = 1
      ORDER BY date_from, date_to, event_id, ticket_status$$,
    'S-TICKEV-002: the re-run''s live generation is identical to the soft-deleted one (replay is deterministic)'
);

-------------------------------------------------------------------------------
-- Ticket B: no pseudo-row, emergency folded in place within 60 s, fall-through events
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL ticketevolution.calculator_materialize_tickev(909002)$$,
    'S-TICKEV-011: materialize_tickev replays an emergency flag raised 30 s after the first row'
);

SELECT is(
    (SELECT count(*) FROM ticketevolution.tickev WHERE ticket_id = 909002 AND deleted = 0),
    2::bigint,
    'S-TICKEV-011: five events, two live rows -- the in-margin emergency flag and the two fall-through events emit nothing'
);

SELECT is(
    (SELECT count(*) FROM ticketevolution.tickev WHERE ticket_id = 909002 AND deleted = 0 AND event_id = 909031),
    1::bigint,
    'S-TICKEV-004: when the first event is not a status change, exactly one row is emitted for it (status ''new'', no pseudo-row)'
);

SELECT is(
    (SELECT ticket_status || '/' || ticket_status_id::text FROM ticketevolution.tickev WHERE ticket_id = 909002 AND deleted = 0 AND event_id = 909031),
    'new/1'::text,
    'S-TICKEV-004: the first row carries status ''new'' and ticket_status_id = MIN(id) of tt.status ''new'''
);

SELECT is(
    (SELECT assigned_engineer || '/' || mcc_state FROM ticketevolution.tickev WHERE ticket_id = 909002 AND deleted = 0 AND event_id = 909031),
    'abc/MCC'::text,
    'S-TICKEV-010: engineer token ''abc'' with marker ''(MCC)'' yields abc / MCC'
);

SELECT is(
    (SELECT emergency_state FROM ticketevolution.tickev WHERE ticket_id = 909002 AND deleted = 0 AND event_id = 909031),
    'emergency'::varchar,
    'S-TICKEV-011: an emergency flag within 60 s of a still-new row is folded into that row in place (emergency_state updated, no new row)'
);

SELECT ok(
    NOT EXISTS(SELECT 1 FROM ticketevolution.tickev WHERE ticket_id = 909002 AND event_id = 909032),
    'S-TICKEV-011: the folded emergency event itself emits no row'
);

SELECT is(
    (SELECT date_to FROM ticketevolution.tickev WHERE ticket_id = 909002 AND deleted = 0 AND event_id = 909031),
    timestamp '2024-03-01 10:10:00',
    'S-TICKEV-008: the folded emergency event does not touch date_to -- the first row is closed by the later status change'
);

SELECT is(
    (SELECT ticket_status || '/' || emergency_state FROM ticketevolution.tickev WHERE ticket_id = 909002 AND deleted = 0 AND event_id = 909033),
    'open/emergency'::text,
    'S-TICKEV-011: the replay''s emergency state is ''emergency'' after a folded flag, so the next row inherits it'
);

SELECT ok(
    NOT EXISTS(SELECT 1 FROM ticketevolution.tickev WHERE ticket_id = 909002 AND event_id IN (909034, 909035)),
    'S-TICKEV-017: a status-type event without the ''New status: '' prefix and a 100003 event with unrecognised text fall through the whole chain and emit nothing'
);

-------------------------------------------------------------------------------
-- Ticket C: emergency flag outside the 60-second margin (corrected S-TICKEV-011)
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL ticketevolution.calculator_materialize_tickev(909003)$$,
    'S-TICKEV-011: materialize_tickev replays an emergency flag raised 5 min after the first row'
);

SELECT is(
    (SELECT count(*) FROM ticketevolution.tickev WHERE ticket_id = 909003 AND deleted = 0),
    2::bigint,
    'S-TICKEV-011: an emergency flag more than 60 s after the still-new first row updates nothing in place and emits its own row (corrected: Oracle''s +60 DAYS would have folded it)'
);

SELECT is(
    (SELECT emergency_state || '/' || date_to::text FROM ticketevolution.tickev WHERE ticket_id = 909003 AND deleted = 0 AND event_id = 909041),
    'non-emergency/2024-03-01 10:05:00'::text,
    'S-TICKEV-011: the first row stays non-emergency and is closed by the emergency event''s db_date'
);

SELECT is(
    (SELECT ticket_status || '/' || emergency_state FROM ticketevolution.tickev WHERE ticket_id = 909003 AND deleted = 0 AND event_id = 909042),
    'new/emergency'::text,
    'S-TICKEV-011: the out-of-margin emergency event''s row is status ''new'', emergency_state ''emergency'''
);

-------------------------------------------------------------------------------
-- Ticket D: no qualifying events
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL ticketevolution.calculator_materialize_tickev(909004)$$,
    'S-TICKEV-003: materialize_tickev runs without error on a ticket with no events'
);

SELECT is(
    (SELECT count(*) FILTER (WHERE deleted = 0) || '/' || count(*) FILTER (WHERE deleted = 1) FROM ticketevolution.tickev WHERE ticket_id = 909004),
    '0/1'::text,
    'S-TICKEV-003: a ticket with no qualifying events ends with zero live rows -- its stale live row was soft-deleted (S-TICKEV-002) and nothing was emitted'
);

-------------------------------------------------------------------------------
-- Ticket E: lone 'ticket merged' event (merge workflow 2)
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL ticketevolution.calculator_materialize_tickev(909005)$$,
    'S-TICKEV-007: materialize_tickev replays a lone 100004 event'
);

SELECT results_eq(
    $$SELECT ticket_status::text, ticket_status_id::text, date_from::text, date_to::text
      FROM ticketevolution.tickev WHERE ticket_id = 909005 AND deleted = 0
      ORDER BY date_to, ticket_status_id$$,
    $$VALUES ('new'::text, '1'::text, '2024-03-01 10:00:00'::text, '2024-03-01 10:00:00'::text),
             ('merged', '110', '2024-03-01 10:00:00', '2024-03-01 10:00:00')$$,
    'S-TICKEV-007: a lone 100004 event yields a pseudo ''new'' row and exactly one ''merged'' row (ticket_status_id 110), both at the event''s db_date'
);

SELECT * FROM finish();
ROLLBACK;
