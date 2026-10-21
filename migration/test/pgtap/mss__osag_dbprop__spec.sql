-- migration/test/pgtap/mss__osag_dbprop__spec.sql
--
-- pgTAP verification for migration/spec/mss.osag_dbprop.md. RED by construction: none of
-- mss.osag_dbprop_* exists yet (translation is a later plan). Every assertion's
-- description starts with the spec clause ID it verifies (HARN-05, trace_lint.py).
--
-- KNOWN GAP (recorded in 02-04-SUMMARY.md): the real ora2pg-migrated
-- mss.v_host_key_value view is backed by the materialized view
-- mss.mv_value_host_default, and per 02-03-SUMMARY.md, everything under
-- ddl/migrated/mviews/ is explicitly out of scope for the mcdb_tmpl template — neither
-- the view nor its materialized view exist in this database. get_string_by_host_key_id's
-- spec (S-DBPROP-003/004/005) is written against the REAL Oracle view
-- (mss.V_HOST_KEY_VALUE, ddl/src/pkgb/mss_osag_dbprop.sql:41-45), so exercising it here
-- needs SOME queryable relation of that name and shape. This file creates a
-- transaction-scoped substitute view with the same 5-column contract
-- (host_id, key_name, scope, object_id, string_value), derived directly from
-- mss.value + mss.key, sufficient for host-scoped lookups. This is a TEST FIXTURE, not a
-- claim about how the real view should be translated — flagged for Phase 4/5 as a
-- schema-completeness gap the pilot surfaced (mviews/ loading), same spirit as
-- migration/test/SCHEMA-FIXES.md.

BEGIN;
SET CONSTRAINTS ALL DEFERRED;

-- Since schema-fix 28 (2026-10-21) the REAL mss.v_host_key_value exists in the template,
-- backed by the materialized views mss.mv_value_host / mss.mv_value_host_default, which
-- are never refreshed inside a test transaction -- so the transaction-scoped substitute
-- below is still what makes these assertions observable. DROP (rolled back with the rest)
-- replaces CREATE OR REPLACE, which cannot change the real view's varchar(4000) columns.
DROP VIEW mss.v_host_key_value;
CREATE VIEW mss.v_host_key_value (host_id, key_name, scope, object_id, string_value) AS
SELECT v.host_id, k.name AS key_name, 'host'::text AS scope, v.host_id AS object_id, v.string_value
FROM mss.value v JOIN mss.key k ON k.id = v.key_id
WHERE v.host_id IS NOT NULL;

SELECT plan(10);

-- Fixture: reuse the existing masterdata mss.key row (id=4, name='vrrp.monitor.ipsec',
-- key_type_id=1 boolean, string_default='1') rather than inventing a new key — avoids
-- colliding with mss.key's unique name index. host_id values are fake (mss.host has no
-- masterdata rows to reuse); SET CONSTRAINTS ALL DEFERRED above defers that FK check
-- past this transaction's ROLLBACK, so it is never actually enforced.
INSERT INTO mss.value (id, key_id, host_id, string_value) VALUES (900101, 4, 999901, '1');

-- S-DBPROP-002: get_number_by_host collapses the underlying string to 1 (exact '1') or
-- 0 (anything else, including no matching value at all).
SELECT is(
    mss.osag_dbprop_get_number_by_host(999901, 'vrrp.monitor.ipsec')::int,
    1,
    'S-DBPROP-002: get_number_by_host returns 1 when the underlying string value is exactly ''1'''
);

SELECT is(
    mss.osag_dbprop_get_number_by_host(999902, 'vrrp.monitor.ipsec')::int,
    0,
    'S-DBPROP-002: get_number_by_host returns 0 for a host with no matching value at all'
);

-- S-DBPROP-003: no matching host/key combination returns NULL, not an exception (cursor
-- FOR loop over zero rows is a no-op, never NO_DATA_FOUND).
SELECT is(
    mss.osag_dbprop_get_string_by_host_key_id(999902, 4),
    NULL,
    'S-DBPROP-003: get_string_by_host_key_id returns NULL (no exception) when zero rows match the host/key pair'
);

-- S-DBPROP-004: duplicate rows that AGREE are logged as a WARNING and the common value
-- is still returned.
INSERT INTO mss.value (id, key_id, host_id, string_value) VALUES (900102, 4, 999903, '1');
INSERT INTO mss.value (id, key_id, host_id, string_value) VALUES (900103, 4, 999903, '1');

SELECT is(
    mss.osag_dbprop_get_string_by_host_key_id(999903, 4),
    '1',
    'S-DBPROP-004: get_string_by_host_key_id returns the common value when duplicate rows agree'
);

SELECT ok(
    EXISTS(SELECT 1 FROM osag.plog_stub_log WHERE message LIKE '%multiple but consistent values%'),
    'S-DBPROP-004: get_string_by_host_key_id logs a WARNING (not an exception) when duplicate rows agree'
);

-- S-DBPROP-005: duplicate rows that DISAGREE are logged as an ERR, no exception raised,
-- first-seen value still returned.
INSERT INTO mss.value (id, key_id, host_id, string_value) VALUES (900104, 4, 999904, '1');
INSERT INTO mss.value (id, key_id, host_id, string_value) VALUES (900105, 4, 999904, '0');

SELECT lives_ok(
    $$SELECT mss.osag_dbprop_get_string_by_host_key_id(999904, 4)$$,
    'S-DBPROP-005: get_string_by_host_key_id does NOT raise when duplicate rows disagree, it only logs'
);

SELECT ok(
    EXISTS(SELECT 1 FROM osag.plog_stub_log WHERE message LIKE '%multiple inconsistently values%'),
    'S-DBPROP-005: get_string_by_host_key_id logs an ERR (not an exception) when duplicate rows disagree'
);

-- S-DBPROP-006 / S-DBPROP-009: unknown property name raises the same error whether the
-- caller passes NULL or '' — Oracle collapses both to the same lookup outcome.
SELECT throws_like(
    $$SELECT mss.osag_dbprop_get_string_by_host(999901, 'no-such-property')$$,
    '%unknown db property%',
    'S-DBPROP-006: get_string_by_host raises ''unknown db property'' for a name with no matching mss.key row'
);

SELECT throws_like(
    $$SELECT mss.osag_dbprop_get_string_by_host(999901, '')$$,
    '%unknown db property%',
    'S-DBPROP-009: get_string_by_host raises the same unknown-property error for an empty-string property name (Oracle NULL/'''' collapsing)'
);

SELECT throws_like(
    $$SELECT mss.osag_dbprop_get_string_by_host(999901, NULL)$$,
    '%unknown db property%',
    'S-DBPROP-009: get_string_by_host raises the same unknown-property error for a NULL property name (Oracle NULL/'''' collapsing)'
);

SELECT * FROM finish();
ROLLBACK;
