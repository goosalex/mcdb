#!/bin/bash
# called by regenerate-ddl.sh
# pass --defaults-file=liquibase-prod.properties --password=... as arguments to this script
set -e
cd "$(dirname "$(readlink -f -- "$0")")"/..
bazel run "//osdb/mcdb/changes/scripts:export-ddl" --run_under="cd $PWD &&" -- "$@" --dataOutputDirectory=../ddl/generated --pgsql=../ddl/migrated
rm -rf ../ddl/src/triggers
mv ../ddl/generated/triggers ../ddl/src/
