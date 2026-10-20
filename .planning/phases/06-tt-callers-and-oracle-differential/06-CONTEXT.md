# Phase 06 — TT callers translated + Oracle/PostgreSQL differential testing

Branch `phoenix/migrate_tt_only`. Opened 2026-10-20 on the project owner's instruction:
"continue autonomously translating all PL/SQL inside TT, TICKETEVOLUTION and other packages
calling into TT to proper PostgreSQL PL/pgSQL; when the Oracle container builds, save the
image locally and complete the test harness so the functions are verified not only by static
analysis but by comparing Oracle results with the results of the translations on Postgres."

This supersedes section 4 of `.planning/reports/tt-only-scope-2026-10-16.md` for the caller
packages: they are translated, not stubbed/bridged. `migration/oracle_side/` keeps only what
still stays on Oracle.

## Scope (dependency closure of everything that calls into TT, from migration/analyze/depgraph.json)

Already translated and green: OSAG.OSAG_PLOG (stub), MSS.OSAG_DBPROP, MSS.OSAG_IP, OSAG.OSAG_MSG,
TICKETEVOLUTION.CALCULATOR, TT.* (5 packages, 2 triggers), AUTH.OSAG_AUTH.

To translate (30 public routines, ~2,900 Oracle body lines):

| Batch | Packages | Wave | Depends on |
|---|---|---|---|
| A (06-01) | MC.OSAG_MAINTSYNC (4), MCAUDIT.OSAG_AUDIT (4) | 2 | plog only |
| B (06-02) | GUMA2.SECONDARY_ISP (2), OSIXINFO.OSAG_HARDWARE (3) + OSIXINFO.OSAG_EXCEPTIONS (constants) | 4 | TT.EVENT_INTERFACE |
| C (06-03) | GUMA2.OSAG_GUMA (8) + GUMA2.OSAG_GUMA_STATE (constants), NIDS.OSAG_NIDS (2) | 4 | A (MCAUDIT), TT, MSS.OSAG_IP |
| D (06-04) | MC.MONITORING (6) + MC.MONITORING_TICKET_PROCESSES (1) + MC.MONITORING_STATE (constants) — one batch, mutual recursion (known_cycles.json) | 4 | TT, TT.ESCALATION_INTERFACE |
| E (06-05) | Differential harness: run the same scenario on Oracle (`mcdb-ora`) and PostgreSQL (`mcdb-pg`), normalise, diff | — | Oracle container |
| F (06-06) | Differential scenarios for every package in the closure | — | E, A–D |
| G (06-07) | Integration: run-all.sh + run-diff.sh green, image saved, STATE/ROADMAP, memory | — | all |

## Rules every plan inherits (unchanged from Phase 2)

- Spec from `ddl/src/pkg` + `ddl/src/pkgb` only (`migration/spec/README.md`, `TEMPLATE.md`, `CHECKLIST.md`).
- Order of commits per package: spec -> tests (RED proven) -> translation (+FINDINGS). A translation
  commit never touches `migration/test/`; amendments go through `migration/spec/TEST-AMENDMENTS.md`.
- Names from `migration/mapping/name-map.csv`, never re-derived. Private routines: `<pkg>__<name>`.
- `ddl/` and `masterdata/` are read-only (productive Oracle still uses them).
- Shared PostgreSQL: container `mcdb-pg` via `migration/db/pg.sh`; template `mcdb_tmpl` is shared —
  agents never rebuild it; per-package schema fixes go to `migration/test/schema-fixes/NN_<pkg>_fixes.sql`
  and are applied to the agent's own `mcdb_test_<pkg>` database.
- Oracle bugs: correct them, annotate `-- DEVIATION(ORACLE-BUG)`, specify the corrected behaviour.
- Concurrency cap: 3 agents.
