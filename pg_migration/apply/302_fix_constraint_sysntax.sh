#!/usr/bin/env bash
mkdir -p ../ddl/migrated/constraints
sed '/DEFERRABLE/d' ../ddl/generated/check-constraints.oracle.sql > ../ddl/migrated/constraints/check-constraints.pg.sql
cp ../ddl/generated/constraints.oracle.sql ../ddl/migrated/constraints/fk-constraints.pg.sql
