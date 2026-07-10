#!/bin/bash
shopt -s nullglob
LQB_VER="4.21.1"
SCRIPTPATH="/mcdb"
GH="https://artifacts.open.ch/artifactory/github-releases-remote"

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
curl -s --output /tmp/jdk.tar.gz "${JDK}"
cd /opt/oracle || exit
mkdir jdk-17
echo -e "\nCONTAINER: Installing JDK"
tar xzf /tmp/jdk.tar.gz --strip-components=1 -C jdk-17 && rm /tmp/jdk.tar.gz
export JAVA_HOME="/opt/oracle/jdk-17"

# install Liquibase
echo -e "\nCONTAINER: Downloading Liquibase ${LQB_VER}"
curl -s --output /tmp/liquibase.tar.gz "${GH}/liquibase/liquibase/releases/download/v${LQB_VER}/liquibase-${LQB_VER}.tar.gz"
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

# mark current changelog up to latest tag as synced (already part of schema)
TAG=$(grep -E -e '^--changeset.*tag' "${SCRIPTPATH}/changes/changelog-current.sql" | tail -1 | sed -n 's/.*tag:\([^[:space:]]*\).*/\1/p')
"${LIQUIBASE_HOME}"/liquibase --defaultsFile "${SCRIPTPATH}/changes/liquibase-container.properties" --search-path="${SCRIPTPATH},${SCRIPTPATH}/changes,${SCRIPTPATH}/ddl,${SCRIPTPATH}/mappingdata" --log-level=INFO --log-file="${OF}" changelog-sync-to-tag --tag="$TAG"





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
