--liquibase formatted sql logicalFilePath:pkgb/mcdb_checks_consistency.sql
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE BODY MCDB_CHECKS.CONSISTENCY AS

  FUNCTION exec_formatted ( cur varchar2 ) RETURN VARCHAR2 AS
    col_cnt     pls_integer;
    rec_tab     dbms_sql.desc_tab;
    handle      pls_integer;
    v_v_val     VARCHAR2(4000);
    v_n_val     NUMBER;
    v_d_val     DATE;
    v_finaltxt  VARCHAR2(4000);
    ignore INTEGER;
  begin
    DECLARE
      err_num NUMBER;
      err_msg VARCHAR2(100);
    BEGIN
      handle := DBMS_SQL.OPEN_CURSOR;
      DBMS_SQL.PARSE(handle, cur, DBMS_SQL.NATIVE);
      ignore := DBMS_SQL.EXECUTE(handle);
    EXCEPTION
      WHEN OTHERS THEN
        err_num := SQLCODE;
        err_msg := SUBSTR(SQLERRM, 1, 100);
        RETURN 'ERROR (:' || err_num || ') "' || err_msg || '" in \\n' || cur;
    END;

    dbms_sql.describe_columns( handle, col_cnt, rec_tab );

    -- Define columns (necessary to retrieve results of the Query)
    FOR i IN 1 .. col_cnt LOOP
        IF rec_tab(i).col_type = 2 THEN
          DBMS_SQL.DEFINE_COLUMN(handle, i, v_n_val);
        ELSIF rec_tab(i).col_type = 12 THEN
          DBMS_SQL.DEFINE_COLUMN(handle, i, v_d_val);
        ELSE
          DBMS_SQL.DEFINE_COLUMN(handle, i, v_v_val, 250);
        END IF;
      END LOOP;
    BEGIN
      v_finaltxt := '';
      WHILE DBMS_SQL.FETCH_ROWS(handle)>0 LOOP --    << row_loop >>
      --    << col_loop >>
          FOR j in 1..col_cnt
            LOOP
              v_finaltxt := v_finaltxt  || rec_tab(j).col_name || ': ';
              CASE rec_tab(j).col_type
                WHEN 1 THEN DBMS_SQL.COLUMN_VALUE(handle,j,v_v_val);
                            v_finaltxt := ltrim(v_finaltxt||'"'||v_v_val||'"',',');
                WHEN 2 THEN DBMS_SQL.COLUMN_VALUE(handle,j,v_n_val);
                            v_finaltxt := ltrim(v_finaltxt||v_n_val,',');
                WHEN 12 THEN DBMS_SQL.COLUMN_VALUE(handle,j,v_d_val);
                             v_finaltxt := ltrim(v_finaltxt||to_char(v_d_val,'DD/MM/YYYY HH24:MI:SS'),',');
                ELSE
                  DBMS_SQL.COLUMN_VALUE(handle,j,v_v_val);
                  v_finaltxt := ltrim(v_finaltxt||'"'||v_v_val||'"',',');
                END CASE;
              v_finaltxt := v_finaltxt || CHR(10);
            end loop;
          v_finaltxt := v_finaltxt || CHR(10) ;
        END LOOP; -- row_loop;
    EXCEPTION WHEN VALUE_ERROR THEN
      DECLARE v_missing INT;
      BEGIN
        v_missing := 1;
        WHILE DBMS_SQL.FETCH_ROWS(handle)>0 LOOP
            v_missing := v_missing + 1;
          end loop;
        v_finaltxt := SUBSTR(v_finaltxt,0,3500) || '... plus at least ' || v_missing || ' records more. See XML!';
      end;
    END;
    dbms_sql.close_cursor(handle);

    return v_finaltxt;

  end exec_formatted;

  PROCEDURE insert_result(p_check_id IN VARCHAR2, p_severity IN VARCHAR2, p_message IN VARCHAR2, p_xml_msg IN CLOB, p_check_group IN VARCHAR2 DEFAULT '')
    IS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    MERGE INTO MCDB_MONITOR.LAST_CONSISTENCY_CHECK_RESULTS r USING dual ON ( r.check_id = p_check_id )
    WHEN MATCHED THEN UPDATE SET r.LAST_RUN = CURRENT_TIMESTAMP , r.message =  p_message, r.XML_MESSAGE = p_xml_msg, r.LOGLEVEL = p_severity
    WHEN NOT MATCHED THEN INSERT (CHECK_ID, CHECK_GROUP, MESSAGE, XML_MESSAGE, LOGLEVEL, LAST_RUN)
                          VALUES ( p_check_id, p_check_group, p_message, p_xml_msg, p_severity, CURRENT_TIMESTAMP);

    COMMIT;
  END insert_result;


  PROCEDURE execute_checks_group(
    group_name IN varchar2,
    level_log  IN BOOLEAN DEFAULT false,
    edge_log   IN BOOLEAN DEFAULT true
  ) IS
    cursor stmt_cursor is
      select c.CHECK_KEY, c.STATEMENT, c.SLOGLEVEL,c.PLOGLEVEL,r.LAST_RESULT_HASH, c.MESSAGE , c.ID
      from MCDB_CHECKS.CONSISTENCY_CHECKS c
           LEFT OUTER JOIN MCDB_CHECKS.CONSISTENCY_CHECK_RUN r
                           ON (c.ID = r.ID)
      where c.CHECK_GROUP = group_name;
    v_message VARCHAR2(4000);
    v_xml_msg CLOB;
    v_severity VARCHAR2(40);
    v_raw_conversion_buf VARCHAR2(10000);
    v_msg_hash RAW(20);
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    for check_rec in stmt_cursor
      LOOP
        DECLARE
          l_cursor   SYS_REFCURSOR;
        BEGIN
          v_message := exec_formatted(TRIM(TRAILING ';' FROM TRIM(BOTH FROM check_rec.STATEMENT)));
          v_xml_msg := null;
          IF (v_message IS NOT NULL) THEN
            -- Check if the Query itself encountered Error and exec_formatted(query) returned the ERROR message.
            -- Also pass it to the Queue, no need for secondary channels
            IF ( SUBSTR(v_message,1,5) = 'ERROR' ) THEN
              v_message := v_message;
              v_severity := 'QUERY_ERROR';
            else
              v_message := 'MCDB_CHECKS '|| check_rec.MESSAGE || CHR(10) || substr(v_message, 0, 4000 - LENGTH( check_rec.MESSAGE) - 20);
              v_severity := check_rec.SLOGLEVEL;
              v_xml_msg  := dbms_xmlgen.getxml(check_rec.STATEMENT);
            end if;
          ELSE
            v_severity := 'CLEAR';
          END IF;
          v_raw_conversion_buf := v_message;
          v_msg_hash := DBMS_CRYPTO.HASH(UTL_RAW.CAST_TO_RAW(v_raw_conversion_buf), DBMS_CRYPTO.HASH_SH1);
          if (NVL(v_msg_hash, '-') != NVL(check_rec.LAST_RESULT_HASH, '-')) THEN
            -- Compatibility measure: Send the message only with the desired loglevel to Syslog.
            -- Edge notification: at every change, also when the warning is cleared, a message is sent
            IF edge_log and v_severity != 'CLEAR' THEN
              OSAG.OSAG_PLOG.LOG(check_rec.PLOGLEVEL, 'MCDB_CHECKS '|| check_rec.MESSAGE);
            END IF;
            insert_result(check_rec.CHECK_KEY, v_severity, v_message, v_xml_msg, group_name);

            merge into MCDB_CHECKS.CONSISTENCY_CHECK_RUN chkrun
            using (select ID, CHECK_KEY FROM MCDB_CHECKS.CONSISTENCY_CHECKS
                   WHERE ID = check_rec.ID ) chkdef
            on (chkdef.ID = chkrun.ID)
            when matched then update set
                                       chkrun.CHECK_KEY = chkdef.CHECK_KEY,
                                       chkrun.LAST_RUN  = CURRENT_TIMESTAMP,
                                       chkrun.LAST_RESULT_HASH = v_msg_hash
            when not matched then insert (id, check_key, last_run, last_result_hash)
                                  VALUES (chkdef.ID, chkdef.CHECK_KEY, CURRENT_TIMESTAMP, v_msg_hash );
          else
            merge into MCDB_CHECKS.CONSISTENCY_CHECK_RUN chkrun
            using (select ID, CHECK_KEY FROM MCDB_CHECKS.CONSISTENCY_CHECKS
                   WHERE ID = check_rec.ID ) chkdef
            on (chkdef.ID = chkrun.ID)
            when matched then update set
                                       chkrun.CHECK_KEY = chkdef.CHECK_KEY,
                                       chkrun.LAST_RUN  = CURRENT_TIMESTAMP
            when not matched then insert (id, check_key, last_run)
                                  VALUES (chkdef.ID, chkdef.CHECK_KEY, CURRENT_TIMESTAMP);
          end if;
          -- Compatibility measure: Send the message only with the desired loglevel to Syslog.
          -- Level notification: as long as an error condition is given, send log messages
          IF level_log AND v_severity != 'CLEAR' THEN
            OSAG.OSAG_PLOG.LOG(check_rec.PLOGLEVEL, 'MCDB_CHECKS '|| check_rec.MESSAGE);
          END IF;
          COMMIT ;
        END;
      end loop ;
  end execute_checks_group;

END CONSISTENCY;
/
