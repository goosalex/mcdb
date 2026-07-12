<!--
  migration/spec/TEMPLATE.md — the exact skeleton every package spec must fill.

  Copy this file to migration/spec/<pg_schema>.<oracle_package_lower>.md (e.g.
  migration/spec/tt.ticket_interface.md) and replace every <PLACEHOLDER>.

  Rules (enforced mechanically by spec_lint.py, see README.md):
  - Every fact here is derived from ddl/src/pkg/** and ddl/src/pkgb/** and NOTHING else.
    Not pg_migration/output/ (untrusted ora2pg). Not the PL/pgSQL translation (which does
    not exist yet, by construction — see D-P4 in 02-02-PLAN.md).
  - pg_schema / pg_prefix in the front-matter MUST match migration/mapping/name-map.csv
    for this Oracle package. Never invent a PostgreSQL name here.
  - Every clause needs a unique ID S-<clause_prefix>-NNN and at least one
    ddl/src/<path>:<line> citation. IDs never get renumbered once assigned.
  - Every public routine the Phase 1 inventory lists for this package must be named in at
    least one clause's `routines:` field. Overloaded names count once.
  - The five ## Checklist dimensions (see CHECKLIST.md) are all mandatory.
  - ## Assumptions / Unresolved is never empty — an honest "nothing unresolved, and here
    is what was checked to reach that" is a valid answer; a guess is not.
-->
---
oracle_schema: <ORACLE_SCHEMA>
oracle_package: <ORACLE_PACKAGE>
pg_schema: <pg_schema>
pg_prefix: <pg_prefix>
clause_prefix: <CLAUSE_PREFIX>
oracle_spec: ddl/src/pkg/<file>.sql
oracle_body: ddl/src/pkgb/<file>.sql
public_routines: <N>
---

# <ORACLE_SCHEMA>.<ORACLE_PACKAGE> — PostgreSQL spec

One paragraph: what this package does, in plain language, derived from its header
comment and routine set in `ddl/src/pkg/<file>.sql`.

## Routines

One subsection per PUBLIC routine (from the Oracle package spec, not the body's private
helpers). Copy the PostgreSQL object name from `migration/mapping/name-map.csv` —
never re-derive it.

### <oracle_routine_name>

- **Oracle signature:** `<ORACLE_ROUTINE_NAME>(<PARAM TYPE>, ...) RETURN <TYPE>` (or
  `PROCEDURE` with no `RETURN`)
- **PostgreSQL name:** `<pg_schema>.<pg_prefix>_<routine_name>` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/<file>.sql:<line>`
- **Defined:** `ddl/src/pkgb/<file>.sql:<line>`
- One or two sentences: what it does and its observable side effects (return value,
  raised exceptions, logging, writes).

<!-- repeat ### per public routine -->

## Clauses

The numbered behavioural claims. Every clause constrains one or more routines above and
cites the Oracle source line(s) that justify it. **A clause with no citation is not a
clause; it is a guess.**

### S-<CLAUSE_PREFIX>-001

- **routines:** <oracle_routine_name>[, <oracle_routine_name_2>]
- **claim:** One sentence describing an observable behaviour (a return value for a given
  input class, a side effect, an exception raised under a named condition).
- **source:** `ddl/src/pkgb/<file>.sql:<line>`

<!-- repeat ### S-<CLAUSE_PREFIX>-NNN per clause, never renumbered once assigned -->

## Checklist

The five SPEC-03 dimensions from `CHECKLIST.md`, answered for THIS package. An answer of
"N/A" is acceptable only when it states the reason N/A applies (e.g. "N/A — this package
has no VARCHAR2 parameters at all, verified by inspecting all 3 routine signatures above").

### 1. Empty-string / NULL handling

<answer>

### 2. SELECT INTO strictness

<answer>

### 3. Exception codes

<answer>

### 4. Package state

<answer>

### 5. FUNCTION vs PROCEDURE

<answer>

## Assumptions / Unresolved

What static analysis of `ddl/src/**` could not settle, and why — there is no live Oracle
to fall back on (see `.planning/research/PITFALLS.md`, "Deriving specs from source without
a runtime baseline"). If genuinely nothing is unresolved, say so explicitly and state what
was checked to reach that conclusion (e.g. "every SELECT INTO site, every RAISE_*, and the
full declare section were reviewed; no dynamic SQL, no package state, no ambiguous NULL/''
site remain"). An honest "cannot know this from static source alone" here is worth more
than a confident guess — a guess here silently poisons Phase 4's translation.

<answer>
