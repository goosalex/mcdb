# OSAG_PLOG stub -- FINDINGS

**Source:** `ddl/src/pkg/osag_osag_plog.sql` (spec, 49 lines), `ddl/src/pkgb/osag_osag_plog.sql`
(body, 211 lines). **Target:** `migration/pgsql/osag/osag_plog.sql`.

**This is a stub, not a translation.** Locked decision D-P5a (`02-CONTEXT.md`): plog is
"the simplest thing that works" for Phase 2 -- write/print the log line, make it
observable enough that a test can assert "this error path logged X". The real UDP
shipper is Phase 3's XCUT-02. **Do not let this file's shape constrain XCUT-02's
design** -- that is the explicit instruction this stub was built under.

## What this stub deliberately does NOT do

| Oracle original | This stub |
|---|---|
| `PublishToMCDBQueue` enqueues onto Oracle AQ (`DBMS_AQ.ENQUEUE`, queue `MCDB_MONITOR.plog_messages`, payload type `MCDB_MONITOR.PLOG_MESSAGE_TYPE`) | Not implemented. No queue exists in this stub or its target. XCUT-02 replaces this with a UDP datagram send. |
| `Log()` runs `PRAGMA AUTONOMOUS_TRANSACTION` and ends with an explicit `COMMIT` (`ddl/src/pkgb/osag_osag_plog.sql` line 47 pragma, line 54 `COMMIT;`), so the log survives the caller's own rollback | **Not ported.** PostgreSQL has no autonomous-transaction equivalent, and — critically — a PostgreSQL `PROCEDURE` that runs `COMMIT`/`ROLLBACK` cannot be `CALL`ed from inside a `FUNCTION` body. Every pilot package calls plog from routines that may well be translated as `FUNCTION`s (`pg_kind` in `name-map.csv` is still provisional pending Phase 3's XCUT-04 COMMIT analysis). A `COMMIT` here would poison the whole pilot with an error that looks like an unrelated translation bug — this was the single most important constraint on this file, and is mechanically proven absent by this plan's own verification (a `CALL` from inside a `pg_temp` `FUNCTION` body succeeds). |
| `AuditUsage()` runs `PRAGMA AUTONOMOUS_TRANSACTION`, updates `osag.plsql_audit`, and `COMMIT`s (`ddl/src/pkgb/osag_osag_plog.sql` line 104 pragma, line 125 `COMMIT;`) | **Deliberately not created at all** (not even as a no-op stub). This is not a new call — `PROJECT.md`, `REQUIREMENTS.md` (XCUT-06), and `.planning/research/PITFALLS.md` Pitfall 4.3 already establish that `plsql_audit` is write-only (nothing reads it) and the feature is **deleted**, not ported. Creating any stub for it would falsely imply the audit still functions. Pilot package translations delete their `plog.AuditUsage(...)` call sites and record the count removed in their own spec/summary docs, reconciled against the corpus-wide expectation of ~177 call sites (02-CONTEXT.md). |
| `who_called_my_caller()` walks `dbms_utility.format_call_stack` text output to resolve the calling procedure's owner/name/line (`ddl/src/pkgb/osag_osag_plog.sql` lines 131-207) | Not ported. There is no direct PostgreSQL equivalent, and reconstructing one is out of scope for a throwaway stub. `osag.osag_plog_log`'s `caller` column is always `NULL` in this stub. If a pilot test ever needs caller attribution, it must derive it from the calling package's own `plog.err(...)` message text, not from this column. |
| `LogRaw()` calls `PublishToMCDBQueue` directly, bypassing `Log()`'s autonomous transaction and caller resolution but NOT the enqueue itself | This stub's `osag_plog_lograw` still writes an observable row (there is no queue to skip here), with `caller` and `levelname` left `NULL` — matching the Oracle spec's own comment that LogRaw "does not filter by level, does not modify the message and does not determine the caller" (`ddl/src/pkg/osag_osag_plog.sql` lines 37-38). |

## Rollback limitation (read this before writing a Phase 2 test)

**`osag.plog_stub_log` rows are written inside the caller's own transaction and are
LOST on `ROLLBACK`.** This is the direct consequence of not porting the autonomous
transaction (see table above) — it is a real, deliberate limitation of the stub, not an
oversight, and it is exactly why Phase 3 replaces this with a UDP shipper (a UDP
datagram, once sent, cannot be un-sent by a later `ROLLBACK`).

**Consequence, stated so no later plan trips on it (02-CONTEXT.md, verbatim):** pilot
tests assert on plog output **without** forcing a rollback. Rollback-survival of
logging is **not** a Phase 2 claim; it is XCUT-02's test, in Phase 3.

## The Phase 3 (XCUT-02) contract this stub must be replaced by

Whatever XCUT-02 builds must, at minimum:

1. Preserve the **12** public procedure/function names and signatures below unchanged
   (client packages already call them; changing the surface breaks every pilot
   translation and every later bulk translation from Phase 4).
2. Replace the body of `osag_plog_log` (and, if warranted, `osag_plog_lograw`) with a UDP
   datagram send instead of (or in addition to) the `osag.plog_stub_log` INSERT.
3. Decide, deliberately, whether the replacement survives `ROLLBACK` (Oracle's original
   did, via the autonomous transaction + AQ enqueue, which itself commits independently
   of the caller). A UDP `sendto()` inherently survives rollback (it is not
   transactional), so XCUT-02 gets this property "for free" if it sends the datagram
   synchronously at call time, rather than deferring it to a `COMMIT` trigger.
4. Decide what (if anything) replaces `osag.plog_stub_log` as an in-database,
   assertable-by-tests sink. If nothing does, every pgTAP test written against this
   stub's table (`SELECT ... FROM osag.plog_stub_log WHERE ...`) must be rewritten in
   Phase 3 — flag this dependency explicitly when XCUT-02 is planned.
5. Restate the no-transaction-control constraint from this file's header: the replacement
   procedures must remain `CALL`-able from inside a `FUNCTION` body. If the UDP send is
   truly synchronous and non-transactional (as a raw `sendto()` naturally is), this holds
   automatically; if XCUT-02 introduces any queuing/batching with its own commit
   semantics, re-verify this property explicitly, the same way this plan did.

## The 12 implemented routines (of 13 total; `AuditUsage` intentionally absent)

All names copied verbatim from `migration/mapping/name-map.csv`'s 13 `OSAG_PLOG` rows.

| Oracle | `pg_kind` | PostgreSQL |
|---|---|---|
| `Emerg(message)` | procedure | `osag.osag_plog_emerg(message text)` |
| `Alert(message)` | procedure | `osag.osag_plog_alert(message text)` |
| `Crit(message)` | procedure | `osag.osag_plog_crit(message text)` |
| `Err(message)` | procedure | `osag.osag_plog_err(message text)` |
| `Warning(message)` | procedure | `osag.osag_plog_warning(message text)` |
| `Notice(message)` | procedure | `osag.osag_plog_notice(message text)` |
| `Info(message)` | procedure | `osag.osag_plog_info(message text)` |
| `Debug(message)` | procedure | `osag.osag_plog_debug(message text)` |
| `LevelAsString(loglevel)` | function | `osag.osag_plog_levelasstring(loglevel int) RETURNS text` |
| `LevelAsNum(loglevel)` | function | `osag.osag_plog_levelasnum(loglevel text) RETURNS int` |
| `Log(loglevel, message)` | procedure | `osag.osag_plog_log(loglevel int, message text)` |
| `LogRaw(loglevel, message)` | procedure | `osag.osag_plog_lograw(loglevel int, message text)` |
| `AuditUsage(...)` | procedure | **not created** (XCUT-06) |

Level numbering (0..7, syslog-shaped) and names (`EMERG ALERT CRIT ERR WARNING NOTICE
INFO DEBUG`) are copied verbatim from the Oracle body's `LevelAsString`/`LevelAsNum`
(`ddl/src/pkgb/osag_osag_plog.sql` lines 72-100), not invented.

## Verification performed

- Loads cleanly into a `bootstrap.sh --template mcdb_tmpl` clone (`mcdb_test_plog`).
- `CALL osag.osag_plog_err('pilot-canary')` inserts exactly one row into
  `osag.plog_stub_log` with `loglevel = 3`, matching the message — the observable
  contract a pilot test can assert on.
- A `pg_temp` `FUNCTION` that `CALL`s `osag.osag_plog_debug(...)` from inside its own
  body succeeds — proves no transaction control leaks out of any of the 12 routines.
- `pg_proc` surface count is exactly 12 for `osag.osag_plog_%`, and
  `osag_plog_auditusage` is confirmed absent.
