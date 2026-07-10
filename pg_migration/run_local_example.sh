#!/usr/bin/env bash
TYPE="VIEW"
IMAGE="georgmoser/ora2pg:latest"
  docker run \
    --name ora2pg --rm \
    -e CONFIG_LOCATION="/config/schema_conversion.conf" \
    -e OUTPUT_LOCATION="/data/schema_output" \
    -e SSL_CERT_FILE="/config/osag-bundle.crt" \
    -it \
    -v "${PANTA_HOME}/osdb/mcdb/pg_migration/output/schema":/data/schema_output \
    -v "${PANTA_HOME}/osdb/mcdb/ddl":/data/ddl \
    -v "${PANTA_HOME}/osdb/mcdb/pg_migration/config":/config \
    "$IMAGE" \
    ora2pg  -t "$TYPE" -c /config/schema_conversion.conf -o "${TYPE}.pg.sql"

SCHEMA="ESP"
  docker run \
    --name ora2pg --rm \
    -e CONFIG_LOCATION="/config/data_export.conf" \
    -e OUTPUT_LOCATION="/data/data_output/" \
    -e TNS_ADMIN="/config" \
    -e ORACLE_HOST="dbi:Oracle:ORADVRO" \
    -e ORA2PG_PASSWD="${ORA_PWD}" \
    -it \
    -v "${PANTA_HOME}/osdb/mcdb/pg_migration/output/data/$SCHEMA":/data/data_output \
    -v "${PANTA_HOME}/osdb/mcdb/pg_migration/config":/config \
    "$IMAGE" \
    ora2pg  -t COPY --namespace "$SCHEMA" -c /config/data_export.conf -o "${SCHEMA}_COPY.pg.sql"
