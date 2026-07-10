#!/bin/bash
# typically pass --defaults-file=liquibase-prod.properties --password=... as arguments to this script
# Check if DEFAULTS_FILE is set, if not, set it to liquibase-prod.properties
if [ -z "${DEFAULTS_FILE}" ]; then
  DEFAULTS_FILE="liquibase-pg-migration.properties"
fi
echo "Using defaults file: ${DEFAULTS_FILE}"
#Check if SYSDBA_PASSWORD is set, if not stop the script and ask to set it
if [ -z "${SYSDBA_PASSWORD}" ]; then
  echo "SYSDBA_PASSWORD is not set. Please set it before running this script."
  exit 1
fi

# Check presence of tools
set -e
shopt -s extglob

which liquibase >/dev/null || {
  echo "Liquibase not installed" >&2
  exit 1
}

(sed --version 2>/dev/null | grep -q GNU) || which gsed &>/dev/null || {
  echo "GNU sed not installed. Run: brew install gnu-sed" >&2
  exit 1
}
which gsed &>/dev/null || alias gsed=sed

# Export USERS ROLES GRANTS FOREIGN KEYS and CHECK CONSTRAINS (later may be also SEQUENCES TRIGGERS SYNONYMS)
echo "Running custom exporter"

# cd to /osdb/mcdb/changes/
cd "$(dirname "$(readlink -f -- "$0")")"/..
bazel run "//osdb/mcdb/changes/scripts:export-ddl" --run_under="cd $PWD &&" -- "--defaults-file=${DEFAULTS_FILE}" "--password=${SYSDBA_PASSWORD}" --dataOutputDirectory=/tmp/null --pgsql=${PANTA_HOME}/osdb/mcdb/ddl/migrated

export ORA_PWD="${SYSDBA_PASSWORD}"
bash ${PANTA_HOME}/osdb/mcdb/pg_migration/run_ora2pg.sh

export SCHEMA_TABLE="${PANTA_HOME}/osdb/mcdb/pg_migration/output/schema/TABLE.pg.sql"
export SCHEMA_VIEW="${PANTA_HOME}/osdb/mcdb/pg_migration/output/schema/VIEW.pg.sql"
export TABS="${PANTA_HOME}/osdb/mcdb/ddl/migrated/tables/tables.pg.sql"
export VIEWS="${PANTA_HOME}/osdb/mcdb/ddl/migrated/tables/views.pg.sql"
export CONS="${PANTA_HOME}/osdb/mcdb/ddl/migrated/tables/constraints.pg.sql"
# move FK constraints out. Oracle Syntax also works in PostgreSQL, and the custom exporter respects the deferrable syntax properly
# grep -E '^ALTER TABLE \S+ ADD CONSTRAINT \S+ FOREIGN KEY ' "${SCHEMA_TABLE}" >"${CONS}"
gsed -i -E '/ALTER TABLE [[:alnum:]|_]+\.[[:alnum:]|_]+ ADD CONSTRAINT [[:alnum:]|_]+ FOREIGN KEY/d' "${SCHEMA_TABLE}"

cp "${PANTA_HOME}/osdb/mcdb/ddl/generated/constraints.oracle.sql" "${CONS}"
cp "$SCHEMA_TABLE" "$TABS"
cp "$SCHEMA_VIEW" "$VIEWS"

gsed -i 's/set ON_ERROR_STOP ON/set ON_ERROR_STOP OFF/g' "$TABS"
gsed -i 's/set ON_ERROR_STOP ON/set ON_ERROR_STOP OFF/g' "$VIEWS"
# Prepend the constraints file with a command to disable ON_ERROR_STOP
gsed -i '1s/^/set ON_ERROR_STOP OFF;\n/' "$CONS"


