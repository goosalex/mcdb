-- migration/test/bootstrap/00_extensions.sql
--
-- Extensions required by the dual test harness. Applied by bootstrap.sh to
-- every disposable test database (and to the mcdb_tmpl template, once plan
-- 02-03 builds it).
--
-- orafce installs into schema `oracle` plus `public` — do not attempt to
-- relocate it; downstream PL/pgSQL that depends on orafce compatibility
-- functions expects the default search_path behavior.

CREATE EXTENSION IF NOT EXISTS orafce;
CREATE EXTENSION IF NOT EXISTS pgtap;
