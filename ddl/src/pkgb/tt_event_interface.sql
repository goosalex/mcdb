--liquibase formatted sql logicalFilePath:pkgb/tt_event_interface.sql
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE BODY tt.event_interface IS

-- private functions declaration

    /* test if escalations are currentently to be suppressed by a service window specifing either disable guma escalation or
     * connection down escalation for a certain event.
     *
     * Parameters:
     *
     * p_host_id: id of the host for which a service window is searched
     *
     */
    FUNCTION is_esc_supp_active(p_host_id NUMBER, p_event_action_id NUMBER, p_event_type_id NUMBER) RETURN BOOLEAN;

--------------------------------------------------------------------------------
-- procedure newevent_new
--------------------------------------------------------------------------------
    PROCEDURE newevent_new(p_event_id OUT NUMBER,
                           p_type_id NUMBER,
                           p_host_id NUMBER,
                           p_details_public VARCHAR2,
                           p_details_private VARCHAR2 DEFAULT NULL,
                           p_contact_id NUMBER DEFAULT NULL,
                           p_public_event BOOLEAN DEFAULT TRUE,
                           p_eventdate DATE DEFAULT sysdate,
                           p_ticket_type_id NUMBER DEFAULT NULL,
                           p_service_component_id NUMBER DEFAULT NULL,
                           p_zitadel_contact_id NUMBER DEFAULT NULL,
                           p_company_id NUMBER DEFAULT NULL) AS

        c_prefix CONSTANT VARCHAR2(64) := 'tt.event_interface.newevent(): ';
        e_continue EXCEPTION;    -- exit loop

        pub_event NUMBER;
        subject VARCHAR2(200);
        eventSubject VARCHAR2(200);
        v_event_id NUMBER;
        v_history_event_id NUMBER;
        v_company_id NUMBER;
        v_mss_service_id NUMBER;
        active NUMBER;
        v_new_source NUMBER;    -- origin of this new event
        v_ticket_id NUMBER;    -- id of existing ticket to append new event to
        v_ticket_type_id NUMBER;
        v_details_public VARCHAR2(30000);
        v_details_private VARCHAR2(30000);
        v_msg_firstline VARCHAR2(30000);
        v_scope_info VARCHAR2(30000);

        v_monitoring_ticket_id NUMBER;
        v_collect_event_ticket_id NUMBER;
        v_disable_event_ticket_id NUMBER;
        v_recent_ticket_id NUMBER;
        v_recent_ticket_type NUMBER;
        v_recent_ticket_open_date DATE;
        v_recent_event_type NUMBER;
        v_recent_event_source NUMBER;

        v_reason VARCHAR2(1024) := '';

        v_count NUMBER;

        v_confirmed NUMBER;
        v_fast_resolvable NUMBER;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- details are only 30000 characters long cut after 30000 chars
        v_details_public := SUBSTRB(p_details_public,1,30000);
        v_details_private := SUBSTRB(p_details_private,1,30000);
        v_company_id := p_company_id;

        -- if a host id is given we select the company from the mss.host table
        -- and the mss.service.id from the host2service table
        BEGIN
            IF (p_host_id IS NOT NULL) THEN
                SELECT h.service_company_id, h2s.service_id INTO v_company_id, v_mss_service_id
                FROM mss.host h, mss.host2service h2s
                WHERE h.id = p_host_id AND h.id = h2s.host_id;
            END IF;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                plog.warning('host ID '||p_host_id||' is not attached to a service');
            WHEN OTHERS THEN
                RAISE;
        END;

        -- if a contact id is given we select the company_id from the contact table
        -- this overrides the company selection from the service id
        -- this only applies if the company wasn't already set
        IF (p_contact_id is not null AND v_company_id is null) THEN
            SELECT company_id INTO v_company_id
            FROM stop.contact
            WHERE contact.id = p_contact_id;
        END IF;

        -- ------------------------------------------------------------------------------------------
        -- [1] drop events from inactive services
        -- ------------------------------------------------------------------------------------------

        IF (p_host_id is not null) THEN
            SELECT h.active INTO active FROM mss.host h WHERE h.id = p_host_id;
            IF (active = 0) THEN
                plog.info(c_prefix||'dropping event of type '|| p_type_id ||' for inactive host '|| p_host_id);
                RETURN;
            END IF;
        END IF;

        -- ------------------------------------------------------------------------------------------
        -- [2] drop events if an open service window requests this
        -- The service window must currently be open and the new event must match its host_id
        -- ------------------------------------------------------------------------------------------

        IF (v_company_id is not null AND p_host_id is not null) THEN
            -- check if there are open service window for this host that have the disable event flag set
            SELECT COUNT(*) INTO v_disable_event_ticket_id
            FROM tt.ticket t
                     INNER JOIN tt.service_window s
                                ON (s.ticket_id = t.id)
                     INNER JOIN tt.host2service_window h2s
                                ON (h2s.service_window_id = s.id)

                     LEFT JOIN tt.maintenance_window m
                               ON (s.id = m.service_window_id)
                     LEFT JOIN tt.cust_maintenance_window cm
                               ON (s.id = cm.service_window_id)

            WHERE
                    t.status_id < 101 AND s.end_date > SYSTIMESTAMP AND s.start_date < SYSTIMESTAMP
              AND (m.disable_events = 1 OR cm.disable_events = 1) AND h2s.host_id = p_host_id;

            IF (v_disable_event_ticket_id > 0) THEN
                plog.info(c_prefix||'dropping event of type ' || p_type_id || ' for host ' || p_host_id ||
                          '. Active service window with disable event flag on ticket ' || v_disable_event_ticket_id );
                RETURN;
            END IF;
        END IF;

        -- ------------------------------------------------------------------------------------------
        -- [3] Try to find an existing ticket to append this event to! This is only relevant for
        --     automatically generated events (v_new_source=1) that can be attached to a ticket with
        --     the initial event also being an automatically generated event!
        --
        --     This code loops over all open tickets of the same host that fulfill certain
        --     type conditions (see comment in source code below) and then determines the
        --     source of the initial event (v_old_source) of each of those tickets. If
        --     an appropriate ticket is found it is stored in variable v_ticket_id.
        -- ------------------------------------------------------------------------------------------

        -- first see if there is a ticket with an open service window requesting event collection
        -- or if there is an open trouble or isp outage ticket with an automatic generated event
        -- as initial event that is still open
        -- in those cases we just add the event to that ticket.

        SELECT source INTO v_new_source FROM event_type WHERE id = p_type_id;

        v_ticket_type_id := nvl(p_ticket_type_id, ticket_type_for_event_type(p_type_id));

        IF ( v_new_source = 1 AND p_host_id IS NOT NULL ) THEN
            BEGIN
                IF ( v_company_id IS NOT NULL ) THEN
                    -- check for open monitoring outage ticket (status lower than deferred)
                    SELECT MIN(t.id) INTO v_monitoring_ticket_id
                    FROM tt.ticket t
                    WHERE t.company_id = v_company_id AND t.type_id = 6 AND t.status_id < 60;

                    IF ( v_monitoring_ticket_id IS NOT NULL ) THEN
                        -- append this automatic event to the open monitoring ticket
                        v_ticket_id := v_monitoring_ticket_id;
                        -- setting ticket type to 6 will prevent executing custom actions (see at the end of procedure)
                        v_ticket_type_id := 6;
                    ELSE
                        -- check if there are open service window for this company that request event collection
                        SELECT MAX(t.id) INTO v_collect_event_ticket_id
                        FROM tt.ticket t
                                 INNER JOIN tt.service_window s
                                            ON (s.ticket_id = t.id)
                                 INNER JOIN tt.host2service_window h2s
                                            ON (h2s.service_window_id = s.id)

                                 LEFT JOIN tt.maintenance_window m
                                           ON (s.id = m.service_window_id)
                                 LEFT JOIN tt.cust_maintenance_window cm
                                           ON (s.id = cm.service_window_id)

                        WHERE
                                t.status_id < 101 AND s.end_date > SYSTIMESTAMP AND s.start_date < SYSTIMESTAMP
                          AND (m.collect_events = 1 OR cm.collect_events = 1) AND h2s.host_id = p_host_id;


                        IF (v_collect_event_ticket_id IS NOT NULL) THEN
                            -- append this automatic event to the service window ticket
                            v_ticket_id := v_collect_event_ticket_id;
                            v_reason := 'found open service window requesting event collection';
                        ELSE
                            -- loop over initial events of recent tickets (open or resolved last 24 hour, not deferred) for same service
                            v_recent_ticket_id := tt.ticket_interface.get_next_recent_ticket(NULL,p_host_id,NULL,24*3600);
                            WHILE ( v_recent_ticket_id IS NOT NULL ) LOOP
                                    BEGIN
                                        -- get event and ticket types of recent ticket
                                        SELECT t.type_id, t.open_date, e.type_id, ety.source
                                        INTO v_recent_ticket_type, v_recent_ticket_open_date, v_recent_event_type, v_recent_event_source
                                        FROM tt.ticket t, tt.event e, tt.event_type ety
                                        WHERE t.id = v_recent_ticket_id
                                          AND e.ticket_id = t.id
                                          AND e.type_id = ety.id
                                          AND e.id = (
                                            SELECT MIN(id) FROM tt.event WHERE ticket_id = t.id
                                        );

                                        -- connection down (10001)
                                        -- isp outage (10003)
                                        IF ( p_type_id IN ( 10001, 10003 ) AND v_recent_event_type IN ( 10001, 10003, 10018 )) THEN
                                            v_ticket_id := v_recent_ticket_id;
                                            v_reason := 'found recent ticket for connection down/isp outage';

                                            -- in case of a connection down event, ISP Outage tickets (ticket type 4)
                                            -- should become trouble tickets (ticket type 1)
                                            IF (p_type_id = 10001 AND v_recent_ticket_type = 4) THEN
                                                ticket_interface.change_type(v_history_event_id, v_ticket_id, 1, p_contact_id);
                                            END IF;

                                            -- ids event: ids event tickets which were created less then one hour ago
                                        ELSIF ( p_type_id IN ( 10002, 10014 ) AND v_recent_event_type IN ( 10002, 10014 )
                                            AND (SYSDATE - v_recent_ticket_open_date) < 1/24 ) THEN
                                            v_ticket_id := v_recent_ticket_id;
                                            v_reason := 'found recent ticket for id alert/id/customer id notification';

                                            -- Don't append ids events to unrelated tickets
                                        ELSIF ( p_type_id IN ( 10002, 10014 ) ) THEN
                                            NULL;

                                            -- hardware installation event (10017)
                                            -- migration ticket type = '8' or installation ticket type = '15'
                                        ELSIF (p_type_id IN ( 10017 ) AND v_recent_ticket_type IN ( 8,15 )) THEN
                                            v_ticket_id := v_recent_ticket_id;
                                            v_reason := 'found recent migration/installation ticket for hardware installation event';
                                            -- Don't append hardware installation event to other automatically generated events
                                        ELSIF (p_type_id IN ( 10017 )) THEN
                                            NULL;

                                            -- customer id notification DNIDS (10020)
                                            -- if a ticket of any type was created by a customer id notification, further
                                            -- customer id notifications are added to that ticket
                                        ELSIF ( p_type_id IN ( 10020 ) AND v_recent_event_type IN ( 10020 )) THEN
                                            v_ticket_id := v_recent_ticket_id;
                                            v_reason := 'found recent ticket for customer id notification';

                                            -- Don't append customer id notifications to unrelated tickets
                                        ELSIF (p_type_id IN (10020)) THEN
                                            NULL;

                                            -- user synchronization error (10030)
                                            -- if a ticket of any type was created by a user synchronization error, further
                                            -- user synchronization errors are added to that ticket
                                        ELSIF (p_type_id IN (10030) AND v_recent_event_type IN (10030)) THEN
                                            v_ticket_id := v_recent_ticket_id;
                                            v_reason := 'found recent ticket for user synchronization error';

                                            -- Don't append user synchronization errors to other tickets
                                        ELSIF (p_type_id IN (10030)) THEN
                                            NULL;

                                            -- others are appended to automatically generated trouble tickets
                                        ELSIF ( v_recent_event_source = 1 AND v_recent_ticket_type = 1 ) THEN
                                            -- Don't append other events to trouble tickets created by customer id notification events
                                            -- or user synchronization errors
                                            -- Don't append to automatic IDS tickets and User Sync tickets
                                            IF (v_recent_event_type IN (10020,10030,10002,10014,10060)) THEN
                                                NULL;
                                            ELSE
                                                v_ticket_id := v_recent_ticket_id;
                                                v_reason := 'found recent ticket for automatically generated event';
                                            END IF;

                                        END IF;

                                    EXCEPTION
                                        WHEN NO_DATA_FOUND THEN
                                            NULL;
                                    END;

                                    IF ( v_ticket_id IS NOT NULL ) THEN
                                        v_recent_ticket_id := NULL;
                                    ELSE
                                        v_recent_ticket_id := tt.ticket_interface.get_next_recent_ticket(v_recent_ticket_id,p_host_id,NULL,24*3600);
                                    END IF;

                                END LOOP;
                        END IF;
                    END IF;
                END IF;
            EXCEPTION
                WHEN OTHERS THEN
                    plog.err(c_prefix||'unexpected error when trying to find appropriate ticket for automatically generated event: '||sqlerrm);
            END;
        END IF;

        -- ------------------------------------------------------------------------------------------
        -- [4] Append to existing ticket
        -- ------------------------------------------------------------------------------------------

        IF ( v_ticket_id IS NOT NULL ) THEN
            plog.notice(c_prefix || 'appending event '||p_type_id||' from host '||p_host_id||' to ticket '||v_ticket_id||': '||v_reason);

            -- an open ticket for this service already exists.
            -- we dont create a new ticket and add the event to the existing ticket
            addevent_new(p_event_id,
                         v_ticket_id,
                         p_type_id,
                         p_host_id,
                         v_details_public,
                         v_details_private,
                         p_contact_id,
                         p_public_event,
                         p_eventdate,
                         FALSE,
                         p_zitadel_contact_id);

            -- store the id of the newly created event
            v_event_id := p_event_id;

            -- Set the status of the ticket to hot (status id = 3)
            ticket_interface.change_status(v_ticket_id, 3, p_contact_id,NULL,'new event added',NULL,NULL,NULL,NULL,p_zitadel_contact_id);


            -- ------------------------------------------------------------------------------------------
            -- [5] Create a new ticket
            -- ------------------------------------------------------------------------------------------

        ELSE

            plog.notice(c_prefix || 'creating new ticket for event '||p_type_id||' from host '||p_host_id);

            IF (p_public_event) THEN
                pub_event:=1;
            ELSE
                pub_event:=0;
            END IF;

            -- default: use the event type name as the subject
            SELECT name INTO subject
            FROM event_type
            WHERE id=p_type_id;

            -- if type is 'email from customer', 'email to customer', 'third party email',
            -- 'id notification', 'id alert'
            -- then get the first line of the public details and put that into the subject
            IF (p_type_id = 30002 OR p_type_id = 30009 OR p_type_id = 40002 OR p_type_id = 10014 OR p_type_id = 10002) THEN
                subject := SUBSTR(v_details_public, 1, 100);
                subject := SUBSTR(subject, 1, INSTR(subject, CHR(10)) - 1);

                -- same for
                -- 'hardware notification/failure'
                -- 'application notification/failure'
                -- 'system notification/failure'
                -- 'customer id notification'
                -- 'system information'
            ELSIF p_type_id = 10004 OR p_type_id = 10005 OR
                  p_type_id = 10006 OR p_type_id = 10007 OR
                  p_type_id = 10008 OR p_type_id = 10009 OR
                  p_type_id = 10020 OR
                  p_type_id = 10021 THEN

                eventSubject := SUBSTR(v_details_public, 1, 95 - length(subject));
                IF (INSTR(eventSubject, CHR(10)) > 0) THEN
                    eventSubject := SUBSTR(eventSubject, 1, INSTR(eventSubject, CHR(10)) - 1);
                ELSIF (length(eventSubject) = (95 - length(subject))) THEN
                    eventSubject := SUBSTR(eventSubject, 1, length(eventSubject) - 3) || '...';
                END IF;
                subject := subject || ': ' || eventSubject;
            END IF;

            v_ticket_type_id := nvl(p_ticket_type_id, ticket_type_for_event_type(p_type_id));
            SELECT ticket_sequence.NextVal INTO v_ticket_id FROM DUAL;

            -- check if the given contact is an admin and therefore suitable as ticket owner
            -- role id 2 is mc_cust_admin
            v_count := 0;
            -- check company wide administrator if no service given
            IF (v_mss_service_id IS NULL) THEN
                SELECT count(*) INTO v_count
                FROM auth.permission p, auth.login l
                WHERE p.login_id = l.id AND l.contact_id = p_contact_id AND p.role_id = 2 AND p.company_id = v_company_id;
                -- check service administrative access if service given
            ELSE
                SELECT count(*) INTO v_count
                FROM auth.mv_service_access sa, auth.login l
                WHERE sa.login_id = l.id AND l.contact_id = p_contact_id AND sa.role_id = 2 AND sa.service_id = v_mss_service_id AND sa.service_company_id = v_company_id;
            END IF;

            -- if it is an automatic event, ticket type and service don't have to be confirmed
            v_confirmed := 0;
            v_fast_resolvable := 0;
            IF (v_new_source = 1) THEN
                v_confirmed := 1;
                v_fast_resolvable := 1;
            END IF;

            -- if zitadel contact id is given we don't check the count because auth and perms are checked in the API
            IF(v_count > 0 OR p_zitadel_contact_id IS NOT NULL) THEN
                -- open a new ticket for this event with the contact as owner
                INSERT INTO ticket
                (id, type_id, contact_id, company_id, host_id, subject, mss_service_id, service_confirmed, type_confirmed, fast_resolvable, service_component_id, contact_zitadel_id)
                VALUES(v_ticket_id, v_ticket_type_id, p_contact_id,v_company_id, p_host_id, subject, v_mss_service_id, v_confirmed, v_confirmed, v_fast_resolvable, p_service_component_id, p_zitadel_contact_id);
            ELSE
                -- open a new ticket for this event w/o owner
                INSERT INTO ticket
                (id, type_id, contact_id, company_id, host_id, subject, mss_service_id, service_confirmed, type_confirmed, fast_resolvable, service_component_id, contact_zitadel_id)
                VALUES(v_ticket_id, v_ticket_type_id, NULL, v_company_id, p_host_id, subject, v_mss_service_id, v_confirmed, v_confirmed, v_fast_resolvable, p_service_component_id, NULL);
            END IF;

            plog.debug(c_prefix || 'subject: ' || subject);

            -- set ux timeout
            UPDATE tt.ticket SET ux_timeout_start = from_tz(cast(open_date as timestamp), 'EUROPE/ZURICH') WHERE id = v_ticket_id;
            tt.ticket_interface.update_ux_timeout_for_ticket(v_ticket_id, TRUE);


            -- set the OUT varialbe p_event_id to the next event id
            SELECT event_sequence.NextVal INTO p_event_id FROM DUAL;

            -- log alerting events
               -- the list of the event types was condensed from the generatorGUMA2Alerts script
               --  10007 application failure
               --  10006 application notification
               --  10005 hardware error
               --  10004 hardware notification
               --  10014 id notification
               --  10002 id alert (not seen in the gen but taken anyway)
               --  10013 monitoring failure
               --  10009 system failure
               --  10021 system information
               --  10008 system notification
               --  10030 user synchronization notification
            IF (v_details_public is not null AND p_type_id IN (
                10007, 10006, 10005, 10004, 10014, 10002, 10013, 10009, 10021, 10008, 10030
            )) THEN
                v_msg_firstline := substr(v_details_public, 1, instr(v_details_public, chr(10)) -1 );
                IF (v_company_id is not null) THEN
                    v_scope_info := v_scope_info || ' company_id=' || v_company_id;
                END IF;
                IF (p_host_id is not null) THEN
                    v_scope_info := v_scope_info || ' host_id=' || p_host_id;
                END IF;
                plog.notice(c_prefix || 'insert event' || ' msgshort="' || v_msg_firstline || '" event_type_id=' || p_type_id || ' ticket=' || v_ticket_id || v_scope_info);
            END IF;

            -- insert the event into the event table
            INSERT INTO event
            (id,type_id,host_id,company_id, ticket_id, eventdate,details_public,details_private,public_event,contact_id,contact_zitadel_id)
            VALUES (p_event_id,
                    p_type_id,
                    p_host_id,
                    v_company_id,
                    v_ticket_id,
                    p_eventdate,
                    v_details_public,
                    v_details_private,
                    pub_event,
                    p_contact_id,
                    p_zitadel_contact_id);

            -- if the event is public and not of source notification (2) or history (10), remember it as the last public event of the ticket
            IF (pub_event > 0 AND v_new_source NOT IN (2, 10)) THEN
                UPDATE tt.ticket SET last_public_event_id = p_event_id WHERE id = v_ticket_id;
            END IF;

            -- if the event is public and not of source notification (2), automatic (1), escalation (6), or history (10)
            -- set the counter for the summary enforcement to 1
            IF (pub_event > 0 AND v_new_source NOT IN (1,2,6,10)) THEN
                UPDATE tt.ticket
                SET summary_relevant_events_count = 1,
                    todo_relevant_events_count = 1
                WHERE id = v_ticket_id;
            END IF;

            -- add a history event to the ticket (event type is 'new ticket', 101001)
            -- only add a history event if the event type source is not 1 (automatic)
            IF (v_new_source != 1) THEN
                add_history_event(v_event_id,
                                  v_ticket_id,
                                  101001,
                                  p_host_id,
                                  v_company_id,
                                  'New ticket created',
                                  NULL,
                                  TRUE, -- yes, it is a public event
                                  SYSDATE,
                                  p_contact_id,
                                  p_zitadel_contact_id);
            END IF;

            tt.ticket_interface.updateTicketFlow(v_ticket_id);
            -- execute the event type actions
            exec_event_type_actions(p_event_id);

        END IF;

        -- send notifications for this event if this is not a monitoring outage ticket
        IF ( v_ticket_type_id != 6 ) THEN
            TT.OSAG_NOTIFY.event_notify(p_event_id, v_ticket_id); -- send notifications via the (MC 8.5) notification framework
        END IF;

    END newevent_new;

------------------------------------------------------------------------------------------------------------------------------------
-- procedure addevent_new
--
-- adds an event to an existing ticket.
-- placeholders '##ticket_id##' and '##event_id##' in the given
-- details are replaced (see tt.ticket_interface.replace_id_placeholders)
--
-- dont add event to merged ticket. add event to the merged with ticket.
-- ticket status need to change to "hot" when adding an email from customer to a ticket.
------------------------------------------------------------------------------------------------------------------------------------
    PROCEDURE addevent_new(p_event_id OUT NUMBER,
                           p_ticket_id NUMBER,
                           p_type_id NUMBER,
                           p_host_id NUMBER,
                           details_public VARCHAR2,
                           details_private VARCHAR2 DEFAULT NULL,
                           p_contact_id NUMBER DEFAULT NULL,
                           public_event BOOLEAN DEFAULT TRUE,
                           eventdate DATE DEFAULT sysdate,
                           notify_event BOOLEAN DEFAULT FALSE,
                           p_zitadel_contact_id NUMBER DEFAULT NULL,
                           p_peer_contact_id NUMBER DEFAULT NULL) AS

        C_PREFIX CONSTANT VARCHAR2(64) := 'tt.event_interface.addevent_new(): ';

        pub_event NUMBER;
        ev_id NUMBER;
        v_company_id NUMBER;
        v_details_public VARCHAR2(30000);
        v_details_private VARCHAR2(30000);
        v_ticket_status NUMBER;
        v_ticket_type NUMBER;
        v_merged_details_private VARCHAR2(30000);
        v_merged_ticket_id NUMBER;
        v_event_source NUMBER;
        v_ticket_has_service_window NUMBER;
        v_history_event_id NUMBER;
        v_fast_resolvable NUMBER;
        v_last_public_event_id NUMBER;
        v_recoverable_status_id NUMBER;
        v_summary_rel_events_count NUMBER;
        v_todo_relevant_events_count NUMBER;
        v_ux_timeout_start TIMESTAMP WITH TIME ZONE;
        v_change_request_pending NUMBER;
        v_pinned NUMBER;
        v_msg_firstline VARCHAR2(30000);
        v_scope_info VARCHAR2(30000);


    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- first we'll query some ticket attributes
        SELECT t.type_id, t.status_id
        INTO   v_ticket_type, v_ticket_status
        FROM   tt.ticket t
        WHERE  t.id = p_ticket_id;

        SELECT source INTO v_event_source FROM tt.event_type WHERE id = p_type_id;
        SELECT autopin INTO v_pinned FROM tt.event_type WHERE id = p_type_id;

        -- if the ticket is already closed or archived we cannot add the event.
        -- what should we do
        -- we should create a new ticket with that data.
        -- In the moment this case isnt handeled!!!!!!!!!!!!!!!!!!!!!!

        -- if the ticket is merged into another ticket we just call addevent recursivly with the new ticket_id.
        IF (v_ticket_status = 110) THEN
            -- get the target ticket id and have a recursive call...
            -- we have to take this one out of the private details
            -- of the merge event (type id 100004)
            BEGIN
                SELECT TO_NUMBER(e.details_private) INTO v_merged_ticket_id
                FROM tt.event e
                WHERE e.ticket_id = p_ticket_id
                  AND e.type_id = 100004
                  AND TO_NUMBER(e.details_private) != p_ticket_id
                  AND EXISTS (SELECT 1 FROM tt.ticket t WHERE t.id = TO_NUMBER(e.details_private))
                  AND ROWNUM=1;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    v_merged_ticket_id := -1;
            END;

            -- call addevent recursively with new ticket_id
            IF (v_merged_ticket_id > 0) THEN
                addevent_new(p_event_id,v_merged_ticket_id,
                             p_type_id,
                             p_host_id,
                             details_public,
                             details_private,
                             p_contact_id,
                             public_event,
                             eventdate,
                             FALSE,
                             p_zitadel_contact_id);
                -- attribute it to the merged ticket: for example nurse OK events
                UPDATE tt.event SET org_ticket_id = p_ticket_id
                WHERE id = p_event_id and org_ticket_id IS NULL;
            END IF;
            -- handle closed, deleted, archived tickets
        ELSIF (v_ticket_status > 101) THEN
            plog.notice(C_PREFIX || ' Ticket with id '|| p_ticket_id || ' is closed/deleted, cannot add event!');
            RAISE_APPLICATION_ERROR(EVENT_INTERFACE_STATE.S_ERRNO_TICKET_CLOSED, 'Ticket with id '|| p_ticket_id || ' is closed/deleted');
        ELSE
            -- else we add the event to the ticket
            -- fill the OUT parameter
            SELECT event_sequence.NextVal INTO ev_id FROM DUAL;

            p_event_id := ev_id;

            -- replace ##ticket_id## and ##event_id## placeholders and truncate to 30000 characters
            v_details_public := tt.ticket_interface.replace_id_placeholders(details_public, p_ticket_id, ev_id);
            v_details_private := tt.ticket_interface.replace_id_placeholders(details_private, p_ticket_id, ev_id);

            IF (public_event) THEN
                pub_event:=1;
            ELSE
                pub_event:=0;
            END IF;

            -- if a host id is given we select the company from the mss.host table
            IF (p_host_id is not null) THEN
                SELECT h.service_company_id INTO v_company_id
                FROM mss.host h
                WHERE h.id = p_host_id;
            ELSE
                -- select company id from ticket
                SELECT company_id INTO v_company_id
                FROM tt.ticket
                WHERE ticket.id = p_ticket_id;
            END IF;

            -- log alerting events
            -- the list of the event types was condensed from the generatorGUMA2Alerts script
            --  10007 application failure
            --  10006 application notification
            --  10005 hardware error
            --  10004 hardware notification
            --  10014 id notification
            --  10002 id alert (not seen in the gen but taken anyway)
            --  10013 monitoring failure
            --  10009 system failure
            --  10021 system information
            --  10008 system notification
            --  10030 user synchronization notification
            IF (v_details_public is not null AND p_type_id IN (
                                                                10007, 10006, 10005, 10004, 10014, 10002, 10013, 10009, 10021, 10008, 10030
                )) THEN
                v_msg_firstline := substr(v_details_public, 1, instr(v_details_public, chr(10)) -1 );
                IF (v_company_id is not null) THEN
                    v_scope_info := v_scope_info || ' company_id=' || v_company_id;
                END IF;
                IF (p_host_id is not null) THEN
                    v_scope_info := v_scope_info || ' host_id=' || p_host_id;
                END IF;
                plog.notice(c_prefix || 'insert event' || ' msgshort="' || v_msg_firstline || '" event_type_id=' || p_type_id || ' ticket=' || p_ticket_id || v_scope_info);
            END IF;

            INSERT INTO event
            (id,type_id,host_id,company_id,eventdate,details_public,details_private,public_event, ticket_id, contact_id, pinned, contact_zitadel_id, peer_contact_id)
            VALUES (ev_id, p_type_id, p_host_id, v_company_id, eventdate,
                    v_details_public,v_details_private, pub_event, p_ticket_id, p_contact_id, v_pinned, p_zitadel_contact_id, p_peer_contact_id);

            -- update ux timeout if this is a public MC event (event type ids between 40000 and 60000)
            IF (public_event AND p_type_id >= 40000 AND p_type_id < 60000) THEN
                SELECT from_tz(cast(eventdate as timestamp), 'EUROPE/ZURICH') INTO v_ux_timeout_start FROM tt.event WHERE id = ev_id;
                UPDATE tt.ticket SET ux_timeout_start = v_ux_timeout_start WHERE id = p_ticket_id;
                tt.ticket_interface.update_ux_timeout_for_ticket(p_ticket_id, FALSE);
            END IF;

            -- TODO figure out why we only make tickets "hot" here in some
            -- cases, whereas we generically do it via newevent_new for
            -- existing tickets, see above

            -- set the ticket status to hot (status 3) if the event was one of...
            --   10002  id alert
            --   10003  isp outage
            --   10008  system notification
            --   10013  monitoring failure
            --   10014  id notification
            --   10040  edr notification
            --   10050  isp down
            --   10060  security notification
            --   10100  connection up
            --   30002  email from customer
            --   30009  email from third party
            --   30011  comment from customer (through the mc portal)
            --   30004  change request (by the customer through the mc portal)
            --   30013  ses change request (by the customer through the mc portal)
            --   30014  sls change request (by the customer through the mc portal)
            --   30016  customer requests to resolve the ticket
            --   30018  bounced email
            --   30019  waf change request
            --   30020  change request approved by customer
            --   30021  change request denied by customer
            --   30022  change request put on hold by customer
            --   30023  change done by customer
            IF (p_type_id IN ( 10002, 10003, 10008, 10013, 10014, 10040, 10050, 10060, 10100, 30002, 30009, 30011, 30004, 30013, 30014, 30016, 30018, 30019, 30020, 30021, 30022, 30023 ) AND v_ticket_status <> 3) THEN
                tt.ticket_interface.change_status(p_ticket_id,3,p_contact_id,NULL,'new event added',NULL,NULL,NULL,NULL,p_zitadel_contact_id);
            END IF;

            -- execute the event type actions, this triggers escalations if necessary
            exec_event_type_actions(p_event_id);

            -- turn an isp outage (4), customer information (5) ticket into a trouble ticket (1)
            -- if event_source is
            -- - one of 3 (from customer), 4 (to customer), 5 (contribution by OSAG)
            -- - and not private
            IF (v_ticket_type IN (4,5)) THEN
                SELECT source INTO v_event_source FROM event_type WHERE id = p_type_id;
                IF (v_event_source IN (3,4,5) AND pub_event = 1) THEN
                    tt.ticket_interface.change_type(v_history_event_id, p_ticket_id,1,NULL);
                END IF;
            END IF;

            /* if the added event is a connection down event, change the ticket type to incident
             * except if the ticket is a third party incident or a monitoring incident or
             * if the ticket has a service window
             */
            IF ( p_type_id = 10001 AND (v_ticket_type NOT IN (1,4,6))) THEN
                SELECT COUNT(*) INTO v_ticket_has_service_window
                FROM tt.service_window s, tt.ticket t
                WHERE t.id = p_ticket_id
                  AND t.id = s.ticket_id
                  AND SYSTIMESTAMP BETWEEN s.start_date AND s.end_date
                  AND t.status_id < 101; -- status 101 is resolved

                IF (v_ticket_has_service_window = 0) THEN
                    tt.ticket_interface.change_type(v_history_event_id, p_ticket_id,1,NULL);
                ELSE
                    plog.notice('ticket type of ticket ' || p_ticket_id || ' not changed due to active service window.');
                END IF;
            END IF;

            -- only do customer notifications for tickets that are not monitoring outage
            IF ( v_ticket_type != 6 ) THEN
                IF (notify_event) THEN
                    -- send notification
                    TT.OSAG_NOTIFY.event_notify(ev_id, p_ticket_id);
                END IF;
            END IF;

            -- update the ticket status_valid_until_date if MCC updated the ticket publicly visible
            -- this means that the event must be one of...
            --   30001 call from customer
            --   30008 third party call
            --   30009 third party email
            --   40002 email to customer
            --   50001 problem analysis
            --   50002 comment
            --   50003 configuration change
            IF (public_event AND p_type_id IN ( 30001, 30008, 30009, 40002, 50001, 50002, 50003 )) THEN
                tt.util.update_status_valid_until(p_ticket_id);
            END IF;

            -- we'll query some more ticket attributes (don't move this up, the attributes might change until here)
            SELECT t.fast_resolvable, t.last_public_event_id, t.recoverable_status_id, t.summary_relevant_events_count, t.todo_relevant_events_count
            INTO   v_fast_resolvable, v_last_public_event_id, v_recoverable_status_id, v_summary_rel_events_count, v_todo_relevant_events_count
            FROM   tt.ticket t
            WHERE  t.id = p_ticket_id;

            -- if the ticket was fast-resolvable and we're adding a non-automatic (1), non-audit (10), and non-notification (2) event,
            -- then it's not fast-resolvable anymore
            IF (v_fast_resolvable > 0 AND pub_event > 0 AND v_event_source NOT IN (1, 2, 10)) THEN
                v_fast_resolvable := 0;
            END IF;

            -- if the customer requests to resolve the ticket (event type 30016), make the ticket fast-resolvable
            IF (p_type_id = 30016) THEN
                v_fast_resolvable := 1;
            END IF;

            -- if the event is public and not of source history (2) or notification (10), remember it as the last public event of the ticket
            IF (pub_event > 0 AND v_event_source NOT IN (2, 10)) THEN
                v_last_public_event_id := ev_id;
                -- the last public event is separated from the others
                -- to avoid unnecessary update_timestamp updates on the ticket
                UPDATE tt.ticket
                SET  last_public_event_id = v_last_public_event_id
                WHERE  id = p_ticket_id;
            END IF;

            -- if the event is public and not of source automatic (1), notification (2), escalation (6) or history (10)
            -- we increase the counter for summary relevant events
            IF (pub_event > 0 AND v_event_source NOT IN (1,2,6,10)) THEN
                v_summary_rel_events_count := v_summary_rel_events_count + 1;
                v_todo_relevant_events_count := v_todo_relevant_events_count + 1;
            END IF;

            -- if it's a public event not of type change request approved by cust (30022) or by mc (50022) and not of source history (2), automatic (1), notification (10), escalation(6), or incoming (3),
            -- or if the customer requests to resolve the ticket (30016)
            -- then we'll clear the recoverable status
            IF ((pub_event > 0 AND v_event_source NOT IN (1, 2, 3, 6, 10) AND p_type_id NOT IN (30022, 50022)) OR p_type_id = 30016) THEN
                v_recoverable_status_id := NULL;
            END IF;

            -- get the number of change requests which are in state sign-off requested (2) or on hold (6)
            SELECT COUNT(*) INTO v_change_request_pending FROM tt.CHANGE_REQUEST cr where cr.TICKET_ID = p_ticket_id AND cr.CHANGE_REQUEST_STATE_ID IN (2, 6);

            -- if currently we can fast recover 'waiting for sign-off' but there are not more change requests in that state, we can safely remove it.
            If (v_change_request_pending = 0 AND v_recoverable_status_id = 61) THEN
                v_recoverable_status_id := NULL;
            END IF;

            -- update the necessary ticket attributes
            UPDATE tt.ticket
            SET    fast_resolvable = v_fast_resolvable,
                   recoverable_status_id = v_recoverable_status_id,
                   summary_relevant_events_count = v_summary_rel_events_count,
                   todo_relevant_events_count = v_todo_relevant_events_count
            WHERE  id = p_ticket_id;

        END IF;
    EXCEPTION
        WHEN EVENT_INTERFACE_STATE.ticket_closed THEN
            RAISE;
        WHEN OTHERS THEN
            plog.err(c_prefix||'unknown error for ticket:'||p_ticket_id||' : '||sqlerrm);
            plog.notice(DBMS_UTILITY.format_error_backtrace);
    END addevent_new;



------------------------------------------------------------------------------------------------------------------------------------
    FUNCTION ticket_type_for_event_type(p_event_type_id NUMBER) RETURN NUMBER IS

        v_ticket_type_id NUMBER;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- note from rv: maybe we could do even better than this and store
        -- this mapping in the table tt.event_type

        -- ticket type 3rd party incident
        --       event type isp outage 10003
        --       event type tunnel notification 10110
        --       event type vpn up 10102
        --       event type vpn down 10019
        IF p_event_type_id IN (10003, 10110, 10102, 10019) THEN
            v_ticket_type_id := 4;

            -- ticket type change request
        ELSIF p_event_type_id = 30002 OR p_event_type_id = 30009 THEN
            v_ticket_type_id := 2;

            -- default: mark the new ticket as a trouble ticket
        ELSE
            v_ticket_type_id := 1;
        END IF;

        RETURN v_ticket_type_id;

    END ticket_type_for_event_type;


------------------------------------------------------------------------------------------------------------------------------------
-- moveevent
-- FIXME / BROKEN the p_event_id is not actually used! This moves ALL events of a ticket. Looks like this code is never run.
------------------------------------------------------------------------------------------------------------------------------------
    PROCEDURE moveevent(p_event_id NUMBER,
                        p_oldticket_id NUMBER,
                        p_newticket_id NUMBER) AS

        c_prefix  CONSTANT VARCHAR2(64) := 'tt.event_interface.moveevent()" ';
        v_dummy   NUMBER;
        v_errmsg   VARCHAR(256);
    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        v_errmsg := 'cannot move event '||p_event_id||' from ticket '||p_oldticket_id||' to ticket '||p_newticket_id||': ';
        IF ( p_event_id IS NOT NULL AND p_newticket_id IS NOT NULL AND p_oldticket_id IS NOT NULL ) THEN
            SELECT id INTO v_dummy FROM tt.ticket WHERE id = p_newticket_id; -- check whether this ticket really exists...
            UPDATE tt.event e SET ticket_id = p_newticket_id WHERE ticket_id = p_oldticket_id;
        END IF;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            plog.warning(c_prefix||v_errmsg||'new ticket does not exist');
        WHEN DUP_VAL_ON_INDEX THEN
            plog.info(c_prefix||v_errmsg||'event is already in new ticket');
        WHEN OTHERS THEN
            plog.err(c_prefix||v_errmsg||'unknown error: '||sqlerrm);
    END moveevent;

------------------------------------------------------------------------------------------------------------------------------------
-- exec_event_type_actions
------------------------------------------------------------------------------------------------------------------------------------
    PROCEDURE exec_event_type_actions(p_event_id NUMBER) AS

        c_prefix CONSTANT VARCHAR2(64) := 'tt.event_interface.exec_event_type_actions(): ';
        v_event_type_id NUMBER;
        v_host_id NUMBER;
        v_proc_str VARCHAR2(4000);
        v_ticket_id tt.ticket.id%TYPE;

        CURSOR event_action_cur IS
            SELECT name, procedure_name, procedure_key_id, event_action_id
            FROM event_action, event_type_action
            WHERE event_type_action.event_type_id = v_event_type_id
              AND event_type_action.event_action_id = event_action.id;

        event_action_rec event_action_cur%ROWTYPE;

        stmt_str VARCHAR2(1000);
        v_esc_event_id NUMBER;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        plog.debug(c_prefix || 'execute exec_event_type_action for event ' || p_event_id);

        -- get the event type_id from the db
        SELECT type_id into v_event_type_id
        FROM event
        WHERE id = p_event_id;

        plog.debug(c_prefix || 'event_type_id is ' || v_event_type_id);


        -- get host for the event
        BEGIN
            SELECT e.host_id INTO v_host_id FROM tt.event e
            WHERE e.id = p_event_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_host_id := NULL;
            WHEN OTHERS THEN
                plog.err(c_prefix||'unexpected error while determing host for event with id ' ||p_event_id||': '||sqlerrm);
        END;

        plog.debug(c_prefix || 'host_id is ' || v_host_id);

        -- get ticket for the event
        SELECT ticket_id INTO v_ticket_id
        FROM tt.event
        WHERE id = p_event_id;

        plog.debug(c_prefix || 'ticket_id is ' || v_ticket_id);

        -- loop over all event type actions for this event type
        FOR event_action_rec IN event_action_cur
            LOOP
                IF (NOT is_esc_supp_active(v_host_id, event_action_rec.event_action_id, v_event_type_id)) THEN
                    -- check if there is a procedure key and a host
                    IF (event_action_rec.procedure_key_id IS NOT NULL AND v_host_id IS NOT NULL) THEN

                        plog.debug(c_prefix || 'looking up procedure name in DBPROP using key with id ' || event_action_rec.procedure_key_id );

                        -- get the procedure name from the dbprop property
                        v_proc_str := mss.OSAG_DBPROP.get_string_by_host_key_id(v_host_id, event_action_rec.procedure_key_id);

                    END IF;

                    IF (v_proc_str IS NULL) THEN
                        v_proc_str := event_action_rec.procedure_name;
                    END IF;

                    plog.debug(c_prefix || 'event action : ' || v_proc_str);

                    -- execute the procedure
                    -- N.B: the only procedure left configured in tt.event_action today is: tt.escalation_interface.escalate_os()
                    IF (v_proc_str IS NOT NULL) THEN
                        BEGIN
                            stmt_str :=  'call ' || v_proc_str || '(:eventid)';
                            plog.debug(c_prefix || 'executing : ' || stmt_str);
                            EXECUTE IMMEDIATE stmt_str USING p_event_id;
                        EXCEPTION
                            WHEN OTHERS THEN
                                plog.err(c_prefix||'unexpected error during procedure execution: '||sqlerrm);
                        END;
                    ELSE
                        plog.notice(c_prefix || 'no procedure executed for host: ' || v_host_id || ' on event of type: '||v_event_type_id);
                    END IF;
                ELSE
                    plog.notice(c_prefix || 'escalation suppressed for event ' || p_event_id || ' due to active service window.');
                    addevent_new(v_esc_event_id, v_ticket_id, 60010, v_host_id,
                                 'Escalation suppressed for event ' || p_event_id || ' due to active service window.' ,
                                 'Event added by tt.event_interface.exec_event_type_actions.');
                END IF;
            END LOOP;
    END exec_event_type_actions;

    FUNCTION is_esc_supp_active(p_host_id NUMBER, p_event_action_id NUMBER, p_event_type_id NUMBER) RETURN BOOLEAN IS

        v_guma_suppressor_exists INTEGER;
        v_conn_suppressor_exists INTEGER;

    BEGIN
        IF (p_event_type_id = 10002 OR
            p_event_type_id = 10005 OR
            p_event_type_id = 10007 OR
            p_event_type_id = 10009) THEN

            -- ok, it's an event we would suppress if there was a service window, so check this

            SELECT COUNT(*) INTO v_guma_suppressor_exists
            FROM tt.ticket t
                     INNER JOIN tt.service_window s
                                ON (s.ticket_id = t.id)
                     INNER JOIN tt.host2service_window h2s
                                ON (h2s.service_window_id = s.id)

                     LEFT JOIN tt.maintenance_window m
                               ON (s.id = m.service_window_id)
                     LEFT JOIN tt.cust_maintenance_window cm
                               ON (s.id = cm.service_window_id)

            WHERE
                    t.status_id < 101 AND s.end_date > SYSTIMESTAMP AND s.start_date < SYSTIMESTAMP
              AND (m.disable_guma_escalation = 1 OR cm.disable_guma_escalation = 1) AND h2s.host_id = p_host_id;

            IF (v_guma_suppressor_exists > 0) THEN
                RETURN TRUE;
            END IF;
        END IF;

        IF (p_event_action_id = 2 -- connection down
            OR (p_event_action_id = 1 AND p_event_type_id=10050) -- isp down
            ) THEN
            -- ok, it's a connection or isp down
            -- we would suppress it if there was a service window, so check this

            SELECT COUNT(*) INTO v_conn_suppressor_exists
            FROM tt.ticket t
                     INNER JOIN tt.service_window s
                                ON (s.ticket_id = t.id)
                     INNER JOIN tt.host2service_window h2s
                                ON (h2s.service_window_id = s.id)

                     LEFT JOIN tt.maintenance_window m
                               ON (s.id = m.service_window_id)
                     LEFT JOIN tt.cust_maintenance_window cm
                               ON (s.id = cm.service_window_id)

            WHERE
                    t.status_id < 101 AND s.end_date > SYSTIMESTAMP AND s.start_date < SYSTIMESTAMP
              AND (m.disable_conn_escalation = 1 OR cm.disable_conn_escalation = 1) AND h2s.host_id = p_host_id;

            IF (v_conn_suppressor_exists > 0) THEN
                RETURN TRUE;
            END IF;
        END IF;

        RETURN FALSE;
    END is_esc_supp_active;

------------------------------------------------------------------------------------------------------------------------------------
-- add_history_event
------------------------------------------------------------------------------------------------------------------------------------
    PROCEDURE add_history_event(p_event_id OUT NUMBER,
                                p_ticket_id NUMBER,
                                p_event_type_id NUMBER,
                                p_host_id NUMBER,
                                p_company_id NUMBER,
                                p_details_public VARCHAR2,
                                p_details_private VARCHAR2 DEFAULT NULL,
                                p_public_event BOOLEAN DEFAULT TRUE,
                                p_eventdate DATE DEFAULT sysdate,
                                p_contact_id NUMBER DEFAULT NULL,
                                p_zitadel_contact_id NUMBER DEFAULT NULL) AS

        -- variable declaration
        -- C_PREFIX CONSTANT VARCHAR2(64) := 'tt.event_interface.add_history_event(): ';
        v_public_event NUMBER;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- convert BOOLEAN to NUMBER
        IF (p_public_event) THEN
            v_public_event:= 1;
        ELSE
            v_public_event:= 0;
        END IF;

        -- fill the OUT parameter
        SELECT event_sequence.NextVal INTO p_event_id FROM DUAL;

        -- create the event
        INSERT INTO event
        (id, type_id, host_id ,company_id, eventdate, details_public, details_private, public_event, ticket_id, contact_id, contact_zitadel_id)
        VALUES (p_event_id,
                p_event_type_id,
                p_host_id,
                p_company_id,
                p_eventdate,
                p_details_public,
                p_details_private,
                v_public_event,
                p_ticket_id,
                p_contact_id,
                p_zitadel_contact_id);

        -- send notifications for this event
        TT.OSAG_NOTIFY.event_notify(p_event_id, p_ticket_id);

    END add_history_event;

------------------------------------------------------------------------------------------------------------------------------------
-- demote_event
------------------------------------------------------------------------------------------------------------------------------------
    PROCEDURE demote_event(p_event_id NUMBER, p_contact_id NUMBER) AS

        v_history_event_id NUMBER;
        v_ticket_id NUMBER;
        v_host_id NUMBER;
        v_company_id NUMBER;
        v_private_details VARCHAR2(30000);
        v_public_details VARCHAR2(30000);
        v_is_public BOOLEAN;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        UPDATE tt.event
        SET    demoted = 1
        WHERE  id = p_event_id;

        SELECT e.ticket_id, t.host_id, t.company_id
        INTO   v_ticket_id, v_host_id, v_company_id
        FROM   tt.event e, tt.ticket t
        WHERE  e.id = p_event_id AND e.ticket_id = t.id;

        v_public_details := NULL;
        v_private_details := 'Event ' || p_event_id || ' demoted';
        v_is_public := FALSE;

        -- NOTE: for the time being, we do not write history events for this...
        -- Add a history event of type "event demotion" (100011)
        -- add_history_event(v_history_event_id, v_ticket_id, 100011, v_host_id, v_company_id, v_public_details, v_private_details, v_is_public, sysdate, p_contact_id);

    END demote_event;

------------------------------------------------------------------------------------------------------------------------------------
-- promote_event
------------------------------------------------------------------------------------------------------------------------------------
    PROCEDURE promote_event(p_event_id NUMBER, p_contact_id NUMBER) AS

        v_history_event_id NUMBER;
        v_ticket_id NUMBER;
        v_host_id NUMBER;
        v_company_id NUMBER;
        v_private_details VARCHAR2(30000);
        v_public_details VARCHAR2(30000);
        v_is_public BOOLEAN;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        UPDATE tt.event
        SET    demoted = 0
        WHERE  id = p_event_id;

        SELECT e.ticket_id, t.host_id, t.company_id
        INTO   v_ticket_id, v_host_id, v_company_id
        FROM   tt.event e, tt.ticket t
        WHERE  e.id = p_event_id AND e.ticket_id = t.id;

        v_public_details := NULL;
        v_private_details := 'Event ' || p_event_id || ' promoted';
        v_is_public := FALSE;

        -- NOTE: for the time being, we do not write history events for this...
        -- Add a history event of type "event promotion" (100012)
        -- add_history_event(v_history_event_id, v_ticket_id, 100012, v_host_id, v_company_id, v_public_details, v_private_details, v_is_public, sysdate, p_contact_id);

    END promote_event;

END event_interface;
/
