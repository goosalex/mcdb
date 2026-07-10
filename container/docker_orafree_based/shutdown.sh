#!/bin/sh
lsnrctl stop
sqlplus -s / as sysdba <<'EOF'
         WHENEVER SQLERROR EXIT SQL.SQLCODE
         -- force a checkpoint to minimize instance recovery time
         alter system checkpoint;
         call DBMS_SESSION.sleep(3);
         shutdown transactional;
         exit;
EOF
sleep 3
