#!/usr/bin/env bash
set -e
# This script cleans up the generated PostgreSQL table DDL files from ora2pg migration
# It removes wrong primary key index specifications and strips misleading double qoutes
# and in turn adds double quotes around reserved words like "end" and "group".
gsed -E -i 's/ADD PRIMARY KEY \(.+\)  USING INDEX [[:alpha:]|\"]+\./ADD PRIMARY KEY USING INDEX /g' "${PANTA_HOME}/osdb/mcdb/ddl/migrated/tables/tables.pg.sql"
gsed -E -i 's/^([[:space:]])+(end|group)[[:space:]]/\1"\2" /g' "${PANTA_HOME}/osdb/mcdb/ddl/migrated/tables/tables.pg.sql"

gsed -E -i 's/CREATE OR REPLACE VIEW ([[:alpha:]]+)\./SET search_path = \1,public; CREATE OR REPLACE VIEW \1./' "${PANTA_HOME}/osdb/mcdb/ddl/migrated/tables/views.pg.sql"
gsed -E -i 's/FROM mss\.host, host/FROM mss.host/' "${PANTA_HOME}/osdb/mcdb/ddl/migrated/tables/views.pg.sql"

gsed -i 's/CREATE EXTENSION .*$//g' "${PANTA_HOME}/osdb/mcdb/ddl/migrated/tables/tables.pg.sql"