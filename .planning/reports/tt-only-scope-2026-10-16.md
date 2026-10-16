# TT-only migration — scope, open questions, remaining code, Oracle-side needs

Branch `phoenix/migrate_tt_only`, 2026-10-16. Filters the 2026-10-13 status report
(`status-report-2026-10-13.html`) and the TT-callers report (`tt-callers-2026-10-14.html`)
down to what matters when **only the ticketing schemas move** — `TT` (34 tables,
7 packages, 2 triggers, 3 jobs) and `TICKETEVOLUTION` (3 tables, 1 package, 1 job) —
and everything else stays on Oracle 19c. Every "decided" item below was decided on this
branch and is implemented in the commits listed in section 6.

## 1. What applies to the Ticket-only part

From the status report, in scope and carried over unchanged:

- The four big TT translations (TICKET_INTERFACE 38 routines, EVENT_INTERFACE 8,
  OSAG_NOTIFY 6, UTIL 5 — 5,748 Oracle body lines) with their specs and 192 assertions.
- The TT dependency closure: MSS.OSAG_DBPROP (green), OSAG.OSAG_PLOG (stub), and the
  three untranslated leaves TT.ESCALATION_INTERFACE, MSS.OSAG_IP, OSAG.OSAG_MSG.
- The 9 red items (4 fixtures, 4 goldens, S-AUTH-007) — all TT except S-AUTH-007.
- Phase 3 cross-cutting items that touch TT files: exception codes (Q4), plog (Q5),
  autonomous transactions (Q6), dev-instance detection (Q7), pg_kind (Q8), dynamic-SQL
  allowlist (Q9), private naming (Q10), Oracle bugs (Q11), empty strings (Q15).

**Not** in the TT-only scope (stays on Oracle, nothing to translate now): AUTH.OSAG_AUTH
(pilot translation stays on the branch as a worked example but is not deployed), the
auth materialized views (Q12), SYS.OSAG_TABLE_REDEFINITION (Q13), grant_role dead code
(Q14), every wave-4/5 caller of TT (section 4 covers what *they* need instead).

**The structural finding the status report did not make:** TT is not a leaf schema.
`ddl/migrated/constraints/fk-constraints.pg.sql` has **22 foreign keys from 12 other
schemas into TT** (`tt.ticket.id` from CERTS, CHECKLIST, FW×3, FYI, MC×3, MCAUDIT, MSS,
NIDS, PRX, TIM×2; `tt.event.id` from MC×2, NIDS; two TT lookup tables from MSS) and
**25 from TT out to STOP/MSS/AUTH/MC**; the TT routines read 31 non-TT tables, and
`deleteTicket` writes 13 non-TT tables. "TT-only" therefore means: TT tables + code on
PostgreSQL, **replicated reference data** (stop.company/contact/company_unit, mss.host,
deleted_host, service, service_type, service_component, software_release, key,
host2service, isp_link, address/city/country, v_host_key_value, auth.login,
auth.permission, auth.mv_service_access, mc.mc_file, mc.isp_link_history,
mc.connection_interrupt_open, guma2.suppressed_signature) Oracle → PostgreSQL, and a
**bridge** in both directions for the writes. Design and drafts:
`migration/oracle_side/README.md`.

## 2. Questions — answered on this branch, and the ones still needing you

### Answered (decision + where it is implemented)

| Q | Decision | Where |
|---|---|---|
| Q1 fixtures | Yes, amended (A-009: 5 fixtures, not 4 — test #3's ticket is 907011, the report's "907012" was its neighbour). `selectinto.sql` 16/20 → 20/20; tt.ticket_interface 129/129. | `1582555`, ledger entry below |
| Q2 goldens | Regenerated, not filtered. The osag_notify DETAIL row is masked with `\set VERBOSITY terse` around that one statement (A-010). All 6 regress files match. | `1582555`, `84c0c4b` |
| Q3 S-AUTH-007 | Left red on purpose: AUTH stays on Oracle in this split, and the assertion is the natural acceptance test for the Phase 3 plog rollback-survival requirement. | — |
| Q4 exception codes | P0002/P0003 ratified; custom SQLSTATE class `OS` + last three digits of the Oracle code (`OS980` ticket_closed — already in use; `OS981/OS982` reserved, Oracle never raises them either; `OS801` unknown dbprop applied). Message-parity shim stays until the last Oracle client is gone. The two TT `*_STATE` packages need no PostgreSQL object. | `migration/mapping/sqlstate-map.md`, `b13cba3` |
| Q7 dev instance | GUC `mcdb.instance_role` (`ALTER DATABASE ... SET mcdb.instance_role = 'dev'`); the test GUC `mcdb.force_dev_instance` still honoured. | `e63792d` |
| Q9 allowlist scope | **Narrow** (the four TT.ESCALATION_INTERFACE routines). Evidence: every value in `masterdata/TT/event_action.csv` and `mss.key` 139/140/399 (incl. the `regexp` validation column) names one of them, and the key regexps themselves forbid anything else. The dynamic edge is now in the dependency graph (`dynamic_edges.json`), ESCALATION_INTERFACE joined the TT cycle group. | `0c6cd59` |
| Q10 private naming | Confirmed: `schema.package__routine` + `REVOKE ALL FROM PUBLIC`, used by all new translations. | agents' FINDINGS |
| Q11 Oracle bugs | **Corrected, not mimicked** (project owner's instruction on this branch), each annotated `DEVIATION(ORACLE-BUG)` at the site, in FINDINGS and in the spec as corrected behaviour. In new translations (ESCALATION_INTERFACE's null-ticket escalation, OSAG_IP's unhandled VALUE_ERROR, CALCULATOR's 60-days-for-60-seconds) — see section 3. For the four already-translated items (moveevent p_event_id, add_status_change_event cust_id, expire_status doc/body, remove_related_file guard): see "Still open" — a second wave on this branch. | agents' FINDINGS |
| Dynamic-SQL cycle | TT.ESCALATION_INTERFACE ↔ TT.EVENT_INTERFACE added to the graph and `known_cycles.json` (now one 5-member TT group, wave 3). | `0c6cd59` |
| Template staleness | Content-hash hard gate in `run-all.sh` (inputs hashed, stored as the template's COMMENT, auto-rebuild on mismatch). | `f7eac3e` |
| DB-name allowlist | `^mcdb_(test|tmpl|harness)[a-z0-9_]*$` now documented in `.claude/CLAUDE.md`. | this branch |
| Jobs | The 4 DBMS_SCHEDULER jobs become pg_cron schedules (guarded file). | `1131a1b` |

### Still needing an answer from you (TT-relevant only)

- **Q5 plog.** Still the Phase 3 UDP-shipper decision. Impact on TT: every TT routine logs;
  tests assert on `osag.plog_stub_log`. *Recommendation:* keep the table sink as the
  **test** implementation permanently (it is what makes log assertions possible) and
  ship a second body for production that also sends the datagram; same signatures.
  Needs: host/port/format of the receiver.
- **Q6 autonomous transactions.** `tt.util_close_old_dev_tickets` as plain PROCEDURE +
  real COMMIT (option 1) stays. It is dev-only and scheduled nowhere (Oracle never
  scheduled it either), so the delta is acceptable; *recommendation:* accept, no dblink.
- **Q8 pg_kind.** Treat `name-map.csv`'s pg_kind as final for the TT closure: the only
  FUNCTIONs (ticket_type_for_event_type, replace_id_placeholders,
  get_next_recent_ticket, is_notify_suppressor_active, the 7 OSAG_IP functions) have no
  DB writes and reach no COMMIT. Confirm.
- **Q15 empty strings.** Can `tt.ticket.customer_reference` / `tt.event.details_public`
  hold `''` in production? The translations normalise at the boundary either way; a
  "no" lets Phase 4 drop that pattern. Only you (or a production query) can answer.
- **NEW — transport.** The Oracle-side bridge is drafted as a synchronous HTTPS call
  (`UTL_HTTP` → `tt-bridge` → `CALL`), see `migration/oracle_side/README.md` for why not
  DB links / outbox. The `tt-bridge` service itself is a ~100-line shim outside this
  repo. Confirm the shape, or name the existing ticketing API (`SVC_API_TICKETING`
  suggests one exists) that should take this role.
- **NEW — reference-data replication direction and cadence** for the 21 non-TT tables
  TT reads (section 1). Logical replication is not available from Oracle; a periodic
  copy by the same bridge is proposed. Acceptable staleness?
- **NEW — cross-schema cascades.** `deleteTicket` (13 statements) and `merge_tickets`
  (1) write Oracle-side tables. Drafted as callbacks `TT.BRIDGE_CALLBACK.on_ticket_deleted
  / on_tickets_merged`. Confirm that `deleteTicket` is even reachable in production
  (no caller in the corpus; only direct-grant accounts could call it).

## 3. Code that still needs migration (TT closure)

| Object | Lines | Status on this branch |
|---|---|---|
| TT.ESCALATION_INTERFACE (5 routines) | 223 | **translated** (spec `tt.escalation_interface.md`, pgTAP + regress, `migration/pgsql/tt/escalation_interface.sql`) — see agent FINDINGS for the corrected null-ticket behaviour |
| MSS.OSAG_IP (7 functions + 2 private) | 323 | **translated** (IMMUTABLE; the 17 Oracle unit-test cases became pgTAP assertions; numeric not bigint for the IPv6 halves) |
| OSAG.OSAG_MSG (2 procedures) | 97 | **translated as an outbox** (`osag.msg_outbox`; SMTP delivery moves to an external shipper — UTL_SMTP has no in-database equivalent) |
| TICKETEVOLUTION.CALCULATOR (2 procedures) | 214 | **translated** (materialize_incremental = PROCEDURE + COMMIT, top-level CALL only) |
| TT.TICKET_UPDATE_TRG, TT.TODO_ITEM_UPDATE_TRG | 16 | **translated** (trigger functions + triggers; harness tooling extended to trigger objects) |
| TT.EVENT_INTERFACE_STATE, TT.TICKET_INTERFACE_STATE | 12 | **no object needed** — `sqlstate-map.md` |
| 4 scheduler jobs | — | `_support/30_pg_cron_jobs.sql` |
| Names stored in data (event_action, dbprop keys 139/140/399) | — | `pgmig.apply_data_name_rewrites()` — verified on the template: 1 + 3 + 2 rows rewritten |
| Q11 corrections in the already-translated packages | — | **open** (second wave, see section 6) |
| OSAG.OSAG_PLOG real implementation | 211 | Phase 3 (Q5) |

Measured after the merge of the three agent branches: see section 6 for the run-all
table.

## 4. Code that stays on Oracle and needs stubs / external calls / pruning

Full detail with line numbers: `migration/oracle_side/README.md`. Summary:

| Oracle package | What it needs | Delivered as |
|---|---|---|
| MC.MONITORING_TICKET_PROCESSES | 5 TT routines (7 call sites), 3 direct selects | stubs → bridge; `tt.v_event_min`/`tt.v_ticket_min` replicas; **edit 3 SQL sites** |
| NIDS.OSAG_NIDS | 4 TT routines (4 sites), maintenance-window join ×2, event_type name ×1 | stubs → bridge; `ticket_type_for_event_type` kept local (pure); `tt.v_host_maintenance`, `tt.event_type_ref`; **edit 3 SQL sites** |
| GUMA2.SECONDARY_ISP / GUMA2.OSAG_GUMA / OSIXINFO.OSAG_HARDWARE | `newevent_new` (4 sites), 1 cursor on tt.ticket | stub → bridge; `tt.v_ticket_min`; **edit 1 SQL site** |
| AUTH.OSAG_AUTH.delete_login | `osag_notify.delete_notifications_for_login` | stub → bridge |
| MC.MONITORING.has_active_SW, MC.OSAG_MAINTSYNC (4 sites) | the 5-table join, read-only | `tt.v_host_maintenance` (one view replaces 7 copies); **edit 5 SQL sites** |
| MC.V_HOST_CONNECTION_STATUS | `tt.event.ticket_id` | `tt.v_event_min` |
| BIREADER.V_TT_* (12 views) | TT tables | **drop**; BIREADER gets a PostgreSQL role |
| 31 service accounts with direct TT grants | tables + package EXECUTE | **move to PostgreSQL** (`ddl/migrated/grants/*.sql` restricted to TT; package EXECUTE fanned out via `rewrite_names.py --report` P1 items; client SQL through `client-rename.sed`) |
| Inbound FKs (22) | — | **drop** (`prune.sql` step 3); integrity via `TT.BRIDGE_CALLBACK` |
| TT.UTIL, the 4 jobs, the 2 triggers, the two `*_STATE` bodies | — | **prune** (no external caller) |
| SYS.OSAG_TABLE_REDEFINITION, auth MVs, grant_role | — | untouched (not TT) |

## 5. The rename tooling (the "routines that go through an existing code base")

`migration/mapping/rewrite_names.py` (stdlib Python, 18 unit tests) rewrites, reading
only `name-map.csv`:

- R1 `SCHEMA.PACKAGE.OBJECT` → `schema.package_object` (quoted/unquoted, any case,
  whitespace, and the `\.`-escaped form found inside regexes stored in data);
- R2 dynamically fabricated prefixes `'tt.escalation_interface.' || v` →
  `'tt.escalation_interface_' || v` (reported so the run-time suffix can be checked);
- R3 public-synonym forms `plog.err` → `osag.osag_plog_err`;
- R4 bare same-schema forms `event_interface.addevent_new` (ambiguous only for
  OSAG_IMPLICATION → `--default-schema`);
- R5 (opt-in) `BEGIN pkg.proc(...); END;` → `CALL schema.pkg_proc(...);` for procedures.

It **reports** package-only references (`GRANT EXECUTE ON tt.ticket_interface`) with
their routine expansion, and package members without a name-map row (types,
`*_STATE` constants — 63 such sites in the Oracle corpus, all `*_STATE`/type refs).
Dry-run on a copy of all 42 Oracle package bodies: no ambiguous bare reference, every
three-part call resolved.

Deliverables generated from it: `client-rename-map.csv` (346 rows: routine, synonym,
dynamic-prefix), `client-rename.sed` (GNU sed, verified in the unit suite), and the
in-database twin `pgmig.rewrite_oracle_names(text)` + `pgmig.apply_data_name_rewrites()`
(`migration/pgsql/_support/`), verified live against the template database. Error-code
rewrites for clients (`SQLCODE = -20980` → `SQLSTATE = 'OS980'`) are in
`sqlstate-map.md`.

## 6. Result on this branch (final run of `migration/test/run-all.sh`, head `3b105ba`)

Gates: spec_lint 12/12, trace_lint 27/27, provenance_lint 12/12 OK. Template hash gate
current. Unit suites (analyze, mapping, spec, test/lib) OK.

| Package | pgTAP | Regress | Result |
|---|---|---|---|
| _canary.canary | 2/2 | 1/1 | PASS |
| _support.pgmig (name rewriter, PostgreSQL twin) | 10/10 | — | PASS |
| auth.osag_auth | 9/10 | — | FAIL — S-AUTH-007, kept red on purpose (Q3; AUTH stays on Oracle) |
| mss.osag_dbprop | 10/10 | 1/1 | PASS |
| mss.osag_ip (new) | 108/108 | — | PASS |
| osag.osag_msg (new, outbox) | 63/63 | — | PASS |
| ticketevolution.calculator (new) | 62/62 | 1/1 | PASS |
| tt.escalation_interface (new) | 74/74 | 1/1 | PASS |
| tt.event_interface (+Q11 a) | 30/30 | 1/1 | PASS |
| tt.osag_notify | 23/23 | 1/1 | PASS |
| tt.ticket_interface (+Q11 b, d) | 144/144 | 1/1 | PASS |
| tt.ticket_update_trg (new) | 17/17 | — | PASS |
| tt.todo_item_update_trg (new) | 12/12 | — | PASS |
| tt.util | 10/10 | 1/1 | PASS |
| **Total** | **574/575** | **8/8** | 13/14 |

Before this branch (status report 2026-10-13): 199/204 pgTAP, 2/6 regress, 2/7 packages.
The TT closure is now fully translated and tested except the real plog implementation
(Phase 3) — every TT package, both triggers, the TICKETEVOLUTION package, and the two
leaf dependencies MSS.OSAG_IP and OSAG.OSAG_MSG.

### Corrections of Oracle behaviour made on this branch (all annotated `DEVIATION(ORACLE-BUG)`)

| Routine | Oracle behaviour | Corrected to | Spec clause |
|---|---|---|---|
| escalation_interface.escalate_os / escalate_customer | one shared NO_DATA_FOUND handler let a nonexistent event fall through to `UPDATE … WHERE id = NULL` and `addevent_new(NULL ticket)` (silently swallowed) | log via plog.err and RETURN with no side effects; "no host → escalate anyway" kept | S-ESC-008, S-ESC-014 |
| osag_ip.ip2num | `'1.a.3.4'` raised ORA-06502; `'1.2.3.4.5'` returned 16909060.5 | NULL | S-IP-008, S-IP-009 |
| osag_ip.num2ip / num2ipv6 / ipv6left/right | `num2ip(1.5)='0.0.0.1.5'`; malformed IPv6 raised or returned half a result; negatives/`NULL` gave `'####'`/`'::'` | NULL, never raise; IPv6 halves as numeric (2^64−1 > bigint) | S-IP-014, 020, 023 |
| osag_msg.send_mail/send_sms | UTL_SMTP at call time; `send_sms(NULL)` mailed `'@mx-sms.open.ch'` | durable `osag.msg_outbox` row (delivery by an external shipper, only for committed work); empty number rejected and logged | S-MSG-012, 013 (PLATFORM) |
| calculator.materialize_tickev | "60s margin" implemented as `date_from + 60` = 60 **days**; date_to chaining also stretched the pseudo `'new'` row | `interval '60 seconds'`; chaining restricted to the row of the last status | S-TICKEV-011, 009 |
| event_interface.moveevent | ignored `p_event_id` (Oracle comment: "BROKEN, never run") — moved every event of the old ticket | moves exactly the event `p_event_id` from `p_oldticket_id`; existing swallow semantics kept | S-EVENT-046/047 |
| ticket_interface.add_status_change_event (private) | never assigned `cust_id` → every status-change audit event had `company_id = NULL` | resolves `tt.ticket.company_id` like the sibling audit helpers | S-TICKET-059 |
| ticket_interface.remove_related_file | no same-company guard (add_related_file has one) | symmetric guard; cross-company detach is logged and refused | S-TICKET-060 |
| ticket_interface.expire_status | doc says it calls change_label; body does not | **kept** — the only caller passes the ticket's own current label (a no-op); stale documentation, evidence in S-TICKET-021 / FINDINGS | — |

Not corrected, by evidence: escalate_customer's body (status 10 / event 60001) vs its
comment (customer escalation 60101/20) — body authoritative, mismatch recorded
(S-ESC-012). ipv6shorten never collapses a *leading* run of exactly two zero groups —
preserved as a quirk, not a bug.

### Commits

57 commits from `1b14c64` to `3b105ba` on `phoenix/migrate_tt_only`: four agent branches
(ESCALATION_INTERFACE; OSAG_IP + OSAG_MSG; CALCULATOR + triggers + trigger-aware
tooling; Q11 corrections) merged with `--no-ff`, each following the spec → RED test →
translation commit order that `provenance_lint.sh` enforces, plus the orchestrator's
tooling/decision commits listed in section 2. Test-amendment ledger entries on this
branch: A-009, A-010 (orchestrator), A-012–A-014, A-018 (Q11), A-015, A-016 (OSAG_IP/MSG),
A-017 (CALCULATOR); A-011 is unused.

### What is still open after this branch

1. Q5 plog, Q6/Q8 confirmations, Q15, and the three NEW questions in section 2.
2. The `tt-bridge` service and the Oracle-side files (`migration/oracle_side/`) have never
   run against Oracle — they need the dev instance.
3. `deleteTicket`/`merge_tickets` still carry their 14 cross-schema statements in the
   PostgreSQL translation; they need the callback hook once the bridge exists.
4. Reference-data replication Oracle → PostgreSQL for the 21 non-TT tables (section 1).
5. Phase 5 items unchanged (ora2pg sequence gap, `\set ON_ERROR_STOP OFF`, FK file choice,
   regenerate `ddl/migrated` from the current baseline).
