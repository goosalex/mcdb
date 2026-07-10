#!/usr/bin/env bash
for TYPE in TABLE VIEW
do
  docker run \
    --name ora2pg --rm \
    -e CONFIG_LOCATION="/config/schema_conversion.conf" \
    -e OUTPUT_LOCATION="/data/schema_output" \
    -it \
    -v "${PANTA_HOME}/osdb/mcdb/pg_migration/output/schema:/data/schema_output" \
    -v "${PANTA_HOME}/osdb/mcdb/ddl:/data/ddl" \
    -v "${PANTA_HOME}/osdb/mcdb/pg_migration/config:/config" \
    ora2pg \
    ora2pg  -t "$TYPE" -c "/config/schema_conversion.conf" -o "${TYPE}.pg.sql"
done


# Output Code in seperate schemas per original package
cp "/Applications/OSAGoraclient/client/network/admin/tnsnames.ora" "${PANTA_HOME}/osdb/mcdb/pg_migration/config/"
#!/usr/bin/env bash
for TYPE in PACKAGE FUNCTION PROCEDURE TRIGGER TYPE
do
  docker run \
    --name ora2pg --rm \
    -e CONFIG_LOCATION="/config/package_conversion.conf" \
    -e OUTPUT_LOCATION="/data/schema_output" \
    -e TNS_ADMIN="/config" \
    -e ORACLE_HOST="dbi:Oracle:ORADEV" \
    -e ORA2PG_PASSWD="${ORA_PWD}" \
    -it \
    -v "${PANTA_HOME}/osdb/mcdb/pg_migration/output/package_as_schema:/data/schema_output" \
    -v "${PANTA_HOME}/osdb/mcdb/pg_migration/config:/config" \
    ora2pg \
    ora2pg  -t "$TYPE" -c "/config/package_conversion.conf" -o "${TYPE}.pg.sql"
done

# Output Code in the same schmema as in oracle, prefixed with the original package name
cp "/Applications/OSAGoraclient/client/network/admin/tnsnames.ora" "${PANTA_HOME}/osdb/mcdb/pg_migration/config/"
#!/usr/bin/env bash
for TYPE in PACKAGE FUNCTION PROCEDURE TRIGGER TYPE
do
  docker run \
    --name ora2pg --rm \
    -e CONFIG_LOCATION="/config/packageless_conversion.conf" \
    -e OUTPUT_LOCATION="/data/schema_output" \
    -e TNS_ADMIN="/config" \
    -e ORACLE_HOST="dbi:Oracle:ORADEV" \
    -e ORA2PG_PASSWD="${ORA_PWD}" \
    -it \
    -v "${PANTA_HOME}/osdb/mcdb/pg_migration/output/package_in_name:/data/schema_output" \
    -v "${PANTA_HOME}/osdb/mcdb/pg_migration/config:/config" \
    ora2pg \
    ora2pg  -t "$TYPE" -c "/config/packageless_conversion.conf" -o "${TYPE}.pg.sql"
done