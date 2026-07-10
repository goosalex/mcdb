#!/usr/bin/env bash
set -e
psql "$PSQL_CONNECTION_STRING" --echo-errors -f ../ddl/migrated/tables/tables.pg.sql
psql "$PSQL_CONNECTION_STRING" --echo-errors -f ../ddl/migrated/tables/constraints.pg.sql
psql "$PSQL_CONNECTION_STRING" --echo-errors -f ../ddl/migrated/tables/views.pg.sql
