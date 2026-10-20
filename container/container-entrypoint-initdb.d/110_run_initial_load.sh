#!/bin/bash
shopt -s nullglob
LQB_VER="4.21.1"
SCRIPTPATH="/mcdb"

# Where to download the JDK and Liquibase from. Inside the company network the
# company mirror of GitHub releases is used; anywhere else (no route to
# artifacts.open.ch) the public GitHub release URLs. Both serve the same files under the
# same paths. MCDB_ARTIFACT_REPO=company|public overrides the probe.
COMPANY_MIRROR="artifacts.open.ch"
GH_COMPANY="https://${COMPANY_MIRROR}/repository/github-releases-remote"
GH_PUBLIC="https://github.com"
# Reachability only: any HTTP status (even 401/404) means the mirror answered; a
# connection failure or timeout (curl prints 000) means we are outside the company.
artifact_repo() {
  case "${MCDB_ARTIFACT_REPO:-}" in
    company|public) echo "$MCDB_ARTIFACT_REPO"; return ;;
  esac
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "https://${COMPANY_MIRROR}/" 2>/dev/null || true)"
  if [ -n "$code" ] && [ "$code" != "000" ]; then echo company; else echo public; fi
}
ARTIFACT_REPO="$(artifact_repo)"
case "$ARTIFACT_REPO" in
  company) GH="$GH_COMPANY" ;;
  *)       GH="$GH_PUBLIC" ;;
esac
echo -e "\nCONTAINER: artifact repository '${ARTIFACT_REPO}' -> ${GH}"

# curl: -f fail on HTTP errors, -L follow redirects (GitHub release downloads redirect;
# the company mirror does not), -S show errors despite -s. A failed download must
# stop the load instead of leaving an empty archive for tar to choke on silently.
fetch() { curl -fsSL --output "$1" "$2" || { echo "CONTAINER: download failed: $2" >&2; exit 1; }; }

# no core dumps.
ulimit -c 0

# install Java, as Oracle's JDK was removed from image unfortunately
echo -e "\nCONTAINER: Downloading JDK Adoptium Temurin 17"
if [[ $(uname -m) == 'aarch64' ]]; then
  # https://adoptium.net/en-GB/temurin/releases/?version=17&os=linux&arch=x64&package=jdk
  JDK="${GH}/adoptium/temurin17-binaries/releases/download/jdk-17.0.9%2B9/OpenJDK17U-jdk_aarch64_linux_hotspot_17.0.9_9.tar.gz"
else
  # https://adoptium.net/en-GB/temurin/releases/?version=17&os=linux&arch=x64
  JDK="${GH}/adoptium/temurin17-binaries/releases/download/jdk-17.0.9%2B9/OpenJDK17U-jdk_x64_linux_hotspot_17.0.9_9.tar.gz"
fi
fetch /tmp/jdk.tar.gz "${JDK}"
cd /opt/oracle || exit
mkdir jdk-17
echo -e "\nCONTAINER: Installing JDK"
tar xzf /tmp/jdk.tar.gz --strip-components=1 -C jdk-17 && rm /tmp/jdk.tar.gz
export JAVA_HOME="/opt/oracle/jdk-17"

# install Liquibase
echo -e "\nCONTAINER: Downloading Liquibase ${LQB_VER}"
fetch /tmp/liquibase.tar.gz "${GH}/liquibase/liquibase/releases/download/v${LQB_VER}/liquibase-${LQB_VER}.tar.gz"
echo -e "\nCONTAINER: Installing Liquibase ${LQB_VER}"
mkdir liquibase
cd liquibase || exit
tar xzf /tmp/liquibase.tar.gz && rm /tmp/liquibase.tar.gz
export LIQUIBASE_HOME="/opt/oracle/liquibase"
cd ..

cd "${SCRIPTPATH}" || exit
f="${SCRIPTPATH}/output/initial_load.sql"
echo -e "\nCONTAINER: running ${f} ..."; echo "exit" | sqlplus -s / as sysdba @"${f}"; echo  "CONTAINER: DONE: running ${f}"

# ---- master-data changelogs (moved here from 100_generate_initial_load.sh) --------------
# Generated only now, with the exported schema in place, so that CSVs for tables that are
# created by the changesets AFTER the export tag can be told apart and loaded later.
CONTAINER_NAME="XEPDB1"
OF="${SCRIPTPATH}/initial_changelog.xml"
echo "creating ${OF}"

# The export in ddl/generated reflects the schema at the latest tag; master data is a
# snapshot of the current production data and may contain CSVs for tables that only the
# changesets AFTER the tag create. Those CSVs cannot be loaded before 110_run_initial_load.sh
# has applied the post-tag changesets, so the master data is split in two changelogs:
#   initial_changelog.xml       tables that exist now           -> loaded before the update
#   initial_changelog_post.xml  tables not (yet) in the schema  -> loaded after the update
EXISTING="${SCRIPTPATH}/output/existing_tables.txt"
# trimout: sqlplus pads terminal output to linesize (trimspool only affects spool files);
# the sed strips whatever padding is left so grep -x can match a full line.
sqlplus -s / as sysdba <<EOF_EXISTING | sed 's/[[:space:]]*$//' | grep -v '^$' >"${EXISTING}"
set heading off feedback off pagesize 0 linesize 300 trimout on trimspool on
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
DEFERRED="${SCRIPTPATH}/output/deferred_masterdata.txt"
: >"${DEFERRED}"
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
        if ! grep -qxF "${schemaname}.${tablenameUC}" "${EXISTING}"; then
            echo "  deferred (table not in export): ${schemaname}.${tablenameUC}"
            echo "${f}|${schemaname}|${tablenameUC}|${xmlname}" >>"${DEFERRED}"
            continue
        fi
        if [ -f "$xmlname" ]; then

            echo "<loadData file=\"$f\" schemaName=\"$schemaname\" tableName=\"$tablenameUC\">" >>"${OF}"
            cat "$xmlname" >>"${OF}"
            echo "</loadData>" >>"${OF}"
        else
            echo "<loadData file=\"$f\" schemaName=\"$schemaname\" tableName=\"$tablenameUC\"/>" >>"${OF}"
        fi
    done
    if [ -e "$s/_post.sql" ]; then
        echo "<sqlFile path=\"${s}/_post.sql\"/>" >>"${OF}"
    fi
done
echo "$XML_FOOTER" >>"${OF}"
cd - || exit


echo -e "\nCONTAINER: running liquibase update"
JAVA_OPTS="-Xmx1g"
# disable JIT on QEMU CPU to prevent SIGILL, colima users should use Haswell-4 CPU
grep -F 'model name' /proc/cpuinfo | grep QEMU && JAVA_OPTS="${JAVA_OPTS} -Xint"
export JAVA_OPTS

OF="${SCRIPTPATH}/output/lqb_update.log"
# insert masterdata
"${LIQUIBASE_HOME}"/liquibase --defaultsFile "${SCRIPTPATH}/changes/liquibase-container.properties" --search-path="${SCRIPTPATH},${SCRIPTPATH}/changes,${SCRIPTPATH}/ddl,${SCRIPTPATH}/mappingdata" --changelog-file "initial_changelog.xml" --log-level=INFO --log-file="${OF}" update

OF="${SCRIPTPATH}/output/lqb_sync_plsql.log"
# Pl/SQL has already been compiled
"${LIQUIBASE_HOME}"/liquibase --defaultsFile "${SCRIPTPATH}/changes/liquibase-container.properties" --search-path="${SCRIPTPATH},${SCRIPTPATH}/changes,${SCRIPTPATH}/ddl,${SCRIPTPATH}/mappingdata" --changelogFile="plsql-changelog.xml"  --log-level=INFO --log-file="${OF}" changelog-sync

OF="${SCRIPTPATH}/output/lqb_sync_tag.log"
# for each archive file -> mark whole content as synced
for a in "${SCRIPTPATH}"/changes/changelog-*.archive.sql; do
  FN=$(basename "$a")
  "${LIQUIBASE_HOME}"/liquibase --defaultsFile "${SCRIPTPATH}/changes/liquibase-container.properties" --search-path="${SCRIPTPATH},${SCRIPTPATH}/changes,${SCRIPTPATH}/ddl,${SCRIPTPATH}/mappingdata" --changelogFile="$FN"  --log-level=INFO --log-file="${OF}" changelog-sync
done

# Mark changelog-current.sql as synced up to and including its latest tag changeset (the
# export in ddl/generated already contains everything up to there); everything after the
# tag is applied by the `update` below. Liquibase 4.21.1 does not recognise the `tag:`
# attribute in formatted-SQL changeset headers, so `changelog-sync-to-tag` would silently
# mark the WHOLE file as run and nothing after the tag would ever be applied. Instead the
# file is copied up to the first changeset after the tag line, header included (same
# logicalFilePath, so the DATABASECHANGELOG rows match), and that copy is changelog-sync'ed.
CL="${SCRIPTPATH}/changes/changelog-current.sql"
TAG_LINE=$(grep -nE '^--changeset.*tag:' "${CL}" | tail -1 | cut -d: -f1)
if [ -z "${TAG_LINE}" ]; then
  echo "CONTAINER: no tag changeset found in ${CL} -- cannot tell where the export ends" >&2
  exit 1
fi
NEXT_LINE=$(awk -v t="${TAG_LINE}" 'NR > t && /^--changeset/ { print NR; exit }' "${CL}")
UPTO="${SCRIPTPATH}/output/changelog-current-upto-tag.sql"
if [ -n "${NEXT_LINE}" ]; then head -n $((NEXT_LINE - 1)) "${CL}" > "${UPTO}"; else cp "${CL}" "${UPTO}"; fi
echo "CONTAINER: changelog-current.sql synced up to the tag at line ${TAG_LINE} ($(grep -c '^--changeset' "${UPTO}") changeset(s)); the rest is applied by update"
"${LIQUIBASE_HOME}"/liquibase --defaultsFile "${SCRIPTPATH}/changes/liquibase-container.properties" --search-path="${SCRIPTPATH},${SCRIPTPATH}/changes,${SCRIPTPATH}/ddl,${SCRIPTPATH}/mappingdata" --changelogFile="output/changelog-current-upto-tag.sql" --log-level=INFO --log-file="${OF}" changelog-sync





# apply latest changelog (changelog, mappingdata, but except the PL/SQL)
#
# The master data is a snapshot of CURRENT production data, while the export and the tag
# describe an older state. A post-tag changeset that INSERTs master-data rows therefore
# collides (ORA-00001) with rows the snapshot already contains: that changeset is already
# reflected in the data, so it is marked as ran and the update continues. Any other
# failure is fatal. Bounded, and every skip is logged, so nothing disappears silently.
# (A changeset that mixes several statements and fails on a late one has already committed
# the earlier ones; Oracle DDL autocommits. The invalid-object check in recompile.sql and
# test.sh are the safety net for that case.)
LQB_UPD=("${LIQUIBASE_HOME}"/liquibase --defaultsFile "${SCRIPTPATH}/changes/liquibase-container.properties" --search-path="${SCRIPTPATH},${SCRIPTPATH}/changes,${SCRIPTPATH}/ddl,${SCRIPTPATH}/mappingdata" --log-level=INFO)
MAX_SKIPS=50
SKIPPED=0
while true; do
  OF="${SCRIPTPATH}/output/lqb_apply_mapping_${SKIPPED}.log"
  if "${LQB_UPD[@]}" --log-file="${OF}" update; then
    echo "Liquibase update succeeded (${SKIPPED} post-tag changeset(s) already covered by the master-data snapshot)"
    break
  fi
  FAILED=$(grep -oE 'Migration failed for changeset [^ ]+' "${OF}" | tail -1 | sed 's/Migration failed for changeset //; s/:$//')
  if [ -n "${FAILED}" ] && grep -q 'ORA-00001' "${OF}" && [ "${SKIPPED}" -lt "${MAX_SKIPS}" ]; then
    echo "CONTAINER: changeset ${FAILED} collides with master data already present (ORA-00001) -- marking it as ran"
    echo "${FAILED}" >>"${SCRIPTPATH}/output/changesets_covered_by_masterdata.txt"
    "${LQB_UPD[@]}" --log-file="${SCRIPTPATH}/output/lqb_mark_next.log" mark-next-changeset-ran || exit 1
    SKIPPED=$((SKIPPED + 1))
    continue
  fi
  echo "Liquibase update failed, executing execute-sql command"
  "${LQB_UPD[@]}" execute-sql --sql="select distinct owner, object_name, subobject_name, object_type, status from dba_objects where status!='VALID'" --output-file="${SCRIPTPATH}/output/invalid_objects.txt"
  cat "${SCRIPTPATH}/output/invalid_objects.txt"
  exit 1
done

# ---- master data for the tables that did not exist in the export -----------------------
# They were created (and usually seeded) by the post-tag changesets above, so plain INSERTs
# would collide: use loadUpdateData (update-or-insert on the primary key) wherever the
# table has a primary key, plain loadData otherwise. Generated only now because the primary
# keys can only be read once the tables exist.
OF2="${SCRIPTPATH}/initial_changelog_post.xml"
echo "${XML_HEADER/1::masterData/2::masterDataPostTag}" >"${OF2}"
if [ -s "${DEFERRED}" ]; then
  while IFS='|' read -r f schemaname tablenameUC xmlname; do
    PK=$(sqlplus -s / as sysdba <<EOF_PK | sed 's/[[:space:]]*$//' | grep -v '^$'
set heading off feedback off pagesize 0 linesize 300 trimout on
ALTER SESSION SET CONTAINER=${CONTAINER_NAME};
select listagg(c.column_name, ',') within group (order by c.position)
  from dba_constraints k join dba_cons_columns c on c.owner = k.owner and c.constraint_name = k.constraint_name
 where k.constraint_type = 'P' and k.owner = '${schemaname}' and k.table_name = '${tablenameUC}';
exit
EOF_PK
)
    if [ -n "${PK}" ]; then
      TAG="loadUpdateData"; ATTR=" primaryKey=\"${PK}\""
    else
      TAG="loadData"; ATTR=""
      echo "  ${schemaname}.${tablenameUC}: no primary key found, plain loadData"
    fi
    echo "  ${schemaname}.${tablenameUC}: ${TAG}${ATTR}"
    if [ -f "${xmlname}" ]; then
      echo "<${TAG} file=\"${f}\" schemaName=\"${schemaname}\" tableName=\"${tablenameUC}\"${ATTR}>" >>"${OF2}"
      cat "${xmlname}" >>"${OF2}"
      echo "</${TAG}>" >>"${OF2}"
    else
      echo "<${TAG} file=\"${f}\" schemaName=\"${schemaname}\" tableName=\"${tablenameUC}\"${ATTR}/>" >>"${OF2}"
    fi
  done <"${DEFERRED}"
fi
echo "$XML_FOOTER" >>"${OF2}"
OF="${SCRIPTPATH}/output/lqb_update_post.log"
echo -e "\nCONTAINER: running liquibase update for post-tag master data ($(grep -c . "${DEFERRED}") table(s))"
"${LIQUIBASE_HOME}"/liquibase --defaultsFile "${SCRIPTPATH}/changes/liquibase-container.properties" --search-path="${SCRIPTPATH},${SCRIPTPATH}/changes,${SCRIPTPATH}/ddl,${SCRIPTPATH}/mappingdata" --changelog-file "initial_changelog_post.xml" --log-level=INFO --log-file="${OF}" update || exit 1

# unlock users
f="${SCRIPTPATH}/output/unlock_users.sql"
echo -e "\nCONTAINER: running ${f} ..."; echo "exit" | sqlplus -s / as sysdba @"${f}"; echo  "CONTAINER: DONE: running ${f}"
cd /opt/oracle || exit
