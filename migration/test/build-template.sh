#!/usr/bin/env bash
# migration/test/build-template.sh
#
# Builds the mcdb_tmpl TEMPLATE database from scratch: the REAL ora2pg-converted schema
# in ddl/migrated/ (the locked decision -- not a hand-built fixture), the sequences
# ora2pg forgot, realistic reference data from masterdata/, and marks the result as a
# PostgreSQL template so bootstrap.sh --template mcdb_tmpl (the default) can clone it in
# seconds for every later plan/wave (D-P8).
#
# This is the ONLY script that creates mcdb_tmpl. Strict dependency order:
#   roles+schemas -> tables -> sequences -> schema-fixes -> fixtures -> mark as template
#
# Usage: build-template.sh [--db NAME]   (defaults to mcdb_tmpl)
#
# Idempotent: safe to re-run. Rebuilds NAME from nothing every time (bootstrap.sh's
# name-allowlist gate, T-02-01, is reused for the DROP/CREATE).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DB="mcdb_tmpl"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --db) DB="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; echo "Usage: $0 [--db NAME]" >&2; exit 1 ;;
  esac
done

# Same allowlist gate as bootstrap.sh (T-02-01): this script issues its own
# ALTER DATABASE / DROP DATABASE-adjacent statements (the IS_TEMPLATE unset below), so
# it re-checks the name itself rather than relying solely on bootstrap.sh's own gate.
NAME_RE='^mcdb_(test|tmpl|harness)[a-z0-9_]*$'
if [[ ! "$DB" =~ $NAME_RE ]]; then
  echo "FATAL: target database name '${DB}' does not match the allowed pattern ${NAME_RE}" >&2
  exit 1
fi

echo "############################################################"
echo "# build-template.sh: building ${DB}"
echo "############################################################"

# --- Step 0: fresh bare database (roles/extensions only) -------------------
# PostgreSQL refuses to DROP a database with datistemplate=true (step 6 below sets
# this on every successful build). Un-mark it first so a re-run of this idempotent
# script can DROP/CREATE it again -- bootstrap.sh's own DROP does not know about this
# self-inflicted condition, since ordinarily only THIS script's step 6 ever sets it.
EXISTING="$(sudo -u postgres psql -X -v ON_ERROR_STOP=on -q -tAc "SELECT 1 FROM pg_database WHERE datname = '${DB}'")"
if [[ "$EXISTING" == "1" ]]; then
  sudo -u postgres psql -X -v ON_ERROR_STOP=on -q -c "ALTER DATABASE ${DB} IS_TEMPLATE false;"
fi

echo ""
echo "--- Step 0/6: bootstrap.sh --bare ---"
"${SCRIPT_DIR}/bootstrap.sh" --db "$DB" --bare

psql_super() {
  sudo -u postgres psql -X -v ON_ERROR_STOP=on -q -d "$DB" "$@"
}

# --- Step 1: roles + schemas ------------------------------------------------
echo ""
echo "--- Step 1/6: bootstrap/10_schemas_roles.sql (116 ddl/migrated/users/*.sql + 2 fixes) ---"
psql_super -f "${SCRIPT_DIR}/bootstrap/10_schemas_roles.sql"

# --- Step 2: tables + constraints + views (errors surfaced, T-02-09) -------
echo ""
echo "--- Step 2/6: bootstrap/20_ddl.sh (tables.pg.sql strict, constraints/views inventoried) ---"
"${SCRIPT_DIR}/bootstrap/20_ddl.sh" --db "$DB"

# --- Step 3: sequences (ora2pg gap, ported from ddl/generated/sequences/) --
echo ""
echo "--- Step 3/6: bootstrap/30_sequences.sql (30 files, 309 sequences) ---"
psql_super -f "${SCRIPT_DIR}/bootstrap/30_sequences.sql"

# --- Step 4: schema-fixes (additive, D-P7 -- ddl/migrated/ itself untouched) -
# Loads every *.sql under schema-fixes/, sorted by filename (10_, 21_, 22_, 23_, ...).
# Generalized by plan 02-11 from a single hardcoded 10_ora2pg_fixes.sql reference: prior
# per-plan ledger files (21_p09_fixes.sql, 22_p10_fixes.sql) happened to need zero actual
# SQL (comment-only, safe no-ops either way), but 23_p11_fixes.sql (TT.EVENT_INTERFACE)
# needs a real additive ALTER TABLE -- which was previously inert (never loaded into
# mcdb_tmpl) despite being ledgered. This loop is the mechanical, forward-compatible fix.
echo ""
echo "--- Step 4/6: schema-fixes/*.sql (all additive per-plan fixes, sorted) ---"
while IFS= read -r -d '' f; do
  echo "    applying $(basename "$f")"
  psql_super -f "$f"
done < <(find "${SCRIPT_DIR}/schema-fixes" -maxdepth 1 -type f -name '*.sql' -print0 | sort -z)

# --- Step 5: fixtures (masterdata/, HARN-03) --------------------------------
echo ""
echo "--- Step 5/6: bootstrap/40_fixtures.sh (masterdata/{AUTH,TT,MSS,MCAUDIT,OSAG}) ---"
"${SCRIPT_DIR}/bootstrap/40_fixtures.sh" --db "$DB"

# --- Step 6: T-02-11 assertion + mark as template ---------------------------
echo ""
echo "--- Step 6/6: T-02-11 assertion (zero disabled triggers) + mark as TEMPLATE ---"
DISABLED_TRIGGERS="$(psql_super -tAc "SELECT count(*) FROM pg_trigger WHERE tgenabled <> 'O';")"
if [[ "$DISABLED_TRIGGERS" -ne 0 ]]; then
  echo "FATAL: ${DISABLED_TRIGGERS} trigger(s) left disabled after the build (T-02-11)." >&2
  echo "fixtures/load_masterdata.py's DISABLE TRIGGER ALL fallback (used only for" >&2
  echo "non-deferrable FKs, not exercised by the current 5 pilot schemas) must" >&2
  echo "re-enable everything it disables, even on failure. Refusing to mark ${DB} as a" >&2
  echo "template with disabled triggers -- every later clone would inherit them." >&2
  exit 1
fi
echo "-- 0 disabled triggers (T-02-11 OK)"

sudo -u postgres psql -X -v ON_ERROR_STOP=on -q -c "ALTER DATABASE ${DB} WITH ALLOW_CONNECTIONS true;"
sudo -u postgres psql -X -v ON_ERROR_STOP=on -q -c "ALTER DATABASE ${DB} IS_TEMPLATE true;"
echo "-- ${DB} marked IS_TEMPLATE true, ALLOW_CONNECTIONS true"

echo ""
echo "############################################################"
echo "# build-template.sh: ${DB} build complete"
echo "############################################################"
