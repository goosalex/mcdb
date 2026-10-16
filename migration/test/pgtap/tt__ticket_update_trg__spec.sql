-- migration/test/pgtap/tt__ticket_update_trg__spec.sql
--
-- pgTAP verification of migration/spec/tt.ticket_update_trg.md. RED by construction:
-- neither trigger tt.ticket_update_trg nor function tt.ticket_update_trg_fn exists yet.
-- Every assertion's description begins with the spec clause ID it verifies (HARN-05,
-- trace_lint.py). Expected values come from the SPEC ONLY -- never from
-- pg_migration/output/TRIGGER.pg.sql (raw ora2pg, which drops the column list) and never
-- from a PL/pgSQL translation.
--
-- Fixture id 909201 (tt.ticket; type_id 1 'incident' from masterdata; no FK rows needed).
-- The ticket's update_timestamp is reset by hand between cases via an UPDATE that names
-- ONLY update_timestamp -- which, per S-TTRG-004, must itself NOT fire the trigger; the
-- resets therefore double as S-TTRG-004 evidence rather than hiding it.

BEGIN;
SET CONSTRAINTS ALL DEFERRED;
SELECT plan(17);

-------------------------------------------------------------------------------
-- S-TTRG-001: shape
-------------------------------------------------------------------------------

SELECT ok(
    EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid = 'tt.ticket'::regclass AND tgname = 'ticket_update_trg' AND NOT tgisinternal),
    'S-TTRG-001: trigger tt.ticket_update_trg exists on tt.ticket'
);

-- tgtype bits: ROW=1, BEFORE=2, INSERT=4, UPDATE=16 -> 23 (no DELETE=8, no TRUNCATE=32)
SELECT is(
    (SELECT tgtype FROM pg_trigger WHERE tgrelid = 'tt.ticket'::regclass AND tgname = 'ticket_update_trg'),
    23::smallint,
    'S-TTRG-001: ticket_update_trg is BEFORE INSERT OR UPDATE, FOR EACH ROW, and never fires on DELETE'
);

SELECT is(
    (SELECT array_agg(a.attname::text ORDER BY a.attname)
     FROM pg_trigger t
     JOIN pg_attribute a ON a.attrelid = t.tgrelid AND a.attnum = ANY (t.tgattr::int2[])
     WHERE t.tgrelid = 'tt.ticket'::regclass AND t.tgname = 'ticket_update_trg'),
    ARRAY['always_visible', 'company_id', 'contact_id', 'customer_reference', 'customer_ticket_rating_id',
          'emergency', 'handled_by_mcc', 'host_id', 'last_public_event_id', 'mss_service_id',
          'status_id', 'subject', 'type_id']::text[],
    'S-TTRG-001: the UPDATE OF column list is exactly the 13 Oracle columns (no more, no fewer)'
);

SELECT ok(
    EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'tt' AND p.proname = 'ticket_update_trg_fn' AND p.prorettype = 'trigger'::regtype),
    'S-TTRG-001: tt.ticket_update_trg_fn() exists and RETURNS trigger'
);

SELECT is(
    (SELECT p.proname::text FROM pg_trigger t JOIN pg_proc p ON p.oid = t.tgfoid
     WHERE t.tgrelid = 'tt.ticket'::regclass AND t.tgname = 'ticket_update_trg'),
    'ticket_update_trg_fn'::text,
    'S-TTRG-001: the trigger executes tt.ticket_update_trg_fn'
);

-------------------------------------------------------------------------------
-- S-TTRG-002: INSERT stamps, overriding an explicit value
-------------------------------------------------------------------------------

INSERT INTO tt.ticket (id, type_id, status_id, update_timestamp)
    VALUES (909201, 1, 2, timestamp '2000-01-01 00:00:00');

SELECT isnt(
    (SELECT update_timestamp FROM tt.ticket WHERE id = 909201),
    timestamp '2000-01-01 00:00:00',
    'S-TTRG-002: an explicit update_timestamp supplied by the INSERT is overwritten'
);

SELECT ok(
    (SELECT update_timestamp >= now()::timestamp AND update_timestamp <= clock_timestamp()::timestamp FROM tt.ticket WHERE id = 909201),
    'S-TTRG-002: the INSERT-stamped update_timestamp is the current time (between transaction start and now)'
);

-------------------------------------------------------------------------------
-- S-TTRG-004: UPDATEs naming none of the 13 columns do not fire the trigger
-------------------------------------------------------------------------------

UPDATE tt.ticket SET update_timestamp = timestamp '2000-01-01 00:00:00' WHERE id = 909201;

SELECT is(
    (SELECT update_timestamp FROM tt.ticket WHERE id = 909201),
    timestamp '2000-01-01 00:00:00',
    'S-TTRG-004: an UPDATE naming only update_timestamp itself does not fire the trigger -- the explicit value sticks'
);

UPDATE tt.ticket SET summary_public = 'a public summary' WHERE id = 909201;

SELECT is(
    (SELECT update_timestamp FROM tt.ticket WHERE id = 909201),
    timestamp '2000-01-01 00:00:00',
    'S-TTRG-004: an UPDATE of summary_public (not in the list) leaves update_timestamp untouched'
);

UPDATE tt.ticket SET priority = 2, worker_id = NULL, last_resolved_date = now() WHERE id = 909201;

SELECT is(
    (SELECT update_timestamp FROM tt.ticket WHERE id = 909201),
    timestamp '2000-01-01 00:00:00',
    'S-TTRG-004: an UPDATE of priority/worker_id/last_resolved_date (none in the list) leaves update_timestamp untouched'
);

-------------------------------------------------------------------------------
-- S-TTRG-003: UPDATEs naming a listed column stamp, even unchanged / even overridden
-------------------------------------------------------------------------------

UPDATE tt.ticket SET status_id = status_id WHERE id = 909201;

SELECT ok(
    (SELECT update_timestamp >= now()::timestamp FROM tt.ticket WHERE id = 909201),
    'S-TTRG-003: an UPDATE that names status_id without changing its value still stamps update_timestamp'
);

UPDATE tt.ticket SET update_timestamp = timestamp '2000-01-01 00:00:00' WHERE id = 909201;
UPDATE tt.ticket SET subject = 'renamed', update_timestamp = timestamp '2001-01-01 00:00:00' WHERE id = 909201;

SELECT isnt(
    (SELECT update_timestamp FROM tt.ticket WHERE id = 909201),
    timestamp '2001-01-01 00:00:00',
    'S-TTRG-003: an UPDATE naming subject AND assigning update_timestamp explicitly has the explicit value overwritten by the trigger'
);

SELECT ok(
    (SELECT update_timestamp >= now()::timestamp FROM tt.ticket WHERE id = 909201),
    'S-TTRG-003: ...and the stamped value is the current time'
);

UPDATE tt.ticket SET update_timestamp = timestamp '2000-01-01 00:00:00' WHERE id = 909201;
UPDATE tt.ticket SET emergency = 1 WHERE id = 909201;

SELECT ok(
    (SELECT update_timestamp >= now()::timestamp FROM tt.ticket WHERE id = 909201),
    'S-TTRG-003: an UPDATE of emergency (listed) stamps update_timestamp'
);

UPDATE tt.ticket SET update_timestamp = timestamp '2000-01-01 00:00:00' WHERE id = 909201;
UPDATE tt.ticket SET handled_by_mcc = 0, customer_reference = 'ref-1' WHERE id = 909201;

SELECT ok(
    (SELECT update_timestamp >= now()::timestamp FROM tt.ticket WHERE id = 909201),
    'S-TTRG-003: an UPDATE of handled_by_mcc + customer_reference (listed) stamps update_timestamp'
);

-------------------------------------------------------------------------------
-- S-TTRG-005: SYSTIMESTAMP semantics -- wall clock at firing, advancing within one
-- transaction (a transaction-start timestamp would make both stamps identical).
-------------------------------------------------------------------------------

CREATE TEMP TABLE ttrg_probe (step int, ts timestamp);

UPDATE tt.ticket SET always_visible = 1 WHERE id = 909201;
INSERT INTO ttrg_probe SELECT 1, update_timestamp FROM tt.ticket WHERE id = 909201;
DO $$ BEGIN PERFORM pg_sleep(0.02); END $$;
UPDATE tt.ticket SET always_visible = 0 WHERE id = 909201;
INSERT INTO ttrg_probe SELECT 2, update_timestamp FROM tt.ticket WHERE id = 909201;

SELECT ok(
    (SELECT (SELECT ts FROM ttrg_probe WHERE step = 2) > (SELECT ts FROM ttrg_probe WHERE step = 1)),
    'S-TTRG-005: two qualifying UPDATEs in one transaction stamp strictly increasing times (wall clock at firing, not transaction start)'
);

SELECT ok(
    (SELECT ts <= clock_timestamp()::timestamp AND ts > now()::timestamp FROM ttrg_probe WHERE step = 2),
    'S-TTRG-005: the stamped time is never in the future and is later than the transaction start'
);

SELECT * FROM finish();
ROLLBACK;
