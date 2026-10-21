-- migration/pgsql/tt/event_interface.sql
--
-- Translation of TT.EVENT_INTERFACE (spec: migration/spec/tt.event_interface.md; Oracle
-- body: ddl/src/pkgb/tt_event_interface.sql, 1172 lines). Names copied verbatim from
-- migration/mapping/name-map.csv's 8 EVENT_INTERFACE rows; the 1 private routine
-- (is_esc_supp_active) has no name-map row and follows the double-underscore
-- private-routine convention plan 02-05 established for TT.OSAG_NOTIFY
-- (tt.event_interface__is_esc_supp_active, REVOKE ALL ... FROM PUBLIC).
--
-- THIS IS THE PILOT'S NAMED RESEARCH RISK: the corpus's only genuine dynamic-SQL site
-- (Oracle line 971, EXECUTE IMMEDIATE) lives in exec_event_type_actions. Translated per
-- migration/spec/DYNAMIC-SQL-TRACE.md's verdict, EXECUTE format(), with an explicit
-- allowlist gate BEFORE execution -- see the routine's own comments and
-- event_interface.FINDINGS.md for the full disposition.
--
-- Oracle's usage-audit call (XCUT-06): all 8 plog usage-audit call sites (one per public
-- routine; is_esc_supp_active is private and never had one) DELETED, not ported. See
-- event_interface.FINDINGS.md.
--
-- 34 single-row-fetch strictness sites, each carrying the verdict
-- migration/spec/tt.event_interface.md's own strictness table assigned it,
-- annotated with its clause ID (-- S-EVENT-0NN) so verdict and code sit together. 5
-- NO_DATA_FOUND handlers, 0 TOO_MANY_ROWS handlers (but 1 STRUCTURALLY REACHABLE
-- TOO_MANY_ROWS site, S-EVENT-001 -- see below), 6 OTHERS handlers -- the large majority
-- are `STRICT, unhandled`: that IS the Oracle contract, preserved even where it reads
-- like a latent bug.
--
-- S-EVENT-001 (newevent_new's mss.host2service join): mss.host2service's PK is
-- (host_id, service_id), NOT unique on host_id alone, so TOO_MANY_ROWS is structurally
-- reachable here. Oracle's local handler only names the NO_DATA_FOUND arm; a
-- TOO_MANY_ROWS falls to WHEN OTHERS THEN RAISE, and newevent_new has NO procedure-level
-- EXCEPTION block of its own, so it propagates fully unhandled to newevent_new's own
-- caller. Preserved exactly (native PL/pgSQL STRICT TOO_MANY_ROWS, SQLSTATE P0003).
--
-- S-EVENT-019 (addevent_new's merged-ticket lookup): Oracle's trailing ROWNUM=1
-- structurally caps the query at one row before the fetch can ever see more than one --
-- translated as a trailing LIMIT 1 (not merely dropped), so PL/pgSQL's own STRICT
-- likewise never sees more than one row here, matching Oracle's guarantee.
--
-- S-EVENT-015 (Pitfall 2): v_scope_info (both newevent_new and addevent_new) is seeded
-- from '' at declaration, not left at its Oracle-implicit NULL start -- Oracle's
-- NULL||'x'='x' seeds the accumulator; PL/pgSQL's NULL||'x'=NULL would silently drop the
-- ' company_id='/' host_id=' suffix from the alerting-log line. v_details_public is
-- normalized via NULLIF(substr(...), '') at both its SUBSTRB-emulating assignment
-- (newevent_new) and its receipt from tt.ticket_interface_replace_id_placeholders
-- (addevent_new, since Oracle's SUBSTRB('')=NULL collapse happens on the OTHER side of
-- that cross-package call) -- both gate a later `IS NOT NULL` check that would otherwise
-- silently diverge for an empty-string p_details_public.
--
-- Schema gap found and fixed (see migration/test/schema-fixes/23_p11_fixes.sql):
-- tt.event.contact_zitadel_id and tt.ticket.contact_zitadel_id, both inserted by this
-- package, do not exist in ddl/migrated/ (ora2pg's conversion of the base export) --
-- changes/changelog-current.sql:2197,2199 adds them via Liquibase but the migrated
-- snapshot predates that changelog. Added as an additive schema-fix, not an edit to
-- ddl/migrated/ (D-P7).
--
-- Schema gap found and DELIBERATELY NOT fixed (Rule 4 -- architectural, not mechanical):
-- newevent_new's admin-permission check queries auth.permission and
-- auth.mv_service_access, NEITHER of which exists anywhere in the checked-in Oracle
-- export or the migrated schema (only auth.user_permission / auth.user_company_scope /
-- auth.mv_service_access-as-materialized-view-not-loaded exist, per plan 02-09's
-- profile-based auth model). This looks like Oracle-side dead/stale code the live
-- database has already moved past. Ported VERBATIM per the spec (translate faithfully,
-- do not silently "fix" a latent Oracle bug) -- no test reaches this branch. See
-- event_interface.FINDINGS.md.
--
-- Oracle's from_tz(cast(x as timestamp), 'EUROPE/ZURICH') sites (ux_timeout_start
-- assignments): the migrated tt.ticket.ux_timeout_start / this INSERT's source columns
-- are plain (tz-naive) `timestamp` in the migrated PostgreSQL schema (ora2pg dropped the
-- WITH TIME ZONE Oracle originally declared) -- there is no naive-timestamp target left
-- to attach a zone to, so these sites read the source column back verbatim instead.
--
-- Mutually recursive with TT.TICKET_INTERFACE (plan 02-12, same wave) at 12 call sites
-- out / 22 in (S-EVENT-045) -- PL/pgSQL does not resolve CALL/function targets at CREATE
-- time, so this file loads regardless of load order; only *running* the affected paths
-- needs TICKET_INTERFACE to exist. Confirmed live for this plan (see FINDINGS.md).

-- =====================================================================================
-- PRIVATE routine (PL/pgSQL has no forward declarations; Oracle's package body forward-
-- declares this one at the top precisely because it is defined last in Oracle source).
-- =====================================================================================

-- ------------------------------------------------------------------------------------
-- is_esc_supp_active: tests whether an active service window currently suppresses
-- escalation for this host/action/event-type combination.
-- S-EVENT-040 (site #30) / S-EVENT-041 (site #31): both COUNT(*) aggregates, no STRICT
-- concern (always exactly one row).
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION tt.event_interface__is_esc_supp_active(
    p_host_id numeric, p_event_action_id numeric, p_event_type_id numeric)
RETURNS boolean
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_guma_suppressor_exists integer;
    v_conn_suppressor_exists integer;
BEGIN
    IF (p_event_type_id = 10002 OR
        p_event_type_id = 10005 OR
        p_event_type_id = 10007 OR
        p_event_type_id = 10009) THEN

        -- S-EVENT-040 (site #30): COUNT aggregate, no STRICT concern.
        SELECT COUNT(*) INTO v_guma_suppressor_exists
        FROM tt.ticket t
                 JOIN tt.service_window s ON (s.ticket_id = t.id)
                 JOIN tt.host2service_window h2s ON (h2s.service_window_id = s.id)
                 LEFT JOIN tt.maintenance_window m ON (s.id = m.service_window_id)
                 LEFT JOIN tt.cust_maintenance_window cm ON (s.id = cm.service_window_id)
        WHERE t.status_id < 101 AND s.end_date > statement_timestamp() AND s.start_date < statement_timestamp()
          AND (m.disable_guma_escalation = 1 OR cm.disable_guma_escalation = 1) AND h2s.host_id = p_host_id;

        IF (v_guma_suppressor_exists > 0) THEN
            RETURN TRUE;
        END IF;
    END IF;

    IF (p_event_action_id = 2 -- connection down
        OR (p_event_action_id = 1 AND p_event_type_id = 10050) -- isp down
        ) THEN

        -- S-EVENT-041 (site #31): COUNT aggregate, no STRICT concern.
        SELECT COUNT(*) INTO v_conn_suppressor_exists
        FROM tt.ticket t
                 JOIN tt.service_window s ON (s.ticket_id = t.id)
                 JOIN tt.host2service_window h2s ON (h2s.service_window_id = s.id)
                 LEFT JOIN tt.maintenance_window m ON (s.id = m.service_window_id)
                 LEFT JOIN tt.cust_maintenance_window cm ON (s.id = cm.service_window_id)
        WHERE t.status_id < 101 AND s.end_date > statement_timestamp() AND s.start_date < statement_timestamp()
          AND (m.disable_conn_escalation = 1 OR cm.disable_conn_escalation = 1) AND h2s.host_id = p_host_id;

        IF (v_conn_suppressor_exists > 0) THEN
            RETURN TRUE;
        END IF;
    END IF;

    RETURN FALSE;
END;
$fn$;
REVOKE ALL ON FUNCTION tt.event_interface__is_esc_supp_active(numeric, numeric, numeric) FROM PUBLIC;

-- =====================================================================================
-- PUBLIC routines (names verbatim from migration/mapping/name-map.csv)
-- =====================================================================================

-- ------------------------------------------------------------------------------------
-- ticket_type_for_event_type (S-EVENT-034): the package's only FUNCTION. Pure IF/ELSIF
-- lookup, zero database access, zero calls to any other routine -- confirmed by the spec
-- to have NO transitive COMMIT hazard. No FUNCTION/PROCEDURE-COMMIT collision exists for
-- this routine.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION tt.event_interface_ticket_type_for_event_type(p_event_type_id numeric)
RETURNS numeric
LANGUAGE plpgsql
IMMUTABLE
AS $fn$
DECLARE
    v_ticket_type_id numeric;
BEGIN
    -- ticket type 3rd party incident: isp outage / tunnel notification / vpn up / vpn down
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
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- moveevent (S-EVENT-033, S-EVENT-046, S-EVENT-047).
--
-- DEVIATION(ORACLE-BUG): Oracle's body (ddl/src/pkgb/tt_event_interface.sql:880) runs
--   UPDATE tt.event e SET ticket_id = p_newticket_id WHERE ticket_id = p_oldticket_id;
-- which never references p_event_id, so ONE call re-parents EVERY event of the old
-- ticket. Oracle's own header comment (line 866) says so: "FIXME / BROKEN the
-- p_event_id is not actually used! This moves ALL events of a ticket. Looks like this
-- code is never run." The package spec (ddl/src/pkg/tt_event_interface.sql:67-73)
-- promises the opposite: move ONE event; nothing happens if it is not on the old
-- ticket; warn if the event or the new ticket does not exist. Per the branch owner's
-- instruction ("Don't mimic broken behaviour of oracle routines, but annotate/explain
-- what changed with the correction") this translation implements the documented
-- contract: the UPDATE is restricted to id = p_event_id AND ticket_id = p_oldticket_id
-- (S-EVENT-046); a wrong old ticket is a silent no-op and a nonexistent event logs
-- 'event does not exist' with the same v_errmsg prefix (S-EVENT-047). Everything else --
-- the three-parameter non-NULL gate, the STRICT new-ticket existence check and its
-- 3-arm swallow-and-log handler (S-EVENT-033) -- is unchanged. See
-- event_interface.FINDINGS.md, "Deviations from Oracle".
--
-- SELECT INTO site #26: STRICT + its own 3-arm handler (NO_DATA_FOUND / DUP_VAL_ON_INDEX
-- -> unique_violation / OTHERS), all three swallow (log, never re-raise).
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.event_interface_moveevent(
    p_event_id numeric, p_oldticket_id numeric, p_newticket_id numeric)
LANGUAGE plpgsql
AS $fn$
DECLARE
    c_prefix CONSTANT text := 'tt.event_interface.moveevent(): ';
    v_dummy numeric;
    v_errmsg varchar;
    v_moved bigint;
BEGIN
    v_errmsg := 'cannot move event '||p_event_id||' from ticket '||p_oldticket_id||' to ticket '||p_newticket_id||': ';
    IF (p_event_id IS NOT NULL AND p_newticket_id IS NOT NULL AND p_oldticket_id IS NOT NULL) THEN
        -- S-EVENT-033 (site #26): STRICT + all three handler arms.
        SELECT id INTO STRICT v_dummy FROM tt.ticket WHERE id = p_newticket_id; -- check whether this ticket really exists...
        -- DEVIATION(ORACLE-BUG) S-EVENT-046: Oracle has no "id = p_event_id" predicate here.
        UPDATE tt.event e SET ticket_id = p_newticket_id
        WHERE e.id = p_event_id AND e.ticket_id = p_oldticket_id;
        GET DIAGNOSTICS v_moved = ROW_COUNT;
        IF v_moved = 0 THEN
            -- S-EVENT-047: not on the old ticket (or already on the new one) -> silent
            -- no-op; event missing altogether -> warning (package-spec contract,
            -- ddl/src/pkg/tt_event_interface.sql:70-71).
            SELECT count(*) INTO v_dummy FROM tt.event WHERE id = p_event_id;
            IF v_dummy = 0 THEN
                CALL osag.osag_plog_warning(c_prefix||v_errmsg||'event does not exist');
            END IF;
        END IF;
    END IF;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        CALL osag.osag_plog_warning(c_prefix||v_errmsg||'new ticket does not exist');
    WHEN UNIQUE_VIOLATION THEN
        CALL osag.osag_plog_info(c_prefix||v_errmsg||'event is already in new ticket');
    WHEN OTHERS THEN
        CALL osag.osag_plog_err(c_prefix||v_errmsg||'unknown error: '||SQLERRM);
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- add_history_event (S-EVENT-042): NO EXCEPTION block of any kind -- the sequence pull,
-- the INSERT, and the unconditional notify call all propagate any failure fully
-- unhandled to this routine's caller.
-- SELECT INTO site #32: sequence pull via nextval(), no STRICT concern.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.event_interface_add_history_event(
    OUT p_event_id numeric,
    p_ticket_id numeric,
    p_event_type_id numeric,
    p_host_id numeric,
    p_company_id numeric,
    p_details_public varchar,
    p_details_private varchar DEFAULT NULL,
    p_public_event boolean DEFAULT TRUE,
    p_eventdate timestamptz DEFAULT statement_timestamp(),
    p_contact_id numeric DEFAULT NULL,
    p_zitadel_contact_id numeric DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_public_event numeric;
BEGIN
    IF (p_public_event) THEN
        v_public_event := 1;
    ELSE
        v_public_event := 0;
    END IF;

    -- S-EVENT-042 (site #32): sequence pull, no STRICT concern.
    SELECT nextval('tt.event_sequence') INTO STRICT p_event_id;

    INSERT INTO tt.event
        (id, type_id, host_id, company_id, eventdate, details_public, details_private,
         public_event, ticket_id, contact_id, contact_zitadel_id)
    VALUES (p_event_id, p_event_type_id, p_host_id, p_company_id, p_eventdate,
            p_details_public, p_details_private, v_public_event, p_ticket_id, p_contact_id,
            p_zitadel_contact_id::varchar);

    -- S-EVENT-042: unconditional notify call -- zero exception handling anywhere in this
    -- routine, so any failure here propagates fully unhandled too.
    CALL tt.osag_notify_event_notify(p_event_id, p_ticket_id);
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- demote_event (S-EVENT-043): zero EXCEPTION blocks anywhere -- a bad p_event_id
-- propagates NO_DATA_FOUND fully unhandled. "no data found" message-parity shim (XCUT-01
-- convention, matching tt.util/tt.osag_notify/auth.osag_auth): re-raises the SAME
-- SQLSTATE (P0002) with Oracle's ORA-01403 text instead of PL/pgSQL's native "query
-- returned no rows" -- required for regress golden parity
-- (migration/test/regress/expected/tt__event_interface__errors.out). The history-event
-- write is commented out in Oracle source ("for the time being, we do not write history
-- events for this") -- reproduced as Oracle's actual current behavior, not filled in.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.event_interface_demote_event(p_event_id numeric, p_contact_id numeric)
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_ticket_id numeric;
    v_host_id numeric;
    v_company_id numeric;
    v_private_details varchar;
    v_public_details varchar;
BEGIN
    UPDATE tt.event SET demoted = 1 WHERE id = p_event_id;

    -- S-EVENT-043 (site #33): STRICT, zero handler anywhere in Oracle's demote_event.
    BEGIN
        SELECT e.ticket_id, t.host_id, t.company_id
        INTO STRICT v_ticket_id, v_host_id, v_company_id
        FROM tt.event e, tt.ticket t
        WHERE e.id = p_event_id AND e.ticket_id = t.id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE EXCEPTION 'no data found' USING ERRCODE = 'P0002';
    END;

    v_public_details := NULL;
    v_private_details := 'Event ' || p_event_id || ' demoted';

    -- NOTE: for the time being, we do not write history events for this...
    -- Add a history event of type "event demotion" (100011) -- commented out in Oracle
    -- source too (ddl/src/pkgb/tt_event_interface.sql:1131-1133), reproduced as-is.
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- promote_event (S-EVENT-044): the exact mirror of demote_event -- same PK-join shape,
-- same total absence of an EXCEPTION block, same "no data found" shim requirement, same
-- commented-out history-event write.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.event_interface_promote_event(p_event_id numeric, p_contact_id numeric)
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_ticket_id numeric;
    v_host_id numeric;
    v_company_id numeric;
    v_private_details varchar;
    v_public_details varchar;
BEGIN
    UPDATE tt.event SET demoted = 0 WHERE id = p_event_id;

    -- S-EVENT-044 (site #34): STRICT, zero handler anywhere in Oracle's promote_event.
    BEGIN
        SELECT e.ticket_id, t.host_id, t.company_id
        INTO STRICT v_ticket_id, v_host_id, v_company_id
        FROM tt.event e, tt.ticket t
        WHERE e.id = p_event_id AND e.ticket_id = t.id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE EXCEPTION 'no data found' USING ERRCODE = 'P0002';
    END;

    v_public_details := NULL;
    v_private_details := 'Event ' || p_event_id || ' promoted';

    -- NOTE: for the time being, we do not write history events for this (reproduced
    -- as-is, ddl/src/pkgb/tt_event_interface.sql:1165-1167).
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- exec_event_type_actions (S-EVENT-035..039): loops over event_action/event_type_action
-- rows matching the event's type; for each, either dispatches suppressed-escalation
-- logging (S-EVENT-039) or resolves a procedure name (DBPROP lookup or table column) and
-- DYNAMICALLY dispatches it -- S-EVENT-038, the package's ONE static_resolution:
-- incomplete site (Oracle line 971). No procedure-level EXCEPTION block of its own.
--
-- v_proc_str is declared ONCE, OUTSIDE the loop, matching Oracle exactly
-- (ddl/src/pkgb/tt_event_interface.sql:899) -- it is NEVER reset between cursor
-- iterations in Oracle source. A stale non-NULL value from an earlier action row can, in
-- principle, carry over to a later row lacking its own procedure identifier. This is an
-- Oracle-side latent quirk, preserved faithfully here, not fixed.
--
-- S-EVENT-038 / DYNAMIC-SQL-TRACE.md verdict: EXECUTE format(), allowlist-validated.
-- Full disposition, injection analysis, and the allowlist-scope open question in
-- event_interface.FINDINGS.md.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.event_interface_exec_event_type_actions(p_event_id numeric)
LANGUAGE plpgsql
AS $fn$
DECLARE
    c_prefix CONSTANT text := 'tt.event_interface.exec_event_type_actions(): ';
    v_event_type_id numeric;
    v_host_id numeric;
    v_proc_str varchar;
    v_ticket_id tt.ticket.id%TYPE;
    v_esc_event_id numeric;
    event_action_rec RECORD;
    v_parts text[];
    v_schema text;
    v_object text;
BEGIN
    CALL osag.osag_plog_debug(c_prefix || 'running exec_event_type_action for event ' || p_event_id);

    -- S-EVENT-035 (site #27): STRICT, mixed by caller -- no handler in this routine
    -- itself; propagation fate depends on which of this package's own routines called it
    -- (unhandled via newevent_new, swallowed via addevent_new's own outer handler).
    SELECT type_id INTO STRICT v_event_type_id
    FROM tt.event
    WHERE id = p_event_id;

    CALL osag.osag_plog_debug(c_prefix || 'event_type_id is ' || v_event_type_id);

    -- S-EVENT-036 (site #28): STRICT + local 2-arm handler, both swallow.
    BEGIN
        SELECT e.host_id INTO STRICT v_host_id FROM tt.event e
        WHERE e.id = p_event_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_host_id := NULL;
        WHEN OTHERS THEN
            CALL osag.osag_plog_err(c_prefix||'unexpected error while determing host for event with id ' ||p_event_id||': '||SQLERRM);
    END;

    CALL osag.osag_plog_debug(c_prefix || 'host_id is ' || v_host_id);

    -- S-EVENT-037 (site #29): STRICT, mixed by caller -- same shape as S-EVENT-035.
    SELECT ticket_id INTO STRICT v_ticket_id
    FROM tt.event
    WHERE id = p_event_id;

    CALL osag.osag_plog_debug(c_prefix || 'ticket_id is ' || v_ticket_id);

    FOR event_action_rec IN
        SELECT ea.name, ea.procedure_name, ea.procedure_key_id, eta.event_action_id
        FROM tt.event_action ea, tt.event_type_action eta
        WHERE eta.event_type_id = v_event_type_id
          AND eta.event_action_id = ea.id
    LOOP
        IF (NOT tt.event_interface__is_esc_supp_active(v_host_id, event_action_rec.event_action_id, v_event_type_id)) THEN
            -- check if there is a procedure key and a host
            IF (event_action_rec.procedure_key_id IS NOT NULL AND v_host_id IS NOT NULL) THEN
                CALL osag.osag_plog_debug(c_prefix || 'looking up procedure name in DBPROP using key with id ' || event_action_rec.procedure_key_id);
                v_proc_str := mss.osag_dbprop_get_string_by_host_key_id(v_host_id::int, event_action_rec.procedure_key_id::int);
            END IF;

            IF (v_proc_str IS NULL) THEN
                v_proc_str := event_action_rec.procedure_name;
            END IF;

            CALL osag.osag_plog_debug(c_prefix || 'event action : ' || v_proc_str);

            -- execute the procedure
            -- N.B: the only procedure left configured in tt.event_action today is:
            -- tt.escalation_interface.escalate_os() (see masterdata/TT/event_action.csv)
            IF (v_proc_str IS NOT NULL) THEN
                -- Step 1 (trace step 1): rewrite Oracle's 3-part <schema>.<package>.
                -- <routine> name to this project's flattened 2-part package_in_name
                -- convention -- new work the Oracle source never had to do.
                v_parts := string_to_array(v_proc_str, '.');
                v_schema := v_parts[1];
                v_object := array_to_string(v_parts[2:array_length(v_parts, 1)], '_');

                -- Step 2 (trace step 2): validate the resolved (schema, object) pair
                -- against the explicit TT.ESCALATION_INTERFACE allowlist -- the NARROW
                -- option the trace names as safer than blind %I-quoted execution. The
                -- BROADER alternative ("any single-NUMBER-arg procedure") is the trace's
                -- own explicitly UNRESOLVED sub-item -- NOT decided here, carried forward
                -- to FINDINGS.md/Phase 4 unchanged, not silently narrowed to a guess.
                --
                -- DELIBERATELY OUTSIDE the swallowing BEGIN block below: silently
                -- swallowing a rejected allowlist match would defeat the entire point of
                -- this mitigation (threat T-02-44/T-02-45) -- an operator must be able to
                -- observe that a config value tried to call an unintended callee.
                IF (v_schema, v_object) NOT IN (
                    ('tt', 'escalation_interface_escalate_os'),
                    ('tt', 'escalation_interface_escalate_customer'),
                    ('tt', 'escalation_interface_escalate_isp_outage_to_os'),
                    ('tt', 'escalation_interface_nop')
                ) THEN
                    RAISE EXCEPTION '%resolved procedure %.% is not on the TT.ESCALATION_INTERFACE allowlist -- refusing to execute (see migration/spec/DYNAMIC-SQL-TRACE.md)',
                        c_prefix, v_schema, v_object;
                END IF;

                -- Step 3 (trace step 3): execute with the bind parameter kept as a
                -- genuine parameter (USING p_event_id, never string-concatenated).
                -- Oracle's own local WHEN OTHERS swallow-and-log is preserved here,
                -- UNCHANGED -- this trace only changes what happens on the success path,
                -- not this failure path.
                BEGIN
                    EXECUTE format('CALL %I.%I($1)', v_schema, v_object) USING p_event_id;
                EXCEPTION
                    WHEN OTHERS THEN
                        CALL osag.osag_plog_err(c_prefix||'unexpected error during procedure execution: '||SQLERRM);
                END;
            ELSE
                CALL osag.osag_plog_notice(c_prefix || 'no procedure executed for host: ' || v_host_id || ' on event of type: '||v_event_type_id);
            END IF;
        ELSE
            CALL osag.osag_plog_notice(c_prefix || 'escalation suppressed for event ' || p_event_id || ' due to active service window.');
            CALL tt.event_interface_addevent_new(v_esc_event_id, v_ticket_id, 60010, v_host_id,
                'Escalation suppressed for event ' || p_event_id || ' due to active service window.',
                'Event added by tt.event_interface.exec_event_type_actions.');
        END IF;
    END LOOP;
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- addevent_new (S-EVENT-016..032): adds an event to an EXISTING ticket. If the ticket is
-- merged, recurses onto the merge target (S-EVENT-019/020); if closed/deleted (status >
-- 101), raises the package's ONE intentionally re-raised exception (S-EVENT-021); else
-- inserts the event and runs the full downstream logic. Has its OWN top-level EXCEPTION
-- block (S-EVENT-032) that re-raises the named ticket_closed condition but swallows
-- (logs) every other error -- the package's one asymmetric handler.
--
-- Oracle error -20980 (EVENT_INTERFACE_STATE.S_ERRNO_TICKET_CLOSED) is mapped here to
-- custom SQLSTATE 'OS980' -- PROVISIONAL pending Phase 3's XCUT-01 authoritative
-- Oracle-code -> SQLSTATE mapping table (see event_interface.FINDINGS.md).
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.event_interface_addevent_new(
    OUT p_event_id numeric,
    p_ticket_id numeric,
    p_type_id numeric,
    p_host_id numeric,
    details_public varchar,
    details_private varchar DEFAULT NULL,
    p_contact_id numeric DEFAULT NULL,
    public_event boolean DEFAULT TRUE,
    eventdate timestamptz DEFAULT statement_timestamp(),
    notify_event boolean DEFAULT FALSE,
    p_zitadel_contact_id numeric DEFAULT NULL,
    p_peer_contact_id numeric DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
DECLARE
    c_prefix CONSTANT text := 'tt.event_interface.addevent_new(): ';

    pub_event numeric;
    ev_id numeric;
    v_company_id numeric;
    v_details_public varchar;
    v_details_private varchar;
    v_ticket_status numeric;
    v_ticket_type numeric;
    v_merged_ticket_id numeric;
    v_event_source numeric;
    v_ticket_has_service_window numeric;
    v_history_event_id numeric;
    v_fast_resolvable numeric;
    v_last_public_event_id numeric;
    v_recoverable_status_id numeric;
    v_summary_rel_events_count numeric;
    v_todo_relevant_events_count numeric;
    v_ux_timeout_start timestamp;
    v_change_request_pending numeric;
    v_pinned numeric;
    v_msg_firstline varchar;
    -- S-EVENT-015 (Pitfall 2): seeded from '' -- Oracle's NULL||'x'='x' would otherwise
    -- be lost.
    v_scope_info varchar := '';
    v_context text;
BEGIN
    -- S-EVENT-016 (site #14): STRICT, no local handler -- escalates to this routine's
    -- own outer WHEN OTHERS (S-EVENT-032).
    SELECT t.type_id, t.status_id
    INTO STRICT v_ticket_type, v_ticket_status
    FROM tt.ticket t
    WHERE t.id = p_ticket_id;

    -- S-EVENT-017 (site #15): STRICT, no local handler -- outer swallow.
    SELECT source INTO STRICT v_event_source FROM tt.event_type WHERE id = p_type_id;
    -- S-EVENT-018 (site #16): STRICT, no local handler -- outer swallow.
    SELECT autopin INTO STRICT v_pinned FROM tt.event_type WHERE id = p_type_id;

    IF (v_ticket_status = 110) THEN
        BEGIN
            -- S-EVENT-019 (site #17): STRICT + local NO_DATA_FOUND handler. Oracle's
            -- trailing ROWNUM=1 structurally caps this at one row before SELECT INTO can
            -- ever see more than one -- translated as LIMIT 1 (a corpus-wide mechanic,
            -- not merely dropped), so STRICT here likewise never sees TOO_MANY_ROWS.
            SELECT oracle.to_number(e.details_private) INTO STRICT v_merged_ticket_id
            FROM tt.event e
            WHERE e.ticket_id = p_ticket_id
              AND e.type_id = 100004
              AND oracle.to_number(e.details_private) != p_ticket_id
              AND EXISTS (SELECT 1 FROM tt.ticket t WHERE t.id = oracle.to_number(e.details_private))
            LIMIT 1;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_merged_ticket_id := -1;
        END;

        -- call addevent recursively with new ticket_id
        IF (v_merged_ticket_id > 0) THEN
            CALL tt.event_interface_addevent_new(p_event_id, v_merged_ticket_id,
                p_type_id, p_host_id, details_public, details_private, p_contact_id,
                public_event, eventdate, FALSE, p_zitadel_contact_id);
            -- attribute it to the merged ticket: for example nurse OK events
            UPDATE tt.event SET org_ticket_id = p_ticket_id
            WHERE id = p_event_id AND org_ticket_id IS NULL;
        END IF;
    -- handle closed, deleted, archived tickets
    ELSIF (v_ticket_status > 101) THEN
        -- S-EVENT-021: the package's ONE intentionally re-raised (never swallowed)
        -- exception.
        CALL osag.osag_plog_notice(c_prefix || ' Ticket with id '|| p_ticket_id || ' is closed/deleted, cannot add event!');
        RAISE EXCEPTION 'Ticket with id % is closed/deleted', p_ticket_id USING ERRCODE = 'OS980';
    ELSE
        -- else we add the event to the ticket
        -- S-EVENT-022 (site #18): sequence pull, no STRICT concern.
        SELECT nextval('tt.event_sequence') INTO STRICT ev_id;
        p_event_id := ev_id;

        -- S-EVENT-045: forward call into TT.TICKET_INTERFACE (cycle partner, plan 02-12,
        -- same wave) -- resolved at first execution, not at CREATE time. S-EVENT-015
        -- (second hazard, Checklist dimension 1): NULLIF normalizes a possible ''
        -- returned by the (not-yet-translated) callee at the boundary this routine's OWN
        -- later IS NOT NULL gate depends on -- the ''-producing boundary is technically
        -- inside TT.TICKET_INTERFACE, but this routine's own gate must see the collapse.
        v_details_public := NULLIF(tt.ticket_interface_replace_id_placeholders(details_public, p_ticket_id, ev_id), '');
        v_details_private := NULLIF(tt.ticket_interface_replace_id_placeholders(details_private, p_ticket_id, ev_id), '');

        IF (public_event) THEN
            pub_event := 1;
        ELSE
            pub_event := 0;
        END IF;

        -- if a host id is given we select the company from the mss.host table
        IF (p_host_id IS NOT NULL) THEN
            -- S-EVENT-023 (site #19): STRICT, no local handler -- outer swallow.
            SELECT h.service_company_id INTO STRICT v_company_id
            FROM mss.host h
            WHERE h.id = p_host_id;
        ELSE
            -- S-EVENT-023 (site #20): STRICT, no local handler -- outer swallow.
            SELECT company_id INTO STRICT v_company_id
            FROM tt.ticket
            WHERE ticket.id = p_ticket_id;
        END IF;

        -- log alerting events (S-EVENT-015: addevent_new's own copy of the accumulator
        -- hazard).
        IF (v_details_public IS NOT NULL AND p_type_id IN (
            10007, 10006, 10005, 10004, 10014, 10002, 10013, 10009, 10021, 10008, 10030
        )) THEN
            -- S-EVENT-048: no newline -> Oracle SUBSTR(x, 1, -1) is NULL. A raw substr()
            -- raised 22011 here, which the outer handler swallowed AFTER p_event_id was
            -- assigned -- the event was silently lost (observed live 2026-10-21).
            v_msg_firstline := NULLIF(substr(v_details_public, 1, GREATEST(strpos(v_details_public, chr(10)) - 1, 0)), '');
            IF (v_company_id IS NOT NULL) THEN
                v_scope_info := v_scope_info || ' company_id=' || v_company_id;
            END IF;
            IF (p_host_id IS NOT NULL) THEN
                v_scope_info := v_scope_info || ' host_id=' || p_host_id;
            END IF;
            CALL osag.osag_plog_notice(c_prefix || 'insert event' || ' msgshort="' || v_msg_firstline || '" event_type_id=' || p_type_id || ' ticket=' || p_ticket_id || v_scope_info);
        END IF;

        INSERT INTO tt.event
            (id, type_id, host_id, company_id, eventdate, details_public, details_private,
             public_event, ticket_id, contact_id, pinned, contact_zitadel_id, peer_contact_id)
        VALUES (ev_id, p_type_id, p_host_id, v_company_id, eventdate,
                v_details_public, v_details_private, pub_event, p_ticket_id, p_contact_id,
                v_pinned, p_zitadel_contact_id::varchar, p_peer_contact_id);

        -- update ux timeout if this is a public MC event (event type ids between 40000
        -- and 60000). ux_timeout_start is a naive `timestamp` column in the migrated
        -- schema (ora2pg dropped Oracle's WITH TIME ZONE) -- Oracle's from_tz(...) attach
        -- has no naive-timestamp target left, so this reads the just-inserted event's own
        -- eventdate back verbatim.
        IF (public_event AND p_type_id >= 40000 AND p_type_id < 60000) THEN
            -- S-EVENT-024 (site #21): STRICT, no local handler -- outer swallow.
            SELECT e.eventdate INTO STRICT v_ux_timeout_start FROM tt.event e WHERE e.id = ev_id;
            UPDATE tt.ticket SET ux_timeout_start = v_ux_timeout_start WHERE id = p_ticket_id;
            CALL tt.ticket_interface_update_ux_timeout_for_ticket(p_ticket_id, FALSE);
        END IF;

        -- set the ticket status to hot (status 3) if the event was one of the listed types
        IF (p_type_id IN (10002, 10003, 10008, 10013, 10014, 10040, 10050, 10060, 10100, 30002, 30009, 30011, 30004, 30013, 30014, 30016, 30018, 30019, 30020, 30021, 30022, 30023) AND v_ticket_status <> 3) THEN
            CALL tt.ticket_interface_change_status(p_ticket_id, 3, p_contact_id, NULL, 'new event added', NULL, NULL, NULL, NULL, p_zitadel_contact_id);
        END IF;

        -- execute the event type actions, this triggers escalations if necessary
        CALL tt.event_interface_exec_event_type_actions(p_event_id);

        -- turn an isp outage (4), customer information (5) ticket into a trouble ticket (1)
        IF (v_ticket_type IN (4, 5)) THEN
            -- S-EVENT-026 (site #22): STRICT, no local handler -- outer swallow.
            SELECT source INTO STRICT v_event_source FROM tt.event_type WHERE id = p_type_id;
            IF (v_event_source IN (3, 4, 5) AND pub_event = 1) THEN
                CALL tt.ticket_interface_change_type(v_history_event_id, p_ticket_id, 1, NULL);
            END IF;
        END IF;

        -- connection down event -> incident, unless the ticket has an active service window
        IF (p_type_id = 10001 AND (v_ticket_type NOT IN (1, 4, 6))) THEN
            -- S-EVENT-027 (site #23): COUNT aggregate, no STRICT concern.
            SELECT COUNT(*) INTO v_ticket_has_service_window
            FROM tt.service_window s, tt.ticket t
            WHERE t.id = p_ticket_id
              AND t.id = s.ticket_id
              AND statement_timestamp() BETWEEN s.start_date AND s.end_date
              AND t.status_id < 101; -- status 101 is resolved

            IF (v_ticket_has_service_window = 0) THEN
                CALL tt.ticket_interface_change_type(v_history_event_id, p_ticket_id, 1, NULL);
            ELSE
                CALL osag.osag_plog_notice('ticket type of ticket ' || p_ticket_id || ' not changed due to active service window.');
            END IF;
        END IF;

        -- only do customer notifications for tickets that are not monitoring outage
        IF (v_ticket_type != 6) THEN
            IF (notify_event) THEN
                CALL tt.osag_notify_event_notify(ev_id, p_ticket_id);
            END IF;
        END IF;

        -- update the ticket status_valid_until_date if MCC updated the ticket publicly visible
        IF (public_event AND p_type_id IN (30001, 30008, 30009, 40002, 50001, 50002, 50003)) THEN
            CALL tt.util_update_status_valid_until(p_ticket_id);
        END IF;

        -- we'll query some more ticket attributes (don't move this up, the attributes
        -- might change until here)
        -- S-EVENT-030 (site #24): STRICT, no local handler -- outer swallow.
        SELECT t.fast_resolvable, t.last_public_event_id, t.recoverable_status_id, t.summary_relevant_events_count, t.todo_relevant_events_count
        INTO STRICT v_fast_resolvable, v_last_public_event_id, v_recoverable_status_id, v_summary_rel_events_count, v_todo_relevant_events_count
        FROM tt.ticket t
        WHERE t.id = p_ticket_id;

        IF (v_fast_resolvable > 0 AND pub_event > 0 AND v_event_source NOT IN (1, 2, 10)) THEN
            v_fast_resolvable := 0;
        END IF;

        IF (p_type_id = 30016) THEN
            v_fast_resolvable := 1;
        END IF;

        IF (pub_event > 0 AND v_event_source NOT IN (2, 10)) THEN
            v_last_public_event_id := ev_id;
            UPDATE tt.ticket
            SET last_public_event_id = v_last_public_event_id
            WHERE id = p_ticket_id;
        END IF;

        IF (pub_event > 0 AND v_event_source NOT IN (1, 2, 6, 10)) THEN
            v_summary_rel_events_count := v_summary_rel_events_count + 1;
            v_todo_relevant_events_count := v_todo_relevant_events_count + 1;
        END IF;

        IF ((pub_event > 0 AND v_event_source NOT IN (1, 2, 3, 6, 10) AND p_type_id NOT IN (30022, 50022)) OR p_type_id = 30016) THEN
            v_recoverable_status_id := NULL;
        END IF;

        -- S-EVENT-031 (site #25): COUNT aggregate, no STRICT concern.
        SELECT COUNT(*) INTO v_change_request_pending
        FROM tt.change_request cr
        WHERE cr.ticket_id = p_ticket_id AND cr.change_request_state_id IN (2, 6);

        IF (v_change_request_pending = 0 AND v_recoverable_status_id = 61) THEN
            v_recoverable_status_id := NULL;
        END IF;

        UPDATE tt.ticket
        SET fast_resolvable = v_fast_resolvable,
            recoverable_status_id = v_recoverable_status_id,
            summary_relevant_events_count = v_summary_rel_events_count,
            todo_relevant_events_count = v_todo_relevant_events_count
        WHERE id = p_ticket_id;
    END IF;
EXCEPTION
    -- S-EVENT-032: two-arm procedure-level handler. ticket_closed re-raises (mapped to
    -- custom SQLSTATE 'OS980', PROVISIONAL); everything else is logged (with a PostgreSQL
    -- exception-context capture standing in for Oracle's own error-backtrace formatter,
    -- for which there is no Oracle-identical PostgreSQL equivalent) and swallowed.
    WHEN OTHERS THEN
        IF SQLSTATE = 'OS980' THEN
            RAISE;
        END IF;
        GET STACKED DIAGNOSTICS v_context = PG_EXCEPTION_CONTEXT;
        CALL osag.osag_plog_err(c_prefix||'unknown error for ticket:'||p_ticket_id||' : '||SQLERRM);
        CALL osag.osag_plog_notice(v_context);
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- newevent_new (S-EVENT-001..014): adds a brand-new event -- drops it if the host is
-- inactive or an open service window disables events; searches open tickets of the same
-- host for one to append to instead of opening a new one; if none is found, opens a new
-- ticket. NO procedure-level EXCEPTION block at all -- only two small inline
-- BEGIN...EXCEPTION blocks exist inside its body; anything else raised propagates fully
-- unhandled to newevent_new's own caller.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.event_interface_newevent_new(
    OUT p_event_id numeric,
    p_type_id numeric,
    p_host_id numeric,
    p_details_public varchar,
    p_details_private varchar DEFAULT NULL,
    p_contact_id numeric DEFAULT NULL,
    p_public_event boolean DEFAULT TRUE,
    p_eventdate timestamptz DEFAULT statement_timestamp(),
    p_ticket_type_id numeric DEFAULT NULL,
    p_service_component_id numeric DEFAULT NULL,
    p_zitadel_contact_id numeric DEFAULT NULL,
    p_company_id numeric DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
DECLARE
    c_prefix CONSTANT text := 'tt.event_interface.newevent(): ';

    pub_event numeric;
    subject varchar;
    event_subject varchar;
    v_event_id numeric;
    v_history_event_id numeric;
    v_company_id numeric;
    v_mss_service_id numeric;
    active numeric;
    v_new_source numeric; -- origin of this new event
    v_ticket_id numeric; -- id of existing ticket to append new event to
    v_ticket_type_id numeric;
    v_details_public varchar;
    v_details_private varchar;
    v_msg_firstline varchar;
    -- S-EVENT-015 (Pitfall 2): seeded from '' -- Oracle's NULL||'x'='x' would otherwise
    -- be lost, silently dropping the alerting-log suffix.
    v_scope_info varchar := '';

    v_monitoring_ticket_id numeric;
    v_collect_event_ticket_id numeric;
    v_disable_event_ticket_id numeric;
    v_recent_ticket_id numeric;
    v_recent_ticket_type numeric;
    v_recent_ticket_open_date timestamp;
    v_recent_event_type numeric;
    v_recent_event_source numeric;

    v_reason varchar := '';

    v_count numeric;

    v_confirmed numeric;
    v_fast_resolvable numeric;
BEGIN
    -- details are only 30000 characters long, cut after 30000 chars.
    -- S-EVENT-015 (second hazard): Oracle's SUBSTRB('',1,30000) collapses '' to NULL;
    -- substr() does not -- NULLIF at the boundary reproduces Oracle's collapse.
    v_details_public := NULLIF(substr(p_details_public, 1, 30000), '');
    v_details_private := NULLIF(substr(p_details_private, 1, 30000), '');
    v_company_id := p_company_id;

    -- if a host id is given we select the company from the mss.host table
    -- and the mss.service.id from the host2service table
    -- S-EVENT-001 (site #1): STRICT + local NO_DATA_FOUND handler; WHEN OTHERS
    -- re-raises. mss.host2service's PK spans (host_id, service_id), NOT unique on
    -- host_id alone, so TOO_MANY_ROWS is structurally reachable -- and newevent_new has
    -- NO procedure-level EXCEPTION block of its own, so a re-raised TOO_MANY_ROWS
    -- propagates fully unhandled to newevent_new's own caller. Preserved exactly.
    BEGIN
        IF (p_host_id IS NOT NULL) THEN
            SELECT h.service_company_id, h2s.service_id INTO STRICT v_company_id, v_mss_service_id
            FROM mss.host h, mss.host2service h2s
            WHERE h.id = p_host_id AND h.id = h2s.host_id;
        END IF;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            CALL osag.osag_plog_warning('host ID '||p_host_id||' is not attached to a service');
        WHEN OTHERS THEN
            RAISE;
    END;

    -- if a contact id is given we select the company_id from the contact table
    -- S-EVENT-002 (site #2): STRICT, no handler anywhere -- fully unhandled.
    IF (p_contact_id IS NOT NULL AND v_company_id IS NULL) THEN
        SELECT company_id INTO STRICT v_company_id
        FROM stop.contact
        WHERE contact.id = p_contact_id;
    END IF;

    -- ------------------------------------------------------------------------------------------
    -- [1] drop events from inactive services
    -- ------------------------------------------------------------------------------------------
    IF (p_host_id IS NOT NULL) THEN
        -- S-EVENT-003 (site #3): STRICT, no handler -- fully unhandled.
        SELECT h.active INTO STRICT active FROM mss.host h WHERE h.id = p_host_id;
        IF (active = 0) THEN
            CALL osag.osag_plog_info(c_prefix||'dropping event of type '|| p_type_id ||' for inactive host '|| p_host_id);
            RETURN;
        END IF;
    END IF;

    -- ------------------------------------------------------------------------------------------
    -- [2] drop events if an open service window requests this
    -- ------------------------------------------------------------------------------------------
    IF (v_company_id IS NOT NULL AND p_host_id IS NOT NULL) THEN
        -- S-EVENT-004 (site #4): COUNT aggregate, no STRICT concern.
        SELECT COUNT(*) INTO v_disable_event_ticket_id
        FROM tt.ticket t
                 JOIN tt.service_window s ON (s.ticket_id = t.id)
                 JOIN tt.host2service_window h2s ON (h2s.service_window_id = s.id)
                 LEFT JOIN tt.maintenance_window m ON (s.id = m.service_window_id)
                 LEFT JOIN tt.cust_maintenance_window cm ON (s.id = cm.service_window_id)
        WHERE t.status_id < 101 AND s.end_date > statement_timestamp() AND s.start_date < statement_timestamp()
          AND (m.disable_events = 1 OR cm.disable_events = 1) AND h2s.host_id = p_host_id;

        IF (v_disable_event_ticket_id > 0) THEN
            CALL osag.osag_plog_info(c_prefix||'dropping event of type ' || p_type_id || ' for host ' || p_host_id ||
                      '. Active service window with disable event flag on ticket ' || v_disable_event_ticket_id);
            RETURN;
        END IF;
    END IF;

    -- ------------------------------------------------------------------------------------------
    -- [3] Try to find an existing ticket to append this event to
    -- ------------------------------------------------------------------------------------------
    -- S-EVENT-005 (site #5): STRICT, no handler anywhere (sits between the two inline
    -- BEGIN blocks) -- fully unhandled.
    SELECT source INTO STRICT v_new_source FROM tt.event_type WHERE id = p_type_id;

    v_ticket_type_id := COALESCE(p_ticket_type_id, tt.event_interface_ticket_type_for_event_type(p_type_id));

    IF (v_new_source = 1 AND p_host_id IS NOT NULL) THEN
        BEGIN
            IF (v_company_id IS NOT NULL) THEN
                -- S-EVENT-006 (site #6): MIN aggregate, no STRICT concern.
                SELECT MIN(t.id) INTO v_monitoring_ticket_id
                FROM tt.ticket t
                WHERE t.company_id = v_company_id AND t.type_id = 6 AND t.status_id < 60;

                IF (v_monitoring_ticket_id IS NOT NULL) THEN
                    -- append this automatic event to the open monitoring ticket
                    v_ticket_id := v_monitoring_ticket_id;
                    v_ticket_type_id := 6;
                ELSE
                    -- S-EVENT-007 (site #7): MAX aggregate, no STRICT concern.
                    SELECT MAX(t.id) INTO v_collect_event_ticket_id
                    FROM tt.ticket t
                             JOIN tt.service_window s ON (s.ticket_id = t.id)
                             JOIN tt.host2service_window h2s ON (h2s.service_window_id = s.id)
                             LEFT JOIN tt.maintenance_window m ON (s.id = m.service_window_id)
                             LEFT JOIN tt.cust_maintenance_window cm ON (s.id = cm.service_window_id)
                    WHERE t.status_id < 101 AND s.end_date > statement_timestamp() AND s.start_date < statement_timestamp()
                      AND (m.collect_events = 1 OR cm.collect_events = 1) AND h2s.host_id = p_host_id;

                    IF (v_collect_event_ticket_id IS NOT NULL) THEN
                        v_ticket_id := v_collect_event_ticket_id;
                        v_reason := 'found open service window requesting event collection';
                    ELSE
                        -- S-EVENT-009: forward call into TT.TICKET_INTERFACE (cycle
                        -- partner, plan 02-12) -- resolved at first execution.
                        v_recent_ticket_id := tt.ticket_interface_get_next_recent_ticket(NULL, p_host_id, NULL, 24*3600);
                        WHILE (v_recent_ticket_id IS NOT NULL) LOOP
                            BEGIN
                                -- S-EVENT-008 (site #8): STRICT + local NO_DATA_FOUND
                                -- handler -- the loop simply continues to the next
                                -- candidate ticket, a miss is not fatal.
                                SELECT t.type_id, t.open_date, e.type_id, ety.source
                                INTO STRICT v_recent_ticket_type, v_recent_ticket_open_date, v_recent_event_type, v_recent_event_source
                                FROM tt.ticket t, tt.event e, tt.event_type ety
                                WHERE t.id = v_recent_ticket_id
                                  AND e.ticket_id = t.id
                                  AND e.type_id = ety.id
                                  AND e.id = (SELECT MIN(id) FROM tt.event WHERE ticket_id = t.id);

                                -- connection down (10001), isp outage (10003)
                                IF (p_type_id IN (10001, 10003) AND v_recent_event_type IN (10001, 10003, 10018)) THEN
                                    v_ticket_id := v_recent_ticket_id;
                                    v_reason := 'found recent ticket for connection down/isp outage';

                                    IF (p_type_id = 10001 AND v_recent_ticket_type = 4) THEN
                                        CALL tt.ticket_interface_change_type(v_history_event_id, v_ticket_id, 1, p_contact_id);
                                    END IF;

                                -- ids event: created less than one hour ago
                                ELSIF (p_type_id IN (10002, 10014) AND v_recent_event_type IN (10002, 10014)
                                    AND (statement_timestamp() - v_recent_ticket_open_date) < interval '1 hour') THEN
                                    v_ticket_id := v_recent_ticket_id;
                                    v_reason := 'found recent ticket for id alert/id/customer id notification';

                                -- don't append ids events to unrelated tickets
                                ELSIF (p_type_id IN (10002, 10014)) THEN
                                    NULL;

                                -- hardware installation event (10017): migration/installation ticket
                                ELSIF (p_type_id IN (10017) AND v_recent_ticket_type IN (8, 15)) THEN
                                    v_ticket_id := v_recent_ticket_id;
                                    v_reason := 'found recent migration/installation ticket for hardware installation event';
                                ELSIF (p_type_id IN (10017)) THEN
                                    NULL;

                                -- customer id notification DNIDS (10020)
                                ELSIF (p_type_id IN (10020) AND v_recent_event_type IN (10020)) THEN
                                    v_ticket_id := v_recent_ticket_id;
                                    v_reason := 'found recent ticket for customer id notification';
                                ELSIF (p_type_id IN (10020)) THEN
                                    NULL;

                                -- user synchronization error (10030)
                                ELSIF (p_type_id IN (10030) AND v_recent_event_type IN (10030)) THEN
                                    v_ticket_id := v_recent_ticket_id;
                                    v_reason := 'found recent ticket for user synchronization error';
                                ELSIF (p_type_id IN (10030)) THEN
                                    NULL;

                                -- others are appended to automatically generated trouble tickets
                                ELSIF (v_recent_event_source = 1 AND v_recent_ticket_type = 1) THEN
                                    IF (v_recent_event_type IN (10020, 10030, 10002, 10014, 10060)) THEN
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

                            IF (v_ticket_id IS NOT NULL) THEN
                                v_recent_ticket_id := NULL;
                            ELSE
                                v_recent_ticket_id := tt.ticket_interface_get_next_recent_ticket(v_recent_ticket_id, p_host_id, NULL, 24*3600);
                            END IF;
                        END LOOP;
                    END IF;
                END IF;
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                CALL osag.osag_plog_err(c_prefix||'unexpected error when trying to find appropriate ticket for automatically generated event: '||SQLERRM);
        END;
    END IF;

    -- ------------------------------------------------------------------------------------------
    -- [4] Append to existing ticket
    -- ------------------------------------------------------------------------------------------
    IF (v_ticket_id IS NOT NULL) THEN
        CALL osag.osag_plog_notice(c_prefix || 'appending event '||p_type_id||' from host '||p_host_id||' to ticket '||v_ticket_id||': '||v_reason);

        CALL tt.event_interface_addevent_new(p_event_id, v_ticket_id, p_type_id, p_host_id,
            v_details_public, v_details_private, p_contact_id, p_public_event, p_eventdate,
            FALSE, p_zitadel_contact_id);

        v_event_id := p_event_id;

        CALL tt.ticket_interface_change_status(v_ticket_id, 3, p_contact_id, NULL, 'new event added', NULL, NULL, NULL, NULL, p_zitadel_contact_id);

    -- ------------------------------------------------------------------------------------------
    -- [5] Create a new ticket
    -- ------------------------------------------------------------------------------------------
    ELSE
        CALL osag.osag_plog_notice(c_prefix || 'creating new ticket for event '||p_type_id||' from host '||p_host_id);

        IF (p_public_event) THEN
            pub_event := 1;
        ELSE
            pub_event := 0;
        END IF;

        -- default: use the event type name as the subject
        -- S-EVENT-010 (site #9): STRICT, no handler (after the ticket-search block
        -- closed) -- fully unhandled.
        SELECT name INTO STRICT subject
        FROM tt.event_type
        WHERE id = p_type_id;

        -- S-EVENT-048: Oracle's SUBSTR returns NULL for a length < 1 -- here INSTR = 0 (no
        -- newline in the details) gives length -1 and the ticket gets a NULL subject.
        -- pg_catalog.substr raises 22011 for a negative length instead; GREATEST(.., 0)
        -- + NULLIF reproduce Oracle's NULL (observed live 2026-10-21).
        IF (p_type_id = 30002 OR p_type_id = 30009 OR p_type_id = 40002 OR p_type_id = 10014 OR p_type_id = 10002) THEN
            subject := substr(v_details_public, 1, 100);
            subject := NULLIF(substr(subject, 1, GREATEST(strpos(subject, chr(10)) - 1, 0)), '');
        ELSIF p_type_id = 10004 OR p_type_id = 10005 OR
              p_type_id = 10006 OR p_type_id = 10007 OR
              p_type_id = 10008 OR p_type_id = 10009 OR
              p_type_id = 10020 OR
              p_type_id = 10021 THEN
            -- S-EVENT-048: same rule for the computed length (NULL if the type name is
            -- 95 characters or longer -- not the case for any current event type).
            event_subject := NULLIF(substr(v_details_public, 1, GREATEST(95 - length(subject), 0)), '');
            IF (strpos(event_subject, chr(10)) > 0) THEN
                event_subject := substr(event_subject, 1, strpos(event_subject, chr(10)) - 1);
            ELSIF (length(event_subject) = (95 - length(subject))) THEN
                event_subject := substr(event_subject, 1, length(event_subject) - 3) || '...';
            END IF;
            subject := subject || ': ' || event_subject;
        END IF;

        v_ticket_type_id := COALESCE(p_ticket_type_id, tt.event_interface_ticket_type_for_event_type(p_type_id));
        -- S-EVENT-011 (site #10): sequence pull, no STRICT concern.
        SELECT nextval('tt.ticket_sequence') INTO STRICT v_ticket_id;

        -- check if the given contact is an admin and therefore suitable as ticket owner
        v_count := 0;
        IF (v_mss_service_id IS NULL) THEN
            -- S-EVENT-012 (site #11): COUNT aggregate, no STRICT concern. NOTE:
            -- auth.permission does not exist in the checked-in schema export or the
            -- migrated schema (Rule-4 finding, see event_interface.FINDINGS.md) -- ported
            -- verbatim per the spec; no test reaches this branch.
            SELECT COUNT(*) INTO v_count
            FROM auth.permission p, auth.login l
            WHERE p.login_id = l.id AND l.contact_id = p_contact_id AND p.role_id = 2 AND p.company_id = v_company_id;
        ELSE
            -- S-EVENT-013 (site #12): COUNT aggregate, no STRICT concern. NOTE:
            -- auth.mv_service_access is a materialized view this pilot's template does
            -- not load (SCHEMA-FIXES.md) -- ported verbatim; no test reaches this branch.
            SELECT COUNT(*) INTO v_count
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

        -- if zitadel contact id is given we don't check the count (auth checked in the API)
        IF (v_count > 0 OR p_zitadel_contact_id IS NOT NULL) THEN
            INSERT INTO tt.ticket
                (id, type_id, contact_id, company_id, host_id, subject, mss_service_id,
                 service_confirmed, type_confirmed, fast_resolvable, service_component_id, contact_zitadel_id)
            VALUES (v_ticket_id, v_ticket_type_id, p_contact_id, v_company_id, p_host_id, subject,
                    v_mss_service_id, v_confirmed, v_confirmed, v_fast_resolvable, p_service_component_id,
                    p_zitadel_contact_id::varchar);
        ELSE
            INSERT INTO tt.ticket
                (id, type_id, contact_id, company_id, host_id, subject, mss_service_id,
                 service_confirmed, type_confirmed, fast_resolvable, service_component_id, contact_zitadel_id)
            VALUES (v_ticket_id, v_ticket_type_id, NULL, v_company_id, p_host_id, subject,
                    v_mss_service_id, v_confirmed, v_confirmed, v_fast_resolvable, p_service_component_id, NULL);
        END IF;

        CALL osag.osag_plog_debug(c_prefix || 'subject: ' || subject);

        -- set ux timeout (naive `timestamp` column -- see file header note)
        UPDATE tt.ticket SET ux_timeout_start = open_date WHERE id = v_ticket_id;
        CALL tt.ticket_interface_update_ux_timeout_for_ticket(v_ticket_id, TRUE);

        -- set the OUT variable p_event_id to the next event id
        -- S-EVENT-014 (site #13): sequence pull, no STRICT concern.
        SELECT nextval('tt.event_sequence') INTO STRICT p_event_id;

        -- log alerting events
        IF (v_details_public IS NOT NULL AND p_type_id IN (
            10007, 10006, 10005, 10004, 10014, 10002, 10013, 10009, 10021, 10008, 10030
        )) THEN
            -- S-EVENT-048: no newline -> Oracle SUBSTR(x, 1, -1) is NULL, the log line
            -- carries an empty msgshort; never an error.
            v_msg_firstline := NULLIF(substr(v_details_public, 1, GREATEST(strpos(v_details_public, chr(10)) - 1, 0)), '');
            IF (v_company_id IS NOT NULL) THEN
                v_scope_info := v_scope_info || ' company_id=' || v_company_id;
            END IF;
            IF (p_host_id IS NOT NULL) THEN
                v_scope_info := v_scope_info || ' host_id=' || p_host_id;
            END IF;
            CALL osag.osag_plog_notice(c_prefix || 'insert event' || ' msgshort="' || v_msg_firstline || '" event_type_id=' || p_type_id || ' ticket=' || v_ticket_id || v_scope_info);
        END IF;

        INSERT INTO tt.event
            (id, type_id, host_id, company_id, ticket_id, eventdate, details_public, details_private,
             public_event, contact_id, contact_zitadel_id)
        VALUES (p_event_id, p_type_id, p_host_id, v_company_id, v_ticket_id, p_eventdate,
                v_details_public, v_details_private, pub_event, p_contact_id, p_zitadel_contact_id::varchar);

        -- if public and not of source notification (2) or history (10), remember it as
        -- the last public event of the ticket
        IF (pub_event > 0 AND v_new_source NOT IN (2, 10)) THEN
            UPDATE tt.ticket SET last_public_event_id = p_event_id WHERE id = v_ticket_id;
        END IF;

        -- if public and not of source notification (2), automatic (1), escalation (6), or
        -- history (10), set the counter for the summary enforcement to 1
        IF (pub_event > 0 AND v_new_source NOT IN (1, 2, 6, 10)) THEN
            UPDATE tt.ticket
            SET summary_relevant_events_count = 1,
                todo_relevant_events_count = 1
            WHERE id = v_ticket_id;
        END IF;

        -- add a history event to the ticket, unless event type source is automatic (1)
        IF (v_new_source != 1) THEN
            CALL tt.event_interface_add_history_event(v_event_id, v_ticket_id, 101001, p_host_id, v_company_id,
                'New ticket created', NULL, TRUE, statement_timestamp(), p_contact_id, p_zitadel_contact_id);
        END IF;

        CALL tt.ticket_interface_updateticketflow(v_ticket_id);
        CALL tt.event_interface_exec_event_type_actions(p_event_id);
    END IF;

    -- send notifications for this event if this is not a monitoring outage ticket
    IF (v_ticket_type_id != 6) THEN
        CALL tt.osag_notify_event_notify(p_event_id, v_ticket_id);
    END IF;
END;
$fn$;
