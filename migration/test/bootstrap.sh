#!/usr/bin/env bash
# migration/test/bootstrap.sh
#
# Disposable-database builder for the dual test harness. Runs as the
# `postgres` superuser via peer auth (this machine's PostgreSQL 17.10 is
# reached that way). Idempotent: re-running against an existing target
# database succeeds and leaves it in the same state.
#
# Usage:
#   bootstrap.sh --db NAME --bare
#   bootstrap.sh --db NAME [--template TMPL]
#
#   --bare             DROP DATABASE IF EXISTS NAME; CREATE DATABASE NAME;
#                       apply bootstrap/00_extensions.sql. No schema, no
#                       fixtures. This is the mode Phase 2 plan 02-01 uses,
#                       because no schema exists yet (plan 02-03 builds the
#                       template).
#   --template TMPL    DROP DATABASE IF EXISTS NAME; CREATE DATABASE NAME
#                       TEMPLATE TMPL. Defaults to `mcdb_tmpl` when neither
#                       --bare nor --template is given AND mcdb_tmpl exists.
#                       Fails with a clear message if TMPL does not exist.
#
# Safety (T-02-01): NAME (and TMPL) must match
#   ^mcdb_(test|tmpl|harness)[a-z0-9_]*$
# — refuses to operate on anything else, so a typo can never drop a real
# database. This is a hard, non-overridable gate.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME_RE='^mcdb_(test|tmpl|harness)[a-z0-9_]*$'

DB=""
TEMPLATE=""
BARE=0

usage() {
  echo "Usage: $0 --db NAME [--template TMPL] [--bare]" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --db) DB="$2"; shift 2 ;;
    --template) TEMPLATE="$2"; shift 2 ;;
    --bare) BARE=1; shift ;;
    *) echo "Unknown argument: $1" >&2; usage ;;
  esac
done

[[ -n "$DB" ]] || usage

assert_safe_name() {
  local name="$1"
  local label="$2"
  if [[ ! "$name" =~ $NAME_RE ]]; then
    echo "FATAL: $label '$name' does not match the allowed pattern $NAME_RE" >&2
    echo "Refusing to operate — this gate exists so a typo can never drop a real database (T-02-01)." >&2
    exit 1
  fi
}

assert_safe_name "$DB" "target database name"
if [[ -n "$TEMPLATE" ]]; then
  assert_safe_name "$TEMPLATE" "template database name"
fi

psql_super() {
  sudo -u postgres psql -X -v ON_ERROR_STOP=on -q "$@"
}

db_exists() {
  local name="$1"
  [[ "$(psql_super -tAc "SELECT 1 FROM pg_database WHERE datname = '${name}'")" == "1" ]]
}

terminate_backends() {
  local name="$1"
  # Scoped by the same NAME_RE allowlist as the DROP itself (T-02-03): this
  # function is only ever called with an already-validated name.
  psql_super -tAc "
    SELECT pg_terminate_backend(pid)
    FROM pg_stat_activity
    WHERE datname = '${name}' AND pid <> pg_backend_pid();
  " >/dev/null
}

drop_if_exists() {
  local name="$1"
  if db_exists "$name"; then
    terminate_backends "$name"
    psql_super -c "DROP DATABASE IF EXISTS ${name};"
  fi
}

apply_extensions() {
  local name="$1"
  psql_super -d "$name" -f "${SCRIPT_DIR}/bootstrap/00_extensions.sql"
}

if [[ "$BARE" -eq 1 ]]; then
  echo "bootstrap.sh: --bare mode, target=${DB}"
  drop_if_exists "$DB"
  psql_super -c "CREATE DATABASE ${DB};"
  apply_extensions "$DB"
  echo "bootstrap.sh: ${DB} created bare with orafce + pgtap"
  exit 0
fi

# Template mode: explicit --template, or default to mcdb_tmpl if it exists.
if [[ -z "$TEMPLATE" ]]; then
  TEMPLATE="mcdb_tmpl"
  assert_safe_name "$TEMPLATE" "template database name"
fi

if ! db_exists "$TEMPLATE"; then
  echo "FATAL: template database '${TEMPLATE}' does not exist." >&2
  echo "Run plan 02-03's template builder first, or build a schema-less database with:" >&2
  echo "  $0 --db ${DB} --bare" >&2
  exit 1
fi

echo "bootstrap.sh: template mode, target=${DB} template=${TEMPLATE}"
drop_if_exists "$DB"
terminate_backends "$TEMPLATE"
psql_super -c "CREATE DATABASE ${DB} TEMPLATE ${TEMPLATE};"
echo "bootstrap.sh: ${DB} created from template ${TEMPLATE}"
