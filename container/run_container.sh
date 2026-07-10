#!/bin/bash

OUTPUT="mcdb_output"

# check if grep finds an existing docker volume
if ! docker volume list | grep -q mcdb_output; then
    # Command to execute if mcdb_output volume does not exist
    docker volume create mcdb_output
fi



if [ "$(arch)" = "arm64" ]; then
  DOCKER_OPTS="" docker run -e ORACLE_PASSWORD=password -p 1521:1521 -v  "${OUTPUT}:/mcdb/output" artifacts.open.ch/central-docker-dev-local/osdb/local_ora_mcdb_arm:2
else
  DOCKER_OPTS="" docker run  -e ORACLE_PASSWORD=password -p 1521:1521 -v  "${OUTPUT}:/mcdb/output" artifacts.open.ch/central-docker-prod-local/osdb/local_ora_mcdb:2
fi

