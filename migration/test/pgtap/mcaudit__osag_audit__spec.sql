-- migration/test/pgtap/mcaudit__osag_audit__spec.sql
--
-- pgTAP verification for migration/spec/mcaudit.osag_audit.md. RED by construction: none
-- of mcaudit.osag_audit_* exists yet. Every assertion's description starts with the spec
-- clause ID it verifies (HARN-05, trace_lint.py). Source of expected values is the SPEC
-- only -- never pg_migration/output/, never a PL/pgSQL translation.
--
-- The four routines return their ids through INOUT parameters. pgTAP cannot capture a
-- CALL's INOUT result directly, so four pg_temp helper functions CALL the procedure with
-- PL/pgSQL variables and record the returned ids in a temp table (audit_out), keyed by a
-- per-call tag. Every "did NOT happen" assertion sits next to a lives_ok/throws_ok
-- proving the CALL actually ran.
--
-- Reference rows reused from masterdata (the exact arguments AUTH.OSAG_AUTH_PASSPORT
-- passes, ddl/src/pkgb/auth_osag_auth_passport.sql:1873): mcaudit.application 1 'guma',
-- mcaudit.component 12 'authsys', mcaudit.record_type 4 'login_modify',
-- mcaudit.severity 10 'info'. mss.object_type and stop.company are empty in the
-- template -- plan-owned rows (9207xx / 9208xx) below. Explicit record ids use 9209xx.
--
-- Depends on migration/test/schema-fixes/26_p0601_fixes.sql (the three zitadel_user_*
-- columns ora2pg dropped from mcaudit.record).

BEGIN;
SET CONSTRAINTS ALL DEFERRED;
SELECT plan(67);

-------------------------------------------------------------------------------
-- S-AUDIT-001: all four routines exist as PostgreSQL PROCEDUREs (prokind='p').
-------------------------------------------------------------------------------

SELECT ok(
    EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'mcaudit' AND p.proname = 'osag_audit_add_record_raw' AND p.prokind = 'p'),
    'S-AUDIT-001: mcaudit.osag_audit_add_record_raw exists as a PostgreSQL PROCEDURE (prokind=p)'
);
SELECT ok(
    EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'mcaudit' AND p.proname = 'osag_audit_add_record_raw2' AND p.prokind = 'p'),
    'S-AUDIT-001: mcaudit.osag_audit_add_record_raw2 exists as a PostgreSQL PROCEDURE (prokind=p)'
);
SELECT ok(
    EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'mcaudit' AND p.proname = 'osag_audit_add_record' AND p.prokind = 'p'),
    'S-AUDIT-001: mcaudit.osag_audit_add_record exists as a PostgreSQL PROCEDURE (prokind=p)'
);
SELECT ok(
    EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'mcaudit' AND p.proname = 'osag_audit_add_record2' AND p.prokind = 'p'),
    'S-AUDIT-001: mcaudit.osag_audit_add_record2 exists as a PostgreSQL PROCEDURE (prokind=p)'
);
SELECT is(
    (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'mcaudit' AND p.proname IN ('osag_audit_add_record_raw', 'osag_audit_add_record_raw2', 'osag_audit_add_record', 'osag_audit_add_record2')
       AND p.proargmodes IS NOT NULL AND 'b' = ANY (p.proargmodes)),
    4::bigint,
    'S-AUDIT-001: every one of the four procedures has at least one INOUT parameter (proargmodes contains b)'
);

-------------------------------------------------------------------------------
-- Fixtures and helpers.
-------------------------------------------------------------------------------

INSERT INTO stop.company (id, name, short) VALUES (920702, 'P0601 Audit Co', 'p0601a');
INSERT INTO mss.object_type (id, table_name, java_class_name) VALUES
    (920801, 'AUTH.PASSPORT_LOGIN', 'p0601.PassportLogin'),
    (920802, 'P0601.DUP',           'p0601.Dup1'),
    (920803, 'P0601.DUP',           'p0601.Dup2');   -- table_name is NOT unique -> S-AUDIT-006

CREATE TEMP TABLE audit_out (tag text PRIMARY KEY, txn bigint, rec bigint);

CREATE FUNCTION pg_temp.run_raw2(
    p_tag text, p_app bigint, p_comp bigint, p_rt bigint, p_sev bigint, p_txn bigint,
    p_msg varchar, p_det text,
    p_company bigint DEFAULT NULL, p_contact bigint DEFAULT NULL, p_table varchar DEFAULT NULL,
    p_object bigint DEFAULT NULL, p_ticket bigint DEFAULT NULL, p_rec bigint DEFAULT NULL,
    p_zid varchar DEFAULT NULL, p_zname varchar DEFAULT NULL, p_zcomp bigint DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $h$
DECLARE
    v_txn bigint := p_txn;
    v_rec bigint := p_rec;
BEGIN
    CALL mcaudit.osag_audit_add_record_raw2(p_app, p_comp, p_rt, p_sev, v_txn, p_msg, p_det,
        p_company, p_contact, p_table, p_object, p_ticket, v_rec, p_zid, p_zname, p_zcomp);
    INSERT INTO audit_out (tag, txn, rec) VALUES (p_tag, v_txn, v_rec);
END
$h$;

CREATE FUNCTION pg_temp.run_raw(
    p_tag text, p_app bigint, p_comp bigint, p_rt bigint, p_sev bigint, p_txn bigint,
    p_msg varchar, p_det text,
    p_company bigint DEFAULT NULL, p_contact bigint DEFAULT NULL, p_table varchar DEFAULT NULL,
    p_object bigint DEFAULT NULL, p_ticket bigint DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $h$
DECLARE
    v_txn bigint := p_txn;
BEGIN
    CALL mcaudit.osag_audit_add_record_raw(p_app, p_comp, p_rt, p_sev, v_txn, p_msg, p_det,
        p_company, p_contact, p_table, p_object, p_ticket);
    INSERT INTO audit_out (tag, txn, rec) VALUES (p_tag, v_txn, NULL);
END
$h$;

CREATE FUNCTION pg_temp.run_add2(
    p_tag text, p_app varchar, p_comp varchar, p_rt varchar, p_sev varchar, p_txn bigint,
    p_msg varchar, p_det text,
    p_company bigint DEFAULT NULL, p_contact bigint DEFAULT NULL, p_table varchar DEFAULT NULL,
    p_object bigint DEFAULT NULL, p_ticket bigint DEFAULT NULL, p_rec bigint DEFAULT NULL,
    p_zid varchar DEFAULT NULL, p_zname varchar DEFAULT NULL, p_zcomp bigint DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $h$
DECLARE
    v_txn bigint := p_txn;
    v_rec bigint := p_rec;
BEGIN
    CALL mcaudit.osag_audit_add_record2(p_app, p_comp, p_rt, p_sev, v_txn, p_msg, p_det,
        p_company, p_contact, p_table, p_object, p_ticket, v_rec, p_zid, p_zname, p_zcomp);
    INSERT INTO audit_out (tag, txn, rec) VALUES (p_tag, v_txn, v_rec);
END
$h$;

CREATE FUNCTION pg_temp.run_add(
    p_tag text, p_app varchar, p_comp varchar, p_rt varchar, p_sev varchar, p_txn bigint,
    p_msg varchar, p_det text,
    p_company bigint DEFAULT NULL, p_contact bigint DEFAULT NULL, p_table varchar DEFAULT NULL,
    p_object bigint DEFAULT NULL, p_ticket bigint DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $h$
DECLARE
    v_txn bigint := p_txn;
BEGIN
    CALL mcaudit.osag_audit_add_record(p_app, p_comp, p_rt, p_sev, v_txn, p_msg, p_det,
        p_company, p_contact, p_table, p_object, p_ticket);
    INSERT INTO audit_out (tag, txn, rec) VALUES (p_tag, v_txn, NULL);
END
$h$;

-------------------------------------------------------------------------------
-- add_record_raw2 (S-AUDIT-002..007, 013)
-------------------------------------------------------------------------------

-- a1: everything NULL that can be allocated; every column supplied.
SELECT lives_ok(
    $$SELECT pg_temp.run_raw2('a1', 1, 12, 4, 10, NULL, 'p0601 msg a1', '<details><p0601 /></details>',
                              920702, NULL, 'AUTH.PASSPORT_LOGIN', 4711, NULL, NULL, 'zid-a1', 'zname-a1', 920702)$$,
    'S-AUDIT-004: add_record_raw2 succeeds with NULL transaction/record ids and every other column supplied'
);
SELECT ok(
    (SELECT txn IS NOT NULL AND txn > 0 FROM audit_out WHERE tag = 'a1'),
    'S-AUDIT-002: a NULL io_transaction_id comes back allocated (not NULL, positive)'
);
SELECT ok(
    (SELECT rec IS NOT NULL AND rec > 0 FROM audit_out WHERE tag = 'a1'),
    'S-AUDIT-003: a NULL io_record_id comes back allocated (not NULL, positive)'
);
SELECT is(
    (SELECT count(*) FROM mcaudit.record r JOIN audit_out o ON o.tag = 'a1' AND r.id = o.rec
     WHERE r.transaction_id = o.txn
       AND r.application_id = 1 AND r.component_id = 12 AND r.record_type_id = 4 AND r.severity_id = 10
       AND r.message = 'p0601 msg a1' AND r.details = '<details><p0601 /></details>'
       AND r.company_id = 920702 AND r.contact_id IS NULL AND r.object_id = 4711 AND r.ticket_id IS NULL
       AND r.zitadel_user_id = 'zid-a1' AND r.zitadel_user_name = 'zname-a1' AND r.zitadel_user_company_id = 920702),
    1::bigint,
    'S-AUDIT-004: exactly one mcaudit.record row with id = io_record_id, transaction_id = io_transaction_id and every column verbatim from the parameters'
);
SELECT is(
    (SELECT object_type_id FROM mcaudit.record WHERE message = 'p0601 msg a1'),
    920801::bigint,
    'S-AUDIT-005: object_type_id is resolved from mss.object_type.table_name = i_table_name'
);
SELECT ok(
    (SELECT "timestamp" > now() - interval '1 minute' AND "timestamp" <= now() + interval '1 second'
     FROM mcaudit.record WHERE message = 'p0601 msg a1'),
    'S-AUDIT-004: timestamp is the current timestamp'
);
SELECT is(
    (SELECT count(*) FROM mcaudit.record WHERE message LIKE 'p0601 msg a1%'),
    1::bigint,
    'S-AUDIT-004: add_record_raw2 inserts exactly ONE row per call'
);

-- a2: both ids supplied -> used unchanged.
SELECT lives_ok(
    $$SELECT pg_temp.run_raw2('a2', 1, 12, 4, 10, (SELECT txn FROM audit_out WHERE tag = 'a1'), 'p0601 msg a2', NULL,
                              NULL, NULL, NULL, NULL, NULL, 920901)$$,
    'S-AUDIT-003: add_record_raw2 succeeds with an explicit io_record_id (920901) and the a1 transaction id'
);
SELECT is(
    (SELECT rec FROM audit_out WHERE tag = 'a2'),
    920901::bigint,
    'S-AUDIT-003: an explicit io_record_id is used as-is and returned unchanged'
);
SELECT is(
    (SELECT id FROM mcaudit.record WHERE message = 'p0601 msg a2'),
    920901::bigint,
    'S-AUDIT-003: the row id IS the explicit io_record_id'
);
SELECT is(
    (SELECT txn FROM audit_out WHERE tag = 'a2'),
    (SELECT txn FROM audit_out WHERE tag = 'a1'),
    'S-AUDIT-002: an explicit io_transaction_id is used unchanged and returned unchanged'
);
SELECT is(
    (SELECT count(*) FROM mcaudit.record WHERE transaction_id = (SELECT txn FROM audit_out WHERE tag = 'a1')),
    2::bigint,
    'S-AUDIT-002: two records can share one transaction id'
);
SELECT is(
    (SELECT count(*) FROM mcaudit.record WHERE message = 'p0601 msg a2' AND details IS NULL AND company_id IS NULL
       AND object_type_id IS NULL AND zitadel_user_id IS NULL AND zitadel_user_name IS NULL AND zitadel_user_company_id IS NULL),
    1::bigint,
    'S-AUDIT-005: a NULL i_table_name yields a NULL object_type_id (and the other NULL inputs are stored as NULL)'
);

-- a3: a second allocated pair differs from the first (sequence-backed).
SELECT lives_ok(
    $$SELECT pg_temp.run_raw2('a3', 1, 12, 4, 10, NULL, 'p0601 msg a3', NULL, NULL, NULL, 'P0601.UNKNOWN')$$,
    'S-AUDIT-005: add_record_raw2 succeeds with an i_table_name that matches no mss.object_type row'
);
SELECT ok(
    (SELECT a3.txn <> a1.txn AND a3.rec <> a1.rec FROM audit_out a1, audit_out a3 WHERE a1.tag = 'a1' AND a3.tag = 'a3'),
    'S-AUDIT-002: a second call with NULL ids allocates a DIFFERENT transaction id and record id (sequences)'
);
SELECT is(
    (SELECT object_type_id FROM mcaudit.record WHERE message = 'p0601 msg a3'),
    NULL::bigint,
    'S-AUDIT-005: an unknown i_table_name yields a NULL object_type_id, no error'
);

-- S-AUDIT-006: duplicate table_name -> cardinality violation, nothing inserted.
SELECT throws_ok(
    $$SELECT pg_temp.run_raw2('a4', 1, 12, 4, 10, NULL, 'p0601 msg a4 dup', NULL, NULL, NULL, 'P0601.DUP')$$,
    '21000', NULL,
    'S-AUDIT-006: an i_table_name matching two mss.object_type rows raises SQLSTATE 21000 (Oracle ORA-01427)'
);
SELECT is(
    (SELECT count(*) FROM mcaudit.record WHERE message = 'p0601 msg a4 dup'),
    0::bigint,
    'S-AUDIT-006: no record is inserted when the object_type subquery fails'
);

-- S-AUDIT-007: NOT NULL inputs.
SELECT throws_ok(
    $$SELECT pg_temp.run_raw2('a5', 1, 12, 4, 10, NULL, NULL, 'p0601 det a5')$$,
    '23502', NULL,
    'S-AUDIT-007: a NULL i_message raises not_null_violation (23502), propagated unhandled'
);
SELECT is(
    (SELECT count(*) FROM mcaudit.record WHERE details = 'p0601 det a5'),
    0::bigint,
    'S-AUDIT-007: no record is inserted for a NULL message'
);
SELECT throws_ok(
    $$SELECT pg_temp.run_raw2('a6', NULL, 12, 4, 10, NULL, 'p0601 msg a6', NULL)$$,
    '23502', NULL,
    'S-AUDIT-007: a NULL i_application_id raises not_null_violation (23502)'
);
SELECT throws_ok(
    $$SELECT pg_temp.run_raw2('a7', 1, 12, 4, NULL, NULL, 'p0601 msg a7', NULL)$$,
    '23502', NULL,
    'S-AUDIT-007: a NULL i_severity_id raises not_null_violation (23502) -- the column DEFAULT 30 does not apply to an explicit NULL'
);
SELECT is(
    (SELECT count(*) FROM mcaudit.record WHERE message IN ('p0601 msg a6', 'p0601 msg a7')),
    0::bigint,
    'S-AUDIT-007: no record is inserted for the NULL-id cases'
);

-- S-AUDIT-013: '' is NULL (Oracle semantics) at the single writer.
SELECT throws_ok(
    $$SELECT pg_temp.run_raw2('a8', 1, 12, 4, 10, NULL, '', 'p0601 det a8')$$,
    '23502', NULL,
    'S-AUDIT-013: an EMPTY i_message is treated as NULL and raises not_null_violation (23502), as Oracle did'
);
SELECT is(
    (SELECT count(*) FROM mcaudit.record WHERE details = 'p0601 det a8'),
    0::bigint,
    'S-AUDIT-013: no record is inserted for an empty message'
);
SELECT lives_ok(
    $$SELECT pg_temp.run_raw2('a9', 1, 12, 4, 10, NULL, 'p0601 msg a9', '', NULL, NULL, '', NULL, NULL, NULL, '', '', NULL)$$,
    'S-AUDIT-013: add_record_raw2 succeeds with empty details / table name / zitadel strings'
);
SELECT is(
    (SELECT count(*) FROM mcaudit.record WHERE message = 'p0601 msg a9'
       AND details IS NULL AND object_type_id IS NULL AND zitadel_user_id IS NULL AND zitadel_user_name IS NULL),
    1::bigint,
    'S-AUDIT-013: empty details / table name / zitadel strings are stored as NULL (object_type_id NULL)'
);

-------------------------------------------------------------------------------
-- add_record_raw (S-AUDIT-008, 012)
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$SELECT pg_temp.run_raw('r1', 1, 12, 4, 10, NULL, 'p0601 msg r1', '<d/>', 920702, NULL, 'AUTH.PASSPORT_LOGIN', 4712, NULL)$$,
    'S-AUDIT-008: add_record_raw succeeds with a NULL transaction id'
);
SELECT ok(
    (SELECT txn IS NOT NULL AND txn > 0 FROM audit_out WHERE tag = 'r1'),
    'S-AUDIT-008: add_record_raw returns the allocated transaction id through io_transaction_id'
);
SELECT is(
    (SELECT count(*) FROM mcaudit.record r JOIN audit_out o ON o.tag = 'r1'
     WHERE r.message = 'p0601 msg r1' AND r.transaction_id = o.txn
       AND r.application_id = 1 AND r.component_id = 12 AND r.record_type_id = 4 AND r.severity_id = 10
       AND r.details = '<d/>' AND r.company_id = 920702 AND r.object_type_id = 920801 AND r.object_id = 4712
       AND r.zitadel_user_id IS NULL AND r.zitadel_user_name IS NULL AND r.zitadel_user_company_id IS NULL),
    1::bigint,
    'S-AUDIT-008: add_record_raw writes one row with its parameters, the returned transaction id, and NULL zitadel columns'
);
SELECT ok(
    (SELECT r.id IS NOT NULL AND r.id > 0 FROM mcaudit.record r WHERE r.message = 'p0601 msg r1'),
    'S-AUDIT-008: the discarded record id was still allocated from the sequence (row id not NULL)'
);
-- S-AUDIT-012: callable with the first seven arguments only (SQL-level CALL, literal INOUT).
SELECT lives_ok(
    $$CALL mcaudit.osag_audit_add_record_raw(1, 12, 4, 10, NULL, 'p0601 msg r2', NULL)$$,
    'S-AUDIT-012: add_record_raw is callable with only its first seven arguments'
);
SELECT is(
    (SELECT count(*) FROM mcaudit.record WHERE message = 'p0601 msg r2' AND company_id IS NULL AND contact_id IS NULL
       AND object_type_id IS NULL AND object_id IS NULL AND ticket_id IS NULL),
    1::bigint,
    'S-AUDIT-012: the defaulted parameters of add_record_raw are NULL in the row'
);

-------------------------------------------------------------------------------
-- add_record2 (S-AUDIT-009, 010, 012)
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$SELECT pg_temp.run_add2('b1', 'guma', 'authsys', 'login_modify', 'info', NULL, 'p0601 msg b1', '<d/>',
                              920702, NULL, 'AUTH.PASSPORT_LOGIN', 4713, NULL, NULL, 'zid-b1', 'zname-b1', 920702)$$,
    'S-AUDIT-009: add_record2 succeeds with the short names AUTH_PASSPORT uses (guma/authsys/login_modify/info)'
);
SELECT is(
    (SELECT count(*) FROM mcaudit.record r JOIN audit_out o ON o.tag = 'b1' AND r.id = o.rec
     WHERE r.message = 'p0601 msg b1' AND r.transaction_id = o.txn
       AND r.application_id = 1 AND r.component_id = 12 AND r.record_type_id = 4 AND r.severity_id = 10
       AND r.details = '<d/>' AND r.company_id = 920702 AND r.object_type_id = 920801 AND r.object_id = 4713
       AND r.zitadel_user_id = 'zid-b1' AND r.zitadel_user_name = 'zname-b1' AND r.zitadel_user_company_id = 920702),
    1::bigint,
    'S-AUDIT-009: add_record2 resolves guma->1, authsys->12, login_modify->4, info->10 and writes one row whose id is the returned io_record_id'
);
SELECT ok(
    (SELECT txn IS NOT NULL AND rec IS NOT NULL FROM audit_out WHERE tag = 'b1'),
    'S-AUDIT-009: add_record2 returns both the transaction id and the record id'
);
-- explicit record id passes through
SELECT lives_ok(
    $$SELECT pg_temp.run_add2('b2', 'guma', 'authsys', 'login_modify', 'info', NULL, 'p0601 msg b2', NULL,
                              NULL, NULL, NULL, NULL, NULL, 920902)$$,
    'S-AUDIT-009: add_record2 succeeds with an explicit io_record_id'
);
SELECT is(
    (SELECT id FROM mcaudit.record WHERE message = 'p0601 msg b2'),
    920902::bigint,
    'S-AUDIT-009: add_record2 passes an explicit io_record_id through to add_record_raw2'
);

-- S-AUDIT-010: unknown shorts -> no data found, nothing inserted.
SELECT throws_ok(
    $$SELECT pg_temp.run_add2('b3', 'p0601_nope', 'authsys', 'login_modify', 'info', NULL, 'p0601 msg b3', NULL)$$,
    'P0002', NULL,
    'S-AUDIT-010: add_record2 with an unknown application short raises no_data_found (P0002)'
);
SELECT throws_like(
    $$SELECT pg_temp.run_add2('b3', 'p0601_nope', 'authsys', 'login_modify', 'info', NULL, 'p0601 msg b3', NULL)$$,
    '%no data found%',
    'S-AUDIT-010: the unknown-short error carries Oracle''s message text "no data found"'
);
SELECT throws_ok(
    $$SELECT pg_temp.run_add2('b4', 'guma', 'p0601_nope', 'login_modify', 'info', NULL, 'p0601 msg b4', NULL)$$,
    'P0002', NULL,
    'S-AUDIT-010: add_record2 with an unknown component short raises P0002'
);
SELECT throws_ok(
    $$SELECT pg_temp.run_add2('b5', 'guma', 'authsys', 'p0601_nope', 'info', NULL, 'p0601 msg b5', NULL)$$,
    'P0002', NULL,
    'S-AUDIT-010: add_record2 with an unknown record type short raises P0002'
);
SELECT throws_ok(
    $$SELECT pg_temp.run_add2('b6', 'guma', 'authsys', 'login_modify', 'p0601_nope', NULL, 'p0601 msg b6', NULL)$$,
    'P0002', NULL,
    'S-AUDIT-010: add_record2 with an unknown severity short raises P0002'
);
SELECT is(
    (SELECT count(*) FROM mcaudit.record WHERE message IN ('p0601 msg b3', 'p0601 msg b4', 'p0601 msg b5', 'p0601 msg b6')),
    0::bigint,
    'S-AUDIT-010: no record is inserted when a short cannot be resolved'
);
SELECT is(
    (SELECT count(*) FROM audit_out WHERE tag IN ('b3', 'b4', 'b5', 'b6')),
    0::bigint,
    'S-AUDIT-010: the failed calls returned nothing (helper never reached its INSERT)'
);
-- S-AUDIT-012: callable with the first seven arguments only.
SELECT lives_ok(
    $$CALL mcaudit.osag_audit_add_record2('guma', 'authsys', 'login_modify', 'info', NULL, 'p0601 msg b7', NULL)$$,
    'S-AUDIT-012: add_record2 is callable with only its first seven arguments (io_record_id defaults to NULL = allocate)'
);
SELECT is(
    (SELECT count(*) FROM mcaudit.record WHERE message = 'p0601 msg b7' AND id IS NOT NULL AND company_id IS NULL
       AND object_type_id IS NULL AND zitadel_user_id IS NULL),
    1::bigint,
    'S-AUDIT-012: the seven-argument add_record2 call allocated a record id and left the defaulted columns NULL'
);

-------------------------------------------------------------------------------
-- add_record (S-AUDIT-010, 011, 012, 015)
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$SELECT pg_temp.run_add('c1', 'guma', 'authsys', 'login_modify', 'info', NULL, 'p0601 msg c1', '<details />',
                             920702, NULL, 'AUTH.PASSPORT_LOGIN', 4714, NULL)$$,
    'S-AUDIT-011: add_record succeeds with the AUTH_PASSPORT argument shape'
);
SELECT is(
    (SELECT count(*) FROM mcaudit.record r JOIN audit_out o ON o.tag = 'c1'
     WHERE r.message = 'p0601 msg c1' AND r.transaction_id = o.txn
       AND r.application_id = 1 AND r.component_id = 12 AND r.record_type_id = 4 AND r.severity_id = 10
       AND r.details = '<details />' AND r.company_id = 920702 AND r.object_type_id = 920801 AND r.object_id = 4714
       AND r.zitadel_user_id IS NULL AND r.zitadel_user_name IS NULL AND r.zitadel_user_company_id IS NULL),
    1::bigint,
    'S-AUDIT-011: add_record resolves the shorts, writes one row with the returned transaction id and NULL zitadel columns'
);
SELECT ok(
    (SELECT txn IS NOT NULL AND txn > 0 FROM audit_out WHERE tag = 'c1'),
    'S-AUDIT-011: add_record returns the allocated transaction id through io_transaction_id'
);
-- reuse of a transaction id across add_record calls
SELECT lives_ok(
    $$SELECT pg_temp.run_add('c2', 'guma', 'authsys', 'login_modify', 'info', (SELECT txn FROM audit_out WHERE tag = 'c1'), 'p0601 msg c2', NULL)$$,
    'S-AUDIT-011: add_record succeeds with the c1 transaction id passed in'
);
SELECT is(
    (SELECT count(*) FROM mcaudit.record WHERE transaction_id = (SELECT txn FROM audit_out WHERE tag = 'c1')),
    2::bigint,
    'S-AUDIT-011: both add_record rows share the passed-in transaction id'
);
SELECT is(
    (SELECT txn FROM audit_out WHERE tag = 'c2'),
    (SELECT txn FROM audit_out WHERE tag = 'c1'),
    'S-AUDIT-011: a passed-in io_transaction_id is returned unchanged by add_record'
);
SELECT throws_ok(
    $$SELECT pg_temp.run_add('c3', 'guma', 'authsys', 'login_modify', 'p0601_nope', NULL, 'p0601 msg c3', NULL)$$,
    'P0002', NULL,
    'S-AUDIT-010: add_record with an unknown severity short raises no_data_found (P0002)'
);
SELECT is(
    (SELECT count(*) FROM mcaudit.record WHERE message = 'p0601 msg c3'),
    0::bigint,
    'S-AUDIT-010: no record is inserted by the failing add_record call'
);
SELECT lives_ok(
    $$CALL mcaudit.osag_audit_add_record('guma', 'authsys', 'login_modify', 'info', NULL, 'p0601 msg c4', NULL)$$,
    'S-AUDIT-012: add_record is callable with only its first seven arguments'
);
SELECT is(
    (SELECT count(*) FROM mcaudit.record WHERE message = 'p0601 msg c4' AND company_id IS NULL AND contact_id IS NULL
       AND object_type_id IS NULL AND object_id IS NULL AND ticket_id IS NULL),
    1::bigint,
    'S-AUDIT-012: the defaulted parameters of add_record are NULL in the row'
);

-- S-AUDIT-015: no COMMIT inside -- the rows are still in this (uncommitted) transaction
-- and a SAVEPOINT rollback removes them, which a committing procedure would make impossible.
SAVEPOINT p0601_audit;
SELECT lives_ok(
    $$CALL mcaudit.osag_audit_add_record('guma', 'authsys', 'login_modify', 'info', NULL, 'p0601 msg c5 rollback', NULL)$$,
    'S-AUDIT-015: add_record succeeds inside a savepoint'
);
SELECT is(
    (SELECT count(*) FROM mcaudit.record WHERE message = 'p0601 msg c5 rollback'),
    1::bigint,
    'S-AUDIT-015: the row is visible inside the caller''s transaction'
);
ROLLBACK TO SAVEPOINT p0601_audit;
SELECT is(
    (SELECT count(*) FROM mcaudit.record WHERE message = 'p0601 msg c5 rollback'),
    0::bigint,
    'S-AUDIT-015: rolling back the caller''s savepoint removes the audit record -- no COMMIT inside the package'
);

-- S-AUDIT-014: the usage audit is deleted, not stubbed -- no AuditUsage call remains.
SELECT is(
    (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'mcaudit' AND p.proname LIKE 'osag_audit_%' AND p.prosrc ~* 'auditusage'),
    0::bigint,
    'S-AUDIT-014: no mcaudit.osag_audit_* body references AuditUsage'
);
SELECT is(
    (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'mcaudit' AND p.proname LIKE 'osag_audit_%'),
    4::bigint,
    'S-AUDIT-001: exactly four mcaudit.osag_audit_* routines exist (no private helpers, no stubs)'
);

SELECT * FROM finish();
ROLLBACK;
