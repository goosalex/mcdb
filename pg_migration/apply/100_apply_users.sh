#!/usr/bin/env bash
set -e
if [[ -z "${PSQL_CONNECTION_STRING}" ]]; then
  echo "Warning, set PSQL_CONNECTION_STRING variable!"
  echo "e.g. export PSQL_CONNECTION_STRING=postgres://postgres:password@localhost:5432/mcdb"
  exit
fi
# checlk if $DATABASE is set, if not extract it from PSQL_CONNECTION_STRING
if [[ -z "${DATABASE}" ]]; then
  DATABASE="$(grep -o -E '[[:alnum:]_]+$' <<<"$PSQL_CONNECTION_STRING")"
fi

# loop over user SQL files in the directory
for user_sql in "${PANTA_HOME}/osdb/mcdb/ddl/migrated/users"/*.sql; do
    [ -e "$user_sql" ] || continue
    echo "Applying user SQL file: $user_sql"
    psql "$PSQL_CONNECTION_STRING" --echo-errors -f  "$user_sql" $DATABASE
done
