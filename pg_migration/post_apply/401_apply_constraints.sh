#!/usr/bin/env bash
psql "$PSQL_CONNECTION_STRING" --echo-errors -f ../ddl/migrated/constraints/fk-constraints.pg.sql
psql "$PSQL_CONNECTION_STRING" --echo-errors -f ../ddl/migrated/constraints/check-constraints.pg.sql