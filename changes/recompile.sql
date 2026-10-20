--liquibase formatted sql logicalFilePath:recompile.sql
--changeset ogl:recompile-all endDelimiter:/ runAlways:true runOnChange:true
--validCheckSum: 8:ff3f136bc91cecf29ce85b9fd9da15df
begin
    for r in (select distinct owner from dba_objects where status!='VALID' and owner!='SYS') loop
            DBMS_UTILITY.compile_schema(schema => r.owner, compile_all => false);
    end loop;
end;
/
--changeset ogl:check-invalid-objs runAlways:true
--preconditions onFail:HALT onFailMessage:There are invalid objects
--precondition-sql-check expectedResult:0 select count(*) from dba_objects where status!='VALID' and owner!='SYS'
--comment:
select 1 from dual;

--changeset ogl:check-missing-body runAlways:true
--preconditions onFail:HALT onFailMessage:There PL/SQL package definitions without package body
--precondition-sql-check expectedResult:0 select count(*) from SYS.DBA_OBJECTS h where h.OBJECT_TYPE='PACKAGE' and not exists (select 1 from SYS.DBA_OBJECTS b where  b.OBJECT_TYPE='PACKAGE BODY' and h.OBJECT_NAME = b.OBJECT_NAME and h.OWNER = b.OWNER) and h.OWNER in (select distinct r.grantee from dba_role_privs r where granted_role in ('MSS_LOGIN_USER', 'MSS_SCHEMA_USER') and r.grantee != 'SYS')
--comment:
select 1 from dual;

--changeset ogl:check-index-owner runAlways:true
--preconditions onFail:HALT onFailMessage:There are indexes owned by SYS on non-SYS tables
--precondition-sql-check expectedResult:0 select count(*) from dba_indexes where owner = 'SYS' and TABLE_OWNER != 'SYS'
select 1 from dual;
