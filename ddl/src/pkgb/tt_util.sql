--liquibase formatted sql logicalFilePath:pkgb/tt_util.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE BODY tt.util IS
--------------------------------------------------------------------------------
-- procedure check_resolved_tickets
--------------------------------------------------------------------------------
    PROCEDURE check_resolved_tickets AS

        CURSOR cur_resolved IS
            SELECT tt.ticket.id
            FROM tt.ticket
            WHERE status_id = 101
              AND (SYSDATE - last_resolved_date) >= 14;

        rec_resolved  cur_resolved%ROWTYPE;
        v_eventdate DATE;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        FOR rec_resolved in cur_resolved
            --loop over all tickets with status resolved
            LOOP
                tt.ticket_interface.change_status(rec_resolved.id,102,NULL,'ticket resolved for more than 2 weeks, closing it automatically');
                UPDATE tt.ticket
                SET close_date = sysdate
                WHERE id = rec_resolved.id;

                -- delete notifications when the ticket is set to closed
                TT.OSAG_NOTIFY.delete_ticket_notifications(rec_resolved.id);

            END LOOP;


    END check_resolved_tickets;

--------------------------------------------------------------------------------
-- procedure check_ticket_status
--------------------------------------------------------------------------------
    PROCEDURE check_ticket_status AS

        -- includes status waiting (11), third party (12), deferred(60), waiting for sign-off(61) MCC and non-mcc tickets
        -- deferred tickets are resurrected by this procedure as well
        -- hot (3) filtered out because status_valid_until_date is always null
        CURSOR t_cur_valid_date_not_null IS
            SELECT t.id as t_id,
                   t.status_valid_until_date as t_valid_until,
                   s.name as s_name,
                   t.last_status_change_date as t_last_change,
                   t.status_id as t_status_id,
                   t.label_id as label_id
            FROM   tt.ticket t, tt.status s
            WHERE  t.status_id = s.id AND t.status_id IN (11,12,60,61) AND t.status_valid_until_date < SYSDATE;

        c_prefix CONSTANT VARCHAR2(64) := 'tt.util.check_ticket_status: ';

        t_rec2 t_cur_valid_date_not_null%ROWTYPE;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        FOR t_rec2 in t_cur_valid_date_not_null
            LOOP
                ticket_interface.expire_status(t_rec2.t_id, t_rec2.t_valid_until,
                                               t_rec2.t_last_change, t_rec2.t_status_id,
                                               t_rec2.s_name, t_rec2.label_id);
            END LOOP;

    END check_ticket_status;

--------------------------------------------------------------------------------
-- procedure update_status_valid_until
--------------------------------------------------------------------------------
    PROCEDURE update_status_valid_until(p_ticket_id NUMBER, p_valid_until_date DATE DEFAULT null) IS

        l_type_id NUMBER;
        l_status_id NUMBER;
        l_emergency NUMBER := NULL;
        l_handled_by_mcc NUMBER := NULL;
        v_period_15min NUMBER := 1/96;
        v_period_30min NUMBER := 1/48;
        v_period_1h NUMBER := 1/24;
        v_period_2h NUMBER := 1/12;
        v_period_4h NUMBER := 1/6;
        v_period_8h NUMBER := 1/3;
        v_period_1d NUMBER := 1;
        v_period_2d NUMBER := 2;
        v_period_4d NUMBER := 4;
        v_period_7d NUMBER := 7;
        v_period_20d NUMBER := 20;
        v_period_60d NUMBER := 60;
        v_period_to_add NUMBER := 0;
        v_valid_until_date DATE := NULL;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- get ticket type, status and emergency flag
        SELECT type_id, status_id, emergency, handled_by_mcc INTO l_type_id, l_status_id, l_emergency, l_handled_by_mcc
        FROM   tt.ticket
        WHERE  id = p_ticket_id;

        -- status deferred (60) has to be treated separately, nothing to do here
        IF (l_status_id = 60) THEN
            RETURN;
        END IF;

        -- status waiting (11) and third party (12) and waiting for sing-off (61)
        IF (l_status_id IN (11, 12, 61)) THEN
            -- for emergency tickets the default is 4h and the maximum 1d (regardless of the ticket type)
            IF (l_emergency = 1) THEN
                IF (p_valid_until_date IS NOT NULL
                    AND p_valid_until_date - SYSDATE > 0
                    AND p_valid_until_date - SYSDATE <= v_period_1d) THEN
                    v_valid_until_date := p_valid_until_date;
                    v_period_to_add := 0;
                ELSE
                    v_period_to_add := v_period_4h;
                END IF;
                -- for non-emergency tickets the default is 20d and the maximum 60d (regardless of the ticket type)
            ELSE
                IF (p_valid_until_date IS NOT NULL
                    AND p_valid_until_date - SYSDATE > 0
                    AND p_valid_until_date - SYSDATE <= v_period_60d) THEN
                    v_valid_until_date := p_valid_until_date;
                    v_period_to_add := 0;
                ELSE
                    v_period_to_add := v_period_20d;
                END IF;
            END IF;
        END IF;

        -- update status_valid_until_date with corresponding time offset (if any)
        IF (v_period_to_add > 0) THEN
            UPDATE tt.ticket t SET t.status_valid_until_date = (SYSDATE + v_period_to_add) WHERE t.id = p_ticket_id;
        ELSIF (v_valid_until_date IS NOT NULL) THEN
            UPDATE tt.ticket t SET t.status_valid_until_date = v_valid_until_date WHERE t.id = p_ticket_id;
        ELSE
            -- if it changed to a state not using the valid_until -> reset this field to NULL!
            -- otherwise it will be reset to hot! or a status hot will not be checked for the worker etc
            UPDATE tt.ticket t SET t.status_valid_until_date = NULL WHERE t.id = p_ticket_id;
        END IF;

        -- for waiting and third-party
        -- store the valid until date in the last deferral date field (used when recovering the status)
        IF (l_status_id IN (11, 12, 61)) THEN
            UPDATE tt.ticket t SET t.last_deferral_date = p_valid_until_date WHERE t.id = p_ticket_id;
        END IF;

    END update_status_valid_until;


    --------------------------------------------------------------------------------
-- procedure check_dnids_tickets_to_resolve
--------------------------------------------------------------------------------
    PROCEDURE check_dnids_tickets_to_resolve IS

        CURSOR cur_to_resolve IS
            SELECT t.id
            FROM tt.ticket t, tt.event e
            WHERE (SYSDATE - e.eventdate > 7 OR REGEXP_INSTR(e.details_public,'^DNIDS:SCAN:INFO:ALLCLEAN',1,1,0,'im') +
                                                REGEXP_INSTR(e.details_public,'^DNIPS:SLOWDOWN:ALLCLEAN',1,1,0,'im') > 0)
              -- type 5 is customer incident and status 101 is resolved
              AND e.id = t.last_public_event_id and  t.type_id = 5 and t.status_id < 101 AND e.type_id = 10020;

        rec_resolved  cur_to_resolve%ROWTYPE;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        FOR rec_resolved in cur_to_resolve
            --loop over all tickets
            LOOP
                tt.ticket_interface.change_status(rec_resolved.id,101,NULL,'Automatically resolving ticket.');
            END LOOP;


    END check_dnids_tickets_to_resolve;

    procedure despam_ticket(p_ticket_id INTEGER, p_limit INTEGER := 1000) is
      v_min INTEGER;
      v_max INTEGER;
    begin
      plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
      for t in (select type_id, count(*)
                from tt.EVENT e
                where e.TICKET_ID = p_ticket_id
                group by type_id
                having count(*) > p_limit) loop

          select min(e.id), max(e.id) into v_min, v_max
          from tt.EVENT e
          where e.TICKET_ID = p_ticket_id
            and e.TYPE_ID = t.TYPE_ID;

          delete
          from tt.EVENT e
          where e.TICKET_ID = p_ticket_id
            and e.TYPE_ID = t.TYPE_ID
            and e.id != (select t.LAST_PUBLIC_EVENT_ID from tt.TICKET t where t.id = e.TICKET_ID)
            and e.id != v_min
            and e.id != v_max
            and not exists (select 1 from mc.ISP_LINK_HISTORY lh where lh.EVENT_ID = e.ID)
          ;
        end loop;
    end;

-- -----------------------------------------------------------------
--  procedure close_old_dev_tickets
-- -----------------------------------------------------------------

    PROCEDURE close_old_dev_tickets IS
        PRAGMA AUTONOMOUS_TRANSACTION;
        CURSOR c IS
          SELECT t.ID
          FROM tt.ticket t
          WHERE t.HANDLED_BY_MCC = 1
            AND t.STATUS_ID NOT IN (2, 102) /* 2 open, 102 closed */
            AND t.STATUS_ID < 100 /* merged, archived, deleted etc... */
            AND t.OPEN_DATE < ( SYSDATE - 30);

        v_is_dev NUMBER;
        v_ticket_to_close  c%ROWTYPE;
    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- precondition: only run on dev instances
        SELECT count(*) into v_is_dev FROM V$INSTANCE WHERE HOST_NAME LIKE '%-dev-%';
        if v_is_dev = 0 THEN
            -- not a dev instance, nothing to do
            ROLLBACK;
            RETURN;
        END IF;

        -- close old tickets
        FOR v_ticket_to_close IN c
            LOOP
                tt.ticket_interface.change_status(v_ticket_to_close.ID, 102, null, 'Automatically closed after 30 days');
                COMMIT;
        END LOOP;

        -- despam tickets with many events
        FOR r in (select e.TICKET_ID, count(*)
                  from tt.event e
                  group by e.TICKET_ID
                  having count(*) > 5000
                  order by e.TICKET_ID desc) LOOP
            despam_ticket(r.TICKET_ID, 100);
            COMMIT;
        END LOOP;
    end close_old_dev_tickets;
END util;
/
