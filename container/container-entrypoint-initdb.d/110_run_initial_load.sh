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





OF="${SCRIPTPATH}/output/lqb_apply_mapping.log"
# apply latest changelog (changelog, mappingdata, but except the PL/SQL)
if "${LIQUIBASE_HOME}"/liquibase --defaultsFile "${SCRIPTPATH}/changes/liquibase-container.properties" --search-path="${SCRIPTPATH},${SCRIPTPATH}/changes,${SCRIPTPATH}/ddl,${SCRIPTPATH}/mappingdata" --log-level=INFO --log-file="${OF}" update; then
# If the liquibase command fails then execute the execute-sql liquibase command
  echo "Liquibase update succeeded"
else
  echo "Liquibase update failed, executing execute-sql command"
  "${LIQUIBASE_HOME}"/liquibase --defaultsFile "${SCRIPTPATH}/changes/liquibase-container.properties" --search-path="${SCRIPTPATH},${SCRIPTPATH}/changes,${SCRIPTPATH}/ddl,${SCRIPTPATH}/mappingdata"  execute-sql --sql="select distinct owner, object_name, subobject_name, object_type, status from dba_objects where status!='VALID'" --output-file="${SCRIPTPATH}/output/invalid_objects.txt"
  cat "${SCRIPTPATH}/output/invalid_objects.txt"
  exit 1
fi

# unlock users
f="${SCRIPTPATH}/output/unlock_users.sql"
echo -e "\nCONTAINER: running ${f} ..."; echo "exit" | sqlplus -s / as sysdba @"${f}"; echo  "CONTAINER: DONE: running ${f}"
cd /opt/oracle || exit
