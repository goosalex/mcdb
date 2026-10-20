#!/usr/bin/env bash
# migration/test/run-all.sh
#
# The ONE command for the whole phase's verification (HARN-04's real deliverable).
# Composes what already exists -- it duplicates none of it:
#   spec_lint.py + trace_lint.py + provenance_lint.sh   (the three gates, fast, run first)
#   build-template.sh                                    (only if --rebuild-template or
#                                                          mcdb_tmpl is absent)
#   bootstrap.sh --db NAME --template mcdb_tmpl
#   run-tests.sh --db NAME --install migration/pgsql     (both harness halves, all
#                                                          discovered packages)
#
# Usage:
#   run-all.sh [--rebuild-template] [--db NAME]
#
#   --rebuild-template   Force a fresh mcdb_tmpl build via build-template.sh even if one
#                          already exists. Use after any change under
#                          migration/test/schema-fixes/ -- the template is NOT rebuilt
#                          automatically, and a stale template silently drops assertions
#                          (cost 5 during 02-12's own verification; see 02-13-SUMMARY.md).
#   --db NAME             Target database for the run (default: mcdb_test_all). Rebuilt
#                          from mcdb_tmpl every run -- disposable, per bootstrap.sh's own
#                          contract.
#
# Exit code: 0 only if all three gates pass AND run-tests.sh reports every discovered
# package PASS AND at least one test ran. Non-zero otherwise -- this script does not
# average, does not partially succeed, and does not hide a red gate behind a green test
# table or vice versa.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# PostgreSQL runs in a container (migration/db/pg.sh); start it before anything else.
PG="${SCRIPT_DIR}/../db/pg.sh"
bash "$PG" start
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SPEC_DIR="${REPO_ROOT}/migration/spec"

REBUILD_TEMPLATE=0
DB="mcdb_test_all"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rebuild-template) REBUILD_TEMPLATE=1; shift ;;
    --db) DB="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; echo "Usage: $0 [--rebuild-template] [--db NAME]" >&2; exit 1 ;;
  esac
done

echo "############################################################"
echo "# run-all.sh: the one command (HARN-04)"
echo "############################################################"

GATE_FAIL=0

# --- 1. The three gates (fast, and they fail for reasons that make the rest moot) -----

echo ""
echo "--- Gate 1/3: spec_lint.py (SPEC-02/SPEC-03) ---"
if python3 "${SPEC_DIR}/spec_lint.py"; then
  echo "spec_lint: PASS"
else
  echo "spec_lint: FAIL"
  GATE_FAIL=1
fi

echo ""
echo "--- Gate 2/3: trace_lint.py (HARN-05) ---"
if python3 "${SPEC_DIR}/trace_lint.py"; then
  echo "trace_lint: PASS"
else
  echo "trace_lint: FAIL"
  GATE_FAIL=1
fi

echo ""
echo "--- Gate 3/3: provenance_lint.sh (HARN-05 / T-02-06, anti-circularity) ---"
if bash "${SPEC_DIR}/provenance_lint.sh"; then
  echo "provenance_lint: PASS"
else
  echo "provenance_lint: FAIL"
  GATE_FAIL=1
fi

if [[ "$GATE_FAIL" -ne 0 ]]; then
  echo ""
  echo "run-all.sh: one or more gates FAILED -- stopping before the rest, per this" >&2
  echo "script's own design (gates fail for reasons that make the build/test run moot)." >&2
  exit 1
fi

# --- 2. Template (rebuild if asked, or if mcdb_tmpl is absent) -------------------------

echo ""
TMPL_EXISTS="$(bash "$PG" psql -X -v ON_ERROR_STOP=on -q -tAc "SELECT 1 FROM pg_database WHERE datname = 'mcdb_tmpl'" 2>/dev/null || true)"
if [[ "$REBUILD_TEMPLATE" -eq 1 || "$TMPL_EXISTS" != "1" ]]; then
  echo "--- Building mcdb_tmpl (--rebuild-template=${REBUILD_TEMPLATE}, exists=${TMPL_EXISTS:-0}) ---"
  bash "${SCRIPT_DIR}/build-template.sh"
else
  echo "--- mcdb_tmpl already exists, skipping build (pass --rebuild-template to force) ---"
  echo "    WARNING: if migration/test/schema-fixes/ changed since the template was last"
  echo "    built, it is now STALE -- re-run with --rebuild-template. build-template.sh"
  echo "    is not invoked automatically; a stale template silently drops assertions"
  echo "    (this cost 5 assertions during plan 02-12's own verification)."
fi

# --- 3. Bootstrap the target database from the template --------------------------------

echo ""
echo "--- bootstrap.sh --db ${DB} --template mcdb_tmpl ---"
bash "${SCRIPT_DIR}/bootstrap.sh" --db "$DB" --template mcdb_tmpl

# --- 4. Both harness halves, all discovered packages, installing the full pilot --------

echo ""
echo "--- run-tests.sh --db ${DB} --install migration/pgsql ---"
RUN_TESTS_RC=0
bash "${SCRIPT_DIR}/run-tests.sh" --db "$DB" --install "${REPO_ROOT}/migration/pgsql" || RUN_TESTS_RC=$?

# --- 5. Final summary --------------------------------------------------------------------

echo ""
echo "############################################################"
echo "# run-all.sh: FINAL SUMMARY"
echo "############################################################"
echo "gates:            $([[ "$GATE_FAIL" -eq 0 ]] && echo PASS || echo FAIL)"
echo "  spec_lint:       PASS"
echo "  trace_lint:      PASS"
echo "  provenance_lint: PASS"
echo "run-tests.sh exit: ${RUN_TESTS_RC} ($([[ "$RUN_TESTS_RC" -eq 0 ]] && echo PASS || echo FAIL))"
echo ""
echo "(the per-package PASS/FAIL table is printed above, by run-tests.sh itself --"
echo "not reproduced here, to avoid two sources of truth for the same numbers.)"

if [[ "$RUN_TESTS_RC" -ne 0 ]]; then
  echo ""
  echo "run-all.sh: FAIL -- see the per-package table above for which package(s) and" >&2
  echo "which half (pgTAP / regress) failed, and migration/PHASE2-FINDINGS.md /" >&2
  echo "migration/test/REDGREEN-EVIDENCE.md for the root-caused, evidenced explanation" >&2
  echo "of every currently-known-red assertion in this pilot." >&2
  exit 1
fi

echo ""
echo "run-all.sh: PASS -- all three gates green, every discovered package PASS."
exit 0
