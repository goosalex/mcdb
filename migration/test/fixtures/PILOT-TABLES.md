# PILOT-TABLES.md — masterdata reference fixtures loaded into `mcdb_tmpl`

`fixtures/load_masterdata.py` COPYs `masterdata/<SCHEMA>/*.csv` reference data into the
pilot's five schemas (`AUTH`, `TT`, `MSS`, `MCAUDIT`, `OSAG`), baked into the `mcdb_tmpl`
template by `bootstrap/40_fixtures.sh` (`build-template.sh` step 5/6), so every database
cloned from the template already has realistic reference data present (HARN-03).

## What this loader is, and is NOT, responsible for

This loads **shared, static reference/lookup data** only (types, statuses, countries,
currencies, roles, etc.) — the kind of data that is identical across every test run and
never mutated by a test. **Pilot tests need transactional, per-test data on top of this**
(a specific ticket, a specific login, a specific host) — that is each test file's OWN
job (INSERT it in the test, or in a fixture the test file owns), NOT this loader's. Do
not add pilot-specific rows to `masterdata/` or to this loader — the shared template
must stay generic across every later plan/wave that clones it.

## Empty-string vs. NULL policy (Pitfall 2) — evidence-based, not assumed

This plan's own text assumed Oracle's NULL/empty-string identity would surface as an
**empty CSV field** needing to be forced to NULL. Inspection of the actual masterdata
CSVs for all five pilot schemas shows a different convention was already used by the
exporter:

- **NULL is represented by the literal quoted token `"NULL"`** — e.g.
  `masterdata/MSS/key.csv`: `"3","vrrp.monitor.ip","4","NULL","NULL","^(...)$","NULL","22","..."`.
  135+ rows across `mss.key`, `tt.event_action`, `tt.event_type_message`, and others use
  this convention.
- **A genuinely empty field (`""`, two adjacent quotes with nothing between) occurs
  ZERO times** across every `.csv` file in the five pilot schemas — verified with
  `grep -nE '(^|,)""(,|$)'` over every file before writing the loader. The only
  double-quote-adjacent occurrences found (`mss/key.csv`, `mss/service_option_type.csv`)
  are CSV-escaped literal `"` characters INSIDE a longer text value (e.g.
  `"""username"" of the API user"`), not empty fields.

**Policy implemented, applied uniformly to every column of every table:** the literal
token `NULL` — quoted or not — loads as SQL `NULL`. Any other value, including a
genuine empty string, loads as-is, unmodified. This is done with PostgreSQL `COPY`'s
`NULL 'NULL'` option **combined with `FORCE_NULL(<every column>)`** — `FORCE_NULL` is
required because `COPY`'s NULL-string matching only applies to UNQUOTED occurrences by
default, and every field in these exports is quoted; without it, a quoted `"NULL"`
would load as the four-character string `NULL`, not SQL `NULL`.

This is a deliberate deviation from the plan's original assumption, made because the
real data disagreed with it — the exporter had already solved the NULL/empty-string
ambiguity itself by choosing an unambiguous sentinel, so implementing "empty field →
NULL" instead would have been both unnecessary and wrong (it would silently coerce any
future genuine empty string to NULL instead of preserving it).

## `type="skip"` columns (mss.key.xml)

One sibling `.xml` file in the pilot's five schemas declares a `type="skip"` column:
`masterdata/MSS/key.xml` → `FILE_DEFAULT`. Inspection of `masterdata/MSS/key.csv` (624
data rows) shows `FILE_DEFAULT` is unconditionally the `NULL` sentinel in every single
row — it loads correctly as SQL `NULL` through the same uniform policy above, with no
column-exclusion logic needed. The loader still parses every sibling `.xml` and logs a
`NOTE:` for any table with a declared skip column, so a future dataset where a skip
column carries a real value is visible in the loader's own output, not silently wrong.

## Tables loaded (last recorded run: 82 tables, 3400 rows total)

| Schema | Tables loaded | Row count range | Notable |
|---|---|---|---|
| `auth` | 15 | 1 – 45 | `auth.role` (13), `auth.user_role` (45) |
| `tt` | 14 | 3 – 130 | `tt.event_type` (130 rows — the pilot's TICKET_INTERFACE/EVENT_INTERFACE reference this heavily) |
| `mss` | 47 | 1 – 804 | `mss.key` (624 rows), `mss.s_option_type2s_level` (804 rows), `mss.service_option_type` (447 rows) |
| `mcaudit` | 6 | 3 – 494 | `mcaudit.record_type` (494 rows) |
| `osag` | 0 | — | see "Skipped" below |

Full per-table row counts are printed by `load_masterdata.py` on every run (its own
stdout is the live source of truth; this table is a snapshot). 82 tables, not 83 (see
below).

## Skipped

- **`osag`: 0 tables.** `masterdata/OSAG/` contains only `#jdo_properties.csv` (DataNucleus
  ORM class-mapping metadata, not application reference data) — excluded by the loader's
  standing rule that any file starting with `#` is metadata, not a table (matches the
  `#jdo_properties.csv`/`.xml` pair present in every schema's masterdata directory, not
  just OSAG's).
- **`mss.scope`**: `masterdata/MSS/scope.csv` (columns `ID, NAME`) has no matching table
  anywhere in the loaded schema. The only table named `scope` in the whole database is
  `nids.scope` (columns `id, company_id, service_id` — a completely different shape,
  outside the pilot's schema set anyway). This is a genuine masterdata/schema mismatch
  — the table this reference data once belonged to appears to have been renamed, merged,
  or dropped since this masterdata snapshot was taken — not an ora2pg gap (there is no
  DDL anywhere, Oracle or PostgreSQL, for an `mss.scope` or equivalent (ID, NAME) table).
  Not loaded; not guessed at. Flagged here rather than silently ignored.

## Idempotency & re-running

`load_masterdata.py` `TRUNCATE`s every table it is about to load (single statement,
CASCADE, all target tables together — handles FK ordering for the truncate itself) at
the start of its one transaction, so re-running is always safe and produces identical
row counts.

## Verify

```
python3 migration/test/fixtures/load_masterdata.py --db mcdb_tmpl --schemas AUTH TT MSS MCAUDIT OSAG
```
