--liquibase formatted sql logicalFilePath:pkgb/guma2_secondary_isp.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE BODY GUMA2.SECONDARY_ISP IS
-- ----------------------------------------------------------------------------------------
-- package constants
-- ----------------------------------------------------------------------------------------

    E_ABORT                EXCEPTION;

    -- 10050 is "ISP down"
    C_SEC_ISP_OUTAGE_EVENT_TYPE   CONSTANT NUMBER :=  10050;

    -- 10100 is "connection up"
    C_SEC_ISP_OK_EVENT_TYPE   CONSTANT NUMBER :=  10100;

-- ----------------------------------------------------------------------------------------
-- PROCEDURE get_next_token: copied from create_pkg_OSAG_IMPLICATION.sql
-- (copied from create_pkg_OSAG_IMPLICATION.sql to avoid circular dependency)
-- ----------------------------------------------------------------------------------------
    PROCEDURE get_next_token(
        i_delim      VARCHAR2,
        i_string     VARCHAR2,
        o_token      OUT VARCHAR2,
        o_rest       OUT VARCHAR2
    ) IS
        C_PREFIX      CONSTANT VARCHAR2(64) := 'SECONDARY_ISP.get_next_token(): ';
        l_pos         NUMBER;

    BEGIN
        o_token := NULL;
        o_rest := NULL;

        -- Empty string handling
        IF (LENGTH(i_string) = 0) THEN
            RETURN;
        END IF;

        l_pos := INSTR(i_string, i_delim, 1, 1);

        -- Last token in string
        IF (l_pos = 0) THEN
            o_token := i_string;
            RETURN;
        END IF;

        IF (l_pos != 1) THEN
            o_token := substr(i_string, 0, l_pos - 1);
        END IF;

        IF ((l_pos + LENGTH(i_delim)) <= LENGTH(i_string)) THEN
            o_rest := substr(i_string, l_pos + length(i_delim));
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(C_PREFIX||'unexpected error 99: '||sqlerrm);
            RAISE;

    END get_next_token;

-- ----------------------------------------------------------------------------------------
-- PROCEDURE secondaryisp_parse_syslog
-- Parse syslog line like:
-- Jul 29 16:51:27 v1 nursed: NURSE:SECONDARYISP:ALERT All tunnels down (interface=eth0, peers=1027|1028|1029) [state=Alert, observed=420s]
-- ----------------------------------------------------------------------------------------
    PROCEDURE secondaryisp_parse_syslog(
        i_host_id       mss.host.id%TYPE,
        i_data          syslog_message.message%TYPE,
        o_interface     OUT NOCOPY VARCHAR2,
        o_peers         OUT NOCOPY VARCHAR2,
        o_since         OUT NOCOPY VARCHAR2
    ) IS
        C_PREFIX           CONSTANT VARCHAR2(64) := 'SECONDARY_ISP.secondaryisp_parse_syslog(): ';
        l_before_token     syslog_message.message%TYPE;
        l_after_token      syslog_message.message%TYPE;
    BEGIN
        -- Parse line up to 'NURSE:SECONDARYISP:'
        get_next_token('NURSE:SECONDARYISP:', i_data, l_before_token, l_after_token);
        IF (l_after_token IS NULL) THEN
            plog.err(C_PREFIX||'can''t  parse NURSE:SECONDARYISP:ALERT line (1): '||i_data);
            RAISE E_ABORT;
        END IF;

        -- Parse line up to '(interface='
        get_next_token('(interface=', l_after_token, l_before_token, l_after_token);
        IF (l_after_token IS NULL) THEN
            plog.err(C_PREFIX||'can''t  parse NURSE:SECONDARYISP:ALERT line (2): '||i_data);
            RAISE E_ABORT;
        END IF;

        --  Parse line up to ', peers='
        get_next_token(', peers=', l_after_token, l_before_token, l_after_token);
        IF (l_after_token IS NULL) THEN
            plog.err(C_PREFIX||'can''t  parse NURSE:SECONDARYISP:ALERT line (3): '||i_data);
            RAISE E_ABORT;
        END IF;

        o_interface := l_before_token;

        --  Parse line up to ') [state='
        get_next_token(') [state=', l_after_token, l_before_token, l_after_token);
        IF (l_after_token IS NULL) THEN
            plog.err(C_PREFIX||'can''t  parse NURSE:SECONDARYISP:ALERT line (4): '||i_data);
            RAISE E_ABORT;
        END IF;

        o_peers := l_before_token;

        --  Parse line up to 'observed='
        get_next_token('observed=', l_after_token, l_before_token, l_after_token);
        IF (l_after_token IS NULL) THEN
            plog.err(C_PREFIX||'can''t  parse NURSE:SECONDARYISP:ALERT line (5): '||i_data);
            RAISE E_ABORT;
        END IF;

        --  Parse line up to ']'
        get_next_token(']', l_after_token, l_before_token, l_after_token);
        o_since := l_before_token;
    END secondaryisp_parse_syslog;


-- ----------------------------------------------------------------------------------------
-- FUNCTION is_host_up
-- Checks if connection monitoring reports the host as up
-- ----------------------------------------------------------------------------------------
    FUNCTION is_host_up(
        i_host_id       mss.host.id%TYPE
    )
        RETURN BOOLEAN
        IS
        C_PREFIX           CONSTANT VARCHAR2(64) := 'SECONDARY_ISP.is_host_up(): ';
        --l_con_int_type_id  mc.host_connection_status.con_int_type_id%TYPE;
        l_con_int_type_id  mc.mon_server_connection.status%TYPE;
    BEGIN
        -- code using new mc.host_connection_status table (not yet available):
        --SELECT conn.con_int_type_id INTO l_con_int_type_id
        -- FROM  mc.host_connection_status conn
        --WHERE conn.host_id = i_host_id;

        SELECT status INTO l_con_int_type_id
        FROM mc.mon_server_connection
        WHERE mon_server_id IS NULL AND host_id = i_host_id;

        IF l_con_int_type_id IS NULL THEN
            RETURN TRUE;
        ELSE
            RETURN FALSE;
        END IF;

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            -- Host apparently doesn't exist! It certainly isn't up...
            RETURN FALSE;
        WHEN OTHERS THEN
            plog.err(C_PREFIX||'error: '||sqlerrm);
            RAISE E_ABORT;
    END is_host_up;

-- ----------------------------------------------------------------------------------------
-- PROCEDURE secondaryisp_interface_info
-- Extract some interface-related information interesting for the secondary isp outage
-- notification logic
-- ----------------------------------------------------------------------------------------
    PROCEDURE secondaryisp_interface_info(
        i_host_id          mss.host.id%TYPE,
        i_interface_name   mss.interface.name%TYPE,
        o_interface_desc   OUT NOCOPY mss.interface.description%TYPE,
        o_wan_managed      OUT NOCOPY mss.isp_link.wan_managed%TYPE,
        o_isp_company      OUT NOCOPY stop.company.name%TYPE
    )
        IS
        C_PREFIX           CONSTANT VARCHAR2(64) := 'SECONDARY_ISP.secondary_interface_info(): ';
    BEGIN
        SELECT i.description,    isp.wan_managed, ispc.name
        INTO o_interface_desc, o_wan_managed,   o_isp_company
        FROM mss.interface i
                 JOIN mss.interface2isp_link i2isp ON i2isp.interface_id = i.id
                 JOIN mss.isp_link isp ON isp.id = i2isp.isp_link_id
                 JOIN stop.company ispc ON isp.company_id = ispc.id
        WHERE i.host_id = i_host_id AND i.name = i_interface_name;

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            plog.err(C_PREFIX||'can''t get information about interface '||i_interface_name||' of host '||i_host_id);
            RAISE E_ABORT;
    END secondaryisp_interface_info;

-- ----------------------------------------------------------------------------------------
-- PROCEDURE is_secondaryisp_all_peers_down
-- For the "Secondary ISP Outage" logic, we need to know if the reason for the
-- reported outage by the host is that all its peers are down. No need to escalate
-- this further, in that case.
-- ----------------------------------------------------------------------------------------
    FUNCTION is_secondaryisp_all_peers_down(
        i_peers     VARCHAR2
    )
        RETURN BOOLEAN
        IS
        l_before_token     syslog_message.message%TYPE;
        l_after_token      syslog_message.message%TYPE;
        l_peer_host_id     mss.host.id%TYPE;
    BEGIN
        l_after_token := i_peers;
        WHILE l_after_token IS NOT NULL
            LOOP
                get_next_token('|', l_after_token, l_before_token, l_after_token);
                l_peer_host_id := TO_NUMBER(l_before_token);
                IF is_host_up(l_peer_host_id) THEN
                    RETURN FALSE;
                END IF;
            END LOOP;

        RETURN TRUE;
    END is_secondaryisp_all_peers_down;

-- ----------------------------------------------------------------------------------------
-- PROCEDURE comma_join
-- Add a string (i_element) to another (io_string) with ', ' to separate strings
-- ----------------------------------------------------------------------------------------
    PROCEDURE comma_join(
        io_string     IN OUT NOCOPY VARCHAR2,
        i_element     VARCHAR2
    )
        IS
    BEGIN
        IF io_string IS NULL THEN
            io_string := i_element;
        ELSE
            io_string := io_string || ', ' || i_element;
        END IF;
    END comma_join;

-- ----------------------------------------------------------------------------------------
-- FUNCTION pretty_print_host_id_list
-- Input:  host list in the format: HOSTID1|HOSTID2|HOSTID3
-- Output: readable list of host names (hostname1, hostname2, hostname3)
-- ----------------------------------------------------------------------------------------
    FUNCTION pretty_print_host_id_list(
        i_peers     VARCHAR2
    )
        RETURN VARCHAR2
        IS
        l_before_token     syslog_message.message%TYPE;
        l_after_token      syslog_message.message%TYPE;
        l_host_id          mss.host.id%TYPE;
        l_host_name        mss.host.name%TYPE;
        l_pretty_string    VARCHAR2(4096) := '';
    BEGIN
        l_after_token := i_peers;
        WHILE l_after_token IS NOT NULL
            LOOP
                get_next_token('|', l_after_token, l_before_token, l_after_token);
                l_host_id := TO_NUMBER(l_before_token);

                -- fetch host name
                BEGIN
                    SELECT host.name INTO l_host_name
                    FROM  mss.host
                    WHERE host.id = l_host_id;

                    -- Note: HREF links in MC events is not a good idea, because links could change. If we really want to
                    -- put a link, then we need to implement this in the MC Admin Ticket Viewer
                    --comma_join(l_pretty_string, '<a href="/mc/sp/h/'||l_host_id||'/status/Status/status.action">'||l_host_name||'</a>');
                    comma_join(l_pretty_string, l_host_name);

                EXCEPTION
                    WHEN NO_DATA_FOUND THEN
                        -- host not found ??
                        comma_join(l_pretty_string, 'unknown(hostid:'||l_host_id||')');
                END;
            END LOOP;

        RETURN l_pretty_string;
    END pretty_print_host_id_list;

-- ----------------------------------------------------------------------------------------
-- PROCEDURE secondaryisp_alert
-- process NURSE:SECONDARYISP:ALERT messages
-- (see: https://control.open.ch/jira/browse/MON-215)
-- ----------------------------------------------------------------------------------------
    PROCEDURE secondaryisp_alert(
        i_host_id       mss.host.id%TYPE,
        i_logdate       syslog_message.log_date%TYPE,
        i_data          syslog_message.message%TYPE
    ) IS
        C_PREFIX           CONSTANT VARCHAR2(64) := 'SECONDARY_ISP.secondaryisp_alert(): ';
        l_interface        syslog_message.message%TYPE;
        l_peers            syslog_message.message%TYPE;
        l_down_since       syslog_message.message%TYPE;
        l_wan_managed      mss.isp_link.wan_managed%TYPE;
        l_interface_desc   mss.interface.description%TYPE;
        l_isp_company      stop.company.name%TYPE;
        l_event_id         NUMBER;
    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- Parse syslog line
        secondaryisp_parse_syslog(i_host_id, i_data, l_interface, l_peers, l_down_since);

        -- Get some information about this interface. In particular: is it WAN managed?
        secondaryisp_interface_info(i_host_id, l_interface,
                                    l_interface_desc, l_wan_managed, l_isp_company);

        -- Ignore this message if the link is not WAN managed
        IF l_wan_managed = 0 THEN
            plog.notice(C_PREFIX||'Ignoring secondary ISP outage, because not WAN managed (host: '||i_host_id||', interface: '||l_interface||')');
            RAISE E_ABORT;
        END IF;

        -- Ignore this message if all peers are down
        -- (because this is likely the reason for all tunnels to be down)
        IF is_secondaryisp_all_peers_down(l_peers) THEN
            plog.notice(C_PREFIX||'Ignoring secondary ISP outage, because all peers down (host: '||i_host_id||', interface: '||l_interface||')');
            RAISE E_ABORT;
        END IF;

        -- Add an event
        TT.event_interface.newevent_new(
                l_event_id,
                C_SEC_ISP_OUTAGE_EVENT_TYPE,
                i_host_id,
            -- public comment:
                'Secondary ISP Outage'||CHR(10)||
                CHR(10)||
                'All VPN tunnels through one ISP link are down. This could mean that the ISP link is down.'||CHR(10)||
                CHR(10)||
                'Open Systems Mission Control will start the WAN Management ISP Down process.'||CHR(10)||
                CHR(10)||
                'Host:       '||pretty_print_host_id_list(i_host_id)||CHR(10)||
                'Interface:  '||l_interface||' ('||l_interface_desc||')'||CHR(10)||
                'ISP name:   '||l_isp_company||CHR(10)||
                'VPN peers:  '||pretty_print_host_id_list(l_peers)||CHR(10)||
                'Down since: '||l_down_since||CHR(10)
            ,
            -- private comment:
                'This host is subscribed to WAN Management.'||CHR(10)||
                CHR(10)||
                'To Do:'||CHR(10)||
                CHR(10)||
                'Execute this process: https://control.open.ch/docs/x/wBlbB'
            );

    EXCEPTION
        WHEN E_ABORT THEN
            NULL;
        WHEN OTHERS THEN
            plog.err(C_PREFIX||'unexpected error 99: '||sqlerrm);
    END secondaryisp_alert;

-- ----------------------------------------------------------------------------------------
-- PROCEDURE secondaryisp_ok
-- ----------------------------------------------------------------------------------------
    PROCEDURE secondaryisp_ok(
        i_host_id          mss.host.id%TYPE,
        i_logdate          syslog_message.log_date%TYPE,
        i_data             syslog_message.message%TYPE
    ) IS
        C_PREFIX           CONSTANT VARCHAR2(64) := 'SECONDARY_ISP.secondaryisp_ok(): ';
        l_interface        syslog_message.message%TYPE;
        l_peers            syslog_message.message%TYPE;
        l_up_since       syslog_message.message%TYPE;
        l_wan_managed      mss.isp_link.wan_managed%TYPE;
        l_interface_desc   mss.interface.description%TYPE;
        l_isp_company      stop.company.name%TYPE;
        l_event_id         NUMBER;
        l_unresolved_ticket_id   tt.ticket.id%TYPE;

        CURSOR l_unresolved_ticket_cur IS
            SELECT t.id
            FROM tt.ticket t
            WHERE t.status_id < 100 AND host_id = i_host_id
            ORDER BY t.id DESC;
    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- Parse syslog line
        secondaryisp_parse_syslog(i_host_id, i_data, l_interface, l_peers, l_up_since);

        -- Get some information about this interface. In particular: is it WAN managed?
        secondaryisp_interface_info(i_host_id, l_interface,
                                    l_interface_desc, l_wan_managed, l_isp_company);


        -- Ignore this message if the link is not WAN managed
        IF l_wan_managed = 0 THEN
            plog.notice(C_PREFIX||'Ignoring secondary ISP ok event, because not WAN managed (host: '||i_host_id||', interface: '||l_interface||')');
            RAISE E_ABORT;
        END IF;

        -- The logic for raising a "Secondary ISP Outage" event is rather complex and
        -- involves checking the current status of VPN peers. One difficult part of
        -- this design is that we also need to know when a Outage is over.
        -- The situation might have (and probably did) change, so we can't just do
        -- the same checks to find out if an Outage event was generated before.
        -- Still, we shouldn't create an OK event, if previously there was no Outage event...
        --
        -- The chosen solution here is to check if there is an non-resolved ticket for this host
        -- This is certainly sub-optimal, but probably good enough. A proper solution would
        -- require tracking the status like we currently do with the connection monitoring
        -- framework, but we want to avoid such a complex system for now...
        --
        -- Anyway, putting a ticket in an open event is not so bad as creating a new ticket
        -- with an "OK" message. Also, not saying OK, just because the Outage ticket has been closed,
        -- is probably Ok too (this shouldn't be done anyway!)

        OPEN l_unresolved_ticket_cur;
        FETCH l_unresolved_ticket_cur INTO l_unresolved_ticket_id;
        CLOSE l_unresolved_ticket_cur;

        IF l_unresolved_ticket_id IS NULL THEN
            -- No unresolved ticket found -> no event (see above)
            plog.notice(C_PREFIX||'Ignoring secondary ISP ok event, because no unresolved ticket was found (host: '||i_host_id||', interface: '||l_interface||')');
            RAISE E_ABORT;
        END IF;

        -- Add an event
        TT.event_interface.newevent_new(
                l_event_id,
                C_SEC_ISP_OK_EVENT_TYPE,
                i_host_id,
            -- public comment:
                'Secondary ISP OK'||CHR(10)||
                CHR(10)||
                'One or more VPN tunnels through one ISP link are up. The ISP link is thus apparently up.'||CHR(10)||
                CHR(10)||
                'The WAN Management ISP Down process will be stopped.'||CHR(10)||
                CHR(10)||
                'Host:       '||pretty_print_host_id_list(i_host_id)||CHR(10)||
                'Interface:  '||l_interface||' ('||l_interface_desc||')'||CHR(10)||
                'ISP name:   '||l_isp_company||CHR(10)||
                'VPN peers:  '||pretty_print_host_id_list(l_peers)||CHR(10)||
                'Up since:   '||l_up_since||CHR(10)
            ,
            -- private comment:
                'To Do:'||CHR(10)||
                CHR(10)||
                'Try to find a corresponding "Secondary ISP Outage" event. If there isn''t one, fast-resolve.'
            );
    EXCEPTION
        WHEN E_ABORT THEN
            NULL;
        WHEN OTHERS THEN
            plog.err(C_PREFIX||'unexpected error: '||sqlerrm);
    END secondaryisp_ok;

END SECONDARY_ISP;
/
