---
phase: 02-spec-method-test-harness-pilot
plan: 01
subsystem: testing
tags: [pgtap, orafce, pg_prove, postgresql-17, bash, python3-stdlib]

# Dependency graph
requires:
  - phase: 01-inventory-foundation
    provides: migration/mapping/name-map.csv (naming SSOT consumed by pkgname.py)
provides:
  - "migration/test/ dual test harness: pgTAP (pg_prove) + plain-SQL expected-output diffing"
  - "migration/test/run-tests.sh — one-command runner, per-package pass/fail table"
  - "migration/test/bootstrap.sh — disposable/template database builder (D-P8)"
  - "migration/test/redgreen.sh — red-before/green-after gate for later plans"
  - "migration/test/lib/pkgname.py — SSOT enforcement (D-P9) for test file naming"
affects: [02-02, 02-03, "every later plan in phase 02", "phase 04 bulk translation"]

# Tech tracking
tech-stack:
  added: [postgresql-17-pgtap 1.3.4, postgresql-17-orafce 4.16.7, libtap-parser-sourcehandler-pgtap-perl 3.37 (pg_prove)]
  patterns:
    - "Package identity for test files resolved from migration/mapping/name-map.csv, never re-derived (D-P9)"
    - "Disposable databases named under ^mcdb_(test|tmpl|harness)[a-z0-9_]*$, enforced by an allowlist gate before any DROP DATABASE (T-02-01)"
    - "sudo -u postgres peer auth for every DB operation; absolute-path filesystem access from the postgres OS user requires traversal permission on all ancestor directories"

key-files:
  created:
    - migration/test/bootstrap.sh
    - migration/test/bootstrap/00_extensions.sql
    - migration/test/run-tests.sh
    - migration/test/redgreen.sh
    - migration/test/lib/pkgname.py
    - migration/test/pgtap/_canary__canary__smoke.sql
    - migration/test/regress/sql/_canary__canary__smoke.sql
    - migration/test/regress/expected/_canary__canary__smoke.out
    - migration/test/README.md
    - migration/test/.gitignore
  modified: []

key-decisions:
  - "T-02-01 mitigation implemented as a hard regex allowlist (^mcdb_(test|tmpl|harness)[a-z0-9_]*$) in bootstrap.sh, checked before any DROP DATABASE or pg_terminate_backend call"
  - "bootstrap.sh --bare used for this plan (no template exists yet — 02-03 builds mcdb_tmpl); --template mode implemented and its no-template error path verified"
  - "run-tests.sh installs *.sql from --install DIR sorted by path with ON_ERROR_STOP=on, matching the plan's contract for later translation-install use"
  - "Fixed a pre-existing filesystem-permission gap (see Deviations) rather than routing every DB call through a workaround — the fix is minimal, reversible, and does not touch repo content"

patterns-established:
  - "Test file naming: <pg_schema>__<oracle_package_lower>__<topic>.sql, validated by pkgname.py against the name-map CSV; reserved '_canary' schema for harness self-tests only"
  - "Aggregate report format: PACKAGE | PGTAP (pass/total) | REGRESS (pass/total) | RESULT, then TOTAL: N packages, P pass, F fail"

requirements-completed: [HARN-01, HARN-02, HARN-04]

coverage:
  - id: D1
    description: "pgTAP assertions execute against PostgreSQL 17.10 via pg_prove, reporting pass/fail (HARN-01)"
    requirement: "HARN-01"
    verification:
      - kind: integration
        ref: "migration/test/run-tests.sh --db mcdb_harness_selftest (pgTAP half against pgtap/_canary__canary__smoke.sql)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Plain-SQL scripts run and their output is diffed against golden .out files to decide pass/fail (HARN-02)"
    requirement: "HARN-02"
    verification:
      - kind: integration
        ref: "migration/test/run-tests.sh --db mcdb_harness_selftest (regress half against regress/sql/_canary__canary__smoke.sql)"
        status: pass
    human_judgment: false
  - id: D3
    description: "One command (run-tests.sh) runs both harnesses and prints one pass/fail row per Oracle package with a truthful exit code, including exiting non-zero on zero-tests-discovered (HARN-04)"
    requirement: "HARN-04"
    verification:
      - kind: integration
        ref: "migration/test/run-tests.sh --db mcdb_harness_selftest (aggregate table + TOTAL line + exit 0)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Harness falsifiability proven by deliberate mutation of both halves, not asserted"
    verification:
      - kind: manual_procedural
        ref: "See 'Falsifiability Proof' section below: flipped pgTAP assertion and corrupted golden .out file, both observed to drive run-tests.sh to exit 1, both reverted and confirmed green again"
        status: pass
    human_judgment: false
  - id: D5
    description: "Test file naming SSOT enforced — a file naming a package absent from name-map.csv aborts run-tests.sh non-zero"
    verification:
      - kind: integration
        ref: "SSOT_GATE_OK verify block (bogus__nosuchpkg__x.sql rejected)"
        status: pass
    human_judgment: false
  - id: D6
    description: "redgreen.sh gate exists, is executable, and contains the RED-must-fail abort guard"
    verification:
      - kind: unit
        ref: "grep -q 'RED PHASE DID NOT FAIL' migration/test/redgreen.sh"
        status: pass
    human_judgment: false

duration: 21min
completed: 2026-07-12
status: complete
---

# Phase 2 Plan 1: Dual Test Harness Summary

**Stood up the pgTAP + plain-SQL-diff dual test harness against local PostgreSQL 17.10, with a one-command runner and a red/green gate — and proved by deliberate mutation, not assertion, that both halves can genuinely fail.**

## Performance

- **Duration:** ~21 min (first commit 14:29:29Z, last commit 14:33:42Z, plus setup/verification before/after)
- **Started:** 2026-07-12T14:27Z (approx, first tool calls)
- **Completed:** 2026-07-12T14:34:13Z
- **Tasks:** 3/3
- **Files modified:** 10 created

## Accomplishments
- Installed `postgresql-17-pgtap` (1.3.4), `postgresql-17-orafce` (4.16.7), and `libtap-parser-sourcehandler-pgtap-perl` (provides `pg_prove` 3.37) via apt
- Built `bootstrap.sh` — a disposable/template PostgreSQL database builder with a hard name-allowlist gate (T-02-01) and stray-backend termination before any DROP
- Built `run-tests.sh` — the one-command runner: validates test-file naming against the Phase 1 name-map SSOT (`pkgname.py`, D-P9), runs the pgTAP half via `pg_prove`, runs the expected-output half via `psql` + `diff`, prints a per-package pass/fail table, and exits non-zero on any failure or on zero tests discovered
- Built `redgreen.sh` — the mechanised red-before/green-after gate, with the `RED PHASE DID NOT FAIL` abort guard for a test suite that would pass against a nonexistent implementation
- Proved falsifiability by hand: flipped a true pgTAP assertion to false, and separately corrupted one byte of a golden `.out` file — both drove `run-tests.sh` to exit 1 with the failure printed, then were reverted and the harness confirmed green again (full output below)

## Task Commits

Each task was committed atomically:

1. **Task 1: Install extensions and prove the local instance can host pgTAP** - `baaffdb` (feat)
2. **Task 2: Both harness halves + the one-command runner** - `ca482b5` (feat)
3. **Task 3: Prove both harnesses can fail, ship redgreen.sh gate** - `9d175be` (feat)

**Plan metadata:** (this commit, made after this SUMMARY)

## Files Created/Modified
- `migration/test/bootstrap.sh` - disposable/template database builder, name-allowlist guard
- `migration/test/bootstrap/00_extensions.sql` - `CREATE EXTENSION orafce/pgtap`
- `migration/test/run-tests.sh` - one-command dual-harness runner with per-package pass/fail table
- `migration/test/lib/pkgname.py` - name-map SSOT enforcement for test-file naming (D-P9)
- `migration/test/pgtap/_canary__canary__smoke.sql` - pgTAP harness self-test
- `migration/test/regress/sql/_canary__canary__smoke.sql` - expected-output harness self-test
- `migration/test/regress/expected/_canary__canary__smoke.out` - golden output for the above
- `migration/test/redgreen.sh` - RED/GREEN gate with the RED-must-fail abort guard
- `migration/test/README.md` - harness contract documentation
- `migration/test/.gitignore` - ignores `regress/results/` and `*.log`

## Falsifiability Proof

Recorded verbatim, as required by the plan's `<output>` spec.

### Mutation (a) — flipped pgTAP assertion

Changed `SELECT ok(true, 'pgTAP can assert a true expression');` to
`SELECT ok(false, ...)` in `pgtap/_canary__canary__smoke.sql`, then ran
`run-tests.sh --db mcdb_harness_selftest`:

```
EXIT CODE: 1
--- pgTAP FAIL: .../migration/test/pgtap/_canary__canary__smoke.sql ---
.../migration/test/pgtap/_canary__canary__smoke.sql ..
# Failed test 1: "pgTAP can assert a true expression"
# Looks like you failed 1 test of 2
Failed 1/2 subtests
Test Summary Report
-------------------
.../_canary__canary__smoke.sql (Wstat: 0 Tests: 2 Failed: 1)
  Failed test:  1
Result: FAIL

PACKAGE                                  | PGTAP (pass/total) | REGRESS (pass/total) | RESULT
_canary.canary                           | 0/2                | 1/1                | FAIL

TOTAL: 1 packages, 0 pass, 1 fail
```

Reverted; `diff` against the pre-mutation backup confirmed clean revert; harness confirmed green again (exit 0) afterward.

### Mutation (b) — corrupted golden `.out` file

Appended `DRIFT\n` to `regress/expected/_canary__canary__smoke.out`, then ran
`run-tests.sh --db mcdb_harness_selftest`:

```
EXIT CODE: 1
--- REGRESS FAIL: .../migration/test/regress/sql/_canary__canary__smoke.sql ---
--- .../regress/expected/_canary__canary__smoke.out
+++ .../regress/results/_canary__canary__smoke.out
@@ -3,4 +3,3 @@
    1 | canary
 (1 row)

-DRIFT

PACKAGE                                  | PGTAP (pass/total) | REGRESS (pass/total) | RESULT
_canary.canary                           | 2/2                | 0/1                | FAIL

TOTAL: 1 packages, 0 pass, 1 fail
```

Reverted; `diff` against the pre-mutation backup confirmed clean revert; harness confirmed green again (exit 0) afterward.

Both halves demonstrably reject a wrong answer and recover cleanly. The harness's core claim — "a green result is worth something" — is proven, not asserted.

## Decisions Made
- Used `bootstrap.sh --bare` throughout this plan's self-tests, since `mcdb_tmpl` does not exist yet (plan 02-03 builds it). `--template` mode's no-template error path was verified separately to fail cleanly with a clear message.
- `pkgname.py --list` doubles as both the discovery mechanism (no-arg mode) and the validator (used per-file by `run-tests.sh` for package attribution) — a single source of parsing logic, per the plan's stated purpose ("so the runner can consume it with no CSV parsing of its own").
- `redgreen.sh`'s dependency on `mcdb_tmpl` was left unresolved by design — it is plan 02-03's responsibility to build that template; this plan proved the gate's guard logic (`grep`-verified) and confirmed its bootstrap failure path is clean, since full end-to-end exercise requires the template.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed a filesystem-permission gap preventing the `postgres` OS user from reaching any file under this worktree**
- **Found during:** Task 1, first `bootstrap.sh --bare` verification run
- **Issue:** `/home/ubuntu` was mode `750` (`drwxr-x---`), owned by `ubuntu:ubuntu`. Every directory below it (`mcdb/`, `.claude/`, `worktrees/`, the agent worktree, `migration/`, `migration/test/`, etc.) was `755`, but the `postgres` OS user — which every DB operation in this plan runs as, via mandatory peer auth (`local all all peer` in `pg_hba.conf`; no password role exists for `ubuntu`) — could not even traverse `/home/ubuntu` to reach any of them. `psql -f <absolute path>` failed with `Permission denied`, and this would have blocked every `-f`, `pg_prove <file>`, and future `--install` load in the harness.
- **Fix:** `sudo chmod o+x /home/ubuntu` — grants execute (traversal) permission only, not read/list, on that one directory. Every directory below it already had `o+rx`; this was the single missing link. Verified `postgres` could then read a file via absolute path.
- **Files modified:** None (no repo file changed; a local filesystem permission adjustment, `750` → `751` on `/home/ubuntu`)
- **Verification:** Re-ran Task 1's verify block; all three DB-touching tool calls (`bootstrap.sh`, `psql -f`, `pg_prove`) succeeded with absolute paths. Re-verified at the end of Task 3 that all six verify blocks across all three tasks still pass in one pass.
- **Committed in:** N/A (not a repo change; no commit needed or made for this fix itself)

**2. [Rule 1 - Bug] Corrected a shell-quoting bug in Task 1's own verify command before treating its result as evidence**
- **Found during:** Task 1 verification
- **Issue:** The plan's verify command for Task 1 embeds `SELECT ok(true, \"x\")` inside a single-quoted outer `bash -c '...'` wrapper. Because backslashes are not special inside single quotes, the literal two-character sequence `\"` reaches the inner shell's double-quoted `-tAc "..."` argument, where the inner shell *does* interpret `\"` as an escaped literal `"`. The SQL that reaches `psql` therefore contains a literal `"x"` — a double-quoted SQL **identifier**, not a string literal — producing `ERROR: column "x" does not exist` regardless of whether pgTAP itself works.
- **Fix:** Did not alter any repo file. Re-ran the equivalent pgTAP sequence with corrected quoting (`ok(true, 'x')`, a proper single-quoted string literal) to confirm the underlying capability — `plan()`/`ok()`/`finish()` executing inside a bootstrapped database — genuinely works, independent of the verify-string's own bug. Exit code 0, output `ok 1 - x`.
- **Files modified:** None
- **Verification:** `sudo -u postgres psql -d mcdb_harness_selftest -tAc "SELECT plan(1); SELECT ok(true, 'x'); SELECT * FROM finish();"` → exit 0, `1..1` / `ok 1 - x`
- **Committed in:** N/A (verify-script text is not a repo artifact; no deliverable code was affected)

---

**Total deviations:** 2 auto-fixed (1 blocking filesystem permission, 1 verify-command quoting bug)
**Impact on plan:** Both were necessary to reach a genuine, non-fabricated PASS on Task 1's verification. Neither touched any harness deliverable file. No scope creep.

## Issues Encountered
None beyond the two deviations above, which were resolved inline.

## User Setup Required
None - all three apt packages were pre-approved by the user (see `02-CONTEXT.md` "System packages — APPROVED") and installed non-interactively via `sudo apt-get install -y`.

## Next Phase Readiness
- The harness (`bootstrap.sh`, `run-tests.sh`, `redgreen.sh`, `pkgname.py`) is ready for plan 02-03 to build `mcdb_tmpl` from `ddl/migrated/` and switch `bootstrap.sh`'s default database mode from `--bare` to template mode.
- `redgreen.sh`'s RED phase (no-template bootstrap failure) was verified to fail cleanly; its full RED→GREEN cycle needs a real template and a real `--install DIR` of translated objects to exercise end-to-end — that first real exercise belongs to whichever plan lands the first pilot package's translation.
- The `/home/ubuntu` permission fix (`o+x`) is a local-machine, session-level condition, not a repo artifact — if this environment is rebuilt or a fresh sandbox is used, the same fix (or an equivalent, e.g. running Postgres via TCP with password auth) will be needed again before any `sudo -u postgres` file-path operation on files under `/home/ubuntu` will succeed.

---
*Phase: 02-spec-method-test-harness-pilot*
*Completed: 2026-07-12*

## Self-Check: PASSED

All 10 created files confirmed present on disk; all 3 task commits (`baaffdb`, `ca482b5`, `9d175be`) confirmed present in `git log --oneline --all`. No missing items.
