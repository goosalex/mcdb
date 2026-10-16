--liquibase formatted sql logicalFilePath:oracle_side/tt_stubs.sql
--changeset phoenix:tt_stubs runOnChange:true endDelimiter:/ splitStatements:true
-- =====================================================================================
-- Façade ("stub") packages that keep the Oracle-side callers compiling unchanged after
-- the TT tables and the real packages moved to PostgreSQL. ONLY the nine entry points
-- reached from outside TT are kept (migration/.planning/reports/tt-callers-2026-10-14.html,
-- section 3) plus ticket_type_for_event_type, which is pure and stays local. Every
-- other routine of the original packages is gone on Oracle on purpose -- a caller that
-- needs one has to be migrated, not bridged.
--
-- Signatures are copied verbatim from ddl/src/pkg/tt_*.sql (parameter names matter:
-- the callers use named notation in places). Bodies marshal the arguments as a JSON
-- object with the PostgreSQL parameter names (identical to Oracle's; see
-- migration/pgsql/tt/*.sql) and call TT.BRIDGE.call_remote with the package_in_name
-- routine name taken from migration/mapping/name-map.csv.
--
-- UNTESTED DRAFT -- no Oracle instance available (README.md).
-- =====================================================================================

CREATE OR REPLACE PACKAGE tt.event_interface AS
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
                           p_company_id NUMBER DEFAULT NULL);

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
                           p_peer_contact_id NUMBER DEFAULT NULL);

    PROCEDURE exec_event_type_actions(p_event_id NUMBER);

    -- pure mapping, no DB access (verified: ddl/src/pkgb/tt_event_interface.sql:833-861);
    -- kept LOCAL so NIDS.OSAG_NIDS's assignment-position call needs no round trip.
    FUNCTION ticket_type_for_event_type(p_event_type_id NUMBER) RETURN NUMBER;
END event_interface;
/

CREATE OR REPLACE PACKAGE BODY tt.event_interface AS
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
        v_out CLOB;
    BEGIN
        v_out := tt.bridge.call_remote('tt.event_interface_newevent_new', JSON_OBJECT(
            KEY 'p_type_id'              VALUE p_type_id,
            KEY 'p_host_id'              VALUE p_host_id,
            KEY 'p_details_public'       VALUE p_details_public,
            KEY 'p_details_private'      VALUE p_details_private,
            KEY 'p_contact_id'           VALUE p_contact_id,
            KEY 'p_public_event'         VALUE tt.bridge.j_bool(p_public_event) FORMAT JSON,
            KEY 'p_eventdate'            VALUE tt.bridge.j_date(p_eventdate),
            KEY 'p_ticket_type_id'       VALUE p_ticket_type_id,
            KEY 'p_service_component_id' VALUE p_service_component_id,
            KEY 'p_zitadel_contact_id'   VALUE p_zitadel_contact_id,
            KEY 'p_company_id'           VALUE p_company_id
            NULL ON NULL RETURNING CLOB));
        p_event_id := TO_NUMBER(JSON_VALUE(v_out, '$.p_event_id'));
    END;

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
        v_out CLOB;
    BEGIN
        v_out := tt.bridge.call_remote('tt.event_interface_addevent_new', JSON_OBJECT(
            KEY 'p_ticket_id'          VALUE p_ticket_id,
            KEY 'p_type_id'            VALUE p_type_id,
            KEY 'p_host_id'            VALUE p_host_id,
            KEY 'details_public'       VALUE details_public,
            KEY 'details_private'      VALUE details_private,
            KEY 'p_contact_id'         VALUE p_contact_id,
            KEY 'public_event'         VALUE tt.bridge.j_bool(public_event) FORMAT JSON,
            KEY 'eventdate'            VALUE tt.bridge.j_date(eventdate),
            KEY 'notify_event'         VALUE tt.bridge.j_bool(notify_event) FORMAT JSON,
            KEY 'p_zitadel_contact_id' VALUE p_zitadel_contact_id,
            KEY 'p_peer_contact_id'    VALUE p_peer_contact_id
            NULL ON NULL RETURNING CLOB));
        p_event_id := TO_NUMBER(JSON_VALUE(v_out, '$.p_event_id'));
    END;

    PROCEDURE exec_event_type_actions(p_event_id NUMBER) AS
        v_out CLOB;
    BEGIN
        v_out := tt.bridge.call_remote('tt.event_interface_exec_event_type_actions',
                                       JSON_OBJECT(KEY 'p_event_id' VALUE p_event_id RETURNING CLOB));
    END;

    -- Copied from ddl/src/pkgb/tt_event_interface.sql:833-861 (unchanged logic; the
    -- plog.AuditUsage call dropped, XCUT-06).
    FUNCTION ticket_type_for_event_type(p_event_type_id NUMBER) RETURN NUMBER IS
        v_ticket_type_id NUMBER;
    BEGIN
        -- 3rd party incident: isp outage 10003, tunnel notification 10110, vpn up 10102, vpn down 10019
        IF p_event_type_id IN (10003, 10110, 10102, 10019) THEN
            v_ticket_type_id := 4;
        -- change request
        ELSIF p_event_type_id = 30002 OR p_event_type_id = 30009 THEN
            v_ticket_type_id := 2;
        -- default: trouble ticket
        ELSE
            v_ticket_type_id := 1;
        END IF;
        RETURN v_ticket_type_id;
    END;
END event_interface;
/

CREATE OR REPLACE PACKAGE tt.ticket_interface AS
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
                            p_zitadel_contact_id NUMBER DEFAULT NULL);

    PROCEDURE change_status(p_ticket_id NUMBER,
                            p_status_id NUMBER,
                            p_contact_id NUMBER,
                            p_details_public VARCHAR2,
                            p_details_private VARCHAR2 DEFAULT NULL,
                            p_valid_until_date DATE DEFAULT null,
                            p_defer_event NUMBER DEFAULT null,
                            p_escalate_after_defer BOOLEAN DEFAULT NULL,
                            p_hot_reason VARCHAR2 DEFAULT NULL,
                            p_zitadel_contact_id NUMBER DEFAULT NULL);

    PROCEDURE change_subject(p_ticket_id NUMBER,
                             p_subject VARCHAR2,
                             p_contact_id NUMBER,
                             p_zitadel_contact_id NUMBER DEFAULT NULL);
END ticket_interface;
/

CREATE OR REPLACE PACKAGE BODY tt.ticket_interface AS
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
                            p_zitadel_contact_id NUMBER DEFAULT NULL) AS
        v_out CLOB;
    BEGIN
        v_out := tt.bridge.call_remote('tt.ticket_interface_newticket_new', JSON_OBJECT(
            KEY 'p_ticket_type_id'       VALUE p_ticket_type_id,
            KEY 'p_subject'              VALUE p_subject,
            KEY 'p_event_type_id'        VALUE p_event_type_id,
            KEY 'p_host_id'              VALUE p_host_id,
            KEY 'p_details_public'       VALUE p_details_public,
            KEY 'p_details_private'      VALUE p_details_private,
            KEY 'p_contact_id'           VALUE p_contact_id,
            KEY 'p_worker_id'            VALUE p_worker_id,
            KEY 'p_public_event'         VALUE tt.bridge.j_bool(p_public_event) FORMAT JSON,
            KEY 'p_eventdate'            VALUE tt.bridge.j_date(p_eventdate),
            KEY 'p_company_id'           VALUE p_company_id,
            KEY 'p_service_component_id' VALUE p_service_component_id,
            KEY 'p_zitadel_contact_id'   VALUE p_zitadel_contact_id
            NULL ON NULL RETURNING CLOB));
        p_ticket_id := TO_NUMBER(JSON_VALUE(v_out, '$.p_ticket_id'));
        p_event_id  := TO_NUMBER(JSON_VALUE(v_out, '$.p_event_id'));
    END;

    PROCEDURE change_status(p_ticket_id NUMBER,
                            p_status_id NUMBER,
                            p_contact_id NUMBER,
                            p_details_public VARCHAR2,
                            p_details_private VARCHAR2 DEFAULT NULL,
                            p_valid_until_date DATE DEFAULT null,
                            p_defer_event NUMBER DEFAULT null,
                            p_escalate_after_defer BOOLEAN DEFAULT NULL,
                            p_hot_reason VARCHAR2 DEFAULT NULL,
                            p_zitadel_contact_id NUMBER DEFAULT NULL) AS
        v_out CLOB;
    BEGIN
        v_out := tt.bridge.call_remote('tt.ticket_interface_change_status', JSON_OBJECT(
            KEY 'p_ticket_id'            VALUE p_ticket_id,
            KEY 'p_status_id'            VALUE p_status_id,
            KEY 'p_contact_id'           VALUE p_contact_id,
            KEY 'p_details_public'       VALUE p_details_public,
            KEY 'p_details_private'      VALUE p_details_private,
            KEY 'p_valid_until_date'     VALUE tt.bridge.j_date(p_valid_until_date),
            KEY 'p_defer_event'          VALUE p_defer_event,
            KEY 'p_escalate_after_defer' VALUE tt.bridge.j_bool(p_escalate_after_defer) FORMAT JSON,
            KEY 'p_hot_reason'           VALUE p_hot_reason,
            KEY 'p_zitadel_contact_id'   VALUE p_zitadel_contact_id
            NULL ON NULL RETURNING CLOB));
    END;

    PROCEDURE change_subject(p_ticket_id NUMBER,
                             p_subject VARCHAR2,
                             p_contact_id NUMBER,
                             p_zitadel_contact_id NUMBER DEFAULT NULL) AS
        v_out CLOB;
    BEGIN
        v_out := tt.bridge.call_remote('tt.ticket_interface_change_subject', JSON_OBJECT(
            KEY 'p_ticket_id'          VALUE p_ticket_id,
            KEY 'p_subject'            VALUE p_subject,
            KEY 'p_contact_id'         VALUE p_contact_id,
            KEY 'p_zitadel_contact_id' VALUE p_zitadel_contact_id
            NULL ON NULL RETURNING CLOB));
    END;
END ticket_interface;
/

CREATE OR REPLACE PACKAGE tt.escalation_interface AS
    PROCEDURE clear_customer_escalation(p_ticket_id NUMBER);
END escalation_interface;
/

CREATE OR REPLACE PACKAGE BODY tt.escalation_interface AS
    PROCEDURE clear_customer_escalation(p_ticket_id NUMBER) AS
        v_out CLOB;
    BEGIN
        v_out := tt.bridge.call_remote('tt.escalation_interface_clear_customer_escalation',
                                       JSON_OBJECT(KEY 'p_ticket_id' VALUE p_ticket_id RETURNING CLOB));
    END;
END escalation_interface;
/

CREATE OR REPLACE PACKAGE tt.osag_notify AS
    PROCEDURE delete_notifications_for_login(p_login_id NUMBER);
END osag_notify;
/

CREATE OR REPLACE PACKAGE BODY tt.osag_notify AS
    PROCEDURE delete_notifications_for_login(p_login_id NUMBER) AS
        v_out CLOB;
    BEGIN
        v_out := tt.bridge.call_remote('tt.osag_notify_delete_notifications_for_login',
                                       JSON_OBJECT(KEY 'p_login_id' VALUE p_login_id RETURNING CLOB));
    END;
END osag_notify;
/

-- The two *_STATE packages keep their exception declarations so callers that catch
-- tt.event_interface_state.ticket_closed still compile; TT.BRIDGE.raise_mapped raises
-- the same -20980, so the handlers keep working.
CREATE OR REPLACE PACKAGE tt.event_interface_state AS
    ticket_closed EXCEPTION;
    S_ERRNO_TICKET_CLOSED CONSTANT NUMBER := -20980;
    PRAGMA EXCEPTION_INIT (ticket_closed, -20980);
END event_interface_state;
/

-- =====================================================================================
-- Callback entry points the PostgreSQL side invokes (via the bridge service, in the
-- other direction) for the cross-schema statements deleteTicket / merge_tickets used
-- to run inside Oracle. Statements copied VERBATIM from
-- ddl/src/pkgb/tt_ticket_interface.sql (deleteTicket lines 2443-2480, merge_tickets
-- line 1630), minus the TT tables themselves, which now live in PostgreSQL. The two
-- EVENT-keyed statements (mc.isp_link_history, mc.connection_interrupt_open is not
-- touched by Oracle either) take the event id list the PostgreSQL side already knows.
-- =====================================================================================
CREATE OR REPLACE PACKAGE tt.bridge_callback AS
    TYPE id_list IS TABLE OF NUMBER;
    PROCEDURE on_ticket_deleted(p_ticket_id NUMBER, p_event_ids id_list);
    PROCEDURE on_tickets_merged(p_ticket_id NUMBER, p_mticket_id NUMBER);
END bridge_callback;
/

CREATE OR REPLACE PACKAGE BODY tt.bridge_callback AS
    PROCEDURE on_ticket_deleted(p_ticket_id NUMBER, p_event_ids id_list) AS
    BEGIN
        UPDATE PRX.PRX_POLICY_ITEM SET TICKET_ID = null WHERE TICKET_ID = p_ticket_id;                 -- line 2443
        UPDATE MCAUDIT.RECORD SET TICKET_ID = NULL WHERE TICKET_ID = p_ticket_id;                       -- 2450
        IF p_event_ids IS NOT NULL AND p_event_ids.COUNT > 0 THEN                                        -- 2456
            FORALL i IN 1 .. p_event_ids.COUNT
                UPDATE MC.ISP_LINK_HISTORY SET EVENT_ID = NULL WHERE EVENT_ID = p_event_ids(i);
        END IF;
        UPDATE MSS.INSTALLATION_PROJECT_ITEM SET ticket_id = null where ticket_id = p_ticket_id;        -- 2458
        DELETE FROM GUMA2.SUPPRESSED_SIGNATURE WHERE TICKET_ID = p_ticket_id;                           -- 2459
        UPDATE MC.ISP_LINK_MAINTENANCE_HISTORY SET TICKET_ID = NULL WHERE TICKET_ID = p_ticket_id;      -- 2460
        UPDATE MC.HOST_MAINTENANCE_HISTORY SET TICKET_ID = NULL WHERE TICKET_ID = p_ticket_id;          -- 2461
        DELETE FROM NIDS.TICKET2RULE where ticket_id = p_ticket_id;                                     -- 2462
        DELETE FROM FW.RULE2TICKET where ticket_id = p_ticket_id;                                       -- 2463
        DELETE FROM FW.SOURCE_NAT_RULE2TICKET where ticket_id = p_ticket_id;                            -- 2464
        DELETE FROM FW.DESTINATION_NAT_RULE2TICKET where ticket_id = p_ticket_id;                       -- 2465
        -- 2474: MSS.deleted_host2service_window by SERVICE_WINDOW_ID -- the service-window
        -- ids are TT data; the PostgreSQL side deletes the TT rows and the Oracle-side
        -- mss.deleted_host2service_window rows for them are orphaned logical references
        -- (their FK was dropped in prune.sql step 3). TODO: pass p_service_window_ids.
        DELETE FROM FW.CHANGE WHERE TICKET_ID = p_ticket_id;                                            -- 2480
        COMMIT;
    END;

    PROCEDURE on_tickets_merged(p_ticket_id NUMBER, p_mticket_id NUMBER) AS
    BEGIN
        -- line 1630: move suppressed events to new ticket (the ONLY cross-schema
        -- statement in merge_tickets; everything else it touches is TT)
        UPDATE guma2.suppressed_signature SET ticket_id = p_mticket_id WHERE ticket_id = p_ticket_id;
        COMMIT;
    END;
END bridge_callback;
/
