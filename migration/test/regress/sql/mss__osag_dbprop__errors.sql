-- migration/test/regress/sql/mss__osag_dbprop__errors.sql
-- verifies: S-DBPROP-006, S-DBPROP-009
--
-- Expected-output harness half: pins the EXACT psql error text (including SQLSTATE) for
-- MSS.OSAG_DBPROP's "unknown db property" error path, and its NULL/'' equivalence
-- (S-DBPROP-009). RED right now because none of the mss.osag_dbprop_* functions exist
-- yet -- run with ON_ERROR_STOP=0 (the harness's expected-output convention), so every
-- statement below runs and its own error is captured independently rather than aborting
-- the whole script after the first one.

SELECT mss.osag_dbprop_get_string_by_host(1, 'no-such-property-xyz');

SELECT mss.osag_dbprop_get_string_by_host(1, '');

SELECT mss.osag_dbprop_get_string_by_host(1, NULL);
