#!/bin/bash
if [ -f /mcdb/DONTCLEANUP ]; then
  rm /mcdb/DONTCLEANUP
elif [ "${FLASHBACK^^}" == "YES" ]; then
  echo "Remove old archivelog, Flashback is only available back to this startup"
  ORACLE_SID=EE rman TARGET / NOCATALOG cmdfile=/container-entrypoint-startdb.d/020_empty_archivelog.yes
fi
