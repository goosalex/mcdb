-- migration/test/regress/sql/_canary__canary__smoke.sql
--
-- Harness self-test (D-P9 reserved `_canary` schema). Not a translation
-- test for any real Oracle package — it exists to prove the expected-output
-- half of the harness can run at all, and (via a deliberate mutation in
-- Task 3) that it can genuinely fail on a golden-file drift.

SELECT 1 AS one, 'canary' AS label;
