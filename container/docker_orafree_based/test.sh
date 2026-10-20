#!/bin/bash
set -e
set -o pipefail

# All checks run inside the PDB (a bare `/ as sysdba` lands in the CDB root, where the
# MCDB schemas do not exist and every count is a vacuous 0). Each sqlplus result is
# checked to be an integer: an error text would otherwise fail the numeric [[ ]] test
# silently, because `set -e` does not apply inside an if condition.
numeric() {
    local v="${1//[[:space:]]}"
    if [[ ! "$v" =~ ^[0-9]+$ ]]; then
        echo "test.sh: expected a number from sqlplus, got: $1" >&2
        exit 1
    fi
    echo "$v"
}

INVALID_OBJECTS=$(sqlplus -s / as sysdba <<'EOF'
  set heading off feedback off;
  ALTER SESSION SET CONTAINER=XEPDB1;
  select count(*) from all_objects where status != 'VALID';
  exit
EOF
)
INVALID_OBJECTS=$(numeric "$INVALID_OBJECTS")

if [[ "${INVALID_OBJECTS}" -gt 0 ]]; then
    echo "Found invalid objects $INVALID_OBJECTS" >&2
    sqlplus -s / as sysdba <<EOF >&2
  set heading off feedback off pagesize 0 linesize 200
  ALTER SESSION SET CONTAINER=XEPDB1;
  select '  '||owner||'.'||object_name||' ('||object_type||')' from all_objects where status != 'VALID' order by 1;
  exit
EOF
    exit 1
fi

INVALID_INDEXES=$(sqlplus -s / as sysdba <<'EOF'
  set heading off feedback off;
  ALTER SESSION SET CONTAINER=XEPDB1;
  select count(*) from DBA_INDEXES where status != 'VALID' and owner not in (select username from SYS.DBA_USERS where ORACLE_MAINTAINED='Y');
  exit
EOF
)
INVALID_INDEXES=$(numeric "$INVALID_INDEXES")

if [[ "${INVALID_INDEXES}" -gt 0 ]]; then
    echo "Found invalid indexes $INVALID_INDEXES" >&2
    exit 1
fi

NO_BODY=$(sqlplus -s / as sysdba <<'EOF'
  set heading off feedback off;
  ALTER SESSION SET CONTAINER=XEPDB1;
  select count(*) from SYS.DBA_OBJECTS h
  where h.OBJECT_TYPE='PACKAGE'
    and not exists (select 1 from SYS.DBA_OBJECTS b
                    where  b.OBJECT_TYPE='PACKAGE BODY'
                      and h.OBJECT_NAME = b.OBJECT_NAME
                      and h.OWNER = b.OWNER)
    and h.OWNER in (select distinct r.grantee
                    from dba_role_privs r
                    where granted_role in ('MSS_LOGIN_USER', 'MSS_SCHEMA_USER')
                      and r.grantee not in (select username from SYS.DBA_USERS where ORACLE_MAINTAINED='Y'));
  exit
EOF
)
NO_BODY=$(numeric "$NO_BODY")

if [[ "${NO_BODY}" -gt 0 ]]; then
    echo "Found packages without body $NO_BODY" >&2
    exit 1
fi

BAD_CONSTRAINTS=$(sqlplus -s / as sysdba <<'EOF'
  set heading off feedback off;
  ALTER SESSION SET CONTAINER=XEPDB1;
  select count(*) from SYS.DBA_CONSTRAINTS
  where OWNER not in (select username from SYS.DBA_USERS where ORACLE_MAINTAINED='Y')
  and DEFERRED!='IMMEDIATE';
  exit
EOF
)
BAD_CONSTRAINTS=$(numeric "$BAD_CONSTRAINTS")

if [[ "${BAD_CONSTRAINTS}" -gt 20 ]]; then
    echo "Found suspicious amount of DEFERRED constraints $BAD_CONSTRAINTS" >&2
    exit 1
fi

ID=$(grep -E -e '^--changeset.*tag' "/mcdb/changes/changelog-current.sql" | tail -1 | sed -n 's/^--changeset [^:]*:\([^[:space:]]*\).*/\1/p')
# unquoted heredoc on purpose: ${ID} must be expanded (it never was with <<'EOF')
FIND_ID=$(sqlplus -s / as sysdba <<EOF
  set heading off feedback off;
  ALTER SESSION SET CONTAINER=XEPDB1;
  select count(*) from LQB.DATABASECHANGELOG where ID='${ID}';
  exit
EOF
)
FIND_ID=$(numeric "$FIND_ID")

if [[ "${FIND_ID}" -ne 1 ]]; then
    echo "Last changelog with ID ${ID} not found in DATABASECHANGELOG" >&2
    exit 1
fi
