# PHASE2-FINDINGS.md — the brief Phase 3 opens first

Seven scattered `*.FINDINGS.md` files (one per pilot package, plus the `osag_plog` stub)
rolled into one document, organised by the Phase 3 decision each finding feeds. Every
claim below is traced to its source FINDINGS file — this document does not re-derive
anything, it indexes and reconciles.

**Pilot scope:** `osag.osag_plog` (D-P5a stub, not a translation), `mss.osag_dbprop`,
`auth.osag_auth`, `tt.util`, `tt.osag_notify`, `tt.event_interface`,
`tt.ticket_interface` — 6 real translations, 76 public routines, 213 `SELECT INTO`
sites, the whole `TT.EVENT_INTERFACE`/`TT.OSAG_NOTIFY`/`TT.TICKET_INTERFACE`/`TT.UTIL`
cycle group exercised together for the first time in `migration/test/REDGREEN-EVIDENCE.md`.

---

## XCUT-01 — Exception mapping

Every Oracle exception path the pilot actually hit, and the PROVISIONAL SQLSTATE choice
made. Phase 3 makes these authoritative — none of them is presented as final.

| Oracle condition | PostgreSQL translation | Status |
|---|---|---|
| Unhandled `NO_DATA_FOUND` on a `SELECT INTO STRICT` that has no local Oracle handler | Native PL/pgSQL `P0002` ("query returned no rows"), propagates unhandled — matches Oracle's own "no local handler" shape exactly | Settled for the pilot; SQLSTATE choice (`P0002`, PL/pgSQL's own default) not yet Phase-3-ratified as the corpus-wide convention |
| Same, but a test/golden needs Oracle's exact `ORA-01403` **message text** (`no data found`), not PL/pgSQL's native `query returned no rows` | The "message-parity shim": `BEGIN ... EXCEPTION WHEN NO_DATA_FOUND THEN RAISE EXCEPTION 'no data found' USING ERRCODE = 'P0002'; END` wrapped tightly around the `SELECT INTO STRICT` — re-raises the SAME SQLSTATE with corrected message text only; no control-flow change | Applied at **14 sites** across 5 packages (see table below). Message text only, not a SQLSTATE decision — flagged in every FINDINGS file that uses it as provisional pending XCUT-01 |
| `TOO_MANY_ROWS`, unhandled | Native `P0003` ("query returned more than one row") | One live-confirmed site (`tt.event_interface` S-EVENT-001, `mss.host2service`'s 2-column PK) |
| `TOO_MANY_ROWS`, locally handled (swallow to `NULL`) | Native `P0003` caught by an explicit `WHEN TOO_MANY_ROWS` arm | One site (`tt.osag_notify` S-NOTIFY-031, `__get_isp_link_id_for_host_id`) |
| Oracle `SQLCODE = -00001` / `ORA-00001` (unique constraint) discriminated in a handler | PostgreSQL native `unique_violation` (`23505`), matched by `SQLSTATE` | `auth.osag_auth` `grant_user_role` — a real business-logic discriminator (swallow a re-grant), not a blanket catch |
| `OSAG_DBPROP_STATE.S_ERRNO_UNKNOWN_DBPROP` (Oracle `-20801`) | Plain `RAISE EXCEPTION`, no explicit `ERRCODE` → defaults to PL/pgSQL's generic `P0001` | **UNASSIGNED.** Not yet mapped to a real, documented custom SQLSTATE. Phase 3 action item. |
| `OSAG_DBPROP_STATE.e_abort` (no `PRAGMA EXCEPTION_INIT`, no fixed Oracle code) | Bare `RAISE;` re-raise inside `WHEN OTHERS`, after logging | **UNASSIGNED**, deliberately kept on a different PostgreSQL error path from the row above (no shared ERRCODE) |
| Oracle's "log and swallow" `WHEN OTHERS` idiom (never re-raises) | `WHEN OTHERS THEN CALL osag.osag_plog_err(...); END;` — no `RAISE` | Used pervasively (`tt.osag_notify`'s `event_notify`, `tt.event_interface`'s dynamic-SQL site, several `tt.ticket_interface` routines) — preserved as-is, not converted to propagate |

**Message-parity shim site count, per package** (the 14 sites above): `auth.osag_auth`
2 (`delete_login`, `grant_user_role`), `tt.util` 1 (`update_status_valid_until`),
`tt.osag_notify` 7 (`send_test_notification` + 6 private helpers reachable from it),
`tt.event_interface` 2 (`demote_event`, `promote_event`), `tt.ticket_interface` 2
(`update_ux_timeout_for_ticket`, `clear_todo_list`) = **14**. Every site is a message-text
correction only — the mutation check in `REDGREEN-EVIDENCE.md` (Mutation 3) confirms the
suite catches a swallow of one of these re-raises, so the shim's presence is exercised,
not decorative.

**Phase 3 action:** ratify `P0002`/`P0003` as the corpus-wide `NO_DATA_FOUND`/
`TOO_MANY_ROWS` convention (used consistently by every pilot package with zero
deviation); assign real custom SQLSTATEs to `-20801`-style Oracle
`RAISE_APPLICATION_ERROR` codes and to `e_abort`-style unnumbered exceptions instead of
leaving them at PL/pgSQL's generic `P0001` default.

---

## XCUT-02 — `plog` as a UDP log shipper

**What the Phase 2 stub (`osag.osag_plog.sql`, `osag_plog.FINDINGS.md`) does and does
not do** — this is Phase 3's precise starting brief, not a design to imitate:

- Implements all **12** public procedure/function names and signatures Oracle declares
  (13th, `AuditUsage`, deliberately not created — see XCUT-06). Whatever XCUT-02 builds
  **must preserve this surface unchanged** — every pilot translation, and every later
  Phase 4 translation, already calls it by these names.
- Writes an observable row to `osag.plog_stub_log` instead of enqueuing onto Oracle AQ
  (`MCDB_MONITOR.plog_messages` via `DBMS_AQ.ENQUEUE`) — no queue exists in this stub or
  its target.
- **Does NOT port `PRAGMA AUTONOMOUS_TRANSACTION` + `COMMIT`.** This was the single most
  important constraint on the stub: a PostgreSQL `PROCEDURE` that runs `COMMIT` cannot be
  `CALL`ed from inside a `FUNCTION` body, and `pg_kind` is still provisional (XCUT-04) —
  a `COMMIT` in `plog` would have poisoned every FUNCTION that ever logs. Mechanically
  proven absent (a `pg_temp` `FUNCTION` that `CALL`s `osag.osag_plog_debug(...)` from
  inside its own body succeeds).
- **Does NOT implement `who_called_my_caller()`** (Oracle walks `dbms_utility.
  format_call_stack` text) — `caller` is always `NULL` in the stub. No PostgreSQL
  equivalent exists; XCUT-02 needs a real decision here, not a workaround.
- `AuditUsage` not created at all (XCUT-06's territory, not stubbed even as a no-op).

**The rollback-survival property the stub does NOT have, and the pilot therefore did NOT
test:** `osag.plog_stub_log` rows are written inside the caller's own transaction and are
**lost on `ROLLBACK`** — the direct consequence of not porting the autonomous
transaction. `osag_plog.FINDINGS.md` states this explicitly as a locked, deliberate
Phase 2 scope boundary ("pilot tests assert on plog output WITHOUT forcing a rollback").

**Fresh evidence this plan surfaced, beyond what the stub's own FINDINGS predicted:**
`REDGREEN-EVIDENCE.md`'s residual `auth.osag_auth` S-AUTH-007 failure (and the identical,
independently-found root cause in `tt.osag_notify.FINDINGS.md`) is a **live demonstration
of exactly the gap XCUT-02 exists to close**. PL/pgSQL's implicit-savepoint-on-EXCEPTION
semantics roll back a `plog` `INSERT` performed inside a handler that a caller's
`throws_ok`/`throws_like` then catches — a real PostgreSQL transaction fact, not a bug in
any pilot translation. A UDP `sendto()`, once sent, cannot be un-sent by a later
`ROLLBACK` — the moment XCUT-02 ships, this specific assertion shape starts passing on
its own, with no translation change required. **XCUT-02's own rollback-survival test
(Phase 3 success criterion 2) should use this exact scenario as its acceptance case.**

**Phase 3 action:** replace `osag_plog_log`'s (and, if warranted, `osag_plog_lograw`'s)
body with a UDP datagram send; decide what (if anything) replaces `osag.plog_stub_log` as
an assertable-by-tests sink (every pilot pgTAP test that queries it will need rewriting
if nothing does — flag this dependency explicitly when XCUT-02 is planned); restate the
no-transaction-control constraint for whatever replaces the stub.

---

## XCUT-04 — Transaction semantics / FUNCTION-vs-PROCEDURE

**The pilot's central finding: `TT.UTIL` COMMITs, and no pilot FUNCTION reaches it.**

`tt.util.close_old_dev_tickets` carries the corpus's only COMMIT this pilot exercised.
Three FUNCTIONs sit in call chains that might reach it — traced by full Oracle-body
read, not inference, for every one:

| Candidate FUNCTION | Full body traced | Calls any other package routine? | Reaches `TT.UTIL`? |
|---|---|---|---|
| `tt.ticket_interface_get_next_recent_ticket` | `ddl/src/pkgb/tt_ticket_interface.sql:1437-1465` | No — one `SELECT MIN(...)`, one `RETURN`, one `plog.err` on error | **No** |
| `tt.ticket_interface_replace_id_placeholders` | `ddl/src/pkgb/tt_ticket_interface.sql:1647-1657` | No — pure string manipulation | **No** |
| `tt.event_interface_ticket_type_for_event_type` | `ddl/src/pkgb/tt_event_interface.sql:833-861` | No — pure `IF`/`ELSIF` branching on the input | **No** |

**Verdict: zero FUNCTIONs anywhere in the pilot's static call graph transitively reach
any `TT.UTIL` routine, COMMIT-bearing or not** (`tt.util.FINDINGS.md`'s own cross-check,
extending `tt.ticket_interface.FINDINGS.md`'s within-package confirmation). This is an
input to XCUT-04's corpus-wide audit, not a substitute for it — a future `pg_kind`
reclassification, or a future caller that IS a FUNCTION, re-applies the hazard
immediately.

**`pg_kind` verdict — HELD for every row this pilot exercised.** `migration/README.md`'s
standing warning ("`pg_kind` is provisional... No downstream consumer should treat
`pg_kind` as settled") was tested live for the first time by this pilot, across all 76
public routines in the 6 translated packages:

- `tt.util`'s 5 routines: Oracle declares all 5 `PROCEDURE`; `name-map.csv` carries
  `pg_kind=procedure` for all 5; the translation creates all 5 as PostgreSQL `PROCEDURE`s
  (`prokind='p'`, verified live).
- `tt.ticket_interface`'s 2 `FUNCTION` rows (`get_next_recent_ticket`,
  `replace_id_placeholders`): both created as `prokind='f'`, matching `name-map.csv`.
- Every other pilot package's routines: no discrepancy found or reported in any of the 6
  packages' own FINDINGS files (each was checked against `name-map.csv`'s `pg_kind`
  column as part of translation; none flagged a mismatch).

**No `pg_kind` row needed changing.** If Phase 3's corpus-wide COMMIT audit ever DOES
need to flip a row, `migration/README.md`'s standing rule applies without exception:
that is a change to `migration/mapping/name_map.py` (the generator), never a hand-edit
to `name-map.csv` — this pilot found no case that required it, but the rule itself is
unaffected by that.

**Phase 3 action:** run the corpus-wide COMMIT/ROLLBACK audit (Phase 3 success criterion
6) using this pilot's traced FUNCTIONs as a positive control (3 FUNCTIONs, 3 confirmed
call chains, 0 hazards) and `tt.util.close_old_dev_tickets` as the one confirmed
COMMIT-bearing PROCEDURE.

---

## XCUT-05 — The two table-writing autonomous-transaction sites

`tt_util.close_old_dev_tickets` (one of the corpus's two) was translated and tested by
this pilot. `mcdb_checks_consistency.insert_result` (the other) was **not** touched —
`MCDB_CHECKS_CONSISTENCY` is outside the pilot's 6-package scope.

**What the pilot did:** Per `migration/spec/tt.util.md`'s own "Assumptions / Unresolved"
section (Phase 2's locked scope boundary, not reinterpreted by this plan): translated as
a plain PostgreSQL `PROCEDURE` with a **real `COMMIT`**, accepting the semantic delta —
neither the `dblink`/`pg_background` option (rejected, `.planning/research/PITFALLS.md`)
nor dropping the per-iteration commit (not chosen).

**The exact semantic delta, traced with evidence in `tt.util.FINDINGS.md`:**
- **Isolation from the caller is LOST.** Oracle's autonomous transaction cannot see the
  caller's uncommitted writes and its own `COMMIT` persists regardless of what the caller
  later does. PostgreSQL has one transaction per session — a `COMMIT` inside
  `close_old_dev_tickets` commits the caller's own prior, unrelated work too. A caller
  that expected to still roll back its own earlier writes after this call returns cannot.
- **Per-iteration commit granularity is PRESERVED** — a concurrent session sees each
  closed ticket become durably visible the moment its own iteration's `COMMIT` runs, same
  as Oracle. Only the isolation-from-caller property differs, not this one.

**What Phase 2 deliberately did NOT test, and why:** a rollback-survival test (start a
transaction, do an unrelated write, call `close_old_dev_tickets` via a nested path, roll
back the outer transaction, assert the unrelated write did NOT survive while the
procedure's own closures DID) is explicitly out of Phase 2 scope
(`migration/spec/tt.util.md`'s own text). `migration/test/regress/sql/tt__util__txn.sql`
only calls it as a bare top-level `CALL` — exactly the scenario where this translation's
behavior is indistinguishable from Oracle's, which is why the pilot's own tests could not
have caught the isolation-from-caller delta even if it were wrong.

**Phase 3 action:** make the explicit recorded decision Phase 3 success criterion 3
requires (UDP telemetry event / accept transactional semantics / dblink last resort) for
BOTH sites — `tt_util.close_old_dev_tickets` has a working baseline to compare against;
`mcdb_checks_consistency.insert_result` needs its own trace, not yet done. Write the
rollback-survival test XCUT-05 owns, using the exact scenario `tt.util.FINDINGS.md`
already describes.

---

## XCUT-06 — `AuditUsage` deletion

Per-package deletion counts, all confirmed by `grep -c AuditUsage` against the Oracle
body AND against the translation (zero remaining matches except the deletion note
itself, in every package):

| Package | Sites deleted | Basis |
|---|---|---|
| `auth.osag_auth` | 3 | one per routine (`delete_login`, `grant_role`, `grant_user_role`) |
| `mss.osag_dbprop` | 3 | one per routine (all 3 public routines) |
| `tt.event_interface` | 8 | one per public routine (private `is_esc_supp_active` never had one) |
| `tt.osag_notify` | 6 | Oracle body lines 335, 784, 861, 901, 953, 984 |
| `tt.ticket_interface` | 36 | one per routine for 36 of 38 public routines (2-arg `change_label` and `deleteTicket` never had one in Oracle source; 3 private routines never had one either) |
| `tt.util` | 6 | 5 public routines + private `despam_ticket` |
| **TOTAL** | **62** | |

**Reconciliation against the ~177 corpus-wide estimate (`02-CONTEXT.md`):** 62 sites
across 76 public + a handful of private routines in 6 of 48 packages (12.5% of packages)
accounts for **~35% of the corpus-wide estimate**. AuditUsage density is not uniform
across the corpus — the pilot's own density is close to **1 site per public routine**
(62 deletions / 76 public routines ≈ 0.82/routine, consistent with "one per routine" being
the modal pattern and the handful of routines with none being the exception, not the
rule). Phase 3 should reconcile the ~177 estimate against a **per-routine** density
figure (using this pilot's ~0.8/routine as a calibration point) rather than a flat
per-package average, since `TT.TICKET_INTERFACE` alone (36 sites, the corpus's largest
package by routine count) contributed more than half this pilot's total.

**Zero AuditUsage call sites remain in `migration/pgsql/` today** (confirmed:
`grep -c AuditUsage migration/pgsql/**/*.sql` matches only header-comment documentation
of the deletion, never code, in every one of the 6 packages).

---

## XCUT-03 — DBMS_*/UTL_* replacements

**Every Oracle vendor-package call site the pilot actually hit, and what replaced it:**

| Oracle built-in | Replacement | Package(s) | Validated against |
|---|---|---|---|
| `SUBSTRB` | `substr()` (native PostgreSQL) | `tt.event_interface`, `tt.ticket_interface`, `mss.osag_dbprop` | live execution, all pilot suites |
| `TO_NUMBER` | `oracle.to_number()` (orafce) | `tt.event_interface` | live execution |
| `INSTR` | `strpos()` (native) | `tt.event_interface` | live execution |
| `REGEXP_INSTR(text, pattern, position, occurrence, return_opt, modifiers)` (6-arg) | `oracle.regexp_instr` (orafce, same 6-arg signature) | `tt.util.check_dnids_tickets_to_resolve` | live execution against the exact argument shape used |
| `FROM_TZ(CAST(x AS TIMESTAMP), 'EUROPE/ZURICH')` | **Dropped** — the migrated PostgreSQL columns (`tt.ticket.ux_timeout_start`, `tt.event.eventdate`) are tz-naive `timestamp`, since ora2pg already dropped Oracle's `WITH TIME ZONE` when converting the schema. No zone-attach target exists to translate this to. | `tt.event_interface` | mechanical simplification, not a behavioral decision — flagged, not chosen |

**No `DBMS_*`/`UTL_*` call sites of any other kind were found anywhere in the pilot.**
Explicitly checked and recorded in 3 packages' own FINDINGS
(`grep -nEi "dbms_|utl_|auditusage"` → zero matches in `auth.osag_auth`,
`mss.osag_dbprop`, `tt.util`) and implicitly true of the remaining 3 (no such call is
mentioned in any of their FINDINGS or spec Assumptions sections). `dblink`/
`pg_background` — explicitly rejected candidates for XCUT-05 — are confirmed **absent**
from the pilot (`grep -nEi "dblink|pg_background"` → zero matches, `tt.util.FINDINGS.md`).

**Phase 3 action:** the orafce-vs-native decision this pilot made (native for
string/number primitives, orafce for `REGEXP_INSTR`'s exact 6-arg Oracle shape) should be
the corpus-wide default; no family the pilot touched needed per-call-site improvisation.

---

## Schema (Phase 5's brief) — pointer to `SCHEMA-FIXES.md`

Full ledger: `migration/test/SCHEMA-FIXES.md`. Headline, for anyone who does not open that
file: **`ddl/migrated/` shipped with NO `CREATE SEQUENCE` statements anywhere** (every
sequence lives only in `ddl/generated/sequences/*.sql`, Oracle syntax — 30 files, 309
sequences ported by `bootstrap/30_sequences.sql`), **and `tables.pg.sql`/`views.pg.sql`
both shipped with `\set ON_ERROR_STOP OFF`** (silently swallowing every broken statement
inside if loaded naively). Both would have ambushed Phase 5's from-scratch container
build with a "successful" load that was actually silently incomplete. Phase 5 must either
apply this pilot's fix files verbatim (`migration/test/bootstrap/30_sequences.sql`'s
sequence port, `migration/test/schema-fixes/10_ora2pg_fixes.sql`'s FK-type widenings and
reconstructed CHECK constraints, `bootstrap/10_schemas_roles.sql`'s `postgresadmin`
role/`checklist` schema provisioning) or fix the underlying ora2pg configuration and
regenerate — `SCHEMA-FIXES.md`'s own table states, per fix, which is more likely correct.

### CORRECTION to plan 02-11's finding — `auth.permission`/`auth.mv_service_access`

`migration/test/schema-fixes/23_p11_fixes.sql` (plan 02-11) and
`migration/pgsql/tt/event_interface.FINDINGS.md`'s "Deliberately NOT fixed" section both
stated that `auth.permission` "has no Oracle-side definition anywhere in
`ddl/export/schema.oracle.sql`" and that fixing it "would be an uninformed architectural
guess." **This plan verified that verdict is wrong.** Both `AUTH.PERMISSION` and
`AUTH.MV_SERVICE_ACCESS` are real materialized views with complete Oracle-side
definitions at `ddl/src/mviews/auth.sql`, already ora2pg-converted to
`ddl/migrated/mviews/auth.sql` — `build-template.sh` simply never loaded
`ddl/migrated/mviews/` (a scope boundary `SCHEMA-FIXES.md` itself already documented from
plan 02-09 forward, correctly labeled a scope boundary, not an error, at the time).

Loading it live surfaces exactly one defect: three of its four `CREATE INDEX` statements
are schema-qualified by ora2pg (`CREATE INDEX AUTH.IDX_... ON AUTH.MV_...`), which
PostgreSQL's grammar rejects (`ERROR: syntax error at or near "."` — an index always
lives in its table's own schema; there is no schema-qualified-index-name syntax at all).
A mechanical ora2pg emission bug, not an architectural unknown.

**Fixed:** `migration/test/schema-fixes/25_p13_fixes.sql` recreates all three MVs
verbatim from the ora2pg output with only the three index names de-schema-qualified.
Resolves `tt.ticket_interface`'s S-TICKET-005 `lives_ok` assertion (previously failing
with `relation "auth.permission" does not exist`).

**Residual, deliberately not resolved by this fix (flagged for Phase 3/5):** this
schema-fix ordering means the three MVs are populated with whatever base-table data
exists at template-CREATE time (empty — `masterdata/` loads afterward) and are **never
auto-refreshed** thereafter (PostgreSQL materialized views do not auto-refresh on
underlying writes; Oracle's `REFRESH FAST ON COMMIT` clause was already dropped by
ora2pg). Both MVs gate real authorization checks (`newticket_new`'s/`newevent_new`'s
company-wide-admin branch today; `mv_service_access`'s own header comment says it backs
broader RLS-style service-access checks not yet reached by any translated pilot routine).
A stale snapshot silently under- or over-granting access is a real, security-relevant
consequence — Phase 3/5 must decide a refresh strategy (cron / trigger-maintained /
convert to a plain always-current view) deliberately, not inherit the pilot's
convenient-for-testing default. See `migration/test/schema-fixes/25_p13_fixes.sql`'s own
trailing comment for the full option list.

---

## Roadmap question — `SYS.OSAG_TABLE_REDEFINITION`

`SYS.OSAG_TABLE_REDEFINITION` was rejected from the pilot as Oracle-specific
(`DBMS_REDEFINITION`, 43 package-state variables, no PostgreSQL analogue) — a decision
made before this plan, not revisited here. **Whether it belongs in the milestone at all
is an open question the user flagged**, and it is raised here explicitly, as instructed,
so the roadmap answers it deliberately rather than Phase 4 discovering a package it
cannot mechanically translate partway through wave-ordered execution. No recommendation
is made in this document — this is a scoping decision for whoever owns the roadmap, not
a technical finding this plan is positioned to resolve.

---

## Regress-golden formatting policy (this plan's own open item, and why it is not applied)

Four `CONTEXT:`-line diffs (`tt.event_interface`, `tt.osag_notify`, `tt.ticket_interface`
×2 sites) and one trailing-whitespace diff (`tt.util`) remain in the regress goldens —
every one substance-identical (`ERROR:`/`NOTICE:` text and SQLSTATE match exactly; only
`CONTEXT:` line numbers/phrasing, or one trailing space, differ). Full breakdown:
`migration/test/REDGREEN-EVIDENCE.md`'s "Regress formatting diffs" section.

**Recommended policy: regenerate the 5 goldens** to match the current, verified-correct
translation output. Filtering `CONTEXT:` lines out of `run-tests.sh`'s comparison was
considered and rejected — it would weaken the harness's own diff contract for every
FUTURE package too, a much bigger blast radius than fixing 5 already-stale files, and it
would still leave the `tt.util` trailing-whitespace diff unaddressed (not a `CONTEXT:`
line at all).

**This plan does NOT implement that regeneration.** Every regress golden lives under
`migration/test/regress/expected/`, which this plan's own critical operating constraints
place off-limits to its executor (the same anti-circularity wall that protects
`migration/test/pgtap/` — `provenance_lint.sh`'s enforcement is scoped to translation
commits, but the constraint given to this plan's executor is broader and unconditional).
Regenerating a golden is exactly the kind of test-file edit this plan is required to
document with evidence and hand to the orchestrator for adjudication, not perform
unilaterally — even though, unlike the `tt.ticket_interface` pgTAP fixture defects, this
one is not a defect in the test's INTENT (the goldens were correct when written; the
translation's own line numbers/signatures simply moved since), so the appropriate action
really is "regenerate," not "amend." Flagged here as an explicit, adjudicated action
item — not silently deferred without a decision, per this plan's own mandate.

---

## Summary table — every FINDINGS file represented above

`osag.osag_plog` (stub, XCUT-02), `mss.osag_dbprop` (XCUT-01/03/04), `auth.osag_auth`
(XCUT-01/04/06), `tt.util` (XCUT-01/03/04/05/06), `tt.osag_notify` (XCUT-01/02/06),
`tt.event_interface` (XCUT-01/03/04/06, schema gaps), `tt.ticket_interface`
(XCUT-01/04/06, schema gaps, the vacuous-test/mutation evidence in
`REDGREEN-EVIDENCE.md`). See `migration/spec/METHOD-REVIEW.md` for the verdict on
whether the method that produced all of the above is fit to run 44 more times.
