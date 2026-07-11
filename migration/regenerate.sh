#!/usr/bin/env bash
# regenerate.sh -- one command to regenerate and validate the whole Phase 1
# foundation (inventory.json, name-map.csv, depgraph.json/.dot) plus every
# gate and the full test suite.
#
# Default mode: regenerates all three artifacts in place (overwriting the
# checked-in copies), then runs every --check gate, then the full unittest
# suite. Run this after any change under ddl/src.
#
#   bash migration/regenerate.sh
#
# --check mode: proves the checked-in artifacts are NOT stale and NOT
# hand-edited. Regenerates every artifact into a temp directory and diffs
# each against its checked-in counterpart (normalizing the volatile
# `generated_at` timestamp on both sides first -- generator_version is
# NOT normalized, so a version bump still forces a regenerate). Also runs
# every --check gate and the full unittest suite, so one command answers
# "is the whole Phase 1 foundation currently valid". Never writes to the
# checked-in files.
#
#   bash migration/regenerate.sh --check
#
# Either mode asserts `git status --porcelain ddl/` is empty afterwards --
# nothing under this pipeline may ever mutate the Oracle source it reads
# (threat T-01-01 / T-01-07).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ANALYZE_DIR="$SCRIPT_DIR/analyze"
MAPPING_DIR="$SCRIPT_DIR/mapping"

MODE="${1:-}"

run_test_suites() {
  echo "--- running migration/analyze/tests ---"
  python3 -m unittest discover -s "$ANALYZE_DIR/tests" -v
  echo "--- running migration/mapping/tests ---"
  python3 -m unittest discover -s "$MAPPING_DIR/tests" -v
}

run_check_gates() {
  echo "--- inventory.py --check ---"
  python3 "$ANALYZE_DIR/inventory.py" --check
  echo "--- name_map.py --check ---"
  python3 "$MAPPING_DIR/name_map.py" --check
  echo "--- depgraph.py --check ---"
  python3 "$ANALYZE_DIR/depgraph.py" --check
}

assert_ddl_untouched() {
  local status
  status="$(cd "$REPO_ROOT" && git status --porcelain ddl/)"
  if [ -n "$status" ]; then
    echo "FATAL: ddl/ was modified by the regeneration pipeline (threat T-01-01/T-01-07):" >&2
    echo "$status" >&2
    exit 1
  fi
}

# Strips the volatile `generated_at` timestamp before comparing two JSON
# artifacts, so --check doesn't fire on a no-op re-run. `generator_version`
# is deliberately left in place -- a version bump SHOULD force a regenerate.
normalize_json() {
  python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
d.pop('generated_at', None)
json.dump(d, sys.stdout, indent=2, sort_keys=False)
print()
" "$1"
}

if [ "$MODE" = "--check" ]; then
  TMPDIR="$(mktemp -d)"
  trap 'rm -rf "$TMPDIR"' EXIT
  mkdir -p "$TMPDIR/analyze" "$TMPDIR/mapping"

  echo "--- regenerating into $TMPDIR to diff against checked-in artifacts ---"
  python3 "$ANALYZE_DIR/inventory.py" \
    --inventory-path "$TMPDIR/analyze/inventory.json"
  python3 "$MAPPING_DIR/name_map.py" \
    --inventory-path "$TMPDIR/analyze/inventory.json" \
    --overrides-path "$MAPPING_DIR/overrides.csv" \
    --output-path "$TMPDIR/mapping/name-map.csv"
  python3 "$ANALYZE_DIR/depgraph.py" \
    --inventory-path "$TMPDIR/analyze/inventory.json" \
    --name-map-path "$TMPDIR/mapping/name-map.csv" \
    --known-cycles-path "$ANALYZE_DIR/known_cycles.json" \
    --output-json-path "$TMPDIR/analyze/depgraph.json" \
    --output-dot-path "$TMPDIR/analyze/depgraph.dot"

  echo "--- diffing regenerated artifacts against checked-in copies (generated_at normalized) ---"
  STALE=0

  if ! diff -u <(normalize_json "$ANALYZE_DIR/inventory.json") <(normalize_json "$TMPDIR/analyze/inventory.json"); then
    echo "STALE: migration/analyze/inventory.json differs from a fresh regenerate" >&2
    STALE=1
  fi
  if ! diff -u "$MAPPING_DIR/name-map.csv" "$TMPDIR/mapping/name-map.csv"; then
    echo "STALE: migration/mapping/name-map.csv differs from a fresh regenerate" >&2
    STALE=1
  fi
  if ! diff -u <(normalize_json "$ANALYZE_DIR/depgraph.json") <(normalize_json "$TMPDIR/analyze/depgraph.json"); then
    echo "STALE: migration/analyze/depgraph.json differs from a fresh regenerate" >&2
    STALE=1
  fi
  if ! diff -u "$ANALYZE_DIR/depgraph.dot" "$TMPDIR/analyze/depgraph.dot"; then
    echo "STALE: migration/analyze/depgraph.dot differs from a fresh regenerate" >&2
    STALE=1
  fi

  if [ "$STALE" -ne 0 ]; then
    echo "FATAL: one or more checked-in artifacts are stale or hand-edited. Run 'bash migration/regenerate.sh' (no --check) and commit the result." >&2
    exit 1
  fi
  echo "--- all checked-in artifacts match a fresh regenerate ---"

  run_check_gates
  run_test_suites
  assert_ddl_untouched
  echo "--check: OK -- the whole Phase 1 foundation is valid and not stale"
  exit 0
fi

echo "--- regenerating migration/analyze/inventory.json ---"
python3 "$ANALYZE_DIR/inventory.py"

echo "--- regenerating migration/mapping/name-map.csv ---"
python3 "$MAPPING_DIR/name_map.py"

echo "--- regenerating migration/analyze/depgraph.json + depgraph.dot ---"
python3 "$ANALYZE_DIR/depgraph.py"

run_check_gates
run_test_suites
assert_ddl_untouched

echo "regenerate.sh: OK -- all artifacts regenerated, every gate and test suite passed"
