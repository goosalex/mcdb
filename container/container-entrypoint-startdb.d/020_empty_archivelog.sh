#!/bin/bash
# FLASHBACK is normally unset. The entrypoint sources this file with `set -u`, so an
# unguarded ${FLASHBACK} aborts every start after the first one (the first start is
# saved only by the DONTCLEANUP marker that 021_flashback_setup.sh leaves behind).
FLASHBACK="${FLASHBACK:-NO}"
if [ -f /mcdb/DONTCLEANUP ]; then
  rm /mcdb/DONTCLEANUP
elif [ "${FLASHBACK^^}" == "YES" ]; then
  echo "Remove old archivelog, Flashback is only available back to this startup"
  ORACLE_SID=EE rman TARGET / NOCATALOG cmdfile=/container-entrypoint-startdb.d/020_empty_archivelog.yes
fi
