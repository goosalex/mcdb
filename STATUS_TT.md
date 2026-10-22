# STATUS_TT.md: TT and TICKETEVOLUTION on PostgreSQL

Progress report for the sub-project that moves the ticketing schemas (`TT`, `TICKETEVOLUTION`)
and their dependency closure to PostgreSQL first, while everything else stays on Oracle 19c.
Branch `phoenix/tt_container_ora`. Last updated 2026-10-22. Previous reports:
`.planning/reports/tt-only-scope-2026-10-16.md` (scope and decisions),
`.planning/reports/known-diffs-2026-10-21.html` (the four frozen Oracle/PostgreSQL differences, with diagrams).

## 1. Why TT first

The full migration (48 packages, 24 schemas) was inventoried and a spec-first method was
proven on a pilot batch (see `migration/README.md`, `migration/PHASE2-FINDINGS.md`). In
October 2026 the focus shifted: translate the ticketing part first, prove it against a live
Oracle, and leave the rest on Oracle behind a bridge. The ticketing closure is:

| Part | Objects |
|---|---|
| `TT` | 34 tables, 5 packages with code (TICKET_INTERFACE 38 routines, EVENT_INTERFACE 8, OSAG_NOTIFY 6, UTIL 5, ESCALATION_INTERFACE 5), 2 `*_STATE` constant packages, 2 triggers, 3 scheduler jobs |
| `TICKETEVOLUTION` | 3 tables, CALCULATOR (2 procedures), 1 job |
| Leaf dependencies | `MSS.OSAG_IP`, `MSS.OSAG_DBPROP`, `OSAG.OSAG_MSG`, `OSAG.OSAG_PLOG` |

## 2. Where the code stands

| Area | State | Evidence |
|---|---|---|
| The 61 public TT routines | translated, re-synced with the October 2026 Oracle source (sign-off senders by Zitadel id, `worker_zitadel_id`) | 25 differential scenarios run live against the Oracle container: 25/25 PASS or KNOWN; every routine driven live at least once |
| MSS.OSAG_IP, OSAG.OSAG_MSG, MSS.OSAG_DBPROP, TICKETEVOLUTION.CALCULATOR, both TT triggers, the 4 jobs (as pg_cron) | translated, green | pgTAP suites and regress goldens |
| Test base | 25 pgTAP suites, 893 assertions, 610 of them in the TT closure; each assertion cites a spec clause | `migration/test/run-all.sh`: gates PASS, 16 of 17 packages green; the one red (`auth.osag_auth` S-AUTH-007) is red by decision (plog, see 5) |
| Corrections of Oracle bugs | 23 sites marked `DEVIATION(ORACLE-BUG)`, each with a spec clause and a test | scope report section 6; the live run confirmed each one is a real divergence |
| Oracle/PostgreSQL differences kept on purpose | 4 classes, frozen as `known.diff` and documented | `.planning/reports/known-diffs-2026-10-21.html`, section 6 below |
| OSAG.OSAG_PLOG | stub (writes a table) | every TT routine logs through it; the production implementation is an open decision (5) |

**Calibration.** First contact with real Oracle found 9 translation defects in 61 routines,
all in rarely exercised branches, and falsified 2 spec claims. The pgTAP suites, derived
from reading the Oracle source, had not caught any of them. Branches no differential
scenario has driven may still hide defects of the same kinds.

## 3. What still separates us from behavioural parity

Ranked by risk.

1. **NULL concatenation class.** Oracle treats `'x' || NULL` as `'x'`; PostgreSQL yields
   NULL. Four live defects were of this class (audit texts silently NULL, events lost).
   161 unguarded concatenation lines with nullable operands remain unaudited in
   `migration/pgsql`. Needs one convention (`concat()` or `coalesce` at every nullable
   operand), applied as a sweep with tests. Largest known gap, and mechanical.
2. **Empty-string class.** Oracle folds `''` to NULL for text arguments. Two sites found
   live and fixed. The same sweep covers it; Q15 (can production rows hold `''`) decides
   how much of it matters.
3. **Residual untested branches.** A second scenario pass aimed at error handlers and
   rarely used flows (merge, despam, rating, deferral expiry) is the cheapest insurance.
4. **Three decisions**, see 5.
5. **Master data drift.** The PostgreSQL template is built from the CSVs; Oracle carries
   post-tag changesets with DML on top (event types: 131 rows vs 134). A production data
   load fixes it; until then fixtures can diverge for the newest rows.
6. **S-NOTIFY-003 cardinality re-read** after schema-fix 29 made the two-services case
   impossible.

## 4. Autonomous transactions: accepted, and where it has an impact

PostgreSQL has no autonomous transactions and a caught error undoes the whole failed call
(the exception block is a sub-transaction). Oracle only undoes the failing statement. The
decision taken for this sub-project: **accept PostgreSQL semantics** (requirement XCUT-05).
It is visible in exactly these cases inside the TT closure:

| Case | Oracle | PostgreSQL | Who notices |
|---|---|---|---|
| `escalate_os` / `escalate_customer` on a closed ticket, caller catches the error | ticket left at escalation status 10 with a date | ticket untouched (0, NULL) | callers with a swallowing handler, e.g. MC.MONITORING_TICKET_PROCESSES. On the dynamic-dispatch path through `exec_event_type_actions` both engines agree |
| `util.close_old_dev_tickets` (PRAGMA AUTONOMOUS_TRANSACTION + COMMIT per iteration) | isolated commits | plain procedure; its COMMIT commits the calling session's transaction | safe only as a top-level scheduled CALL; dev-only, never scheduled on Oracle either |
| `plog` on error paths | autonomous: log line survives the rollback | stub rides in the transaction: line lost | the red S-AUTH-007 assertion; fixed by the real plog implementation |
| mail and SMS (`OSAG_MSG`) | sent at call time, even for work later rolled back | outbox row, sent only for committed work | strictly better; clients no longer get mail from a failed transaction |
| MC.OSAG_MAINTSYNC batch loops | earlier iterations kept on a late failure | earlier iterations undone, redone next minute | not TT; stays on Oracle in this split |

Documented today in `migration/spec/tt.escalation_interface.md` (XCUT-05 note),
`migration/pgsql/tt/escalation_interface.FINDINGS.md`, `migration/pgsql/tt/util.FINDINGS.md`,
`migration/pgsql/osag/osag_msg.FINDINGS.md`, `migration/pgsql/mc/osag_maintsync.FINDINGS.md`
and the `closed_ticket` scenario's `known.diff`. Remaining paperwork: state the rule once
in a cross-cutting spec and turn those notes into citations.

## 5. Decisions needed from the owner

| # | Question | Recommendation |
|---|---|---|
| plog (Q5, XCUT-02) | production logging: UDP shipper to the telemetry sink, table sink, or both | keep the table sink as the test implementation; ship a second body for production that also sends the datagram. Needs host/port/format of the receiver |
| S-TICKET-065 | keep Oracle's wipe of `recoverable_status_id` on tickets without a public event, or correct it | keep through cut-over so both systems agree; correct afterwards as a recorded `DEVIATION(ORACLE-BUG)` (one-line change, clause rewrite, two assertions flipped, one `known.diff`) |
| Allowlist scope (Q9, S-EVENT-038) | which procedure names `exec_event_type_actions` may dispatch | decided narrow (the four TT.ESCALATION_INTERFACE routines) from master data; confirm with `SELECT DISTINCT procedure_name FROM tt.event_action` on production |
| Q15 empty strings | can `tt.ticket.customer_reference` / `tt.event.details_public` hold `''` in production | a production query answers it |
| Outbox drainer | who sends `osag.msg_outbox` rows | a small external job; go-live dependency, without it no mail or SMS leaves PostgreSQL |

## 6. The four frozen differences (summary)

Full explanation with sequence and state diagrams: `.planning/reports/known-diffs-2026-10-21.html`.

1. Earlier writes survive a caught error on Oracle only (section 4, first row).
2. Email: ORA-24247 inside the Oracle container (no mail relay, no network ACL), outbox on
   PostgreSQL. Test-environment artefact plus the planned platform change S-MSG-013.
3. Dynamic dispatch refuses procedure names that are not on the allowlist; Oracle would
   execute any configured name. Deliberate hardening (S-EVENT-038).
4. `recoverable_status_id` follows Oracle's three-valued `NOT x IN (30016)`, reproduced
   faithfully as S-TICKET-065 (no longer a `known.diff`; the translation matches).

## 7. From parity to a stable deployment

The larger half, and architecture rather than translation.

- **TT is not a leaf schema.** 22 foreign keys from 12 other schemas point into TT, TT reads
  31 non-TT tables, `deleteTicket` writes 13 of them. A TT-only move needs replicated
  reference data for 21 tables, a bridge for the Oracle-side callers (MC monitoring, NIDS,
  OSIXINFO, AUTH.delete_login) and callbacks for `deleteTicket` / `merge_tickets`. Drafts:
  `migration/oracle_side/`. They have never run against Oracle; the local container
  (`mcdb-ora`) now makes that possible.
- **Data migration** of the 37 tables plus sequences has not been attempted. The ora2pg
  sequence gap is a known item.
- **Schema baseline.** `ddl/migrated` (ora2pg output) predates the October export and is
  patched by the fix files under `migration/test/schema-fixes/` (10 files, ledger in
  `migration/test/SCHEMA-FIXES.md`). Regenerate from the current export and carry the
  post-tag changesets to PostgreSQL.
- **Client renames.** `migration/mapping/rewrite_names.py`, `client-rename.sed` (346 rows) and
  the in-database twin `pgmig.*` are verified against all Oracle package bodies and the names
  stored in data, not yet against the Java and Perl clients.
- **Not yet looked at.** Concurrency and locking under load, grants for the 31 service
  accounts on PostgreSQL, the outbox drainer and the plog receiver as external components.

## 8. Estimate

Code parity (sweep, decisions, plog, a second scenario pass): one to two weeks of focused
work, fully inside this repository. Deployment (bridge, replication, data migration, client
renames): several weeks, dependent on decisions outside the repository (bridge transport,
replication cadence, who runs the drainer and the log receiver). Best next step by return:
the NULL-concatenation and empty-string sweep, the one proven defect class the current
tests do not cover.

## 9. How to re-verify

```bash
migration/db/pg.sh start                      # PostgreSQL 18 + orafce + pgTAP container (mcdb-pg)
migration/test/run-all.sh                     # gates, pgTAP, regress goldens
migration/test/diff/run-diff.sh --all         # differential run against the Oracle container (mcdb-ora)
migration/test/diff/run-diff.sh --all --ora-from migration/test/diff/tests/fixtures/oracle-capture-2026-10-21
```

Oracle container: built from `container/docker_orafree_based/Dockerfile` (artifact repository
detected automatically, see `migration/db/pg.sh` and `container/container-entrypoint-initdb.d/110_run_initial_load.sh`).
Rules: `ddl/` and `masterdata/` are read-only inputs (productive Oracle uses them); all
migration output lives under `migration/`. Disposable test databases must match
`^mcdb_(test|tmpl|harness)[a-z0-9_]*$`.
