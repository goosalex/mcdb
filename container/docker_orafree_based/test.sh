#!/bin/bash
set -e
set -o pipefail

INVALID_OBJECTS=$(sqlplus -s / as sysdba <<'EOF'
  set heading off;
  select count(*) from all_objects where status != 'VALID';
  exit
EOF
)

if [[ "${INVALID_OBJECTS//[$'\r\n']}" -gt 0 ]]; then
    echo "Found invalid objects $INVALID_OBJECTS" >&2
    exit 1
fi

INVALID_INDEXES=$(sqlplus -s / as sysdba <<'EOF'
  set heading off;
  select count(*) from DBA_INDEXES where status != 'VALID' and owner not in (select username from SYS.DBA_USERS where ORACLE_MAINTAINED='Y');
  exit
EOF
)

if [[ "${INVALID_INDEXES//[$'\r\n']}" -gt 0 ]]; then
    echo "Found invalid indexes $INVALID_INDEXES" >&2
    exit 1
fi

NO_BODY=$(sqlplus -s / as sysdba <<'EOF'
  set heading off;
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

if [[ "${NO_BODY//[$'\r\n']}" -gt 0 ]]; then
    echo "Found packages without body $NO_BODY" >&2
    exit 1
fi

BAD_CONSTRAINTS=$(sqlplus -s / as sysdba <<'EOF'
  set heading off;
  select count(*) from SYS.DBA_CONSTRAINTS
  where OWNER not in (select username from SYS.DBA_USERS where ORACLE_MAINTAINED='Y')
  and DEFERRED!='IMMEDIATE';
  exit
EOF
)

if [[ "${BAD_CONSTRAINTS//[$'\r\n']}" -gt 20 ]]; then
    echo "Found suspicious amount of DEFERRED constraints $BAD_CONSTRAINTS" >&2
    exit 1
fi

ID=$(grep -E -e '^--changeset.*tag' "/mcdb/changes/changelog-current.sql" | tail -1 | sed -n 's/^--changeset [^:]*:\([^[:space:]]*\).*/\1/p')
FIND_ID=$(sqlplus -s / as sysdba <<'EOF'
  set heading off;
  select count(*) from LQB.DATABASECHANGELOG where ID='${ID}';
  exit
EOF
)

if [[ "${FIND_ID//[$'\r\n']}" -ne 1 ]]; then
    echo "Last changelog with ID ${ID} not found in DATABASECHANGELOG" >&2
    exit 1
fi
