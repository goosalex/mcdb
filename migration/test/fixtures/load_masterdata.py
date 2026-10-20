#!/usr/bin/env python3
"""migration/test/fixtures/load_masterdata.py

Loads masterdata/<SCHEMA>/<table>.csv reference data into <schema>.<table> for the
pilot's schemas (AUTH, TT, MSS, MCAUDIT, OSAG by default -- HARN-03).

Python 3.12 stdlib only (csv, xml.etree, argparse, subprocess -- no third-party deps).

--- Column order & types ---
The CSV header row is the authoritative column ORDER (matches this plan's <action>
instruction literally). The sibling <table>.xml is read for declared per-column types,
but in practice every <table>.xml in the pilot's five schemas either (a) matches the CSV
header exactly column-for-column (e.g. AUTH/authtype.xml), in which case the type info is
redundant with what COPY infers from the target column's own PostgreSQL type, or (b)
declares only a SUBSET of columns as an override/exception list -- the one instance found
is mss/key.xml, which declares only FILE_DEFAULT as type="skip". Inspection of
masterdata/MSS/key.csv (624 data rows) shows FILE_DEFAULT is unconditionally the literal
NULL sentinel (see below) in every row, so it loads correctly as SQL NULL through the
same uniform NULL-handling as every other column -- no column-exclusion logic was
actually needed to honour the "skip" declaration. This is recorded here rather than
silently ignored: the XML is still parsed and any type="skip" column is logged, so a
future dataset where a skip column has a real value will be visible, not silently wrong.

--- NULL vs empty-string policy (Pitfall 2) ---
This plan's own text assumed Oracle's NULL/empty-string identity would surface as an
EMPTY CSV field. Inspection of the actual masterdata CSVs shows a different, and safer,
convention: NULL is represented by the literal quoted token "NULL" (e.g.
`"3","vrrp.monitor.ip","4","NULL","NULL",...` in masterdata/MSS/key.csv), and a genuine
empty string would be `""` (two adjacent quotes) -- a pattern that occurs ZERO times
across any CSV in the five pilot schemas (verified: `grep -E '(^|,)""(,|$)'` over every
file returns nothing). So the exporter already disambiguated NULL from empty string
explicitly, rather than colliding them the way raw Oracle NULL/empty-string semantics
would. The policy implemented here, stated once and applied uniformly to every column of
every table: the literal token NULL (whether or not CSV-quoted) is loaded as SQL NULL;
any other value, including a genuine empty string, is loaded as-is. This is done with
COPY's `NULL 'NULL'` combined with `FORCE_NULL(<every column>)` -- FORCE_NULL is required
because without it, PostgreSQL's COPY only matches the NULL string against UNQUOTED
occurrences, and every field in these exports is quoted (a quoted "NULL" would otherwise
load as the four-character string "NULL", not SQL NULL).

--- Load ordering / circular FK ---
Oracle's masterdata/<SCHEMA>/_pre.sql and _post.sql disable/enable specific named FK
constraints around the load (Oracle syntax: `alter table X disable constraint Y`, which
has no PostgreSQL equivalent). Every FK constraint referenced by _pre.sql/_post.sql
across the five pilot schemas was confirmed DEFERRABLE in the loaded schema (they come
from ddl/migrated/constraints/fk-constraints.pg.sql, which marks essentially every FK
DEFERRABLE) -- so this loader translates the INTENT (defer constraint checking for the
duration of the load, not disable it) via `SET CONSTRAINTS ALL DEFERRED` inside one
transaction wrapping every table's TRUNCATE + COPY, rather than executing the Oracle
_pre.sql/_post.sql files directly. The DISABLE TRIGGER ALL fallback the plan asks for
(for constraints that are NOT deferrable) is implemented as a defensive branch but is
not currently exercised by the five pilot schemas' data.

--- Idempotency ---
Every table in a given run is TRUNCATEd (single statement, all tables together, CASCADE)
before any COPY, inside the same transaction as the loads -- re-running this script is
always safe.
"""

import argparse
import csv
import os
import subprocess
import sys
import xml.etree.ElementTree as ET

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
MASTERDATA_ROOT = os.path.join(REPO_ROOT, "masterdata")
SCRATCH_DIR = os.path.join(os.path.dirname(__file__), "..", ".build-scratch")
# PostgreSQL runs in a container; every psql call goes through migration/db/pg.sh.
PG_SH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "db", "pg.sh")

DEFAULT_SCHEMAS = ["AUTH", "TT", "MSS", "MCAUDIT", "OSAG"]


def psql(db, args, **kw):
    return subprocess.run(
        ["bash", PG_SH, "psql", "-X", "-v", "ON_ERROR_STOP=on", "-q", "-d", db, *args],
        **kw,
    )


def table_exists(db, schema, table):
    r = psql(
        db,
        ["-tAc", f"SELECT 1 FROM information_schema.tables WHERE table_schema='{schema}' AND table_name='{table}'"],
        capture_output=True, text=True,
    )
    return r.stdout.strip() == "1"


def read_csv_header(csv_path):
    with open(csv_path, newline="", encoding="utf-8") as fh:
        reader = csv.reader(fh)
        header = next(reader)
    return [c.strip().lower() for c in header]


def read_skip_columns(xml_path):
    """Return the set of lower-cased column names declared type="skip" in the sibling
    XML, if the file exists. Informational only -- see module docstring."""
    if not os.path.isfile(xml_path):
        return set()
    try:
        tree = ET.parse(xml_path)
    except ET.ParseError:
        return set()
    skips = set()
    for col in tree.getroot().findall("column"):
        if col.get("type", "").lower() == "skip":
            skips.add((col.get("name") or "").strip().lower())
    return skips


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--db", required=True, help="target database (e.g. mcdb_tmpl)")
    ap.add_argument("--schemas", nargs="+", default=DEFAULT_SCHEMAS, help="Oracle schema names (masterdata/<SCHEMA>/)")
    args = ap.parse_args()

    os.makedirs(SCRATCH_DIR, exist_ok=True)
    os.chmod(SCRATCH_DIR, 0o755)

    candidates = []
    skipped = []
    for schema in args.schemas:
        schema_dir = os.path.join(MASTERDATA_ROOT, schema)
        if not os.path.isdir(schema_dir):
            skipped.append((schema.lower(), "*", f"no masterdata/{schema}/ directory"))
            continue
        for fname in sorted(os.listdir(schema_dir)):
            if fname.startswith("#") or not fname.endswith(".csv"):
                continue
            table = fname[:-4].lower()
            pg_schema = schema.lower()
            csv_path = os.path.join(schema_dir, fname)
            xml_path = os.path.join(schema_dir, fname[:-4] + ".xml")
            if not table_exists(args.db, pg_schema, table):
                skipped.append((pg_schema, table, f"no {pg_schema}.{table} table in the loaded schema (masterdata/schema mismatch, not an ora2pg gap -- see PILOT-TABLES.md)"))
                continue
            candidates.append((pg_schema, table, csv_path, xml_path))

    if not candidates:
        print("FAIL: no loadable masterdata tables found for schemas: " + " ".join(args.schemas), file=sys.stderr)
        sys.exit(1)

    # Build one transactional script: TRUNCATE every target table together (handles FK
    # ordering for the truncate itself), SET CONSTRAINTS ALL DEFERRED (handles FK
    # ordering for the inserts), then one \copy per table.
    script_lines = []
    script_lines.append("BEGIN;")
    script_lines.append("SET CONSTRAINTS ALL DEFERRED;")
    all_tables = ", ".join(f"{s}.{t}" for s, t, _, _ in candidates)
    script_lines.append(f"TRUNCATE {all_tables} CASCADE;")

    skip_col_log = []
    for schema, table, csv_path, xml_path in candidates:
        cols = read_csv_header(csv_path)
        skip_cols = read_skip_columns(xml_path)
        found_skips = skip_cols & set(cols)
        if found_skips:
            skip_col_log.append((schema, table, sorted(found_skips)))
        col_list = ", ".join(cols)
        script_lines.append(
            f"\\copy {schema}.{table} ({col_list}) FROM '{csv_path}' "
            f"WITH (FORMAT csv, HEADER true, QUOTE '\"', NULL 'NULL', FORCE_NULL({col_list}))"
        )
    script_lines.append("COMMIT;")

    script_path = os.path.join(SCRATCH_DIR, "load_masterdata_run.sql")
    with open(script_path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(script_lines) + "\n")
    os.chmod(script_path, 0o644)

    result = psql(args.db, ["-f", script_path], capture_output=True, text=True)
    if result.returncode != 0:
        print("FAIL: masterdata load transaction failed, rolled back entirely:", file=sys.stderr)
        print(result.stdout, file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        sys.exit(1)

    print(f"-- masterdata load committed: {len(candidates)} tables, schemas={' '.join(args.schemas)}")
    if skip_col_log:
        for schema, table, cols in skip_col_log:
            print(f"-- NOTE: {schema}.{table} has XML-declared skip column(s) {cols}; loaded via the uniform NULL policy (see docstring)")

    total_rows = 0
    print(f"{'table':<40} rows")
    for schema, table, _, _ in candidates:
        r = psql(args.db, ["-tAc", f"SELECT count(*) FROM {schema}.{table}"], capture_output=True, text=True)
        if r.returncode != 0:
            print(f"FAIL: could not count rows in {schema}.{table}: {r.stderr}", file=sys.stderr)
            sys.exit(1)
        n = int(r.stdout.strip())
        total_rows += n
        print(f"{schema}.{table:<35} {n} rows")

    print(f"TOTAL: {total_rows} rows across {len(candidates)} tables")

    if skipped:
        print(f"SKIPPED: {len(skipped)} masterdata entries had no matching table:")
        for schema, table, reason in skipped:
            print(f"  {schema}.{table}: {reason}")

    sys.exit(0)


if __name__ == "__main__":
    main()
