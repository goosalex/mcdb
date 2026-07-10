#!/bin/bash
# Use old v12 format to avoid complexity requirements
orapwd file="${ORACLE_HOME}"/dbs/orapwEE password=password  force=Y format=12

ORACLE_PWD=$ORACLE_PASSWORD
ORACLE_PDB=XEPDB1
sqlplus / as sysdba << EOF
      ALTER USER SYS IDENTIFIED BY "$ORACLE_PWD";
      ALTER USER SYSTEM IDENTIFIED BY "$ORACLE_PWD";
      ALTER SESSION SET CONTAINER=$ORACLE_PDB;
      ALTER USER PDBADMIN IDENTIFIED BY "$ORACLE_PWD";
      exit;
EOF
