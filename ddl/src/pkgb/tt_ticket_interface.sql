--liquibase formatted sql logicalFilePath:pkgb/tt_ticket_interface.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE BODY tt.ticket_interface IS
    -- $Id$

-- private procedure
    PROCEDURE add_status_change_event(event_id OUT NUMBER,
                                      p_ticket_id NUMBER,
                                      p_public_change_text VARCHAR2,
                                      p_contact_id NUMBER,
                                      p_private_change_text VARCHAR2 DEFAULT NULL,
                                      p_zitadel_contact_id NUMBER DEFAULT NULL);

-- private procedure
-- handles the status transition in change_status for tickets
-- that were deferred or get deferred
    PROCEDURE handleDeferredTransitions(p_ticket_id NUMBER,
                                        p_new_status_id NUMBER,
                                        p_cur_status_id NUMBER,
                                        p_defer_date DATE,
                                        p_contact_id NUMBER,
                                        p_zitadel_contact_id NUMBER DEFAULT NULL);

-- private procedure
-- updates the timer values of a ticket when the status changes
-- currently we collect times for open, waiting, third-party, deferred, resolved
    PROCEDURE updateTicketTimeStats(p_ticket_id NUMBER,
                                    p_cur_status_id NUMBER,
                                    p_last_status_change_date DATE);


--------------------------------------------------------------------------------
-- procedure newticket_new
--------------------------------------------------------------------------------
    PROCEDURE newticket_new(p_ticket_id OUT NUMBER,
                            p_event_id OUT NUMBER,
                            p_ticket_type_id NUMBER,
                            p_subject VARCHAR2,
                            p_event_type_id NUMBER,
                            p_host_id NUMBER,
                            p_details_public VARCHAR2,
                            p_details_private VARCHAR2 DEFAULT NULL,
                            p_contact_id NUMBER DEFAULT NULL,
                            p_worker_id NUMBER DEFAULT NULL,
                            p_public_event BOOLEAN DEFAULT TRUE,
                            p_eventdate DATE DEFAULT sysdate,
                            p_company_id NUMBER DEFAULT NULL,
                            p_service_component_id NUMBER DEFAULT NULL,
                            p_zitadel_contact_id NUMBER DEFAULT NULL) IS

        v_pub_event NUMBER;
        v_company_id NUMBER;
        v_contact_id NUMBER;
        v_event_id NUMBER;
        v_event_source_id NUMBER;
        v_confirmed NUMBER;
        v_fast_resolvable NUMBER;
        v_contact_company_id NUMBER;
        v_details_public tt.event.details_public%TYPE;
        v_details_private tt.event.details_private%TYPE;
        v_mss_service_id mss.service.id%TYPE;
        v_count NUMBER;
        v_ticket_type_id NUMBER;
        v_create_cr NUMBER;
        v_cr_id NUMBER;
        v_sign_off_sender NUMBER;
        v_sender_contact_id NUMBER;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        v_ticket_type_id := p_ticket_type_id;

        IF (p_public_event) THEN
            v_pub_event:=1;
        ELSE
            v_pub_event:=0;
        END IF;

        -- if a company is given, let's take that first
        -- Needed if providing contact_zitadel_id
        IF (p_company_id IS NOT NULL) THEN
            v_company_id := p_company_id;
        END IF;

        -- if a host is given, we get the company from the mss.host table
        -- as well as the service id (mss.service)
        IF (p_host_id is not null) THEN
            SELECT h.service_company_id INTO v_company_id
            FROM mss.host h
            WHERE h.id = p_host_id;
            SELECT h2s.service_id INTO v_mss_service_id
            FROM mss.host2service h2s
            WHERE h2s.host_id = p_host_id;

        END IF;

        -- ServiceNow sign-off senders (see the change request below) come through the tickets API with their Zitadel user ID only.
        -- Use their legacy contact like the old mail gateway did, for the ticket and event contact and the change request.
        --  260976466693466175 - ServiceNow ServiceDesk (swissre@service-now.com)
        --  260976421227212858 - ServiceNow ServiceDesk (swissreesm@service-now.com)
        --  260976444195221562 - InfoSec_ServiceDesk (Protection_Monitoring@swissre.com)
        --  249698997185305231 - ServiceNow Production Sign-Off (snow.mc.approval@partnersgroup.com)
        --  250130937734526554 - ServiceNow Test Sign-OFF (snow.mc.approval.test@partnersgroup.com)
        --  250130921494181466 - ServiceNow Develpoment Sign-OFF (snow.mc.approval.dev@partnersgroup.com)
        --  296895704029212305 - Sika Network Servicedesk Production Sign-OFF (network.servicedesk@int.sika.com)
        --  389858629131441574 - Swiss Post Cybersecurity portal (portal@swisspost-cybersecurity.ch)
        v_sign_off_sender := 0;
        IF (p_event_type_id = 30002
            AND p_zitadel_contact_id IN ('260976466693466175', '260976421227212858', '260976444195221562',
                                         '249698997185305231', '250130937734526554', '250130921494181466',
                                         '296895704029212305', '389858629131441574')) THEN
            v_sign_off_sender := 1;
        END IF;
        v_sender_contact_id := p_contact_id;
        IF (v_sender_contact_id IS NULL AND v_sign_off_sender = 1) THEN
            SELECT MAX(l.contact_id) INTO v_sender_contact_id
            FROM auth.login l
            WHERE l.oidc_zitadel_id = TO_CHAR(p_zitadel_contact_id);
        END IF;

        -- if a contact id is given we select the company_id from the contact table
        -- this overrides the company selection from the service id
        IF (v_sender_contact_id is not null) THEN
            SELECT company_id INTO v_company_id
            FROM stop.contact
            WHERE contact.id = v_sender_contact_id;
        END IF;

        -- for company wide tickets check if the given contact is a company wide
        -- admin and therefore suitable as ticket owner
        v_contact_id := v_sender_contact_id;
        IF (p_host_id is null AND v_sender_contact_id is not null) THEN
            -- role id 2 is mc_cust_admin
            SELECT count(*) INTO v_count
            FROM auth.permission p, auth.login l
            WHERE p.login_id = l.id
              AND l.contact_id = v_sender_contact_id
              AND p.role_id = 2
              AND p.company_unit_id IS NULL
              AND p.user_unit_id IS NULL
              AND p.service_id IS NULL;
            IF (v_count = 0) THEN
                -- the contact is not company wide admin, do not set the owner
                v_contact_id := NULL;
            END IF;
        END IF;

        -- if the ticket was created automatically, ticket type and service don't have to be confirmed, and the ticket is fast-resolvable
        v_confirmed := 0;
        v_fast_resolvable := 0;
        SELECT source INTO v_event_source_id FROM tt.event_type WHERE id = p_event_type_id;
        IF (v_event_source_id = 1) THEN
            v_confirmed := 1;
            v_fast_resolvable := 1;
        END IF;

        -- if the ticket was created by an OSAG engineer, nothing has to be confirmed neither
        IF (p_worker_id IS NOT NULL) THEN
            SELECT company_id INTO v_contact_company_id FROM stop.contact WHERE id = p_worker_id;
            -- OSAG company has ID 6
            IF (v_contact_company_id = 6) THEN
                v_confirmed := 1;
            END IF;
        END IF;

        -- set the OUT variable p_ticket_id and p_event_id to the current value
        SELECT ticket_sequence.NEXTVAL INTO p_ticket_id FROM dual;
        SELECT event_sequence.NEXTVAL INTO p_event_id FROM dual;

        -- replace placeholders for ticket_id and event_id in event details
        v_details_public := replace_id_placeholders(p_details_public, p_ticket_id, p_event_id);
        v_details_private := replace_id_placeholders(p_details_private, p_ticket_id, p_event_id);

        -- if ticket is opened with an incident report (30005), comment from customer (30011) or a comment by MC (50002)
        -- and public details are available
        -- prepend subject to event_details
        IF p_event_type_id IN (30005, 30011, 50002) AND v_details_public IS NOT NULL THEN
            v_details_public := p_subject || CHR(10) || CHR(10) || v_details_public;
        END IF;

        -- find out if we need to create a change request inside the newly created ticket as well (used for ServiceNOW ticketing integration).
        v_create_cr := 0;
        -- That's the case if the event type is "email_from_customer" (ID 30002) and if the sender contact is one of the well-defined ones:
        --  224019  - ServiceNow ServiceDesk (swissre@service-now.com)
        --  1150408 - ServiceNow ServiceDesk (swissreesm@service-now.com)
        --  235692  - InfoSec_ServiceDesk (Protection_Monitoring@swissre.com)
        --  371508  - SICPA Service Now (spike@service-now.com)
        --  458818  - ServiceNow Production Sign-Off (snow.mc.approval@partnersgroup.com)
        --  430183  - ServiceNow Test Sign-OFF (snow.mc.approval.test@partnersgroup.com)
        --  430181  - ServiceNow Develpoment Sign-OFF (snow.mc.approval.dev@partnersgroup.com)
        --  3598    - Sika Network Servicedesk (network.servicedesk) Production Sign-OFF (network.servicedesk@int.sika.com)
        --  796216  - PG splunk monitor Sign-off (splunk-monitoring@notification.partnersgroup.com)
        -- or if it is a sign-off sender known by Zitadel user ID (see above).
        IF (p_event_type_id = 30002
            AND (v_sender_contact_id IN (224019, 1150408, 235692, 371508, 458818, 430183, 430181, 3598, 796216)
                 OR v_sign_off_sender = 1)) THEN
            -- remember to create a CR after creating the ticket
            v_create_cr := 1;
            -- use ticket type "change" (ID 2)
            v_ticket_type_id := 2;
        END IF;

        -- open a new ticket for this event
        INSERT INTO ticket (id, type_id, contact_id, worker_id, company_id, host_id, subject, last_status_change_date,
                            mss_service_id, service_confirmed, type_confirmed, fast_resolvable, service_component_id, contact_zitadel_id,
                            worker_zitadel_id)
        VALUES (p_ticket_id,
                v_ticket_type_id,
                v_contact_id,
                p_worker_id,
                v_company_id,
                p_host_id,
                SUBSTR(p_subject, 1, 100),
                SYSDATE,
                v_mss_service_id,
                v_confirmed,
                v_confirmed,
                v_fast_resolvable,
                p_service_component_id,
                p_zitadel_contact_id,
                (SELECT oidc_zitadel_id FROM auth.login WHERE contact_id = p_worker_id));

        -- set ux timeout
        UPDATE tt.ticket SET ux_timeout_start = from_tz(cast(open_date as timestamp), 'EUROPE/ZURICH') WHERE id = p_ticket_id;
        update_ux_timeout_for_ticket(p_ticket_id, TRUE);

        -- determine contact for event
        IF (p_worker_id is not NULL) THEN
            v_contact_id := p_worker_id;
        ELSIF (v_sender_contact_id is not NULL) THEN
            v_contact_id := v_sender_contact_id;
        ELSE
            v_contact_id := NULL;
        END IF;

        -- insert the event into the event table
        INSERT INTO event
        (id,type_id,host_id,eventdate,details_public,details_private,public_event, ticket_id, contact_id, contact_zitadel_id)
        VALUES (p_event_id,
                p_event_type_id,
                p_host_id,
                p_eventdate,
                v_details_public,
                v_details_private,
                v_pub_event,
                p_ticket_id,
                v_contact_id,
                p_zitadel_contact_id);

        -- if the event is public and not of source notification (2) or history (10), remember it as the last public event of the ticket
        IF (v_pub_event > 0 AND v_event_source_id NOT IN (2, 10)) THEN
            UPDATE tt.ticket SET last_public_event_id = p_event_id WHERE id = p_ticket_id;
        END IF;

        -- if the event is public and not of source notification (2), automatic (1), escalation (6), or history (10)
        -- set the counter for the summary enforcement to 1
        IF (v_pub_event > 0 AND v_event_source_id NOT IN (1,2,6,10)) THEN
            UPDATE tt.ticket
            SET summary_relevant_events_count = 1,
                todo_relevant_events_count = 1
            WHERE id = p_ticket_id;
        END IF;

        -- notify the event
        TT.OSAG_NOTIFY.event_notify(p_event_id, p_ticket_id);

        -- add a history event to the ticket (event type is 'new ticket', 101001)
        tt.event_interface.add_history_event(v_event_id,
                                             p_ticket_id,
                                             101001,
                                             p_host_id,
                                             v_company_id,
                                             'New ticket created',
                                             NULL,
                                             TRUE, -- yes, it is a public event
                                             SYSDATE,
                                             v_contact_id,
                                             p_zitadel_contact_id);

        -- execute the event type actions
        event_interface.exec_event_type_actions(p_event_id);

        -- create the change request if needed
        IF (v_create_cr = 1) THEN
            SELECT changerequest_seq.NEXTVAL INTO v_cr_id FROM dual;

            -- for now, all of those email requests will lead to a pre-approved CR. We're not checking the flag that defines on company level if requester needs to be != approver
            INSERT INTO change_request (id, change_request_state_id, description, requester_id, approver_id, creation_date, approval_denial_date, ticket_id, requester_zitadel_id, approver_zitadel_id)
            VALUES (v_cr_id,
                    3, -- status "approved"
                    v_details_public, -- copy of the email body text
                    v_contact_id, -- requester
                    v_contact_id, -- approver: same as requester
                    SYSTIMESTAMP,
                    SYSTIMESTAMP,
                    p_ticket_id,
                    p_zitadel_contact_id,
                    p_zitadel_contact_id);
        END IF;

        updateTicketFlow(p_ticket_id);

    END newticket_new;


--------------------------------------------------------------------------------
-- procedure change_deferral_date
--------------------------------------------------------------------------------
    PROCEDURE change_deferral_date(p_ticket_id NUMBER,
                                   p_contact_id NUMBER,
                                   p_defer_date DATE,
                                   p_details_public tt.event.details_public%TYPE,
                                   p_zitadel_contact_id NUMBER DEFAULT NULL) IS

        v_host_id NUMBER;
        v_ticket_status_id NUMBER;
        v_event_id NUMBER;
    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        SELECT status_id INTO v_ticket_status_id
        FROM tt.ticket t
        WHERE t.id = p_ticket_id;

        -- only change deferral date if ticket is deferred (id = 60)
        IF (v_ticket_status_id = 60) THEN
            SELECT t.host_id INTO v_host_id
            FROM tt.ticket t
            WHERE t.id = p_ticket_id;

            UPDATE tt.ticket t
            SET t.status_valid_until_date = p_defer_date, t.last_deferral_date = p_defer_date
            WHERE t.id = p_ticket_id;

            event_interface.addevent_new(v_event_id, p_ticket_id, 100003, v_host_id, p_details_public, NULL, p_contact_id, TRUE, sysdate, FALSE,p_zitadel_contact_id);
        ELSE
            plog.warning('tt.ticket_interface.change_deferral_date: called for ticket ' || p_ticket_id || ' but it is not deferred. status id: ' || v_ticket_status_id);
        END IF;

    END change_deferral_date;


--------------------------------------------------------------------------------
-- procedure change_status
--------------------------------------------------------------------------------
    PROCEDURE change_status(p_ticket_id NUMBER,
                            p_status_id NUMBER,
                            p_contact_id NUMBER,
                            p_details_public VARCHAR2,
                            p_details_private VARCHAR2 DEFAULT NULL,
                            p_valid_until_date DATE DEFAULT null,
                            p_defer_event NUMBER DEFAULT null,
                            p_escalate_after_defer BOOLEAN DEFAULT NULL,
                            p_hot_reason VARCHAR2 DEFAULT NULL,
                            p_zitadel_contact_id NUMBER DEFAULT NULL) IS

        ev_id NUMBER;

    BEGIN
        -- delegate call
        change_status_event_id_out(ev_id,
                                   p_ticket_id,
                                   p_status_id,
                                   p_contact_id,
                                   p_details_public,
                                   p_details_private,
                                   p_valid_until_date,
                                   p_defer_event,
                                   p_escalate_after_defer,
                                   p_hot_reason,
                                   p_zitadel_contact_id);

    END change_status;

--------------------------------------------------------------------------------
-- procedure change_status_event_id_out
--------------------------------------------------------------------------------
    PROCEDURE change_status_event_id_out(event_id OUT NUMBER,
                                         p_ticket_id NUMBER,
                                         p_status_id NUMBER,
                                         p_contact_id NUMBER,
                                         p_details_public VARCHAR2,
                                         p_details_private VARCHAR2 DEFAULT NULL,
                                         p_valid_until_date DATE DEFAULT NULL,
                                         p_defer_event NUMBER DEFAULT NULL,
                                         p_escalate_after_defer BOOLEAN DEFAULT NULL,
                                         p_hot_reason VARCHAR2 DEFAULT NULL,
                                         p_zitadel_contact_id NUMBER DEFAULT NULL) IS

        dets_pub VARCHAR2(2000);
        status_name VARCHAR2(100);
        v_cur_status_name VARCHAR2(100);
        l_ticket_type_id NUMBER;
        l_events_were_moved NUMBER := NULL;
        v_cur_status NUMBER;
        v_escalation_status_id NUMBER;
        v_cur_valid_until_date DATE;
        v_cur_status_changed_date DATE;
        v_details_private tt.event.details_private%TYPE;
        v_event_type_id NUMBER;
        v_handled_by_mcc NUMBER;
        v_hot_event_id NUMBER;
        v_last_public_event_id NUMBER;
        v_last_public_event_type_id NUMBER;
        v_now DATE;
        v_last_deferral_date DATE;
        v_ux_timeout_start TIMESTAMP WITH TIME ZONE;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        plog.debug('changestatus called');

        SELECT t.status_id, t.handled_by_mcc, t.last_public_event_id, t.escalation_status_id, t.status_valid_until_date,
               t.last_status_change_date, t.last_deferral_date, SYSDATE
        INTO   v_cur_status, v_handled_by_mcc, v_last_public_event_id, v_escalation_status_id, v_cur_valid_until_date, v_cur_status_changed_date, v_last_deferral_date, v_now
        FROM   tt.ticket t
        WHERE  t.id = p_ticket_id;

        v_last_public_event_type_id := NULL;
        IF (v_last_public_event_id IS NOT NULL) THEN
            SELECT event.type_id INTO v_last_public_event_type_id
            FROM   tt.event
            WHERE  event.id = v_last_public_event_id;
        END IF;

        -- and avoid unnecessary updates
        IF (v_cur_status = p_status_id) THEN
            RETURN;
        END IF;

        -- update time statitics for this ticket
        -- for the stati open(2), waiting(11), deferred(60), third-party(12), waiting for sign-off(61), resolved(101)
        IF (v_cur_status IN (2, 11, 12, 60, 61, 101)) THEN
            updateTicketTimeStats(p_ticket_id, v_cur_status, v_cur_status_changed_date);
        END IF;

        -- change the status of the ticket and update last_status_change date
        UPDATE tt.ticket t
        SET    t.status_id = p_status_id,
               t.last_status_change_date = SYSDATE
        WHERE  t.id = p_ticket_id;

        IF (v_last_deferral_date < v_now) THEN
            UPDATE tt.ticket t SET t.last_deferral_date = NULL WHERE t.id = p_ticket_id;
        END IF;

        -- create the update string
        SELECT name INTO status_name FROM status WHERE id = p_status_id;
        SELECT name INTO v_cur_status_name FROM status WHERE id = v_cur_status;

        dets_pub := 'New status: ' || status_name || CHR(10) || 'Previous status: ' || v_cur_status_name;
        dets_pub := dets_pub || CHR(10) || p_details_public;

        IF (p_escalate_after_defer) THEN
            dets_pub := dets_pub || ', escalation to os when reached.';
        END IF;

        -- status id 3 is hot
        IF (p_hot_reason IS NOT NULL AND p_status_id = 3) THEN
            -- hot status is currently private
            v_details_private := 'Hot because: ' || p_hot_reason || CHR(10) || p_details_private;
        ELSE
            v_details_private := p_details_private;
        END IF;

        -- get ticket type
        SELECT type_id INTO l_ticket_type_id FROM tt.ticket WHERE id = p_ticket_id;

        -- handle changes from/to deferred status
        IF (p_status_id = 60 OR v_cur_status = 60) THEN
            IF (p_status_id = 60) THEN
                IF (p_escalate_after_defer) THEN
                    /* we use status 20 (escalation to customer(!)) here, because in handleDeferredTransitions() the ticket will be
                     * escalated with status 10 (escalation to os) when the ticket is deferred and escalation status is 20 after the deferral
                     * ends (status will be hot =3)
                     * note: escalation status is not changed if an escalation is already in progress
                     */
                    UPDATE tt.ticket SET escalation_status_id = 20 WHERE ticket.id = p_ticket_id AND escalation_status_id NOT in (10,11);
                    UPDATE tt.ticket SET last_deferral_escalated = 1 WHERE ticket.id = p_ticket_id;
                ELSE
                    UPDATE tt.ticket SET last_deferral_escalated = 0 WHERE ticket.id = p_ticket_id;
                END IF;
            END IF;
            handleDeferredTransitions(p_ticket_id,p_status_id,v_cur_status,p_valid_until_date, p_contact_id, p_zitadel_contact_id);
        END IF;

        -- calculate the event type id, 101XXX is the prefix for status change events
        v_event_type_id := 101000 + p_status_id;

        -- create a new status change event (event_id is an OUT parameter of add_history_event())
        tt.event_interface.add_history_event(event_id,
                                             p_ticket_id,
                                             v_event_type_id,
                                             NULL,     --no host_id specified
                                             NULL,     --no company_id specified
                                             dets_pub,
                                             v_details_private,
                                             TRUE,     --it is a public event
                                             sysdate,  -- event date not specified, use sysdate
                                             p_contact_id,
                                             p_zitadel_contact_id);

        -- status id 3 is hot
        -- add the "hot non-MCC ticket" event if appropriate
        IF (p_status_id = 3 AND v_handled_by_mcc = 0) THEN
            -- event type 100008 is "hot non-MCC ticket"
            tt.event_interface.add_history_event(v_hot_event_id,
                                                 p_ticket_id,
                                                 100008,
                                                 NULL,
                                                 NULL,
                                                 NULL,  -- this event is always private
                                                 'This non-MCC ticket just became hot.',
                                                 FALSE, -- private
                                                 sysdate,
                                                 p_contact_id,
                                                 p_zitadel_contact_id);
        END IF;

        -- resolved event
        IF (p_status_id = 101) THEN
            UPDATE ticket SET last_resolved_date = SYSDATE WHERE ticket.id=p_ticket_id;
        END IF;

        -- delete event
        -- set resolved date and clear escalation status
        IF (p_status_id = 120) THEN
            -- delete ticket specific notifications
            TT.OSAG_NOTIFY.delete_ticket_notifications(p_ticket_id);

            UPDATE ticket SET last_resolved_date = SYSDATE, escalation_status_id = 0 WHERE ticket.id=p_ticket_id;
        END IF;

        -- pending escalations have to be stopped, if the ticket is opened (2) or acknowledged (4)
        -- furthermore if its status is recovered which might result in waiting (11), third-party (12), deferred (60), waiting for sign-off (61), or resolved (101)
        -- unless the current status is 60, then those transitions are already handled in
        -- handleDeferredTransitions (yes, this smells like refactoring is needed)
        IF (p_status_id IN (2, 4, 11, 12, 60, 61, 101) AND v_cur_status != 60 AND (p_contact_id IS NOT NULL OR p_zitadel_contact_id IS NOT NULL)) THEN
            -- in case of an escalation to the customer (20)
            IF (v_escalation_status_id = 20) THEN
                event_interface.addevent_new(event_id, p_ticket_id, 60102, null, 'Open Systems Mission Control engineer has acknowledged this ticket.'||CHR(10)||'The escalation process has finished.',null,p_contact_id,TRUE, sysdate, FALSE,p_zitadel_contact_id);
                UPDATE tt.ticket SET escalation_status_id = 0 WHERE id = p_ticket_id;
                -- otherwise we have an escalation to open systems (10 or 11)
            ELSIF (v_escalation_status_id IN (10,11)) THEN
                event_interface.addevent_new(event_id, p_ticket_id, 60002, null, 'Open Systems Mission Control engineer has acknowledged this ticket.'||CHR(10)||'The escalation process has finished.',null,p_contact_id,TRUE, sysdate, FALSE,p_zitadel_contact_id);
                UPDATE tt.ticket SET escalation_status_id = 0 WHERE id = p_ticket_id;
            END IF;
        END IF;

        -- update ticket status_valid_until field, status waiting (11), third party (12), waiting for sign-off (61)
        IF (p_status_id IN (11, 12, 61) AND p_valid_until_date IS NOT NULL) THEN
            tt.util.update_status_valid_until(p_ticket_id, p_valid_until_date);
        ELSE
            tt.util.update_status_valid_until(p_ticket_id);
        END IF;

        -- if the new status is "hot" (3), "acknowledged" (4), "open" (2), then check whether the current status is recoverable,
        -- unless the customer requests to resolve the ticket (30016)
        IF (p_status_id IN (2, 3, 4) AND NOT v_last_public_event_type_id IN (30016)) THEN
            -- "resolved" (101) is always recoverable
            IF (v_cur_status = 101) THEN
                UPDATE tt.ticket SET recoverable_status_id = v_cur_status WHERE id = p_ticket_id;

                -- "waiting" (11), "third party" (12) and "waiting for sign-off" (61) are recoverable if the ticket is a non-mcc ticket
                -- or the current "valid until date" is still in the future
            ELSIF (v_cur_status IN (11, 12, 61) AND (v_handled_by_mcc = 0 OR v_cur_valid_until_date > v_now)) THEN
                UPDATE tt.ticket SET recoverable_status_id = v_cur_status WHERE id = p_ticket_id;

                -- "deferred" (60) is only recoverable, if the current "valid until date" is still in the future
            ELSIF (v_cur_status = 60 AND v_cur_valid_until_date > v_now) THEN
                UPDATE tt.ticket SET recoverable_status_id = v_cur_status WHERE id = p_ticket_id;
            END IF;
        ELSE
            UPDATE tt.ticket SET recoverable_status_id = NULL WHERE id = p_ticket_id;
        END IF;

        -- update ux timeout
        -- if the new status is "open"(2), "hot"(3) or "acknowledged"(4) and the ticket was "waiting"(11), "third party"'(12), "deferred"(60), waiting for "sign-off" (61) or "resolved"(101)
        IF (p_status_id IN (2, 3, 4) AND v_cur_status IN (11, 12, 60, 61, 101)) THEN
            -- set the new ux timeout start to the time of the status change event
            SELECT from_tz(cast(eventdate as timestamp), 'EUROPE/ZURICH') INTO v_ux_timeout_start FROM tt.event WHERE id = event_id;
            UPDATE tt.ticket SET ux_timeout_start = v_ux_timeout_start WHERE id = p_ticket_id;
        END IF;
        update_ux_timeout_for_ticket(p_ticket_id, FALSE);

        -- current is actually previous at this stage of the process
        updateTicketFlow(p_ticket_id, v_cur_status, v_cur_status_changed_date);

    END change_status_event_id_out;

--------------------------------------------------------------------------------
-- procedure update_ux_timeout_for_ticket
--------------------------------------------------------------------------------

    PROCEDURE update_ux_timeout_for_ticket(p_ticket_id tt.ticket.id%TYPE,
                                           p_is_initial BOOLEAN) IS

        v_type_id NUMBER;
        v_emergency NUMBER;
        v_handled_by_mcc NUMBER;
        v_status_id NUMBER;
        v_ux_timeout TIMESTAMP WITH TIME ZONE;
        v_ux_timeout_start TIMESTAMP WITH TIME ZONE;
        v_service_window_end TIMESTAMP WITH TIME ZONE;
        v_ux_timeout_delta INTERVAL DAY TO SECOND;
        v_ticket_has_service_window NUMBER;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- extract ticket type and emergency status
        SELECT type_id, emergency, ux_timeout_start, handled_by_mcc, status_id
        INTO v_type_id, v_emergency, v_ux_timeout_start, v_handled_by_mcc, v_status_id
        FROM tt.ticket
        WHERE id = p_ticket_id;

        -- no timeouts for
        -- > tickets of type "third party incident"(4) or "customer incident"(5)
        -- > non MCC tickets
        -- > ticket status other than "new"(1), "open"(2), "hot"(3) and "acknowledged"(4)
        IF (v_type_id = 4 OR v_type_id = 5 OR v_handled_by_mcc = 0 OR v_status_id > 4) THEN
            UPDATE ticket SET ux_timeout = null WHERE id=p_ticket_id;
            RETURN;
        END IF;

        -- emergency timeouts
        IF (v_emergency = 1) THEN
            IF (p_is_initial) THEN
                v_ux_timeout_delta := INTERVAL '60' MINUTE;
            ELSE
                v_ux_timeout_delta := INTERVAL '120' MINUTE;
            END IF;
        ELSE
            -- for ticket types "incident", "monitoring incident"
            IF (v_type_id = 1 OR v_type_id = 6) THEN
                IF (p_is_initial) THEN
                    v_ux_timeout_delta := INTERVAL '120' MINUTE;
                ELSE
                    v_ux_timeout_delta := INTERVAL '240' MINUTE;
                END IF;
                -- for ticket types "change", "request", "installation", "migration"
            ELSIF (v_type_id = 2 OR v_type_id = 14 OR  v_type_id = 15 OR v_type_id = 8) THEN
                v_ux_timeout_delta := INTERVAL '480' MINUTE;
                -- for ticket type "problem"
            ELSIF (v_type_id = 11) THEN
                v_ux_timeout_delta := INTERVAL '960' MINUTE;
                -- for ticket type "purchase order"
            ELSIF (v_type_id = 9) THEN
                v_ux_timeout_delta := INTERVAL '720' MINUTE;
                -- for ticket type "maintenance"
            ELSIF (v_type_id = 12) THEN
                SELECT COUNT(*) INTO v_ticket_has_service_window
                FROM tt.service_window s
                WHERE p_ticket_id = s.ticket_id;

                IF (v_ticket_has_service_window > 0) THEN
                    -- get end of service window
                    SELECT from_tz(cast(end_date as timestamp), 'EUROPE/ZURICH')
                    INTO v_service_window_end
                    FROM tt.service_window
                    WHERE ticket_id = p_ticket_id AND ROWNUM = 1;

                    IF (v_service_window_end > v_ux_timeout_start) THEN
                        -- set timeout to 60 minutes after service window end
                        v_ux_timeout_start := v_service_window_end;
                        v_ux_timeout_delta := INTERVAL '60' MINUTE;
                    ELSE
                        v_ux_timeout_delta := INTERVAL '480' MINUTE;
                    END IF;
                ELSE
                    v_ux_timeout_delta := INTERVAL '480' MINUTE;
                END IF;

            END IF;
        END IF;

        v_ux_timeout := v_ux_timeout_start + v_ux_timeout_delta;
        UPDATE ticket SET ux_timeout = v_ux_timeout WHERE id=p_ticket_id;

    END update_ux_timeout_for_ticket;


--------------------------------------------------------------------------------
-- procedure change worker
--------------------------------------------------------------------------------
    PROCEDURE change_worker(p_ticket_id NUMBER,
                            p_worker_id NUMBER,
                            p_contact_id NUMBER,
                            p_handled_by_mcc NUMBER DEFAULT 0,
                            p_is_emergency NUMBER DEFAULT 0,
                            p_reason VARCHAR2 DEFAULT NULL,
                            p_zitadel_contact_id NUMBER DEFAULT NULL) IS

        cust_id NUMBER;
        new_shrt VARCHAR2(50);
        old_shrt VARCHAR2(50);
        new_mcc_flag VARCHAR2(20) := NULL;
        old_mcc_flag VARCHAR2(20) := NULL;
        v_handled_by_mcc NUMBER;
        v_status NUMBER;
        v_private_detail VARCHAR2(255);
        v_worker_id stop.contact.id%TYPE;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        BEGIN
            -- get the shrt of the new worker
            SELECT short, id INTO new_shrt, v_worker_id
            FROM stop.contact
            WHERE id = p_worker_id;

        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                new_shrt := 'MCC';
                new_mcc_flag := '';
                v_worker_id := NULL;
        END;

        BEGIN
            -- get the shrt and mcc-flag of the old worker
            SELECT c.short, t.handled_by_mcc INTO old_shrt, v_handled_by_mcc
            FROM stop.contact c, tt.ticket t
            WHERE t.id = p_ticket_id AND
                t.worker_id = c.id;

        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                old_shrt := 'MCC';
                old_mcc_flag := '';
                v_handled_by_mcc := 1;
        END;

        -- set the worker id for the ticket to the new worker_id
        UPDATE ticket
        SET worker_id = v_worker_id,
            worker_zitadel_id = (SELECT oidc_zitadel_id FROM auth.login WHERE contact_id = v_worker_id)
        WHERE ticket.id = p_ticket_id;

        -- set the handled by mcc flag for the ticket to the new p_handled_by_mcc
        IF (v_handled_by_mcc != p_handled_by_mcc) THEN
            UPDATE ticket
            SET handled_by_mcc = p_handled_by_mcc
            WHERE ticket.id = p_ticket_id;

            update_ux_timeout_for_ticket(p_ticket_id, FALSE);
        END IF;

        -- get the customer id
        SELECT company_id into cust_id
        FROM ticket WHERE id = p_ticket_id;

        -- set the old mcc flag comments
        IF (old_shrt != 'MCC') THEN
            IF (v_handled_by_mcc = 1) THEN
                old_mcc_flag := ' (MCC)';
            ELSE
                old_mcc_flag := ' (non-MCC)';
            END IF;
        END IF;

        -- set the new mcc flag comments
        IF (new_shrt != 'MCC') THEN
            IF (p_handled_by_mcc = 1) THEN
                new_mcc_flag := ' (MCC)';
            ELSE
                new_mcc_flag := ' (non-MCC)';
            END IF;
        END IF;

        -- add a private "attribute change event" to the ticket
        v_private_detail := 'Engineer changed to: ' || new_shrt || new_mcc_flag || '. Was: ' || old_shrt || old_mcc_flag || '.';
        IF (p_reason IS NOT NULL) THEN
            v_private_detail := v_private_detail || CHR(10) || 'Reason: ' || p_reason;
        END IF;

        INSERT into event
        (id,public_event,type_id,host_id,company_id,ticket_id,contact_id,details_private,contact_zitadel_id)
        VALUES (event_sequence.NextVal,
                0,
                100003,
                NULL,
                cust_id,
                p_ticket_id,
                p_contact_id,
                v_private_detail,
                p_zitadel_contact_id);

        updateTicketFlow(p_ticket_id);

    END change_worker;


--------------------------------------------------------------------------------
-- procedure change_service_host
--------------------------------------------------------------------------------
    PROCEDURE change_service_host(p_ticket_id NUMBER,
                                  p_service_id NUMBER,
                                  p_host_id NUMBER,
                                  p_contact_id NUMBER,
                                  p_zitadel_contact_id NUMBER DEFAULT NULL) IS

        cust_id NUMBER;
        v_host_label_old VARCHAR2(100);
        v_host_label_new VARCHAR2(100);
        v_service_id_old NUMBER;
        v_service_label_old VARCHAR2(300);
        v_service_label_new VARCHAR2(300);
        v_details_public VARCHAR2(600);

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- get the customer id
        SELECT company_id into cust_id
        FROM tt.ticket WHERE id = p_ticket_id;

        BEGIN
            -- get the old service name
            SELECT s.id, st.name INTO v_service_id_old, v_service_label_old
            FROM mss.service_type st, mss.service s, tt.ticket t
            WHERE t.id = p_ticket_id AND
                t.mss_service_id = s.id AND
                s.service_type_id = st.id;

            v_service_label_old := ' (' || v_service_label_old || ' [' || v_service_id_old || '])';

        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_service_label_old := NULL;
        END;

        BEGIN
            -- get the new service name
            SELECT st.name INTO v_service_label_new
            FROM mss.service_type st, mss.service s
            WHERE s.service_type_id = st.id AND
                s.id = p_service_id;

            v_service_label_new := ' (' || v_service_label_new || ' [' || p_service_id || '])';

        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_service_label_new := NULL;
        END;

        BEGIN
            -- get the old host name
            SELECT h.name INTO v_host_label_old
            FROM mss.host h, tt.ticket t
            WHERE t.id = p_ticket_id AND h.id = t.host_id;

            v_host_label_old := ' ' || v_host_label_old;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_host_label_old := ' <empty>';
        END;

        BEGIN
            -- get the new host name
            SELECT name INTO v_host_label_new
            FROM mss.host
            WHERE  id = p_host_id;
            v_host_label_new := ' ' || v_host_label_new;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_host_label_new := ' <empty>';
        END;

        v_details_public := 'service changed from' || v_host_label_old || v_service_label_old  || ' to' || v_host_label_new || v_service_label_new;

        -- edit an ticket "attribute change event" to the ticket
        INSERT into tt.event
        (id,type_id,company_id,details_public,contact_id,ticket_id,contact_zitadel_id)
        VALUES (event_sequence.NextVal,
                100003,
                cust_id,
                v_details_public,
                p_contact_id,
                p_ticket_id,
                p_zitadel_contact_id);

        -- update the service/host in the ticket
        UPDATE tt.ticket
        SET mss_service_id = p_service_id,
            host_id = p_host_id
        WHERE id = p_ticket_id;



    END change_service_host;

--------------------------------------------------------------------------------
-- procedure change_subject
--------------------------------------------------------------------------------
    PROCEDURE change_subject(p_ticket_id NUMBER,
                             p_subject VARCHAR2,
                             p_contact_id NUMBER,
                             p_zitadel_contact_id NUMBER DEFAULT NULL) IS

        cust_id NUMBER;
        sub_old VARCHAR2(200);

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        plog.debug('change_subject called');

        -- get the customer id
        SELECT company_id into cust_id
        FROM ticket WHERE id = p_ticket_id;

        -- get old subject
        SELECT t.subject INTO sub_old FROM tt.ticket t
        WHERE t.id = p_ticket_id;

        -- edit an ticket "attribute change event" to the ticket
        INSERT into event
        (id,type_id,company_id,ticket_id, contact_id, details_public, contact_zitadel_id)
        VALUES (event_sequence.NextVal,
                100003,
                cust_id,
                p_ticket_id,
                p_contact_id,
                'ticket subject changed:' || CHR(10) || 'old: ' || sub_old || CHR(10) || 'new: ' || p_subject,
                p_zitadel_contact_id);

        -- update the subject in the ticket
        UPDATE ticket
        SET subject=p_subject
        WHERE id=p_ticket_id;

    END change_subject;

--------------------------------------------------------------------------------
-- procedure change_customer_reference
--------------------------------------------------------------------------------
    PROCEDURE change_customer_reference(p_ticket_id NUMBER,
                                        p_customer_reference tt.ticket.customer_reference%TYPE,
                                        p_contact_id NUMBER,
                                        p_zitadel_contact_id NUMBER DEFAULT NULL) IS

        v_change_text tt.event.details_public%TYPE;
        v_event_id NUMBER;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        IF (p_customer_reference IS NOT NULL) THEN
            v_change_text := 'customer reference changed to ' || p_customer_reference;
        ELSE
            v_change_text := 'customer reference changed to <empty>';
        END IF;

        UPDATE tt.ticket
        SET customer_reference = p_customer_reference
        WHERE id = p_ticket_id;

        -- writing audit trail
        add_status_change_event(v_event_id, p_ticket_id, v_change_text, p_contact_id, null,p_zitadel_contact_id);

    END change_customer_reference;


--------------------------------------------------------------------------------
-- procedure change_label
--------------------------------------------------------------------------------
    PROCEDURE change_label(p_ticket_id NUMBER,
                           p_label_id NUMBER) IS

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        UPDATE tt.ticket SET label_id = p_label_id
        WHERE id = p_ticket_id;

    END change_label;


--------------------------------------------------------------------------------
-- procedure change_label
--------------------------------------------------------------------------------
    PROCEDURE change_label(p_ticket_id NUMBER,
                           p_label_id NUMBER,
                           p_contact_id NUMBER,
                           p_zitadel_contact_id NUMBER DEFAULT NULL) IS

        v_change_text VARCHAR2(100);
        v_company_id NUMBER;
        v_label_name VARCHAR2(100);

        v_old_label_id NUMBER;
        v_old_label_name VARCHAR2(100);

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- get the companyId and old labelId;
        SELECT company_id, label_id INTO v_company_id, v_old_label_id FROM ticket WHERE id=p_ticket_id;

        -- get old label name
        IF (v_old_label_id IS NULL) THEN
            v_old_label_name := 'null';
        ELSE
            SELECT name INTO v_old_label_name FROM label WHERE id=v_old_label_id;
        END IF;

        -- create audit event private text
        IF (p_label_id IS NULL) THEN
            v_change_text := 'Ticket label removed (was: ' || v_old_label_name || ')';
        ELSE
            SELECT name INTO v_label_name FROM label WHERE id=p_label_id;
            IF (v_old_label_id IS NULL) THEN
                v_change_text := 'Ticket label ' || v_label_name || ' added';
            ELSE
                v_change_text := 'Ticket label changed to ' || v_label_name || ' (was: ' || v_old_label_name || ')';
            END IF;
        END IF;

        change_label(p_ticket_id,p_label_id);

        -- add an "attribute change event" to the ticket
        INSERT into event
        (id, public_event, type_id, company_id, ticket_id, contact_id, details_private, contact_zitadel_id)
        VALUES (event_sequence.NextVal,
                0,
                100003,
                v_company_id,
                p_ticket_id,
                p_contact_id,
                v_change_text,
                p_zitadel_contact_id);

    END change_label;

--------------------------------------------------------------------------------
-- procedure expire_status
--------------------------------------------------------------------------------
    PROCEDURE expire_status(p_ticket_id NUMBER,
                            p_valid_until DATE,
                            p_last_change DATE,
                            p_status_id NUMBER,
                            p_status_name VARCHAR2,
                            p_label_id NUMBER) IS

        v_private_details VARCHAR2(4000);
        v_time_difference NUMBER := 0;
        v_label_name VARCHAR2(10);

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- time difference is computed in days -> multiply by 24 to get hours
        v_time_difference := 24 * (p_valid_until - p_last_change);
        v_private_details := 'Status changed to: hot (was ' || p_status_name || ' for ' || round(v_time_difference,2) || ' hours)';
        -- change the current status to status hot (3)
        change_status(p_ticket_id,3,NULL,NULL,v_private_details);
    END expire_status;

--------------------------------------------------------------------------------
-- procedure change_partner_reference
--------------------------------------------------------------------------------
    PROCEDURE change_partner_reference(p_ticket_id NUMBER,
                                       p_partner_reference tt.ticket.partner_reference%TYPE,
                                       p_contact_id NUMBER,
                                       p_zitadel_contact_id NUMBER DEFAULT NULL) IS

        v_change_text tt.event.details_public%TYPE;
        v_event_id NUMBER;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        IF (p_partner_reference IS NOT NULL) THEN
            v_change_text := 'partner reference changed to ' || p_partner_reference;
        ELSE
            v_change_text := 'partner reference changed to <empty>';
        END IF;

        UPDATE tt.ticket
        SET partner_reference = p_partner_reference
        WHERE id = p_ticket_id;

        -- writing audit trail
        add_status_change_event(v_event_id, p_ticket_id, NULL, p_contact_id, v_change_text, p_zitadel_contact_id);

    END change_partner_reference;

--------------------------------------------------------------------------------
-- procedure change_owner
--------------------------------------------------------------------------------
    PROCEDURE change_owner(p_ticket_id NUMBER,
                           p_owner_id NUMBER,
                           p_contact_id NUMBER,
                           p_zitadel_owner_id NUMBER DEFAULT NULL,
                           p_zitadel_contact_id NUMBER DEFAULT NULL,
                           p_company_id NUMBER DEFAULT NULL,
                           p_owner_zitadel_first_name VARCHAR2 DEFAULT NULL,
                           p_owner_zitadel_last_name VARCHAR2 DEFAULT NULL) IS

        cust_id NUMBER;
        first_name VARCHAR2(50);
        last_name VARCHAR2(50);
        v_details_public VARCHAR(300);
        v_company_id NUMBER;


    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- if provided, use zitadel info
        IF(p_owner_zitadel_first_name IS NOT NULL AND p_owner_zitadel_last_name IS NOT NULL) THEN
            v_details_public := 'ticket owner changed to ' || p_owner_zitadel_first_name || ' ' || p_owner_zitadel_last_name;
        ELSIF(p_owner_id IS NOT NULL) THEN
            -- get the first and lastname of the new customer/owner
            SELECT firstname, lastname into first_name, last_name
            FROM stop.contact
            WHERE id = p_owner_id;

            v_details_public := 'ticket owner changed to ' || first_name || ' ' || last_name;

            SELECT company_id INTO v_company_id
            FROM stop.contact
            WHERE id = p_owner_id;
        ELSE
            v_details_public := 'ticket owner changed to <empty>';

            -- get the customer id
            SELECT company_id into v_company_id
            FROM tt.ticket WHERE id = p_ticket_id;
        END IF;

        -- update the ticket owner and his company using zitadel ids if provided
        IF(p_zitadel_owner_id IS NOT NULL AND p_company_id IS NOT NULL) THEN
            UPDATE tt.ticket
            SET contact_zitadel_id = p_zitadel_owner_id,
                company_id = p_company_id
            WHERE id = p_ticket_id;
        ELSE
            UPDATE tt.ticket
            SET contact_id = p_owner_id,
                company_id = v_company_id
            WHERE id = p_ticket_id;
        END IF;

        -- add an "attribute change event" to the ticket
        INSERT into event
        (id,type_id,company_id,ticket_id, contact_id, details_public, contact_zitadel_id)
        VALUES (event_sequence.NextVal,
                100003,
                v_company_id,
                p_ticket_id,
                p_contact_id,
                v_details_public,
                p_zitadel_contact_id);

    END change_owner;

--------------------------------------------------------------------------------
-- procedure change_company
--------------------------------------------------------------------------------
    PROCEDURE change_company(p_ticket_id NUMBER,
                             p_company_id NUMBER,
                             p_contact_id NUMBER,
                             p_zitadel_contact_id NUMBER DEFAULT NULL) IS

        v_ser_id NUMBER;
        v_companyshort VARCHAR2(40);
        v_old_company_short stop.company.short%TYPE;
        v_old_company_id stop.company.id%TYPE;
        v_old_host_name mss.host.name%TYPE;
        v_old_host_id mss.host.id%TYPE;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- collect old data
        -- for history
        SELECT t.company_id, t.host_id INTO v_old_company_id, v_old_host_id FROM tt.ticket t WHERE t.id = p_ticket_id;

        IF (v_old_host_id IS NOT NULL) THEN
            SELECT h.name INTO v_old_host_name FROM mss.host h WHERE id = v_old_host_id;
        ELSE
            v_old_host_name := '<none>';
        END IF;

        IF (v_old_company_id IS NOT NULL) THEN
            SELECT c.short INTO v_old_company_short FROM stop.company c WHERE c.id = v_old_company_id;
        ELSE
            v_old_company_short := '<empty>';
        END IF;

        -- update the ticket owner and his company
        -- make sure that service and owner is also reset!
        UPDATE ticket
        SET company_id = p_company_id, contact_id = null, contact_zitadel_id = null, mss_service_id = null, host_id = null
        WHERE id = p_ticket_id;

        BEGIN
            -- get the company short;
            SELECT short INTO v_companyshort
            FROM stop.company
            WHERE id=p_company_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_companyshort := '<empty>';
        END;

        -- add an "attribute change event" to the ticket
        INSERT into event
        (id,type_id,company_id,ticket_id, contact_id,details_private,public_event,contact_zitadel_id)
        VALUES (event_sequence.NextVal,
                100003,
                p_company_id,
                p_ticket_id,
                p_contact_id,
                'company changed to ' || v_companyshort || CHR(10) || 'old company: '||v_old_company_short
                    ||CHR(10)||'old assigned host: '||v_old_host_name,
                0,
                p_zitadel_contact_id);

        -- delete notifications for non-OSAG logins which are assigned to this ticket
        DELETE FROM event_notification en
        WHERE EXISTS
                  (SELECT en.id FROM auth.login l
                   WHERE en.ticket_id = p_ticket_id
                     AND en.login_id = l.id
                     AND l.company_id != 6);  -- company_id = 6 means OSAG

        -- adapt the company reference of existing notifications of OSAG logins
        UPDATE tt.event_notification en
        SET en.company_id = p_company_id
        WHERE EXISTS
                  (SELECT en.id FROM auth.login l
                   WHERE en.ticket_id = p_ticket_id
                     AND en.login_id = l.id
                     AND l.company_id = 6); -- company_id = 6 means OSAG


    END change_company;

    -- call tt.ticket_interface.change_emergency(102706, 1, 2201);

    PROCEDURE change_emergency(p_ticket_id NUMBER,
                               p_emergency NUMBER,
                               p_contact_id NUMBER,
                               p_is_new_ticket NUMBER DEFAULT 0,
                               p_zitadel_contact_id NUMBER DEFAULT NULL) IS

        change_text VARCHAR2(100);
        v_event_id NUMBER;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        IF (p_emergency = 1) THEN
            change_text := 'ticket changed to emergency';
        ELSE
            change_text := 'ticket changed to non-emergency';
        END IF;

        add_status_change_event(v_event_id, p_ticket_id, change_text, p_contact_id, p_zitadel_contact_id);

        UPDATE ticket
        SET emergency = p_emergency, was_emergency = GREATEST(p_emergency, was_emergency)
        WHERE id=p_ticket_id;

        -- update ux timeout
        IF (p_is_new_ticket = 0) THEN
            update_ux_timeout_for_ticket(p_ticket_id, FALSE);
        ELSE
            update_ux_timeout_for_ticket(p_ticket_id, TRUE);
        END IF;

    END change_emergency;

    PROCEDURE change_always_visible(p_ticket_id NUMBER,
                                    p_always_visible NUMBER,
                                    p_contact_id NUMBER,
                                    p_zitadel_contact_id NUMBER DEFAULT NULL) IS

        change_text VARCHAR2(100);
        v_event_id NUMBER;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        IF (p_always_visible = 1) THEN
            change_text := 'ticket changed to always visible';
        ELSE
            change_text := 'ticket changed to not always visible';
        END IF;

        add_status_change_event(v_event_id, p_ticket_id, change_text, p_contact_id, p_zitadel_contact_id);

        UPDATE ticket
        SET always_visible = p_always_visible
        WHERE id=p_ticket_id;

    END change_always_visible;


    -- call tt.ticket_interface.change_notification(102706, '  -added email notificat...', 2201, '  -added SMS notification...);

    PROCEDURE change_notification(p_ticket_id NUMBER,
                                  p_change_text_public VARCHAR2,
                                  p_change_text_private VARCHAR2,
                                  p_contact_id NUMBER,
                                  p_zitadel_contact_id NUMBER DEFAULT NULL) IS

        EVENT_DETAILS_PREFIX CONSTANT VARCHAR2(64) := 'Notification settings changed' || CHR(10);

        v_event_id NUMBER;
        v_event_details_public VARCHAR2(4000);
        v_event_details_private VARCHAR2(4000);

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        IF (p_change_text_public IS NOT NULL) THEN
            v_event_details_public := EVENT_DETAILS_PREFIX || p_change_text_public;
        END IF;

        IF (p_change_text_private IS NOT NULL) THEN
            v_event_details_private := EVENT_DETAILS_PREFIX || p_change_text_private;
        END IF;

        add_status_change_event(v_event_id, p_ticket_id, v_event_details_public, p_contact_id, v_event_details_private, p_zitadel_contact_id);

    END change_notification;


    -- call tt.ticket_interface.change_summary(102706, NULL, 'public summary', 2201);

    PROCEDURE change_summary(p_ticket_id NUMBER,
                             p_summary_private VARCHAR2,
                             p_summary_public VARCHAR2,
                             p_contact_id NUMBER,
                             p_zitadel_contact_id NUMBER DEFAULT NULL) IS

        old_summary_private VARCHAR2(16000);
        old_summary_public VARCHAR2(16000);
        v_event_id NUMBER;
        p_summary_rel_events_count NUMBER;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- get the old summary
        SELECT summary_private, summary_public, summary_relevant_events_count into old_summary_private, old_summary_public, p_summary_rel_events_count
        FROM ticket WHERE id = p_ticket_id;

        IF ((old_summary_private != p_summary_private OR
             old_summary_private IS NULL OR
             p_summary_private IS NULL) AND
            NOT (old_summary_private IS NULL AND p_summary_private IS NULL)) THEN

            add_status_change_event(v_event_id, p_ticket_id, NULL, p_contact_id,
                                    'private summary changed to:' || CHR(10) || SUBSTR(NVL(p_summary_private, '<empty>'), 1, 3900), p_zitadel_contact_id);

            UPDATE ticket
            SET summary_private = p_summary_private
            WHERE id=p_ticket_id;
        END IF;

        IF ((old_summary_public != p_summary_public OR
             old_summary_public IS NULL OR
             p_summary_public IS NULL) AND
            NOT (old_summary_public IS NULL AND p_summary_public IS NULL)) THEN

            add_status_change_event(v_event_id, p_ticket_id,
                                    'public summary changed to:' || CHR(10) || SUBSTR(NVL(p_summary_public, '<empty>'), 1, 3900), p_contact_id, p_zitadel_contact_id);
            p_summary_rel_events_count := 0;

            UPDATE ticket
            SET summary_public = p_summary_public,
                summary_relevant_events_count = p_summary_rel_events_count,
                last_summary_update = SYSTIMESTAMP
            WHERE id=p_ticket_id;

        END IF;


    END change_summary;


--------------------------------------------------------------------------------
-- procedure change_type
--------------------------------------------------------------------------------
    PROCEDURE change_type(p_event_id OUT NUMBER,
                          p_ticket_id NUMBER,
                          p_type_id NUMBER,
                          p_contact_id NUMBER,
                          p_zitadel_contact_id NUMBER DEFAULT NULL) IS

        v_company_id NUMBER;
        v_old_type_name VARCHAR2(40);
        v_type_name VARCHAR2(40);

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- get the company id;
        SELECT company_id INTO v_company_id FROM ticket WHERE id=p_ticket_id;

        -- get the old type name for audit purposes
        SELECT type.name INTO v_old_type_name FROM ticket_type type, ticket t WHERE type.id = t.type_id AND t.id = p_ticket_id;

        -- get the new type name;
        SELECT name INTO v_type_name FROM ticket_type WHERE id=p_type_id;

        -- update the ticket type_id
        UPDATE ticket SET type_id = p_type_id  WHERE id = p_ticket_id;

        -- add a "ticket type change" event to the ticket
        INSERT into event
        (id,type_id,company_id,ticket_id, contact_id,details_public, contact_zitadel_id)
        VALUES (event_sequence.NextVal,100005,v_company_id, p_ticket_id, p_contact_id,'type changed from ' || v_old_type_name || ' to ' || v_type_name, p_zitadel_contact_id);

        -- store the event_id
        SELECT event_sequence.CurrVal INTO p_event_id FROM DUAL;

        update_ux_timeout_for_ticket(p_ticket_id, FALSE);
        updateTicketFlow(p_ticket_id);

    END change_type;

--------------------------------------------------------------------------------
-- procedure change_service_component
--------------------------------------------------------------------------------
    PROCEDURE change_service_component(p_event_id OUT NUMBER,
                                       p_ticket_id NUMBER,
                                       p_service_component_id NUMBER,
                                       p_contact_id NUMBER,
                                       p_zitadel_contact_id NUMBER DEFAULT NULL) IS

        v_company_id NUMBER;
        v_old_service_component_code VARCHAR2(40);
        v_old_service_component_name VARCHAR2(40);
        v_service_component_code VARCHAR2(40);
        v_service_component_name VARCHAR2(40);

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- get the company id;
        SELECT company_id INTO v_company_id FROM ticket WHERE id=p_ticket_id;

        -- get the old service component code for audit purposes
        BEGIN
            SELECT sc.internal_code INTO v_old_service_component_code FROM mss.service_component sc, ticket t WHERE sc.id = t.service_component_id AND t.id = p_ticket_id;
            SELECT sc.name INTO v_old_service_component_name FROM mss.service_component sc, ticket t WHERE sc.id = t.service_component_id AND t.id = p_ticket_id;
        EXCEPTION WHEN NO_DATA_FOUND THEN
            v_old_service_component_code := '';
            v_old_service_component_name := '<empty>';
        END;

        -- get the new service component code
        BEGIN
            SELECT internal_code INTO v_service_component_code FROM mss.service_component WHERE id = p_service_component_id;
            SELECT name INTO v_service_component_name FROM mss.service_component WHERE id = p_service_component_id;
        EXCEPTION WHEN NO_DATA_FOUND THEN
            v_service_component_code := '';
            v_service_component_name := '<empty>';
        END;

        -- update the ticket type_id
        UPDATE ticket SET service_component_id = p_service_component_id  WHERE id = p_ticket_id;

        -- add a "ticket attribute change" event to the ticket
        INSERT into event
        (id,type_id,company_id,ticket_id,contact_id,details_public,details_private, contact_zitadel_id)
        VALUES (event_sequence.NextVal,100003,v_company_id, p_ticket_id, p_contact_id,
                'service component changed',
                'service component changed from ' || v_old_service_component_name || ' (' || v_old_service_component_code || ') to ' || v_service_component_name || ' (' || v_service_component_code || ')', p_zitadel_contact_id);

        -- store the event_id
        SELECT event_sequence.CurrVal INTO p_event_id FROM DUAL;

        update_ux_timeout_for_ticket(p_ticket_id, FALSE);

    END change_service_component;

--------------------------------------------------------------------------------
-- function  get_next_recent_ticket
--------------------------------------------------------------------------------
    FUNCTION  get_next_recent_ticket(p_last_ticket_id NUMBER,
                                     p_host_id NUMBER,
                                     p_ticket_type_id NUMBER,
                                     p_resolve_age NUMBER ) RETURN NUMBER IS

        c_prefix  CONSTANT VARCHAR2(64) := 'get_next_recent_ticket(): ';
        v_ticketid  NUMBER := NULL;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- only look at tickets that haven't been closed (status 102) yet and are not deferred (status 60)

        SELECT MIN(t.id) INTO v_ticketid
        FROM tt.ticket t
        WHERE ( t.status_id < 102 ) AND (t.status_id <> 60)
          AND ( p_last_ticket_id IS NULL OR ( t.id > p_last_ticket_id ))
          AND ( p_host_id IS NULL        OR ( t.host_id = p_host_id )      OR ( p_host_id = 0 AND t.host_id IS NULL ))
          AND ( p_ticket_type_id IS NULL OR ( t.type_id = p_ticket_type_id ))
          AND ( p_resolve_age IS NULL
            OR t.status_id < 60   -- ticket not resolved yet
            OR ((t.last_resolved_date IS NULL ) OR (SYSDATE-t.last_resolved_date)*86400 <= p_resolve_age) ); -- ticket resolved

        RETURN v_ticketid;

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(c_prefix||'unexpected error 99: '||sqlerrm);
            RETURN NULL;
    END get_next_recent_ticket;

--------------------------------------------------------------------------------
-- procedure merge_tickets
--------------------------------------------------------------------------------
    PROCEDURE merge_tickets(p_ticket_id NUMBER,
                            p_mticket_id NUMBER,
                            p_contact_id NUMBER,
                            p_zitadel_contact_id NUMBER DEFAULT NULL) IS

        v_event_id NUMBER;
        v_status_change_event_id NUMBER;
        v_partner_ref VARCHAR2(50);
        v_mpartner_ref VARCHAR2(50);
        v_fast_resolvable NUMBER;
        v_mfast_resolvable NUMBER;
        v_last_public_event_id NUMBER;
        v_mlast_public_event_id NUMBER;
        v_mlast_public_event_id_before NUMBER;
        v_last_public_event_date tt.event.eventdate%TYPE;
        v_mlast_public_event_date tt.event.eventdate%TYPE;
        v_cust_rating_id tt.ticket_rating.id%TYPE;
        v_mcust_rating_id tt.ticket_rating.id%TYPE;
        v_eng_rating_id tt.ticket_rating.id%TYPE;
        v_meng_rating_id tt.ticket_rating.id%TYPE;
        v_mstatus_id NUMBER;
        v_mrecoverable_status_id NUMBER;
        v_ux_timeout_start TIMESTAMP WITH TIME ZONE;
        v_mux_timeout_start TIMESTAMP WITH TIME ZONE;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- first we'll query some attributes of the source ticket
        SELECT partner_reference, fast_resolvable, last_public_event_id, ux_timeout_start, customer_ticket_rating_id, engineer_ticket_rating_id
        INTO   v_partner_ref, v_fast_resolvable, v_last_public_event_id, v_ux_timeout_start, v_cust_rating_id, v_eng_rating_id
        FROM   ticket
        WHERE  id = p_ticket_id;

        IF (v_last_public_event_id IS NOT NULL) THEN
            SELECT eventdate INTO v_last_public_event_date FROM tt.event WHERE id = v_last_public_event_id;
        END IF;

        -- and some attributes of the target ticket
        SELECT partner_reference, fast_resolvable, last_public_event_id, recoverable_status_id, status_id, ux_timeout_start, customer_ticket_rating_id, engineer_ticket_rating_id
        INTO   v_mpartner_ref, v_mfast_resolvable, v_mlast_public_event_id, v_mrecoverable_status_id, v_mstatus_id, v_mux_timeout_start, v_mcust_rating_id, v_meng_rating_id
        FROM   ticket
        WHERE  id = p_mticket_id;

        IF (v_mlast_public_event_id IS NOT NULL) THEN
            SELECT eventdate INTO v_mlast_public_event_date FROM tt.event WHERE id = v_mlast_public_event_id;
        END IF;

        -- handle ratings (take most recent by id)
        -- customer
        IF (v_cust_rating_id IS NOT NULL) THEN
            UPDATE tt.ticket SET customer_ticket_rating_id = NVL(GREATEST(v_cust_rating_id, v_mcust_rating_id), v_cust_rating_id) WHERE id = p_mticket_id;
        END IF;

        -- engineer
        IF (v_eng_rating_id IS NOT NULL) THEN
            UPDATE tt.ticket SET engineer_ticket_rating_id = NVL(GREATEST(v_eng_rating_id, v_meng_rating_id), v_eng_rating_id) WHERE id = p_mticket_id;
        END IF;

        -- merge all events from ticket to mticket by changing the ticket id in
        -- the event table, but backup the original ticket id
        UPDATE tt.event
        SET org_ticket_id = ticket_id
        WHERE ticket_id = p_ticket_id and org_ticket_id IS NULL;

        UPDATE tt.event
        SET ticket_id = p_mticket_id
        WHERE ticket_id = p_ticket_id;

        /* add an mergeticket event (event type 100004) to ticket
         * we write the p_mticket_id in the private details field to give addevent a hint where to redirect
         * when trying to add an event to a merged ticket. so do not remove.
         */
        event_interface.addevent_new(v_event_id,
                                     p_mticket_id,
                                     100004,
                                     NULL,
                                     'ticket ' ||  p_ticket_id || ' merged with ticket no ' || p_mticket_id,
                                     p_mticket_id,
                                     p_contact_id,
                                     TRUE, sysdate, FALSE,
                                     p_zitadel_contact_id);

        -- Instead of simply connecting this event (in mticket) with the p_ticket,
        -- we create an exact duplicate of the event and connect
        -- p_ticket to this duplicate -> prepare migration to MC 7.1 where we
        -- don't have shared events anymore.

        INSERT INTO event
        (id, company_id, details_private, details_public, eventdate, public_event,type_id, ticket_id, contact_id, host_id, contact_zitadel_id)
        SELECT event_sequence.nextval, company_id, details_private, details_public, eventdate, public_event, type_id, p_ticket_id, contact_id, host_id, contact_zitadel_id
        FROM event
        WHERE id = v_event_id;

        -- set the merged into ticket field of the source ticket to hold the target ticket
        UPDATE tt.ticket set merged_into_ticket_id = p_mticket_id WHERE id = p_ticket_id;

        -- set the p_ticket status to merged (status 110) and set the close and resolve date
        ticket_interface.change_status(p_ticket_id,110,p_contact_id,NULL,NULL,NULL,NULL,NULL,NULL,p_zitadel_contact_id);
        UPDATE ticket
        SET close_date = sysdate, last_resolved_date = sysdate, last_public_event_id = NULL
        WHERE id = p_ticket_id;

        -- delete duplicate ticket notifications
        DELETE FROM tt.event_notification en1
        WHERE en1.ticket_id = p_ticket_id
          AND EXISTS (SELECT * FROM tt.event_notification en2
                      WHERE en2.ticket_id = p_mticket_id
                        AND en2.event_notification_type_id = en1.event_notification_type_id
                        AND en2.login_id = en1.login_id
                        AND (
                          (( en2.event_type_id is null and en1.event_type_id is null) or (en2.event_type_id = en1.event_type_id))
                              OR
                          (( en2.event_type_group_id is null and en1.event_type_group_id is null) or (en2.event_type_group_id = en1.event_type_group_id))
                          ));

        -- move ticket notifications from p_ticket to p_mticket
        UPDATE event_notification
        SET ticket_id = p_mticket_id
        WHERE ticket_id = p_ticket_id;

        -- move any existing change requests from p_ticket to p_mticket
        UPDATE change_request
        SET ticket_id = p_mticket_id
        WHERE ticket_id = p_ticket_id;

        -- if mticket has no partner reference, take over the one from ticket
        IF (v_mpartner_ref IS NULL AND v_partner_ref IS NOT NULL) THEN
            v_mpartner_ref := v_partner_ref;
        END IF;

        -- merge the fast-resolvable state
        IF (v_fast_resolvable = 0 AND v_mfast_resolvable = 1) THEN
            v_mfast_resolvable := 0;
        END IF;

        -- if both tickets have a "last public event", choose the newest
        -- if the last public event changes, the recoverable status is cleared.
        v_mlast_public_event_id_before := v_mlast_public_event_id;
        IF (v_last_public_event_id IS NOT NULL AND v_mlast_public_event_id IS NOT NULL AND v_last_public_event_date > v_mlast_public_event_date) THEN
            v_mlast_public_event_id := v_last_public_event_id;
            v_mrecoverable_status_id := NULL;
            -- if only the source ticket has one, merge it into the target
        ELSIF (v_last_public_event_id IS NOT NULL AND v_mlast_public_event_id IS NULL) THEN
            v_mlast_public_event_id := v_last_public_event_id;
            v_mrecoverable_status_id := NULL;
        END IF;

        -- update the ux_timeout start if the one from the source ticket is newer
        -- the timeout itself will be updated when the status of the ticket is changed to hot
        IF (v_ux_timeout_start > v_mux_timeout_start) THEN
            v_mux_timeout_start := v_ux_timeout_start;
        END IF;

        -- To make life easier:
        -- if the target ticket was resolved (101), make the status recoverable
        IF (v_mstatus_id = 101) THEN
            v_mrecoverable_status_id := 101;
        END IF;

        -- move suppressed events to new ticket
        UPDATE guma2.suppressed_signature
        SET ticket_id = p_mticket_id
        WHERE ticket_id = p_ticket_id;

        -- update all requirement attributes of the target ticket
        UPDATE tt.ticket
        SET    partner_reference = v_mpartner_ref, fast_resolvable = v_mfast_resolvable, last_public_event_id = v_mlast_public_event_id, recoverable_status_id = v_mrecoverable_status_id, ux_timeout_start = v_mux_timeout_start
        WHERE  id = p_mticket_id;

        -- set the status of the merged to ticket to hot (status 3)
        ticket_interface.change_status(p_mticket_id,3,p_contact_id,NULL,NULL,NULL,NULL,NULL,'ticket ' ||  p_ticket_id || ' merged into this ticket',p_zitadel_contact_id);

    END merge_tickets;

------------------------------------------------------------
-- replace_id_placeholders
------------------------------------------------------------
    FUNCTION replace_id_placeholders(p_text VARCHAR2,
                                     p_ticket_id NUMBER,
                                     p_event_id NUMBER) RETURN VARCHAR2 IS
        v_text VARCHAR2(30000);

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        v_text := SUBSTRB(REPLACE(p_text, '##ticket_id##', p_ticket_id), 1, 30000);
        v_text := SUBSTRB(REPLACE(v_text, '##event_id##', p_event_id), 1, 30000);
        RETURN v_text;
    END replace_id_placeholders;

--------------------------------------------------------------------------------

-- private procedure (read below when making public)--

    PROCEDURE add_status_change_event(event_id OUT NUMBER,
                                      p_ticket_id NUMBER,
                                      p_public_change_text VARCHAR2,
                                      p_contact_id NUMBER,
                                      p_private_change_text VARCHAR2 DEFAULT NULL,
                                      p_zitadel_contact_id NUMBER DEFAULT NULL) IS

        cust_id NUMBER;
        v_public_event NUMBER := 1;

    BEGIN

        -- check whether we have to hide the event
        -- we hide if p_public_change_text is NULL and p_private_change_text not
        -- if you ever decide to make this procedure public this has to be checked more carefully (whitespace-only strings...)
        IF (p_public_change_text IS NULL AND p_private_change_text IS NOT NULL) THEN
            v_public_event := 0;
        END IF;


        -- add a ticket "attribute change event" to the ticket
        INSERT into event
        (id,type_id,company_id,ticket_id, contact_id, details_public,details_private,public_event, contact_zitadel_id)
        VALUES (event_sequence.NextVal,
                100003,
                cust_id,
                p_ticket_id,
                p_contact_id,
                p_public_change_text,
                p_private_change_text,
                v_public_event,
                p_zitadel_contact_id);


        SELECT event_sequence.CurrVal INTO event_id FROM dual;

        -- notify event
        TT.OSAG_NOTIFY.event_notify(event_id, p_ticket_id);

    END add_status_change_event;


/*
 * Explicitly trigger escalation for a given ticket
 */
    PROCEDURE trigger_escalation(p_ticket_id NUMBER, p_contact_id NUMBER, p_triggering_event_id NUMBER,
                                 p_zitadel_contact_id NUMBER DEFAULT NULL) IS

        c_prefix       CONSTANT VARCHAR2(64) := 'trigger_escalation(): ';

        v_event_id NUMBER;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- event type id is 100007 = escalation triggering event
        tt.event_interface.add_history_event(v_event_id,
                                             p_ticket_id,
                                             100007,
                                             NULL,     --no host_id specified
                                             NULL,     --no company_id specified
                                             'Explicitly trigger escalation',
                                             'Escalation triggered by event '||p_triggering_event_id,
                                             TRUE,     --it is a public event
                                             sysdate,  -- event date not specified, use sysdate
                                             p_contact_id,
                                             p_zitadel_contact_id);

        -- execute the event type actions
        event_interface.exec_event_type_actions(v_event_id);
    EXCEPTION
        WHEN OTHERS THEN
            plog.err(c_prefix||'unexpected error: '||sqlerrm);
    END;


    /*
     * Create a new ticket rating and link it to the corresponding ticket
     */
    PROCEDURE rate_ticket(p_rating_id OUT NUMBER,
                          p_ticket_id NUMBER,
                          p_rating_event_id NUMBER,
                          p_contact_id NUMBER,
                          p_by_engineer NUMBER,
                          p_rating_value NUMBER,
                          p_zitadel_contact_id NUMBER DEFAULT NULL) IS

        v_history_event_id NUMBER;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- set the OUT varialbe p_rating_id to the current value
        SELECT ticketrating_seq.NextVal INTO p_rating_id FROM dual;

        INSERT INTO ticket_rating(id, rating, event_id)
        VALUES(p_rating_id, p_rating_value, p_rating_event_id);

        -- rating by engineer
        IF (p_by_engineer > 0) THEN
            UPDATE ticket
            SET engineer_ticket_rating_id = p_rating_id
            WHERE id = p_ticket_id;
            -- rating by customer
        ELSE
            UPDATE ticket
            SET customer_ticket_rating_id = p_rating_id
            WHERE id = p_ticket_id;
            -- if the rating by customer was bad (< 3), make the ticket hot (status 3)
            IF (p_rating_value < 3) THEN
                ticket_interface.change_status(p_ticket_id, 3, p_contact_id, NULL, NULL,NULL,NULL,NULL,NULL, p_zitadel_contact_id);
            END IF;
        END IF;
    END rate_ticket;


    /**
     * Add a Docs page to the ticket
     */
    PROCEDURE add_docs_page(p_ticket_docs_page_id OUT NUMBER,
                            p_ticket_id NUMBER,
                            p_page_id NUMBER,
                            p_page_version NUMBER,
                            p_page_title VARCHAR2,
                            p_hot_issue NUMBER,
                            p_contact_id NUMBER,
                            p_zitadel_contact_id NUMBER DEFAULT NULL) IS

        v_details_private VARCHAR2(4000);
        v_event_id NUMBER;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- set the return variable
        SELECT ticketdocspage_seq.NextVal INTO p_ticket_docs_page_id FROM dual;
        -- insert the new ticket-docs-page
        INSERT INTO ticket_docs_page(id, ticket_id, page_id, page_version, hot_issue)
        VALUES (p_ticket_docs_page_id, p_ticket_id, p_page_id, p_page_version, p_hot_issue);
        -- add history event ('added docs page' event, ID 100009)
        -- NOTE: if you change the private details, the text might not be replaced by a link anymore (see the DOCS_URL_PATTERN in HTML.java)
        v_details_private := 'Docs Page "' || p_page_title || '" (ID ' || p_page_id || ', v' || p_page_version
            || ') has been added to the ticket.';
        IF (p_hot_issue > 0) THEN
            v_details_private := 'Hot issue ' || v_details_private;
        END IF;
        event_interface.addevent_new(v_event_id, p_ticket_id, 100009, null, '', v_details_private, p_contact_id, false, sysdate, FALSE, p_zitadel_contact_id);

    EXCEPTION
        WHEN OTHERS THEN
            plog.err('tt.ticketInterface.add_docs_page: Unexpected error: ' || sqlerrm );
    END add_docs_page;


    /**
     * Remove a Docs page from the ticket
     */
    PROCEDURE remove_docs_page(p_ticket_docs_page_id NUMBER,
                               p_page_title VARCHAR2,
                               p_contact_id NUMBER,
                               p_zitadel_contact_id NUMBER DEFAULT NULL) IS

        v_details_private VARCHAR2(4000);
        v_page_id NUMBER;
        v_page_version NUMBER;
        v_ticket_id NUMBER;
        v_event_id NUMBER;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        SELECT page_id, page_version, ticket_id
        INTO v_page_id, v_page_version, v_ticket_id
        FROM ticket_docs_page
        WHERE id = p_ticket_docs_page_id;

        -- delete the ticket-docs-page
        DELETE FROM ticket_docs_page WHERE id = p_ticket_docs_page_id;
        -- add history event ('removed docs page' event, ID 100010)
        v_details_private := 'Docs Page "' || p_page_title || '" (ID ' || v_page_id || ', v' || v_page_version
            || ') has been removed from the ticket.';
        event_interface.addevent_new(v_event_id, v_ticket_id, 100010, null, '', v_details_private, p_contact_id, false, sysdate, FALSE, p_zitadel_contact_id);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            NULL;
        WHEN OTHERS THEN
            plog.err('tt.ticketInterface.remove_docs_page: Unexpected error: ' || sqlerrm );
    END remove_docs_page;


-- private procedure
-- handles the status transition in change_status for tickets
-- that were deferred or get deferred

-- p_ticket_id the affected ticket
-- p_new_status_id the status after the change
-- p_cur_status_id the status before the change
-- p_defer_date the date to defer the ticket to, maybe null
-- p_contact_id the contact carrying out the status change may be null

    PROCEDURE handleDeferredTransitions(p_ticket_id NUMBER,
                                        p_new_status_id NUMBER,
                                        p_cur_status_id NUMBER,
                                        p_defer_date DATE,
                                        p_contact_id NUMBER,
                                        p_zitadel_contact_id NUMBER DEFAULT NULL) IS

        c_prefix  CONSTANT VARCHAR2(64) := 'handleDeferredTransitions(): ';

        v_escalation_status NUMBER;
        v_event_id NUMBER;


    BEGIN

        -- check the escalation status
        SELECT escalation_status_id INTO v_escalation_status FROM ticket WHERE id = p_ticket_id;

        -- in case we have a deferred (status 60) customer escalation (escalation_status 20)
        -- it gets interesting
        IF (v_escalation_status = 20 AND p_cur_status_id = 60) THEN
            -- from deferred to hot (3), waiting(11), third party(12), deferred(60), waiting for sign-off (61), resolved(101): escalate!
            IF (p_new_status_id IN (3,11,12,60,61,101)) THEN

                event_interface.addevent_new(v_event_id, p_ticket_id,60001,null,
                                             'Starting escalation to Open Systems Mission Control','Event added by tt.handleDeferredTransitions. The ticket had a pending escalation (deferred) and changed its status to status '||p_new_status_id||'.');

                -- update escalation status and date of ticket
                -- escalation_status_id 10 means escalation to os
                UPDATE tt.ticket SET escalation_status_id = 10, last_escalation_date = sysdate WHERE id = p_ticket_id;

                -- from deferred to open, ack: add dummy events, don't escalate, i.e. reset
            ELSIF (p_new_status_id IN (2,4)) THEN

                UPDATE ticket SET escalation_status_id = 0 WHERE id = p_ticket_id AND escalation_status_id = 20;

                -- if we really reset something, we also add the according events
                IF (SQL%ROWCOUNT > 0) THEN
                    event_interface.addevent_new(v_event_id, p_ticket_id,60001, null,
                                                 'Starting escalation to Open Systems Mission Control','Event added by tt.handleDeferredTransitions. The ticket had a pending escalation (deferred) and changed its status');
                    event_interface.addevent_new(v_event_id, p_ticket_id, 60002, null,
                                                 'Open Systems Mission Control engineer has acknowledged this ticket.'||CHR(10)||'The escalation process has finished.','Immediate acknowledgment of the escalation as the ticket status has been manually changed.',p_contact_id, TRUE, sysdate, FALSE, p_zitadel_contact_id);
                END IF;

                -- from deferred(60) to deleted(120): clear escalation status, don't do anything else
            ELSIF (p_new_status_id = 120) THEN

                UPDATE tt.ticket SET escalation_status_id = 0 WHERE id = p_ticket_id;

            END IF;
        END IF;

        -- ticket will be deferred => set defer date, i.e. status_valid_until_date
        IF (p_new_status_id = 60) THEN
            UPDATE tt.ticket SET status_valid_until_date = p_defer_date, last_deferral_date = p_defer_date WHERE id = p_ticket_id;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            plog.err(c_prefix||'unexpected error: '||sqlerrm);
            RETURN;
    END handleDeferredTransitions;


    /**
     * Adds a ticket to the list of related tickets for a ticket
     */
    PROCEDURE add_related_ticket(p_ticket_id tt.ticket.id%TYPE, p_related_ticket_id tt.ticket.id%TYPE, p_contact_id stop.contact.id%TYPE,
                                 p_zitadel_contact_id NUMBER DEFAULT NULL) AS

        c_prefix  CONSTANT VARCHAR2(64) := 'add_related_ticket(): ';

        v_details_private VARCHAR2(500);
        v_counter NUMBER;
        v_event_id tt.event.id%TYPE;
    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- both tickets have to exists
        SELECT COUNT(*) INTO v_counter FROM tt.ticket t
        WHERE t.id IN (p_ticket_id, p_related_ticket_id);

        IF (v_counter != 2) THEN
            plog.err(c_prefix || 'One of the tickets involved does not exist or they are equal. Aborted!');
            RETURN;
        END IF;

        -- insert the relation
        INSERT INTO ticket2related_ticket (ticket_id, related_ticket_id)
        VALUES (p_ticket_id, p_related_ticket_id);

        -- add history event ('added related ticket' event, ID 100016)
        v_details_private := 'Related ticket ' || p_related_ticket_id || ' has been added to the ticket.';
        event_interface.addevent_new(v_event_id, p_ticket_id, 100016, null, null, v_details_private, p_contact_id, false, sysdate, FALSE, p_zitadel_contact_id);
    EXCEPTION
        WHEN OTHERS THEN
            plog.err(c_prefix || 'Unexpected error: ' || sqlerrm );
            RETURN;
    END add_related_ticket;

    /**
     * Removes a ticket from the list of related tickets for a ticket
     */
    PROCEDURE remove_related_ticket(p_ticket_id tt.ticket.id%TYPE, p_related_ticket_id tt.ticket.id%TYPE, p_contact_id stop.contact.id%TYPE,
                                    p_zitadel_contact_id NUMBER DEFAULT NULL) AS

        c_prefix  CONSTANT VARCHAR2(64) := 'remove_related_ticket(): ';

        v_counter NUMBER;
        v_details_private VARCHAR2(500);
        v_event_id tt.event.id%TYPE;
    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        SELECT COUNT(*) INTO v_counter FROM tt.ticket2related_ticket rt
        WHERE rt.ticket_id = p_ticket_id AND rt.related_ticket_id = p_related_ticket_id;

        IF (v_counter > 0) THEN
            -- delete the related ticket
            DELETE FROM tt.ticket2related_ticket
            WHERE ticket_id = p_ticket_id AND related_ticket_id = p_related_ticket_id;

            -- add history event ('removed related ticket' event, ID 100017)
            v_details_private := 'Removed ticket ' || p_related_ticket_id || ' from the list of related tickets.';
            event_interface.addevent_new(v_event_id, p_ticket_id, 100017, null, null, v_details_private, p_contact_id, false, sysdate, FALSE,p_zitadel_contact_id);
        END IF;


    EXCEPTION
        WHEN OTHERS THEN
            plog.err(c_prefix || 'Unexpected error: ' || sqlerrm );
            RETURN;

    END remove_related_ticket;


    /**
     * adds a file to the list of related mc files of a ticket
     */
    PROCEDURE add_related_file(p_ticket_id tt.ticket.id%TYPE, p_related_file_id mc.mc_file.id%TYPE, p_contact_id stop.contact.id%TYPE, p_zitadel_contact_id NUMBER DEFAULT NULL) AS

        c_prefix  CONSTANT VARCHAR2(64) := 'add_related_file(): ';

        v_file_display_name mc.mc_file.display_name%TYPE;
        v_details_private VARCHAR2(500);
        v_event_id tt.event.id%TYPE;
    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- get the name of the MC file
        -- and make sure that ticket and mc file belong to the same company
        -- otherwise the NO_DATA_FOUND should be triggered
        SELECT f.display_name INTO v_file_display_name FROM mc.mc_file f, mc.mc_file_release r, tt.ticket t
        WHERE t.id = p_ticket_id AND f.id = p_related_file_id and r.mc_file_id = f.id
          AND t.company_id = r.company_id;

        -- insert the relation
        INSERT INTO tt.ticket2mc_file (ticket_id, mc_file_id)
        VALUES (p_ticket_id, p_related_file_id);

        -- add history event ('added related document' event, ID 100018)
        v_details_private := 'Related file "' || v_file_display_name || '" (' || p_related_file_id || ') has been added to the ticket.';
        event_interface.addevent_new(v_event_id, p_ticket_id, 100018, null, null, v_details_private, p_contact_id, false, sysdate, FALSE,p_zitadel_contact_id);

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            plog.err(c_prefix || 'MC File or ticket does not exits or they belong to different companies.');
            RETURN;

        WHEN OTHERS THEN
            plog.err(c_prefix || 'Unexpected error: ' || sqlerrm );
            RETURN;

    END add_related_file;



    /**
     * removes a file from the list of related MC file of a ticket
     */
    PROCEDURE remove_related_file(p_ticket_id tt.ticket.id%TYPE, p_related_file_id mc.mc_file.id%TYPE, p_contact_id stop.contact.id%TYPE,
                                  p_zitadel_contact_id NUMBER DEFAULT NULL) AS

        c_prefix  CONSTANT VARCHAR2(64) := 'remove_related_file(): ';

        v_counter NUMBER;
        v_details_private VARCHAR2(500);
        v_event_id tt.event.id%TYPE;
        v_file_display_name mc.mc_file.display_name%TYPE;
    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        SELECT COUNT(*) INTO v_counter FROM tt.ticket2mc_file t2f
        WHERE t2f.ticket_id = p_ticket_id AND t2f.mc_file_id = p_related_file_id;

        IF (v_counter > 0) THEN

            SELECT mcf.display_name INTO v_file_display_name FROM mc.mc_file mcf
            WHERE mcf.id = p_related_file_id;

            -- delete the related ticket
            DELETE FROM tt.ticket2mc_file
            WHERE ticket_id = p_ticket_id AND mc_file_id = p_related_file_id;

            -- add history event ('removed related document' event, ID 100019)
            v_details_private := 'Removed file "' || v_file_display_name || '" (' || p_related_file_id || ') from the list of related files.';
            event_interface.addevent_new(v_event_id, p_ticket_id, 100019, null, null, v_details_private, p_contact_id, false, sysdate, FALSE, p_zitadel_contact_id);
        END IF;


    EXCEPTION
        WHEN OTHERS THEN
            plog.err(c_prefix || 'Unexpected error: ' || sqlerrm );
            RETURN;

    END remove_related_file;



    /**
     * Classifies the initial request based on the "customer's skill level".
     *
     * Note that only one of the three classifications (precise, standard, imprecise) can be given at a time.
     */
    PROCEDURE classify_request(p_ticket_id tt.ticket.id%TYPE, p_classification tt.ticket_request_classification.classification%TYPE,
                               p_contact_id stop.contact.id%TYPE, p_zitadel_contact_id NUMBER DEFAULT NULL) AS

        c_prefix  CONSTANT VARCHAR2(64) := 'classify_request(): ';

        v_counter NUMBER;
        v_details_private VARCHAR2(500);
        v_classification tt.ticket_request_classification.classification%TYPE;
        v_classification_text VARCHAR2(500);
        v_event_id tt.event.id%TYPE;
    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        v_classification := p_classification;

        -- map the classification to a meaningful text message
        IF (p_classification = 1) THEN
            v_classification_text := 'very precise';
        ELSIF (p_classification = 2) THEN
            v_classification_text := 'standard';
        ELSIF (p_classification = 3) THEN
            v_classification_text := 'imprecise';
        ELSE
            -- default to "standard" in case an invalid option is given
            v_classification := 2;
            v_classification_text := 'standard';
        END IF;

        SELECT COUNT(*) INTO v_counter FROM tt.ticket_request_classification
        WHERE ticket_id = p_ticket_id;

        IF (v_counter > 0) THEN
            UPDATE tt.ticket_request_classification SET classification = v_classification
            WHERE ticket_id = p_ticket_id;
        ELSE
            INSERT INTO tt.ticket_request_classification (id, ticket_id, classification)
            VALUES (tt.ticketreqclassification_seq.nextval, p_ticket_id, v_classification);
        END IF;

        -- add history event ('request classified' event, ID 100021)
        v_details_private := 'Classified initial request: ' || v_classification_text;
        event_interface.addevent_new(v_event_id, p_ticket_id, 100021, null, null, v_details_private, p_contact_id, false, sysdate, FALSE,p_zitadel_contact_id);

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(c_prefix || 'Unexpected error: ' || sqlerrm);
            RETURN;

    END classify_request;



    /**
     * Clears the todo list of the given ticket
     */
    PROCEDURE clear_todo_list(p_ticket_id NUMBER, p_contact_id NUMBER,  p_add_history_event Number DEFAULT 1, p_zitadel_contact_id NUMBER DEFAULT NULL) IS

        v_event_id NUMBER;
        v_event_type_id NUMBER;
        v_host_id NUMBER;
        v_company_id NUMBER;
        v_private_details VARCHAR2(4000);

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);

        DELETE FROM tt.todo_item WHERE ticket_id = p_ticket_id;

        IF (p_add_history_event = 1) THEN
            -- Add a "todo list cleared" history event (ID 100013)
            v_event_type_id := 100013;

            SELECT t.host_id, t.company_id
            INTO   v_host_id, v_company_id
            FROM   tt.ticket t
            WHERE  id = p_ticket_id;

            v_private_details := 'Todo list cleared';
            tt.event_interface.add_history_event(v_event_id,
                                                 p_ticket_id,
                                                 v_event_type_id,
                                                 v_host_id,
                                                 v_company_id,
                                                 NULL,
                                                 v_private_details,
                                                 FALSE,
                                                 sysdate,
                                                 p_contact_id,
                                                 p_zitadel_contact_id);
        END IF;

        -- set step count of ticket to 0
        UPDATE tt.ticket
        SET steps_total = 0, steps_completed = 0
        WHERE id = p_ticket_id;

    END clear_todo_list;


    /**
     * Adds a new todo item to a ticket
     * Note: This procedure doesn't add a history event. Todo items are always added in bunches but
     * we only want one single history event. Therefore the caller adds the history event itself.
     */
    PROCEDURE add_todo_item(p_todo_item_id OUT NUMBER,
                            p_ticket_id NUMBER,
                            p_seq_no NUMBER,
                            p_details VARCHAR2,
                            p_todo_item_status_id NUMBER,
                            p_contact_id NUMBER,
                            p_todo_item_is_public NUMBER DEFAULT 0,
                            p_zitadel_contact_id NUMBER DEFAULT NULL) IS

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- set the return variable
        SELECT todoitem_seq.NextVal INTO p_todo_item_id FROM dual;
        -- insert the new todo item
        INSERT INTO tt.todo_item(id, ticket_id, seq_no, details, todo_item_status_id, is_public)
        VALUES (p_todo_item_id, p_ticket_id, p_seq_no, p_details, p_todo_item_status_id, p_todo_item_is_public);

        -- increase step count of ticket for public todo items
        IF (p_todo_item_is_public = 1) THEN
            UPDATE tt.ticket
            SET steps_total = steps_total + 1
            WHERE id = p_ticket_id;

            -- if a public todo item is done or skipped increase steps_completed
            IF (p_todo_item_status_id IN (2, 4)) THEN
                UPDATE tt.ticket
                SET steps_completed = steps_completed + 1
                WHERE id = p_ticket_id;
            END IF;

            -- set todo_relevant_events_count to 0
            UPDATE tt.ticket
            SET todo_relevant_events_count = 0
            WHERE id = p_ticket_id;
        END IF;

    END add_todo_item;


    /**
     * Updates the status of a todo item.
     */
    PROCEDURE update_todo_item_status(p_ticket_id NUMBER,
                                      p_seq_no NUMBER,
                                      p_todo_item_status_id NUMBER,
                                      p_contact_id NUMBER,
                                      p_zitadel_contact_id NUMBER DEFAULT NULL) IS

        v_event_id NUMBER;
        v_event_type_id NUMBER;
        v_host_id NUMBER;
        v_company_id NUMBER;
        v_private_details VARCHAR2(8000);
        v_public_details VARCHAR2(8000);
        v_status_name tt.todo_item_status.name%TYPE;
        v_old_status_name tt.todo_item_status.name%TYPE;
        v_old_status_id NUMBER;
        v_details VARCHAR2(8000);
        v_is_public NUMBER;
        v_is_public_bool BOOLEAN;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        SELECT tis.name, ti.details, ti.is_public, tis.id
        INTO   v_old_status_name, v_details, v_is_public, v_old_status_id
        FROM   tt.todo_item ti LEFT JOIN tt.todo_item_status tis ON (ti.todo_item_status_id = tis.id)
        WHERE  ti.ticket_id = p_ticket_id AND ti.seq_no = p_seq_no;

        UPDATE tt.todo_item
        SET    todo_item_status_id = p_todo_item_status_id
        WHERE  ticket_id = p_ticket_id AND seq_no = p_seq_no;

        -- Add a "todo item updated" history event (ID 100015)
        v_event_type_id := 100015;

        SELECT t.host_id, t.company_id
        INTO   v_host_id, v_company_id
        FROM   tt.ticket t
        WHERE  id = p_ticket_id;

        SELECT tis.name
        INTO   v_status_name
        FROM   tt.todo_item_status tis
        WHERE  tis.id = p_todo_item_status_id;

        IF (v_is_public = 1) THEN
            v_public_details := 'New status of todo item (was: ' || v_old_status_name || '):' || CHR(13)
                || v_status_name || ' ' || v_details;
            v_private_details := NULL;
            v_is_public_bool := TRUE;

            -- adjust steps_completed
            IF (v_old_status_id IN (1, 3) AND p_todo_item_status_id IN (2, 4)) THEN
                -- if a public todo item changed from (todo or active) to (done or skipped) increase steps_completed
                UPDATE tt.ticket
                SET steps_completed = steps_completed + 1
                WHERE id = p_ticket_id;
            ELSIF (v_old_status_id IN (2, 4) AND p_todo_item_status_id IN (1, 3)) THEN
                -- if a public todo item changed from (done or skipped) to (todo or active) decrease steps_completed
                UPDATE tt.ticket
                SET steps_completed = steps_completed - 1
                WHERE id = p_ticket_id;
            END IF;

            -- set todo_relevant_events_count to 0
            UPDATE tt.ticket
            SET todo_relevant_events_count = 0
            WHERE id = p_ticket_id;

        ELSE
            v_public_details := NULL;
            v_private_details := 'New status of todo item ' || (p_seq_no + 1) || ' (was: ' || v_old_status_name || '):' || CHR(13)
                || v_status_name || ' ' || v_details;
            v_is_public_bool := FALSE;
        END IF;

        tt.event_interface.add_history_event(v_event_id,
                                             p_ticket_id,
                                             v_event_type_id,
                                             v_host_id,
                                             v_company_id,
                                             v_public_details,
                                             v_private_details,
                                             v_is_public_bool,
                                             sysdate,
                                             p_contact_id,
                                             p_zitadel_contact_id);

    END update_todo_item_status;


    -- update the time statistics of a ticket
    PROCEDURE updateTicketTimeStats(p_ticket_id NUMBER, p_cur_status_id NUMBER, p_last_status_change_date DATE) IS

        v_status_time NUMBER(10);
        v_stats_id NUMBER(10);
    BEGIN

        -- We only want to handle certain states
        -- open, resolved, waiting, third-party, waiting for sign-off, deferred
        IF (p_cur_status_id NOT IN (2,11,12,60,61,101)) THEN
            RETURN;
        END IF;

        -- calculate time in seconds
        v_status_time := TRUNC((sysdate - p_last_status_change_date) * 24 * 60 * 60);

        BEGIN
            -- select existing statistics record or create a new one
            SELECT ts.id INTO v_stats_id FROM tt.ticket_time_statistic ts WHERE ts.ticket_id = p_ticket_id;

        EXCEPTION
            -- no stats data exists
            WHEN NO_DATA_FOUND THEN
                SELECT tt.tickettimestatistic_seq.nextval INTO v_stats_id FROM dual;
                -- Use a merge into for atomic insert to avoid race
                merge into tt.ticket_time_statistic ts
                using (select p_ticket_id id from dual) sq
                on (ts.ticket_id = sq.id)
                when not matched then insert (ts.ID, ts.TICKET_ID) -- timer have 0 as a default
                                      values (v_stats_id, p_ticket_id);
                -- but in any case do the select again as it may not have inserted a new record
                SELECT ts.id INTO v_stats_id FROM tt.ticket_time_statistic ts WHERE ts.ticket_id = p_ticket_id;
        END;

        -- update times
        IF (p_cur_status_id = 2) THEN
            UPDATE tt.ticket_time_statistic SET open_time = open_time + v_status_time WHERE id = v_stats_id;
        ELSIF (p_cur_status_id IN (11,61)) THEN
            UPDATE tt.ticket_time_statistic SET waiting_time = waiting_time + v_status_time WHERE id = v_stats_id;
        ELSIF (p_cur_status_id = 12) THEN
            UPDATE tt.ticket_time_statistic SET third_party_time = third_party_time + v_status_time WHERE id = v_stats_id;
        ELSIF (p_cur_status_id = 60) THEN
            UPDATE tt.ticket_time_statistic SET deferred_time = deferred_time + v_status_time WHERE id = v_stats_id;
        ELSIF (p_cur_status_id = 101) THEN
            UPDATE tt.ticket_time_statistic SET resolved_time = resolved_time + v_status_time WHERE id = v_stats_id;
        END IF;

    END updateTicketTimeStats;

    /**
     * Checks and updates ticket flow entry if necessary
     * for the given ticket id
     */

    PROCEDURE updateTicketFlow (p_ticket_id NUMBER, p_prev_status_id NUMBER DEFAULT NULL, p_prev_status_change_date DATE DEFAULT NULL) IS

        v_status_id NUMBER;
        v_mcc_flag NUMBER;
        v_ticket_type_id NUMBER;
        v_flow_id NUMBER;

        v_last_status_change_date DATE;
        v_flow_in_date TIMESTAMP WITH TIME ZONE;
        v_status_time NUMBER;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- check if we have a flow entry in the queue for the ticket
        BEGIN
            SELECT tf.id, tf.FLOW_IN_DATE INTO v_flow_id, v_flow_in_date FROM tt.ticket_flow tf where ticket_id = p_ticket_id AND flow_out_date IS NULL;
        EXCEPTION
            -- no flow entry exists
            WHEN NO_DATA_FOUND THEN
                v_flow_id := NULL;
        END;

        -- check if the ticket should be in the MCC queue

        -- get required data
        SELECT t.handled_by_mcc, t.type_id, t.status_id, t.last_status_change_date
        INTO v_mcc_flag, v_ticket_type_id, v_status_id, v_last_status_change_date
        FROM tt.ticket t where t.id = p_ticket_id;

        -- if the ticket is MCC responsibility
        -- and the status is in progress, the ticket should be in the queue
        IF (v_flow_id IS NULL
            AND (v_status_id IN (1,2,3,4))
            AND (v_ticket_type_id NOT IN (4,5))
            AND (v_mcc_flag = 1) ) THEN

            -- put ticket in
            INSERT INTO tt.ticket_flow (ID, TICKET_ID, FLOW_IN_DATE, OPEN_TIME) VALUES (TT.TICKETFLOW_SEQ.NEXTVAL, p_ticket_id, SYSTIMESTAMP AT TIME ZONE 'EUROPE/ZURICH', 0);

        ELSIF (v_flow_id IS NOT NULL
            AND
               (v_status_id NOT IN (1,2,3,4)
                   OR v_ticket_type_id IN (4,5)
                   OR v_mcc_flag = 0)
            ) THEN

            -- take ticket out
            UPDATE tt.ticket_flow SET FLOW_OUT_DATE = SYSTIMESTAMP AT TIME ZONE 'EUROPE/ZURICH' WHERE ID = v_flow_id;

            -- update flow relevant open time if the status is still open
            IF v_status_id = 2 THEN
                -- calculate time in seconds
                v_status_time := (SYSDATE - GREATEST(CAST(v_flow_in_date AS DATE), v_last_status_change_date)) * 24 * 60 * 60;

                UPDATE tt.ticket_flow SET open_time = open_time + v_status_time WHERE ID = v_flow_id;

                -- update flow relevant open time if status change was reason for queue exit
            ELSIF (p_prev_status_id = 2) THEN
                -- calculate time in seconds
                v_status_time := (SYSDATE - GREATEST(CAST(v_flow_in_date AS DATE), p_prev_status_change_date)) * 24 * 60 * 60;

                UPDATE tt.ticket_flow SET open_time = open_time + v_status_time WHERE ID = v_flow_id;
            END IF;

            -- only open time change iff ticket was open before, but is no longer
        ELSIF (v_flow_id IS NOT NULL AND p_prev_status_id = 2 AND v_status_id != 2) THEN
            -- calculate time in seconds
            v_status_time := (SYSDATE - GREATEST(CAST(v_flow_in_date AS DATE), p_prev_status_change_date)) * 24 * 60 * 60;

            UPDATE tt.ticket_flow SET open_time = open_time + v_status_time WHERE ID = v_flow_id;

        END IF;

    END updateTicketFlow;

    PROCEDURE deleteTicket(p_ticket_id NUMBER) IS
    BEGIN
        UPDATE PRX.PRX_POLICY_ITEM SET TICKET_ID = null WHERE TICKET_ID = p_ticket_id;
        UPDATE TT.TICKET SET MERGED_INTO_TICKET_ID = null WHERE merged_INTO_TICKET_ID = p_ticket_id;
        UPDATE TT.TICKET SET LAST_PUBLIC_EVENT_ID = null WHERE ticket.id = p_ticket_id;
        UPDATE TT.TICKET SET CUSTOMER_TICKET_RATING_ID = null WHERE ticket.id IN (SELECT ID FROM TT.TICKET_RATING WHERE EVENT_ID IN ( SELECT ID FROM TT.EVENT WHERE TICKET_ID = p_ticket_id));
        UPDATE TT.TICKET SET ENGINEER_TICKET_RATING_ID = null WHERE ticket.id IN (SELECT ID FROM TT.TICKET_RATING WHERE EVENT_ID IN ( SELECT ID FROM TT.EVENT WHERE TICKET_ID = p_ticket_id));
        UPDATE TT.TICKET SET CUSTOMER_TICKET_RATING_ID = null WHERE CUSTOMER_TICKET_RATING_ID in (select id FROM TT.TICKET_RATING WHERE EVENT_ID IN ( SELECT ID FROM TT.EVENT WHERE TICKET_ID = p_ticket_id));
        UPDATE TT.TICKET SET ENGINEER_TICKET_RATING_ID = null WHERE ENGINEER_TICKET_RATING_ID in (select id FROM TT.TICKET_RATING WHERE EVENT_ID IN ( SELECT ID FROM TT.EVENT WHERE TICKET_ID = p_ticket_id));
        UPDATE MCAUDIT.RECORD SET TICKET_ID = NULL WHERE TICKET_ID = p_ticket_id;
        DELETE FROM TT.TICKET_DOCS_PAGE WHERE TICKET_ID = p_ticket_id;
        DELETE FROM TT.TICKET_FLOW WHERE ticket_id = p_ticket_id;
        DELETE FROM TT.TICKET2RELATED_TICKET WHERE TICKET_ID = p_ticket_id;
        DELETE FROM TT.TICKET2RELATED_TICKET WHERE RELATED_TICKET_ID = p_ticket_id;
        DELETE FROM TT.ATTACHMENT WHERE TICKET_ID = p_ticket_id;
        UPDATE MC.ISP_LINK_HISTORY SET EVENT_ID = NULL WHERE EVENT_ID IN ( SELECT ID FROM TT.EVENT WHERE TICKET_ID = p_ticket_id );
        DELETE FROM TT.TICKET_TIME_STATISTIC WHERE TICKET_ID = p_ticket_id;
        UPDATE MSS.INSTALLATION_PROJECT_ITEM SET ticket_id = null where ticket_id = p_ticket_id;
        DELETE FROM GUMA2.SUPPRESSED_SIGNATURE WHERE TICKET_ID = p_ticket_id;
        UPDATE MC.ISP_LINK_MAINTENANCE_HISTORY SET TICKET_ID = NULL WHERE TICKET_ID = p_ticket_id;
        UPDATE MC.HOST_MAINTENANCE_HISTORY SET TICKET_ID = NULL WHERE TICKET_ID = p_ticket_id;
        DELETE FROM NIDS.TICKET2RULE where ticket_id = p_ticket_id;
        DELETE FROM FW.RULE2TICKET where ticket_id = p_ticket_id;
        DELETE FROM FW.SOURCE_NAT_RULE2TICKET where ticket_id = p_ticket_id;
        DELETE FROM FW.DESTINATION_NAT_RULE2TICKET where ticket_id = p_ticket_id;
        DELETE FROM TT.TICKET2MC_FILE WHERE TICKET_ID = p_ticket_id;
        DELETE FROM TT.TICKET_RATING WHERE EVENT_ID IN ( SELECT ID FROM TT.EVENT WHERE TICKET_ID = p_ticket_id);
        DELETE FROM tt.ticket_rating WHERE id in (select t.customer_ticket_rating_id from tt.ticket t where t.id = p_ticket_id);
        DELETE FROM tt.ticket_rating WHERE id in (select t.engineer_ticket_rating_id from tt.ticket t where t.id = p_ticket_id);
        DELETE FROM TT.EVENT WHERE TICKET_ID = p_ticket_id;
        DELETE FROM TT.MAINTENANCE_WINDOW WHERE SERVICE_WINDOW_ID IN (SELECT SW.ID FROM tt.SERVICE_WINDOW SW WHERE TICKET_ID = p_ticket_id);
        DELETE FROM TT.CUST_MAINTENANCE_WINDOW WHERE SERVICE_WINDOW_ID IN (SELECT SW.ID FROM tt.SERVICE_WINDOW SW WHERE TICKET_ID = p_ticket_id);
        DELETE FROM TT.HOST2SERVICE_WINDOW WHERE SERVICE_WINDOW_ID IN (SELECT SW.ID FROM tt.SERVICE_WINDOW SW WHERE TICKET_ID = p_ticket_id);
        DELETE FROM MSS.deleted_host2service_window WHERE SERVICE_WINDOW_ID IN (SELECT SW.ID FROM tt.SERVICE_WINDOW SW WHERE TICKET_ID = p_ticket_id);
        DELETE FROM TT.SERVICE_WINDOW WHERE TICKET_ID = p_ticket_id;
        DELETE FROM TT.EVENT_NOTIFICATION WHERE TICKET_ID = p_ticket_id;
        DELETE from TT.TODO_ITEM where TICKET_ID = p_ticket_id;
        DELETE from TT.TICKET_REQUEST_CLASSIFICATION where TICKET_ID = p_ticket_id;
        DELETE FROM TT.CHANGE_REQUEST WHERE TICKET_ID = p_ticket_id;
        DELETE FROM FW.CHANGE WHERE TICKET_ID = p_ticket_id;
        DELETE FROM TT.TICKET WHERE ID = p_ticket_id;
    END deleteTicket;

END ticket_interface;
/