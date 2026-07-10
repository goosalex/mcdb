--liquibase formatted sql logicalFilePath:pkgb/tt_escalation_interface.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE BODY tt.escalation_interface IS
------------------------------------------------------------------------------------------------------------------------------------
-- escalate_os
--
-- this procedure is called from an event that is potentialy escalated
-- we get the ticket from the event table and then we check if we need to escalate the ticket.
-- By default the ticket is escalated.
-- The ticket is not escalated if the host is inactive, that means if mss.host.active is 0.
------------------------------------------------------------------------------------------------------------------------------------
    PROCEDURE escalate_os(p_event_id NUMBER) AS

        v_company_id NUMBER;
        v_host_id NUMBER;
        v_ticket_id NUMBER;
        v_host_active NUMBER;
        v_escalation_status_id NUMBER;
        v_event_id NUMBER;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        plog.debug('escalate_to_os called for event id ' || p_event_id);

        BEGIN
            -- get the ticket id for the event
            SELECT e.ticket_id into v_ticket_id
            FROM tt.event e
            WHERE e.id = p_event_id;

            -- get the escalation status from the ticket
            SELECT escalation_status_id INTO v_escalation_status_id FROM ticket WHERE id = v_ticket_id;

            -- get the host id from the ticket
            SELECT t.host_id into v_host_id
            FROM tt.ticket t
            WHERE t.id = v_ticket_id;

            -- see if we realy need escalation
            -- check if the host is active
            SELECT h.active INTO v_host_active
            FROM mss.host h
            WHERE h.id = v_host_id;

        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_host_id := NULL;
        END;

        plog.debug('ticket id is ' || v_ticket_id);
        plog.debug('host id is ' || v_host_id);

        -- if the ticket is already in an escalation to os
        -- we don't do anything
        IF (v_escalation_status_id IN (10,11)) THEN
            RETURN;
        END IF;

        -- if no host was specified we need escalation anyway
        IF (v_host_active = 1 OR v_host_id IS null) THEN
            plog.debug('escalate ticket ' || v_ticket_id);

            -- update escalation status and date of ticket
            -- escalation_status_id 10 means escalation to os
            UPDATE tt.ticket SET escalation_status_id = 10, last_escalation_date = sysdate WHERE id = v_ticket_id;

            -- insert the escalation event
            event_interface.addevent_new(v_event_id,
                                         v_ticket_id,
                                         60001,
                                         v_host_id,
                                         'Starting escalation to Open Systems Mission Control',
                                         'Event added by tt.escalation_interface.escalate_os. Caused by event '||p_event_id);

        END IF;

    END escalate_os;



------------------------------------------------------------------------------------------------------------------------------------
-- escalate_customer
-- this procedure adds an "escalation to customer" (60101) event to the ticket.
-- this is only done during off hours, during office hours OSAG is escalated
------------------------------------------------------------------------------------------------------------------------------------
    PROCEDURE escalate_customer(p_event_id NUMBER) AS

        v_ticket_id NUMBER;
        v_host_id NUMBER;
        v_host_active NUMBER;
        v_escalation_status_id NUMBER;
        v_event_id NUMBER;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        BEGIN
            -- get the ticket id for the event
            SELECT e.ticket_id into v_ticket_id
            FROM tt.event e
            WHERE e.id = p_event_id;

            -- get the escalation status of the ticket
            -- get the host id from the ticket
            SELECT t.escalation_status_id, t.host_id INTO v_escalation_status_id, v_host_id
            FROM tt.ticket t
            WHERE t.id = v_ticket_id;

            -- see if we realy need escalation
            -- check if the host is active
            SELECT h.active INTO v_host_active
            FROM mss.host h
            WHERE h.id = v_host_id;

        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_host_id := NULL;
        END;

        -- we only escalate to a customer if there is
        -- no other escalation in process
        IF (v_escalation_status_id <> 0) THEN
            RETURN;
        END IF;

        -- if no host was specified we need escalation anyway
        IF (v_host_active = 1 OR v_host_id IS null) THEN
            UPDATE tt.ticket SET escalation_status_id = 10, last_escalation_date = SYSDATE WHERE ticket.id = v_ticket_id AND escalation_status_id <> 10;

            -- if we really changed the status, insert an event
            IF (SQL%ROWCOUNT > 0) THEN
                event_interface.addevent_new(v_event_id, v_ticket_id,
                                             60001,
                                             v_host_id,
                                             'Starting escalation to Open Systems Mission Control',
                                             'Event added by tt.escalation_interface.escalate_customer. Caused by event '||p_event_id);

            END IF;
        END IF;
    END escalate_customer;


------------------------------------------------------------------------------------------------------------------------------------
-- escalate_isp_outage_to_os
------------------------------------------------------------------------------------------------------------------------------------

    PROCEDURE escalate_isp_outage_to_os(p_event_id NUMBER) AS


        c_prefix CONSTANT VARCHAR2(64) := 'tt.escalation_interface.escalate_isp_outage_to_os(): ';

        v_host_name VARCHAR2(32);
        v_company_short VARCHAR2(10);
        v_public_details VARCHAR2(300);
        v_private_details VARCHAR2(400);
        v_org_event_date DATE;
        v_ticket_id NUMBER;
        v_event_id NUMBER;
    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        BEGIN
            -- get host name, company, ticket id
            -- company on event or ticket may be null, fall back to host
            SELECT h.name, COALESCE(ec.short, tc.SHORT, sc.SHORT), t.id
            INTO v_host_name, v_company_short, v_ticket_id
            FROM tt.event e, tt.ticket t, mss.host h, stop.company ec, stop.company sc, stop.company tc
            WHERE e.id = p_event_id
              AND e.TICKET_ID = t.ID
              AND h.id = NVL(e.host_id, t.HOST_ID)
              AND e.COMPANY_ID = ec.ID(+)
              AND t.COMPANY_ID = tc.ID(+)
              AND h.SERVICE_COMPANY_ID = sc.ID;

        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                plog.err(c_prefix || 'either ticket, host or company not found for event with id: ' || p_event_id ||' This is needed for escalation. Aborting escalation.');
                RETURN;
            WHEN OTHERS THEN
                plog.err(c_prefix || 'Error while retrieving company and host name for event with id: '|| p_event_id ||' This is needed for escalation. Aborting escalation.');
                RETURN;
        END;

        SELECT eventdate INTO v_org_event_date FROM event where id = p_event_id;

        v_public_details := 'Critical ISP Outage escalation'||CHR(10)
            ||'Host: '||v_host_name||CHR(10)
            ||'Company: '||v_company_short||CHR(10)
            ||'Time of original event: '||TO_CHAR(v_org_event_date, 'YYYY-MM-DD HH24:MI:SS')||CHR(10)
            ||'Original ticket '|| v_ticket_id;

        v_private_details :=  'To Do:'||CHR(10)
            ||'https://open-systems.atlassian.net/wiki/x/3xYBAQ'||CHR(10)||CHR(10)
            ||'Do not add any further events to this escalation ticket.'||CHR(10)
            ||'Use the original ticket ' || v_ticket_id || ' for tracking any work!'||CHR(10)
            ||'This ticket is intentionally hidden from the customer, so do not merge it. ';

        -- create trouble ticket (type id 1) with incident report event (id 30005)
        -- Note: this ticket does not have the company set to hide it from the customer
        -- set service component to 27 (other)
        tt.ticket_interface.newticket_new(v_ticket_id, v_event_id,
                                          1,'Critical ISP Outage escalation',
                                          30005,NULL,v_public_details, v_private_details, NULL, NULL, TRUE, SYSDATE, NULL, 27 );

    END escalate_isp_outage_to_os;

------------------------------------------------------------------------------------------------------------------------------------
-- nop (no operation)
------------------------------------------------------------------------------------------------------------------------------------
    PROCEDURE nop(p_event_id NUMBER) AS
    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- do nothing
        NULL;
    END nop;

    PROCEDURE clear_customer_escalation(p_ticket_id tt.ticket.id%TYPE) AS
    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- clear the escalation status if it's set to customer escalation (20)
        UPDATE tt.ticket SET escalation_status_id = 0 WHERE id = p_ticket_id AND escalation_status_id = 20;
    END clear_customer_escalation;

END escalation_interface;
/
