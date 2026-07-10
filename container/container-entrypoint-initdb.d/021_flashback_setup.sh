#!/bin/bash

set >/container-entrypoint-initdb.d/021_flashback_setup.set
if [ -z "${FLASHBACK:=NO}"]; then
  FLASHBACK="NO"
else
  if [ "${FLASHBACK^^}" == "YES" ]; then
    echo "Activating ARCHIVEMODE & FLASHBACK"
    sqlplus SYS/$ORACLE_PASSWORD AS SYSDBA >021_flashback_setup.log <<EOF
    @/container-entrypoint-initdb.d/021_flashback_setup.yes
EOF
  fi
fi
touch /mcdb/DONTCLEANUP
