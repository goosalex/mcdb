#!/usr/bin/env bash
# migration/test/bootstrap/40_fixtures.sh
#
# Bakes masterdata/ reference data into the target database via
# fixtures/load_masterdata.py, so that every database cloned from mcdb_tmpl (D-P8)
# starts with the pilot's reference tables already populated (HARN-03).
#
# Usage: 40_fixtures.sh --db NAME [--schemas SCHEMA...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="${SCRIPT_DIR}/.."

DB=""
SCHEMAS=(AUTH TT MSS MCAUDIT OSAG)
while [[ $# -gt 0 ]]; do
  case "$1" in
    --db) DB="$2"; shift 2 ;;
    --schemas)
      shift
      SCHEMAS=()
      while [[ $# -gt 0 && "$1" != --* ]]; do SCHEMAS+=("$1"); shift; done
      ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done
[[ -n "$DB" ]] || { echo "Usage: $0 --db NAME [--schemas SCHEMA...]" >&2; exit 1; }

echo "=== 40_fixtures.sh: target=${DB} schemas=${SCHEMAS[*]} ==="
python3 "${TEST_DIR}/fixtures/load_masterdata.py" --db "$DB" --schemas "${SCHEMAS[@]}"
