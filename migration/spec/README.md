# migration/spec/

This tree is where the spec-first methodology (SPEC-02, SPEC-03, HARN-05) becomes a
property of the repo rather than an intention. It exists for exactly one reason: a test
written by reading the PL/pgSQL translation proves nothing — it merely asserts the
translation does what the translation does. Everything here exists to make that
mechanically impossible, not merely discouraged.

## The standing rule

**A spec is derived from `ddl/src/pkg/**` and `ddl/src/pkgb/**`, and from nothing else.**

Not from `pg_migration/output/` — that is raw, untrusted ora2pg output (per
`CLAUDE.md`/`migration/README.md`, "It for sure contains errors, ora2pg is not capable of
translating the program code"). Not from the PL/pgSQL translation — for a package spec
written before its translation exists (the normal order this phase enforces, see
D-P4 below), the translation is not even readable yet. Not from what would be convenient
to implement. If a fact isn't traceable to an Oracle source line, it does not belong in a
spec clause.

## How to author a spec

1. Copy `TEMPLATE.md` to `migration/spec/<pg_schema>.<oracle_package_lower>.md` — e.g.
   `AUTH.OSAG_AUTH` becomes `migration/spec/auth.osag_auth.md`,
   `TT.TICKET_INTERFACE` becomes `migration/spec/tt.ticket_interface.md`.
2. Fill the front-matter. `pg_schema` and `pg_prefix` MUST match
   `migration/mapping/name-map.csv` for that Oracle package — copy them, never re-derive.
   `clause_prefix` is your choice (short, uppercase, stable — e.g. `DBPROP`, `TICKET`).
3. Fill `## Routines` — one subsection per PUBLIC routine from the Oracle package spec
   (`ddl/src/pkg/...`), with the PostgreSQL name copied from `name-map.csv`.
4. Fill `## Clauses` — the numbered behavioural claims (`S-<PREFIX>-NNN`). Every clause
   cites at least one `ddl/src/...:LINE`. IDs never get renumbered once assigned, because
   tests cite them (HARN-05) and a renumber would silently break every citing test.
5. Fill `## Checklist` — apply all five dimensions from `CHECKLIST.md` to this package.
6. Fill `## Assumptions / Unresolved` — SPEC-02. Never empty. If genuinely nothing is
   unresolved, say so and state what was checked.
7. Run `python3 migration/spec/spec_lint.py` before committing. It will reject a spec that
   invents a PostgreSQL name, drops a routine, skips a checklist dimension, leaves
   Assumptions empty, or cites a source line that does not exist.

**Triggers** (standalone objects with an EMPTY `oracle_package` column in `name-map.csv`):
name the spec `migration/spec/<pg_schema>.<trigger_name_lower>.md`, put the trigger name in
`oracle_package`, add the optional front-matter field `oracle_kind: trigger` (default:
`package`), set `pg_prefix` to the trigger row's `pg_object_name` verbatim (the linter demands
equality, not a prefix match), `public_routines: 1`, and name the trigger itself in at least one
clause's `routines:` field. `oracle_spec` and `oracle_body` both point at the
`ddl/src/triggers/<SCHEMA>.sql` file. Test files follow the same shape:
`<pg_schema>__<trigger_name_lower>__<topic>.sql`.

## The three linters

| Linter | Gate | Rejects |
|---|---|---|
| `spec_lint.py` | SPEC-02, SPEC-03 | Missing front-matter; `pg_schema`/`pg_prefix` that don't match `name-map.csv`; any of the four mandatory sections missing; an empty/bare-N/A `## Assumptions / Unresolved`; any of the five `## Checklist` dimensions missing or empty; a clause with a malformed ID, a duplicate ID, or no `ddl/src/...:LINE` citation; a citation whose file doesn't exist or whose line is past end-of-file; a spec that doesn't name every public routine `inventory.json` lists for that package in at least one clause's `routines:` field. |
| `trace_lint.py` | HARN-05 | A pgTAP assertion whose description doesn't start with `S-<PREFIX>-NNN: `; an expected-output test file with no `-- verifies: S-...` header; a test citing a clause ID that doesn't exist in that package's spec; a test file for a package with no spec at all. Also prints a coverage report (which clauses have at least one citing test) — a report, not a gate; VER-02 (test per routine) is Phase 4's job. |
| `provenance_lint.sh` | HARN-05 (structural anti-circularity, T-02-06) | A translation (`migration/pgsql/<schema>/<pkg>.sql`) whose spec-add or first-test-add commit is NOT a git ancestor of the translation-add commit — i.e. the translation was written first, so any test "verifying" it is circular. Also rejects a translation commit that also modifies one of that package's test files, unless the change is explicitly logged in `migration/spec/TEST-AMENDMENTS.md`. |

All three run cleanly (`0 found, nothing to check`, exit 0) on a tree with no specs, no
tests, and no translations yet — later plans in this phase call them as they go, and CI
can run them unconditionally from day one.

## Running the linters

```bash
python3 migration/spec/spec_lint.py              # lint every migration/spec/*.md
python3 migration/spec/spec_lint.py PATH [PATH…]  # lint exactly the given file(s)
python3 migration/spec/trace_lint.py              # lint every migration/test/{pgtap,regress/sql} file
python3 migration/spec/trace_lint.py PATH [PATH…]  # lint exactly the given file(s)
bash migration/spec/provenance_lint.sh            # check ancestry for every migration/pgsql/*/*.sql
python3 -m unittest discover -s migration/spec/tests -v   # linter unit suite
```

## The TEST-AMENDMENTS.md escape hatch

`provenance_lint.sh` normally rejects any commit that touches a translation file
(`migration/pgsql/<schema>/<pkg>.sql`) AND a test file for that same package in the same
commit — that shape is indistinguishable from "I noticed my test was wrong while writing
the translation and quietly fixed it to match." If a test genuinely must change after
translation begins (a real bug found in the test itself, not the translation), the escape
hatch is explicit and leaves evidence:

1. Amend the SPEC first, in its own commit, citing the Oracle source that shows the test
   was wrong (not the translation).
2. Change the test in a separate commit that does NOT touch the translation file.
3. Add a line to `migration/spec/TEST-AMENDMENTS.md` (create it if it doesn't exist yet):
   `commit:<full-sha> file:<path/to/test_file.sql> reason:<why>`

`provenance_lint.sh` reads that ledger and permits exactly the `(commit, file)` pairs it
lists — nothing else.

## Directory layout

- `TEMPLATE.md` — the spec skeleton (this file's sibling; not itself linted).
- `CHECKLIST.md` — the five SPEC-03 dimensions, each tied to a pitfall and to concrete
  Oracle-source evidence (not itself linted).
- `spec_lint.py` / `trace_lint.py` / `provenance_lint.sh` — the three linters.
- `<pg_schema>.<oracle_package_lower>.md` — one real package spec per file, at the root of
  this directory (linted).
- `fixtures/` — throwaway specs used only by `tests/test_spec_lint.py` to prove the linter
  actually rejects bad input. Never treated as real specs; `spec_lint.py`'s default glob
  skips this directory (it only lints fixtures when given an explicit path, as the unit
  tests and the plan's own verification commands do).
- `tests/` — the `unittest` suite pinning linter behaviour, including the rejection cases.
- `TEST-AMENDMENTS.md` — created lazily by whichever future plan first needs the escape
  hatch above. Absence is fine; `provenance_lint.sh` treats a missing ledger as "no
  amendments permitted," not as an error.
