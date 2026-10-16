-- migration/pgsql/tt/escalation_interface.sql
--
-- Translation of TT.ESCALATION_INTERFACE (spec: migration/spec/tt.escalation_interface.md;
-- Oracle body: ddl/src/pkgb/tt_escalation_interface.sql, 223 lines). Names copied verbatim
-- from migration/mapping/name-map.csv's 5 ESCALATION_INTERFACE rows (all pg_kind=procedure).
-- No private routines. The package spec's `TYPE ref_cursor IS REF CURSOR` is unused by every
-- routine and is not ported.
--
-- THIS PACKAGE IS THE DYNAMIC-DISPATCH TARGET of tt.event_interface_exec_event_type_actions
-- (EXECUTE format('CALL %I.%I($1)') behind its TT.ESCALATION_INTERFACE allowlist, which names
-- exactly the four escalate_*/nop procedures below). Every routine therefore MUST stay a
-- PROCEDURE with a single numeric parameter (S-ESC-001).
--
-- Oracle's usage-audit call (XCUT-06): all 5 plog.AuditUsage sites (lines 22, 95, 159,
-- 210, 217 -- one per routine) DELETED, not ported. See escalation_interface.FINDINGS.md.
--
-- Oracle NUMBER -> numeric, VARCHAR2 -> varchar, DATE -> timestamp, SYSDATE ->
-- statement_timestamp(), plog.<level>() -> CALL osag.osag_plog_<level>(), SQL%ROWCOUNT ->
-- GET DIAGNOSTICS ... ROW_COUNT, `(+)` -> LEFT JOIN, unqualified `ticket`/`event` -> tt.*.
-- Every SELECT INTO is STRICT and carries the clause id of the spec's strictness table row
-- (-- S-ESC-0NN, site #N).
--
-- TWO DELIBERATE DEVIATIONS FROM ORACLE, both marked `-- DEVIATION(ORACLE-BUG)` at the site
-- (project-owner instruction: do not mimic broken Oracle behaviour, annotate the correction):
--   * escalate_os (S-ESC-008) and escalate_customer (S-ESC-014): Oracle's single shared
--     `WHEN NO_DATA_FOUND THEN v_host_id := NULL` handler covers the EVENT/TICKET lookups as
--     well as the HOST lookup, so a nonexistent event made Oracle continue with a NULL ticket
--     id -- a zero-row UPDATE and (escalate_os) an addevent_new(NULL ticket) call whose own
--     failure was swallowed inside addevent_new. Here the event/ticket lookups get their own
--     handler that logs via plog.err and RETURNs; the host lookup keeps Oracle's intended
--     "no host -> escalate anyway" handling (S-ESC-005) UNCHANGED.
-- Everything else -- including escalate_customer's body writing status 10 / event 60001
-- while its comments talk about a customer escalation (S-ESC-012) -- is Oracle-faithful.
--
-- NULL concatenation (Pitfall 2 / spec Checklist 1): Oracle's `||` treats NULL as '';
-- PostgreSQL's `||` yields NULL. concat() has Oracle's semantics and is used wherever an
-- operand can be NULL (p_event_id in error/debug lines, v_host_id/v_ticket_id in debug
-- lines, v_company_short in the ISP-outage public text, S-ESC-018). Plain `||` is kept
-- where every operand is provably NOT NULL at that point.

-- ------------------------------------------------------------------------------------
-- escalate_os (S-ESC-002..009, S-ESC-022): escalate the event's ticket to OS unless it is
-- already in an OS escalation (10/11) or its host is inactive.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.escalation_interface_escalate_os(p_event_id numeric)
LANGUAGE plpgsql
AS $fn$
DECLARE
    c_prefix CONSTANT text := 'tt.escalation_interface.escalate_os(): ';
    v_host_id numeric;
    v_ticket_id numeric;
    v_host_active numeric;
    v_escalation_status_id numeric;
    v_event_id numeric;
BEGIN
    -- Oracle line 23: fires BEFORE the lookups, so it is logged even on the corrected
    -- not-found path below (pinned by the regress golden).
    CALL osag.osag_plog_debug(concat('escalate_to_os called for event id ', p_event_id));

    BEGIN
        -- S-ESC-002 (site #1): get the ticket id for the event. STRICT.
        SELECT e.ticket_id INTO STRICT v_ticket_id
        FROM tt.event e
        WHERE e.id = p_event_id;

        -- S-ESC-002 (site #2): get the escalation status from the ticket. STRICT.
        SELECT escalation_status_id INTO STRICT v_escalation_status_id FROM tt.ticket WHERE id = v_ticket_id;

        -- S-ESC-002 (site #3): get the host id from the ticket. STRICT.
        SELECT t.host_id INTO STRICT v_host_id
        FROM tt.ticket t
        WHERE t.id = v_ticket_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            -- DEVIATION(ORACLE-BUG): Oracle (ddl/src/pkgb/tt_escalation_interface.sql:45-48)
            -- shares ONE handler across sites #1-#4 that only does `v_host_id := NULL` and
            -- carries on. For a nonexistent event (site #1) that leaves v_ticket_id /
            -- v_escalation_status_id NULL, so line 55's IN (10,11) is not true, line 60's
            -- `v_host_id IS NULL` IS true, and Oracle runs `UPDATE tt.ticket ... WHERE id =
            -- NULL` (0 rows) plus addevent_new(NULL ticket, 60001, ...) whose NO_DATA_FOUND
            -- is swallowed and logged as "unknown error for ticket:" inside addevent_new
            -- (tt_event_interface.sql:825-827): an "escalation" of nothing, surfacing only as
            -- a misleading addevent_new log line. Corrected per S-ESC-008: log here, RETURN,
            -- no side effects, no exception. Site #4 (host) keeps Oracle's handling below.
            CALL osag.osag_plog_err(concat(c_prefix, 'event with id ', p_event_id,
                ' or its ticket not found. This is needed for escalation. Aborting escalation.'));
            RETURN;
    END;

    BEGIN
        -- S-ESC-002 (site #4) / S-ESC-005: is the host active? A NULL host_id (no row can
        -- match) or a missing mss.host row both land in the handler -- Oracle's intended
        -- "if no host was specified we need escalation anyway" (line 59), preserved.
        SELECT h.active INTO STRICT v_host_active
        FROM mss.host h
        WHERE h.id = v_host_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_host_id := NULL;
    END;

    CALL osag.osag_plog_debug(concat('ticket id is ', v_ticket_id));
    CALL osag.osag_plog_debug(concat('host id is ', v_host_id));

    -- S-ESC-003: if the ticket is already in an escalation to os we don't do anything.
    -- S-ESC-007: any other status (0, 20) falls through -- a customer escalation is
    -- overridden to OS.
    IF (v_escalation_status_id IN (10, 11)) THEN
        RETURN;
    END IF;

    -- S-ESC-004 / S-ESC-005 / S-ESC-006: escalate if the host is active or there is none.
    IF (v_host_active = 1 OR v_host_id IS NULL) THEN
        CALL osag.osag_plog_debug('escalate ticket ' || v_ticket_id);

        -- update escalation status and date of ticket; escalation_status_id 10 means
        -- escalation to os
        UPDATE tt.ticket SET escalation_status_id = 10, last_escalation_date = statement_timestamp() WHERE id = v_ticket_id;

        -- S-ESC-009: insert the escalation event -- NO handler here, matching Oracle; the
        -- ticket_closed error addevent_new re-raises for a closed ticket propagates out.
        CALL tt.event_interface_addevent_new(v_event_id,
                                             v_ticket_id,
                                             60001,
                                             v_host_id,
                                             'Starting escalation to Open Systems Mission Control',
                                             'Event added by tt.escalation_interface.escalate_os. Caused by event ' || p_event_id);
    END IF;
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- escalate_customer (S-ESC-009..014): despite the name (and Oracle's own comments, which
-- talk about a customer escalation / event 60101 / status 20), the BODY escalates to OS --
-- status 10, event 60001 -- and is translated as the body says (S-ESC-012). Differs from
-- escalate_os in its gate (ANY non-zero status returns) and in adding the event only when
-- its race-guarded UPDATE actually changed a row.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.escalation_interface_escalate_customer(p_event_id numeric)
LANGUAGE plpgsql
AS $fn$
DECLARE
    c_prefix CONSTANT text := 'tt.escalation_interface.escalate_customer(): ';
    v_ticket_id numeric;
    v_host_id numeric;
    v_host_active numeric;
    v_escalation_status_id numeric;
    v_event_id numeric;
    v_rows integer;
BEGIN
    BEGIN
        -- S-ESC-010 (site #5): get the ticket id for the event. STRICT.
        SELECT e.ticket_id INTO STRICT v_ticket_id
        FROM tt.event e
        WHERE e.id = p_event_id;

        -- S-ESC-010 (site #6): escalation status and host id of the ticket, one select.
        SELECT t.escalation_status_id, t.host_id INTO STRICT v_escalation_status_id, v_host_id
        FROM tt.ticket t
        WHERE t.id = v_ticket_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            -- DEVIATION(ORACLE-BUG): same shared-handler shape as escalate_os
            -- (ddl/src/pkgb/tt_escalation_interface.sql:114-117). For a nonexistent event
            -- Oracle continued with a NULL ticket: line 121's `NULL <> 0` is not true (the
            -- comparison is NULL-unsafe), line 126's `v_host_id IS NULL` is true, the UPDATE
            -- on line 127 matches zero rows, SQL%ROWCOUNT = 0 skips addevent_new -- a
            -- completely SILENT no-op for a request to escalate an event that does not
            -- exist. Corrected per S-ESC-014: same (absent) data effect, but the failure is
            -- logged instead of swallowed without a trace.
            CALL osag.osag_plog_err(concat(c_prefix, 'event with id ', p_event_id,
                ' or its ticket not found. This is needed for escalation. Aborting escalation.'));
            RETURN;
    END;

    BEGIN
        -- S-ESC-010 (site #7): host active? NULL/missing host -> v_host_id := NULL, as Oracle.
        SELECT h.active INTO STRICT v_host_active
        FROM mss.host h
        WHERE h.id = v_host_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_host_id := NULL;
    END;

    -- S-ESC-011: we only escalate to a customer if there is no other escalation in process.
    -- (Oracle's `<> 0` is NULL-unsafe, but v_escalation_status_id can no longer be NULL
    -- here: the column is NOT NULL and the corrected handler above returned otherwise.)
    IF (v_escalation_status_id <> 0) THEN
        RETURN;
    END IF;

    -- S-ESC-012 / S-ESC-013: if no host was specified we need escalation anyway.
    IF (v_host_active = 1 OR v_host_id IS NULL) THEN
        UPDATE tt.ticket SET escalation_status_id = 10, last_escalation_date = statement_timestamp() WHERE ticket.id = v_ticket_id AND escalation_status_id <> 10;
        GET DIAGNOSTICS v_rows = ROW_COUNT;

        -- if we really changed the status, insert an event (S-ESC-009: no handler here).
        IF (v_rows > 0) THEN
            CALL tt.event_interface_addevent_new(v_event_id, v_ticket_id,
                                                 60001,
                                                 v_host_id,
                                                 'Starting escalation to Open Systems Mission Control',
                                                 'Event added by tt.escalation_interface.escalate_customer. Caused by event ' || p_event_id);
        END IF;
    END IF;
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- escalate_isp_outage_to_os (S-ESC-015..019): open a NEW hidden trouble ticket describing
-- the ISP outage. The six-table join is Oracle's exactly: e->t->h inner, h->sc inner,
-- e->ec and t->tc outer (`(+)` -> LEFT JOIN), host = NVL(e.host_id, t.host_id).
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.escalation_interface_escalate_isp_outage_to_os(p_event_id numeric)
LANGUAGE plpgsql
AS $fn$
DECLARE
    c_prefix CONSTANT varchar := 'tt.escalation_interface.escalate_isp_outage_to_os(): ';
    v_host_name varchar;
    v_company_short varchar;
    v_public_details varchar;
    v_private_details varchar;
    v_org_event_date timestamp;
    v_ticket_id numeric;
    v_event_id numeric;
BEGIN
    BEGIN
        -- S-ESC-015 (site #8): host name, company short, ORIGINAL ticket id. STRICT + the
        -- same two-arm handler Oracle has (S-ESC-016). Company on event or ticket may be
        -- null, fall back to the host's service company.
        SELECT h.name, COALESCE(ec.short, tc.short, sc.short), t.id
        INTO STRICT v_host_name, v_company_short, v_ticket_id
        FROM tt.event e
        JOIN tt.ticket t ON e.ticket_id = t.id
        JOIN mss.host h ON h.id = COALESCE(e.host_id, t.host_id)
        JOIN stop.company sc ON h.service_company_id = sc.id
        LEFT JOIN stop.company ec ON e.company_id = ec.id
        LEFT JOIN stop.company tc ON t.company_id = tc.id
        WHERE e.id = p_event_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            CALL osag.osag_plog_err(concat(c_prefix, 'either ticket, host or company not found for event with id: ', p_event_id, ' This is needed for escalation. Aborting escalation.'));
            RETURN;
        WHEN OTHERS THEN
            CALL osag.osag_plog_err(concat(c_prefix, 'Error while retrieving company and host name for event with id: ', p_event_id, ' This is needed for escalation. Aborting escalation.'));
            RETURN;
    END;

    -- S-ESC-017 (site #9): outside the handler in Oracle too; the row's existence was just
    -- proven by site #8, so no message shim -- STRICT, unhandled, exactly as Oracle.
    SELECT eventdate INTO STRICT v_org_event_date FROM tt.event WHERE id = p_event_id;

    -- S-ESC-018: texts are composed BEFORE v_ticket_id is reused as newticket_new's OUT
    -- parameter, so both carry the ORIGINAL ticket id. concat(): v_company_short may be
    -- NULL (nullable stop.company.short) and Oracle's `||` kept the rest of the text.
    v_public_details := concat('Critical ISP Outage escalation', chr(10),
        'Host: ', v_host_name, chr(10),
        'Company: ', v_company_short, chr(10),
        'Time of original event: ', to_char(v_org_event_date, 'YYYY-MM-DD HH24:MI:SS'), chr(10),
        'Original ticket ', v_ticket_id);

    v_private_details := 'To Do:' || chr(10)
        || 'https://open-systems.atlassian.net/wiki/x/3xYBAQ' || chr(10) || chr(10)
        || 'Do not add any further events to this escalation ticket.' || chr(10)
        || 'Use the original ticket ' || v_ticket_id || ' for tracking any work!' || chr(10)
        || 'This ticket is intentionally hidden from the customer, so do not merge it. ';

    -- S-ESC-019: create trouble ticket (type id 1) with incident report event (id 30005).
    -- Note: this ticket does not have the company set to hide it from the customer; set
    -- service component to 27 (other). OUT parameters first, matching the translated
    -- signature; SYSDATE passed explicitly as Oracle does (cast: the parameter is a naive
    -- timestamp, and CALL resolution has no implicit timestamptz -> timestamp cast).
    CALL tt.ticket_interface_newticket_new(v_ticket_id, v_event_id,
                                           1, 'Critical ISP Outage escalation',
                                           30005, NULL, v_public_details, v_private_details, NULL, NULL, TRUE, statement_timestamp()::timestamp, NULL, 27);
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- nop (S-ESC-020): the configurable "no action" event action. Never touches the database.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.escalation_interface_nop(p_event_id numeric)
LANGUAGE plpgsql
AS $fn$
BEGIN
    -- do nothing
    NULL;
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- clear_customer_escalation (S-ESC-021): one race-guarded UPDATE -- only a customer
-- escalation (20) is ever cleared, never an OS escalation. tt.ticket.id%TYPE kept, as the
-- established convention for %TYPE parameters (see osag_notify.sql).
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.escalation_interface_clear_customer_escalation(p_ticket_id tt.ticket.id%TYPE)
LANGUAGE plpgsql
AS $fn$
BEGIN
    -- clear the escalation status if it's set to customer escalation (20)
    UPDATE tt.ticket SET escalation_status_id = 0 WHERE id = p_ticket_id AND escalation_status_id = 20;
END;
$fn$;
