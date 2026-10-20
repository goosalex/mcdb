#!/usr/bin/env bash
# migration/test/bootstrap/20_ddl.sh
#
# Loads the real ora2pg-converted schema (ddl/migrated/tables/, ddl/migrated/constraints/)
# into the target database, errors surfaced, never swallowed (T-02-09).
#
# Usage: 20_ddl.sh --db NAME
#
# THE LANDMINE THIS FILE EXISTS TO DEFUSE:
# ddl/migrated/tables/tables.pg.sql and ddl/migrated/tables/views.pg.sql both open with
# `\set ON_ERROR_STOP OFF`. A naive `psql -f` load of either "succeeds" (exit 0) while
# silently skipping every broken statement inside -- the single most dangerous outcome
# this plan can produce, because Phase 5 would inherit a schema nobody ever actually
# proved loads. Two independent defences, neither alone sufficient:
#   1. Every `\set ON_ERROR_STOP ...` line is stripped from the stream before it reaches
#      psql -- a file's own directive can never re-disable (or re-enable) the flag we
#      set from outside mid-stream.
#   2. Every psql invocation below passes -v ON_ERROR_STOP=on explicitly. (psql's own
#      default, with no -v flag at all, is OFF -- relying on a file's internal directive
#      was never safe to begin with, even for files that never mention it.)
#
# tables.pg.sql is loaded STRICT (ON_ERROR_STOP=on, the whole load aborts non-zero on the
# FIRST error). After bootstrap/10_schemas_roles.sql's two fixes (postgresadmin role,
# checklist schema -- see ../SCHEMA-FIXES.md fixes #1-#2), this file is expected to load
# with ZERO errors. This is the plan's literal, provable hard-fail demonstration: run
# this file today with fix #2 reverted (`git stash` the checklist DO block) and the
# load aborts at the first `schema "checklist" does not exist` error instead of
# finishing "successfully" with 43 silently-dropped tables.
#
# The constraint and view files are known, at THIS stage (before schema-fixes/
# 10_ora2pg_fixes.sql has run), to contain a fixed, enumerated set of ora2pg errors --
# every one recorded in ../SCHEMA-FIXES.md. They are loaded in INVENTORY mode
# (ON_ERROR_STOP=off, one psql invocation per file, collecting every failure) and the
# resulting failure line-number set is diffed against the EXPECTED_* arrays below. A
# match is not "swallowed" -- it is an explicitly reconciled, ledgered, expected
# discrepancy, printed in full either way. Any statement that fails OUTSIDE the expected
# set (a regression, or ora2pg output that changed) aborts the whole build non-zero.
#
# tables/constraints.pg.sql is DELIBERATELY NOT LOADED (SCHEMA-FIXES.md decision D-1):
# it is a duplicate, NON-deferrable export of the identical 843 FK constraints found in
# constraints/fk-constraints.pg.sql (which IS deferrable -- required by
# fixtures/load_masterdata.py's SET CONSTRAINTS ALL DEFERRED strategy). Loading both
# would produce 843 "constraint already exists" errors for no benefit.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# PostgreSQL runs in a container (migration/db/pg.sh); start it before anything else.
PG="${SCRIPT_DIR}/../../db/pg.sh"
bash "$PG" start
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
TEST_DIR="${SCRIPT_DIR}/.."
SCRATCH_DIR="${TEST_DIR}/.build-scratch"

DB=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --db) DB="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done
[[ -n "$DB" ]] || { echo "Usage: $0 --db NAME" >&2; exit 1; }

mkdir -p "$SCRATCH_DIR"
chmod 755 "$SCRATCH_DIR"

psql_super() {
  bash "$PG" psql -X -v ON_ERROR_STOP=on -q -d "$DB" "$@"
}

# Strip every `\set ON_ERROR_STOP ...` line from $1, write result to $2, make it
# world-readable (the postgres OS user, reached via sudo peer auth, must be able to
# read it -- see 02-01-SUMMARY.md's /home/ubuntu o+x deviation).
strip_error_stop() {
  local src="$1" dst="$2"
  grep -v '^\\set ON_ERROR_STOP' "$src" > "$dst"
  chmod 644 "$dst"
}

# Run $file in inventory mode (ON_ERROR_STOP=off): every statement is attempted, every
# failure is captured with its source line number, nothing aborts the whole file. The
# caller then reconciles the returned line-number set against an expected allowlist.
run_inventory() {
  local file="$1" label="$2"
  local log="${SCRATCH_DIR}/$(basename "$file").log"
  bash "$PG" psql -X -v ON_ERROR_STOP=off -q -d "$DB" -f "$file" > "$log" 2>&1 || true
  local lines
  lines="$(grep -oE ":[0-9]+: ERROR" "$log" | grep -oE '[0-9]+' | sort -n -u | tr '\n' ' ')"
  echo "-- ${label}: failed statement line numbers: [${lines}]" >&2
  if grep -q "ERROR" "$log"; then
    grep -B0 -A1 "ERROR" "$log" | sed 's/^/     /' >&2
  fi
  echo "$lines"
}

assert_line_set() {
  local label="$1" actual="$2" expected="$3"
  local a_sorted e_sorted
  a_sorted="$(echo "$actual" | tr ' ' '\n' | sed '/^$/d' | sort -n | tr '\n' ',')"
  e_sorted="$(echo "$expected" | tr ' ' '\n' | sed '/^$/d' | sort -n | tr '\n' ',')"
  if [[ "$a_sorted" != "$e_sorted" ]]; then
    echo "FATAL: ${label} failure set changed." >&2
    echo "  expected line numbers: ${e_sorted}" >&2
    echo "  actual   line numbers: ${a_sorted}" >&2
    echo "This is either a regression or ora2pg output that changed underneath this" >&2
    echo "plan's fixed expectations -- surfaced hard, not swallowed. Update" >&2
    echo "migration/test/SCHEMA-FIXES.md and this script's EXPECTED_* list deliberately" >&2
    echo "if the new failure set is understood and correct." >&2
    exit 1
  fi
  echo "-- ${label}: failure set matches the ledgered/expected set (${a_sorted:-none}) -- OK"
}

echo "=== 20_ddl.sh: target=${DB} ==="

# --- tables.pg.sql: STRICT load, must be zero-error after 10_schemas_roles.sql's fixes ---
echo "-- loading tables.pg.sql (STRICT: ON_ERROR_STOP=on, aborts hard on ANY error)"
strip_error_stop "${REPO_ROOT}/ddl/migrated/tables/tables.pg.sql" "${SCRATCH_DIR}/tables_stripped.sql"
psql_super -f "${SCRATCH_DIR}/tables_stripped.sql" > "${SCRATCH_DIR}/tables_load.log" 2>&1
echo "-- tables.pg.sql: 548 tables loaded, zero errors (strict pass proves ON_ERROR_STOP=on works: see SCHEMA-FIXES.md fix demonstration)"

# --- constraints/fk-constraints.pg.sql: inventory mode, reconcile against known 15 ---
EXPECTED_FK="569 637 638 643 644 762 764 766 772 773 774 787 795 803 804"
actual_fk="$(run_inventory "${REPO_ROOT}/ddl/migrated/constraints/fk-constraints.pg.sql" "fk-constraints.pg.sql")"
assert_line_set "fk-constraints.pg.sql" "$actual_fk" "$EXPECTED_FK"

# --- constraints/check-constraints.pg.sql: inventory mode, reconcile against known 1 ---
EXPECTED_CHECK="18"
actual_check="$(run_inventory "${REPO_ROOT}/ddl/migrated/constraints/check-constraints.pg.sql" "check-constraints.pg.sql")"
assert_line_set "check-constraints.pg.sql" "$actual_check" "$EXPECTED_CHECK"

# --- tables/views.pg.sql: inventory mode, reconcile against known 4 (line numbers are
#     relative to the STRIPPED file, since the directive line is removed before load) ---
EXPECTED_VIEWS="33 210 256 411"
strip_error_stop "${REPO_ROOT}/ddl/migrated/tables/views.pg.sql" "${SCRATCH_DIR}/views_stripped.sql"
actual_views="$(run_inventory "${SCRATCH_DIR}/views_stripped.sql" "views.pg.sql")"
assert_line_set "views.pg.sql" "$actual_views" "$EXPECTED_VIEWS"

echo "=== 20_ddl.sh: base load complete. 15 FK + 1 (merged, 3-statement) check-constraint +"
echo "    4 view failures are EXPECTED at this stage -- see SCHEMA-FIXES.md. The FK and"
echo "    check-constraint failures are fixed next by schema-fixes/10_ora2pg_fixes.sql;"
echo "    the 4 view failures are deferred (non-pilot, documented, left broken)."
