---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
current_phase: 02
current_phase_name: spec-method-test-harness-pilot
status: executing
stopped_at: Completed 02-07-PLAN.md (TT.TICKET_INTERFACE spec)
last_updated: "2026-07-25T17:25:45.822Z"
last_activity: 2026-07-25
last_activity_desc: Phase 02 execution started
progress:
  total_phases: 5
  completed_phases: 1
  total_plans: 15
  completed_plans: 13
  percent: 20
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-07-10)

**Core value:** Every translated PostgreSQL object behaves like its Oracle original, proven by tests derived from the Oracle code's specification — not just "compiles cleanly."
**Current focus:** Phase 02 — spec-method-test-harness-pilot

## Current Position

Phase: 02 (spec-method-test-harness-pilot) — EXECUTING
Plan: 1 of 13
Status: Executing Phase 02
Last activity: 2026-07-25 — Phase 02 execution started

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**

- Total plans completed: 0
- Average duration: —
- Total execution time: 0.0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**

- Last 5 plans: —
- Trend: —

*Updated after each plan completion*
| Phase 01 P01 | 20min | 2 tasks | 7 files |
| Phase 01 P02 | 16min | 3 tasks | 11 files |
| Phase 02 P03 | 30min | 3 tasks | 12 files |
| Phase 02 P04 | ~2h | 3 tasks | 10 files |
| Phase 02 P05 | ~2h | 3 tasks | 5 files |
| Phase 02 P06 | 45min | 3 tasks | 4 files |
| Phase 02 P07 | 2.5h | 3 tasks | 1 files |
| Phase 02 P08 | 95min | 3 tasks | 5 files |
| Phase 02 P09 | ~3h | 3 tasks | 9 files |
| Phase 02 P10 | 50min | 2 tasks | 3 files |
| Phase 02 P11 | 3h10m | 3 tasks | 4 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Roadmap]: Spec-first — specs derived from Oracle source by static analysis; tests verify specs, never the translation's own assumptions
- [Roadmap]: Translation order comes from the Phase 1 dependency graph (leaf-first waves), never file-alphabetical or Liquibase include order
- [Roadmap]: Cross-cutting semantics (exception map, plog autonomous transactions, DBMS_*/UTL_* replacements, COMMIT/ROLLBACK → PROCEDURE) settled once in Phase 3 before bulk translation
- [Roadmap]: `package_in_name` naming kept from prototype; the name-mapping table is the single source of truth for refactors, test names, and client regexps
- [Roadmap]: ora2pg output is raw material and a completeness checklist only — never shipped unverified
- [Phase ?]: schemas count is 23 (not the plan's stated 21) -- ddl/src/triggers/APPID.sql and STOP.sql declare objects in schemas absent from every package spec; hard-gated on the lexer-derived truth
- [Phase ?]: reconcile() recomputes structural counts live from result['objects'] rather than a precomputed snapshot, so --check can actually detect a removed object
- [Phase ?]: Real corpus has exactly one name collision (the legitimate TT.TICKET_INTERFACE.change_label overload); overrides.csv ships empty since the collision gate's hard-fail path is proven via synthetic fixtures
- [Phase ?]: Two genuine mutual-recursion cycle groups verified against source and accepted into known_cycles.json: MC.MONITORING<->MC.MONITORING_TICKET_PROCESSES, and TT.EVENT_INTERFACE/OSAG_NOTIFY/TICKET_INTERFACE/UTIL
- [Phase ?]: depgraph.py derives its synonym index from name-map.csv's oracle_synonym column rather than re-parsing inventory.json synonyms, keeping synonym resolution a single source of truth
- [Phase ?]: tables/constraints.pg.sql (843 FK, non-deferrable) skipped in favor of constraints/fk-constraints.pg.sql (deferrable) -- avoids 843 duplicate-constraint errors and matches the masterdata loader's SET CONSTRAINTS ALL DEFERRED strategy
- [Phase ?]: postgresadmin role + checklist schema (2 ora2pg gaps) fixed in bootstrap/10_schemas_roles.sql, not schema-fixes/ -- they must exist before tables.pg.sql can even attempt the statements that need them
- [Phase ?]: masterdata NULL sentinel is the literal quoted token NULL, not an empty CSV field -- evidence-based (grep-verified), overturning the plan's own assumption; implemented via COPY NULL 'NULL' + FORCE_NULL
- [Phase 02]: TT.UTIL's autonomous-transaction/COMMIT decision deferred to XCUT-05, pg_kind finalization to XCUT-04 -- spec documents 3 candidate PostgreSQL behaviors without choosing one
- [Phase 02]: mss.v_host_key_value substitute view (transaction-scoped, test-only) created for DBPROP pgTAP suite since the real mview-backed view is out of scope for mcdb_tmpl per 02-03
- [Phase ?]: TT.OSAG_NOTIFY private-routine naming: double-underscore prefix (tt.osag_notify__<name>) + REVOKE ALL FROM PUBLIC, flagged as a Phase 4/name-map-generator decision, not yet final
- [Phase ?]: TT.OSAG_NOTIFY: TOO_MANY_ROWS is never caller-observable as a raised exception anywhere in this package -- both structurally-reachable sites swallow it; tests assert on return value/plog content instead
- [Phase 02]: Carried DYNAMIC-SQL-TRACE.md's EXECUTE format() verdict into tt.event_interface.md unchanged, including its own UNRESOLVED allowlist-scope sub-item
- [Phase 02]: Closed the plan's flagged FUNCTION/PROCEDURE question: ticket_type_for_event_type has zero DB access, so no COMMIT hazard via TT.UTIL
- [Phase 02]: TICKET_INTERFACE public_routines front-matter set to 37 (dedup) to match spec_lint.py's name-keyed inventory check; both change_label overloads remain fully specced as distinct routines — spec_lint.py cross-checks front-matter public_routines against inventory.json's routine NAME set, which collapses the change_label overload pair to one entry
- [Phase ?]: TT.TICKET_INTERFACE RED suite: both change_label overloads dispatched and asserted distinctly (not just called twice)
- [Phase ?]: Site #20's multi-row (TOO_MANY_ROWS) fixture is unconstructible in ddl/migrated's schema due to an immediate UNIQUE(ticket_id) index on tt.service_window -- covered with the single-row positive case only, flagged for Phase 4/5
- [Phase ?]: close_old_dev_tickets translated as plain PROCEDURE + real COMMIT (option 1), accepting the semantic delta from Oracle's autonomous transaction; XCUT-05 owns the final call
- [Phase ?]: no data found message-parity shim: transparent WHEN NO_DATA_FOUND re-raise with corrected text only, no control-flow change, applied corpus-wide pending XCUT-01
- [Phase ?]: Traced all 3 XCUT-04 candidate FUNCTIONs full-body: none transitively reaches TT.UTIL's COMMIT today
- [Phase ?]: Applied the established 'no data found' message-parity shim only at externally-reachable unhandled NO_DATA_FOUND sites, matching the spec's XCUT-01 requirement without unverifiable scope creep.
- [Phase ?]: Did not touch any file under migration/test/ despite finding 4 reproducible test-file defects (pgTAP throws_ok overload footgun, off-by-one plan() count, missing fixture row, non-deterministic golden DETAIL text); documented with proposed fixes in FINDINGS.md instead.
- [Phase ?]: TT.EVENT_INTERFACE dynamic-SQL site (Oracle line 971) translated as EXECUTE format() with a narrow TT.ESCALATION_INTERFACE allowlist gate placed outside the Oracle-fidelity swallow handler; the trace's broader-vs-narrower allowlist-scope question remains unresolved for Phase 4
- [Phase ?]: tt.event/tt.ticket.contact_zitadel_id schema gap (changelog-current.sql applied but missing from ddl/migrated's frozen export baseline) fixed via additive schema-fix; build-template.sh generalized to load all schema-fixes files

### Pending Todos

None yet.

### Blockers/Concerns

- No live Oracle 19c instance — specs are static-analysis-derived; every spec must carry an explicit "assumptions / unresolved" section. Empirical validation deferred to v2 (ORA-01).
- Autonomous transactions: 3 packages use PRAGMA AUTONOMOUS_TRANSACTION with no PostgreSQL equivalent. Phase 3 must land dblink/pg_background before dependent packages translate.
- Dynamic SQL (EXECUTE IMMEDIATE, DBMS_SQL) may leave call edges unresolvable in the Phase 1 dependency graph — must be flagged, not silently omitted.

## Deferred Items

Items acknowledged and carried forward from previous milestone close:

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| *(none)* | | | |

## Session Continuity

Last session: 2026-07-14T22:09:52.119Z
Stopped at: Completed 02-07-PLAN.md (TT.TICKET_INTERFACE spec)
Resume file: None
