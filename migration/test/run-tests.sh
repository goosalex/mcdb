#!/usr/bin/env bash
# migration/test/run-tests.sh
#
# The one-command harness runner (HARN-04). Runs BOTH harness halves —
# pgTAP via pg_prove (HARN-01) and plain-SQL expected-output diffing
# (HARN-02) — against one database, and prints one pass/fail row per Oracle
# package.
#
# Usage:
#   run-tests.sh [--db NAME] [--install DIR] [--package PKG] [--filter GLOB]
#
#   --db NAME       Target database. Default: mcdb_test. If it does not
#                    exist, bootstrap.sh is invoked to create it (template
#                    mode — requires mcdb_tmpl to exist, or pass --db to an
#                    already-bootstrapped database).
#   --install DIR   Load every *.sql under DIR into the database, sorted by
#                    path, with ON_ERROR_STOP=on, before running any tests.
#                    A load failure aborts with a non-zero exit and prints
#                    the offending file.
#   --package PKG   Restrict both halves to files whose parsed package is
#                    exactly PKG (format: pg_schema.oracle_package_lower).
#   --filter GLOB   Restrict both halves to files whose basename matches
#                    GLOB (shell glob, applied via bash [[ == ]] pattern
#                    matching).
#
# Exit code: 0 only if every discovered package passed AND at least one test
# ran. Zero tests discovered is a non-zero exit — an empty suite silently
# "passing" is the exact failure this harness exists to prevent.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PGTAP_DIR="${SCRIPT_DIR}/pgtap"
REGRESS_SQL_DIR="${SCRIPT_DIR}/regress/sql"
REGRESS_EXPECTED_DIR="${SCRIPT_DIR}/regress/expected"
REGRESS_RESULTS_DIR="${SCRIPT_DIR}/regress/results"
PKGNAME_PY="${SCRIPT_DIR}/lib/pkgname.py"

DB="mcdb_test"
INSTALL_DIR=""
PKG_FILTER=""
GLOB_FILTER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --db) DB="$2"; shift 2 ;;
    --install) INSTALL_DIR="$2"; shift 2 ;;
    --package) PKG_FILTER="$2"; shift 2 ;;
    --filter) GLOB_FILTER="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

psql_super() {
  sudo -u postgres psql -X -q -v ON_ERROR_STOP=on "$@"
}

db_exists() {
  [[ "$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname = '${DB}'")" == "1" ]]
}

# --- 1. Ensure the target database exists ----------------------------------

if ! db_exists; then
  echo "run-tests.sh: database '${DB}' does not exist, bootstrapping..."
  bash "${SCRIPT_DIR}/bootstrap.sh" --db "${DB}"
fi

# --- 2. Optionally install translated objects -------------------------------

if [[ -n "$INSTALL_DIR" ]]; then
  if [[ ! -d "$INSTALL_DIR" ]]; then
    echo "FATAL: --install directory does not exist: ${INSTALL_DIR}" >&2
    exit 1
  fi
  echo "run-tests.sh: installing *.sql from ${INSTALL_DIR} (sorted by path)..."
  while IFS= read -r -d '' f; do
    if ! sudo -u postgres psql -X -q -v ON_ERROR_STOP=on -d "$DB" -f "$f" >/tmp/run-tests-install.log 2>&1; then
      echo "FATAL: load failed for ${f}" >&2
      cat /tmp/run-tests-install.log >&2
      exit 1
    fi
  done < <(find "$INSTALL_DIR" -type f -name '*.sql' -print0 | sort -z)
fi

# --- 3. Discover + validate test files against the name-map SSOT -----------

mkdir -p "$REGRESS_RESULTS_DIR"

matches_filters() {
  local file="$1"
  local base
  base="$(basename "$file")"
  if [[ -n "$GLOB_FILTER" ]]; then
    [[ "$base" == $GLOB_FILTER ]] || return 1
  fi
  if [[ -n "$PKG_FILTER" ]]; then
    local pkg
    pkg="$(python3 "$PKGNAME_PY" --list "$file" 2>/dev/null | cut -f1)"
    [[ "$pkg" == "$PKG_FILTER" ]] || return 1
  fi
  return 0
}

# pkgname.py --list with no args discovers pgtap/*.sql and regress/sql/*.sql
# on its own and validates every file's (pg_schema, oracle_package) pair
# against migration/mapping/name-map.csv. A non-zero exit here means the SSOT
# rejected a filename — abort before running anything (D-P9).
if ! LISTING="$(python3 "$PKGNAME_PY" --list)"; then
  echo "FATAL: pkgname.py rejected one or more test files (SSOT violation)" >&2
  python3 "$PKGNAME_PY" --list >/dev/null
  exit 1
fi

PGTAP_FILES=()
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  f="$(printf '%s' "$line" | cut -f2)"
  [[ "$f" == "${PGTAP_DIR}/"* ]] || continue
  matches_filters "$f" || continue
  PGTAP_FILES+=("$f")
done <<< "$LISTING"

REGRESS_FILES=()
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  f="$(printf '%s' "$line" | cut -f2)"
  [[ "$f" == "${REGRESS_SQL_DIR}/"* ]] || continue
  matches_filters "$f" || continue
  REGRESS_FILES+=("$f")
done <<< "$LISTING"

# --- Collect the union of packages across both halves -----------------------

declare -A PACKAGES=()
for f in "${PGTAP_FILES[@]:-}"; do
  [[ -z "$f" ]] && continue
  pkg="$(python3 "$PKGNAME_PY" --list "$f" | cut -f1)"
  PACKAGES["$pkg"]=1
done
for f in "${REGRESS_FILES[@]:-}"; do
  [[ -z "$f" ]] && continue
  pkg="$(python3 "$PKGNAME_PY" --list "$f" | cut -f1)"
  PACKAGES["$pkg"]=1
done

TOTAL_TESTS_RUN=0

declare -A PGTAP_PASS=()
declare -A PGTAP_TOTAL=()
declare -A REGRESS_PASS=()
declare -A REGRESS_TOTAL=()
declare -A PKG_FAILED=()

# --- 4. pgTAP half (HARN-01) -------------------------------------------------

for pkg in "${!PACKAGES[@]}"; do
  PGTAP_PASS["$pkg"]=0
  PGTAP_TOTAL["$pkg"]=0
  REGRESS_PASS["$pkg"]=0
  REGRESS_TOTAL["$pkg"]=0
  PKG_FAILED["$pkg"]=0
done

for f in "${PGTAP_FILES[@]:-}"; do
  [[ -z "$f" ]] && continue
  pkg="$(python3 "$PKGNAME_PY" --list "$f" | cut -f1)"
  TAP_OUT="$(mktemp)"
  set +e
  sudo -u postgres pg_prove --ext .sql -d "$DB" "$f" >"$TAP_OUT" 2>&1
  RC=$?
  set -e
  # Count assertions HONESTLY, per file. The old logic credited a file's passing
  # assertions only when the WHOLE file passed (RC==0), so a 9-of-10 file reported
  # "0/10" -- and an aborted file reported "0/0", hiding its planned assertions
  # entirely. Both misreport HARN-04's per-package pass/fail contract.
  #
  # pg_prove gives us two shapes:
  #   partial: "Failed 1/10 subtests"   + "(Wstat: 0   Tests: 10 Failed: 1)"
  #   aborted: "Failed 20/20 subtests"  + "(Wstat: 768 Tests: 0  Failed: 0)"
  #   all-ok : (no "Failed X/Y" line)   + "(Wstat: 0   Tests: 10 Failed: 0)"
  # The "Failed X/Y subtests" line carries the PLANNED total (Y) even when the file
  # aborted after 0 assertions, so prefer it; fall back to "Tests: N" when absent.
  SUBTEST_LINE=$(grep -oE 'Failed [0-9]+/[0-9]+ subtests' "$TAP_OUT" | head -1 || true)
  if [[ -n "$SUBTEST_LINE" ]]; then
    NFAILED=$(sed -E 's|Failed ([0-9]+)/([0-9]+) subtests|\1|' <<<"$SUBTEST_LINE")
    NTOTAL=$(sed -E 's|Failed ([0-9]+)/([0-9]+) subtests|\2|' <<<"$SUBTEST_LINE")
  else
    # All-pass case: pg_prove prints no "(Wstat: ...)" line at all, only the
    # "Files=1, Tests=10, ..." summary (note '=' not ':').
    NTOTAL=$(grep -oE 'Tests=[0-9]+' "$TAP_OUT" | head -1 | grep -oE '[0-9]+' || true)
    [[ -z "$NTOTAL" ]] && NTOTAL=$(grep -oE 'Tests: +[0-9]+' "$TAP_OUT" | head -1 | grep -oE '[0-9]+' || true)
    NFAILED=0
  fi
  [[ -z "$NTOTAL" ]] && NTOTAL=0
  [[ -z "$NFAILED" ]] && NFAILED=0
  NPASSED=$(( NTOTAL - NFAILED ))
  (( NPASSED < 0 )) && NPASSED=0

  PGTAP_TOTAL["$pkg"]=$(( PGTAP_TOTAL["$pkg"] + NTOTAL ))
  PGTAP_PASS["$pkg"]=$(( PGTAP_PASS["$pkg"] + NPASSED ))
  if [[ $RC -ne 0 ]]; then
    PKG_FAILED["$pkg"]=1
    echo "--- pgTAP FAIL: ${f} ---"
    cat "$TAP_OUT"
  fi
  TOTAL_TESTS_RUN=$(( TOTAL_TESTS_RUN + NTOTAL ))
  rm -f "$TAP_OUT"
done

# --- 5. Expected-output half (HARN-02) --------------------------------------

for f in "${REGRESS_FILES[@]:-}"; do
  [[ -z "$f" ]] && continue
  pkg="$(python3 "$PKGNAME_PY" --list "$f" | cut -f1)"
  base="$(basename "$f")"
  expected="${REGRESS_EXPECTED_DIR}/${base%.sql}.out"
  result="${REGRESS_RESULTS_DIR}/${base%.sql}.out"
  REGRESS_TOTAL["$pkg"]=$(( REGRESS_TOTAL["$pkg"] + 1 ))
  TOTAL_TESTS_RUN=$(( TOTAL_TESTS_RUN + 1 ))

  # ON_ERROR_STOP=0 deliberately: an expected-output test is allowed to
  # provoke an error and assert on the error text.
  #
  # psql embeds the exact -f argument in its own "psql:<path>:<line>:"
  # error/notice prefixes. Every golden file under regress/expected/ was
  # authored against the repo-root-relative form (e.g.
  # "psql:migration/test/regress/sql/foo.sql:11:"), so -f is passed relative
  # to REPO_ROOT (with cwd set there) rather than the absolute $f this script
  # discovers files with -- otherwise no expected-output golden with a
  # pinned error/notice line could ever match, regardless of translation
  # correctness (found in plan 02-09, mss.osag_dbprop's error-path golden).
  # client_min_messages=warning suppresses server-side NOTICE output (e.g. the
  # plog stub's own `RAISE NOTICE '[plog stub ...`, migration/pgsql/osag/osag_plog.sql)
  # from the captured stream. No golden file under regress/expected/ pins a NOTICE
  # line -- every one of them was authored expecting only ERROR/CONTEXT output and
  # ordinary query results, so this does not hide anything any existing golden
  # depends on (found in plan 02-09 against mss.osag_dbprop's error-path golden).
  rel_f="${f#"${REPO_ROOT}"/}"
  (cd "$REPO_ROOT" && sudo -u postgres psql -X -q -v ON_ERROR_STOP=0 -d "$DB" \
      -c "SET client_min_messages TO WARNING;" -f "$rel_f") > "$result" 2>&1 || true

  if [[ ! -f "$expected" ]]; then
    echo "--- REGRESS FAIL: ${f} (no golden file: ${expected}) ---"
    PKG_FAILED["$pkg"]=1
    continue
  fi

  if diff -u "$expected" "$result" >/tmp/run-tests-diff.$$; then
    REGRESS_PASS["$pkg"]=$(( REGRESS_PASS["$pkg"] + 1 ))
  else
    echo "--- REGRESS FAIL: ${f} ---"
    cat /tmp/run-tests-diff.$$
    PKG_FAILED["$pkg"]=1
  fi
  rm -f /tmp/run-tests-diff.$$
done

# --- 6. Aggregate table -------------------------------------------------

echo ""
printf '%-40s | %-18s | %-18s | %s\n' "PACKAGE" "PGTAP (pass/total)" "REGRESS (pass/total)" "RESULT"
printf '%-40s-+-%-18s-+-%-18s-+-%s\n' \
  "----------------------------------------" "------------------" "------------------" "------"

PASS_COUNT=0
FAIL_COUNT=0
for pkg in $(printf '%s\n' "${!PACKAGES[@]}" | sort); do
  pt="${PGTAP_PASS[$pkg]}/${PGTAP_TOTAL[$pkg]}"
  rt="${REGRESS_PASS[$pkg]}/${REGRESS_TOTAL[$pkg]}"
  failed="${PKG_FAILED[$pkg]}"
  pgtap_ok=1
  [[ "${PGTAP_TOTAL[$pkg]}" -gt 0 && "${PGTAP_PASS[$pkg]}" -ne "${PGTAP_TOTAL[$pkg]}" ]] && pgtap_ok=0
  regress_ok=1
  [[ "${REGRESS_TOTAL[$pkg]}" -gt 0 && "${REGRESS_PASS[$pkg]}" -ne "${REGRESS_TOTAL[$pkg]}" ]] && regress_ok=0
  if [[ "$failed" -eq 0 && "$pgtap_ok" -eq 1 && "$regress_ok" -eq 1 ]]; then
    result="PASS"
    PASS_COUNT=$(( PASS_COUNT + 1 ))
  else
    result="FAIL"
    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
  fi
  printf '%-40s | %-18s | %-18s | %s\n' "$pkg" "$pt" "$rt" "$result"
done

echo ""
echo "TOTAL: ${#PACKAGES[@]} packages, ${PASS_COUNT} pass, ${FAIL_COUNT} fail"

# --- 7. Exit code ------------------------------------------------------

if [[ "$TOTAL_TESTS_RUN" -eq 0 ]]; then
  echo "FATAL: zero tests discovered — an empty suite must never report success" >&2
  exit 1
fi

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi

exit 0
