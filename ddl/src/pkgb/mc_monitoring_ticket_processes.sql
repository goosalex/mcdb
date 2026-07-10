--liquibase formatted sql logicalFilePath:pkgb/mc_monitoring_ticket_processes.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE BODY mc.monitoring_ticket_processes IS

-------------------------------------------------------------------------------
-- resolve_isp_ticket: auto resolve ISP outages ( ie. no WAN management)
-- *** SPECIAL CASE ***
--
-- parameter: p_ticket_id
-- return;    -
-------------------------------------------------------------------------------
    PROCEDURE resolve_isp_ticket(
        p_ticket_id tt.event.ticket_id%TYPE
    ) IS

        S_PREFIX CONSTANT VARCHAR2(32) := 'resolve_isp_ticket(): ';
        v_subject_changed NUMBER;
        v_ticket_subject  VARCHAR2(2000);
        v_isp_down_date   DATE;
        v_isp_up_date     DATE;
        v_isp_outages_cnt NUMBER;
        v_duration        NUMBER;

    BEGIN
        -- check whether we want to update the subject
        -- in case there is a manual subject change event
        -- in the ticket, we don't want to change it
        -- contact is set (ticket attribute change not automatically done)
        SELECT COUNT(*) INTO v_subject_changed FROM tt.event e
        WHERE e.type_id = mc.monitoring_state.EVENT_TYPE_ATTR_CHG AND e.details_public LIKE 'ticket subject changed:%'
          AND e.ticket_id = p_ticket_id AND e.contact_id IS NOT NULL;
        IF (v_subject_changed = 0 ) THEN
            -- get number of outages
            -- as well as the first down date and the latest up date
            -- for outages in this ticket
            SELECT COUNT(*), MIN(cic.down_date), MAX(cic.up_date)
            INTO v_isp_outages_cnt, v_isp_down_date, v_isp_up_date
            FROM connection_interrupt_closed cic, tt.event e
            WHERE e.ticket_id = p_ticket_id
              AND e.id = cic.event_id
              AND cic.type_id IN (mc.monitoring_state.STATE_ISP,mc.monitoring_state.STATE_ISP_SW);

            v_duration := ROUND((v_isp_up_date - v_isp_down_date) *24*60);

            -- single outage
            IF (v_isp_outages_cnt = 1) THEN
                v_ticket_subject := 'ISP outage for '||v_duration||' minutes';
            ELSE
                -- several outages
                -- withing 3 hours
                IF (v_duration < 180) THEN
                    v_ticket_subject := v_isp_outages_cnt || ' ISP outages within ' || v_duration || ' minute';
                ELSIF (v_duration < 24*60) THEN
                    -- within one day
                    v_duration := ROUND(v_duration/60);
                    v_ticket_subject := v_isp_outages_cnt || ' ISP outages within '||v_duration||' hour';
                ELSE
                    -- within more than one day
                    v_duration := ROUND(v_duration/(24*60));
                    v_ticket_subject := v_isp_outages_cnt || ' ISP outages within '||v_duration||' day';
                END IF;

                -- fixing plural stuff
                IF (v_duration > 1) THEN
                    v_ticket_subject := v_ticket_subject || 's';
                END IF;
            END IF;
            tt.ticket_interface.change_subject(p_ticket_id,v_ticket_subject, NULL);
        END IF;
        tt.ticket_interface.change_status(p_ticket_id, mc.monitoring_state.TICKET_STATUS_RESOLVED, NULL,'automatic resolve of ISP outage ticket');

    END resolve_isp_ticket;

-------------------------------------------------------------------------------
-- new_event_up: trigger a new "connection UP" ticket event,
--               add it to an existing ticket or open new ticket.
--               This is a wrapper for tt.new_event().
--
-- parameter: p_host_id, the host_id to which the event refers to
--            p_mode, the mode of the state machine (active, inactive, SW)
--            p_event_id, the ID of the last event for this interrupt (if any)
-------------------------------------------------------------------------------
    PROCEDURE new_event_up(
        p_host_id     mss.host.id%TYPE,
        p_mode        NUMBER,
        p_event_id    tt.event.id%TYPE DEFAULT NULL
    ) IS

        S_PREFIX CONSTANT VARCHAR2(32) := 'new_event_up(): ';
        S_SANG_STATUS     NUMBER       := mc.monitoring_state.SANG_UP;
        v_private               VARCHAR2(256) := NULL;
        v_event_details         connection_interrupt_open.details%TYPE;
        v_event_type            tt.event.type_id%TYPE;
        v_ticket_id             tt.ticket.id%TYPE := NULL;
        v_ticket_type_id        tt.ticket.type_id%TYPE;
        v_ticket_event_type_id  tt.event.type_id%TYPE;
        v_event_id              tt.event.id%TYPE;
        --- TEMPORARY SRE CHANGE
        v_bypass                NUMBER;

    BEGIN
        v_event_type    := mc.monitoring_state.EVENT_TYPE_UP;
        v_private       := NULL;
        v_event_details := 'service is up again';


        -- Alerts handled via the Thanos route (#sre-team)
        return;

        -- get ticket_id of last connection down/isp if there has been an event
        IF ( p_event_id IS NOT NULL ) THEN
            BEGIN
                SELECT t.id, t.type_id INTO v_ticket_id, v_ticket_type_id
                FROM tt.ticket t, tt.event e
                WHERE t.id = e.ticket_id AND e.id = p_event_id
                  AND (t.status_id < mc.monitoring_state.TICKET_STATUS_CLOSED OR t.status_id = mc.monitoring_state.TICKET_STATUS_MERGED);

            EXCEPTION
                WHEN no_data_found THEN
                    v_ticket_id := NULL;
            END;
        END IF;

        -- ------------
        -- ADD EVENT
        -- ------------
        -- UP events should only be triggered if a ticket has been found
        IF ( v_ticket_id IS NOT NULL ) THEN
            tt.event_interface.addevent_new(v_event_id, v_ticket_id, v_event_type, p_host_id, v_event_details,
                                            NULL, NULL, TRUE, SYSDATE, TRUE);
            -- clear escalation status
            tt.escalation_interface.clear_customer_escalation(v_ticket_id);
            tt.ticket_interface.change_status(v_ticket_id,mc.monitoring_state.TICKET_STATUS_HOT,NULL,NULL);

            -- *** SPECIAL CASE new_event_3  ***
            -- If this was an ISP outage, and an existing ticket for this service is of
            -- type 'isp outage', then resolve the ticket so the poor guy in mission
            -- control has less work!!!
            IF ( v_ticket_type_id = 4 ) THEN
                resolve_isp_ticket(v_ticket_id);
            END IF;
            RETURN;
            -- *** END SPECIAL CASE new_event_3  ***
        ELSE
            -- service is UP, there was a down or isp event
            -- the old ticket is no longer valid, therefore the ticket id is null
            v_event_id := NULL;
            RETURN; -- no ticket found, return without event
        END IF;

        -- --------------
        -- call NEW event
        -- --------------
        BEGIN
            -- if its a service down event during the service window, the event wont be escalated by newevent
            -- set service compomnent to 1 (sdp)
            tt.event_interface.newevent_new(v_event_id, v_event_type, p_host_id, v_event_details, v_private, NULL, TRUE, SYSDATE, NULL, 1);
        EXCEPTION
            WHEN OTHERS THEN
                plog.err(S_PREFIX||'newevent_new raised exception: '||sqlerrm);
        END;

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);

    END new_event_up;

-------------------------------------------------------------------------------
-- new_event_down_or_isp: trigger a new ticket event for a broken connection,
--                        add it to an existing ticket or open new ticket.
--                        This is a wrapper for tt.new_event().
--
-- parameter: p_host_id, the host_id to which the event refers to
--            p_sang_status, the status reported by SANG
--            p_mode, the mode of the state machine (active, inactive, SW)
--            p_event_id, the ID of the last event for this interrupt (if any)
-------------------------------------------------------------------------------
    PROCEDURE new_event_down_or_isp(
        p_host_id     mss.host.id%TYPE,
        p_sang_status NUMBER,
        p_mode        NUMBER,
        p_event_id    tt.event.id%TYPE DEFAULT NULL
    ) IS

        S_PREFIX CONSTANT VARCHAR2(32) := 'new_event_down_or_isp(): ';
        r_interrupt             connection_interrupt_open%ROWTYPE;
        v_private               VARCHAR2(256) := NULL;
        v_event_details         connection_interrupt_open.details%TYPE;
        v_event_type            tt.event.type_id%TYPE;
        v_ticket_id             tt.ticket.id%TYPE := NULL;
        v_ip_address            VARCHAR2(15);
        v_event_id              tt.event.id%TYPE;
        dbms_job_no             NUMBER;
        v_old_type              NUMBER;
        v_old_sang              NUMBER;
        v_old_mode              NUMBER;
        v_old_active            NUMBER;
        v_SW_count              NUMBER;
         --- TEMPORARY SRE CHANGE
        v_bypass                NUMBER;

    BEGIN

        -- Alerts handled via the Thanos route (#sre-team)
        return;

        IF ( p_event_id IS NOT NULL ) THEN
            -- there exists already an event id.
            -- check if the event id belongs to this event
            -- or to a different event in the past (check connection_interrupt_closed).
            -- if the event id belongs to this event id, then skip host.
            BEGIN
                -- get interrupt type_id of first event with p_event_id
                SELECT type_id,active INTO v_old_type,v_old_active
                FROM ( SELECT type_id,active
                       FROM mc.connection_interrupt_closed
                       WHERE event_id = p_event_id
                         AND host_id  = p_host_id
                       ORDER BY up_date ASC)
                WHERE rownum < 2;
                v_old_sang := mc.monitoring.get_sang_status_from_state( v_old_type );
                v_old_mode := mc.monitoring.get_mode_from_state( v_old_type );

                -- Skip event generation if the same event has already been generated.
                -- This is the case if the generated (old) event has the same SANG status
                -- as the new event at hand.
                -- Checking STATUS...
                IF ( v_old_sang = p_sang_status ) THEN
                    -- Exception: if old_mode=SW and new_mode=ACTIVE, then
                    -- we do generate a new event.
                    -- In all other cases we skip event generation.
                    -- Checking MODE...
                    IF ( v_old_mode = p_mode
                        OR v_old_mode = mc.monitoring_state.MODE_ACTIVE ) THEN
                        -- note: events during inactive modes do not reach this code
                        --   skip if old_mode=ACTIVE and new_mode=ACTIVE
                        --   skip if old_mode=ACTIVE and new_mode=SW
                        --   skip if old_mode=SW and new_mode=ACTIVE
                        RETURN;
                    END IF;
                END IF;

            EXCEPTION
                WHEN no_data_found THEN
                    -- event has already been reported
                    RETURN;
            END;

        END IF;

        IF ( p_sang_status = mc.monitoring_state.SANG_ISP ) THEN
            v_private := mc.monitoring_state.TODO_ISP_DOWN;
            v_event_type := mc.monitoring_state.EVENT_TYPE_ISP;
        ELSIF ( p_sang_status = mc.monitoring_state.SANG_DOWN ) THEN
            v_private := mc.monitoring_state.TODO_CONN_DOWN;
            v_event_type := mc.monitoring_state.EVENT_TYPE_DOWN;
        ELSE
            plog.err(S_PREFIX||'the sang state '||p_sang_status||' is not valid for this function!');
            RETURN;
        END IF;

        -- get data from open interrupt table
        SELECT * INTO r_interrupt
        FROM connection_interrupt_open
        WHERE host_id = p_host_id;

        IF ( p_mode = mc.monitoring_state.MODE_SW ) THEN
            -- silent events ( because of ServiceWindow )
            v_event_details := r_interrupt.details || CHR(10) || '(detected during service window that disables escalation)';
        ELSE
            v_event_details := r_interrupt.details;
        END IF;
        -- --------------
        -- call NEW event
        -- --------------
        BEGIN
            -- if its a service down event during the service window, the event wont be escalated by newevent
            -- set the service component to 1 (sdp)
            tt.event_interface.newevent_new(v_event_id, v_event_type, p_host_id, v_event_details, v_private, NULL, TRUE, SYSDATE, NULL, 1);
        EXCEPTION
            WHEN OTHERS THEN
                plog.err(S_PREFIX||'newevent_new raised exception: '||sqlerrm);
        END;

        -- --------------------
        -- POST event adaptions
        -- --------------------
        IF (v_event_id IS NOT NULL) THEN
            -- SANG not UP
            -- update event id in cio
            UPDATE connection_interrupt_open cio
            SET event_id = v_event_id
            WHERE cio.host_id = p_host_id;

            IF ( p_sang_status = mc.monitoring_state.SANG_ISP ) THEN
                -- update also ISP link history
                UPDATE mc.isp_link_history h
                SET h.event_id = v_event_id
                WHERE h.id IN (
                    -- returns the latest isp_link_history entries for given host, but only if down and no event yet linked
                    WITH numbered_link_history AS (
                        SELECT id, isp_link_id, new_isp_link_status_type_id, event_id, ROW_NUMBER() OVER (PARTITION BY isp_link_id ORDER BY change_date DESC) AS rn FROM mc.isp_link_history
                    )
                    SELECT
                        ilh.id
                    FROM mss.interface2isp_link il
                             JOIN mss.interface i ON il.interface_id = i.id
                             JOIN numbered_link_history ilh ON ilh.isp_link_id = il.isp_link_id AND ilh.rn = 1
                    WHERE i.host_id = p_host_id
                      AND ilh.event_id IS NULL
                      AND ilh.new_isp_link_status_type_id = 2
                );
            END IF;
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);

    END new_event_down_or_isp;

-------------------------------------------------------------------------------
-- new_event: trigger a new ticket event, add it to an existing ticket
--            or open new ticket. This is a wrapper for tt.new_event().
--
-- parameter: p_host_id, the host_id to which the event refers to
--            p_sang_status, the status reported by SANG
--            p_mode, the mode of the state machine (active, inactive, SW)
--            p_event_id, the ID of the last event for this interrupt (if any)
-- return:    -
-------------------------------------------------------------------------------
    PROCEDURE new_event(
        p_host_id     mss.host.id%TYPE,
        p_sang_status NUMBER,
        p_mode        NUMBER,
        p_event_id    tt.event.id%TYPE DEFAULT NULL
    ) IS

        S_PREFIX CONSTANT VARCHAR2(32) := 'new_event(): ';

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        IF ( p_mode = mc.monitoring_state.MODE_INACTIVE AND p_sang_status > mc.monitoring_state.SANG_UP ) THEN
            -- no events if monitoring is inactive
            -- except 'Service up' events
            RETURN;
        END IF;

        -- decide which event type should be generated
        IF ( p_sang_status = mc.monitoring_state.SANG_UP ) THEN
            new_event_up(p_host_id,p_mode,p_event_id);
        ELSIF ( p_sang_status = mc.monitoring_state.SANG_ISP OR p_sang_status = mc.monitoring_state.SANG_DOWN ) THEN
            new_event_down_or_isp(p_host_id,p_sang_status,p_mode,p_event_id);
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);

    END new_event;

END monitoring_ticket_processes;
/
