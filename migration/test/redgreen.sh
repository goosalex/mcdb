#!/usr/bin/env bash
# migration/test/redgreen.sh
#
# The mechanised form of Phase 2 success criterion 5: red-before/green-after
# is a repeatable gate, not a one-time anecdote. Later plans in this phase
# invoke this before claiming a package's translation is verified.
#
# Usage:
#   redgreen.sh --db NAME --install DIR [--package PKG]
#
#   --db NAME       Disposable database name (must pass bootstrap.sh's
#                    T-02-01 name allowlist). Rebuilt from the template
#                    twice — once for RED, once for GREEN.
#   --install DIR   Directory of translated *.sql to install for the GREEN
#                    phase (and to withhold for the RED phase).
#   --package PKG   Restrict run-tests.sh to this package only
#                    (pg_schema.oracle_package_lower). Optional; if omitted,
#                    all discovered packages are exercised.
#
# Phase 1 — RED: build NAME fresh from the template WITHOUT installing DIR,
#   then run run-tests.sh --db NAME (optionally --package PKG). This MUST
#   exit non-zero — the translated objects do not exist yet, so every
#   assertion against them errors. If it exits 0, ABORT with
#   "RED PHASE DID NOT FAIL — the tests do not actually exercise the
#   translation": that is the single most valuable thing this script does,
#   because it catches a test suite that would pass even against a
#   nonexistent implementation. Output captured to redgreen-red.log.
#
# Phase 2 — GREEN: rebuild NAME from the template, install DIR, re-run. This
#   MUST exit zero. Output captured to redgreen-green.log.
#
# Exit 0 only if both phases behaved as required; prints
# "RED->GREEN PROVEN for: <packages>".

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# PostgreSQL runs in a container (migration/db/pg.sh); start it before anything else.
PG="${SCRIPT_DIR}/../db/pg.sh"
bash "$PG" start
LOG_DIR="${SCRIPT_DIR}/regress/results"
mkdir -p "$LOG_DIR"

DB=""
INSTALL_DIR=""
PKG_FILTER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --db) DB="$2"; shift 2 ;;
    --install) INSTALL_DIR="$2"; shift 2 ;;
    --package) PKG_FILTER="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$DB" || -z "$INSTALL_DIR" ]]; then
  echo "Usage: $0 --db NAME --install DIR [--package PKG]" >&2
  exit 1
fi

if [[ ! -d "$INSTALL_DIR" ]]; then
  echo "FATAL: --install directory does not exist: ${INSTALL_DIR}" >&2
  exit 1
fi

RED_LOG="${LOG_DIR}/redgreen-red.log"
GREEN_LOG="${LOG_DIR}/redgreen-green.log"

run_tests_args=(--db "$DB")
[[ -n "$PKG_FILTER" ]] && run_tests_args+=(--package "$PKG_FILTER")

# --- Phase 1: RED -----------------------------------------------------------

echo "redgreen.sh: RED phase — building '${DB}' from template WITHOUT installing ${INSTALL_DIR}"
bash "${SCRIPT_DIR}/bootstrap.sh" --db "$DB"

set +e
bash "${SCRIPT_DIR}/run-tests.sh" "${run_tests_args[@]}" >"$RED_LOG" 2>&1
RED_RC=$?
set -e

if [[ "$RED_RC" -eq 0 ]]; then
  echo "RED PHASE DID NOT FAIL — the tests do not actually exercise the translation" >&2
  echo "See ${RED_LOG} for the run that should have failed but didn't." >&2
  exit 1
fi
echo "redgreen.sh: RED phase failed as required (exit ${RED_RC}). See ${RED_LOG}"

# --- Phase 2: GREEN ----------------------------------------------------------

echo "redgreen.sh: GREEN phase — rebuilding '${DB}' from template and installing ${INSTALL_DIR}"
bash "${SCRIPT_DIR}/bootstrap.sh" --db "$DB"

set +e
bash "${SCRIPT_DIR}/run-tests.sh" "${run_tests_args[@]}" --install "$INSTALL_DIR" >"$GREEN_LOG" 2>&1
GREEN_RC=$?
set -e

if [[ "$GREEN_RC" -ne 0 ]]; then
  echo "GREEN PHASE FAILED — translated objects installed but tests still fail" >&2
  echo "See ${GREEN_LOG}" >&2
  cat "$GREEN_LOG" >&2
  exit 1
fi
echo "redgreen.sh: GREEN phase passed (exit 0). See ${GREEN_LOG}"

PACKAGES="$(grep -oE '^[a-z_0-9]+\.[a-z_0-9]+' "$GREEN_LOG" | sort -u | tr '\n' ' ')"
[[ -n "$PKG_FILTER" ]] && PACKAGES="$PKG_FILTER"

echo "RED->GREEN PROVEN for: ${PACKAGES}"
exit 0
