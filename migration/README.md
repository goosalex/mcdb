# migration/

This tree is the pipeline for Phase 1 (Inventory & Foundation) of the Oracle → PostgreSQL
migration, and everything downstream of it in later phases. It is deliberately kept
separate from `pg_migration/` (ora2pg's raw, untrusted output) — nothing under
`migration/` is ora2pg output, and nothing under `pg_migration/` is treated as verified.

## What lives here

- `analyze/` — static-analysis tooling that reads `ddl/src/{pkg,pkgb,proc,triggers,types}`
  (read-only input) and produces the object inventory and (in plan 02) the dependency
  graph.
  - `plsql_lex.py` — comment/string-stripping lexer + top-level object header scanner.
    Library only, no CLI. Every other tool in this tree that needs to look at Oracle
    source text imports this first and works against its `.clean` output, never raw text.
  - `inventory.py` — the inventory generator. Default mode writes `inventory.json`;
    `--check` mode reconciles the parse against `expected_counts.json` and exits
    non-zero on any mismatch, without writing anything.
  - `inventory.json` — THE object inventory (satisfies INV-01). Machine-generated,
    never hand-edited.
  - `expected_counts.json` — the reconciliation contract: the structural ground truth
    (`--check` must exactly reproduce these counts).
  - `tests/` — unittest suites pinning lexer and inventory-generator behavior against
    real files in `ddl/src/`.
- `mapping/` — (plan 02) the name-mapping SSOT (`name-map.csv`) and its generator.

## Decisions (from 01-01-PLAN.md, stated here verbatim so every consumer sees them)

- **D-A — Artifact formats: JSON for inventory + graph, CSV for the name map.**
  The inventory and graph are nested (routines inside packages, edges with metadata) —
  JSON is the natural fit. The name map is flat, row-per-object, and is read by three
  independent consumers plus humans doing `grep`/diff review — CSV, per
  `.planning/research/ARCHITECTURE.md` Pattern 2.
- **D-B — Tooling: Python 3.12 stdlib only. No pip/npm/cargo installs. No ZPA/JVM.**
  The facts this phase needs are recoverable with a comment-and-string-stripping lexer
  plus targeted matching. Reversibility is protected by the artifact formats: if a later
  phase finds the lexer insufficient, a real parser (e.g. ZPA/ANTLR) can be swapped in
  behind the same `inventory.json` schema without touching any consumer.
- **D-C — Location: a new top-level `migration/` tree.** Deliberately NOT `pg_migration/`
  — that tree holds untrusted ora2pg output and must not be confused with verified
  pipeline artifacts.
- **D-D — Generator AND output are both checked in.** Artifacts are regenerable, never
  hand-maintained. (Plan 02's `migration/regenerate.sh --check` regenerates into a temp
  dir and diffs against the checked-in copies, failing if they are stale.)

## The rule

Every artifact under `migration/` is generated. If you find yourself about to hand-edit
`inventory.json`, `name-map.csv`, or `depgraph.json` — stop. Fix the generator instead
and re-run it. A hand-edited artifact silently drifts from the Oracle source it's
supposed to describe, and nothing downstream would ever notice.
