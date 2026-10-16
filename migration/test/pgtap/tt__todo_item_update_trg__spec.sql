-- migration/test/pgtap/tt__todo_item_update_trg__spec.sql
--
-- pgTAP verification of migration/spec/tt.todo_item_update_trg.md. RED by construction:
-- neither trigger tt.todo_item_update_trg nor function tt.todo_item_update_trg_fn exists
-- yet. Every assertion's description begins with the spec clause ID it verifies (HARN-05,
-- trace_lint.py). Expected values come from the SPEC ONLY.
--
-- Fixture ids: tt.ticket 909300 (FK parent, type_id 1 from masterdata), tt.todo_item
-- 909301 (todo_item_status_id 1 'TODO' from masterdata). Because this trigger has NO
-- column list, update_timestamp can never be reset by hand (S-TITRG-003) -- the
-- behavioural assertions therefore compare successive stamps against each other and
-- against the transaction clock instead of against a sentinel value.

BEGIN;
SET CONSTRAINTS ALL DEFERRED;
SELECT plan(12);

-------------------------------------------------------------------------------
-- S-TITRG-001: shape
-------------------------------------------------------------------------------

SELECT ok(
    EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid = 'tt.todo_item'::regclass AND tgname = 'todo_item_update_trg' AND NOT tgisinternal),
    'S-TITRG-001: trigger tt.todo_item_update_trg exists on tt.todo_item'
);

-- tgtype bits: ROW=1, BEFORE=2, INSERT=4, UPDATE=16 -> 23 (no DELETE=8, no TRUNCATE=32)
SELECT is(
    (SELECT tgtype FROM pg_trigger WHERE tgrelid = 'tt.todo_item'::regclass AND tgname = 'todo_item_update_trg'),
    23::smallint,
    'S-TITRG-001: todo_item_update_trg is BEFORE INSERT OR UPDATE, FOR EACH ROW, and never fires on DELETE'
);

SELECT is(
    (SELECT tgattr::text FROM pg_trigger WHERE tgrelid = 'tt.todo_item'::regclass AND tgname = 'todo_item_update_trg'),
    ''::text,
    'S-TITRG-001: todo_item_update_trg has NO UPDATE OF column list (fires on every UPDATE)'
);

SELECT ok(
    EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'tt' AND p.proname = 'todo_item_update_trg_fn' AND p.prorettype = 'trigger'::regtype),
    'S-TITRG-001: tt.todo_item_update_trg_fn() exists and RETURNS trigger'
);

SELECT is(
    (SELECT p.proname::text FROM pg_trigger t JOIN pg_proc p ON p.oid = t.tgfoid
     WHERE t.tgrelid = 'tt.todo_item'::regclass AND t.tgname = 'todo_item_update_trg'),
    'todo_item_update_trg_fn'::text,
    'S-TITRG-001: the trigger executes tt.todo_item_update_trg_fn'
);

-------------------------------------------------------------------------------
-- Fixtures
-------------------------------------------------------------------------------

INSERT INTO tt.ticket (id, type_id, status_id) VALUES (909300, 1, 2);

CREATE TEMP TABLE titrg_probe (step int, ts timestamp);

-------------------------------------------------------------------------------
-- S-TITRG-002: INSERT stamps, overriding an explicit value
-------------------------------------------------------------------------------

INSERT INTO tt.todo_item (id, ticket_id, seq_no, details, todo_item_status_id, update_timestamp)
    VALUES (909301, 909300, 1, 'first step', 1, timestamp '2000-01-01 00:00:00');

SELECT isnt(
    (SELECT update_timestamp FROM tt.todo_item WHERE id = 909301),
    timestamp '2000-01-01 00:00:00',
    'S-TITRG-002: an explicit update_timestamp supplied by the INSERT is overwritten'
);

SELECT ok(
    (SELECT update_timestamp >= now()::timestamp AND update_timestamp <= clock_timestamp()::timestamp FROM tt.todo_item WHERE id = 909301),
    'S-TITRG-002: the INSERT-stamped update_timestamp is the current time (between transaction start and now)'
);

INSERT INTO titrg_probe SELECT 1, update_timestamp FROM tt.todo_item WHERE id = 909301;

-------------------------------------------------------------------------------
-- S-TITRG-003: EVERY UPDATE stamps -- including one that only sets update_timestamp
-------------------------------------------------------------------------------

DO $$ BEGIN PERFORM pg_sleep(0.02); END $$;
UPDATE tt.todo_item SET update_timestamp = timestamp '2000-01-01 00:00:00' WHERE id = 909301;

SELECT isnt(
    (SELECT update_timestamp FROM tt.todo_item WHERE id = 909301),
    timestamp '2000-01-01 00:00:00',
    'S-TITRG-003: an UPDATE naming only update_timestamp has its explicit value overwritten -- the column cannot be set by hand'
);

INSERT INTO titrg_probe SELECT 2, update_timestamp FROM tt.todo_item WHERE id = 909301;

SELECT ok(
    (SELECT (SELECT ts FROM titrg_probe WHERE step = 2) > (SELECT ts FROM titrg_probe WHERE step = 1)),
    'S-TITRG-003: ...and the stamp advanced past the INSERT''s stamp'
);

DO $$ BEGIN PERFORM pg_sleep(0.02); END $$;
UPDATE tt.todo_item SET details = 'first step, reworded' WHERE id = 909301;
INSERT INTO titrg_probe SELECT 3, update_timestamp FROM tt.todo_item WHERE id = 909301;

SELECT ok(
    (SELECT (SELECT ts FROM titrg_probe WHERE step = 3) > (SELECT ts FROM titrg_probe WHERE step = 2)),
    'S-TITRG-003: an UPDATE of details stamps a later update_timestamp'
);

DO $$ BEGIN PERFORM pg_sleep(0.02); END $$;
UPDATE tt.todo_item SET is_public = 1, todo_item_status_id = 2 WHERE id = 909301;
INSERT INTO titrg_probe SELECT 4, update_timestamp FROM tt.todo_item WHERE id = 909301;

SELECT ok(
    (SELECT (SELECT ts FROM titrg_probe WHERE step = 4) > (SELECT ts FROM titrg_probe WHERE step = 3)),
    'S-TITRG-003: an UPDATE of is_public + todo_item_status_id stamps a later update_timestamp'
);

-------------------------------------------------------------------------------
-- S-TITRG-004: SYSTIMESTAMP semantics -- wall clock at firing, within one transaction
-------------------------------------------------------------------------------

SELECT ok(
    (SELECT ts <= clock_timestamp()::timestamp AND ts > now()::timestamp FROM titrg_probe WHERE step = 4),
    'S-TITRG-004: the stamped time is never in the future and is later than the transaction start (not the transaction-start timestamp)'
);

SELECT * FROM finish();
ROLLBACK;
