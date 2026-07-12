# SCHEMA-FIXES.md — ora2pg gaps this plan's pilot template surfaced

Loading the REAL ora2pg-converted schema (`ddl/migrated/`) — the locked decision for
Phase 2's test database, not a hand-built fixture — surfaced errors, exactly as
`CLAUDE.md` warns ("It might contain errors"). Fixing what the pilot's tables need is
IN SCOPE for this plan (02-CONTEXT.md, "Test schema — LOCKED"). This document is the
ledger: every fix applied, its root cause, and — the point of the whole document —
whether Phase 5's container build should apply the SAME fix file, or fix the ora2pg
configuration and regenerate. Every failure left deliberately UNFIXED is also recorded,
with the reason it was out of the pilot's reach.

`ddl/migrated/` itself is **never edited** (D-P7). Fixes #1–#2 are additive files loaded
BEFORE the base schema load (they must exist before `tables.pg.sql` can reference them);
fixes #3–#4 are additive files loaded AFTER it (`migration/test/schema-fixes/`).

## Fix ledger

| # | Object | Error observed | Fix applied | Root cause (ora2pg behaviour) | Phase 5 action |
|---|--------|-----------------|--------------|-------------------------------|-----------------|
| 1 | Every one of 116 `ddl/migrated/users/*.sql` files (`GRANT %I TO postgresadmin`) | `role "postgresadmin" does not exist` — and because each file is one `DO $do$...$do$` block (one implicit transaction), the failing `GRANT` rolls back the `CREATE ROLE` and `CREATE SCHEMA AUTHORIZATION` that preceded it in the SAME file, so **every** one of the 116 files fails completely, not just the grant line | `migration/test/bootstrap/10_schemas_roles.sql` creates `postgresadmin` (`CREATE ROLE postgresadmin;`, idempotent) as its first statement, before `\ir`-including any of the 116 `ddl/migrated/users/*.sql` files | ora2pg's export assumes a `postgresadmin` role already exists in the target cluster — presumably provisioned by container/cluster setup outside ora2pg's own export scope, not a translation bug in the SQL itself | Either provision `postgresadmin` as part of Phase 5's container bootstrap (the more likely correct fix, matching what production Oracle→PG migration tooling would assume), or carry this exact one-line fix forward verbatim. Not an ora2pg regeneration issue. |
| 2 | 43 `CREATE TABLE checklist.*` / `ALTER TABLE checklist.*` statements in `tables.pg.sql` (lines 1619-4740) | `schema "checklist" does not exist` | `migration/test/bootstrap/10_schemas_roles.sql` appends a `checklist` role+schema DO block, reconstructed using the IDENTICAL pattern ora2pg emits for every other schema (`ddl/migrated/users/*.sql`) | `ddl/migrated/users/` is missing a `CHECKLIST.sql` file. Every OTHER schema referenced anywhere in `tables.pg.sql` has a matching `users/<SCHEMA>.sql` role/schema file; `checklist` is the sole exception — a genuine ora2pg export gap, not a translation error (the reconstructed DO block is byte-for-byte the same shape ora2pg uses elsewhere, just with `checklist` substituted) | Fix the ora2pg export configuration so it emits `CHECKLIST.sql` like every other schema, and regenerate `ddl/migrated/users/`. Until then, carry this fix forward. |
| 3 | 15 `ALTER TABLE ... ADD CONSTRAINT ... FOREIGN KEY` statements in `constraints/fk-constraints.pg.sql` (lines 569, 637, 638, 643, 644, 762, 764, 766, 772, 773, 774, 787, 795, 803, 804) | `foreign key constraint "X" cannot be implemented` / `DETAIL: Key columns "<fk_col>" and "id" are of incompatible types: numeric and bigint` | `migration/test/schema-fixes/10_ora2pg_fixes.sql`: widens each offending FK column from `numeric` to `bigint` (matching the `bigint` surrogate-id PK it references) via `ALTER TABLE ... ALTER COLUMN ... TYPE bigint USING ...::bigint`, then re-applies the 15 FK constraints verbatim. 3 of the 15 affected tables (`mss.local_contact_notification`, `tt.event`, `tt.ticket`) are read by 3 `bireader.*` views loaded earlier by `views.pg.sql`; PostgreSQL refuses `ALTER COLUMN TYPE` while a view depends on the column (no CASCADE option exists), so the fix file `DROP VIEW`s all three first and recreates them verbatim (from `tables/views.pg.sql` lines 188, 195, 263) immediately after | ora2pg maps an unscaled Oracle `NUMBER` column to `bigint` when it infers the column is a sequence-backed surrogate primary key, but to plain unbounded `numeric` for a FOREIGN KEY column pointing at that same kind of id — even when both columns originate from the identical Oracle `NUMBER` declaration with no explicit precision. All 15 failures are this one pattern (`<x>_id numeric` → `id bigint`); confirmed by inspection, not a one-off | Fix the ora2pg type-inference configuration so FK columns get the same `bigint` inference as the PK they reference (the more correct, durable fix — this pattern likely recurs beyond the 5 pilot schemas, e.g. it already touched `nids.*`, outside the pilot), and regenerate. Until then, carry this fix file forward verbatim — it is small, explicit, and self-contained. |
| 4 | 1 reported syntax error (`ERROR: syntax error at or near "TABLE"`) in `constraints/check-constraints.pg.sql` line 18, which is actually 3 lost/merged CHECK constraints (see below) | `ALTER TABLE NIDS.MDR_SIGNATURE_GROUP_MEMBER ADD CONSTRAINT MDR_SIGNATURE_GROUP_MEMBER_C1 CHECK (...) OR` (line 15) has NO closing paren or semicolon — the next line begins a completely different, ALSO-truncated `ALTER TABLE PRX.PRX_POLICY_GROUP_ENTRY ADD CONSTRAINT ... CHECK (...) OR` (lines 16-17), and psql (correctly, per SQL statement parsing — `ON_ERROR_STOP` changes stop-on-failure behaviour, not statement boundaries) treats the unterminated text as ONE continuous statement running to the next `;` it finds, which belongs to a THIRD, otherwise-fine constraint (`STOP.COMPANY.SHORT_LOWERCASE`, line 18) — swallowing it into the same failure | `migration/test/schema-fixes/10_ora2pg_fixes.sql` reconstructs all 3 constraints from `ddl/generated/check-constraints.oracle.sql` lines 28-34 (the pre-conversion Oracle source, which has the complete, correctly-terminated text), stripping the trailing ` DEFERRABLE` clause — PostgreSQL does not support deferrable CHECK constraints (always immediate); confirmed correct because ora2pg strips this same suffix from every OTHER CHECK constraint in its own output (`grep -c DEFERRABLE constraints/check-constraints.pg.sql` → 0) | ora2pg's PostgreSQL export keeps the Oracle source's original line breaks for multi-line CHECK constraints but, for these two specific constraints, dropped the continuation/closing content and terminating semicolon entirely during conversion — a genuine ora2pg line-based-conversion bug, not a translation judgment call (every other multi-line CHECK constraint in the same source file, e.g. `APPID.PATH_OVERRIDE_MEMBER_LINK_CHK1`, `MSS.SPEED_TESTS.CHK_SPEED_TESTS_TARGET`, converts correctly) | File a fix upstream against this specific ora2pg conversion path (multi-line CHECK constraints with nested parens spanning >1 physical Oracle source line), then regenerate. Until then, carry this fix file forward — it is 3 constraints, verified byte-identical (minus DEFERRABLE) to the Oracle source. |

## Deliberately UNFIXED (out of the pilot's reach)

Per the plan's own instruction — "Tables outside the pilot's reach are allowed to remain
broken — record them, do not chase them" — these 4 `tables/views.pg.sql` errors are
recorded, not fixed:

| View | Error | Why left unfixed |
|------|-------|-------------------|
| `mc.v_...` (line 33, unnamed anonymous `SELECT` inside a larger view definition for `mc` connection-interrupt reporting) | `operator does not exist: interval > bigint` (comparing a computed `interval` against `host.escalation_timeout`, an integer column, with no cast) | `mc` schema, not one of the pilot's 5 (`auth mss tt mcaudit osag`). Requires understanding the intended comparison semantics (minutes vs. an interval), which is a real translation decision, not a mechanical fix — deferred to whichever later phase actually translates `mc`-schema views. |
| same view group (line 210) | `function trunc(interval) does not exist` — Oracle's `TRUNC()` on a date/interval expression has no direct PostgreSQL equivalent; needs `date_trunc()` or explicit `extract()` arithmetic depending on intent | Same `mc` view, same reasoning — a translation decision, not a mechanical fix. |
| `bireader.v_tt_service_window` (line 256) | `column "sys_nc00008$" does not exist` — an Oracle-generated hidden/virtual column (function-based-index artifact) that has no PostgreSQL counterpart; already flagged as a known issue in `.planning/research/CONCERNS.md` | This view is in the `bireader` reporting schema, not one of the pilot's 5, and the pilot's own tables/specs never reference `sys_nc00008$`. Ghost-column views are a known, pre-flagged category of breakage (CONCERNS.md), not new information from this plan. |
| `bireader.v_mv_value...` (line 411) | `relation "mss.mv_value_host_default" does not exist` — a materialized view defined in `ddl/migrated/mviews/mss.sql`, which this plan's `build-template.sh` does not load (materialized views were out of this plan's scope; see "Also out of scope" below) | Ordering/scope issue, not a data error — the view exists, just not yet, because `mviews/` isn't loaded by this plan. Loading `ddl/migrated/mviews/` is a reasonable Phase 5 task; not chased here since the pilot's own table dependency list never reaches this view. |

## Also out of scope for this plan (not errors, deliberate scope boundaries)

- **`tables/constraints.pg.sql` is not loaded at all.** It is a duplicate, NON-deferrable
  export of the identical 843 FK constraints found in `constraints/fk-constraints.pg.sql`
  (which IS marked `DEFERRABLE` throughout, and is what
  `fixtures/load_masterdata.py`'s `SET CONSTRAINTS ALL DEFERRED` strategy depends on).
  Loading both would produce 843 "constraint already exists" errors for zero benefit —
  same constraint names, same tables, same columns, just missing the `DEFERRABLE`
  keyword. Phase 5 should standardize on `constraints/fk-constraints.pg.sql` and drop
  `tables/constraints.pg.sql` from the ora2pg output entirely (or regenerate ora2pg
  config to stop emitting the duplicate).
- **`ddl/migrated/grants/`, `ddl/migrated/helpers/`, `ddl/migrated/mviews/` are not
  loaded.** Not required for the pilot's tables to exist and be queryable (this plan
  connects as the `postgres` superuser throughout, so role-based `GRANT`s are moot for
  test purposes), and not mentioned in this plan's scope. Left for Phase 5's full
  container build.

## Sequences ported (ora2pg gap, not an error — see `bootstrap/30_sequences.sql`)

`ddl/migrated/` ships **zero** `CREATE SEQUENCE` statements anywhere — every sequence
the schema needs lives only in `ddl/generated/sequences/*.sql` (30 files, Oracle
syntax). `bootstrap/30_sequences.sql` ports all **30 files / 309 sequences**, not just
the pilot's 12, since it's cheap and Phase 5 needs the rest anyway. The only Oracle-only
clause found across all 30 files was `ORDER` (Oracle RAC-wide monotonic-ordering
guarantee, no PostgreSQL equivalent, safely dropped — a single-instance sequence is
already monotonic); `START WITH n` (5 sequences use it) is valid, unmodified PostgreSQL
syntax. No `NOCACHE` / `NOCYCLE` / `MINVALUE` / `MAXVALUE` clauses were found anywhere in
the 30 files (verified by grep across the full set before writing the port).

## How the base load proves it isn't lying about success (T-02-09)

`ddl/migrated/tables/tables.pg.sql` and `ddl/migrated/tables/views.pg.sql` both open
with `\set ON_ERROR_STOP OFF` — loaded naively, either "succeeds" (`psql` exits 0) while
silently skipping every broken statement inside. `bootstrap/20_ddl.sh` defuses this two
ways, neither alone sufficient: (1) every `\set ON_ERROR_STOP` line is stripped from the
stream before it reaches `psql`, so a file's own directive can never re-disable the flag
set from outside mid-stream; (2) every `psql` invocation passes `-v ON_ERROR_STOP=on`
explicitly (`psql`'s own default, with no `-v` flag at all, is OFF).

`tables.pg.sql` is loaded STRICT (`ON_ERROR_STOP=on`, aborts the WHOLE build non-zero on
the first error) — after fixes #1-#2 above, it is expected and verified to load with
**zero** errors; if that ever regresses, the build stops hard instead of reporting a
green result over a broken table. The constraint/view files are loaded in INVENTORY mode
(every failure captured with its exact source line number) and the resulting failure set
is diffed against the hardcoded expected line numbers in `bootstrap/20_ddl.sh` — a match
is an explicitly reconciled, ledgered discrepancy (printed either way, in full, every
build), never a silently swallowed one. Any statement failing OUTSIDE the expected set
aborts the build non-zero.
