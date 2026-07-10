#!/usr/bin/env bash

execute_directory_of_files() {
  local directory="$1"
  shift
  # check if directory exists
  if [ ! -d "$directory" ]; then
      echo "Directory $directory does not exist. Please create it and add your SQL scripts."
      exit 1
  fi
  mkdir -p "output/$directory"
  # merge list of .sql files in perparation directory and .sh files in preparation directory
  # and execute them in alphabetical order
  # This is useful for running scripts that need to be executed in a specific order
  # e.g. 100_schema_users.sql, 200_roles.sql, etc.
  # check if preparation directory exists
  # merge the list of .sql and .sh files in the preparation directory
  files=("$directory"/*.sh "$directory"/*.sql)
  # sort the list of files alphabetically
  IFS=$'\n' files=($(sort <<<"${files[*]}"))
  unset IFS

    for filename in "${files[@]}"; do
        [ -e "$filename" ] || continue
        if [[ "$filename" == *.sh ]]; then
            echo "Executing script: $filename"
            bash "$filename" 2> >(tee "output/$directory/$(basename "$filename").err" >&2)   >"output/$directory/$(basename "$filename").out"
            continue
        fi
        if [[ "$filename" != *.sql ]]; then
            echo "Skipping non-SQL file: $filename"
            continue
        fi
        # If its a .sql file then execute it with psql
        echo "Executing SQL script: $filename"
        psql "$PSQL_CONNECTION_STRING" --echo-errors -f "$filename" "$DATABASE"  2> >(tee "output/$directory/$(basename "$filename").err" >&2)   >"output/$directory/$(basename "$filename").out"
    done
}


set -e
which psql >/dev/null || {
  echo "Psql/libpq/postgres not installed" >&2
  exit 1
}
if [[ -z "${PSQL_CONNECTION_STRING}" ]]; then
  echo "Warning, set PSQL_CONNECTION_STRING variable!"
  echo "e.g. export PSQL_CONNECTION_STRING=postgres://postgres:password@localhost:5432/mcdb"
  exit
fi
# check if ORA_PWD is set, if not exit with error
if [[ -z "${ORA_PWD}" ]]; then
  echo "ORA_PWD is not set. Please set it to your Oracle password."
  echo "check also ORAHOST (DSN) and ORA_USER variables, if not defaults for SYS AS SYSDBA@ORADEV are used"
  exit 1
fi

SUPERUSER="${SUPERUSER:-postgresadmin}"
MASTER_CONNECTION_STRING="$(sed -E 's/[[:alnum:]_]+$/postgres/' <<<"$PSQL_CONNECTION_STRING")"
DATABASE="$(grep -o -E '[[:alnum:]_]+$' <<<"$PSQL_CONNECTION_STRING")"

export ORACLE_PWD="${ORACLE_PWD}"
export ORACLE_USER="${ORACLE_USER:-SYS AS SYSDBA}"
export ORACLE_DSN="${ORACLE_DSN:-ORADEV}"
export PSQL_CONNECTION_STRING="${PSQL_CONNECTION_STRING}"
export DATABASE="$DATABASE"

# psql "$MASTER_CONNECTION_STRING" -c "DROP DATABASE IF EXISTS $DATABASE"
# psql "$MASTER_CONNECTION_STRING" -c "CREATE DATABASE $DATABASE owner $SUPERUSER"




#execute_directory_of_files preparation

#execute_directory_of_files apply

# wait for user input to confirm that the scripts have been executed
echo "All scripts have been executed."
echo "You can now check the output on the target server."
echo "Press y to continue with the final steps... applying constraints"
read -n 1 -s -r -p "Press y to continue or any other key to exit: " key
if [[ "$key" != "y" ]]; then
  echo "Exiting without final steps."
  exit 0
fi

execute_directory_of_files post_apply
