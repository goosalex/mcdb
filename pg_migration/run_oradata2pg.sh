#!/usr/bin/env bash


cp "/Applications/OSAGoraclient/client/network/admin/tnsnames.ora" "${PANTA_HOME}/osdb/mcdb/pg_migration/config/"
#!/usr/bin/env bash
for TYPE in COPY INSERT
  do
    prod_schemas="$(grep -E 'schemas=(.*)$' "${PANTA_HOME}/osdb/mcdb/changes/liquibase-prod.properties" | sed 's/schemas=//' | sed 's/,/ /g')"
    for SCHEMA in ${prod_schemas}
      do
        echo "Processing schema: $SCHEMA"

        mkdir -p "${PANTA_HOME}/osdb/mcdb/pg_migration/output/data/$SCHEMA"
        rm -rf "${PANTA_HOME}/osdb/mcdb/pg_migration/output/data/$SCHEMA"/*

        echo "Running ora2pg for $TYPE on schema $SCHEMA"

        docker run \
          --name ora2pg --rm \
          -e CONFIG_LOCATION="/config/data_export.conf" \
          -e OUTPUT_LOCATION="/data/data_output/" \
          -e TNS_ADMIN="/config" \
          -e ORACLE_HOST="dbi:Oracle:ORADVRO" \
          -e ORA2PG_PASSWD="${ORA_PWD}" \
          -it \
          -v "${PANTA_HOME}/osdb/mcdb/pg_migration/output/data/$SCHEMA:/data/data_output" \
          -v "${PANTA_HOME}/osdb/mcdb/pg_migration/config:/config" \
          ora2pg \
          ora2pg  -t "$TYPE" --namespace "$SCHEMA" -c "/config/data_export.conf" -o "${SCHEMA}_$TYPE.pg.sql"
      done
  done
