--liquibase formatted sql logicalFilePath:pkgb/ticketevolution_calculator.sql
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE BODY TICKETEVOLUTION.CALCULATOR AS
  procedure materialize_tickev(p_ticket_id tt.EVENT.ticket_id%type) is
    -- gates the creation of a record in tickev
    v_out    number(1);
    v_first_event_date DATE;
    v_last_status tt.STATUS.name%type;
    v_status tt.STATUS.name%type;
    v_emerg  varchar2(32);
    v_eng    varchar2(32);
    v_mcc    varchar2(32);
    v_ttype  tt.TICKET_TYPE.NAME%type;
    v_ttype_initial number(1);
    v_label  varchar2(32);
    v_last_event_id integer;
  begin
    -- always produce initial row
    v_out := 1;
    v_first_event_date := NULL;
    v_last_status := NULL;
    v_status := 'new';
    v_emerg := 'non-emergency';
    v_eng := '';
    v_mcc := 'MCC';
    v_ttype := '';
    v_ttype_initial := 1;
    v_label := '';
    v_last_event_id := null;

    -- use current ticket type until further information from an event
    select ty.name into v_ttype
    from tt.TICKET_TYPE ty, tt.TICKET t
    where t.ID = p_ticket_id
      and t.TYPE_ID = ty.ID;

    -- replace existing data
    update tickev set update_dt = sysdate, deleted = 1 where ticket_id = p_ticket_id and deleted = 0;

    for e in (select e.*
              from tt.EVENT e
              where e.TICKET_ID = p_ticket_id
              AND e.ORG_TICKET_ID IS NULL
              order by e.db_date, e.id) loop
        IF v_first_event_date is null
        THEN
          v_first_event_date := e.DB_DATE;
        end if;
        -- 101002	status change: open
        -- 101003	status change: hot
        -- 101004	status change: acknowledged
        -- 101011	status change: waiting
        -- 101012	status change: third party
        -- 101060	status change: deferred
        -- 101061	status change: waiting for sign-off
        -- 101101	status change: resolved
        -- 101102	status change: closed
        -- 101110	status change: merged
        -- 101120	status change: deleted
        -- 100004 ticket merged

        -- Status change
        IF
          (e.TYPE_ID in (101002, 101003, 101101, 101102,  101060, 101004, 101011, 101012, 101061, 101110, 101120) and e.DETAILS_PUBLIC like 'New status: %')
            OR
          (e.TYPE_ID IN (100004))
        THEN
          -- There are two types of merged ticket workflows:
          -- 1. tickets with event ‘ticket merged’ (event type id 100004) and additional separate event noting status change ‘status change: merged’ (event type id 101110)
          IF e.TYPE_ID in (101002, 101003, 101101, 101102,  101060, 101004, 101011, 101012, 101061, 101110, 101120)
          THEN
            v_status := REGEXP_SUBSTR(e.DETAILS_PUBLIC, '^New status: (.+)$', 1, 1, 'm', 1); -- returns e.g. 'open'
          -- 2. tickets with only event ‘ticket merged’ (event type id 100004), without separate event noting status change
          ELSIF e.TYPE_ID IN (100004)
          THEN
            v_status := 'merged';
          END IF;

          IF v_status != v_last_status
          THEN
            v_out := 1;
          END IF;


        -- Engineer change
        ELSIF e.TYPE_ID = 100003 and e.DETAILS_PRIVATE like 'Engineer changed to:%'
        THEN  -- 100003 ticket attribute change. e.g.: "Engineer changed to: jho (non-MCC). Was: jho (MCC)."
            -- select the first "jho"
          v_eng := REGEXP_SUBSTR(e.DETAILS_PRIVATE, '^Engineer changed to: ([^ .]+)', 1, 1, '', 1);
            -- select the first MCC status "non-MCC"
          v_mcc := REGEXP_SUBSTR(e.DETAILS_PRIVATE, '^Engineer changed to: [^ ]+ \(((non-)?MCC)\)', 1, 1, '', 1);

          -- MCC change
          IF v_eng = 'MCC'
          THEN
            v_eng := '';
            v_mcc := 'MCC';
          end IF;
          v_out := 1;


        -- Emergency change
        ELSIF e.TYPE_ID = 100003 and e.DETAILS_PUBLIC like '%emergency%'
        THEN -- 100003 ticket attribute CHANGE
          IF e.DETAILS_PUBLIC like 'ticket changed to emergency'
          THEN
            IF v_status = 'new' and v_emerg = 'non-emergency'
            THEN
              -- 60s margin for setting emergency flag on a new ticket
              update tickev set emergency_state = 'emergency', update_dt = sysdate
              where ticket_id = e.ticket_id
                and deleted = 0
                and emergency_state = 'non-emergency'
                and e.eventdate < date_from + 60;
              IF SQL%ROWCOUNT = 0
              THEN
                -- nothing to update, so create the event
                v_out := 1;
              end if;
            ELSE
              v_out := 1;
            END IF;
            v_emerg := 'emergency';
          ELSIF e.DETAILS_PUBLIC like 'ticket changed to non-emergency'
          THEN
            v_emerg := 'non-emergency';
            v_out := 1;
          END IF;


        -- Queue change
        ELSIF e.TYPE_ID = 100003 and e.DETAILS_PRIVATE like 'Ticket label %'
        THEN -- 100003 ticket attribute CHANGE
          IF e.DETAILS_PRIVATE like 'Ticket label % added'
          THEN
            v_label := REGEXP_SUBSTR(e.DETAILS_PRIVATE, '^Ticket label ([^ ]+) added', 1, 1, '', 1); -- returns e.g. 'Dispatch'
          ELSIF e.DETAILS_PRIVATE like 'Ticket label changed to %'
          THEN
            v_label := REGEXP_SUBSTR(e.DETAILS_PRIVATE, '^Ticket label changed to ([^ ]+)', 1, 1, '', 1); -- returns e.g. 'Dispatch'
          ELSIF e.DETAILS_PRIVATE like 'Ticket label removed %'
          THEN
            v_label := NULL; -- returns e.g. 'Dispatch'
          END IF;
          v_out := 1;

        -- Ticket Type change
        ELSIF e.TYPE_ID = 100005 and e.DETAILS_PUBLIC like 'type changed from %'
        THEN -- 100005 ticket type changed
          IF v_ttype_initial = 1
          THEN
            -- update existing tickev records
            v_ttype := REGEXP_SUBSTR(e.DETAILS_PUBLIC, '^type changed from ([a-z ]+) to ([a-z ]+)$', 1, 1, '', 1);
            update tickev set ticket_type = v_ttype, update_dt = sysdate where ticket_id = e.ticket_id and deleted = 0;
            v_ttype_initial := 0;
          end IF;
          v_ttype := REGEXP_SUBSTR(e.DETAILS_PUBLIC, '^type changed from ([a-z ]+) to ([a-z ]+)$', 1, 1, '', 2);
          v_out := 1;
        end IF;

        IF v_out = 1
        THEN
          IF v_last_status is null and v_status != 'new'
          THEN
              insert into tickev(EVENT_ID, TICKET_ID, TICKET_STATUS, EMERGENCY_STATE, ASSIGNED_ENGINEER, MCC_STATE, TICKET_TYPE, TICKET_LABEL, DATE_FROM, DATE_TO, update_dt, TICKET_STATUS_ID)
              values (e.ID, e.TICKET_ID, 'new', v_emerg, '', v_mcc, v_ttype, v_label, v_first_event_date, e.DB_DATE, sysdate, (select min(ID) from TT.STATUS WHERE NAME = 'new'));
          end if;

          IF v_last_event_id is not null
          THEN
            update tickev
            set date_to = e.DB_DATE, update_dt = sysdate
            where ticket_id = p_ticket_id
              and event_id = v_last_event_id
              and deleted = 0;
          end IF;

          insert into tickev(EVENT_ID, TICKET_ID, TICKET_STATUS, EMERGENCY_STATE, ASSIGNED_ENGINEER, MCC_STATE, TICKET_TYPE, TICKET_LABEL, DATE_FROM, DATE_TO, update_dt, TICKET_STATUS_ID)
          values (e.ID, e.TICKET_ID, v_status, v_emerg, v_eng, v_mcc, v_ttype, v_label, e.DB_DATE, e.DB_DATE, sysdate, (select min(ID) from TT.STATUS WHERE NAME = v_status));
          v_last_event_id := e.ID;
          v_last_status := v_status;
          v_out := 0;
        end IF;


      end loop;
  end;

  procedure materialize_incremental is
    v_last_run date;
    v_this_run date;
  begin
     v_this_run := sysdate;
     begin
       select value_dt into v_last_run from state where key = 'LAST_RUN';
     exception
       when no_data_found then
          v_last_run := sysdate-365;
          insert into state (key, value_dt) values ('LAST_RUN', v_last_run);
          commit;
     end;

     for r in (select t.id
              from tt.TICKET t
              where cast(UPDATE_TIMESTAMP as date) > v_last_run) loop
       materialize_tickev(r.id);
       commit;
     end loop;

     update state set value_dt = v_this_run where key = 'LAST_RUN';
     commit;
  end;

END CALCULATOR;
/
