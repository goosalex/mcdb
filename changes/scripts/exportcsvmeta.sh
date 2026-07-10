#!/bin/bash
# typically pass --defaults-file=liquibase-prod.properties --password=... as arguments to this script
set -e
cd "$(dirname $(readlink -f $0))"/..
bazel run "//osdb/mcdb/changes/scripts:export-csv-meta" --run_under="cd $PWD &&" -- "$@" --dataOutputDirectory=../masterdata
