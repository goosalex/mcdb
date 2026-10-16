# TICKETEVOLUTION.CALCULATOR -- FINDINGS

**Source:** `ddl/src/pkg/ticketevolution_calculator.sql` (spec, 14 lines),
`ddl/src/pkgb/ticketevolution_calculator.sql` (body, 214 lines). **Spec:**
`migration/spec/ticketevolution.calculator.md` (20 clauses, prefix TICKEV). **Target:**
`migration/pgsql/ticketevolution/calculator.sql`. **Tests:**
`migration/test/pgtap/ticketevolution__calculator__spec.sql` (62 assertions),
`migration/test/regress/sql/ticketevolution__calculator__txn.sql` (+ golden).

## Deviations from Oracle

Both are marked `-- DEVIATION(ORACLE-BUG):` at the site in `calculator.sql`, stated as
corrected behaviour in the spec, and asserted by tests that FAIL against a literal port
(mutation evidence below).

| # | Site (Oracle) | Oracle behaviour | Corrected behaviour | Spec clause |
|---|---|---|---|---|
| 1 | `ddl/src/pkgb/ticketevolution_calculator.sql:114` `e.eventdate < date_from + 60` | Oracle DATE arithmetic: `+ 60` is **60 days**. An emergency flag raised on a still-new ticket up to 60 days after the row started is folded into the existing row; the `SQL%ROWCOUNT = 0` branch (line 115-119) is dead in practice. | `date_from + interval '60 seconds'`, per the inline comment at line 109 ("60s margin for setting emergency flag on a new ticket"): a flag within 60 s of the row's start is folded in place; later flags emit their own `'emergency'` row. | S-TICKEV-011 |
| 2 | `ddl/src/pkgb/ticketevolution_calculator.sql:170-174` chaining `UPDATE ... WHERE event_id = v_last_event_id` | The pseudo `'new'` row (lines 162-166) shares the first event's `event_id`, so the next emitted event's chaining update stretches BOTH rows' `date_to`: `'new'` [T1,T2] and e.g. `'open'` [T1,T2] overlap, contradicting the explicit `date_to = e.DB_DATE` the same code assigns to the pseudo-row at line 165 and the contiguous-chain invariant every other row obeys. | The chaining update additionally requires `ticket_status IS NOT DISTINCT FROM v_last_status`, i.e. it targets the row actually emitted last; the pseudo-row (status `'new'`, guaranteed `!= v_last_status` by the insert condition at line 162) keeps `date_from = date_to = T1`. `tickev` has no PK, so the status is the only discriminator available without a schema change. | S-TICKEV-009 |

**Why these are bugs and not design:** both contradict a statement of intent in the same
source (the comment at line 109; the explicit `date_to` at line 165). Neither can be
confirmed against live Oracle data (none available); the spec's Assumptions section
records what such data would show if the Oracle behaviour had in fact been relied upon.

**Mutation evidence (run live on `mcdb_test_tickev`, not committed):**

- Replacing `interval '60 seconds'` with `interval '60 days'` (the literal Oracle semantics):
  `Failed 3/62 subtests`, tests 56-58 (all three S-TICKEV-011 assertions on ticket C).
- Removing the `IS NOT DISTINCT FROM v_last_status` predicate (literal Oracle chaining):
  `Failed 2/62 subtests`, tests 6 (the 13-row `results_eq`) and 10 (pseudo-row `date_to`).

## NOT deviations (faithful translations worth calling out)

- **Oracle `''` → `NULL`** (S-TICKEV-016). `v_eng := ''`, `v_label := ''`, `v_eng := ''` after an
  `'MCC'` token, and the `''` literal in the pseudo-row insert are all NULL in Oracle; the
  translation writes `NULL` explicitly so `assigned_engineer`/`ticket_label` are SQL NULL,
  exactly what Oracle stores. Three assertions pin "NULL, never empty string".
- **First type-change rewrites ALL earlier live rows** (S-TICKEV-015, Oracle line 153).
  Intended per the inline comment ("update existing tickev records") — the rows were seeded
  with the ticket's CURRENT type and the event is the first evidence of the prior type. Kept.
- **`v_status != v_last_status` NULL-unsafety** (Oracle line 79). Traced: `v_last_status` is
  NULL only before the first emitted row (where `v_out` is already 1 from initialisation,
  so the comparison's result is irrelevant) or after a row with NULL status, which needs a
  `details_public` of exactly `'New status: '`. Identical in both engines; kept as `!=`.
- **`v_eng = 'MCC'` with NULL `v_eng`**: not true in both engines; kept.
- **Same-second watermark race** (S-TICKEV-020): a ticket updated in the same whole second
  as `v_this_run`, after the loop's query ran, is missed by the next run in Oracle (its
  truncated `update_timestamp` equals, does not exceed, the watermark). Kept — the brief
  asks to preserve the DATE-truncation semantics; flagged as an open question below.

## Oracle → PostgreSQL mechanics

| Oracle | PostgreSQL | Note |
|---|---|---|
| `REGEXP_SUBSTR(x, '^New status: (.+)$', 1, 1, 'm', 1)` | `(regexp_match(x, '^New status: (.+)$', 'n'))[1]` | Oracle `'m'`: `^`/`$` at line boundaries, `.` does not cross a newline (Oracle default). PostgreSQL `'n'` (newline-sensitive) is exactly that pair; `'m'` in PostgreSQL is only a synonym for `'n'` too, but `'n'` is the documented primary spelling. Verified live: `E'New status: open\nsecond line'` → `open` with `'n'`, `open\nsecond line` without. |
| `REGEXP_SUBSTR(x, pat, 1, 1, '', n)` | `(regexp_match(x, pat))[n]` | Default flags; all five patterns verified live against the spec's example strings (`jho`/`non-MCC`, `MCC`, `Dispatch`, `SOC`, `third party incident`/`incident`, no-match → NULL). |
| `SQL%ROWCOUNT` | `GET DIAGNOSTICS v_rows = ROW_COUNT` | |
| `SYSDATE` | `statement_timestamp()` | Project convention. Inside `materialize_incremental`, `statement_timestamp()` stays at the `CALL`'s start across the per-ticket COMMITs, so every `update_dt` of one run carries the run's start time; Oracle's `SYSDATE` would advance. `update_dt` is informational only; no clause depends on it. |
| `sysdate - 365` | `date_trunc('second', statement_timestamp()) - interval '365 days'` | |
| `CAST(update_timestamp AS DATE) > v_last_run` | `date_trunc('second', t.update_timestamp) > v_last_run` | Oracle's cast keeps time-of-day and drops fractional seconds (truncation). PostgreSQL would ROUND on assignment to `timestamp(0)`, so `v_this_run`/`v_last_run` are truncated explicitly — a rounded-up watermark could sit in the future and hide a ticket. |
| `tickev`, `state` (unqualified) | `ticketevolution.tickev`, `ticketevolution.state` | Package owner schema. |
| `COMMIT` inside `WHEN NO_DATA_FOUND` (line 199) | flag set in the handler; insert + `COMMIT` after the block | PL/pgSQL forbids `COMMIT` inside a block with an `EXCEPTION` clause. Same observable sequence (insert, commit, then loop). |
| `COMMIT` inside the cursor `FOR` loop (line 206) | same | PL/pgSQL converts the loop cursor to a holdable cursor on the first `COMMIT`; the ticket set is fixed when the query starts, as in Oracle. |

## `pg_kind` verdict: correct for both routines

Both declared `PROCEDURE` in Oracle (`ddl/src/pkg/ticketevolution_calculator.sql:7,13`),
`pg_kind=procedure` in `name-map.csv`, created as `prokind='p'` (asserted by tests 1-2).
`materialize_tickev` never commits and is callable from anywhere (the pgTAP suite calls it
inside its wrapping transaction). `materialize_incremental` carries three real `COMMIT`s
(Oracle lines 199, 206, 210) — **option 1, same decision as `tt.util_close_old_dev_tickets`**:
plain PROCEDURE, real COMMITs, top-level `CALL` only. Its only caller is the hourly
`DBMS_SCHEDULER` job (`ddl/src/jobs/ticketevolution_incremental_update.sql:7`, PL/SQL block
`BEGIN ticketevolution.CALCULATOR.materialize_incremental; END;`), which IS a top-level
call. No `ROLLBACK`, no `PRAGMA AUTONOMOUS_TRANSACTION`, so unlike `tt.util` there is no
isolation delta to accept — the only consequence is the usual one: it cannot be `CALL`ed
from a FUNCTION or from inside a transaction the caller intends to roll back. The job
itself is not translated here (XCUT-03 / scheduler replacement is out of scope).

## AuditUsage deletion count

**0 of 0** — this package has no `plog` calls of any kind (confirmed by
`grep -ci plog ddl/src/pkgb/ticketevolution_calculator.sql` → 0).

## SELECT INTO strictness (both sites, matching the spec)

- Line 32 (type name): `INTO STRICT`, no handler — unhandled `P0002` propagates (tests 3-4:
  nonexistent ticket, NULL `type_id`). No message-parity shim needed: the tests pin the
  SQLSTATE, not the text.
- Line 194 (watermark): `INTO STRICT` with `WHEN NO_DATA_FOUND` mirroring Oracle's; a second
  `LAST_RUN` row raises `P0003` unhandled, as Oracle's `TOO_MANY_ROWS` would.

## Red/green status (verified live on `mcdb_test_tickev`, bootstrapped from `mcdb_tmpl`)

- **RED** (`run-tests.sh --db mcdb_test_tickev --package ticketevolution.calculator`, nothing
  installed): pgTAP **9/62**, regress **0/1**, exit 1 — `procedure
  ticketevolution.calculator_materialize_tickev(integer) does not exist`. The 9 vacuous
  passes are the `NOT EXISTS` / `IS NULL` / `count = 0` checks that hold on an empty
  `tickev` (same class as the 6 vacuous `tt.ticket_interface` passes documented in
  `migration/test/REDGREEN-EVIDENCE.md`); every assertion that touches a routine is red.
- **GREEN** (`--install migration/pgsql`): pgTAP **62/62**, regress **1/1**, exit 0 — after
  one test-only amendment (A-009, `migration/spec/TEST-AMENDMENTS.md`: an ORDER BY tie-break
  that sorted `'merged'` before `'new'`; committed before the translation, touching only the
  test file).
- `grep -nEi "dbms_|utl_|auditusage|dblink|pg_background"` over `calculator.sql`: zero matches.

## Open questions

1. **Status text spelling** in `details_public` vs `tt.status.name` (e.g. `waiting for
   signoff` vs `waiting for sign-off`) decides whether `ticket_status_id` resolves; unknown
   without application code or live data. Translation preserves the exact-match lookup.
2. **Same-second watermark race** (above). A `>=` comparison or a `v_this_run` taken AFTER
   the loop's query would close it, but both change which tickets are reprocessed; left
   as Oracle has it pending a product decision.
3. **Scheduler**: the hourly job that is this package's only caller needs a PostgreSQL
   scheduler (pg_cron or external) issuing a top-level `CALL
   ticketevolution.calculator_materialize_incremental()`; not part of this translation.
4. `ticketevolution.state` has no key constraint; a unique index on `key` would turn the
   theoretical `TOO_MANY_ROWS` into an impossibility. Schema change, not made here.
