# migration/

This tree is the pipeline for Phase 1 (Inventory & Foundation) of the Oracle → PostgreSQL
migration, and everything downstream of it in later phases: specs (`spec/`), translations
(`pgsql/`), the test harness (`test/`), the PostgreSQL container (`db/`) and the Oracle-side
material for the split (`oracle_side/`).

**Current focus (since October 2026): the ticketing schemas `TT` and `TICKETEVOLUTION` and
their dependency closure are translated and verified first**; the other schemas stay on
Oracle for now. The progress of that sub-project, its open decisions and its distance to
parity are tracked in [`../STATUS_TT.md`](../STATUS_TT.md). It is deliberately kept
separate from `pg_migration/` (ora2pg's raw, untrusted output) — nothing under
`migration/` is ora2pg output, and nothing under `pg_migration/` is treated as verified.

## What lives here

- `analyze/` — static-analysis tooling that reads `ddl/src/{pkg,pkgb,proc,triggers,types}`
  (read-only input) and produces the object inventory and the dependency graph.
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
  - `depgraph.py` — the dependency graph generator. Default mode writes
    `depgraph.json` + `depgraph.dot`; `--check` validates every gate below and exits
    non-zero on failure, without writing anything.
  - `depgraph.json` — THE dependency graph, call edges, and wave list (satisfies
    INV-02). Machine-generated, never hand-edited.
  - `depgraph.dot` — a Graphviz rendering of the same graph, for human review only
    (not a consumer input — nothing downstream parses this file).
  - `known_cycles.json` — **human-authored input.** The accepted cycle groups; a
    cycle group produced by `depgraph.py` that isn't listed here fails `--check`.
  - `tests/` — unittest suites pinning lexer/inventory/depgraph generator behavior
    against real files in `ddl/src/`.
- `mapping/` — the name-mapping SSOT and its generator.
  - `name_map.py` — the name-map generator. Default mode writes `name-map.csv`;
    `--check` runs the collision gate and exits non-zero on any unresolved collision,
    without writing anything.
  - `name-map.csv` — THE name-mapping SSOT (satisfies INV-03). Machine-generated,
    never hand-edited.
  - `overrides.csv` — **human-authored input.** The only sanctioned place a
    PostgreSQL object name may deviate from the mechanical `package_in_name` rule;
    resolves a hard collision the generator refuses to resolve on its own. A stale
    override (one that matches no existing collision) fails `--check`.
  - `tests/` — unittest suites pinning name-map generator behavior, including the
    collision gate, against real inventory data and synthetic fixtures.
- `regenerate.sh` — one command that regenerates all three artifacts, runs every
  `--check` gate, and runs the full test suite. `regenerate.sh --check` proves the
  checked-in artifacts are not stale (regenerates into a temp dir and diffs).
- `db/` — the PostgreSQL 18.6 container (orafce, pgTAP, `pg_prove`) that every regeneration and test script starts before it runs. `pg.sh` starts it and runs `psql`/`pg_prove` inside it; see [Database container](test/README.md#database-container).

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
and re-run it (`bash migration/regenerate.sh`). A hand-edited artifact silently drifts
from the Oracle source it's supposed to describe, and nothing downstream would ever
notice.

The sole exceptions are `migration/mapping/overrides.csv` and
`migration/analyze/known_cycles.json` — these are **human-authored inputs by design**,
not generated output. They exist precisely so a human can make an explicit, reviewable
decision (accept a collision resolution; accept a cycle) that the generators themselves
must never invent silently.

## Consumer contract (who reads what)

This is the part later phases need in order not to re-derive any of this. No consumer
may invent a PostgreSQL object name or a translation order anywhere else — if a name or
an order is needed, it comes from these files.

| Artifact | Format | Exact path | Who reads it, for what |
|---|---|---|---|
| `name-map.csv` | CSV | `migration/mapping/name-map.csv` | **Phase 4**: every cross-reference rewrite (translating a call site to its new PostgreSQL name) and every generated test's name. **Phase 5**: the client regexp kit is generated mechanically from this file's rows. |
| `depgraph.json` | JSON | `migration/analyze/depgraph.json` | **Phase 4**: `waves[]` is the translation batch order — iterate wave 1 first, and by the time a wave is translated, everything it calls already exists (except within a `cycle_groups[]` member, which must be translated together as one batch). |
| `depgraph.dot` | Graphviz DOT | `migration/analyze/depgraph.dot` | Human review only. Not parsed by any downstream consumer. |
| `inventory.json` | JSON | `migration/analyze/inventory.json` | Upstream input to the above two generators. Later phases should prefer `name-map.csv`/`depgraph.json` over re-deriving facts from `inventory.json` directly, since those two are the settled, cross-referenced SSOTs. |

A second mapping table, a second dependency order, or a second collision-resolution
mechanism appearing anywhere else in the repo is the failure mode this contract exists
to prevent.

## Naming rules (the `package_in_name` mechanical rule — INV-03)

Schema layout stays identical to Oracle; only object names change. Every PostgreSQL
name is lowercased.

| Oracle object | PG schema | PG object name | Example |
|---|---|---|---|
| Package routine `SCHEMA.PKG.OBJ` | `schema` (lower) | `pkg_obj` (lower) | `TICKETEVOLUTION.CALCULATOR.materialize_tickev` becomes `ticketevolution.calculator_materialize_tickev` |
| Standalone procedure `SCHEMA.PROC` | `schema` (lower) | `proc` (lower) — no prefix, it has no package | `SYS.decomAuthHost` becomes `sys.decomauthhost` |
| Trigger `SCHEMA.TRG` | `schema` (lower) | `trg` (lower) — no prefix | `APPID.t_interface_ps_link_class_sync` |
| Trigger function (PG needs one; Oracle has no such concept) | `schema` (lower) | `trg` + `_fn` (lower) | `appid.t_interface_ps_link_class_sync_fn` |
| Type `SCHEMA.TYP` | `schema` (lower) | `typ` (lower) — no prefix | `MCDB_MONITOR.consistency_check_result_type` |

The trigger-function row exists so Phase 4 does not invent trigger-function names
outside the SSOT.

## Collision semantics

`package_in_name` flattening creates a real, concrete collision hazard in this schema,
because several packages in the same schema are prefix-extensions of each other (e.g.
`MC.MONITORING` / `MC.MONITORING_STATE`; `AUTH.OSAG_AUTH` / `AUTH.OSAG_AUTH_STATE`;
`TT.TICKET_INTERFACE` / `TT.TICKET_INTERFACE_STATE`). A routine `state_foo` in
`MC.MONITORING` and a routine `foo` in `MC.MONITORING_STATE` would both flatten to
`mc.monitoring_state_foo`. Every duplicate `(pg_schema, pg_object_name)` group is
classified as exactly one of:

| Case | Condition | Disposition |
|------|-----------|-------------|
| Legitimate overload | All rows come from the SAME Oracle package AND the same routine name, with DISTINCT normalized argument-type lists | ALLOWED. Every row marked `is_overload=true`. PostgreSQL overloads natively. (`TT.TICKET_INTERFACE.change_label` is the real instance in this corpus.) |
| Hard collision — identical signature | Two or more rows share `(pg_schema, pg_object_name, oracle_signature)` | HARD FAIL. Exit non-zero. Unresolvable without a human decision. |
| Hard collision — cross-package prefix ambiguity | Rows share `(pg_schema, pg_object_name)` but come from DIFFERENT Oracle packages, even when the argument lists differ | HARD FAIL. Two unrelated routines masquerading as overloads of one function would silently mis-dispatch. |

A hard collision is resolved ONLY by a human adding a row to
`migration/mapping/overrides.csv`. `name_map.py --check` fails if any hard collision
lacks a matching override row, and also fails on a stale override row that matches no
collision. As of this writing, the real corpus contains exactly one duplicate-name
group, and it is the legitimate-overload case — `overrides.csv` is seeded with a header
row only.

## Cycle policy

Oracle packages CAN be mutually recursive, so a cycle is not automatically a bug and
does not hard-fail the topological sort:

- Every strongly-connected component of size greater than 1 is a cycle group. All its
  members share one wave number and carry that group's `cycle_group` id.
- Every cycle group must be listed in `migration/analyze/known_cycles.json` — a cycle
  group NOT listed there fails `depgraph.py --check`. This makes a genuinely new cycle
  (as opposed to one already reviewed and accepted) a build failure.
- **A cycle group's members translate as one batch in Phase 4** — none of them can
  precede the others, since each calls at least one of the others.
- The real corpus has two genuine cycles, both verified against source before being
  accepted into `known_cycles.json`: `MC.MONITORING` ↔ `MC.MONITORING_TICKET_PROCESSES`,
  and the four core ticketing packages `TT.EVENT_INTERFACE` / `TT.OSAG_NOTIFY` /
  `TT.TICKET_INTERFACE` / `TT.UTIL`.

## Standing warnings for downstream phases

- **`pg_kind` is provisional.** `name-map.csv`'s `pg_kind` column carries the Oracle
  FUNCTION/PROCEDURE declaration through as-is — it is NOT the final FUNCTION-vs-
  PROCEDURE decision for PostgreSQL. That decision depends on the COMMIT/ROLLBACK
  transaction-semantics audit and belongs to Phase 3 (XCUT-04). No downstream consumer
  should treat `pg_kind` as settled.
- **`static_resolution: "incomplete"` nodes need manual tracing.** Both `inventory.json`
  and `depgraph.json` flag objects whose call edges a static parser cannot fully see —
  either genuine dynamic SQL (`EXECUTE IMMEDIATE`/`DBMS_SQL`) or a reference the lexer-
  based extractor couldn't resolve (including some false positives, such as
  `INSERT INTO schema.table (col_list)` being misread as a call-shaped reference).
  Phase 2 and Phase 4 must manually trace each `incomplete` node's `reasons[]` rather
  than trusting the graph's edge list for those objects; `depgraph.py`'s report prints
  the full list on every run specifically so it is never buried.
