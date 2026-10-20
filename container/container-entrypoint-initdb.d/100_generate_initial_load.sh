#!/bin/bash
# This script generates the initial load script for the database.
# It must include anything that Liquibase won't apply afterwards: See ddl/generated/init_changelog.sql
shopt -s nullglob
SCRIPTPATH="/mcdb"
CONTAINER_NAME="XEPDB1"
mkdir -p "${SCRIPTPATH}/output"
OF="${SCRIPTPATH}/output/initial_load.sql"
echo "creating ${OF}"

echo "ALTER SESSION SET CONTAINER=${CONTAINER_NAME};" >"${OF}"
echo "SET SQLBLANKLINES ON" >>"${OF}"

echo "SPOOL OFF" >>"${OF}"
echo "SPOOL 'output/01_global.log'" >>"${OF}"
echo "@ $SCRIPTPATH/ddl/src/global/create_default_adjustments.sql" >>"${OF}"
echo "@ $SCRIPTPATH/ddl/src/global/create_job_class.sql" >>"${OF}"
echo "@ $SCRIPTPATH/ddl/src/global/create_libs.sql" >>"${OF}"
echo "@ $SCRIPTPATH/ddl/src/global/create_nls_session_setup.sql" >>"${OF}"
echo "@ $SCRIPTPATH/ddl/src/global/create_net_acl.sql" >>"${OF}"

echo "SPOOL OFF" >>"${OF}"
echo "SPOOL 'output/02_roles_users.log'" >>"${OF}"

echo "" >>"${OF}"
echo "-- Roles " >>"${OF}"
for f in "${SCRIPTPATH}"/ddl/src/roles/*.sql; do
    echo "@ $f" >>"${OF}"
done

echo "" >>"${OF}"
echo "-- Users " >>"${OF}"
for f in "${SCRIPTPATH}"/ddl/generated/users/*.sql "${SCRIPTPATH}"/ddl/src/users/*.sql; do
    echo "@ $f" >>"${OF}"
done

echo "SPOOL OFF" >>"${OF}"
echo "SPOOL 'output/03_schema.log'" >>"${OF}"

echo "-- Tables, Indexes, Views " >>"${OF}"
echo "@ $SCRIPTPATH/ddl/generated/schema.oracle.sql" >>"${OF}"

echo "" >>"${OF}"
echo "-- Sequences " >>"${OF}"
for f in "${SCRIPTPATH}"/ddl/generated/sequences/*.sql; do
    echo "@ $f" >>"${OF}"
done

echo "" >>"${OF}"
echo "-- Triggers " >>"${OF}"
for f in "${SCRIPTPATH}"/ddl/src/triggers/*.sql; do
    echo "@ $f" >>"${OF}"
done

echo "SPOOL OFF" >>"${OF}"
echo "SPOOL 'output/04_packages.log'" >>"${OF}"

echo "" >>"${OF}"
echo "-- Types " >>"${OF}"
for f in "${SCRIPTPATH}"/ddl/src/types/*.sql; do
    echo "@ $f" >>"${OF}"
done

echo "" >>"${OF}"
echo "-- Packages " >>"${OF}"
for f in "${SCRIPTPATH}"/ddl/src/pkg/*.sql; do
    echo "@ $f" >>"${OF}"
done

echo "" >>"${OF}"
echo "-- Procedures " >>"${OF}"
for f in "${SCRIPTPATH}"/ddl/src/proc/*.sql; do
    echo "@ $f" >>"${OF}"
done

echo "" >>"${OF}"
echo "-- Package Bodies " >>"${OF}"
for f in "${SCRIPTPATH}"/ddl/src/pkgb/*.sql; do
    echo "@ $f" >>"${OF}"
done

echo "" >>"${OF}"
echo "-- Recompile " >>"${OF}"
echo "@ $SCRIPTPATH/ddl/src/global/recompile_all.sql" >>"${OF}"

echo "SPOOL OFF" >>"${OF}"
echo "SPOOL 'output/05_grants.log'" >>"${OF}"

echo "" >>"${OF}"
echo "-- Grants " >>"${OF}"
for f in "${SCRIPTPATH}"/ddl/generated/grants/*.sql; do
    echo "@ $f" >>"${OF}"
done

echo "SPOOL OFF" >>"${OF}"
echo "SPOOL 'output/06_constraints.log'" >>"${OF}"

echo "-- Constraints " >>"${OF}"
echo "@ $SCRIPTPATH/ddl/generated/constraints.oracle.sql" >>"${OF}"
echo "@ $SCRIPTPATH/ddl/generated/check-constraints.oracle.sql" >>"${OF}"

echo "SPOOL OFF" >>"${OF}"
echo "SPOOL 'output/07_mv.log'" >>"${OF}"

echo "" >>"${OF}"
echo "-- Materialized Views Logs " >>"${OF}"
for f in "${SCRIPTPATH}"/ddl/src/mlog/*.sql; do
    echo "@ $f" >>"${OF}"
done

echo "" >>"${OF}"
echo "-- Materialized Views " >>"${OF}"
for f in "${SCRIPTPATH}"/ddl/src/mviews/*.sql; do
    echo "@ $f" >>"${OF}"
done

echo "" >>"${OF}"
echo "-- rest of Grants " >>"${OF}"
for f in "${SCRIPTPATH}"/ddl/generated/grants/*.sql; do
    echo "@ $f" >>"${OF}"
done

echo "SPOOL OFF" >>"${OF}"
echo "SPOOL 'output/09_queues.log'" >>"${OF}"

echo "" >>"${OF}"
echo "-- Queues " >>"${OF}"
for f in "${SCRIPTPATH}"/ddl/src/queues/*.sql; do
    echo "@ $f" >>"${OF}"
done

echo "SPOOL OFF" >>"${OF}"
echo "-- finish" >>"${OF}"
echo "exit;" >>"${OF}"

OF="${SCRIPTPATH}/initial_changelog.xml"
OF2="${SCRIPTPATH}/initial_changelog_post.xml"
echo "creating ${OF} and ${OF2}"

# The export in ddl/generated reflects the schema at the latest tag; master data is a
# snapshot of the current production data and may contain CSVs for tables that only the
# changesets AFTER the tag create. Those CSVs cannot be loaded before 110_run_initial_load.sh
# has applied the post-tag changesets, so the master data is split in two changelogs:
#   initial_changelog.xml       tables that exist now           -> loaded before the update
#   initial_changelog_post.xml  tables not (yet) in the schema  -> loaded after the update
EXISTING="${SCRIPTPATH}/output/existing_tables.txt"
sqlplus -s / as sysdba >"${EXISTING}" <<EOF_EXISTING
set heading off feedback off pagesize 0 linesize 300 trimspool on
ALTER SESSION SET CONTAINER=${CONTAINER_NAME};
select owner||'.'||table_name from dba_tables order by 1;
exit
EOF_EXISTING
echo "  $(grep -c . "${EXISTING}") tables exist in the exported schema"
XML_HEADER=$(cat << _XML_HEADER
<?xml version="1.0" encoding="UTF-8"?>
<databaseChangeLog
	xmlns="http://www.liquibase.org/xml/ns/dbchangelog"
	xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
	xmlns:ext="http://www.liquibase.org/xml/ns/dbchangelog-ext"
	xmlns:pro="http://www.liquibase.org/xml/ns/pro"
	xsi:schemaLocation="http://www.liquibase.org/xml/ns/dbchangelog dbchangelog-latest.xsd
	    http://www.liquibase.org/xml/ns/dbchangelog http://www.liquibase.org/xml/ns/dbchangelog/dbchangelog-latest.xsd
		http://www.liquibase.org/xml/ns/dbchangelog-ext http://www.liquibase.org/xml/ns/dbchangelog/dbchangelog-ext.xsd
		http://www.liquibase.org/xml/ns/pro http://www.liquibase.org/xml/ns/pro/liquibase-pro-latest.xsd">
        <!-- This is the root of the changelogs and it just includes others in the right order. -->
	<changeSet author="osdb" id="1::masterData">
_XML_HEADER
)
XML_FOOTER=$(cat << _XML_FOOTER
	</changeSet>
</databaseChangeLog>
_XML_FOOTER
)

echo "$XML_HEADER" >"${OF}"
echo "${XML_HEADER/1::masterData/2::masterDataPostTag}" >"${OF2}"
cd "${SCRIPTPATH}" || exit
# make sure s and f a relative paths to SCRIPTPATH (liquibase searchPath)
for s in masterdata/*; do
    if [ -e "$s/_pre.sql" ]; then
        echo "<sqlFile path=\"${s}/_pre.sql\"/>" >>"${OF}"
    fi
    for f in "$s"/*.csv; do
        # lqb can not load empty files
        if [ ! -s "${f}" ]; then
          continue
        fi
        filename=$(basename -- "$f")
        tablename="${filename%.*}"
        tablenameUC=$(tr '[:lower:]' '[:upper:]' <<<"$tablename")
        schemaname=$(basename "$s")
        xmlname="${f%.csv}.xml"
        # table created only by post-tag changesets? -> second changelog
        if grep -qxF "${schemaname}.${tablenameUC}" "${EXISTING}"; then TARGET="${OF}"; else TARGET="${OF2}"; echo "  deferred (table not in export): ${schemaname}.${tablenameUC}"; fi
        if [ -f "$xmlname" ]; then

            echo "<loadData file=\"$f\" schemaName=\"$schemaname\" tableName=\"$tablenameUC\">" >>"${TARGET}"
            cat "$xmlname" >>"${TARGET}"
            echo "</loadData>" >>"${TARGET}"
        else
            echo "<loadData file=\"$f\" schemaName=\"$schemaname\" tableName=\"$tablenameUC\"/>" >>"${TARGET}"
        fi
    done
    if [ -e "$s/_post.sql" ]; then
        echo "<sqlFile path=\"${s}/_post.sql\"/>" >>"${OF}"
    fi
done
echo "$XML_FOOTER" >>"${OF}"
echo "$XML_FOOTER" >>"${OF2}"
cd - || exit

OF="${SCRIPTPATH}/output/unlock_users.sql"
echo "creating ${OF}"
echo "ALTER SESSION SET CONTAINER=${CONTAINER_NAME};" >"${OF}"
echo "SET SQLBLANKLINES ON" >>"${OF}"
echo "SPOOL 'output/11_unlock.log'" >>"${OF}"
echo "-- unlock all custom user account with the same password" >>"${OF}"
for u in "${SCRIPTPATH}/ddl/src/users"/*.sql "${SCRIPTPATH}/ddl/generated/users"/*.sql; do
        filename=$(basename -- "$u")
        username="${filename%.*}"
        usernameUC=$(tr '[:lower:]' '[:upper:]' <<<"$username")
        echo "ALTER USER \"$usernameUC\" IDENTIFIED BY \"password\" ACCOUNT UNLOCK;" >>"${OF}"
done
echo "SPOOL OFF" >>"${OF}"
echo "exit;" >>"${OF}"
