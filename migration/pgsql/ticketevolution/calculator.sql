-- migration/pgsql/ticketevolution/calculator.sql
--
-- Translation of TICKETEVOLUTION.CALCULATOR (spec: migration/spec/ticketevolution.calculator.md;
-- Oracle body: ddl/src/pkgb/ticketevolution_calculator.sql, 214 lines). Names copied
-- verbatim from migration/mapping/name-map.csv's 2 TICKETEVOLUTION.CALCULATOR rows, both
-- pg_kind=procedure. No private routines, no plog calls, no package state.
--
-- Unqualified `tickev` / `state` in the Oracle body resolve to the package owner's schema;
-- written fully qualified here (ticketevolution.tickev / ticketevolution.state).
--
-- Conventions: NUMBER -> numeric, DATE -> timestamp, SYSDATE -> statement_timestamp(),
-- REGEXP_SUBSTR(x, pat, 1, 1, flags, n) -> (regexp_match(x, pat, flags))[n] (Oracle's 'm'
-- flag -- ^/$ at line boundaries while '.' still stops at a newline -- is PostgreSQL's 'n'),
-- SQL%ROWCOUNT -> GET DIAGNOSTICS, Oracle '' -> explicit NULL (S-TICKEV-016: Oracle's ''/NULL
-- collapsing means the Oracle rows hold NULL, so NULL here is the faithful translation, not a
-- deviation).
--
-- Two sites are marked DEVIATION(ORACLE-BUG) -- see calculator.FINDINGS.md "Deviations from
-- Oracle" and the corrected spec clauses S-TICKEV-009 / S-TICKEV-011.

-- ------------------------------------------------------------------------------------
-- materialize_tickev (S-TICKEV-001..017): no COMMIT, no handler -- the type lookup's
-- NO_DATA_FOUND (STRICT, P0002) propagates exactly as Oracle's unhandled ORA-01403.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE ticketevolution.calculator_materialize_tickev(p_ticket_id numeric)
LANGUAGE plpgsql
AS $fn$
DECLARE
    -- gates the creation of a record in tickev
    v_out              integer;
    v_first_event_date timestamp;
    v_last_status      varchar(32);   -- tt.status.name%TYPE
    v_status           varchar(32);
    v_emerg            varchar(32);
    v_eng              varchar(32);
    v_mcc              varchar(32);
    v_ttype            varchar(32);   -- tt.ticket_type.name%TYPE
    v_ttype_initial    integer;
    v_label            varchar(32);
    v_last_event_id    numeric;
    v_rows             integer;
    ev                 RECORD;
BEGIN
    -- always produce initial row (S-TICKEV-004)
    v_out := 1;
    v_first_event_date := NULL;
    v_last_status := NULL;
    v_status := 'new';
    v_emerg := 'non-emergency';
    v_eng := NULL;              -- Oracle: v_eng := ''  (S-TICKEV-016)
    v_mcc := 'MCC';
    v_ttype := NULL;            -- Oracle: v_ttype := '' (dead: overwritten below)
    v_ttype_initial := 1;
    v_label := NULL;            -- Oracle: v_label := '' (S-TICKEV-016)
    v_last_event_id := NULL;

    -- use current ticket type until further information from an event (S-TICKEV-001)
    SELECT ty.name INTO STRICT v_ttype
    FROM tt.ticket_type ty, tt.ticket t
    WHERE t.id = p_ticket_id
      AND t.type_id = ty.id;

    -- replace existing data (S-TICKEV-002)
    UPDATE ticketevolution.tickev
    SET update_dt = statement_timestamp(), deleted = 1
    WHERE ticket_id = p_ticket_id AND deleted = 0;

    -- S-TICKEV-003
    FOR ev IN
        SELECT *
        FROM tt.event
        WHERE ticket_id = p_ticket_id
          AND org_ticket_id IS NULL
        ORDER BY db_date, id
    LOOP
        IF v_first_event_date IS NULL THEN
            v_first_event_date := ev.db_date;
        END IF;

        -- Status change (S-TICKEV-006) / ticket merged (S-TICKEV-007)
        IF (ev.type_id IN (101002, 101003, 101101, 101102, 101060, 101004, 101011, 101012, 101061, 101110, 101120)
            AND ev.details_public LIKE 'New status: %')
           OR ev.type_id IN (100004)
        THEN
            IF ev.type_id IN (101002, 101003, 101101, 101102, 101060, 101004, 101011, 101012, 101061, 101110, 101120) THEN
                -- Oracle REGEXP_SUBSTR(..., 1, 1, 'm', 1): first line's remainder, e.g. 'open'
                v_status := (regexp_match(ev.details_public, '^New status: (.+)$', 'n'))[1];
            ELSIF ev.type_id IN (100004) THEN
                v_status := 'merged';
            END IF;

            -- NULL-unsafe in Oracle exactly as here (spec Checklist 1): only matters before the
            -- first emitted row, where v_out is already 1.
            IF v_status != v_last_status THEN
                v_out := 1;
            END IF;

        -- Engineer change (S-TICKEV-010)
        ELSIF ev.type_id = 100003 AND ev.details_private LIKE 'Engineer changed to:%' THEN
            -- e.g. "Engineer changed to: jho (non-MCC). Was: jho (MCC)." -> 'jho' / 'non-MCC'
            v_eng := (regexp_match(ev.details_private, '^Engineer changed to: ([^ .]+)'))[1];
            v_mcc := (regexp_match(ev.details_private, '^Engineer changed to: [^ ]+ \(((non-)?MCC)\)'))[1];

            -- MCC change
            IF v_eng = 'MCC' THEN
                v_eng := NULL;      -- Oracle: v_eng := '' (S-TICKEV-016)
                v_mcc := 'MCC';
            END IF;
            v_out := 1;

        -- Emergency change (S-TICKEV-011..013)
        ELSIF ev.type_id = 100003 AND ev.details_public LIKE '%emergency%' THEN
            IF ev.details_public LIKE 'ticket changed to emergency' THEN
                IF v_status = 'new' AND v_emerg = 'non-emergency' THEN
                    -- 60s margin for setting emergency flag on a new ticket (S-TICKEV-011)
                    -- DEVIATION(ORACLE-BUG): Oracle reads `e.eventdate < date_from + 60`, which in
                    -- Oracle DATE arithmetic is +60 DAYS; the inline comment states 60 seconds,
                    -- and 60 days would make the SQL%ROWCOUNT = 0 branch below dead in practice.
                    -- The stated intent (60 seconds) is implemented. See FINDINGS.
                    UPDATE ticketevolution.tickev
                    SET emergency_state = 'emergency', update_dt = statement_timestamp()
                    WHERE ticket_id = ev.ticket_id
                      AND deleted = 0
                      AND emergency_state = 'non-emergency'
                      AND ev.eventdate < date_from + interval '60 seconds';
                    GET DIAGNOSTICS v_rows = ROW_COUNT;
                    IF v_rows = 0 THEN
                        -- nothing to update, so create the event
                        v_out := 1;
                    END IF;
                ELSE
                    v_out := 1;                                          -- S-TICKEV-012
                END IF;
                v_emerg := 'emergency';
            ELSIF ev.details_public LIKE 'ticket changed to non-emergency' THEN   -- S-TICKEV-013
                v_emerg := 'non-emergency';
                v_out := 1;
            END IF;

        -- Queue change (S-TICKEV-014)
        ELSIF ev.type_id = 100003 AND ev.details_private LIKE 'Ticket label %' THEN
            IF ev.details_private LIKE 'Ticket label % added' THEN
                v_label := (regexp_match(ev.details_private, '^Ticket label ([^ ]+) added'))[1];           -- e.g. 'Dispatch'
            ELSIF ev.details_private LIKE 'Ticket label changed to %' THEN
                v_label := (regexp_match(ev.details_private, '^Ticket label changed to ([^ ]+)'))[1];      -- e.g. 'Dispatch'
            ELSIF ev.details_private LIKE 'Ticket label removed %' THEN
                v_label := NULL;
            END IF;
            v_out := 1;

        -- Ticket Type change (S-TICKEV-015)
        ELSIF ev.type_id = 100005 AND ev.details_public LIKE 'type changed from %' THEN
            IF v_ttype_initial = 1 THEN
                -- update existing tickev records: they were seeded with the ticket's CURRENT
                -- type; the first type-change event tells what the type was before.
                v_ttype := (regexp_match(ev.details_public, '^type changed from ([a-z ]+) to ([a-z ]+)$'))[1];
                UPDATE ticketevolution.tickev
                SET ticket_type = v_ttype, update_dt = statement_timestamp()
                WHERE ticket_id = ev.ticket_id AND deleted = 0;
                v_ttype_initial := 0;
            END IF;
            v_ttype := (regexp_match(ev.details_public, '^type changed from ([a-z ]+) to ([a-z ]+)$'))[2];
            v_out := 1;
        END IF;

        IF v_out = 1 THEN
            -- pseudo 'new' row (S-TICKEV-009): first emitted row is not 'new'
            IF v_last_status IS NULL AND v_status != 'new' THEN
                INSERT INTO ticketevolution.tickev
                    (event_id, ticket_id, ticket_status, emergency_state, assigned_engineer, mcc_state,
                     ticket_type, ticket_label, date_from, date_to, update_dt, ticket_status_id)
                VALUES
                    (ev.id, ev.ticket_id, 'new', v_emerg, NULL /* Oracle '' */, v_mcc,
                     v_ttype, v_label, v_first_event_date, ev.db_date, statement_timestamp(),
                     (SELECT min(id) FROM tt.status WHERE name = 'new'));
            END IF;

            -- date chaining (S-TICKEV-008)
            IF v_last_event_id IS NOT NULL THEN
                UPDATE ticketevolution.tickev
                SET date_to = ev.db_date, update_dt = statement_timestamp()
                WHERE ticket_id = p_ticket_id
                  AND event_id = v_last_event_id
                  AND deleted = 0
                  -- DEVIATION(ORACLE-BUG): Oracle keys this update on event_id alone. The pseudo
                  -- 'new' row above shares the first event's id, so Oracle also stretches the
                  -- pseudo-row's date_to (set explicitly to the first event's db_date at insert)
                  -- to the second event's db_date, yielding two overlapping live intervals.
                  -- Restrict to the row actually emitted last: its status is v_last_status,
                  -- and the pseudo-row's 'new' is guaranteed != v_last_status by the insert
                  -- condition above. IS NOT DISTINCT FROM keeps the (degenerate) NULL-status
                  -- case behaving as Oracle does. Corrected spec clause S-TICKEV-009; see FINDINGS.
                  AND ticket_status IS NOT DISTINCT FROM v_last_status;
            END IF;

            -- S-TICKEV-005
            INSERT INTO ticketevolution.tickev
                (event_id, ticket_id, ticket_status, emergency_state, assigned_engineer, mcc_state,
                 ticket_type, ticket_label, date_from, date_to, update_dt, ticket_status_id)
            VALUES
                (ev.id, ev.ticket_id, v_status, v_emerg, v_eng, v_mcc,
                 v_ttype, v_label, ev.db_date, ev.db_date, statement_timestamp(),
                 (SELECT min(id) FROM tt.status WHERE name = v_status));
            v_last_event_id := ev.id;
            v_last_status := v_status;
            v_out := 0;
        END IF;
    END LOOP;
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- materialize_incremental (S-TICKEV-018..020): the hourly scheduled entry point. Plain
-- PROCEDURE with REAL COMMITs (same decision as tt.util_close_old_dev_tickets, option 1):
-- top-level CALL only, which is how ddl/src/jobs/ticketevolution_incremental_update.sql
-- invokes it. PL/pgSQL forbids COMMIT inside a block that has an EXCEPTION clause, so the
-- Oracle handler's insert+COMMIT (lines 197-199) is moved just after the block via a flag --
-- identical observable behaviour. Oracle DATE is whole seconds; every timestamp this
-- routine compares or stores is truncated to the second explicitly, because PostgreSQL
-- would ROUND on assignment to state.value_dt timestamp(0) (possibly into the future).
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE ticketevolution.calculator_materialize_incremental()
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_last_run   timestamp;
    v_this_run   timestamp;
    v_first_run  boolean := false;
    r            RECORD;
BEGIN
    v_this_run := date_trunc('second', statement_timestamp());   -- Oracle: SYSDATE

    BEGIN
        SELECT value_dt INTO STRICT v_last_run
        FROM ticketevolution.state
        WHERE key = 'LAST_RUN';
        -- TOO_MANY_ROWS (P0003) deliberately unhandled, as in Oracle (S-TICKEV-018)
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_first_run := true;
    END;

    IF v_first_run THEN
        v_last_run := date_trunc('second', statement_timestamp()) - interval '365 days';   -- Oracle: sysdate-365
        INSERT INTO ticketevolution.state (key, value_dt) VALUES ('LAST_RUN', v_last_run);
        COMMIT;
    END IF;

    -- S-TICKEV-019: Oracle CAST(update_timestamp AS DATE) keeps time-of-day, drops fractional
    -- seconds -> date_trunc('second', ...); strictly greater than the watermark.
    FOR r IN
        SELECT t.id
        FROM tt.ticket t
        WHERE date_trunc('second', t.update_timestamp) > v_last_run
    LOOP
        CALL ticketevolution.calculator_materialize_tickev(r.id);
        COMMIT;
    END LOOP;

    -- S-TICKEV-020: watermark = this run's START time
    UPDATE ticketevolution.state SET value_dt = v_this_run WHERE key = 'LAST_RUN';
    COMMIT;
END;
$fn$;
