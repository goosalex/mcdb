-- migration/pgsql/guma2/secondary_isp.sql
--
-- Translation of GUMA2.SECONDARY_ISP (spec: migration/spec/guma2.secondary_isp.md; Oracle
-- body: ddl/src/pkgb/guma2_secondary_isp.sql, 445 lines). Public names copied verbatim from
-- migration/mapping/name-map.csv's 2 SECONDARY_ISP rows (both pg_kind=procedure). The seven
-- body-only helpers are private: guma2.secondary_isp__<name>, EXECUTE revoked from PUBLIC
-- (S-SISP-018). Oracle PROCEDUREs whose only outputs are OUT parameters (get_next_token,
-- secondaryisp_parse_syslog, secondaryisp_interface_info) are FUNCTIONs with OUT columns
-- here so PL/pgSQL can read their results with one SELECT ... INTO; comma_join keeps its
-- IN OUT shape as a PROCEDURE with an INOUT parameter.
--
-- Oracle's usage-audit call (XCUT-06): both plog.AuditUsage sites (lines 295, 373 -- one per
-- public routine) DELETED, not ported. See secondary_isp.FINDINGS.md.
--
-- Package-private E_ABORT (body line 8) -> SQLSTATE 'OS020' (PROVISIONAL, XCUT-01; see the
-- spec's checklist 3): raised with RAISE EXCEPTION ... USING ERRCODE = 'OS020', caught with
-- WHEN SQLSTATE 'OS020'. It never leaves the package: both public procedures end in
-- WHEN SQLSTATE 'OS020' ...; WHEN OTHERS THEN plog.err(...) (S-SISP-014/017) and therefore
-- never raise. Because the plog stub is transactional (Oracle's plog ran in an autonomous
-- transaction), a log line written just before RAISE E_ABORT would be erased by the catching
-- handler's subtransaction rollback: every raise site hands its log line over in the
-- exception (MESSAGE_TEXT = the line, DETAIL = 'ERR'|'NOTICE') and the public handler emits
-- it once. Same line, same level, same order as Oracle.
--
-- ONE DELIBERATE DEVIATION FROM ORACLE, marked `-- DEVIATION(ORACLE-BUG)` at the site
-- (project-owner instruction: do not mimic broken Oracle behaviour, annotate the correction):
--   * is_host_up (S-SISP-009): Oracle queries mc.mon_server_connection WHERE mon_server_id IS
--     NULL -- a NOT NULL primary-key column -- so the query never returns a row, every peer is
--     "down", is_secondaryisp_all_peers_down is constantly TRUE and secondaryisp_alert has
--     never raised a 10050 event. The body's own comment (lines 135-138) names the intended
--     mc.host_connection_status query; it is used here, with MC.MONITORING's own definition of
--     "up" (COALESCE(con_int_type_id, 0) = 0, SANG_UP = 0).
-- Everything else is Oracle-faithful.
--
-- Oracle NUMBER -> numeric/bigint (%TYPE anchors kept on the public signatures), VARCHAR2 ->
-- varchar/text, CLOB -> text, INSTR(s, d, 1, 1) -> strpos(s, d), substr(s, 0, n) -> substr(s,
-- 1, n) (Oracle treats position 0 as 1), TO_NUMBER -> ::bigint (a non-numeric token raises
-- 22P02, caught by the public WHEN OTHERS exactly where Oracle's VALUE_ERROR was),
-- plog.<level>() -> CALL osag.osag_plog_<level>(), OPEN/FETCH/CLOSE cursor -> SELECT ... INTO
-- (non-STRICT) ... LIMIT 1. Every other SELECT INTO is STRICT and carries the clause id of
-- the spec's strictness table row.
--
-- NULL concatenation (Pitfall 2 / spec checklist 1, S-SISP-019): Oracle's `||` treats NULL as
-- ''; PostgreSQL's `||` yields NULL. concat() has Oracle's semantics and is used wherever an
-- operand can be NULL (interface name, peers list, observed duration, ISP company name,
-- unknown-host id). Plain `||` is kept only where every operand is provably NOT NULL.
-- pretty_print_host_id_list's accumulator starts as NULL, not '' (Oracle's '' IS NULL;
-- S-SISP-012 -- a '' start would emit a leading ', ').

-- ------------------------------------------------------------------------------------
-- get_next_token (S-SISP-002, private): split i_string at the FIRST occurrence of i_delim.
-- Copied in Oracle from OSAG_IMPLICATION "to avoid circular dependency" (body lines 17-18).
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION guma2.secondary_isp__get_next_token(
    i_delim text, i_string text, OUT o_token text, OUT o_rest text)
LANGUAGE plpgsql
AS $fn$
DECLARE
    c_prefix CONSTANT text := 'SECONDARY_ISP.get_next_token(): ';
    l_pos integer;
BEGIN
    o_token := NULL;
    o_rest := NULL;

    -- Empty string handling. Oracle's LENGTH('') is NULL so its `= 0` test never fired, but
    -- the outcome for ''/NULL was "both outputs NULL" either way (S-SISP-002 (d)); the
    -- explicit test makes PostgreSQL's distinct '' behave identically.
    IF (i_string IS NULL OR length(i_string) = 0) THEN
        RETURN;
    END IF;

    l_pos := strpos(i_string, i_delim);

    -- Last token in string
    IF (l_pos = 0) THEN
        o_token := i_string;
        RETURN;
    END IF;

    IF (l_pos <> 1) THEN
        o_token := substr(i_string, 1, l_pos - 1);
    END IF;

    IF ((l_pos + length(i_delim)) <= length(i_string)) THEN
        o_rest := substr(i_string, l_pos + length(i_delim));
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        CALL osag.osag_plog_err(c_prefix || 'unexpected error 99: ' || SQLERRM);
        RAISE;
END;
$fn$;
REVOKE ALL ON FUNCTION guma2.secondary_isp__get_next_token(text, text) FROM PUBLIC;

-- ------------------------------------------------------------------------------------
-- secondaryisp_parse_syslog (S-SISP-003/004, private): parse a line like
-- "Jul 29 16:51:27 v1 nursed: NURSE:SECONDARYISP:ALERT All tunnels down (interface=eth0,
-- peers=1027|1028|1029) [state=Alert, observed=420s]". i_host_id is unused (as in Oracle).
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION guma2.secondary_isp__secondaryisp_parse_syslog(
    i_host_id bigint, i_data text, OUT o_interface text, OUT o_peers text, OUT o_since text)
LANGUAGE plpgsql
AS $fn$
DECLARE
    c_prefix CONSTANT text := 'SECONDARY_ISP.secondaryisp_parse_syslog(): ';
    l_before_token text;
    l_after_token text;
BEGIN
    -- Parse line up to 'NURSE:SECONDARYISP:'
    SELECT t.o_token, t.o_rest INTO l_before_token, l_after_token
    FROM guma2.secondary_isp__get_next_token('NURSE:SECONDARYISP:', i_data) t;
    IF (l_after_token IS NULL) THEN
        RAISE EXCEPTION '%', concat(c_prefix, 'can''t  parse NURSE:SECONDARYISP:ALERT line (1): ', i_data) USING ERRCODE = 'OS020', DETAIL = 'ERR';
    END IF;

    -- Parse line up to '(interface='
    SELECT t.o_token, t.o_rest INTO l_before_token, l_after_token
    FROM guma2.secondary_isp__get_next_token('(interface=', l_after_token) t;
    IF (l_after_token IS NULL) THEN
        RAISE EXCEPTION '%', concat(c_prefix, 'can''t  parse NURSE:SECONDARYISP:ALERT line (2): ', i_data) USING ERRCODE = 'OS020', DETAIL = 'ERR';
    END IF;

    -- Parse line up to ', peers='
    SELECT t.o_token, t.o_rest INTO l_before_token, l_after_token
    FROM guma2.secondary_isp__get_next_token(', peers=', l_after_token) t;
    IF (l_after_token IS NULL) THEN
        RAISE EXCEPTION '%', concat(c_prefix, 'can''t  parse NURSE:SECONDARYISP:ALERT line (3): ', i_data) USING ERRCODE = 'OS020', DETAIL = 'ERR';
    END IF;

    o_interface := l_before_token;

    -- Parse line up to ') [state='
    SELECT t.o_token, t.o_rest INTO l_before_token, l_after_token
    FROM guma2.secondary_isp__get_next_token(') [state=', l_after_token) t;
    IF (l_after_token IS NULL) THEN
        RAISE EXCEPTION '%', concat(c_prefix, 'can''t  parse NURSE:SECONDARYISP:ALERT line (4): ', i_data) USING ERRCODE = 'OS020', DETAIL = 'ERR';
    END IF;

    o_peers := l_before_token;

    -- Parse line up to 'observed='
    SELECT t.o_token, t.o_rest INTO l_before_token, l_after_token
    FROM guma2.secondary_isp__get_next_token('observed=', l_after_token) t;
    IF (l_after_token IS NULL) THEN
        RAISE EXCEPTION '%', concat(c_prefix, 'can''t  parse NURSE:SECONDARYISP:ALERT line (5): ', i_data) USING ERRCODE = 'OS020', DETAIL = 'ERR';
    END IF;

    -- Parse line up to ']' -- unchecked in Oracle too (S-SISP-003).
    SELECT t.o_token, t.o_rest INTO l_before_token, l_after_token
    FROM guma2.secondary_isp__get_next_token(']', l_after_token) t;
    o_since := l_before_token;
END;
$fn$;
REVOKE ALL ON FUNCTION guma2.secondary_isp__secondaryisp_parse_syslog(bigint, text) FROM PUBLIC;

-- ------------------------------------------------------------------------------------
-- is_host_up (S-SISP-009, private): does connection monitoring report the host as up?
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION guma2.secondary_isp__is_host_up(i_host_id bigint)
RETURNS boolean
LANGUAGE plpgsql
AS $fn$
DECLARE
    c_prefix CONSTANT text := 'SECONDARY_ISP.is_host_up(): ';
    l_con_int_type_id bigint;
BEGIN
    -- DEVIATION(ORACLE-BUG): Oracle (ddl/src/pkgb/guma2_secondary_isp.sql:140-142) reads
    --   SELECT status FROM mc.mon_server_connection WHERE mon_server_id IS NULL AND host_id = ...
    -- but MON_SERVER_ID is part of that table's primary key and NOT NULL (schema.oracle.sql
    -- line 126), so the predicate can never match: NO_DATA_FOUND for every host, every peer
    -- "down", and secondaryisp_alert never raised a 10050 event. The body's own comment
    -- (lines 135-138, "code using new mc.host_connection_status table (not yet available)")
    -- names the intended query, used here. "Up" is MC.MONITORING's own definition --
    -- nvl(con_int_type_id, 0) = 0 (mc_monitoring.sql:459, SANG_UP = 0) -- rather than the
    -- literal IS NULL of line 144, because collate_conn_status stores NULL and 0 alike for
    -- an up host (mc_monitoring.sql:706). Spec: S-SISP-009. S-SISP-002 strictness table
    -- site #1: STRICT + Oracle's own two-arm handler.
    SELECT conn.con_int_type_id INTO STRICT l_con_int_type_id
    FROM mc.host_connection_status conn
    WHERE conn.host_id = i_host_id;

    IF COALESCE(l_con_int_type_id, 0) = 0 THEN
        RETURN TRUE;
    ELSE
        RETURN FALSE;
    END IF;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        -- Host apparently doesn't exist! It certainly isn't up...
        RETURN FALSE;
    WHEN OTHERS THEN
        RAISE EXCEPTION '%', c_prefix || 'error: ' || SQLERRM USING ERRCODE = 'OS020', DETAIL = 'ERR';
END;
$fn$;
REVOKE ALL ON FUNCTION guma2.secondary_isp__is_host_up(bigint) FROM PUBLIC;

-- ------------------------------------------------------------------------------------
-- secondaryisp_interface_info (S-SISP-005/006/007, private): interface description, WAN
-- managed flag and ISP company name of the named interface of the host.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION guma2.secondary_isp__secondaryisp_interface_info(
    i_host_id bigint, i_interface_name text,
    OUT o_interface_desc varchar, OUT o_wan_managed smallint, OUT o_isp_company varchar)
LANGUAGE plpgsql
AS $fn$
DECLARE
    -- Oracle-verbatim prefix: it says "secondary_interface_info", not the routine's real
    -- name (S-SISP-006).
    c_prefix CONSTANT text := 'SECONDARY_ISP.secondary_interface_info(): ';
BEGIN
    -- Strictness table site #2: STRICT; NO_DATA_FOUND handled below; TOO_MANY_ROWS (an
    -- interface linked to several ISP links) propagates to the public WHEN OTHERS as in
    -- Oracle (S-SISP-007).
    SELECT i.description, isp.wan_managed, ispc.name
    INTO STRICT o_interface_desc, o_wan_managed, o_isp_company
    FROM mss.interface i
             JOIN mss.interface2isp_link i2isp ON i2isp.interface_id = i.id
             JOIN mss.isp_link isp ON isp.id = i2isp.isp_link_id
             JOIN stop.company ispc ON isp.company_id = ispc.id
    WHERE i.host_id = i_host_id AND i.name = i_interface_name;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE EXCEPTION '%', concat(c_prefix, 'can''t get information about interface ', i_interface_name, ' of host ', i_host_id) USING ERRCODE = 'OS020', DETAIL = 'ERR';
END;
$fn$;
REVOKE ALL ON FUNCTION guma2.secondary_isp__secondaryisp_interface_info(bigint, text) FROM PUBLIC;

-- ------------------------------------------------------------------------------------
-- is_secondaryisp_all_peers_down (S-SISP-010, private): TRUE iff no peer in the '|' list
-- is up. Empty list -> TRUE. A non-numeric token raises (22P02, Oracle VALUE_ERROR) and
-- is caught by the public WHEN OTHERS.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION guma2.secondary_isp__is_secondaryisp_all_peers_down(i_peers text)
RETURNS boolean
LANGUAGE plpgsql
AS $fn$
DECLARE
    l_before_token text;
    l_after_token text;
    l_peer_host_id bigint;
BEGIN
    l_after_token := i_peers;
    WHILE l_after_token IS NOT NULL LOOP
        SELECT t.o_token, t.o_rest INTO l_before_token, l_after_token
        FROM guma2.secondary_isp__get_next_token('|', l_after_token) t;
        l_peer_host_id := l_before_token::bigint;
        IF guma2.secondary_isp__is_host_up(l_peer_host_id) THEN
            RETURN FALSE;
        END IF;
    END LOOP;

    RETURN TRUE;
END;
$fn$;
REVOKE ALL ON FUNCTION guma2.secondary_isp__is_secondaryisp_all_peers_down(text) FROM PUBLIC;

-- ------------------------------------------------------------------------------------
-- comma_join (S-SISP-012, private): append i_element to io_string with ', ' between.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE guma2.secondary_isp__comma_join(INOUT io_string text, i_element text)
LANGUAGE plpgsql
AS $fn$
BEGIN
    IF io_string IS NULL THEN
        io_string := i_element;
    ELSE
        io_string := io_string || ', ' || i_element;
    END IF;
END;
$fn$;
REVOKE ALL ON PROCEDURE guma2.secondary_isp__comma_join(text, text) FROM PUBLIC;

-- ------------------------------------------------------------------------------------
-- pretty_print_host_id_list (S-SISP-012, private): "ID1|ID2|ID3" -> "name1, name2, name3";
-- an unknown id renders as "unknown(hostid:ID)".
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION guma2.secondary_isp__pretty_print_host_id_list(i_peers text)
RETURNS varchar
LANGUAGE plpgsql
AS $fn$
DECLARE
    l_before_token text;
    l_after_token text;
    l_host_id bigint;
    l_host_name mss.host.name%TYPE;
    -- Oracle initialises this to '' (body line 247), which IS NULL in Oracle -- the first
    -- comma_join therefore takes the "io_string IS NULL" arm. NULL here, not '' (Pitfall 2).
    l_pretty_string text := NULL;
BEGIN
    l_after_token := i_peers;
    WHILE l_after_token IS NOT NULL LOOP
        SELECT t.o_token, t.o_rest INTO l_before_token, l_after_token
        FROM guma2.secondary_isp__get_next_token('|', l_after_token) t;
        l_host_id := l_before_token::bigint;

        -- fetch host name. Strictness table site #3: STRICT + Oracle's own handler.
        BEGIN
            SELECT host.name INTO STRICT l_host_name
            FROM mss.host
            WHERE host.id = l_host_id;

            -- Note: HREF links in MC events is not a good idea, because links could change
            -- (Oracle comment, lines 261-263).
            CALL guma2.secondary_isp__comma_join(l_pretty_string, l_host_name);

        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                -- host not found ??
                CALL guma2.secondary_isp__comma_join(l_pretty_string, concat('unknown(hostid:', l_host_id, ')'));
        END;
    END LOOP;

    RETURN l_pretty_string;
END;
$fn$;
REVOKE ALL ON FUNCTION guma2.secondary_isp__pretty_print_host_id_list(text) FROM PUBLIC;

-- ------------------------------------------------------------------------------------
-- secondaryisp_alert (S-SISP-001, 004-014, 019): process NURSE:SECONDARYISP:ALERT messages
-- (MON-215). i_logdate is unused, as in Oracle (S-SISP-001).
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE guma2.secondary_isp_secondaryisp_alert(
    i_host_id mss.host.id%TYPE,
    i_logdate guma2.syslog_message.log_date%TYPE,
    i_data guma2.syslog_message.message%TYPE)
LANGUAGE plpgsql
AS $fn$
DECLARE
    c_prefix CONSTANT text := 'SECONDARY_ISP.secondaryisp_alert(): ';
    -- C_SEC_ISP_OUTAGE_EVENT_TYPE: 10050 is "ISP down" (package constant, body line 11)
    c_sec_isp_outage_event_type CONSTANT numeric := 10050;
    l_interface text;
    l_peers text;
    l_down_since text;
    l_wan_managed smallint;
    l_interface_desc varchar;
    l_isp_company varchar;
    l_event_id numeric;
    v_abort_msg text;
    v_abort_level text;
BEGIN
    -- Parse syslog line
    SELECT t.o_interface, t.o_peers, t.o_since INTO l_interface, l_peers, l_down_since
    FROM guma2.secondary_isp__secondaryisp_parse_syslog(i_host_id, i_data) t;

    -- Get some information about this interface. In particular: is it WAN managed?
    SELECT t.o_interface_desc, t.o_wan_managed, t.o_isp_company INTO l_interface_desc, l_wan_managed, l_isp_company
    FROM guma2.secondary_isp__secondaryisp_interface_info(i_host_id, l_interface) t;

    -- Ignore this message if the link is not WAN managed (S-SISP-008)
    IF l_wan_managed = 0 THEN
        RAISE EXCEPTION '%', concat(c_prefix, 'Ignoring secondary ISP outage, because not WAN managed (host: ', i_host_id, ', interface: ', l_interface, ')') USING ERRCODE = 'OS020', DETAIL = 'NOTICE';
    END IF;

    -- Ignore this message if all peers are down (S-SISP-011)
    -- (because this is likely the reason for all tunnels to be down)
    IF guma2.secondary_isp__is_secondaryisp_all_peers_down(l_peers) THEN
        RAISE EXCEPTION '%', concat(c_prefix, 'Ignoring secondary ISP outage, because all peers down (host: ', i_host_id, ', interface: ', l_interface, ')') USING ERRCODE = 'OS020', DETAIL = 'NOTICE';
    END IF;

    -- Add an event (S-SISP-013). concat(): l_interface, both pretty-printed lists and
    -- l_down_since may be NULL (S-SISP-019).
    CALL tt.event_interface_newevent_new(
            l_event_id,
            c_sec_isp_outage_event_type,
            i_host_id,
        -- public comment:
            concat('Secondary ISP Outage', chr(10),
                   chr(10),
                   'All VPN tunnels through one ISP link are down. This could mean that the ISP link is down.', chr(10),
                   chr(10),
                   'Open Systems Mission Control will start the WAN Management ISP Down process.', chr(10),
                   chr(10),
                   'Host:       ', guma2.secondary_isp__pretty_print_host_id_list(i_host_id::text), chr(10),
                   'Interface:  ', l_interface, ' (', l_interface_desc, ')', chr(10),
                   'ISP name:   ', l_isp_company, chr(10),
                   'VPN peers:  ', guma2.secondary_isp__pretty_print_host_id_list(l_peers), chr(10),
                   'Down since: ', l_down_since, chr(10)),
        -- private comment:
            'This host is subscribed to WAN Management.' || chr(10) ||
            chr(10) ||
            'To Do:' || chr(10) ||
            chr(10) ||
            'Execute this process: https://control.open.ch/docs/x/wBlbB'
        );

EXCEPTION
    -- S-SISP-014: E_ABORT is the expected "ignore this message" exit; everything else is
    -- logged. The procedure never raises to its caller.
    WHEN SQLSTATE 'OS020' THEN
        -- Oracle: NULL; -- the log line had already been written by plog's AUTONOMOUS
        -- transaction at the raise site. The PostgreSQL plog stub is transactional
        -- (osag_plog.FINDINGS.md): this handler's subtransaction rollback would erase a row
        -- written before RAISE. The raise sites therefore hand their log line over in the
        -- exception (MESSAGE = text, DETAIL = level) and it is emitted here, once.
        GET STACKED DIAGNOSTICS v_abort_msg = MESSAGE_TEXT, v_abort_level = PG_EXCEPTION_DETAIL;
        IF v_abort_level = 'NOTICE' THEN
            CALL osag.osag_plog_notice(v_abort_msg);
        ELSE
            CALL osag.osag_plog_err(v_abort_msg);
        END IF;
    WHEN OTHERS THEN
        CALL osag.osag_plog_err(c_prefix || 'unexpected error 99: ' || SQLERRM);
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- secondaryisp_ok (S-SISP-001, 004-008, 015-017, 019): process NURSE:SECONDARYISP:OK
-- messages. No peers check; instead the host must have an unresolved ticket.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE guma2.secondary_isp_secondaryisp_ok(
    i_host_id mss.host.id%TYPE,
    i_logdate guma2.syslog_message.log_date%TYPE,
    i_data guma2.syslog_message.message%TYPE)
LANGUAGE plpgsql
AS $fn$
DECLARE
    c_prefix CONSTANT text := 'SECONDARY_ISP.secondaryisp_ok(): ';
    -- C_SEC_ISP_OK_EVENT_TYPE: 10100 is "connection up" (package constant, body line 14)
    c_sec_isp_ok_event_type CONSTANT numeric := 10100;
    l_interface text;
    l_peers text;
    l_up_since text;
    l_wan_managed smallint;
    l_interface_desc varchar;
    l_isp_company varchar;
    l_event_id numeric;
    l_unresolved_ticket_id tt.ticket.id%TYPE;
    v_abort_msg text;
    v_abort_level text;
BEGIN
    -- Parse syslog line
    SELECT t.o_interface, t.o_peers, t.o_since INTO l_interface, l_peers, l_up_since
    FROM guma2.secondary_isp__secondaryisp_parse_syslog(i_host_id, i_data) t;

    -- Get some information about this interface. In particular: is it WAN managed?
    SELECT t.o_interface_desc, t.o_wan_managed, t.o_isp_company INTO l_interface_desc, l_wan_managed, l_isp_company
    FROM guma2.secondary_isp__secondaryisp_interface_info(i_host_id, l_interface) t;

    -- Ignore this message if the link is not WAN managed (S-SISP-008)
    IF l_wan_managed = 0 THEN
        RAISE EXCEPTION '%', concat(c_prefix, 'Ignoring secondary ISP ok event, because not WAN managed (host: ', i_host_id, ', interface: ', l_interface, ')') USING ERRCODE = 'OS020', DETAIL = 'NOTICE';
    END IF;

    -- The logic for raising a "Secondary ISP Outage" event is rather complex and involves
    -- checking the current status of VPN peers. [...] The chosen solution here is to check
    -- if there is an non-resolved ticket for this host (Oracle comment, lines 388-402).
    -- S-SISP-015: Oracle's OPEN/FETCH/CLOSE of the highest-id unresolved ticket -- a plain
    -- (non-STRICT) INTO leaves the variable NULL on zero rows, exactly like the cursor.
    SELECT t.id INTO l_unresolved_ticket_id
    FROM tt.ticket t
    WHERE t.status_id < 100 AND host_id = i_host_id
    ORDER BY t.id DESC
    LIMIT 1;

    IF l_unresolved_ticket_id IS NULL THEN
        -- No unresolved ticket found -> no event (see above)
        RAISE EXCEPTION '%', concat(c_prefix, 'Ignoring secondary ISP ok event, because no unresolved ticket was found (host: ', i_host_id, ', interface: ', l_interface, ')') USING ERRCODE = 'OS020', DETAIL = 'NOTICE';
    END IF;

    -- Add an event (S-SISP-016). The ticket found above is NOT passed on -- newevent_new
    -- decides where the event lands, as in Oracle.
    CALL tt.event_interface_newevent_new(
            l_event_id,
            c_sec_isp_ok_event_type,
            i_host_id,
        -- public comment:
            concat('Secondary ISP OK', chr(10),
                   chr(10),
                   'One or more VPN tunnels through one ISP link are up. The ISP link is thus apparently up.', chr(10),
                   chr(10),
                   'The WAN Management ISP Down process will be stopped.', chr(10),
                   chr(10),
                   'Host:       ', guma2.secondary_isp__pretty_print_host_id_list(i_host_id::text), chr(10),
                   'Interface:  ', l_interface, ' (', l_interface_desc, ')', chr(10),
                   'ISP name:   ', l_isp_company, chr(10),
                   'VPN peers:  ', guma2.secondary_isp__pretty_print_host_id_list(l_peers), chr(10),
                   'Up since:   ', l_up_since, chr(10)),
        -- private comment:
            'To Do:' || chr(10) ||
            chr(10) ||
            'Try to find a corresponding "Secondary ISP Outage" event. If there isn''t one, fast-resolve.'
        );
EXCEPTION
    -- S-SISP-017: same two-arm shape as the alert, but "unexpected error: " without "99".
    WHEN SQLSTATE 'OS020' THEN
        -- E_ABORT carrying its log line -- see secondaryisp_alert's handler.
        GET STACKED DIAGNOSTICS v_abort_msg = MESSAGE_TEXT, v_abort_level = PG_EXCEPTION_DETAIL;
        IF v_abort_level = 'NOTICE' THEN
            CALL osag.osag_plog_notice(v_abort_msg);
        ELSE
            CALL osag.osag_plog_err(v_abort_msg);
        END IF;
    WHEN OTHERS THEN
        CALL osag.osag_plog_err(c_prefix || 'unexpected error: ' || SQLERRM);
END;
$fn$;
