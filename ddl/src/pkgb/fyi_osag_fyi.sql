--liquibase formatted sql logicalFilePath:pkgb/fyi_osag_fyi.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE BODY fyi.OSAG_FYI IS

    --------------------------------------------------------------------------------
    -- procedure check_resolved_tickets
    --------------------------------------------------------------------------------
    PROCEDURE check_old_entries AS

        oldest_event_time TIMESTAMP WITH TIME ZONE := (SYSTIMESTAMP - INTERVAL '93' DAY);

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);

        DELETE
        FROM fyi.message_history fm
        WHERE fm.notification_event_id IN (SELECT id
                                           FROM notification_event
                                           WHERE event_time < oldest_event_time);

        DELETE
        FROM fyi.affected_host fa
        WHERE fa.notification_event_id IN (SELECT id
                                           FROM fyi.notification_event
                                           WHERE (event_time < oldest_event_time));

        DELETE
        FROM fyi.notification_event
        WHERE (event_time < oldest_event_time);

        DELETE
        FROM fyi.last_seen
        WHERE (last_seen < oldest_event_time);

        DELETE
        FROM fyi.target ft
        WHERE NOT EXISTS (SELECT *
                          FROM fyi.last_seen fl
                          WHERE fl.target_id = ft.id);

    END check_old_entries;

END OSAG_FYI;
/
