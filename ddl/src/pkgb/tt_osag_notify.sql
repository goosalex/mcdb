--liquibase formatted sql logicalFilePath:pkgb/tt_osag_notify.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE BODY TT.OSAG_NOTIFY IS
-------------------------------------------------------------------------------
/* This procedure sends notifications to registered listeners of this event.
 *
 * Parameters:
 *
 * p_event_notification_type_id : ID of the event notification type
 * p_ticket_id                  : ID of the ticket
 * p_login_id                   : ID of the login
 * p_event_type_name            : name of the event type
 * p_host_name                  : name of the host these notifications are sent for
 * p_eventdate                  : the date when the event occured
 * p_event_details_public       : public details of the event
 * p_email_message_subject      : subject of the email notification message
 * p_email_message_body         : body of the email notification message
 * p_sms_message                : SMS notification message
 * p_is_public_event            : specifies whether the event is a public/private event
 *
 *****************************************************************************/
    PROCEDURE send_notification_by_type(p_event_notification_type_id NUMBER,
                                        p_ticket_id NUMBER,
                                        p_login_id NUMBER,
                                        p_event_type_name VARCHAR2,
                                        p_host_name VARCHAR2,
                                        p_eventdate DATE,
                                        p_event_details_public VARCHAR2,
                                        p_email_message_subject VARCHAR2,
                                        p_email_message_body VARCHAR2,
                                        p_sms_message VARCHAR2,
                                        p_is_public_event DECIMAL DEFAULT 1);
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
/* This procedure composes the email notification message which tells the
 * customer what kind of event has happened.
 *
 * Parameters:
 *
 * p_message_subject         : subject of the message which is composed by the method
 * p_message                 : message which is composed by this method
 * p_ticket_id               : ID of associated ticket
 * p_ticket_subject          : subject of the ticket
 * p_ticket_type_name        : type of the ticket (e.g. incident)
 * p_customer_reference      : customer reference string (for email subject)
 * p_host_name               : name of the host
 * p_event_type_id           : id of the event type
 * p_event_type_name         : event type name
 * p_event_subject           : subject (extracted from the public event details)
 * p_eventdate               : the date the event occured
 * p_status_valid_until_date : date until the ticket status is valid
 * p_details_public          : the public details of the event
 * p_details_private         : the private details of the event
 * p_company_id              : id of the company the ticket belongs to (used to build the
 *                              company-scoped Reports link, cf. MC-32584); can be NULL
 *
 *****************************************************************************/
    PROCEDURE compose_email_msg(p_message_subject OUT VARCHAR2,
                                p_message OUT VARCHAR2,
                                p_ticket_id NUMBER,
                                p_ticket_subject VARCHAR2,
                                p_ticket_type_name VARCHAR2,
                                p_customer_reference VARCHAR2,
                                p_host_name VARCHAR2,
                                p_event_type_id NUMBER,
                                p_event_type_name VARCHAR2,
                                p_event_subject VARCHAR2,
                                p_eventdate DATE,
                                p_status_valid_until_date DATE,
                                p_details_public VARCHAR2,
                                p_details_private VARCHAR2,
                                p_emergency_flag tt.ticket.emergency%TYPE,
                                p_company_id NUMBER);
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
/* This function composes the SMS notification message which tells the
 * customer what kind of event has happened.
 *
 * Parameters:
 *
 * p_ticket_id               : ID of associated ticket
 * p_host_name               : name of the host
 * p_event_type_id           : id of the event type
 * p_event_type_name         : event type name
 * p_eventdate               : the date the event occured
 * p_status_valid_until_date : date until the ticket status is valid
 * p_ticket_subject          : subject of the ticket
 *
 *****************************************************************************/
    FUNCTION compose_sms_msg(p_ticket_id NUMBER,
                             p_host_name VARCHAR2,
                             p_event_type_id NUMBER,
                             p_event_type_name VARCHAR2,
                             p_eventdate DATE,
                             p_status_valid_until_date DATE,
                             p_ticket_subject VARCHAR2,
                             p_emergency_flag tt.ticket.emergency%TYPE) RETURN VARCHAR2;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
/* This procedure sends notifications to the local emergency contacts in case of an
 * connectivity related event.
 *
 * Parameters:
 *
 * p_event_id                : ID of the event
 * p_event_type_id           : ID of the event type
 * p_ticket_id               : ID of the ticket
 * p_host_id                 : id of the host these notifications are sent for
 * p_host_name               : name of the host these notifications are sent for
 * p_customer_reference      : customer reference string (for email subject)
 * p_company_id              : id of the target company
 * p_service_id              : id of the affected service
 * p_eventdate               : Timestamp of the ticket event
 * p_status_valid_until_date : date until the ticket status is valid
 * p_ticket_subject          : subject of the ticket
 * p_notified_cust           : OUT variable to indicate wether customer was notified
 *
 *****************************************************************************/
    PROCEDURE notify_local_contacts(p_event_id NUMBER,
                                    p_event_type_id NUMBER,
                                    p_ticket_id NUMBER,
                                    p_host_id NUMBER,
                                    p_host_name VARCHAR2,
                                    p_customer_reference VARCHAR2,
                                    p_company_id NUMBER,
                                    p_service_id NUMBER,
                                    p_eventdate DATE,
                                    p_status_valid_until_date DATE,
                                    p_ticket_subject VARCHAR2,
                                    p_notified_cust OUT BOOLEAN);
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
/* This function composes the message which is sent to local contacts
 * in case of connectivity related events.
 *
 * Parameters:
 *
 * p_ticket_id              : ID of the ticket
 * p_event_type_name        : name of the event type
 * p_host_name              : name of the host these notifications are sent for
 * p_eventdate              : Timestamp of the ticket event
 *
 *****************************************************************************/
    FUNCTION compose_local_contact_message(p_ticket_id NUMBER,
                                           p_event_type_name VARCHAR2,
                                           p_host_name VARCHAR2,
                                           p_eventdate DATE) RETURN VARCHAR2;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
/* This procedure sends notifications to an isp support contact in case of an
 * isp outage or connection up event.
 *
 * Parameters:
 *
 * p_event_id               : ID of the event
 * p_event_type_id          : ID of the event type
 * p_ticket_id              : ID of the ticket
 * p_host_id                : id of the host these notifications are sent for
 * p_host_name              : name of the host these notifications are sent for
 * p_customer_reference     : customer reference string (for email subject)
 *
 *****************************************************************************/
    PROCEDURE notify_isp(p_event_id NUMBER,
                         p_event_type_id NUMBER,
                         p_ticket_id NUMBER,
                         p_host_id NUMBER,
                         p_host_name VARCHAR2,
                         p_customer_reference VARCHAR2);
-------------------------------------------------------------------------------

--------------------------------------------------------------------------
/* This function returns the isp link id assigned to the spedified host.
 *
 * Parameters:
 *
 * p_host_id    : id of the host to find the isp link for
 *
 ***********************************************************************/
    FUNCTION get_isp_link_id_for_host_id(p_host_id NUMBER) RETURN NUMBER;
--------------------------------------------------------------------------

-------------------------------------------------------------------------------
/* This function composes the message which is sent to the isp support contact
 * in case of an isp outage event.
 *
 * Parameters:
 *
 * p_ticket_id              : ID of the ticket
 * p_isp_link_id            : ID of the ISP link connected to the specified host
 * p_host_id                : ID of the host
 * p_event_id               : ID of the event
 * p_isp_router_ip          : IP of the host's isp router
 * p_host_name              : name of the host
 *
 *****************************************************************************/
    FUNCTION get_message_for_isp_outage(p_ticket_id NUMBER,
                                        p_isp_link_id NUMBER,
                                        p_host_id NUMBER,
                                        p_event_id NUMBER,
                                        p_isp_router_ip VARCHAR2,
                                        p_host_name VARCHAR2) RETURN VARCHAR2;
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
/* This function composes the message which is sent to the isp support contact
 * in case of a connection up event.
 *
 * Parameters:
 *
 * p_ticket_id              : ID of the ticket
 * p_isp_link_id            : ID of the ISP link connected to the specified host
 * p_host_id                : ID of the host
 * p_event_id               : ID of the event
 * p_isp_router_ip          : IP of the host's isp router
 * p_host_name              : name of the host
 *
 *****************************************************************************/
    FUNCTION get_message_for_connection_up(p_ticket_id NUMBER,
                                           p_isp_link_id NUMBER,
                                           p_host_id NUMBER,
                                           p_event_id NUMBER,
                                           p_isp_router_ip VARCHAR2,
                                           p_host_name VARCHAR2) RETURN VARCHAR2;
-------------------------------------------------------------------------------

--------------------------------------------------------------------------
/* This fuction formats a customer reference string. So far it just adds
 * brackets to the string.
 *
 * Parameters:
 *
 * p_customer_reference : customer reference string
 *
 ***********************************************************************/
    FUNCTION format_customer_reference(p_customer_reference VARCHAR2) RETURN VARCHAR2;
--------------------------------------------------------------------------

/* This fuction looks up the name of the event notification type and returns
 * it.
 *
 * Parameters:
 *
 * p_event_notification_type_id : ID of the event notification type to
 *                                look up the name for
 *
 ***********************************************************************/
    FUNCTION get_notification_type_name(p_event_notification_type_id NUMBER)
        RETURN event_notification_type.name%TYPE;
--------------------------------------------------------------------------

--------------------------------------------------------------------------
/* This function returns the email footer.
 *
 * Parameters:
 *
 * p_ticket_id              : ID of associated ticket
 *
 ***********************************************************************/
    FUNCTION email_footer(p_ticket_id NUMBER) RETURN VARCHAR2;
-------------------------------------------------------------------------

--------------------------------------------------------------------------
/* This function returns the email signature.
 *
 ***********************************************************************/
    FUNCTION email_signature RETURN VARCHAR2;
-------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- procedure event_notify
-------------------------------------------------------------------------------
    PROCEDURE event_notify(p_event_id NUMBER,
                           p_ticket_id NUMBER DEFAULT NULL,
                           p_question VARCHAR2 DEFAULT NULL) AS

        S_PREFIX CONSTANT VARCHAR2(64) := 'tt.osag_notify.event_notify(): ';
        MAX_EVENT_NOTIFY_COUNT CONSTANT NUMBER := 5;
        ELAPSED_TIME_BARRIER CONSTANT BINARY_INTEGER := 500; -- [100th of a second, cs] --> means 2s

        v_host_name mss.host.name%TYPE;
        v_host_id NUMBER;
        v_service_id NUMBER;
        v_ticket_worker_id NUMBER;
        v_service_type_id NUMBER;
        v_company_id NUMBER;
        v_company_unit_id NUMBER;
        v_ticket_id NUMBER;
        v_ticket_type_id NUMBER;
        v_ticket_type_name tt.ticket_type.name%TYPE;
        v_ticket_subject tt.ticket.subject%TYPE;
        v_emergency_flag tt.ticket.emergency%TYPE;
        v_status_valid_until_date tt.ticket.status_valid_until_date%TYPE;
        v_eventdate DATE;
        v_details VARCHAR2(30000);
        v_details_private VARCHAR2(30000);
        v_event_subject VARCHAR2(300);
        v_customer_reference tt.ticket.customer_reference%TYPE;
        v_event_notify_count_cust tt.ticket.event_notify_count%TYPE;
        v_event_notify_count_osag tt.ticket.event_notify_count_osag%TYPE;
        v_event_type_id tt.event_type.id%TYPE;
        v_event_type_group_id tt.event_type_group.id%TYPE;
        v_event_type_name VARCHAR2(300);
        v_peer_contact_name VARCHAR2(200);
        v_event_source_id NUMBER;
        v_notified_customer BOOLEAN;
        v_notified_osag BOOLEAN;
        v_local_contact_notified BOOLEAN;
        v_number_of_permissions NUMBER;
        v_notif_event_is_public DECIMAL;
        v_is_public_event NUMBER;
        v_email_message_subject VARCHAR2(512);
        v_email_message_body VARCHAR2(30000);
        v_sms_message VARCHAR2(8000);


        -- We fear that the cursor statements in this procedure might consume a lot of processing time
        -- on our DB. To keep an eye on the elapsed time we try to measure the processing time used by
        -- this procedure. We disregard the amount of time which is used to send the notifications.
        -- Therefore, we measure the time used to send notifications and subtract it in the
        -- end of the procedure from the elapsed time.
        -- If the elapsed time exceeds a certain threshold we log it accordingly.
        v_procedure_threshold BINARY_INTEGER;
        v_send_noti_threshold BINARY_INTEGER;
        v_elapsed_time_procedure BINARY_INTEGER;
        v_elapsed_time_send_noti BINARY_INTEGER;


    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        v_procedure_threshold := DBMS_UTILITY.GET_TIME;
        v_elapsed_time_send_noti := 0;
        v_notified_customer := FALSE;
        v_notified_osag := FALSE;

        v_ticket_id := p_ticket_id;

        -- if v_ticket_id is null: get the ticket_id from the DB
        IF (v_ticket_id IS NULL) THEN
            SELECT e.ticket_id
            INTO v_ticket_id
            FROM tt.event e
            WHERE e.id = p_event_id;
        END IF;

        -- get the event details
        SELECT NVL(event.host_id, ticket.host_id), NVL(h2s.service_id, ticket.mss_service_id), event.type_id,  event.eventdate, event.details_public, event.details_private, event.public_event,
               ticket.event_notify_count, ticket.event_notify_count_osag, ticket.customer_reference, ticket.subject, ticket.status_valid_until_date, ticket.emergency,
               event_type.name, NVL(h.name, 'unspecified'), event_type.source
        INTO v_host_id, v_service_id, v_event_type_id, v_eventdate, v_details, v_details_private, v_is_public_event,
            v_event_notify_count_cust, v_event_notify_count_osag, v_customer_reference, v_ticket_subject, v_status_valid_until_date, v_emergency_flag,
            v_event_type_name, v_host_name, v_event_source_id
        FROM tt.event, tt.ticket, tt.event_type, mss.host h, MSS.host2service h2s
        WHERE event.id = p_event_id
          AND ticket.id = event.ticket_id
          AND event.type_id = event_type.id
          AND h.id(+) = COALESCE(event.host_id, ticket.host_id) -- If the event has no host_id, use the ticket's host_id
          AND h2s.host_id(+) = COALESCE(event.host_id, ticket.host_id); -- If the event has no host_id, use the ticket's host_id

        -- event_source.id = 1 => 'automatic' events
        -- do not send notifications for automatic events if max count reached
        IF (v_event_notify_count_cust >= MAX_EVENT_NOTIFY_COUNT AND v_event_notify_count_osag >= MAX_EVENT_NOTIFY_COUNT  AND v_event_source_id = 1) THEN
            plog.debug(S_PREFIX || 'No more notifications for this ticket for automatic events because max notify count reached: ' || MAX_EVENT_NOTIFY_COUNT);
            RETURN;
        END IF;

        v_event_subject := SUBSTR(v_details, 1, 100);
        IF (INSTR(v_event_subject, CHR(10)) > 0) THEN
            v_event_subject := SUBSTR(v_event_subject, 1, INSTR(v_event_subject, CHR(10)) - 1);
        END IF;

        -- For change request approved by engineer (50020), append approver name from peer_contact
        IF (v_event_type_id = 50020) THEN
            BEGIN
                SELECT c.firstname || ' ' || c.lastname
                INTO v_peer_contact_name
                FROM stop.contact c, tt.event e
                WHERE e.id = p_event_id
                  AND c.id = e.peer_contact_id;
                v_event_type_name := v_event_type_name || ': ' || v_peer_contact_name;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN NULL;
            END;
        END IF;

        -- do not send notifications to registered listeners if we suppressed notifications during a service window
        -- but still send questions
        IF (NOT is_notify_suppressor_active(v_host_id) OR v_event_type_id = 50008) THEN

            -- get the ticket_type, company_id and service_id from the ticket
            -- notice: the company_id and service_id can be null
            SELECT t.company_id, t.type_id, t.worker_id
            INTO v_company_id, v_ticket_type_id, v_ticket_worker_id
            FROM tt.ticket t
            WHERE t.id = v_ticket_id;

            SELECT ty.name
            INTO v_ticket_type_name
            FROM tt.ticket_type ty
            WHERE ty.id = v_ticket_type_id;

            IF (v_service_id IS NOT NULL) THEN
                SELECT company_unit_id, service_type_id
                INTO v_company_unit_id, v_service_type_id
                FROM mss.service
                WHERE service.id = v_service_id;

                -- if the company unit is still not set, select the default company unit of the company
                IF (v_company_unit_id IS NULL) THEN
                    SELECT c.default_company_unit_id
                    INTO v_company_unit_id
                    FROM stop.company c, mss.service s
                    WHERE s.id = v_service_id
                      AND s.company_id = c.id;
                END IF;
            ELSIF (v_company_id IS NOT NULL) THEN
                -- if no service is available for the ticket
                -- the company unit in charge is the default one
                -- cf. MC-1570
                SELECT c.default_company_unit_id INTO v_company_unit_id
                FROM stop.company c
                WHERE v_company_id = c.id;
                v_service_type_id := NULL;
            ELSE
                v_company_unit_id := NULL;
                v_service_type_id := NULL;
            END IF;

            plog.debug(S_PREFIX || 'event_type_name: ' || v_event_type_name || ', host.id: ' || v_host_id || ', company_id: ' || v_company_id || ', service_id: ' || v_service_id || ', company_unit_id: ' || v_company_unit_id
                || ', service_type_id: ' || v_service_type_id);

            v_notif_event_is_public := 1; --add notification events as public events by default

            -- send isp notification if event type is 10003 (isp outage)
            IF (v_event_type_id = 10003) THEN
                notify_isp(p_event_id,
                           v_event_type_id,
                           v_ticket_id,
                           v_host_id,
                           v_host_name,
                           v_customer_reference);
            END IF;

            -- determine event_type_group_id of event
            BEGIN
                SELECT event_type2event_type_group.event_type_group_id
                INTO v_event_type_group_id
                FROM tt.event, tt.event_type2event_type_group
                WHERE event.id = p_event_id
                  AND event.type_id = event_type2event_type_group.event_type_id;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    v_event_type_group_id := NULL;
            END;

            -- send local contact notification if event is connectivity related
            -- (id of connectivity related event group is 1)
            -- and we know the host that triggered the event
            IF (v_event_type_group_id = 1 AND v_host_id IS NOT NULL) THEN
                v_local_contact_notified := FALSE;
                notify_local_contacts(p_event_id,
                                      v_event_type_id,
                                      v_ticket_id,
                                      v_host_id,
                                      v_host_name,
                                      v_customer_reference,
                                      v_company_id,
                                      v_service_id,
                                      v_eventdate,
                                      v_status_valid_until_date,
                                      v_ticket_subject,
                                      v_local_contact_notified);
                IF v_local_contact_notified THEN
                    v_notified_customer := TRUE;
                END IF;
            END IF;

            -- compose the SMS message
            v_sms_message := compose_sms_msg(v_ticket_id,
                                             v_host_name,
                                             v_event_type_id,
                                             v_event_type_name,
                                             v_eventdate,
                                             v_status_valid_until_date,
                                             v_ticket_subject,
                                             v_emergency_flag);

            -- compose the email message
            -- NOTE: v_email_message_subject and v_email_message_body are out parameters!
            compose_email_msg(v_email_message_subject,
                              v_email_message_body,
                              v_ticket_id,
                              v_ticket_subject,
                              v_ticket_type_name,
                              v_customer_reference,
                              v_host_name,
                              v_event_type_id,
                              v_event_type_name,
                              v_event_subject,
                              v_eventdate,
                              v_status_valid_until_date,
                              v_details,
                              v_details_private,
                              v_emergency_flag,
                              v_company_id);

            -- notifications for *NON*-OSAG users

            -- event_source.id = 1 => 'automatic' events
            -- do not send notifications to customers for automatic events if max count for customers is reached
            IF (v_event_notify_count_cust >= MAX_EVENT_NOTIFY_COUNT AND v_event_source_id = 1) THEN
                plog.debug(S_PREFIX || 'No more customer notifications for this ticket for automatic events because max notify count reached: ' || MAX_EVENT_NOTIFY_COUNT);
            ELSIF (v_details IS NULL OR v_is_public_event = 0) THEN
                -- do not notify customers if no public info available or the event is private
                NULL;
            ELSIF(v_service_id IS NULL) THEN
                DECLARE

                    -- define a cursor that selects all event notifications
                    -- that are defined for this event (exclude OSAG logins, they are treated below)

                    CURSOR notify_cur IS
                        SELECT DISTINCT en.login_id, en.event_notification_type_id
                        FROM tt.event_notification en, tt.event_type2event_type_group et2etg, auth.login l, auth.permission p
                        WHERE (en.event_type_id = v_event_type_id
                            OR (en.event_type_group_id = et2etg.event_type_group_id
                                AND et2etg.event_type_id = v_event_type_id))
                          AND en.login_id = l.id
                          AND l.company_id != 6  -- exclude OSAG logins from this cursor (they are treated separately)
                          AND en.company_id = l.company_id -- for non-OSAG logins the company of the notification must be the same as the logins company
                          AND en.login_id = p.login_id

                          -- company monitor users only may receive company wide notifications
                          AND p.company_id = en.company_id
                          AND p.company_unit_id IS NULL AND p.service_id IS NULL AND p.user_unit_id IS NULL
                          AND p.role_id = 1

                          -- only company wide notifications
                          -- or such defined on the default company unit
                          -- (cf. above where v_company_unit_id is assigned in the case
                          --  when no service is defined for the ticket)
                          AND (en.company_unit_id IS NULL OR en.company_unit_id = v_company_unit_id) AND en.service_id IS NULL AND en.service_type_id IS NULL
                          AND (en.company_id = v_company_id) -- for non-OSAG logins the en.company_id should be set (is therefore never null)
                          AND (en.ticket_id IS NULL OR en.ticket_id = v_ticket_id)
                          AND (en.ticket_type_id IS NULL OR en.ticket_type_id = v_ticket_type_id);

                    notify_rec notify_cur%ROWTYPE;

                BEGIN
                    FOR notify_rec in notify_cur
                        LOOP -- loop over the selected event notifications
                    v_notified_customer := TRUE;

                    v_send_noti_threshold := DBMS_UTILITY.GET_TIME;
                    send_notification_by_type(notify_rec.event_notification_type_id,
                                              v_ticket_id,
                                              notify_rec.login_id,
                                              v_event_type_name,
                                              v_host_name,
                                              v_eventdate,
                                              v_details,
                                              v_email_message_subject,
                                              v_email_message_body,
                                              v_sms_message,
                                              v_notif_event_is_public);
                    v_elapsed_time_send_noti := v_elapsed_time_send_noti + (DBMS_UTILITY.GET_TIME - v_send_noti_threshold);

                        END LOOP; -- end loop over the selected event notifications
                END;
            ELSE -- v_service_id is not null
                DECLARE

                    -- define a cursor that selects all event notifications
                    -- that are defined for this event (exclude OSAG logins, they are treated below)

                    CURSOR notify_cur IS
                        SELECT DISTINCT en.login_id, en.event_notification_type_id
                        FROM tt.event_notification en, tt.event_type2event_type_group et2etg, auth.login l, auth.mv_service_access mvsa
                        WHERE (en.event_type_id = v_event_type_id
                            OR (en.event_type_group_id = et2etg.event_type_group_id
                                AND et2etg.event_type_id = v_event_type_id))
                          AND en.login_id = l.id
                          AND l.company_id != 6  -- exclude OSAG logins from this cursor (they are treated separately)
                          AND en.company_id = l.company_id -- for non-OSAG logins the company of the notification must be the same as the logins company
                          AND en.login_id = mvsa.login_id
                          -- When the v_service_id is null, we can not check the user permissions for the service
                          -- with the mv_service_access table. In this case we ignore this restriction here
                          -- (v_service_id IS NULL OR ...) but check this later on in the loop (->see comment there).
                          -- role_id = 1 is 'mc-cust-monitor'
                          AND (mvsa.service_id = v_service_id AND mvsa.role_id =1 )
                          AND (en.company_id = v_company_id) -- for non-OSAG logins the en.company_id should be set (is therefore never null)
                          AND (en.service_id IS NULL OR en.service_id = v_service_id)
                          AND (en.company_unit_id IS NULL OR en.company_unit_id = v_company_unit_id)
                          AND (en.service_type_id IS NULL OR en.service_type_id = v_service_type_id)
                          AND (en.ticket_id IS NULL OR en.ticket_id = v_ticket_id)
                          AND (en.ticket_type_id IS NULL OR en.ticket_type_id = v_ticket_type_id);

                    notify_rec notify_cur%ROWTYPE;

                BEGIN
                    FOR notify_rec in notify_cur
                        LOOP -- loop over the selected event notifications
                    v_notified_customer := TRUE;

                    v_send_noti_threshold := DBMS_UTILITY.GET_TIME;
                    send_notification_by_type(notify_rec.event_notification_type_id,
                                              v_ticket_id,
                                              notify_rec.login_id,
                                              v_event_type_name,
                                              v_host_name,
                                              v_eventdate,
                                              v_details,
                                              v_email_message_subject,
                                              v_email_message_body,
                                              v_sms_message,
                                              v_notif_event_is_public);
                    v_elapsed_time_send_noti := v_elapsed_time_send_noti + (DBMS_UTILITY.GET_TIME - v_send_noti_threshold);

                        END LOOP; -- end loop over the selected event notifications
                END;
            END IF;


            -- notifications for OSAG users

            -- event_source.id = 1 => 'automatic' events
            -- do not send notifications to customers for automatic events if max count for customers is reached
            IF (v_event_notify_count_osag >= MAX_EVENT_NOTIFY_COUNT AND v_event_source_id = 1) THEN
                plog.debug(S_PREFIX || 'No more notifications for OSAG employees for this ticket for automatic events because max notify count reached: ' || MAX_EVENT_NOTIFY_COUNT);
            ELSE
                -- For events which are generated by customer services we make notifications
                -- of OSAG employees private. Our customers should not see that we have
                -- notifications on their services.
                IF (v_company_id IS NOT NULL AND v_company_id != 6) THEN
                    v_notif_event_is_public := 0;
                END IF;

                DECLARE

                    -- define a cursor that selects all event notifications
                    -- that are defined for this event and belong to OSAG users

                    CURSOR notify_cur IS
                        SELECT DISTINCT en.login_id, en.event_notification_type_id
                        FROM tt.event_notification en, tt.event e, tt.event_type2event_type_group et2etg, auth.login l, auth.permission p
                        WHERE e.id = p_event_id
                          AND (en.event_type_id = e.type_id
                            OR (en.event_type_group_id = et2etg.event_type_group_id
                                AND et2etg.event_type_id = e.type_id))
                          AND en.login_id = l.id
                          AND l.company_id = 6  -- only OSAG logins (notifications for other logins are sent with the cursor above)
                          AND l.id = p.login_id
                          AND p.role_id = 6 -- the OSAG login must have the mc-osag-monitor role
                          AND (en.company_id IS NULL OR en.company_id = v_company_id)
                          AND (en.service_id IS NULL OR en.service_id = v_service_id)
                          AND (en.company_unit_id IS NULL OR en.company_unit_id = v_company_unit_id)
                          AND (en.service_type_id IS NULL OR en.service_type_id = v_service_type_id)
                          AND (en.ticket_id IS NULL OR en.ticket_id = v_ticket_id)
                          AND (en.ticket_type_id IS NULL OR en.ticket_type_id = v_ticket_type_id)
                          AND (en.regexp IS NULL OR REGEXP_LIKE(e.details_public, en.regexp))
                          AND (en.only_if_worker = 0 OR l.contact_id = v_ticket_worker_id); -- check ticket worker when only_if_worker is not 0

                    notify_rec notify_cur%ROWTYPE;

                BEGIN
                    FOR notify_rec in notify_cur
                        LOOP -- loop over the selected event notifications
                    v_notified_osag := TRUE;
                    v_send_noti_threshold := DBMS_UTILITY.GET_TIME;
                    send_notification_by_type(notify_rec.event_notification_type_id,
                                              v_ticket_id,
                                              notify_rec.login_id,
                                              v_event_type_name,
                                              v_host_name,
                                              v_eventdate,
                                              v_details,
                                              v_email_message_subject,
                                              v_email_message_body,
                                              v_sms_message,
                                              v_notif_event_is_public);
                    v_elapsed_time_send_noti := v_elapsed_time_send_noti + (DBMS_UTILITY.GET_TIME - v_send_noti_threshold);
                        END LOOP; -- end loop over the selected event notifications
                END;
            END IF;
        END IF;

        IF v_notified_customer THEN
            -- increase notify count for this ticket (on a per event basis)

            IF (v_event_notify_count_cust IS NULL) THEN
                v_event_notify_count_cust := 1;
            ELSE
                v_event_notify_count_cust := v_event_notify_count_cust + 1;
            END IF;

            UPDATE ticket
            SET event_notify_count = v_event_notify_count_cust
            WHERE id = v_ticket_id;

            IF (v_event_notify_count_cust = MAX_EVENT_NOTIFY_COUNT) THEN
                -- write event that there will be no more notifications
                -- make the notify entry in the ticket
                INSERT INTO event
                (id, type_id, ticket_id, eventdate, details_public)
                VALUES (event_sequence.NextVal,
                        20010, v_ticket_id,
                        sysdate,
                        'notification limit (' || MAX_EVENT_NOTIFY_COUNT || ') reached' || CHR(10) ||
                        'There will be no more notifications for system events added to this ticket.');

            END IF;
        END IF;

        IF v_notified_osag THEN
            -- increase notify count for this ticket (on a per event basis)

            IF (v_event_notify_count_osag IS NULL) THEN
                v_event_notify_count_osag := 1;
            ELSE
                v_event_notify_count_osag := v_event_notify_count_osag + 1;
            END IF;

            UPDATE ticket
            SET event_notify_count_osag = v_event_notify_count_osag
            WHERE id = v_ticket_id;

            IF (v_event_notify_count_osag = MAX_EVENT_NOTIFY_COUNT) THEN
                -- write event that there will be no more notifications
                -- make the notify entry in the ticket
                INSERT INTO event
                (id, type_id, ticket_id, eventdate, details_private, public_event)
                VALUES (event_sequence.NextVal,
                        20010, v_ticket_id,
                        sysdate,
                        'notification limit (' || MAX_EVENT_NOTIFY_COUNT || ') reached' || CHR(10) ||
                        'There will be no more notifications for OSAG employees for system events added to this ticket.',
                        0);  -- no public event

            END IF;
        END IF;

        -- write a warning if the elapsed time of this procedure (minus the time we used to send the notifications) exceeds the barrier
        v_elapsed_time_procedure := DBMS_UTILITY.GET_TIME - v_procedure_threshold;
        IF ((v_elapsed_time_procedure - v_elapsed_time_send_noti) > ELAPSED_TIME_BARRIER) THEN
            plog.warning(S_PREFIX || 'procedure elapsed time (' || (v_elapsed_time_procedure - v_elapsed_time_send_noti)*10 || 'ms) exceeded the barrier ('
                || ELAPSED_TIME_BARRIER*10 || 'ms), the queries in this procedure should be optimized');
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            plog.warning(S_PREFIX || 'sending of notification for event ID ' || p_event_id || ' and ticket ID ' || p_ticket_id || ' failed');
            plog.warning(S_PREFIX || 'exception: ' || sqlerrm);

    END event_notify;

-------------------------------------------------------------------------------
-- procedure send_test_notification
-------------------------------------------------------------------------------
    PROCEDURE send_test_notification(p_destination_address VARCHAR2,
                                     p_notification_type_id NUMBER,
                                     p_ticket_id NUMBER,
                                     p_ticket_subject VARCHAR2,
                                     p_host_name VARCHAR2,
                                     p_event_type_id NUMBER,
                                     p_eventdate TIMESTAMP WITH TIME ZONE,
                                     p_contact_last_name VARCHAR2 DEFAULT NULL,
                                     p_contact_first_name VARCHAR2 DEFAULT NULL) IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'tt.osag_notify.send_test_notification(): ';
        S_REPLY_TO_ADDR VARCHAR2(32)   := 'support@open.ch';
        S_FROM_ADDR VARCHAR2(32) := 'monitoring@open.ch';

        v_event_type_name tt.event_type.name%TYPE;
        v_message_subject VARCHAR2(4000);
        v_message VARCHAR2(4000);
        v_message_prefix VARCHAR2(512);

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        SELECT name
        INTO v_event_type_name
        FROM tt.event_type et
        WHERE et.id = p_event_type_id;

        v_message_prefix := ' ---------------------------------------------------------------------- ' || CHR(10) ||
                            '|                   THIS IS ONLY A TEST NOTIFICATION                   |' || CHR(10) ||
                            ' ----------------------------------------------------------------------'  || CHR(10) || CHR(10);


        IF (p_notification_type_id = 1) THEN
            -- notification type is 1 - SMS
            v_message := compose_sms_msg(p_ticket_id,
                                         p_host_name,
                                         p_event_type_id,
                                         v_event_type_name,
                                         p_eventdate,
                                         p_eventdate + 1,
                                         p_ticket_subject,
                                         0 -- no emergency
                );

            OSAG_MSG.send_sms(p_destination_address, 'TEST - ' || v_message);

            plog.notice(S_PREFIX || 'test notification (SMS) sent to ' || p_contact_first_name || ' ' || p_contact_last_name ||
                        ' (' || p_destination_address || ')' );
            plog.notice(S_PREFIX || p_destination_address || ' - TEST - ' || v_message);
        ELSIF (p_notification_type_id = 2) THEN
            compose_email_msg(v_message_subject, -- out parameter
                              v_message,         -- out parameter
                              p_ticket_id,
                              p_ticket_subject,
                              'test ticket',
                              NULL,  --no customer reference
                              p_host_name,
                              p_event_type_id,  --
                              v_event_type_name,
                              p_ticket_subject,
                              p_eventdate,
                              p_eventdate + 1,
                              'This is a test notification.',
                              'This is a test notification',
                              0, -- no emergency
                              6 -- no real company available here, use the OSAG company as a placeholder for test notifications
                );

            -- compose message body
            IF (p_contact_last_name IS NOT NULL AND p_contact_first_name IS NOT NULL) THEN
                v_message := 'Dear ' || p_contact_first_name || ' ' || p_contact_last_name  || ',' || CHR(10) || CHR(10) || v_message;
            ELSE
                v_message := 'Dear customer,' || CHR(10)|| CHR(10) || v_message;
            END IF;

            OSAG_MSG.send_mail(S_REPLY_TO_ADDR, S_FROM_ADDR, NULL, p_destination_address, v_message_subject, v_message_prefix || v_message);

            plog.notice(S_PREFIX || 'test notification (email) sent to ' || p_contact_first_name || ' ' || p_contact_last_name ||
                        ' (' || p_destination_address || ')' );
        END IF;

    END send_test_notification;

-------------------------------------------------------------------------------
-- procedure delete_notifications_for_login
-------------------------------------------------------------------------------
    PROCEDURE delete_notifications_for_login(p_login_id NUMBER) IS

        -- this cursor selects all ticket ids for which the login has notifications
        CURSOR notification_cursor IS
            SELECT DISTINCT en.ticket_id
            FROM tt.event_notification en
            WHERE en.login_id = p_login_id
              AND en.ticket_id IS NOT NULL;

        notification_record notification_cursor%ROWTYPE;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        FOR notification_record in notification_cursor
            LOOP -- loop over the selected event notifications
        -- delete notifications for the selected ticket and login
                delete_ticket_notifications(notification_record.ticket_id, p_login_id, 'because the user was deleted');
            END LOOP;
        -- delete the remaining (not ticket relevant) notifications of this login
        DELETE FROM tt.event_notification WHERE login_id = p_login_id;
    END delete_notifications_for_login;

-------------------------------------------------------------------------------
-- procedure delete_ticket_notifications
-------------------------------------------------------------------------------
    PROCEDURE delete_ticket_notifications(p_ticket_id NUMBER,
                                          p_login_id NUMBER DEFAULT NULL,
                                          p_event_details_suffix VARCHAR DEFAULT NULL) IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'tt.osag_notify.delete_ticket_notifications(): ';

        -- define a cursor that selects all event notifications
        -- that are defined for this ticket
        CURSOR notification_cursor IS
            SELECT en.id, en.login_id, en.event_notification_type_id, c.lastname, c.firstname,
                   c.mobile, c.email, l.company_id AS login_company_id, t.company_id AS ticket_company_id
            FROM tt.event_notification en, auth.login l, stop.contact c, ticket t
            WHERE en.ticket_id = p_ticket_id
              AND t.id = p_ticket_id
              AND l.id = en.login_id
              AND (p_login_id IS NULL OR en.login_id = p_login_id) -- if p_login id is set we select only ticket notifications from this login
              AND c.id = l.contact_id;

        notification_record notification_cursor%ROWTYPE;
        -- For each deleted ticket notification an entry is made either in details_public or details_private of the deletion event.
        -- A default entry is generally not longer than 60 characters so we can collect all deletion events in one single
        -- event because the field details_public VARCHAR2(4000) provides space for about 65 deletion events and is therefore assumed
        -- to provide enough space.
        v_event_details_public VARCHAR2(4000);
        v_event_details_private VARCHAR2(4000);

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        FOR notification_record in notification_cursor
            LOOP -- loop over the selected event notifications
        IF (notification_record.login_company_id = 6 AND notification_record.ticket_company_id  != 6) THEN
            -- notification for OSAG logins in non-OSAG tickets are private
            v_event_details_private := v_event_details_private || '  -deleted ' || get_notification_type_name(notification_record.event_notification_type_id) ||
                                       ' notification for ' || notification_record.firstname || ' ' || notification_record.lastname || CHR(10);
        ELSE
            v_event_details_public := v_event_details_public || '  -deleted ' || get_notification_type_name(notification_record.event_notification_type_id) ||
                                      ' notification for ' || notification_record.firstname || ' ' || notification_record.lastname || CHR(10);
        END IF;
        DELETE FROM tt.event_notification en WHERE en.id = notification_record.id;
            END LOOP;

        --delete the content of the details public/private fields if no deletion event is inserted in the specific field
        IF (v_event_details_public IS NOT NULL) THEN
            v_event_details_public := v_event_details_public || p_event_details_suffix;
        END IF;
        IF (v_event_details_private IS NOT NULL) THEN
            v_event_details_private := v_event_details_private || p_event_details_suffix;
        END IF;

        -- make a ticket attribute change entry in the ticket which tells which ticket notifications
        -- have been deleted
        IF (v_event_details_public IS NOT NULL OR v_event_details_private IS NOT NULL) THEN
            TT.TICKET_INTERFACE.change_notification(p_ticket_id,
                                                    v_event_details_public,
                                                    v_event_details_private,
                                                    NULL);  -- no contact id specified for this change
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            plog.warning(S_PREFIX || 'deletion of notifications for ticket ' || p_ticket_id || ' failed');
            plog.warning(S_PREFIX || 'exception: ' || sqlerrm);

    END delete_ticket_notifications;

-------------------------------------------------------------------------------
-- procedure add_notification_event
-------------------------------------------------------------------------------
    PROCEDURE add_notification_event(p_ticket_id NUMBER,
                                     p_event_type_id NUMBER,
                                     p_text VARCHAR2,
                                     p_contact_id NUMBER,
                                     p_peer_contact_id NUMBER DEFAULT NULL,
                                     p_is_public_event DECIMAL DEFAULT 1) IS

        v_details_public VARCHAR2(30000);
        v_details_private VARCHAR2(30000);

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        IF (p_is_public_event = 1) THEN
            v_details_public := p_text;
            v_details_private := null;
        ELSE
            v_details_public := null;
            v_details_private := p_text;
        END IF;
        -- make the notify entry in the ticket
        INSERT INTO event
        (id,contact_id,peer_contact_id,type_id,ticket_id,eventdate,details_public,details_private,public_event)
        VALUES (event_sequence.NextVal,
                p_contact_id,
                p_peer_contact_id,
                p_event_type_id,
                p_ticket_id,
                sysdate,
                v_details_public,
                v_details_private,
                p_is_public_event);

    END add_notification_event;

-------------------------------------------------------------------------------
-- function is_notify_suppressor_active
-------------------------------------------------------------------------------
    FUNCTION is_notify_suppressor_active(p_host_id NUMBER) RETURN BOOLEAN IS
        v_entry_exists INTEGER;
        v_host_id tt.ticket.host_id%TYPE;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- we disable here all notifications for hosts attached to an active service window of this ticket. Otherwise notification may occur because the event was added to
        -- another ticket by event_interface.newevent().
        SELECT COUNT(*)
        INTO v_entry_exists
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
          AND (m.disable_notification = 1 OR cm.disable_notification = 1) AND h2s.host_id = p_host_id;

        IF (v_entry_exists > 0) THEN
            RETURN TRUE;
        END IF;
        RETURN FALSE;
    END is_notify_suppressor_active;

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-- private procedures and functions
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- procedure send_notification_by_type
-------------------------------------------------------------------------------
    PROCEDURE send_notification_by_type(p_event_notification_type_id NUMBER,
                                        p_ticket_id NUMBER,
                                        p_login_id NUMBER,
                                        p_event_type_name VARCHAR2,
                                        p_host_name  VARCHAR2,
                                        p_eventdate DATE,
                                        p_event_details_public VARCHAR2,
                                        p_email_message_subject VARCHAR2,
                                        p_email_message_body VARCHAR2,
                                        p_sms_message VARCHAR2,
                                        p_is_public_event DECIMAL DEFAULT 1) AS

        S_PREFIX CONSTANT VARCHAR2(64) := 'tt.osag_notify.send_notification_by_type(): ';
        S_REPLY_TO_ADDR VARCHAR2(32)   := 'support@open.ch';
        S_FROM_ADDR VARCHAR2(32) := 'monitoring@open.ch';

        v_contact_id NUMBER;
        v_target_address VARCHAR2(50);
        v_contact_last_name stop.contact.lastname%TYPE;
        v_contact_first_name stop.contact.firstname%TYPE;
        v_email_message_body VARCHAR2(30000);
        v_envelope_from VARCHAR2(64);

        -- smtp headers to mark the mail message as auto generated
        v_smtp_headers OSAG_MSG.smtp_headers_t := OSAG_MSG.smtp_headers_t();
        v_smtp_header_rec OSAG_MSG.smtp_header_t;

    BEGIN
        -- this is hardcoded stuff and does not use the event_action table
        IF p_event_notification_type_id = 1 THEN
            -- notification type is 1 - SMS
            SELECT contact.id,  contact.mobile, contact.lastname, contact.firstname
            INTO v_contact_id, v_target_address, v_contact_last_name, v_contact_first_name
            FROM auth.login, stop.contact
            WHERE login.id = p_login_id
              AND contact.id = login.contact_id;

            IF (v_target_address IS NOT NULL) THEN
                -- send an SMS to the specified target address
                plog.notice(S_PREFIX || 'sending SMS to ' || v_contact_first_name || ' ' || v_contact_last_name || ' (login[' || p_login_id || ']), ' || v_target_address );

                OSAG_MSG.send_sms(v_target_address, p_sms_message);

                add_notification_event(p_ticket_id, 20003,
                                       'sent to ' || v_contact_first_name || ' ' || v_contact_last_name || ', ' || v_target_address ||  CHR(10) ||
                                       p_sms_message, NULL, v_contact_id, p_is_public_event);
            ELSE
                plog.notice(S_PREFIX || 'event notification not sent to auth.login[' || p_login_id || '], assigned contact has no mobile number specified');
            END IF;
        END IF; --end of SMS notification

        IF p_event_notification_type_id = 2 THEN
            -- notification type is 2 - email
            SELECT contact.id,  contact.email, contact.lastname, contact.firstname
            INTO v_contact_id, v_target_address, v_contact_last_name, v_contact_first_name
            FROM auth.login, stop.contact
            WHERE login.id = p_login_id
              AND contact.id = login.contact_id;

            IF (v_target_address IS NOT NULL) THEN
                plog.notice(S_PREFIX || 'sending email to ' || v_contact_first_name || ' ' || v_contact_last_name || ' (login[' || p_login_id || ']), ' || v_target_address);

                -- smtp headers to mark the mail message as auto generated
                -- Find a way to declared this as constant and be my PL/SQL hero of the day
                v_smtp_headers.extend(2);

                v_smtp_header_rec.h_name := 'Auto-Submitted';
                v_smtp_header_rec.h_value := 'auto-generated';

                v_smtp_headers(1) := v_smtp_header_rec;

                v_smtp_header_rec.h_name := 'Precedence';
                v_smtp_header_rec.h_value := 'bulk';

                v_smtp_headers(2) := v_smtp_header_rec;

                -- compose message body
                IF (v_contact_last_name IS NOT NULL AND v_contact_first_name IS NOT NULL) THEN
                    v_email_message_body := 'Dear ' || v_contact_first_name || ' ' || v_contact_last_name  || ',' || CHR(10) || CHR(10) || p_email_message_body;
                ELSE
                    v_email_message_body := 'Dear customer,' || CHR(10)|| CHR(10) || p_email_message_body;
                END IF;

                IF (p_is_public_event = 1) THEN
                    v_envelope_from := 'ttbounce+' || p_ticket_id || '@open.ch';
                ELSE
                    v_envelope_from := 'ttbounce-private+' || p_ticket_id || '@open.ch';
                END IF;

                OSAG_MSG.send_mail(S_REPLY_TO_ADDR, S_FROM_ADDR, v_envelope_from, v_target_address, p_email_message_subject, v_email_message_body, v_smtp_headers);

                add_notification_event(p_ticket_id, 20001,
                                       'sent to ' || v_contact_first_name || ' ' || v_contact_last_name || ', ' || v_target_address || CHR(10) ||
                                       v_email_message_body, NULL, v_contact_id, p_is_public_event);
            ELSE
                plog.notice(S_PREFIX || 'event notification not sent to auth.login[' || p_login_id || '], assigned contact has no email address specified');
            END IF;
        END IF; --end of email notification

    END send_notification_by_type;

-------------------------------------------------------------------------------
-- procedure compose_email_msg
-------------------------------------------------------------------------------
    PROCEDURE compose_email_msg(p_message_subject OUT VARCHAR2,
                                p_message OUT VARCHAR2,
                                p_ticket_id NUMBER,
                                p_ticket_subject VARCHAR2,
                                p_ticket_type_name VARCHAR2,
                                p_customer_reference VARCHAR2,
                                p_host_name VARCHAR2,
                                p_event_type_id NUMBER,
                                p_event_type_name VARCHAR2,
                                p_event_subject VARCHAR2,  --currently unused
                                p_eventdate DATE,
                                p_status_valid_until_date DATE,
                                p_details_public VARCHAR2,
                                p_details_private VARCHAR2,
                                p_emergency_flag tt.ticket.emergency%TYPE,
                                p_company_id NUMBER) IS

        v_message_subject VARCHAR2(512);
        v_subject_prefix VARCHAR2(512);
        v_message VARCHAR2(30000);
        v_subject_template VARCHAR2(512);
        v_message_template VARCHAR2(30000);
        v_email_msg_template_id NUMBER;
        v_details VARCHAR2(2000);
        v_emergency_text VARCHAR2(20) := '';

    BEGIN
        SELECT email_message_template_id
        INTO v_email_msg_template_id
        FROM tt.event_type et
        WHERE et.id = p_event_type_id;

        SELECT subject_template, message_template
        INTO v_subject_template, v_message_template
        FROM tt.event_type_message etm
        WHERE etm.id = v_email_msg_template_id;

        IF p_emergency_flag = 1 THEN
            v_emergency_text := 'EMERGENCY: ';
        END IF;

        -- compose message subject
        v_subject_prefix := '[OS-' || p_ticket_id || ']' || format_customer_reference(p_customer_reference);
        v_subject_template := REPLACE(v_subject_template, '$#TICKET_SUBJECT#$', p_ticket_subject);
        v_subject_template := REPLACE(v_subject_template, '$#EVENT_TYPE_NAME#$', p_event_type_name);
        v_subject_template := REPLACE(v_subject_template, '$#TICKET_TYPE#$', p_ticket_type_name);
        v_subject_template := REPLACE(v_subject_template, '$#EMERGENCY#$', v_emergency_text);

        IF (p_host_name IS NOT NULL AND p_host_name != 'unspecified') THEN
            v_subject_template := REPLACE(v_subject_template, '$#HOST_NAME#$', p_host_name);
        ELSE
            v_subject_template := REPLACE(v_subject_template, '$#HOST_NAME#$', '<unspecified service>');
        END IF;

        -- because of different session timezones, the timezone indicator is slightly hacked...
        v_subject_template := REPLACE(v_subject_template, '$#STATUS_VALID_UNTIL#$', TO_CHAR(p_status_valid_until_date,'DD.MM.YYYY HH24:MI') || ' ' || TO_CHAR(SYSTIMESTAMP AT TIME ZONE 'EUROPE/ZURICH', 'TZD'));

        p_message_subject := v_subject_prefix || ' ' || v_subject_template;

        -- because of different session timezones, the timezone indicator is slightly hacked...
        v_message_template := REPLACE(v_message_template, '$#EVENT_DATE#$', TO_CHAR(p_eventdate,'DD.MM.YYYY HH24:MI') || ' ' || TO_CHAR(SYSTIMESTAMP AT TIME ZONE 'EUROPE/ZURICH', 'TZD'));
        v_message_template := REPLACE(v_message_template, '$#EVENT_TYPE_NAME#$', p_event_type_name);
        v_message_template := REPLACE(v_message_template, '$#TICKET_SUBJECT#$', p_ticket_subject);
        v_message_template := REPLACE(v_message_template, '$#EMERGENCY#$', v_emergency_text);

        IF (p_host_name IS NOT NULL AND p_host_name != 'unspecified') THEN
            v_message_template := REPLACE(v_message_template, '$#HOST_NAME#$', p_host_name);
        ELSE
            v_message_template := REPLACE(v_message_template, '$#HOST_NAME#$', '<unspecified service>');
        END IF;

        v_message_template := REPLACE(v_message_template, '$#TICKET_ID#$', p_ticket_id);
        -- because of different session timezones, the timezone indicator is slightly hacked...
        v_message_template := REPLACE(v_message_template, '$#STATUS_VALID_UNTIL#$', TO_CHAR(p_status_valid_until_date,'DD.MM.YYYY HH24:MI') || ' ' || TO_CHAR(SYSTIMESTAMP AT TIME ZONE 'EUROPE/ZURICH', 'TZD'));

        -- company-scoped link to the Reports view, cf. MC-32584
        v_message_template := REPLACE(v_message_template, '$#COMPANY_ID#$', p_company_id);

        -- Replace the first line placeholder of the public details into the message
        v_message_template := REPLACE(v_message_template, '$#PUBLIC_DETAILS_FIRST_LINE#$', SUBSTR(p_details_public, 1, INSTR(p_details_public, CHR(10)) - 1));

        -- if it's a question event (ID 50008), replace the question
        IF (p_event_type_id = 50008) THEN
            v_message_template := SUBSTR(REPLACE(v_message_template, '$#QUESTION#$', p_details_public), 1, 29000);
        END IF;

        -- for rating events we also inject the event details cut down to 2000 CHARs maximal
        -- public details for customer rating, private details for engineer ratings
        IF (p_event_type_id = 30012) THEN
            -- only take the first 2000 chars as the message otherwise gets too long
            v_details := SUBSTR(p_details_public, 1, 2000);
            v_message_template := REPLACE(v_message_template, '$#PUBLIC_DETAILS#$', v_details);
        ELSIF (p_event_type_id = 50004) THEN
            -- only take the first 2000 chars as the message otherwise gets too long
            v_details := SUBSTR(p_details_private, 1, 2000);
            v_message_template := REPLACE(v_message_template, '$#PRIVATE_DETAILS#$', v_details);
        END IF;

        v_message := v_message || v_message_template || CHR(10) || CHR(10) ||  email_footer(p_ticket_id);

        p_message := v_message;

    END compose_email_msg;

-------------------------------------------------------------------------------
-- function compose_sms_msg
-------------------------------------------------------------------------------
    FUNCTION compose_sms_msg(p_ticket_id NUMBER,
                             p_host_name VARCHAR2,
                             p_event_type_id NUMBER,
                             p_event_type_name VARCHAR2,
                             p_eventdate DATE,
                             p_status_valid_until_date DATE,
                             p_ticket_subject VARCHAR2,
                             p_emergency_flag tt.ticket.emergency%TYPE) RETURN VARCHAR2 AS

        S_SMS_MSG_SIZE CONSTANT NUMBER := 160;

        v_message VARCHAR2(4000);
        v_message_template VARCHAR2(4000);
        v_sms_msg_template_id NUMBER;
        v_max_ticket_subject_size NUMBER;
        v_ticket_subject tt.ticket.subject%TYPE;
        v_emergency_text VARCHAR2(20) := '';

    BEGIN
        SELECT sms_message_template_id
        INTO v_sms_msg_template_id
        FROM tt.event_type et
        WHERE et.id = p_event_type_id;

        SELECT  message_template
        INTO v_message_template
        FROM tt.event_type_message etm
        WHERE etm.id = v_sms_msg_template_id;

        IF p_emergency_flag = 1 THEN
            v_emergency_text := 'EM: ';
        END IF;

        IF (p_host_name IS NOT NULL AND p_host_name != 'unspecified') THEN
            v_message_template := REPLACE(v_message_template, '$#HOST_NAME#$', p_host_name);
        ELSE
            v_message_template := REPLACE(v_message_template, '$#HOST_NAME#$', '<unspecified service>');
        END IF;

        v_message_template := REPLACE(v_message_template, '$#EVENT_DATE#$', TO_CHAR(p_eventdate,'DD.MM.YYYY HH24:MI') || ' ' || TO_CHAR(SYSTIMESTAMP AT TIME ZONE 'EUROPE/ZURICH', 'TZD'));
        v_message_template := REPLACE(v_message_template, '$#EVENT_TYPE_NAME#$', p_event_type_name);
        v_message_template := REPLACE(v_message_template, '$#TICKET_ID#$', p_ticket_id);
        v_message_template := REPLACE(v_message_template, '$#STATUS_VALID_UNTIL#$', TO_CHAR(p_status_valid_until_date,'DD.MM.YYYY HH24:MI') || ' ' || TO_CHAR(SYSTIMESTAMP AT TIME ZONE 'EUROPE/ZURICH', 'TZD'));

        v_message_template := v_message_template ||  ' - Open Systems Mission Control';

        -- If the ticket subject message would lead the SMS to be longer than S_SMS_MSG_SIZE we have to
        -- abbreviate the message. It is assumed that v_max_ticket_subject_size >= 3 and that the string
        -- ##TICKET_SUBJECT## does not occure more than once in the template message.
        v_max_ticket_subject_size := S_SMS_MSG_SIZE - LENGTH(v_message_template) + LENGTH('$#TICKET_SUBJECT#$') - LENGTH(v_emergency_text);
        IF (LENGTH(p_ticket_subject) > v_max_ticket_subject_size) THEN
            v_ticket_subject := SUBSTR(p_ticket_subject, 0, v_max_ticket_subject_size -3) || '...';
        ELSE
            v_ticket_subject := p_ticket_subject;
        END IF;

        v_message_template := REPLACE(v_message_template, '$#TICKET_SUBJECT#$', v_ticket_subject);
        v_message_template := REPLACE(v_message_template, '$#EMERGENCY#$', v_emergency_text);

        v_message := v_message_template;

        RETURN v_message;
    END compose_sms_msg;

-------------------------------------------------------------------------------
-- procedure notify_local_contacts
-------------------------------------------------------------------------------
    PROCEDURE notify_local_contacts(p_event_id NUMBER,
                                    p_event_type_id NUMBER,
                                    p_ticket_id NUMBER,
                                    p_host_id NUMBER,
                                    p_host_name VARCHAR2,
                                    p_customer_reference VARCHAR2,
                                    p_company_id NUMBER,
                                    p_service_id NUMBER,
                                    p_eventdate DATE,
                                    p_status_valid_until_date DATE,
                                    p_ticket_subject VARCHAR2,
                                    p_notified_cust OUT BOOLEAN) IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'tt.osag_notify.notify_local_contacts(): ';
        S_REPLY_TO_ADDR VARCHAR(32)    := 'support@open.ch';
        S_FROM_ADDR VARCHAR(32)        := 'monitoring@open.ch';

        v_message_subject VARCHAR2(4000);
        v_message VARCHAR2(4000);
        v_sms_message VARCHAR2(200);
        v_service_name mss.service_type.name%TYPE;
        v_company_name stop.company.name%TYPE;
        v_event_type_name tt.event_type.name%TYPE;
        v_envelope_from VARCHAR2(64);

        -- create list of on-site intervention contacts to notify
        CURSOR local_contact_cur IS
            SELECT c.*, lcn.event_notification_type_id
            FROM stop.contact c, mss.local_contact lc, mss.address a, mss.host h, mss.local_contact_notification lcn
            WHERE h.address_id = a.id
              AND a.id = lc.address_id
              AND lc.contact_id = c.id
              AND lc.local_contact_type_id = 1 -- on-site intervention contacts only
              AND lc.id = lcn.local_contact_id
              AND h.id = p_host_id
            ORDER BY lc.priority;

    BEGIN

        SELECT st.name
        INTO v_service_name
        FROM mss.service_type st, mss.service s
        WHERE s.service_type_id = st.id
          AND s.id = p_service_id;

        SELECT name
        INTO v_company_name
        FROM stop.company
        WHERE id = p_company_id;

        SELECT name
        INTO v_event_type_name
        FROM tt.event_type
        WHERE id = p_event_type_id;

        v_message_subject := '[OS-' || p_ticket_id ||']' || format_customer_reference(p_customer_reference) || v_event_type_name;
        v_message := compose_local_contact_message(p_ticket_id, v_event_type_name, p_host_name, p_eventdate);
        v_sms_message := compose_sms_msg(p_ticket_id, p_host_name, p_event_type_id, v_event_type_name,
                                         p_eventdate, p_status_valid_until_date, p_ticket_subject, 0); -- no support for emergency flag for local contact notifications

        p_notified_cust := FALSE;
        FOR local_contact_rec IN local_contact_cur LOOP
                IF (local_contact_rec.event_notification_type_id = 1 AND (local_contact_rec.mobile IS NOT NULL)) THEN
                    -- SMS
                    plog.notice(S_PREFIX || 'sending sms to local emergency contact: '||local_contact_rec.mobile);
                    OSAG_MSG.send_sms(local_contact_rec.mobile, v_sms_message);
                    TT.OSAG_NOTIFY.add_notification_event(p_ticket_id, 20003,
                                                          'sent to ' || local_contact_rec.mobile || ' (local contact sms notification)' || CHR(10) ||
                                                          CHR(10) || CHR(10) || v_sms_message, NULL, local_contact_rec.id);
                    p_notified_cust := TRUE;
                ELSIF (local_contact_rec.event_notification_type_id = 2 AND (local_contact_rec.email IS NOT NULL)) THEN
                    -- EMAIL
                    plog.notice(S_PREFIX || 'sending email to local emergency contact: '||local_contact_rec.email);
                    v_envelope_from := 'ttbounce+' || p_ticket_id || '@open.ch';
                    OSAG_MSG.send_mail(S_REPLY_TO_ADDR, S_FROM_ADDR, v_envelope_from, local_contact_rec.email, v_message_subject, v_message);
                    TT.OSAG_NOTIFY.add_notification_event(p_ticket_id, 20001,
                                                          'sent to ' || local_contact_rec.email || ' (local contact email notification)' || CHR(10) ||
                                                          v_message_subject || CHR(10) || CHR(10) || v_message, NULL, local_contact_rec.id);
                    p_notified_cust := TRUE;
                END IF;
            END LOOP;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            plog.err(S_PREFIX || 'found no data for event ' || p_event_id);
            RETURN;
    END notify_local_contacts;

-------------------------------------------------------------------------------
-- function compose_local_contact_message
-------------------------------------------------------------------------------
    FUNCTION compose_local_contact_message(p_ticket_id NUMBER,
                                           p_event_type_name VARCHAR2,
                                           p_host_name VARCHAR2,
                                           p_eventdate DATE) RETURN VARCHAR2 IS
    BEGIN
        RETURN 'This is an automatically generated email to inform you that the following event has occurred:' ||
               CHR(10) || CHR(10) ||
               'Ticket:   ' || p_ticket_id || CHR(10) ||
               'Event:    ' || p_event_type_name || CHR(10) ||
               'Host:     ' || p_host_name || CHR(10) ||
               'Date:     ' || TO_CHAR(p_eventdate,'DD.MM.YYYY HH24:MI') || ' ' ||
               TO_CHAR(SYSTIMESTAMP AT TIME ZONE 'EUROPE/ZURICH', 'TZD') || CHR(10) || CHR(10) ||
               'If you have access to the Open Systems Ticket System, you can view' || CHR(10) ||
               'the complete ticket using the following link:' || CHR(10) || CHR(10) ||
               'https://control.open.ch/mc/ticket/' || p_ticket_id || CHR(10) || CHR(10) ||
               email_signature;
    END compose_local_contact_message;

-------------------------------------------------------------------------------
-- procedure notify_isp
-------------------------------------------------------------------------------
    PROCEDURE notify_isp(p_event_id NUMBER,
                         p_event_type_id NUMBER,
                         p_ticket_id NUMBER,
                         p_host_id NUMBER,
                         p_host_name VARCHAR2,
                         p_customer_reference VARCHAR2) IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'tt.osag_notify.notify_isp(): ';
        S_REPLY_TO_ADDR VARCHAR2(32)   := 'support@open.ch';
        S_FROM_ADDR VARCHAR2(32) := 'monitoring@open.ch';

        v_isp_link_id mss.isp_link.id%TYPE;
        v_isp_notification mss.isp_link.isp_notification%TYPE;
        v_isp_support_mail stop.contact.email%TYPE;
        v_isp_contact_id stop.contact.id%TYPE;
        v_isp_router_ip mss.isp_link.router_ip_address1%TYPE;
        v_message_subject VARCHAR2(4000);
        v_message VARCHAR2(4000);
        v_envelope_from VARCHAR2(64);


    BEGIN

        v_isp_link_id := get_isp_link_id_for_host_id(p_host_id);

        IF (v_isp_link_id IS NULL) THEN
            RETURN; -- return if no isp link can be found
        END IF;

        BEGIN
            SELECT i.isp_notification, i.router_ip_address1, c.email, c.id
            INTO v_isp_notification, v_isp_router_ip, v_isp_support_mail, v_isp_contact_id
            FROM mss.isp_link i, stop.contact c
            WHERE i.id = v_isp_link_id
              AND i.support_id = c.id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_isp_support_mail := NULL;
            WHEN OTHERS THEN
                plog.err(S_PREFIX||'unknown error: '||sqlerrm);
                v_isp_support_mail := NULL;
        END;

        IF (v_isp_notification = 0) THEN
            RETURN; -- return if isp outage notification is disabled for this link
        END IF;

        -- 'unknown@during.import.tld' was the default email address during the checklist import
        IF (v_isp_support_mail IS NOT NULL AND v_isp_support_mail != 'unknown@during.import.tld') THEN

            IF p_event_type_id = 10003 THEN -- isp outage
                v_message_subject := '[OS-' || p_ticket_id ||']' || format_customer_reference(p_customer_reference) ||
                                     ' ISP outage detected for ' || mss.osag_ip.num2ip(v_isp_router_ip);
                v_message := get_message_for_isp_outage(p_ticket_id, v_isp_link_id, p_host_id,
                                                        p_event_id, mss.osag_ip.num2ip(v_isp_router_ip), p_host_name);
            END IF;

            IF p_event_type_id = 10100 THEN -- connection up
                v_message_subject := '[OS-' || p_ticket_id ||']' || format_customer_reference(p_customer_reference) ||
                                     ' connection up for ' || mss.osag_ip.num2ip(v_isp_router_ip);
                v_message := get_message_for_connection_up(p_ticket_id, v_isp_link_id, p_host_id,
                                                           p_event_id, mss.osag_ip.num2ip(v_isp_router_ip), p_host_name);
            END IF;
            v_envelope_from := 'ttbounce+' || p_ticket_id || '@open.ch';

            plog.notice(S_PREFIX || 'sending email to isp support contact: '||v_isp_support_mail);

            OSAG_MSG.send_mail(S_REPLY_TO_ADDR, S_FROM_ADDR, v_envelope_from, v_isp_support_mail, v_message_subject, v_message);

            TT.OSAG_NOTIFY.add_notification_event(p_ticket_id, 20001,
                                                  'sent to ' || v_isp_support_mail || ' (isp email notification)' || CHR(10) ||
                                                  v_message_subject || CHR(10) || CHR(10) || v_message, NULL, v_isp_contact_id);
        END IF;
    END notify_isp;

-------------------------------------------------------------------------------
-- function get_isp_link_id_for_host_id
-------------------------------------------------------------------------------
    FUNCTION get_isp_link_id_for_host_id(p_host_id NUMBER) RETURN NUMBER IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'tt.osag_notify.get_isp_link_id_for_host_id(): ';

        v_isp_link_id NUMBER;

    BEGIN

        BEGIN

            SELECT mss.interface2isp_link.isp_link_id
            INTO v_isp_link_id
            FROM mss.host, mss.interface, mss.interface2isp_link
            WHERE mss.host.id = p_host_id
              AND mss.interface.host_id = mss.host.id
              AND mss.interface2isp_link.interface_id = mss.interface.id
              AND mss.interface.mgmtaccess = 1;

        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RETURN NULL;
            WHEN TOO_MANY_ROWS THEN
                plog.err(S_PREFIX||'host['||p_host_id
                    ||'] has too many ISP links');
                RETURN NULL;
            WHEN OTHERS THEN
                plog.err(S_PREFIX||'unknown error: '||sqlerrm);
                RETURN NULL;
        END;

        RETURN v_isp_link_id;
    END get_isp_link_id_for_host_id;

-------------------------------------------------------------------------------
-- function get_message_for_isp_outage
-------------------------------------------------------------------------------
    FUNCTION get_message_for_isp_outage(p_ticket_id NUMBER,
                                        p_isp_link_id NUMBER,
                                        p_host_id NUMBER,
                                        p_event_id NUMBER,
                                        p_isp_router_ip VARCHAR2,
                                        p_host_name VARCHAR2) RETURN VARCHAR2 IS
        v_message VARCHAR2(4000);
        v_contact_list VARCHAR2(4000);
        v_acc_mgr_lastname stop.contact.lastname%TYPE;
        v_acc_mgr_firstname stop.contact.firstname%type;
        v_isp_account_number mss.isp_link.account_number%TYPE;
        v_isp_line_number mss.isp_link.line_number%TYPE;
        v_isp_company_id NUMBER;
        v_isp_company_name stop.company.name%TYPE;
        v_company_name stop.company.name%TYPE;
        v_city_name mss.city.name%TYPE;
        v_country_name mss.country.name%TYPE;
        v_connection_down_date VARCHAR2(40);

        -- cursor to fetch all local emergency contacts
        -- with name, phone (direct) and email address
        -- magic number: local_contact_id 1 is Emergency contact
        CURSOR contact_cur IS
            SELECT c.id, c.firstname, c.lastname, c.direct, c.email
            FROM stop.contact c, mss.host h, mss.local_contact lc
            WHERE h.id = p_host_id AND
                    lc.address_id = h.address_id AND lc.contact_id = c.id AND
                (c.direct IS NOT NULL OR c.email IS NOT NULL) AND
                    lc.local_contact_type_id = 1
            ORDER BY lc.priority;

    BEGIN
        BEGIN
            -- select account manager lastname and firstname, account number, line number, isp company id
            SELECT NVL(stop.contact.lastname, ''), NVL(stop.contact.firstname, ''), mss.isp_link.account_number,
                   mss.isp_link.line_number, mss.isp_link.company_id
            INTO v_acc_mgr_lastname, v_acc_mgr_firstname, v_isp_account_number, v_isp_line_number, v_isp_company_id
            FROM stop.contact, mss.isp_link
            WHERE mss.isp_link.id = p_isp_link_id
              AND mss.isp_link.account_manager_id = stop.contact.id(+);
        EXCEPTION
            WHEN OTHERS THEN
                v_acc_mgr_lastname := '';
        END;


        IF v_isp_company_id IS NOT NULL THEN
            BEGIN
                -- select the isp company name according to the company id from the previous query
                SELECT company.name
                INTO v_isp_company_name
                FROM stop.company
                WHERE company.id = v_isp_company_id;
            EXCEPTION
                WHEN OTHERS THEN
                    NULL;
            END;
        END IF;

        BEGIN
            -- select the customer company name,  host city name, host country name
            SELECT company.name, city.name, country.name
            INTO v_company_name, v_city_name, v_country_name
            FROM stop.company, mss.host, mss.address, mss.city, mss.country
            WHERE host.id = p_host_id
              AND host.service_company_id = company.id
              AND host.address_id = address.id(+)
              AND address.city_id = city.id(+)
              AND city.country_id = country.id(+);
        EXCEPTION
            WHEN OTHERS THEN
                NULL;
        END;

        BEGIN
            -- select the connection interrupt down date, we can not use the event_id because
            -- that is still null until the newevent call for the ISP outage event (+notification)
            -- has been added (see mc.monitoring), therefore search via service_id and assume there's
            -- one open outage for that service
            SELECT to_char(from_tz(cast(down_date as timestamp), 'EUROPE/ZURICH'), 'DD Mon YYYY, HH24:MI TZH:TZM')
            INTO v_connection_down_date
            FROM mc.connection_interrupt_open cio
            WHERE cio.host_id = p_host_id;
        EXCEPTION
            WHEN OTHERS THEN
                NULL;
        END;

        v_message := 'Dear ' || v_isp_company_name || ' support,' || CHR(10) ||
                     CHR(10) ||
                     'The following local loop';
        IF (v_isp_company_name IS NOT NULL) THEN
            v_message := v_message || ' operated by ' || v_isp_company_name;
        END IF;

        v_contact_list := '';

        -- create list of local emergency contacts
        FOR contact_rec in contact_cur LOOP
                v_contact_list := v_contact_list || CHR(10) || '- ' || contact_rec.firstname || ' ' || contact_rec.lastname || ' (';
                IF (contact_rec.direct IS NOT NULL) THEN
                    v_contact_list := v_contact_list || 'phone: ' || contact_rec.direct;
                END IF;
                IF (contact_rec.email IS NOT NULL) THEN
                    IF (contact_rec.direct IS NOT NULL) THEN
                        v_contact_list := v_contact_list || ', ';
                    END IF;
                    v_contact_list := v_contact_list || 'email: ' || contact_rec.email;
                END IF;
                v_contact_list := v_contact_list || ')';
            END LOOP;


        v_message := v_message ||
                     ' is currently down.' || CHR(10) ||
                     'The local loop details are provided below.' || CHR(10) ||
                     'Please investigate and resolve the ' ||
                     'problem according to the SLA provided.' || CHR(10) ||
                     CHR(10);

        IF (v_contact_list IS NOT NULL) THEN
            v_message := v_message || 'Should you need support by the affected customer site, please contact:' ||
                         v_contact_list || CHR(10) || CHR(10);
        END IF;

        v_message := v_message || 'In case of further technical information required, do not hesitate' || CHR(10) ||
                     'to contact Open Systems Mission Control by replying to this e-mail.' || CHR(10) ||CHR(10) ||
                     'Best regards,' || CHR(10) ||
                     'Mission Control' || CHR(10) ||
                     CHR(10) ||
                     'ISP Router IP: ' || p_isp_router_ip || ' (' || p_host_name || ')' || CHR(10) ||
                     'Location:      ';
        IF (v_city_name IS NOT NULL) THEN
            v_message := v_message || v_city_name || ', ' || v_country_name || CHR(10);
        ELSE
            v_message := v_message || 'n/a' || CHR(10);
        END IF;

        v_message := v_message ||
                     'Customer:      ' || NVL(v_company_name, 'n/a') || CHR(10) ||
                     'Account no:    ' || NVL(v_isp_account_number, 'n/a') || CHR(10) ||
                     'Line no:       ' || NVL(v_isp_line_number, 'n/a') || CHR(10) ||
                     'Account mgr:   ';
        IF (v_acc_mgr_lastname IS NULL) THEN
            v_message := v_message  || 'n/a' || CHR(10);
        ELSE
            v_message := v_message || v_acc_mgr_lastname || ' ' || v_acc_mgr_firstname || CHR(10);
        END IF;

        v_message := v_message ||
                     'Outage start:  ' || NVL(v_connection_down_date, 'n/a') || CHR(10) ||
                     CHR(10) ||
                     'This message was automatically generated.'|| CHR(10) || 'The Internet connectivity ' ||
                     'is measured from Zurich, Switzerland.' || CHR(10) ||
                     email_signature;

        RETURN v_message;
    END get_message_for_isp_outage;

-------------------------------------------------------------------------------
-- function get_message_for_connection_up
-------------------------------------------------------------------------------
    FUNCTION get_message_for_connection_up(p_ticket_id NUMBER,
                                           p_isp_link_id NUMBER,
                                           p_host_id NUMBER,
                                           p_event_id NUMBER,
                                           p_isp_router_ip VARCHAR2,
                                           p_host_name VARCHAR2) RETURN VARCHAR2 IS
        v_message VARCHAR2(4000);
        v_acc_mgr_lastname stop.contact.lastname%TYPE;
        v_acc_mgr_firstname stop.contact.firstname%type;
        v_isp_account_number mss.isp_link.account_number%TYPE;
        v_isp_line_number mss.isp_link.line_number%TYPE;
        v_isp_company_id NUMBER;
        v_isp_company_name stop.company.name%TYPE;
        v_company_name stop.company.name%TYPE;
        v_city_name mss.city.name%TYPE;
        v_country_name mss.country.name%TYPE;

    BEGIN
        BEGIN
            -- select account manager lastname and firstname, account number, line number, isp company id
            SELECT NVL(stop.contact.lastname, ''), NVL(stop.contact.firstname, ''), mss.isp_link.account_number,
                   mss.isp_link.line_number, mss.isp_link.company_id
            INTO v_acc_mgr_lastname, v_acc_mgr_firstname, v_isp_account_number, v_isp_line_number, v_isp_company_id
            FROM stop.contact, mss.isp_link
            WHERE mss.isp_link.id = p_isp_link_id
              AND mss.isp_link.account_manager_id = stop.contact.id(+);
        EXCEPTION
            WHEN OTHERS THEN
                v_acc_mgr_lastname := '';
        END;


        IF v_isp_company_id IS NOT NULL THEN
            BEGIN
                -- select the isp company name according to the company id from the previous query
                SELECT company.name
                INTO v_isp_company_name
                FROM stop.company
                WHERE company.id = v_isp_company_id;
            EXCEPTION
                WHEN OTHERS THEN
                    NULL;
            END;
        END IF;

        BEGIN
            -- select the customer company name,  host city name, host country name
            SELECT company.name, city.name, country.name
            INTO v_company_name, v_city_name, v_country_name
            FROM stop.company, mss.host, mss.address, mss.city, mss.country
            WHERE host.id = p_host_id
              AND host.service_company_id = company.id
              AND host.address_id = address.id(+)
              AND address.city_id = city.id(+)
              AND city.country_id = country.id(+);
        EXCEPTION
            WHEN OTHERS THEN
                NULL;
        END;

        v_message := 'Dear support,' || CHR(10) ||
                     CHR(10) ||
                     'The following local loop,';
        IF (v_isp_company_name IS NOT NULL) THEN
            v_message := v_message || ' provided by ' || v_isp_company_name || ',';
        END IF;
        v_message := v_message ||
                     ' is up again. Thank you for your efforts.' || CHR(10) ||
                     CHR(10) ||
                     'Do not hesitate to contact Open Systems Mission Control by ' ||
                     'replying to this e-mail in case you require further information.' || CHR(10) ||
                     CHR(10) ||
                     'Best regards,' || CHR(10) ||
                     'Mission Control' || CHR(10) ||
                     CHR(10) ||
                     'ISP Router IP: ' || p_isp_router_ip || ' (' || p_host_name || ')' || CHR(10) ||
                     'Location:      ';
        IF (v_city_name IS NOT NULL) THEN
            v_message := v_message || v_city_name || ', ' || v_country_name || CHR(10);
        ELSE
            v_message := v_message || 'n/a' || CHR(10);
        END IF;

        v_message := v_message ||
                     'Customer:      ' || NVL(v_company_name, 'n/a') || CHR(10) ||
                     'Account no:    ' || NVL(v_isp_account_number, 'n/a') || CHR(10) ||
                     'Line no:       ' || NVL(v_isp_line_number, 'n/a') || CHR(10) ||
                     'Account mgr:   ';
        IF (v_acc_mgr_lastname IS NULL) THEN
            v_message := v_message  || 'n/a' || CHR(10);
        ELSE
            v_message := v_message || v_acc_mgr_lastname || ' ' || v_acc_mgr_firstname || CHR(10);
        END IF;

        v_message := v_message ||
                     CHR(10) ||
                     'This message was automatically generated. The Internet connectivity ' ||
                     'is measured from Zurich, Switzerland.' || CHR(10) ||
                     email_signature;

        RETURN v_message;
    END get_message_for_connection_up;

-------------------------------------------------------------------------------
-- function format_customer_reference
-------------------------------------------------------------------------------
    FUNCTION format_customer_reference(p_customer_reference VARCHAR2) RETURN VARCHAR2 IS
        -- the returned string is a little longer than the field tt.ticket.customer_reference (varchar2(64))
        v_prepared_customer_reference VARCHAR2(72);
    BEGIN
        IF (p_customer_reference IS NULL) THEN
            v_prepared_customer_reference := '';
        ELSE
            v_prepared_customer_reference := ' [' || p_customer_reference || ']';
        END IF;
        RETURN v_prepared_customer_reference;
    END format_customer_reference;

-------------------------------------------------------------------------------
-- function get_notification_type_name
-------------------------------------------------------------------------------
    FUNCTION get_notification_type_name(p_event_notification_type_id NUMBER) RETURN event_notification_type.name%TYPE AS

        v_event_notification_type_name event_notification_type.name%TYPE;

    BEGIN
        SELECT name INTO v_event_notification_type_name FROM tt.event_notification_type WHERE id = p_event_notification_type_id;
        RETURN v_event_notification_type_name;
    END get_notification_type_name;

-------------------------------------------------------------------------------
-- function email_footer
-------------------------------------------------------------------------------
    FUNCTION email_footer(p_ticket_id NUMBER) RETURN VARCHAR2 IS
        v_message VARCHAR2(4000);
    BEGIN
        v_message := 'Notification settings can be changed at: https://control.open.ch' || CHR(10) ||
                     CHR(10) ||
                     'Best regards,' || CHR(10) ||
                     'Mission Control' || CHR(10) ||
                     email_signature;
        RETURN v_message;
    END email_footer;

-------------------------------------------------------------------------------
-- function email_signature
-------------------------------------------------------------------------------
    FUNCTION email_signature RETURN VARCHAR2 IS
    BEGIN
        RETURN CHR(10) ||
               '-- ' || CHR(10) ||
               'Open Systems Mission Control'|| CHR(10) || CHR(10) ||
               'E. support@open.ch' || CHR(10) ||
               'T. +800 00 724 000' || CHR(10) ||
               '   +41 58 100 11 11' || CHR(10) ||
               '   1-800-724-2407 (US toll free) ' || CHR(10) ||
               'W. https://control.open.ch';
    END email_signature;

END OSAG_NOTIFY;
/
