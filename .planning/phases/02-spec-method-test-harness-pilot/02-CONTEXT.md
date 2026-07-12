# Phase 2: Spec Method, Test Harness & Pilot - Context

**Gathered:** 2026-07-12
**Status:** Ready for planning
**Source:** Direct user decisions during /gsd-plan-phase 2

<domain>
## Phase Boundary

Phase 2 proves the spec-first methodology end-to-end at small scale. It delivers:
- The dual test harness (pgTAP + plain-SQL expected-output) running against local PostgreSQL 17.10
- The uniform spec format and checklist (SPEC-02, SPEC-03)
- A pilot batch of real packages specified, translated, and verified green — red-before/green-after

It does NOT deliver bulk translation (Phase 4) or the final cross-cutting decisions (Phase 3).
The pilot's purpose is to prove the method, not to claim translation coverage.

</domain>

<decisions>
## Implementation Decisions

### Pilot batch — LOCKED (user override of "draw from wave 1")

The roadmap said "pilot packages (3-5, drawn from wave 1)". The user overrode this deliberately:
wave 1 is dominated by trivial constants-only `*_STATE` packages (0 routines) that would prove
nothing about the method. The pilot uses **representative real-life packages** instead:

| Package | Wave | Public routines | Notes |
|---------|------|-----------------|-------|
| `AUTH.OSAG_AUTH` | 4 | 3 | static: complete |
| `MSS.OSAG_DBPROP` | 2 | 3 | static: complete |
| `TT.EVENT_INTERFACE` | 3 | 8 | static: **incomplete** (dynamic SQL) |
| `TT.TICKET_INTERFACE` | 3 | **38** | static: complete; **ALL 38 routines in scope** (user-confirmed) |

**`SYS.OSAG_TABLE_REDEFINITION` is explicitly rejected from the pilot** — it is Oracle-specific
(DBMS_REDEFINITION, 43 package-state vars) and has no meaningful PostgreSQL analogue. Consider
whether it belongs in the milestone at all; flag for the roadmap, do not pilot it.

### Transitive dependencies — the pilot pulls in 3 more packages

The 4 pilot packages do not stand alone. Their call edges (from Phase 1's depgraph) require:

| Dependency | Wave | Public routines | Why it's needed |
|------------|------|-----------------|-----------------|
| `OSAG.OSAG_PLOG` | 1 | 13 | Called by ALL 4 pilot packages on error paths |
| `TT.OSAG_NOTIFY` | 3 | 6 | Called by OSAG_AUTH, EVENT_INTERFACE, TICKET_INTERFACE; 30 SELECT INTO sites |
| `TT.UTIL` | 3 | 5 | Called by EVENT_INTERFACE, TICKET_INTERFACE; has COMMIT + autonomous transaction |

The planner must decide how far to translate these (full translation vs. minimum needed to make
the pilot's specs testable) and say so explicitly. They are NOT free.

**`TT.EVENT_INTERFACE` ↔ `TT.TICKET_INTERFACE` are mutually recursive** — one of the two accepted
cycle groups in `migration/analyze/known_cycles.json`. They cannot be translated in strict
dependency order; they must land together. The pilot is therefore also the first real test of the
cycle-group handling that Phase 1 built.

### plog handling — LOCKED

**Stub `plog` as a simple log-writing/printing package.** Defer the UDP shipper to Phase 3.

The pilot needs *some* plog to exist because every pilot package calls it on error paths. Build the
simplest thing that works — write/print the log line — and make it observable enough that a test can
assert "this error path logged X". Do NOT build the UDP datagram emitter here; that is Phase 3's
XCUT-02, and its rollback-survival property is a Phase 3 concern.

The stub is throwaway. Do not let its shape constrain the Phase 3 UDP design, and do not let the
pilot's tests depend on plog internals — they should assert on plog's observable output only.

### Test schema — LOCKED

**Use `ddl/migrated/` (the ora2pg-converted DDL) as the test database schema.** Do not hand-build a
minimal fixture schema.

This is the real target schema (`ddl/migrated/tables/tables.pg.sql` + `constraints.pg.sql` +
`views.pg.sql`, ~9.7k lines). It is ora2pg output and CLAUDE.md warns it "might contain errors" —
so **fixing the errors the pilot surfaces is in scope for this phase**. That is a feature, not a
detour: it front-loads schema breakage that would otherwise ambush Phase 5's container build.

Only the schema subset the pilot actually needs must be proven working; the rest can fail later.
Known pilot table dependencies include (non-exhaustive): `auth.login`, `auth.profile`,
`auth.user_permission`, `auth.user_*_scope`, `auth.consented_term`, `mss.key`, `mss.news_entry`,
`mcaudit.record`, plus the TT ticketing tables.

### System packages — APPROVED

The user approved `sudo apt` installs. None of these are currently present:

| Package | Version available | Purpose |
|---------|-------------------|---------|
| `postgresql-17-pgtap` | 1.3.4-1.pgdg24.04+1 | pgTAP assertions (HARN-01) |
| `postgresql-17-orafce` | 4.16.7-1.pgdg24.04+1 | Oracle built-in compatibility |
| `libtap-parser-sourcehandler-pgtap-perl` | — | provides `pg_prove` runner |

Local PostgreSQL is 17.10, reachable via sudo peer auth (`sudo -u postgres psql`).

### Claude's Discretion

- Spec document format and file layout (must satisfy SPEC-02: explicit "assumptions/unresolved"
  section; SPEC-03: uniform checklist)
- pgTAP test file organization and naming (should read object names from `migration/mapping/name-map.csv`)
- Expected-output harness layout (sql/*.sql vs expected/*.out diffing)
- How fixtures are seeded from `masterdata/` (HARN-03)
- The one-command runner's shape (HARN-04)
- How far to translate the 3 transitive dependency packages
- Whether the plog stub writes to a table, RAISE NOTICE, or both

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 1 artifacts — the ground truth this phase consumes
- `migration/analyze/inventory.json` — 105 objects, per-object metadata (routines, SELECT INTO sites, exception handlers, COMMIT/ROLLBACK, autonomous pragmas, package state)
- `migration/mapping/name-map.csv` — the naming SSOT. Test names and translated object names MUST come from here, not be re-derived. Columns: oracle_schema, oracle_package, oracle_object, oracle_signature, oracle_synonym, kind, pg_schema, pg_object_name, pg_kind, is_overload, overridden, source_path, source_line
- `migration/analyze/depgraph.json` — 105 nodes, 94 edges, 5 waves, call edges resolved in both shapes (qualified + public synonym)
- `migration/analyze/known_cycles.json` — the 2 accepted mutual-recursion cycle groups (one is the TT pair in this pilot)
- `migration/README.md` — tree purpose, decisions, and the standing warning about `static_resolution: "incomplete"` false positives
- `migration/regenerate.sh` — rebuilds all artifacts; `--check` is a staleness gate with teeth

### Oracle source (source of truth for specs)
- `ddl/src/pkg/` (specs), `ddl/src/pkgb/` (bodies) — specs are derived from these by static analysis

### Migration target schema
- `ddl/migrated/tables/` — ora2pg-converted DDL: `tables.pg.sql`, `constraints.pg.sql`, `views.pg.sql`

### Project research
- `.planning/research/PITFALLS.md` — semantic traps. Note Pitfall 4 is CORRECTED: plog logs via UDP (Phase 3), AuditUsage is deleted
- `.planning/research/STACK.md` — pgTAP 1.3.4 / orafce 4.16.7 / pg_prove versions and rationale

</canonical_refs>

<specifics>
## Specific Ideas

- **`pg_kind` in name-map.csv is PROVISIONAL.** The FUNCTION-vs-PROCEDURE decision genuinely depends
  on the COMMIT analysis, which is Phase 3's XCUT-04. The pilot will be the first place this bites:
  `TT.UTIL` has both COMMIT and an autonomous transaction. Surface what the pilot learns; do not
  silently treat `pg_kind` as settled.
- **`TT.OSAG_NOTIFY` has 30 SELECT INTO sites** — the single richest source of the NO_DATA_FOUND /
  STRICT semantic trap in the pilot's dependency set. Good place to prove the checklist works.
- **`TT.EVENT_INTERFACE` is `static_resolution: incomplete`** (genuine dynamic SQL). The roadmap
  flagged exactly this as the phase's research risk: dynamic SQL may resist static spec derivation
  with no live-Oracle baseline. Its spec's "assumptions/unresolved" section must carry that honestly
  rather than guessing.
- Tests must cite the spec clause they verify (HARN-05) and must be derived from the **Oracle**
  spec, not from the PL/pgSQL translation — otherwise verification is circular.
- The harness must demonstrably go **red-before / green-after** on the pilot. A test suite that was
  never seen failing proves nothing.

</specifics>

<deferred>
## Deferred Ideas

- Real UDP log shipper for plog → Phase 3 (XCUT-02)
- Exception mapping table, DBMS_*/UTL_* replacement reference, transaction-semantics audit → Phase 3
- Bulk translation of the remaining ~44 packages → Phase 4
- Full container build proving the whole `ddl/migrated` schema → Phase 5
- `SYS.OSAG_TABLE_REDEFINITION` — Oracle-specific; user rejected it from the pilot. Its place in the
  milestone at all is an open question for the roadmap.

</deferred>

---

*Phase: 02-spec-method-test-harness-pilot*
*Context gathered: 2026-07-12 via direct user decisions*
