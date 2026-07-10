#!/bin/bash
set -e
shopt -s nullglob

# Liquibase v>=4.13 should be installed. not checking Version though
which liquibase >/dev/null || {
  echo "Liquibase not installed" >&2
  exit 1
}

# change into changes dir
cd "$(dirname $(readlink -f $0))"/..
echo $(pwd)
liquibase --defaultsFile liquibase-container.properties update --logLevel=debug # if something goes wrong, add " --logLevel=debug " to find the error
