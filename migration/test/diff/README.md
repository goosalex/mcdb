# migration/test/diff/ -- Oracle vs PostgreSQL differential harness

The DIFFERENTIAL half of the test harness (phase 06, plan 06-05). `../run-tests.sh`
verifies the PostgreSQL translations against specifications derived from the Oracle
source by static analysis. This directory adds the other kind of evidence: **run the same
scenario against a real Oracle database (the MCDB Oracle container) and against the
PostgreSQL translations, normalise both outputs, diff them.** "Oracle says X,
PostgreSQL says X" -- or, more valuably, "Oracle says X, PostgreSQL says Y".

```
migration/test/diff/
├── run-diff.sh            the one command (per-scenario PASS/KNOWN/DIFF table, exit code)
├── compose.py             builds the one-shot SQL*Plus / psql script of a scenario
├── normalize.py           makes the two captures comparable (rules R1-R11, see its docstring)
├── derive_pg_call.sh      HELPER: drafts call.pg.sql from call.ora.sql (review required)
├── scenarios/
│   └── <pg_schema>__<oracle_package_lower>__<topic>/
│       ├── meta.env               ORA_USER=, COMMITS=no|yes, COMPARE_MSG=no|yes, DESCRIPTION=
│       ├── setup.sql              dialect-neutral fixtures (setup.ora.sql / setup.pg.sql override)
│       ├── call.ora.sql           the invocations, PL/SQL anonymous block(s) ending in `/`
│       ├── call.pg.sql            the same invocations, DO $$ ... $$; (+ pg_temp.* helpers)
│       ├── probe.sql              dialect-neutral SELECTs producing the rows to compare
│       ├── cleanup.ora.sql        COMMITS=yes only: best-effort undo of committed rows
│       └── known.diff             optional: an accepted, documented difference
├── tests/
│   ├── test_normalize.py          unit tests for every normalisation rule + the composer
│   ├── pg2synthetic.py            re-dresses a psql capture in SQL*Plus shape (self-test only)
│   └── fixtures/synthetic-ora-capture/   SYNTHETIC captures for the harness self-test
├── .work/                 (gitignored) per-scenario ora.sql/ora.raw/pg.sql/pg.raw/*.norm/diff.txt
└── captures/              (gitignored) suggested place for --ora-capture / --pg-capture output
```

Scenario directories are named exactly like test files minus `.sql`; `../lib/pkgname.py`
validates the `(pg_schema, oracle_package)` pair against `migration/mapping/name-map.csv`
before anything runs (D-P9: nobody invents a package name outside the SSOT).

## How it works

Per scenario, per side, ONE script is composed (`compose.py`) and run in ONE session:

```
probe table  ->  SET CONSTRAINTS ALL DEFERRED  ->  setup  ->  call  ->  probes  ->  ROLLBACK
```

* **Probe table.** Every call in `call.*.sql` is wrapped so that an exception becomes DATA:
  the wrapper inserts `(step, code, msg)` into `diff_probe(step VARCHAR(100), code
  VARCHAR(20), msg VARCHAR(4000), n NUMBER, s VARCHAR(4000))`. Successful calls insert
  their result into `n` (numeric) / `s` (text). The harness creates the table on both sides
  before the scenario's own statements: on Oracle a **GLOBAL TEMPORARY TABLE** in the
  connecting user's schema (CREATE TABLE is a committing DDL in Oracle, so it is created
  *before* the transaction starts and dropped after the ROLLBACK; its rows are
  session-private and transactional), on PostgreSQL a `TEMP TABLE ... ON COMMIT DROP`.
* **Oracle side.** `docker exec -i <container> sqlplus -s /nolog`, the script fed on stdin
  with a leading `CONNECT user/password@localhost:1521/XEPDB1` (so the password is not on a
  command line inside the container). `SET MARKUP CSV ON`, `FEEDBACK OFF`, `NUMWIDTH 40`
  (20-digit IPv6 halves must not become `1.7E+19`), `SQLBLANKLINES ON`, `DEFINE OFF`,
  `WHENEVER SQLERROR CONTINUE`, NLS formats `YYYY-MM-DD HH24:MI:SS`(`.FF6`) and
  `NLS_NUMERIC_CHARACTERS='.,'`. The container is used **read-only**: this script never
  starts, stops, builds or tags a container, and every scenario ends with `ROLLBACK` +
  `EXIT ROLLBACK`.
* **PostgreSQL side.** `bash migration/db/pg.sh psql --csv -X -q -v ON_ERROR_STOP=0 -f
  <script>` against a fresh clone of `mcdb_tmpl` (`../bootstrap.sh --db mcdb_test_diff
  --template mcdb_tmpl`, then every `*.sql` under `migration/pgsql` installed in path
  order, exactly as `../run-tests.sh --install` does). `\set ON_ERROR_ROLLBACK on` gives
  psql Oracle's statement-level atomicity (a failing statement does not poison the
  transaction), `SET datestyle='ISO, YMD'`, `SET timezone='UTC'` (see Timezone). `pg.sh`
  attaches no stdin, so the composed script is written under `.work/` (inside the repo,
  which the container mounts) and passed with `-f`.
* **Probes.** `probe.sql` is split into statements (a line ending in `;` ends one); before
  each the composer emits a marker (`PROMPT ## probe N label` / `\echo ## probe N label`) so
  the normaliser can section the stream. A comment `-- probe: <label>` right before a
  statement names its section. Probes should ORDER BY (determinism) and alias every
  expression (SQL*Plus prints the expression text as header otherwise).
* **Normalisation** (`normalize.py`, rules R1-R11, each unit-tested): lower-cased headers;
  trailing spaces (Oracle CHAR padding) and CR stripped; NULL and `''` both empty (Oracle
  has no empty string -- encode the distinction as data if a scenario needs it); canonical
  numbers (`12.0`->`12`, `-0`->`0`, `.5`->`0.5`, scientific notation expanded,
  `256.0000000000000000`->`256`); boolean columns (`t/f/true/false` only) -> `1/0`; a column
  named `code`/`*_code` mapped through the SQLSTATE table (below); a column named
  `msg`/`*_msg` blanked unless `COMPARE_MSG=yes`; zero-row probes reduce to their marker on
  both sides (SQL*Plus prints nothing, psql a bare header); embedded newlines rendered as
  `\n`; **rows sorted within a section** (the template collates `en_US.utf8`, Oracle sorts
  BINARY -- row order is not part of the contract; expose order as data if it matters);
  `--` comment lines dropped (only fixtures contain them). Anything that is not a CSV
  record of its section (ORA- lines, `ERROR at line`, `psql:...: ERROR:`) is kept as a
  `! ...` noise line so a failure on either side shows up in the diff instead of
  vanishing.
* **Diff.** `diff -u ora.norm pg.norm`; the table prints one row per scenario; exit code 0
  only if every scenario is PASS or KNOWN *and* at least one scenario had Oracle data.

### Error-code mapping (R6)

Derived from `migration/mapping/sqlstate-map.md`; `normalize.py --self-check` prints it.

| Oracle | canonical token | note |
|---|---|---|
| ORA-01403 | `P0002` | NO_DATA_FOUND |
| ORA-01422 | `P0003` | TOO_MANY_ROWS |
| ORA-00001 | `23505` | DUP_VAL_ON_INDEX |
| ORA-01400 / 01407 | `23502` | NOT NULL violation |
| ORA-02291 / 02292 | `23503` | FK violation |
| ORA-06502, ORA-01722, and PG 22023 / 22P02 / 22003 / 22001 | `VALUE_ERROR` | Oracle does not distinguish the PG class-22 codes (sqlstate-map rule 1), so both sides collapse onto one token |
| ORA-01476 | `22012` | division by zero |
| ORA-06510 | `P0001` | unhandled user-defined exception / RAISE EXCEPTION default |
| ORA-20NNN | `OSNNN` | sqlstate-map rule 3 (`-20980` -> `OS980`) |
| anything else | unchanged | an unmapped code is meant to show in the diff |

### Result codes

| RESULT | meaning |
|---|---|
| `PASS` | normalised outputs identical |
| `KNOWN` | they differ and the difference equals the scenario's `known.diff` (an accepted, documented deviation such as a `DEVIATION(ORACLE-BUG)`); counts as pass |
| `STALE-KNOWN` | `known.diff` exists but the sides agree -> the file is stale; fails |
| `DIFF` | they differ; the diff is printed (`- oracle`, `+ postgresql`) |
| `NO-ORACLE` | no Oracle data for the scenario (container not running, or no capture for it under `--ora-from`); the PostgreSQL side still ran |
| `ERROR` | a side produced no probe output at all (connect failure, compose error) |

`known.diff` is the `+`/`-` body of the unified diff (`.work/<scenario>/diff.body` after a
DIFF run); copy it into the scenario only after understanding every line, and cite the
FINDINGS/spec clause in `meta.env`'s comments.

## Running

```bash
# live, all scenarios (Oracle container mcdb-ora must be RUNNING; the script never starts it)
bash migration/test/diff/run-diff.sh --all --ora-capture migration/test/diff/captures/$(date +%F)

# one scenario, verbose work files kept
bash migration/test/diff/run-diff.sh --scenario tt__ticket_interface__status_lifecycle --keep

# offline: PostgreSQL side against a captured Oracle run
bash migration/test/diff/run-diff.sh --all --ora-from migration/test/diff/captures/2026-10-21

# harness self-test (synthetic capture, see Falsifiability)
bash migration/test/diff/run-diff.sh --all --ora-from migration/test/diff/tests/fixtures/synthetic-ora-capture
python3 -m unittest discover -s migration/test/diff/tests -v
```

Options: `--ora-container NAME` (default `$MCDB_ORA_CONTAINER` or `mcdb-ora`), `--ora-user
USER` (overrides every scenario's `ORA_USER`; password `$MCDB_ORA_PASSWORD`, default
`password`), `--ora-service` (default `XEPDB1`), `--pg-db NAME` (default `mcdb_test_diff`;
must match `^mcdb_(test|tmpl|harness)[a-z0-9_]*$`), `--pg-timezone TZ`, `--install DIR` /
`--no-install` (reuse the prepared database), `--keep`, `--ora-capture DIR`, `--ora-from
DIR`, `--pg-capture DIR`.

### Live preflight

In live mode the script first runs a preflight as `tt` and records
`.work/oracle.env` (copied into `--ora-capture DIR`): `ORA_VERSION`,
`ORA_SESSIONTIMEZONE`, `ORA_DBTIMEZONE`, `ORA_SYSTIMESTAMP_TZ`, `ORA_SYSDATE`, and the
status of the `TT.TICKET_INTERFACE` and `MSS.OSAG_IP` package bodies -- so a capture always
says which Oracle, in which timezone, with valid or invalid packages, produced it.

### Timezone

The Oracle container (`gvenzl/oracle-free`, `docker inspect mcdb-ora`) sets no `TZ`, so the
server's OS clock is UTC and `SYSDATE`/`SYSTIMESTAMP` are UTC (`ORA_SYSTIMESTAMP_TZ=+00:00`
expected in the preflight). The PostgreSQL template is also `Etc/UTC`. The PostgreSQL
session therefore runs with `SET timezone = 'UTC'` by default -- NOT `Europe/Zurich` as
first planned: the point is to give both engines the same wall clock, and the Oracle code
that cares about Zurich says so explicitly (`from_tz(..., 'EUROPE/ZURICH')` in
`change_status_event_id_out`). If the preflight reports another offset, the script warns
and `--pg-timezone` sets the matching zone. Scenarios still avoid comparing absolute
timestamps (probes use `CASE WHEN d IS NOT NULL THEN 1 ELSE 0 END` flags).

### Which Oracle user

`meta.env`'s `ORA_USER` is the schema user whose privileges the scenario needs
(`tt`, `mss`, ...; all container schema users share the password `password`). The
lifecycle scenario connects as `system`: its fixtures insert into `stop.company`,
`stop.contact` and `mss.host`, and `TT` holds only `SELECT`/`REFERENCES` on those tables
(`ddl/generated/grants`). The routines are definer-rights package procedures and every
call is schema-qualified, so the caller's identity does not change what they do.

## Limitations (read before trusting a result)

1. **Oracle is left untouched only by ROLLBACK.** Everything runs in one transaction that
   is rolled back; the GTT is dropped afterwards. What survives on Oracle regardless:
   rows written through `OSAG.OSAG_PLOG`'s `PRAGMA AUTONOMOUS_TRANSACTION` (every TT
   routine calls `plog.AuditUsage`), and anything a routine does through autonomous
   transactions or external calls (mail). Scenarios with `COMMITS=yes` (a routine that
   commits internally) are run on a fresh PostgreSQL clone without a transaction block
   (a PL/pgSQL procedure may COMMIT only outside one) and are followed on Oracle by the
   author's `cleanup.ora.sql`, best effort -- a failed cleanup leaves rows in Oracle. No
   pilot scenario commits; that branch of the composer is implemented but unexercised.
2. **Deferred constraints.** `SET CONSTRAINTS ALL DEFERRED` is issued on both sides
   (`DEFER_CONSTRAINTS=no` in meta.env turns it off). Every FK in
   `ddl/generated/constraints.oracle.sql` is `DEFERRABLE`, so fixtures may be sparse; but a
   constraint violation that would surface at COMMIT is never seen (there is no COMMIT).
3. **NULL vs empty string, booleans, row order** are deliberately collapsed (R3, R5, R10);
   encode them as data when they are the subject of a scenario.
4. **Messages are not compared** by default (R7); the code is the contract. `COMPARE_MSG=yes`
   compares them verbatim after R2 -- expect differences for engine-generated texts.
5. **The replay mode compares against whatever the capture contains.** A capture is only
   Oracle evidence if `oracle.env` in it was written by the live preflight. The
   `tests/fixtures/synthetic-ora-capture/` files are NOT (see below).
6. **`derive_pg_call.sh` is a helper, not a translator.** It applies
   `migration/mapping/client-rename.sed` exactly as that file's header prescribes (`sed -E
   -f`), prefixes `CALL` to procedures listed in `client-rename-map.csv`, converts the
   outer `DECLARE`/`BEGIN ... END; /` to `DO $$ ... $$;` and rewrites `SYSDATE`, `FROM
   DUAL`, `seq.NEXTVAL`, `SQLCODE`, `VARCHAR2`, `SUBSTR`, `NVL`, `CHR(10)`. Tried on
   `tt__ticket_interface__status_lifecycle/call.ora.sql`: the three-part calls came out as
   `CALL tt.ticket_interface_change_status(...)`, the block as `DO $$ DECLARE ... $$;` --
   and the nested PL/SQL procedures came out unchanged, which PL/pgSQL does not have. The
   committed `call.pg.sql` files were written by hand (nested procedures became `pg_temp.*`
   functions driven by a `DO` block with `PERFORM`); the helper saved the renaming.

## Falsifiability

A green result is only meaningful because the harness has been seen rejecting a wrong
answer. Two things were done on 2026-10-20, while **no Oracle container was running**
(the owner was rebuilding `mcdb-ora` on this box; `docker ps` was re-checked throughout
and the container was `Exited` every time -- so nothing below is Oracle evidence).

### 1. Replay self-test against a SYNTHETIC capture

`tests/fixtures/synthetic-ora-capture/` contains, clearly labelled in `oracle.env` and in
each file's first line:

* `mss__osag_ip__pure.ora.raw`, `tt__event_interface__ticket_type.ora.raw`,
  `tt__ticket_interface__status_lifecycle.ora.raw`: the **PostgreSQL** captures re-dressed
  in SQL*Plus shape by `tests/pg2synthetic.py` (upper-case quoted header, quoted strings,
  bare numbers, BINARY row order, Oracle-style `-1403` codes). They prove only that the
  pipeline handles the SQL*Plus format and reports PASS when the sides agree -- they say
  nothing about Oracle.
* `mss__osag_ip__oracle_bugs.ora.raw`: **hand-derived** from the Oracle source
  (`ddl/src/pkgb/mss_osag_ip.sql`, the arithmetic of the lines cited by spec clauses
  S-IP-008/009/014/020/023). This is what the differential run is expected to show for the
  documented `DEVIATION(ORACLE-BUG)` inputs; the scenario's `known.diff` was frozen from
  it. The first live run confirms or corrects both files -- a mismatch is reported as
  `DIFF`, never hidden.

```
$ bash migration/test/diff/run-diff.sh --all --ora-from migration/test/diff/tests/fixtures/synthetic-ora-capture --no-install
run-diff.sh: Oracle side replayed from migration/test/diff/tests/fixtures/synthetic-ora-capture
run-diff.sh: replayed capture's oracle.env:
    ORA_VERSION=SYNTHETIC -- this capture was NOT produced by an Oracle database
    ...
SCENARIO                                         | ORACLE  | PROBES | RESULT
-------------------------------------------------+---------+--------+------------
mss__osag_ip__oracle_bugs                        | replay  | 1      | KNOWN
mss__osag_ip__pure                               | replay  | 1      | PASS
tt__event_interface__ticket_type                 | replay  | 1      | PASS
tt__ticket_interface__status_lifecycle           | replay  | 5      | PASS

TOTAL: 4 scenarios, 4 pass/known, 0 diff/error, 0 without Oracle data (oracle: replay)
exit=0
```

### 2. A deliberate difference is caught

`tt__ticket_interface__status_lifecycle/call.pg.sql` was mutated so that step 01 changes
the status to 4 (acknowledged) instead of 3 (hot), and the replay above was repeated:

```
=== tt__ticket_interface__status_lifecycle  (ORA_USER=system, COMMITS=no) ===
--- DIFF: tt__ticket_interface__status_lifecycle (- oracle, + postgresql) ---
@@ -1,7 +1,7 @@
 ## probe 1 steps (post-step status in n, valid-until set/null in s; error code for failed steps)
 step,code,msg,n,s
 00 initial,,,2,null
-01 open->hot,,,3,null
+01 open->hot,,,4,null
 02 hot->hot no-op,,,3,null
@@ -14,7 +14,8 @@
 ## probe 3 events written by the routines (the fixture event 950011 excluded)
 type_id,ticket_id,public_event,company_id,contact_id,details_public,details_private
-101003,950010,1,,950002,New status: hot\nPrevious status: open\nmoved to hot,
+101003,950010,1,,950002,New status: hot\nPrevious status: acknowledged\nsame status again,
+101004,950010,1,,950002,New status: acknowledged\nPrevious status: open\nmoved to hot,

mss__osag_ip__oracle_bugs                        | replay  | 1      | KNOWN
mss__osag_ip__pure                               | replay  | 1      | PASS
tt__event_interface__ticket_type                 | replay  | 1      | PASS
tt__ticket_interface__status_lifecycle           | replay  | 5      | DIFF
TOTAL: 4 scenarios, 3 pass/known, 1 diff/error, 0 without Oracle data (oracle: replay)
exit=1
```

The mutation was reverted and the clean run (exit 0) repeated. The `PASS` rows above are
PostgreSQL-vs-PostgreSQL by construction; the `KNOWN` row is PostgreSQL-vs-hand-traced
Oracle. **The real Oracle run has not happened yet.**

## How to run the Oracle side (when `mcdb-ora` is up)

```bash
docker ps --format '{{.Names}} {{.Status}}'          # mcdb-ora must say Up; do not start it yourself if someone is rebuilding it
docker exec mcdb-ora sqlplus -s tt/password@localhost:1521/XEPDB1 <<< "SELECT status FROM all_objects WHERE owner='TT' AND object_name='TICKET_INTERFACE' AND object_type='PACKAGE BODY';"
bash migration/test/diff/run-diff.sh --all --ora-capture migration/test/diff/captures/$(date +%F) --keep
```

Then, per scenario:

* `PASS` -- record it in the plan summary; keep the capture directory (it makes the result
  reproducible offline with `--ora-from`).
* `KNOWN` on `mss__osag_ip__oracle_bugs` -- the hand-derivation was right; note it.
* `DIFF` on `mss__osag_ip__oracle_bugs` -- compare `.work/mss__osag_ip__oracle_bugs/diff.body`
  with `known.diff`: where they disagree, Oracle's real output replaces the hand-traced
  value in `tests/fixtures/.../mss__osag_ip__oracle_bugs.ora.raw` and in `known.diff`
  (and, if the spec's description of Oracle's behaviour was wrong, in the spec's cited
  clause through `migration/spec/TEST-AMENDMENTS.md`).
* `DIFF` on any other scenario -- that is the finding this harness exists for. Each
  differing line is either a translation defect (fix the translation, re-run), a
  fixture/probe asymmetry (fix the scenario), or an undocumented Oracle behaviour (spec
  amendment + decide). Record each precisely in the plan summary.
* `ERROR` with `ORA-01017` in `.work/<s>/ora.raw` -- the schema user's password is not
  `password`; pass `MCDB_ORA_PASSWORD`. `SP2-0640: Not connected` -- the CONNECT failed
  (service name, listener); check `docker logs mcdb-ora`.

Things the live run will tell us that static analysis could not, already visible in the
PostgreSQL output: whether `add_history_event` leaves `tt.ticket.last_public_event_id`
untouched on Oracle too (PostgreSQL: `has_last_public_event=0`), whether
`updateTicketTimeStats` records a non-zero `waiting_time` for a sub-second waiting period
(PostgreSQL: `has_waiting_time=0`), and the exact Oracle renderings for the five
`num2ipv6` bug inputs.
