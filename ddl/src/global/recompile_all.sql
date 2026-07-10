begin
    for r in (select distinct owner from dba_objects where status!='VALID') loop
            DBMS_UTILITY.compile_schema(schema => r.owner, compile_all => false);
    end loop;
end;
/
