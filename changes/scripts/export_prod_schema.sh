#!/bin/bash
# the liquibase-prod.properties file contains definitive list of schemas to export/import
#
SCHEMA_LIST=$(grep schemas= "$PANTA_HOME"/osdb/mcdb/changes/liquibase-prod.properties)
echo "$SCHEMA_LIST"

#check if variable USERNAME is defined, if not check if variable USER is defined and use it as USERNAME. If not, fail
if [[ -z "${USERNAME}" ]]; then
  if [[ -z "${USER}" ]]; then
    echo "Neither USERNAME nor USER is set. Please set one of them to your username."
    exit 1
  else
    USERNAME="$USER"
  fi
fi

# ### export_schema on EM (could be any machine, close to PROD DB servers ####
#
# #!/bin/sh
# cd export
# JAVA_HOME=/opt/oracle/product/em24/oms_home/oracle_common/jdk TNS_ADMIN=/home/oracle/export ./liquibase/liquibase generate-changelog --defaults-file=prod.conf --password=<JPROD_SYS_AS_SYSDBA_PASSWORD> --changelog-file=/tmp/schema.oracle.sql --overwriteOutputFile=true --includeSchema=true --diffTypes=tables,views,columns,indexes,primarykeys,uniqueconstraints "$@"
#
# runs env 2 mins and generates a schema.oracle.sql file in /tmp/ which has later to be scp'ed to your machine
#
echo "You will now have to enter your admin.$USERNAME password twice:"

# You will have to [nolint] for the following line to pass Megalinter
ssh "admin.$USERNAME"@jump2 "ssh -o StrictHostKeyChecking=no oracle@ora19-a13-em-prod-1 ./export_schema.sh --$SCHEMA_LIST > /dev/null 2>&1 && scp  -o StrictHostKeyChecking=no oracle@ora19-a13-em-prod-1:/tmp/schema.oracle.sql ./tmp/"
scp "admin.$USERNAME"@jump2:tmp/schema.oracle.sql "$PANTA_HOME"/osdb/mcdb/ddl/generated/
# mkdir -p "$PANTA_HOME"/osdb/mcdb/ddl/ora_export
# cp "$PANTA_HOME"/osdb/mcdb/ddl/generated/schema.oracle.sql "$PANTA_HOME"/osdb/mcdb/ddl/ora_export/schema.oracle.sql

echo "Now you can continue with >regenerate-ddl.sh --defaults-file=liquibase-prod.properties --password=... "
echo "..and then with >regenerate-csv.sh --defaults-file=liquibase-prod.properties --password=... "
echo "giving the PROD-DB SYS password as argument"