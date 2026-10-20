# 06-05 SUMMARY -- Differential harness (Oracle vs PostgreSQL)

Branch `phoenix/migrate_tt_only`, executed 2026-10-20 in worktree `agent-a53b893c031935a63`.
Deliverable: `migration/test/diff/` (new) + a pointer section in `migration/test/README.md`.
Nothing else under `migration/test/` changed; `ddl/`, `masterdata/`, `migration/spec/*`,
`migration/pgsql/*`, `migration/test/pgtap/*`, `migration/test/regress/*` untouched.

## Commits

| commit | content |
|---|---|
| `73ddd96` | cherry-pick of `1a8c31c` (pg.sh resolves the project root to the main checkout from worktrees) -- requested by the coordinator mid-plan; only the `migration/db/pg.sh` hunk was taken, the two conflicting container scripts (owner's area) were kept at this branch's state. Verified: `pg.sh start` from the worktree left `mcdb-pg`'s StartedAt unchanged. |
| `fdb39ec` | `test(diff)`: harness -- `run-diff.sh`, `compose.py`, `normalize.py`, `derive_pg_call.sh`, `tests/test_normalize.py` (17 tests), `tests/pg2synthetic.py` |
| `cdcb454` | `test(diff)`: 4 pilot scenarios + `tests/fixtures/synthetic-ora-capture/` |
| `4a015a3` | `test(diff)`: `diff/README.md` + section in `migration/test/README.md` |
| (this)    | `docs(06)`: this summary |

Not pushed.

## What exists

```
migration/test/diff/
├── run-diff.sh        [--scenario NAME ...|--all] [--ora-container] [--ora-user] [--ora-service]
│                      [--pg-db] [--pg-timezone] [--install DIR|--no-install] [--keep]
│                      [--ora-capture DIR|--ora-from DIR] [--pg-capture DIR]
├── compose.py         one-shot script per side; probe markers `## probe N label`
├── normalize.py       rules R1-R11; sqlstate table from migration/mapping/sqlstate-map.md
├── derive_pg_call.sh  helper (client-rename.sed + CALL + DO $$ + built-ins), not a translator
├── scenarios/
│   ├── mss__osag_ip__pure/                      73 inputs, expected equal
│   ├── mss__osag_ip__oracle_bugs/               18 inputs, expected to differ (known.diff)
│   ├── tt__event_interface__ticket_type/        130 event types + unknown + NULL
│   └── tt__ticket_interface__status_lifecycle/  fixtures 950xxx; 2->3->3->11->102, change_subject, NO_DATA_FOUND
└── tests/  test_normalize.py, pg2synthetic.py, fixtures/synthetic-ora-capture/
```

Design points that differ from the plan text, and why (all documented in `diff/README.md`):

- **Probe table on Oracle is a GLOBAL TEMPORARY TABLE**, not a heap table: CREATE TABLE
  commits in Oracle, so it is created before the transaction and dropped after the
  ROLLBACK; a GTT needs no quota, its rows are session-private and transactional.
- **PostgreSQL session timezone defaults to UTC, not Europe/Zurich**: the Oracle container
  (`docker inspect mcdb-ora`) sets no `TZ`, SYSDATE there is UTC, and the template is
  `Etc/UTC`; the live preflight records Oracle's offset in `oracle.env` and the script
  warns on a mismatch (`--pg-timezone` overrides).
- **Rows are sorted within a probe section (R10)**: the template collates `en_US.utf8`,
  Oracle sorts BINARY; row order is not part of the contract.
- **`\set ON_ERROR_ROLLBACK on`** on psql: emulates Oracle's statement-level atomicity so a
  failing statement does not poison the transaction and later probes still run.
- **`known.diff` + KNOWN/STALE-KNOWN results**: documented `DEVIATION(ORACLE-BUG)` inputs are
  *supposed* to differ; a scenario can freeze the accepted difference, and the harness
  fails when the sides later agree (stale file) or differ otherwise.
- **`--pg-capture DIR`** added (used by the self-test).
- **Lifecycle scenario connects as SYSTEM**: TT holds only SELECT/REFERENCES on
  `stop.company`/`stop.contact`/`mss.host` (`ddl/generated/grants`), and the fixtures must
  insert there. Routines are definer-rights and schema-qualified, so the caller does not
  change their behaviour.
- **Dialect-neutral fixtures use `CURRENT_TIMESTAMP - INTERVAL '1' HOUR`** (valid in both),
  not SYSDATE/now().

## What was verified

| item | how | result |
|---|---|---|
| Unit tests | `python3 -m unittest discover -s migration/test/diff/tests -v` | 17/17 OK |
| PostgreSQL side, all 4 scenarios | `run-diff.sh --all --pg-capture ...` (fresh `mcdb_test_diff` from `mcdb_tmpl` + `migration/pgsql`) | every probe produced rows, no noise lines, exit 2 (nothing to compare) |
| Replay pipeline, SQL*Plus shape | `run-diff.sh --all --ora-from tests/fixtures/synthetic-ora-capture --no-install` | 3 PASS + 1 KNOWN, exit 0 |
| Falsifiability | lifecycle `call.pg.sql` step 01 mutated to status 4; same replay | lifecycle DIFF (2 hunks: step row `3`->`4`, event rows 101003/101004), exit 1; reverted, clean run exit 0 |
| `pkgname.py` gate on scenario names | all four names validated at run start | OK |
| `derive_pg_call.sh` | on lifecycle and ticket_type `call.ora.sql` | names + CALL + outer block correct; nested PL/SQL procedures left as-is (documented) |

**The Oracle side did NOT run.** `docker ps` was checked at the start, three times during
the work and at the end: `mcdb-ora` was `Exited (143)` every time (the project owner was
rebuilding it on this box; anonymous build containers came and went). Per the plan's
rules no container was started, stopped, built or tagged. Consequently:

- the three `PASS` results above are PostgreSQL-vs-PostgreSQL (synthetic captures made by
  `tests/pg2synthetic.py`, labelled as such in `oracle.env` and in each file's first line)
  and prove the pipeline, not Oracle parity;
- the `KNOWN` result is PostgreSQL-vs-**hand-traced** Oracle (`mss__osag_ip__oracle_bugs`):
  the 18 Oracle values in the fixture and in `known.diff` were derived by hand from
  `ddl/src/pkgb/mss_osag_ip.sql` (e.g. `ip2num('1.2.3.4.5') = 16909060.5`,
  `num2ip(1.5) = '0.0.0.1.5'`, `ipv6right('1:2:3:4:5:6:7:8:9') = 1407400653815816`,
  `num2ipv6(1.5, 0) = '0:0:0:2::'`, `num2ipv6(-1, 0) = '#####::'`); the first live run
  confirms or corrects them -- a mismatch is reported as DIFF.

## Differences between Oracle and PostgreSQL behaviour found

None could be *established* without Oracle. Two observations from the PostgreSQL output
are flagged in `diff/README.md` as the first things the live run will settle:

1. `tt__ticket_interface__status_lifecycle`, probe 2: `has_last_public_event = 0` after four
   `add_history_event` calls -- the translation does not update
   `tt.ticket.last_public_event_id`. Whether Oracle's `add_history_event` does is exactly
   what the diff will show.
2. probe 5: `has_waiting_time = 0` after a sub-second waiting period -- whether Oracle's
   `updateTicketTimeStats` rounds the same way.

Plus the 18 documented ORACLE-BUG deviations of `MSS.OSAG_IP`, now encoded as an
executable expectation (`known.diff`) rather than prose.

## Limitations

- Oracle untouched only by ROLLBACK: `OSAG.OSAG_PLOG` writes through
  `PRAGMA AUTONOMOUS_TRANSACTION` (every TT routine calls `plog.AuditUsage`) survive.
- `COMMITS=yes` path (fresh PG clone, no transaction block, `cleanup.ora.sql` best effort)
  is implemented but unexercised: no pilot scenario commits.
- `SET CONSTRAINTS ALL DEFERRED` on both sides means a violation that would surface at
  COMMIT is never seen.
- NULL vs `''`, booleans and row order are collapsed; messages are not compared unless
  `COMPARE_MSG=yes`.
- `derive_pg_call.sh` cannot convert nested PL/SQL procedures; hand-written `call.pg.sql`.
- The sandbox refused compound shell commands several times; nothing functional depends
  on it, but `run-diff.sh` is best invoked with its output redirected to a file.

## How to run (next person, with `mcdb-ora` up)

```bash
docker ps --format '{{.Names}} {{.Status}}'      # mcdb-ora must be Up -- do not start it if someone is rebuilding it
bash migration/test/diff/run-diff.sh --all --ora-capture migration/test/diff/captures/$(date +%F) --keep
```

Then follow "How to run the Oracle side" in `diff/README.md`: PASS -> record; KNOWN on
`oracle_bugs` -> hand-derivation confirmed; DIFF on `oracle_bugs` -> replace the
hand-traced values in the fixture and `known.diff` with Oracle's real ones; DIFF elsewhere
-> the finding (translation defect / scenario asymmetry / undocumented Oracle behaviour),
list each line in the plan summary of whoever runs it.

## Next steps (plan 06-06 / 06-07)

- First live run; keep the capture directory under version control if small (it makes the
  comparison reproducible offline with `--ora-from`).
- Scenarios for every package in the TT closure (06-06): the pattern is in place --
  `meta.env`, dialect-neutral `setup.sql`/`probe.sql`, hand-written `call.*.sql`
  wrappers (Oracle nested procedures / PostgreSQL `pg_temp.*` functions + `DO`/`PERFORM`).
- Consider a `--pg-only` flag that skips the Oracle preflight entirely (today "none" mode
  does that implicitly when the container is down).
- `run-all.sh` integration (06-07): `run-diff.sh --all --ora-from <latest capture>` as a
  gate when Oracle is not available, live when it is.
