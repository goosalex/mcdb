ALTER SESSION SET CURRENT_SCHEMA = DBREADER;
CREATE OR REPLACE DIRECTORY CLOBDIR AS '/dbdata/clobexport';
GRANT read,write ON DIRECTORY CLOBDIR TO DBREADER;

create or replace function quote(pString varchar2) return varchar2 is
begin
    -- replace " or \" with \"
return chr(34)||regexp_replace(pString,'(\\"|")','\"')||chr(34); -- fixes already quoted strings too
end;
create or replace function replace_quote(pString varchar2) return varchar2 is
begin
    -- replace " or \" with \"
return regexp_replace(pString,'(\\"|")','\"'); -- fixes already quoted strings too
end;

CREATE OR REPLACE FUNCTION  EXPORT_TABLE_TO_CSV_FILE
(
    p_query     in dbms_sql.varchar2a,
    p_separator in varchar2 default ',',
    p_dir       in varchar2,
    p_filename  in varchar2,
    p_is_head   in boolean default false
)
    RETURN NUMBER
    is
    l_output        utl_file.file_type;
    l_theCursor     integer default dbms_sql.open_cursor;
    l_columnValue   varchar2(4000);
    l_columnValClob clob;
    l_status        integer;
    l_colCnt        number default 0;
    l_separator     varchar2(10) default '';
    l_cnt           number default 0;
    l_col_desc      dbms_sql.desc_tab;
    l_offset        integer;
BEGIN
    dbms_sql.parse
(
            l_theCursor
        , p_query
        , p_query.first
        , p_query.last
        , true
        , dbms_sql.native
    );

    dbms_sql.describe_columns
(
            l_theCursor
        , l_colCnt
        , l_col_desc
    );

for i in 1 .. l_colCnt loop
            if l_col_desc(i).col_type = 112 then
                dbms_sql.define_column
                (
                        l_theCursor
                    , i
                    , l_columnValClob
                );
else
                dbms_sql.define_column
                (
                        l_theCursor
                    , i
                    , l_columnValue
                    , 4000
                );
end if;
end loop;

    l_status := dbms_sql.execute(l_theCursor);
    if dbms_sql.fetch_rows(l_theCursor) > 0 then
        l_output := utl_file.fopen( p_dir, p_filename, 'w', 32767 );
        if p_is_head then
            for i in 1..l_col_desc.count
                loop
                    utl_file.put(l_output, l_separator || l_col_desc(i).col_name);
                    l_separator := p_separator;
end loop;
            utl_file.new_line( l_output );
end if;

        loop
l_separator := '';
for i in 1 .. l_colCnt
                loop
                    if l_col_desc(i).col_type = 112
                    then
                        l_offset := 1;
                        dbms_sql.column_value
(
                                l_theCursor
                            , i
                            , l_columnValClob
                        );
                        utl_file.put( l_output, l_separator );
                        utl_file.put( l_output, chr(34) );
                        loop
l_columnValue := replace_quote(dbms_lob.substr(l_columnValClob, 2000, l_offset));
                            -- dbms_output.put_line(l_columnValue);
                            l_offset := l_offset + 2000;
                            utl_file.put( l_output, l_columnValue);
                            exit when trim(l_columnValue) is null;
end loop;
                        utl_file.put( l_output, chr(34) );
else
                        dbms_sql.column_value
                        (
                                l_theCursor
                            , i
                            , l_columnValue
                        );
                        utl_file.put( l_output, l_separator ||  quote(l_columnValue) );
end if;

                    l_separator := p_separator;
end loop;

            utl_file.new_line( l_output );
            l_cnt := l_cnt+1;

            exit when ( dbms_sql.fetch_rows(l_theCursor) <= 0 );
end loop;
end if;
    dbms_sql.close_cursor(l_theCursor);
    utl_file.fclose( l_output );
return l_cnt;
END;
/


CREATE TABLE DBREADER.LOB_EXPORT AS
select distinct OWNER,TABLE_NAME,0 row_count from DBA_LOBS where TABLESPACE_NAME in ( 'USERS', 'TT', 'MCAUDIT');


DECLARE
l_sql dbms_sql.varchar2a;
    l_cnt integer;
BEGIN
        FOR export_item IN (
            SELECT OWNER, TABLE_NAME FROM DBREADER.LOB_EXPORT
        ) LOOP
        l_sql(1) := 'SELECT * FROM ' || trim(export_item.OWNER) || '.' || trim(export_item.TABLE_NAME);
        l_cnt := export_table_to_csv_file
                (
            l_sql,
            ',',
            'CLOBDIR',
            lower(export_item.OWNER) || '_' || lower(export_item.TABLE_NAME) || '.csv',
            TRUE
                );
          UPDATE DBREADER.LOB_EXPORT SET row_count = l_cnt
          WHERE OWNER = export_item.OWNER AND TABLE_NAME = export_item.TABLE_NAME;
        COMMIT;
    END LOOP;
END;
/