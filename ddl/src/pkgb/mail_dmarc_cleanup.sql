--liquibase formatted sql logicalFilePath:pkgb/mail_dmarc_cleanup.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE BODY mail.dmarc_cleanup AS
    PROCEDURE cleanup_reports_aged_days(days NUMBER) IS
    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        DECLARE
            deadlock_detected EXCEPTION;
            PRAGMA EXCEPTION_INIT (deadlock_detected, -60);
            -- custom error, when checking number of days input
            -- any error number between -20000 and -20999
            invalid_days_range EXCEPTION;
            PRAGMA exception_init (invalid_days_range, -20001);
        BEGIN
            IF (days < 1) THEN
                raise_application_error(-20001, 'Number of days to keep must be positive');
                plog.ERR('Number of days to keep must be positive');
            END IF;
            LOOP
                BEGIN
                    DELETE
                    from mail.DMARC_REPORT_RECORD
                    where exists(
                                  select 1
                                  from mail.DMARC_REPORT
                                  where mail.DMARC_REPORT_RECORD.DMARC_REPORT_ID = mail.DMARC_REPORT.ID
                                    and mail.DMARC_REPORT.START_DATE < (sysdate - days)
                              );

                    DELETE
                    from mail.DMARC_REPORT
                    where mail.DMARC_REPORT.START_DATE < (sysdate - days);
                    exit; -- successful, happy path
                EXCEPTION
                    WHEN deadlock_detected THEN BEGIN
                        plog.NOTICE('Failed, sleeping');
                        dbms_session.sleep(60);
                    END;
                    WHEN OTHERS THEN
                        raise;
                END;
            END LOOP;
        END;
    END; -- cleanup_reports_aged_days;

END dmarc_cleanup;
/
