-- migration/test/pgtap/_canary__canary__smoke.sql
--
-- Harness self-test (D-P9 reserved `_canary` schema). Not a translation
-- test for any real Oracle package — it exists to prove the pgTAP half of
-- the harness can run at all, and (via a deliberate mutation in Task 3) that
-- it can genuinely fail.

BEGIN;
SELECT plan(2);

SELECT ok(true, 'pgTAP can assert a true expression');
SELECT is(1 + 1, 2, 'pgTAP can assert over a trivially-known value');

SELECT * FROM finish();
ROLLBACK;
