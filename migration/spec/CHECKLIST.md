# The SPEC-03 uniform checklist

Every package spec under `migration/spec/*.md` answers these five dimensions, in this
order, under its own `## Checklist` section. Each dimension maps to a documented pitfall
in `.planning/research/PITFALLS.md`, and each has a precise, answerable question — not a
vibe. `spec_lint.py` requires all five headings present with non-empty content (SPEC-03);
an empty or bare "N/A" answer fails the lint. `migration/spec/TEMPLATE.md` is the
copy-paste skeleton that already has these five headings in the right shape.

The authoritative evidence for every answer is `ddl/src/pkg/**` and `ddl/src/pkgb/**` —
never `pg_migration/output/` (untrusted ora2pg), never the PL/pgSQL translation (which,
for a spec written before its translation, does not exist yet).

---

### 1. Empty-string / NULL handling

**Maps to:** Pitfall 2 — Oracle collapses `''` and `NULL` into the same value; PostgreSQL
does not. `NVL('', x)` returns `x` in Oracle and `''` in PostgreSQL, because PostgreSQL's
`''` was never NULL to begin with.

**Question:** For every `VARCHAR2`/`CLOB` parameter, column, and local variable in this
package that takes part in an `IS NULL`/`IS NOT NULL` check, an equality/inequality
comparison, or a `||` concatenation — what did Oracle do when the value was `''`? Record,
per parameter/column/local: (a) is `''` reachable for this value at all; (b) if so, does
Oracle's implicit `''` == `NULL` collapsing change the outcome of a check that a naive
PostgreSQL port would get wrong; (c) the translation decision — normalize `''` to `NULL`
at the boundary (`NULLIF(x, '')`), add an explicit `CHECK`, or leave as-is with a reason.

**Evidence:** Grep the routine bodies for `IS NULL`, `IS NOT NULL`, `=`, `!=`/`<>`, and
`||` against every `VARCHAR2`/`CLOB`-typed identifier. Cite the exact `ddl/src/...:LINE`
for each site considered, even ones where the answer is "not reachable here."

---

### 2. SELECT INTO strictness

**Maps to:** Pitfall 1 — Oracle's `SELECT ... INTO` always raises `NO_DATA_FOUND` on zero
rows and `TOO_MANY_ROWS` on more than one; PL/pgSQL's plain `SELECT INTO` raises neither.

**Question:** For every `SELECT ... INTO` site in this package (the Phase 1 inventory's
`select_into_sites` gives the line numbers — cross-check the count matches), is a
zero-row result possible/expected, is a multi-row result possible/expected, and what did
the Oracle handler do at that site (an explicit `EXCEPTION WHEN NO_DATA_FOUND`/
`WHEN TOO_MANY_ROWS`, an enclosing handler further up the call stack, or nothing — meaning
an unhandled `NO_DATA_FOUND` was itself part of the Oracle contract)? Record the intended
PostgreSQL translation per site: `SELECT ... INTO STRICT ...` plus a matching handler
where Oracle had one, or `STRICT` with no local handler (matching Oracle's unhandled
propagation) where Oracle had none.

**Evidence:** Cite each `SELECT ... INTO` line and its nearest enclosing
`EXCEPTION WHEN NO_DATA_FOUND` / `WHEN TOO_MANY_ROWS` block (or state explicitly that
none exists at any enclosing scope in this package).

---

### 3. Exception codes

**Maps to:** Pitfall 3 — Oracle's `-20NNN` `RAISE_APPLICATION_ERROR` codes and named
package exceptions have no 1:1 PostgreSQL equivalent; naive translation to a bare
`RAISE EXCEPTION` loses the code entirely, which can break callers that branch on it.

**Question:** For every `RAISE_APPLICATION_ERROR` call, every named exception the package
declares or raises (including ones declared in a paired `*_STATE` package, e.g.
`OSAG_DBPROP_STATE.e_abort`), and every bare re-raise inside a `WHEN OTHERS` handler: what
is the Oracle error code or exception name, and what PostgreSQL SQLSTATE should it map to?
The authoritative mapping table is Phase 3 (XCUT-01) — this pilot spec records what it
needs and marks the mapping **PROVISIONAL**, it does not invent a final answer.

**Evidence:** Cite each `RAISE_APPLICATION_ERROR(code, ...)` call site and each exception
name it raises or catches, including any that live in a companion `*_STATE` package (the
Phase 1 lexer's `RAISE_APPLICATION_ERROR` regex only catches numeric-literal codes — a
call through a named constant, like `OSAG_DBPROP_STATE.S_ERRNO_UNKNOWN_DBPROP`, will not
appear in `inventory.json`'s `raise_application_error[]` and must be traced by hand back
to its declaration).

---

### 4. Package state

**Maps to:** Pitfall 5 — `package_in_name` flattening to stateless functions silently
drops any package-body-level mutable variable and any trailing unnamed initialization
block; Oracle would have kept both warm for the life of a session.

**Question:** Does this package's body declare any non-`CONSTANT` package-level variable
(the inventory's `package_state[]` lists candidates — verify, don't just trust), and does
it have a trailing unnamed `BEGIN...END` initialization block (`has_init_block`)? If
either is true, what does the state hold, is it read across more than one call in the
same session, and what is the translation decision (session GUC, session-scoped temp
table, or safe re-derivation per call with the resulting behavior delta noted)? If
neither exists, say so explicitly and name what was checked (the declare section between
the package body's `IS`/`AS` and its first routine).

**Evidence:** Cite the declare-section line range and, for any state variable found, its
declaration line and every assignment site.

---

### 5. FUNCTION vs PROCEDURE

**Maps to:** Pitfall 6 — a PostgreSQL FUNCTION can never `COMMIT`/`ROLLBACK`; only a
PostgreSQL PROCEDURE (invoked via `CALL`) can, and only at the top of an uninterrupted
`CALL` chain. An Oracle FUNCTION that commits has no direct PostgreSQL FUNCTION
translation at all.

**Question:** Does any routine in this package issue an explicit `COMMIT`/`ROLLBACK`
(`has_commit`/`has_rollback` in the inventory) or carry `PRAGMA AUTONOMOUS_TRANSACTION`?
If so, which routine, and is it declared `FUNCTION` or `PROCEDURE` in the Oracle spec? An
Oracle FUNCTION that commits needs to be redesigned as a PostgreSQL PROCEDURE with an OUT
parameter — flag this, and flag every caller found in the dependency graph, since the
call shape changes. `name-map.csv`'s `pg_kind` column carries the Oracle declaration
through as-is and is **PROVISIONAL**; the final call belongs to Phase 3 (XCUT-04). This
checklist item records the finding and its consequences, it does not settle it.

**Evidence:** Cite every `COMMIT`/`ROLLBACK`/`PRAGMA AUTONOMOUS_TRANSACTION` line found,
or state explicitly that none exist and that the inventory's `has_commit`/`has_rollback`/
`autonomous_transaction` fields were checked to reach that conclusion.
