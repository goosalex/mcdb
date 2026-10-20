#!/usr/bin/env bash
#
# provenance_lint.sh -- the structural anti-circularity gate (HARN-05 / T-02-06).
#
# For every translated package file under migration/pgsql/<schema>/<pkg>.sql,
# assert -- via git ancestry, not reviewer goodwill -- that BOTH its spec and
# its first test file were committed BEFORE the translation, and that no
# commit touching the translation also modified one of that package's test
# files (unless migration/spec/TEST-AMENDMENTS.md explicitly permits it).
#
# If either ancestry assertion fails, the tests may have been written by
# reading the translation, which proves nothing.
#
# Runs clean ("0 packages translated, nothing to check", exit 0) before any
# translation exists -- plans 02-09..02-12 populate migration/pgsql/ as they
# go, and this script is safe to run unconditionally in CI from day one.
#
# Usage:
#   bash migration/spec/provenance_lint.sh
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

SPEC_DIR="migration/spec"
TEST_AMENDMENTS="$SPEC_DIR/TEST-AMENDMENTS.md"
TRANS_DIR="migration/pgsql"

PREDATE_MSG="translation predates its spec/tests -- the tests may have been written from the translation, which proves nothing."

# Returns 0 (true) iff TEST-AMENDMENTS.md explicitly permits `commit` to have
# touched `file`. Ledger line shape: commit:<sha> file:<path> reason:<text>
is_amended() {
  local commit="$1" file="$2"
  [ -f "$TEST_AMENDMENTS" ] || return 1
  grep -F "commit:${commit}" "$TEST_AMENDMENTS" 2>/dev/null | grep -qF "file:${file}"
}

if [ ! -d "$TRANS_DIR" ]; then
  echo "provenance_lint: 0 packages translated (no $TRANS_DIR directory yet) -- nothing to check"
  exit 0
fi

# osag/osag_plog.sql is a deliberate exception, not a gap: plog is the locked D-P5a
# stub ("the simplest thing that works" -- 02-CONTEXT.md), built explicitly WITHOUT the
# spec-first cycle this script polices for every real package translation (no
# migration/spec/osag.osag_plog.md, no migration/test/{pgtap,regress/sql}/osag__osag_plog__*.sql
# exist, or ever will, by design -- see migration/pgsql/osag/osag_plog.FINDINGS.md). It
# predates this script (plan 02-03 vs. 02-02) and would fail this check forever, for a
# reason unrelated to anti-circularity: it never had a spec/test pair to be circular
# about. Found and exempted in plan 02-09 while gating the first real translations.
EXEMPT_TRANS_FILES=("migration/pgsql/osag/osag_plog.sql")

mapfile -t trans_files < <(find "$TRANS_DIR" -mindepth 2 -maxdepth 2 -type f -name '*.sql' | sort)

filtered_trans_files=()
for tf in "${trans_files[@]}"; do
  skip=0
  for ex in "${EXEMPT_TRANS_FILES[@]}"; do
    [ "$tf" = "$ex" ] && skip=1 && break
  done
  [ "$skip" -eq 0 ] && filtered_trans_files+=("$tf")
done
trans_files=("${filtered_trans_files[@]}")

if [ "${#trans_files[@]}" -eq 0 ]; then
  echo "provenance_lint: 0 packages translated (no *.sql under $TRANS_DIR/<schema>/) -- nothing to check"
  exit 0
fi

total_violations=0

for trans_file in "${trans_files[@]}"; do
  schema="$(basename "$(dirname "$trans_file")")"
  pkg="$(basename "$trans_file" .sql)"
  spec_file="$SPEC_DIR/${schema}.${pkg}.md"
  pkg_violations=0

  echo "== ${schema}.${pkg} =="

  trans_add="$(git log --diff-filter=A --format=%H -- "$trans_file" | tail -1)"
  if [ -z "$trans_add" ]; then
    echo "  SKIP: $trans_file exists on disk but is not committed yet"
    continue
  fi

  spec_add="$(git log --diff-filter=A --format=%H -- "$spec_file" | tail -1)"
  if [ -z "$spec_add" ]; then
    echo "  FAIL: ${schema}.${pkg}: $PREDATE_MSG (no spec found at $spec_file)"
    pkg_violations=$((pkg_violations + 1))
  fi

  test_files=()
  for f in "migration/test/pgtap/${schema}__${pkg}__"*.sql "migration/test/regress/sql/${schema}__${pkg}__"*.sql; do
    [ -e "$f" ] && test_files+=("$f")
  done

  test_add=""
  if [ "${#test_files[@]}" -eq 0 ]; then
    echo "  FAIL: ${schema}.${pkg}: $PREDATE_MSG (no test files found matching migration/test/{pgtap,regress/sql}/${schema}__${pkg}__*.sql)"
    pkg_violations=$((pkg_violations + 1))
  else
    test_add="$(git log --diff-filter=A --format=%H -- "${test_files[@]}" | tail -1)"
  fi

  if [ -n "$spec_add" ]; then
    if ! git merge-base --is-ancestor "$spec_add" "$trans_add"; then
      echo "  FAIL: ${schema}.${pkg}: $PREDATE_MSG (spec commit $spec_add is not an ancestor of translation commit $trans_add)"
      pkg_violations=$((pkg_violations + 1))
    fi
  fi

  if [ -n "$test_add" ]; then
    if ! git merge-base --is-ancestor "$test_add" "$trans_add"; then
      echo "  FAIL: ${schema}.${pkg}: $PREDATE_MSG (test commit $test_add is not an ancestor of translation commit $trans_add)"
      pkg_violations=$((pkg_violations + 1))
    fi
  fi

  # No commit touching the translation file may also touch one of this
  # package's test files -- unless TEST-AMENDMENTS.md explicitly permits it.
  mapfile -t trans_commits < <(git log --format=%H -- "$trans_file")
  for commit in "${trans_commits[@]}"; do
    changed="$(git show --name-only --format= "$commit")"
    while IFS= read -r changed_file; do
      [ -z "$changed_file" ] && continue
      case "$changed_file" in
        migration/test/pgtap/"${schema}"__"${pkg}"__*|migration/test/regress/sql/"${schema}"__"${pkg}"__*)
          if is_amended "$commit" "$changed_file"; then
            echo "  OK (amended): commit $commit touched $changed_file -- permitted by $TEST_AMENDMENTS"
          else
            echo "  FAIL: ${schema}.${pkg}: translation commit $commit also modified test file $changed_file without a $TEST_AMENDMENTS entry"
            pkg_violations=$((pkg_violations + 1))
          fi
          ;;
      esac
    done <<< "$changed"
  done

  if [ "$pkg_violations" -eq 0 ]; then
    echo "  OK"
  fi
  total_violations=$((total_violations + pkg_violations))
done

if [ "$total_violations" -gt 0 ]; then
  echo ""
  echo "provenance_lint: $total_violations violation(s)"
  exit 1
fi

echo ""
echo "provenance_lint: all ${#trans_files[@]} translated package(s) OK"
exit 0
