--liquibase formatted sql logicalFilePath:pkgb/report_osag_channel.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE BODY REPORT.OSAG_CHANNEL IS

    PROCEDURE run_queries AS

        c_prefix CONSTANT VARCHAR2(64) := 'OSAG_CHANNEL.run_queries(): ';
        l_time    DATE   := SYSDATE;
        l_minute  NUMBER := to_number(to_char(l_time, 'MI'));
        l_hour    NUMBER := to_number(to_char(l_time, 'HH24'));
        l_day     NUMBER := to_number(to_char(l_time, 'D')) - 1;
        v_channelvalue report.channelvalue.VALUE%TYPE;
        v_channelvalue_id report.channelvalue.ID%TYPE;

        CURSOR l_key_cursor IS
            SELECT k.id, k.sqlquery, k.exechour, k.execminute, k.execday, k.execinterval, k.historysize, k.lastupdated FROM report.channelkey k
            WHERE
                ((k.execinterval IS NOT NULL AND (l_time - k.lastupdated) * 24 * 60 >= k.execinterval)
                    OR (k.execinterval IS NULL
                        AND (k.execminute IS NULL
                            OR (k.execminute = l_minute
                                AND ((k.exechour IS NULL AND to_number(to_char(k.lastupdated, 'HH24')) != l_hour)
                                    OR (k.exechour = l_hour AND trunc(k.lastupdated, 'DD') != trunc(l_time, 'DD')
                                        AND (k.execday IS NULL OR k.execday = l_day)
                                         )
                                    )
                                 )
                            )
                     )
                    );


    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        FOR l_key IN l_key_cursor LOOP

                BEGIN
                    -- collect the value
                    EXECUTE IMMEDIATE trim(TRAILING ';' FROM l_key.sqlquery) INTO v_channelvalue;
                    SELECT report.seq_channelvalue_id.nextval INTO v_channelvalue_id FROM dual;
                    INSERT INTO report.channelvalue (channelkey_id, timestamp, value, id) VALUES (l_key.id, l_time, v_channelvalue, v_channelvalue_id);
                    -- update last run on channelkey
                    UPDATE report.channelkey SET lastupdated = l_time, last_value_id = v_channelvalue_id WHERE id = l_key.id;

                    -- clean up history
                    DELETE FROM report.channelvalue WHERE id IN
                                                          (SELECT id FROM
                                                              (SELECT id, row_number() OVER (ORDER BY timestamp DESC) r FROM report.channelvalue WHERE channelkey_id = l_key.id)
                                                           WHERE r > l_key.historysize);

                EXCEPTION
                    WHEN NO_DATA_FOUND THEN
                        plog.warning(c_prefix||'REPORT.CHANNEL_KEY#'|| l_key.id ||': no data found');
                    WHEN OTHERS THEN
                        plog.err(c_prefix||'unexpected error for REPORT.CHANNEL_KEY#' || l_key.id || ': '||sqlerrm);

                END;

            END LOOP;

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            plog.warning(c_prefix||'no data found');
        WHEN OTHERS THEN
            plog.err(c_prefix||'unexpected error: '||sqlerrm);

    END run_queries;


    PROCEDURE count_hosts AS

        c_prefix CONSTANT VARCHAR2(64) := 'OSAG_CHANNEL.count_hosts(): ';
        v_host_count NUMBER;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        SELECT COUNT(*) INTO v_host_count FROM mss.host WHERE active = 1;

        INSERT INTO report.host_count (ID, DATE_COUNTED, HOSTCOUNT)
            (SELECT report.host_count_seq.nextval, systimestamp,v_host_count FROM dual);

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(c_prefix||'unexpected error: '||sqlerrm);

    END count_hosts;

END OSAG_CHANNEL;
/
