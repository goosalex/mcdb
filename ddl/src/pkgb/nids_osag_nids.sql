--liquibase formatted sql logicalFilePath:pkgb/nids_osag_nids.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE BODY NIDS.OSAG_NIDS IS
-- ----------------------------------------------------------------------------------------
-- package constants
-- ----------------------------------------------------------------------------------------
    E_SIG_NOT_FOUND               EXCEPTION;
    E_SENSOR_ID_NOT_FOUND         EXCEPTION;

-- FUNCTION get_signature
-- Purprose: Retrieve signature record given SID and GID
    FUNCTION get_signature(
        i_signature_gid          signature.gid%TYPE,
        i_signature_sid          signature.sid%TYPE)
        RETURN signature%ROWTYPE IS
        l_signature signature%ROWTYPE;
    BEGIN
        SELECT * INTO l_signature FROM signature
        WHERE gid = i_signature_gid AND sid = i_signature_sid;
        RETURN l_signature;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            -- If GID is 501 or 502, then it's normal (local custom signatures)
            IF i_signature_gid = 501 OR i_signature_gid = 502 THEN RETURN NULL;
            ELSE RAISE E_SIG_NOT_FOUND;
            END IF;
    END get_signature;

-- FUNCTION get_signature_class_name
-- Purprose: Retrieve signature class name given signature class id
    FUNCTION get_signature_class_name(i_signature_class_id signature_class.id%TYPE)
        RETURN signature_class.name%TYPE IS
        l_name signature_class.name%TYPE;
    BEGIN
        SELECT name INTO l_name FROM signature_class
        WHERE id = i_signature_class_id;
        RETURN l_name;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN 'unknown';
    END get_signature_class_name;

-- FUNCTION get_sensor_host_id
-- Purprose: Retrieve signature id given SID and GID
-- (note: we also use the sender host id to make sure that it is of the same company)
    FUNCTION get_sensor_host_id(
        i_sensor_name      VARCHAR2,
        i_sender_host_id   mss.host.id%TYPE)
        RETURN mss.host.id%TYPE IS
        l_sensor_host_id     mss.host.id%TYPE;
    BEGIN
        SELECT id INTO l_sensor_host_id FROM mss.host
        WHERE mss.host.name = i_sensor_name AND
                mss.host.service_company_id IN (SELECT service_company_id FROM mss.host WHERE id = i_sender_host_id);
        RETURN l_sensor_host_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RAISE E_SENSOR_ID_NOT_FOUND;
    END get_sensor_host_id;

-- FUNCTION get_direction_name
-- Purprose: Retrieve direction name given id
    FUNCTION get_direction_name(i_direction_id direction.id%TYPE)
        RETURN direction.name%TYPE IS
        l_direction_name     direction.name%TYPE;
    BEGIN
        SELECT name INTO l_direction_name FROM direction
        WHERE id = i_direction_id;
        RETURN l_direction_name;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN 'unknown';
    END get_direction_name;

-- FUNCTION ip_proto_to_string
-- Purprose: Translate IP protocol number to readable string
    FUNCTION ip_proto_to_string(i_protocol NUMBER)
        RETURN VARCHAR IS
        l_protocol   VARCHAR(64);
    BEGIN
        IF i_protocol    IS NULL THEN  l_protocol := 'not available';
        ELSIF i_protocol =  1    THEN  l_protocol := 'ICMP';
        ELSIF i_protocol =  6    THEN  l_protocol := 'TCP';
        ELSIF i_protocol =  17   THEN  l_protocol := 'UDP';
        ELSIF i_protocol =  50   THEN  l_protocol := 'IPSEC ESP';
        ELSIF i_protocol =  51   THEN  l_protocol := 'IPSEC AH';
        ELSIF i_protocol =  89   THEN  l_protocol := 'OSPF';
        ELSE                           l_protocol := 'IP('||i_protocol||')';
        END IF;
        RETURN l_protocol;
    END ip_proto_to_string;

-- PROCEDURE submit_msg
-- Purpose: Submit a NIDS log entry
    PROCEDURE submit_msg_new(
        i_log_date               nids_event.log_date%TYPE,
        i_sensor_name            VARCHAR2,
        i_sender_host_id         nids_event.sender_host_id%TYPE,
        i_event_id               nids_event.local_event_id%TYPE,
        i_tt_event_id            OUT NUMBER,
        i_ticket_id              NUMBER,
        i_signature_gid          signature.gid%TYPE,
        i_signature_sid          signature.sid%TYPE,
        i_signature_class        VARCHAR2,
        i_suppressed             nids_event.suppressed%TYPE,
        i_ip_source_address      nids_event.ip_source_address%TYPE,
        i_ip_source_port         nids_event.ip_source_port%TYPE,
        i_ip_destination_address nids_event.ip_destination_address%TYPE,
        i_ip_destination_port    nids_event.ip_destination_port%TYPE,
        i_ip_protocol            nids_event.ip_protocol%TYPE,
        i_direction_id           nids_event.direction_id%TYPE,
        i_description            VARCHAR2,
        i_escalation_level       INTEGER
    ) IS

        C_PREFIX             CONSTANT VARCHAR2(64)   := 'OSAG_NIDS.submit_msg_new(): ';
        C_EVENT_TYPE_ID_NOTIFICATION CONSTANT NUMBER := 10014;
        C_EVENT_TYPE_ID_ESCALATION CONSTANT NUMBER   := 10002;

        l_signature          signature%ROWTYPE;
        l_description        signature.name%TYPE;
        l_signature_class    signature_class.NAME%TYPE;
        l_sensor_host_id     mss.host.id%TYPE;
        l_pubmsg             VARCHAR2(4000);
        l_privmsg            VARCHAR2(4000);
        l_tt_event_id        NUMBER := NULL;
        l_tt_ticket_id       NUMBER := NULL;
        l_event_type         NUMBER;
        l_ticket_status_id   tt.ticket.status_id%TYPE;
        l_new_ticket_id      tt.ticket.id%TYPE;
        l_disable_event_ticket_id NUMBER;
        l_collect_event_ticket_id NUMBER;
        l_active             mss.host.active%TYPE;

        subject              VARCHAR2(200);
        eventSubject         VARCHAR2(200);
        ticket_type_id       NUMBER;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        l_signature         := get_signature(i_signature_gid, i_signature_sid);
        l_sensor_host_id    := get_sensor_host_id(i_sensor_name, i_sender_host_id);

        IF (i_description IS NULL) AND (l_signature.id IS NOT NULL) THEN
            l_description := l_signature.name;
        ELSE
            l_description := i_description;
        END IF;

        IF (l_signature.id IS NOT NULL) THEN
            l_signature_class := get_signature_class_name(l_signature.signature_class_id);
        ELSE
            l_signature_class := i_signature_class;
        END IF;

        -- prepare public message
        -- note: links for the event, signature and related events will be generated at run
        --       time by Java (tt.Event and HTML)
        l_pubmsg := l_description || chr(10) || chr(10);
        l_pubmsg := l_pubmsg || 'Date            : ' || TO_CHAR(i_log_date, 'YYYY-mm-dd HH24:MI:SSTZHTZM') || chr(10);
        l_pubmsg := l_pubmsg || 'Sensor          : ' || i_sensor_name || chr(10);
        l_pubmsg := l_pubmsg || 'Event Id        : ' || i_event_id || chr(10);
        l_pubmsg := l_pubmsg || 'Signature Id    : ';
        l_pubmsg := l_pubmsg || i_signature_gid || ':' || i_signature_sid || chr(10);
        l_pubmsg := l_pubmsg || 'Signature Name  : ' || l_description || chr(10);
        l_pubmsg := l_pubmsg || 'Signature Class : ' || l_signature_class || chr(10);
        l_pubmsg := l_pubmsg || 'Direction       : ' || get_direction_name(i_direction_id) || chr(10);
        l_pubmsg := l_pubmsg || 'Source          : ' || OSAG_IP.num2ip(i_ip_source_address);
        IF i_ip_source_port IS NOT NULL THEN
            l_pubmsg := l_pubmsg || ':' || i_ip_source_port;
        END IF;
        l_pubmsg := l_pubmsg || chr(10);
        l_pubmsg := l_pubmsg || 'Destination     : ' || OSAG_IP.num2ip(i_ip_destination_address);
        IF i_ip_destination_port IS NOT NULL THEN
            l_pubmsg := l_pubmsg || ':' || i_ip_destination_port;
        END IF;
        l_pubmsg := l_pubmsg || chr(10);
        l_pubmsg := l_pubmsg || 'Protocol        : ' || ip_proto_to_string(i_ip_protocol) || chr(10);
        l_pubmsg := l_pubmsg || 'Related Events  : ' ||
                    CASE WHEN i_suppressed IS NULL OR i_suppressed = 0 THEN 'none' ELSE i_suppressed || ' with same source and signature' END;

        l_privmsg := 'MCC: Proceed according to to the <a href="https://control.open.ch/docs/x/VQDS">NIDS Ticketing Howto</a>.';

        -- create a ticket event
        IF i_escalation_level = 2 THEN
            l_event_type := C_EVENT_TYPE_ID_ESCALATION;
        ELSE
            l_event_type := C_EVENT_TYPE_ID_NOTIFICATION;
        END IF;

        -- set the requested ticket id (if there is any)
        -- note: this might be overwritten by active service windows
        IF ( i_ticket_id IS NOT NULL AND i_ticket_id > 0 ) THEN
            l_tt_ticket_id := i_ticket_id;
        END IF;

        -- filter events from inactive hosts
        IF (i_sender_host_id is not null) THEN
            SELECT h.active INTO l_active FROM mss.host h WHERE h.id = i_sender_host_id;
            IF (l_active = 0) THEN
                plog.info(c_prefix||'dropping event of type '|| l_event_type ||' for inactive host '|| i_sender_host_id);
                RETURN;
            END IF;
        END IF;

        -- filter events from hosts with Service Window
        IF (i_sender_host_id is not null) THEN
            -- check if there are open service window for this host that have the disable event flag set
            SELECT COUNT(*) INTO l_disable_event_ticket_id
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
              AND (m.disable_events = 1 OR cm.disable_events = 1) AND h2s.host_id = i_sender_host_id;

            IF (l_disable_event_ticket_id > 0) THEN
                plog.info(c_prefix||'dropping event of type ' || l_event_type || ' for host ' || i_sender_host_id ||
                          '. Active service window with disable event flag on ticket ' || l_disable_event_ticket_id );
                RETURN;
            END IF;
        END IF;

        -- check if there are open service windows that request event collection
        if (i_sender_host_id IS NOT NULL) THEN
            SELECT MAX(t.id) INTO l_collect_event_ticket_id

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
              AND (m.collect_events = 1 OR cm.collect_events = 1) AND h2s.host_id = i_sender_host_id;

            IF (l_collect_event_ticket_id IS NOT NULL) THEN
                -- set the ticket id to append this event to
                -- (this might overwrite the requested ticket id from the Logic in Redis)
                l_tt_ticket_id := l_collect_event_ticket_id;
                plog.info(c_prefix||'overwriting ticket id because open service window '
                    ||'requests event collection in ticket '||l_collect_event_ticket_id);
            END IF;
        END IF;

        IF ( l_tt_ticket_id IS NOT NULL AND l_tt_ticket_id > 0 ) THEN

            -- addevent_new will follow merged tickets
            tt.event_interface.addevent_new(
                    l_tt_event_id,
                    l_tt_ticket_id,
                    l_event_type,
                    l_sensor_host_id,
                    l_pubmsg,
                    l_privmsg,
                    NULL,
                    TRUE,
                    i_log_date);

            -- execute event type actions
            tt.event_interface.exec_event_type_actions(l_tt_event_id);

        ELSE
            -- create new ticket
            SELECT name INTO subject
            FROM tt.event_type
            WHERE id=l_event_type;

            ticket_type_id := tt.event_interface.ticket_type_for_event_type( l_event_type );

            eventSubject := SUBSTR(l_pubmsg, 1, 95 - length(subject));
            IF (INSTR(eventSubject, CHR(10)) > 0) THEN
                eventSubject := SUBSTR(eventSubject, 1, INSTR(eventSubject, CHR(10)) - 1);
            ELSIF (length(eventSubject) = (95 - length(subject))) THEN
                eventSubject := SUBSTR(eventSubject, 1, length(eventSubject) - 3) || '...';
            END IF;
            subject := subject || ': ' || eventSubject;

            tt.ticket_interface.newticket_new(
                    l_tt_ticket_id,
                    l_tt_event_id,
                    ticket_type_id,
                    subject,
                    l_event_type,
                    l_sensor_host_id,
                    l_pubmsg,
                    l_privmsg,
                    NULL, -- contact_id
                    NULL, -- worker_id
                    TRUE, -- public event
                    i_log_date,
                    NULL -- company id
                );
        END IF;

        -- write the ticketing event id to the OUT variable
        i_tt_event_id := l_tt_event_id;


        -- write the message into the event table
        INSERT INTO nids.nids_event (
            id, log_date, sensor_host_id, sender_host_id, local_event_id, signature_id, suppressed, ip_source_address,
            ip_source_port, ip_destination_address, ip_destination_port, ip_protocol, direction_id, tt_event_id)
        VALUES (
                   nids.nidsevent_seq.nextval, i_log_date, l_sensor_host_id, i_sender_host_id, i_event_id, l_signature.id,
                   i_suppressed, i_ip_source_address, i_ip_source_port, i_ip_destination_address, i_ip_destination_port,
                   i_ip_protocol, i_direction_id, l_tt_event_id);

        -- FIXME: no class_id for custom rules

    EXCEPTION
        WHEN E_SIG_NOT_FOUND THEN
            plog.err(C_PREFIX||'no matching signature found for GID '||i_signature_gid||' and SID '||i_signature_sid ||' (sensor host: ' || i_sensor_name || ')');
        WHEN E_SENSOR_ID_NOT_FOUND THEN
            plog.err(C_PREFIX||'no matching host found for sensor name '||i_sensor_name);
        WHEN DUP_VAL_ON_INDEX THEN
            plog.warning(C_PREFIX||'dropped duplicate ids event (local event id: ' || i_event_id || ', sensor: ' || i_sensor_name || ', signature: ' || i_signature_gid || ':' || i_signature_sid || ')');
        WHEN OTHERS THEN
            plog.err(C_PREFIX||'caught exception while processing '||i_sender_host_id||': '||sqlerrm);
    END submit_msg_new;

-- OLD
-- PROCEDURE submit_msg
-- Purpose: Submit a NIDS log entry
    PROCEDURE submit_msg(
        i_log_date               nids_event.log_date%TYPE,
        i_sensor_name            VARCHAR2,
        i_sender_host_id         nids_event.sender_host_id%TYPE,
        i_event_id               nids_event.local_event_id%TYPE,
        i_signature_gid          signature.gid%TYPE,
        i_signature_sid          signature.sid%TYPE,
        i_signature_class        VARCHAR2,
        i_suppressed             nids_event.suppressed%TYPE,
        i_ip_source_address      nids_event.ip_source_address%TYPE,
        i_ip_source_port         nids_event.ip_source_port%TYPE,
        i_ip_destination_address nids_event.ip_destination_address%TYPE,
        i_ip_destination_port    nids_event.ip_destination_port%TYPE,
        i_ip_protocol            nids_event.ip_protocol%TYPE,
        i_direction_id           nids_event.direction_id%TYPE,
        i_description            VARCHAR2,
        i_escalation_level       INTEGER
    ) IS

        l_signature          signature%ROWTYPE;
        l_description        signature.name%TYPE;
        l_signature_class    signature_class.NAME%TYPE;
        l_sensor_host_id     mss.host.id%TYPE;
        l_pubmsg             VARCHAR2(4000);
        l_tt_event_id        NUMBER := NULL;
        l_event_type         NUMBER;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        submit_msg_new(
                i_log_date,
                i_sensor_name,
                i_sender_host_id,
                i_event_id,
                l_tt_event_id,    -- tt_event_id is 0
                NULL, -- tt_ticket_id is NULL
                i_signature_gid,
                i_signature_sid,
                i_signature_class,
                i_suppressed,
                i_ip_source_address,
                i_ip_source_port,
                i_ip_destination_address,
                i_ip_destination_port,
                i_ip_protocol,
                i_direction_id,
                i_description,
                i_escalation_level
            );

    END submit_msg;


END OSAG_NIDS;
/
