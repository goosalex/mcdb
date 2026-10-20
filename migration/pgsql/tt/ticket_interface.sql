-- migration/pgsql/tt/ticket_interface.sql
--
-- Translation of TT.TICKET_INTERFACE (spec: migration/spec/tt.ticket_interface.md; Oracle
-- body: ddl/src/pkgb/tt_ticket_interface.sql, 2484 lines). Names copied verbatim from
-- migration/mapping/name-map.csv's 38 TICKET_INTERFACE rows (37 distinct pg_object_names
-- -- change_label is the corpus's one genuine overload pair, both rows is_overload=true).
-- The 3 private routines (add_status_change_event, handleDeferredTransitions,
-- updateTicketTimeStats) have no name-map row and follow the double-underscore
-- private-routine convention established by TT.OSAG_NOTIFY/TT.EVENT_INTERFACE
-- (tt.ticket_interface__<name>, REVOKE ALL ... FROM PUBLIC).
--
-- THE PILOT'S LARGEST TRANSLATION: 38 public routines, 77 SELECT INTO sites, 13
-- NO_DATA_FOUND handlers, 0 TOO_MANY_ROWS handlers, 10 WHEN OTHERS handlers. Every SELECT
-- INTO site below carries the clause-ID comment (-- S-TICKET-0NN) matching
-- migration/spec/tt.ticket_interface.md's own 77-row strictness table, so verdict and
-- code sit together. The large majority are `STRICT, unhandled` -- Oracle's real contract
-- for this package, preserved even where it reads like a latent bug (13 handlers against
-- 77 sites).
--
-- Oracle's per-routine usage-audit call (XCUT-06, the write-only osag.plsql_audit
-- feature documented in osag_plog.FINDINGS.md): all 36 call sites (one per public
-- routine that had one -- see ticket_interface.FINDINGS.md for the exact per-routine
-- count) DELETED outright, not ported, matching Pitfall 4's established disposition.
--
-- change_label: BOTH overloads created (2-arg bare form, 4-arg audited form). PostgreSQL
-- dispatches on argument COUNT natively, exactly as Oracle does -- the 4-arg overload's
-- own internal call to the 2-arg overload (2 positional args) resolves unambiguously
-- since the 4-arg overload requires a minimum of 3 args (only its last parameter has a
-- DEFAULT).
--
-- Empty-string/NULL boundary normalization (Pitfall 2, Checklist dimension 1 of the
-- spec): change_customer_reference and change_partner_reference apply NULLIF(p_x, '')
-- to their audit-text IS NOT NULL check ONLY -- the UPDATE that writes the actual column
-- still stores whatever was passed verbatim, exactly matching Oracle's own behavior
-- (Oracle already treats ''===NULL for both the comparison AND storage; PostgreSQL's ''
-- is a distinct value at the storage layer too, so only the comparison needs the
-- boundary fix, not the write).
--
-- GENUINE, PREVIOUSLY-UNDOCUMENTED ORACLE BUG found during translation, NOT flagged by
-- the spec (recorded here and in FINDINGS.md, preserved faithfully per this project's
-- translate-don't-fix methodology): change_emergency, change_always_visible, and
-- change_summary's PUBLIC-summary branch each call add_status_change_event(...) with
-- only 5 positional arguments against add_status_change_event's 6-parameter signature
-- (event_id OUT, p_ticket_id, p_public_change_text, p_contact_id, p_private_change_text
-- DEFAULT NULL, p_zitadel_contact_id DEFAULT NULL). Positionally, the caller's own
-- p_zitadel_contact_id lands in add_status_change_event's p_private_change_text slot
-- (implicitly converted NUMBER->VARCHAR2 in Oracle; ported here as an explicit ::varchar
-- cast, since PostgreSQL has no numeric->varchar cast at all, not even assignment), and
-- add_status_change_event's own p_zitadel_contact_id parameter is left at its DEFAULT
-- NULL -- so the real zitadel contact id is NEVER forwarded to the audit event's
-- contact_zitadel_id column at these 3 call sites, and the private_change_text column
-- instead receives the stringified zitadel id (or NULL, harmlessly, when the caller
-- didn't pass one). See ticket_interface.FINDINGS.md for the full analysis.
--
-- Mutually recursive with TT.EVENT_INTERFACE (plan 02-11, same wave) and calls into
-- TT.OSAG_NOTIFY (plan 02-10) and TT.UTIL (plan 02-09) -- all four packages are the
-- accepted TT cycle group (migration/analyze/known_cycles.json). PL/pgSQL does not
-- resolve CALL/function targets at CREATE time, so this file loads regardless of load
-- order; only *running* the affected paths needs the other three to exist.
--
-- Sequences (S-TICKET-005/031/039/040/049/053/055): mechanical nextval()/currval()
-- translation only (Pitfall 11 -- no identity-column modernization). Sequence pulls use
-- SELECT ... INTO STRICT (harmless -- a sequence call always returns exactly one row;
-- matches the established convention in migration/pgsql/tt/event_interface.sql). COUNT/
-- MIN/MAX aggregates use plain SELECT INTO without STRICT, same convention.
--
-- DATE -> timestamp (not timestamptz): every tt.ticket/tt.event/tt.service_window/
-- tt.ticket_flow/tt.ticket_docs_page/tt.todo_item date-ish column in the migrated schema
-- is a naive `timestamp` (ora2pg dropped Oracle's WITH TIME ZONE), so every DATE
-- parameter/local variable in this file is declared `timestamp`, matching
-- migration/pgsql/tt/util.sql's established convention for the same reason. Oracle's
-- from_tz(cast(x as timestamp), 'EUROPE/ZURICH') attach sites read the naive column back
-- verbatim, per event_interface.sql's precedent for the identical situation.
--
-- Schema gap found and fixed (see migration/test/schema-fixes/24_p12_fixes.sql):
-- tt.change_request.requester_zitadel_id / approver_zitadel_id, both inserted
-- unconditionally by newticket_new's change-request-creation branch, do not exist
-- anywhere in ddl/migrated/ OR ddl/export/ OR changes/ -- this specific pair of columns
-- appears NOWHERE else in the whole repository outside this one INSERT statement. Added
-- as an additive schema-fix (varchar(128), matching contact_zitadel_id's established
-- type), not an edit to ddl/migrated/ (D-P7).
--
-- Schema gap found and DELIBERATELY NOT fixed (Rule 4 -- architectural, not mechanical,
-- identical precedent to event_interface.sql's newevent_new admin-permission check):
-- newticket_new's company-wide-admin check queries auth.permission, which does not exist
-- anywhere in the checked-in Oracle export or the migrated schema. Ported VERBATIM per
-- the spec (translate faithfully, do not silently "fix" a latent Oracle-side schema
-- drift) -- no test reaches this branch. See ticket_interface.FINDINGS.md.

-- =====================================================================================
-- PRIVATE routines (PL/pgSQL has no forward declarations; Oracle's package body forward-
-- declares these three at the top precisely because they are defined last in Oracle
-- source).
-- =====================================================================================

-- ------------------------------------------------------------------------------------
-- add_status_change_event: the shared audit-event writer used by
-- change_customer_reference, change_partner_reference, change_emergency,
-- change_always_visible, change_notification, change_summary.
--
-- S-TICKET-053: a genuine, previously-undocumented Oracle bug. `cust_id` is declared but
-- NEVER ASSIGNED anywhere in the Oracle body -- every audit event this routine writes has
-- company_id = NULL regardless of the ticket's real company. Preserved faithfully (not
-- "fixed"), matching TT.EVENT_INTERFACE.moveevent's identical precedent (S-EVENT-033).
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.ticket_interface__add_status_change_event(
    OUT event_id numeric,
    p_ticket_id numeric,
    p_public_change_text varchar,
    p_contact_id numeric,
    p_private_change_text varchar DEFAULT NULL,
    p_zitadel_contact_id numeric DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
DECLARE
    cust_id numeric;  -- S-TICKET-053: never assigned in Oracle source either -- stays NULL.
    v_public_event numeric := 1;
BEGIN
    -- check whether we have to hide the event: hide if p_public_change_text is NULL and
    -- p_private_change_text is not (Oracle's own inline comment flags this check as
    -- fragile "if you ever decide to make this procedure public" -- stays private here).
    IF (p_public_change_text IS NULL AND p_private_change_text IS NOT NULL) THEN
        v_public_event := 0;
    END IF;

    INSERT INTO tt.event
        (id, type_id, company_id, ticket_id, contact_id, details_public, details_private,
         public_event, contact_zitadel_id)
    VALUES (nextval('tt.event_sequence'), 100003, cust_id, p_ticket_id, p_contact_id,
            p_public_change_text, p_private_change_text, v_public_event,
            p_zitadel_contact_id::varchar);

    -- S-TICKET-053 (site #57): sequence CurrVal after NextVal in the same session/
    -- transaction, no STRICT concern (corpus-wide mechanic).
    SELECT currval('tt.event_sequence') INTO STRICT event_id;

    -- notify event -- unconditional, no EXCEPTION block anywhere in this routine, so any
    -- failure (including this call) propagates fully unhandled to whichever change_*
    -- routine called this one.
    CALL tt.osag_notify_event_notify(event_id, p_ticket_id);
END;
$fn$;
REVOKE ALL ON PROCEDURE tt.ticket_interface__add_status_change_event(numeric, numeric, varchar, numeric, varchar, numeric) FROM PUBLIC;

-- ------------------------------------------------------------------------------------
-- handleDeferredTransitions: called only from change_status_event_id_out when a ticket
-- transitions into or out of "deferred" (status 60). Has its own EXCEPTION WHEN OTHERS
-- that logs and swallows, never propagates back to change_status_event_id_out.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.ticket_interface__handledeferredtransitions(
    p_ticket_id numeric,
    p_new_status_id numeric,
    p_cur_status_id numeric,
    p_defer_date timestamp,
    p_contact_id numeric,
    p_zitadel_contact_id numeric DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
DECLARE
    c_prefix CONSTANT text := 'handleDeferredTransitions(): ';
    v_escalation_status numeric;
    v_event_id numeric;
    v_rowcount bigint;
BEGIN
    -- S-TICKET-054 (site #61): STRICT, structurally near-impossible (this routine's only
    -- caller already validated the ticket exists moments earlier, S-TICKET-008) but not
    -- assumed safe merely for that reason; the whole-routine WHEN OTHERS below covers it.
    SELECT escalation_status_id INTO STRICT v_escalation_status FROM tt.ticket WHERE id = p_ticket_id;

    IF (v_escalation_status = 20 AND p_cur_status_id = 60) THEN
        IF (p_new_status_id IN (3, 11, 12, 60, 61, 101)) THEN
            CALL tt.event_interface_addevent_new(v_event_id, p_ticket_id, 60001, NULL,
                'Starting escalation to Open Systems Mission Control',
                'Event added by tt.handleDeferredTransitions. The ticket had a pending escalation (deferred) and changed its status to status '||p_new_status_id||'.');

            UPDATE tt.ticket SET escalation_status_id = 10, last_escalation_date = statement_timestamp() WHERE id = p_ticket_id;

        ELSIF (p_new_status_id IN (2, 4)) THEN
            UPDATE tt.ticket SET escalation_status_id = 0 WHERE id = p_ticket_id AND escalation_status_id = 20;
            GET DIAGNOSTICS v_rowcount = ROW_COUNT;

            -- if we really reset something, we also add the according events
            IF (v_rowcount > 0) THEN
                CALL tt.event_interface_addevent_new(v_event_id, p_ticket_id, 60001, NULL,
                    'Starting escalation to Open Systems Mission Control',
                    'Event added by tt.handleDeferredTransitions. The ticket had a pending escalation (deferred) and changed its status');
                CALL tt.event_interface_addevent_new(v_event_id, p_ticket_id, 60002, NULL,
                    'Open Systems Mission Control engineer has acknowledged this ticket.'||chr(10)||'The escalation process has finished.',
                    'Immediate acknowledgment of the escalation as the ticket status has been manually changed.',
                    p_contact_id, TRUE, statement_timestamp(), FALSE, p_zitadel_contact_id);
            END IF;

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
        CALL osag.osag_plog_err(c_prefix||'unexpected error: '||SQLERRM);
        RETURN;
END;
$fn$;
REVOKE ALL ON PROCEDURE tt.ticket_interface__handledeferredtransitions(numeric, numeric, numeric, timestamp, numeric, numeric) FROM PUBLIC;

-- ------------------------------------------------------------------------------------
-- updateTicketTimeStats: called only from change_status_event_id_out, accumulates
-- per-status elapsed time into tt.ticket_time_statistic. tickettimestats_uk1 (a UNIQUE
-- index on ticket_id) is the same structural uniqueness the Oracle MERGE relied on to
-- avoid a race on first-row creation -- confirmed against ddl/migrated/tables/tables.pg.sql,
-- closing S-TICKET-055's Assumption (a). No EXCEPTION block of its own beyond the local
-- NO_DATA_FOUND guarding the create-row path.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.ticket_interface__updatetickettimestats(
    p_ticket_id numeric, p_cur_status_id numeric, p_last_status_change_date timestamp)
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_status_time numeric;
    v_stats_id numeric;
BEGIN
    -- We only want to handle certain states: open, resolved, waiting, third-party,
    -- waiting for sign-off, deferred.
    IF (p_cur_status_id NOT IN (2, 11, 12, 60, 61, 101)) THEN
        RETURN;
    END IF;

    -- calculate time in seconds (Oracle: TRUNC((sysdate - p_last_status_change_date)*86400))
    v_status_time := trunc(extract(epoch FROM (statement_timestamp()::timestamp - p_last_status_change_date)));

    BEGIN
        -- S-TICKET-055 (site #73): STRICT + local NO_DATA_FOUND handler -- zero rows is
        -- the EXPECTED case for a ticket's first-ever time-stat write.
        SELECT ts.id INTO STRICT v_stats_id FROM tt.ticket_time_statistic ts WHERE ts.ticket_id = p_ticket_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            -- S-TICKET-055 (site #74): sequence pull, no STRICT concern.
            SELECT nextval('tt.tickettimestatistic_seq') INTO STRICT v_stats_id;
            -- race-avoidance insert mirrors Oracle's MERGE ... WHEN NOT MATCHED THEN
            -- INSERT against the ticket_id unique index (tickettimestats_uk1) exactly.
            INSERT INTO tt.ticket_time_statistic (id, ticket_id)
            VALUES (v_stats_id, p_ticket_id)
            ON CONFLICT (ticket_id) DO NOTHING;
            -- S-TICKET-055 (site #75): re-SELECT after the (possibly no-op) insert -- a
            -- concurrent session may have won the race, per Oracle's own inline comment
            -- ("but in any case do the select again as it may not have inserted a new
            -- record").
            SELECT ts.id INTO STRICT v_stats_id FROM tt.ticket_time_statistic ts WHERE ts.ticket_id = p_ticket_id;
    END;

    -- update times
    IF (p_cur_status_id = 2) THEN
        UPDATE tt.ticket_time_statistic SET open_time = open_time + v_status_time WHERE id = v_stats_id;
    ELSIF (p_cur_status_id IN (11, 61)) THEN
        UPDATE tt.ticket_time_statistic SET waiting_time = waiting_time + v_status_time WHERE id = v_stats_id;
    ELSIF (p_cur_status_id = 12) THEN
        UPDATE tt.ticket_time_statistic SET third_party_time = third_party_time + v_status_time WHERE id = v_stats_id;
    ELSIF (p_cur_status_id = 60) THEN
        UPDATE tt.ticket_time_statistic SET deferred_time = deferred_time + v_status_time WHERE id = v_stats_id;
    ELSIF (p_cur_status_id = 101) THEN
        UPDATE tt.ticket_time_statistic SET resolved_time = resolved_time + v_status_time WHERE id = v_stats_id;
    END IF;
END;
$fn$;
REVOKE ALL ON PROCEDURE tt.ticket_interface__updatetickettimestats(numeric, numeric, timestamp) FROM PUBLIC;

-- =====================================================================================
-- PUBLIC routines (names verbatim from migration/mapping/name-map.csv). Task 1 scope:
-- newticket_new through change_summary (routines 1-19 of 38).
-- =====================================================================================

-- ------------------------------------------------------------------------------------
-- newticket_new (S-TICKET-001..005): opens a brand-new ticket and its first event. No
-- procedure-level EXCEPTION block at all -- any unhandled error propagates fully.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.ticket_interface_newticket_new(
    OUT p_ticket_id numeric,
    OUT p_event_id numeric,
    p_ticket_type_id numeric,
    p_subject varchar,
    p_event_type_id numeric,
    p_host_id numeric,
    p_details_public varchar,
    p_details_private varchar DEFAULT NULL,
    p_contact_id numeric DEFAULT NULL,
    p_worker_id numeric DEFAULT NULL,
    p_public_event boolean DEFAULT TRUE,
    p_eventdate timestamp DEFAULT statement_timestamp(),
    p_company_id numeric DEFAULT NULL,
    p_service_component_id numeric DEFAULT NULL,
    p_zitadel_contact_id numeric DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_pub_event numeric;
    v_company_id numeric;
    v_contact_id numeric;
    v_event_id numeric;
    v_event_source_id numeric;
    v_confirmed numeric;
    v_fast_resolvable numeric;
    v_contact_company_id numeric;
    v_details_public varchar;
    v_details_private varchar;
    v_mss_service_id numeric;
    v_count numeric;
    v_ticket_type_id numeric;
    v_create_cr numeric;
    v_cr_id numeric;
BEGIN
    v_ticket_type_id := p_ticket_type_id;

    IF (p_public_event) THEN
        v_pub_event := 1;
    ELSE
        v_pub_event := 0;
    END IF;

    -- if a company is given, let's take that first (needed if providing contact_zitadel_id)
    IF (p_company_id IS NOT NULL) THEN
        v_company_id := p_company_id;
    END IF;

    -- if a host is given, we get the company from the mss.host table as well as the
    -- service id (mss.service)
    IF (p_host_id IS NOT NULL) THEN
        -- S-TICKET-001 (sites #1-#2): STRICT, unhandled -- newticket_new has no
        -- EXCEPTION block at all. mss.host2service's PK is (host_id, service_id), NOT
        -- unique on host_id alone, so TOO_MANY_ROWS is structurally reachable at site #2.
        SELECT h.service_company_id INTO STRICT v_company_id FROM mss.host h WHERE h.id = p_host_id;
        SELECT h2s.service_id INTO STRICT v_mss_service_id FROM mss.host2service h2s WHERE h2s.host_id = p_host_id;
    END IF;

    -- if a contact id is given we select the company_id from the contact table -- this
    -- overrides the company selection from the service id
    -- S-TICKET-002 (site #3): STRICT, unhandled.
    IF (p_contact_id IS NOT NULL) THEN
        SELECT company_id INTO STRICT v_company_id FROM stop.contact WHERE contact.id = p_contact_id;
    END IF;

    -- for company wide tickets check if the given contact is a company wide admin and
    -- therefore suitable as ticket owner.
    -- Schema gap (mirrors event_interface.sql's newevent_new precedent): auth.permission
    -- does not exist anywhere in ddl/migrated -- ported verbatim per spec, Rule 4
    -- (architectural, not mechanical). See ticket_interface.FINDINGS.md.
    v_contact_id := p_contact_id;
    IF (p_host_id IS NULL AND p_contact_id IS NOT NULL) THEN
        -- S-TICKET-003 (site #4): COUNT aggregate, no STRICT concern.
        SELECT count(*) INTO v_count
        FROM auth.permission p, auth.login l
        WHERE p.login_id = l.id
          AND l.contact_id = p_contact_id
          AND p.role_id = 2
          AND p.company_unit_id IS NULL
          AND p.user_unit_id IS NULL
          AND p.service_id IS NULL;
        IF (v_count = 0) THEN
            v_contact_id := NULL;
        END IF;
    END IF;

    -- if the ticket was created automatically, ticket type and service don't have to be
    -- confirmed, and the ticket is fast-resolvable
    v_confirmed := 0;
    v_fast_resolvable := 0;
    -- S-TICKET-003 (site #5): STRICT, unhandled.
    SELECT source INTO STRICT v_event_source_id FROM tt.event_type WHERE id = p_event_type_id;
    IF (v_event_source_id = 1) THEN
        v_confirmed := 1;
        v_fast_resolvable := 1;
    END IF;

    -- if the ticket was created by an OSAG engineer, nothing has to be confirmed neither
    -- S-TICKET-004 (site #6): STRICT, unhandled.
    IF (p_worker_id IS NOT NULL) THEN
        SELECT company_id INTO STRICT v_contact_company_id FROM stop.contact WHERE id = p_worker_id;
        -- OSAG company has ID 6
        IF (v_contact_company_id = 6) THEN
            v_confirmed := 1;
        END IF;
    END IF;

    -- S-TICKET-005 (sites #7-#8): sequence pulls, no STRICT concern.
    SELECT nextval('tt.ticket_sequence') INTO STRICT p_ticket_id;
    SELECT nextval('tt.event_sequence') INTO STRICT p_event_id;

    -- replace placeholders for ticket_id and event_id in event details.
    -- Pitfall 2 / S-EVENT-015 precedent: Oracle's SUBSTRB(x,1,30000) inside
    -- replace_id_placeholders collapses '' to NULL; substr() does not -- NULLIF at this
    -- boundary reproduces Oracle's collapse (this routine's own IS NOT NULL check three
    -- lines below depends on it). Not called out by name in the spec's own S-TICKET-037
    -- clause (which only traces replace_id_placeholders' own body), but required for
    -- fidelity at this specific call site -- see ticket_interface.FINDINGS.md.
    v_details_public := NULLIF(tt.ticket_interface_replace_id_placeholders(p_details_public, p_ticket_id, p_event_id), '');
    v_details_private := NULLIF(tt.ticket_interface_replace_id_placeholders(p_details_private, p_ticket_id, p_event_id), '');

    -- if ticket is opened with an incident report (30005), comment from customer (30011)
    -- or a comment by MC (50002) and public details are available, prepend subject to
    -- event_details
    IF p_event_type_id IN (30005, 30011, 50002) AND v_details_public IS NOT NULL THEN
        v_details_public := p_subject || chr(10) || chr(10) || v_details_public;
    END IF;

    -- find out if we need to create a change request inside the newly created ticket as
    -- well (used for ServiceNOW ticketing integration).
    v_create_cr := 0;
    IF (p_event_type_id = 30002 AND p_contact_id IS NOT NULL AND p_contact_id IN (224019, 1150408, 235692, 371508, 458818, 430183, 430181, 3598, 796216)) THEN
        v_create_cr := 1;
        v_ticket_type_id := 2;
    END IF;

    -- open a new ticket for this event
    INSERT INTO tt.ticket (id, type_id, contact_id, worker_id, company_id, host_id, subject, last_status_change_date,
                           mss_service_id, service_confirmed, type_confirmed, fast_resolvable, service_component_id, contact_zitadel_id)
    VALUES (p_ticket_id, v_ticket_type_id, v_contact_id, p_worker_id, v_company_id, p_host_id,
            substr(p_subject, 1, 100), statement_timestamp(), v_mss_service_id, v_confirmed, v_confirmed,
            v_fast_resolvable, p_service_component_id, p_zitadel_contact_id::varchar);

    -- set ux timeout -- ux_timeout_start is a naive `timestamp` column in the migrated
    -- schema (no naive-timestamp target left for Oracle's from_tz() attach, matching
    -- event_interface.sql's established convention for the identical situation).
    UPDATE tt.ticket SET ux_timeout_start = open_date WHERE id = p_ticket_id;
    CALL tt.ticket_interface_update_ux_timeout_for_ticket(p_ticket_id, TRUE);

    -- determine contact for event
    IF (p_worker_id IS NOT NULL) THEN
        v_contact_id := p_worker_id;
    ELSIF (p_contact_id IS NOT NULL) THEN
        v_contact_id := p_contact_id;
    ELSE
        v_contact_id := NULL;
    END IF;

    -- insert the event into the event table
    INSERT INTO tt.event
        (id, type_id, host_id, eventdate, details_public, details_private, public_event, ticket_id, contact_id, contact_zitadel_id)
    VALUES (p_event_id, p_event_type_id, p_host_id, p_eventdate, v_details_public, v_details_private,
            v_pub_event, p_ticket_id, v_contact_id, p_zitadel_contact_id::varchar);

    -- if the event is public and not of source notification (2) or history (10),
    -- remember it as the last public event of the ticket
    IF (v_pub_event > 0 AND v_event_source_id NOT IN (2, 10)) THEN
        UPDATE tt.ticket SET last_public_event_id = p_event_id WHERE id = p_ticket_id;
    END IF;

    -- if the event is public and not of source notification (2), automatic (1),
    -- escalation (6), or history (10), set the counter for the summary enforcement to 1
    IF (v_pub_event > 0 AND v_event_source_id NOT IN (1, 2, 6, 10)) THEN
        UPDATE tt.ticket SET summary_relevant_events_count = 1, todo_relevant_events_count = 1 WHERE id = p_ticket_id;
    END IF;

    -- notify the event
    CALL tt.osag_notify_event_notify(p_event_id, p_ticket_id);

    -- add a history event to the ticket (event type is 'new ticket', 101001)
    CALL tt.event_interface_add_history_event(v_event_id, p_ticket_id, 101001, p_host_id, v_company_id,
        'New ticket created', NULL, TRUE, statement_timestamp(), v_contact_id, p_zitadel_contact_id);

    -- execute the event type actions
    CALL tt.event_interface_exec_event_type_actions(p_event_id);

    -- create the change request if needed
    IF (v_create_cr = 1) THEN
        -- S-TICKET-005 (site #9): sequence pull, no STRICT concern.
        SELECT nextval('tt.changerequest_seq') INTO STRICT v_cr_id;

        -- for now, all of those email requests will lead to a pre-approved CR. We're not
        -- checking the flag that defines on company level if requester needs to be !=
        -- approver.
        INSERT INTO tt.change_request (id, change_request_state_id, description, requester_id, approver_id,
            creation_date, approval_denial_date, ticket_id, requester_zitadel_id, approver_zitadel_id)
        VALUES (v_cr_id,
                3, -- status "approved"
                v_details_public, -- copy of the email body text
                v_contact_id, -- requester
                v_contact_id, -- approver: same as requester
                statement_timestamp(),
                statement_timestamp(),
                p_ticket_id,
                p_zitadel_contact_id::varchar,
                p_zitadel_contact_id::varchar);
    END IF;

    CALL tt.ticket_interface_updateticketflow(p_ticket_id);
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- change_deferral_date (S-TICKET-006): changes the deferral date of a ticket only if it
-- is currently in status 60 (deferred); otherwise logs a warning and does nothing. No
-- EXCEPTION block of its own.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.ticket_interface_change_deferral_date(
    p_ticket_id numeric,
    p_contact_id numeric,
    p_defer_date timestamp,
    p_details_public varchar,
    p_zitadel_contact_id numeric DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_host_id numeric;
    v_ticket_status_id numeric;
    v_event_id numeric;
BEGIN
    -- S-TICKET-006 (site #10): STRICT, unhandled -- change_deferral_date has no
    -- EXCEPTION block of its own.
    SELECT status_id INTO STRICT v_ticket_status_id FROM tt.ticket t WHERE t.id = p_ticket_id;

    -- only change deferral date if ticket is deferred (id = 60)
    IF (v_ticket_status_id = 60) THEN
        -- S-TICKET-006 (site #11): STRICT, unhandled.
        SELECT t.host_id INTO STRICT v_host_id FROM tt.ticket t WHERE t.id = p_ticket_id;

        UPDATE tt.ticket t
        SET status_valid_until_date = p_defer_date, last_deferral_date = p_defer_date
        WHERE t.id = p_ticket_id;

        CALL tt.event_interface_addevent_new(v_event_id, p_ticket_id, 100003, v_host_id, p_details_public, NULL, p_contact_id, TRUE, statement_timestamp(), FALSE, p_zitadel_contact_id);
    ELSE
        CALL osag.osag_plog_warning('tt.ticket_interface.change_deferral_date: called for ticket ' || p_ticket_id || ' but it is not deferred. status id: ' || v_ticket_status_id);
    END IF;
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- change_status_event_id_out (S-TICKET-008..012): the real status-change engine.
-- No procedure-level EXCEPTION block -- everything propagates fully unhandled.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.ticket_interface_change_status_event_id_out(
    OUT event_id numeric,
    p_ticket_id numeric,
    p_status_id numeric,
    p_contact_id numeric,
    p_details_public varchar,
    p_details_private varchar DEFAULT NULL,
    p_valid_until_date timestamp DEFAULT NULL,
    p_defer_event numeric DEFAULT NULL,
    p_escalate_after_defer boolean DEFAULT NULL,
    p_hot_reason varchar DEFAULT NULL,
    p_zitadel_contact_id numeric DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
DECLARE
    dets_pub varchar;
    status_name varchar;
    v_cur_status_name varchar;
    l_ticket_type_id numeric;
    v_cur_status numeric;
    v_escalation_status_id numeric;
    v_cur_valid_until_date timestamp;
    v_cur_status_changed_date timestamp;
    v_details_private varchar;
    v_event_type_id numeric;
    v_handled_by_mcc numeric;
    v_hot_event_id numeric;
    v_last_public_event_id numeric;
    v_last_public_event_type_id numeric;
    v_now timestamp;
    v_last_deferral_date timestamp;
    v_ux_timeout_start timestamp;
BEGIN
    CALL osag.osag_plog_debug('changestatus called');

    -- S-TICKET-008 (site #12): STRICT, unhandled -- the routine's main ticket-state read.
    SELECT t.status_id, t.handled_by_mcc, t.last_public_event_id, t.escalation_status_id, t.status_valid_until_date,
           t.last_status_change_date, t.last_deferral_date, statement_timestamp()
    INTO STRICT v_cur_status, v_handled_by_mcc, v_last_public_event_id, v_escalation_status_id, v_cur_valid_until_date, v_cur_status_changed_date, v_last_deferral_date, v_now
    FROM tt.ticket t
    WHERE t.id = p_ticket_id;

    v_last_public_event_type_id := NULL;
    IF (v_last_public_event_id IS NOT NULL) THEN
        -- S-TICKET-008 (site #13): STRICT, unhandled.
        SELECT event.type_id INTO STRICT v_last_public_event_type_id
        FROM tt.event
        WHERE event.id = v_last_public_event_id;
    END IF;

    -- avoid unnecessary updates
    IF (v_cur_status = p_status_id) THEN
        RETURN;
    END IF;

    -- update time statistics for this ticket -- open(2), waiting(11), deferred(60),
    -- third-party(12), waiting for sign-off(61), resolved(101)
    IF (v_cur_status IN (2, 11, 12, 60, 61, 101)) THEN
        CALL tt.ticket_interface__updatetickettimestats(p_ticket_id, v_cur_status, v_cur_status_changed_date);
    END IF;

    -- change the status of the ticket and update last_status_change date
    UPDATE tt.ticket t
    SET status_id = p_status_id,
        last_status_change_date = statement_timestamp()
    WHERE t.id = p_ticket_id;

    IF (v_last_deferral_date < v_now) THEN
        UPDATE tt.ticket t SET last_deferral_date = NULL WHERE t.id = p_ticket_id;
    END IF;

    -- create the update string
    -- S-TICKET-009 (sites #14-#15): STRICT, unhandled.
    SELECT name INTO STRICT status_name FROM tt.status WHERE id = p_status_id;
    SELECT name INTO STRICT v_cur_status_name FROM tt.status WHERE id = v_cur_status;

    dets_pub := 'New status: ' || status_name || chr(10) || 'Previous status: ' || v_cur_status_name;
    dets_pub := dets_pub || chr(10) || p_details_public;

    IF (p_escalate_after_defer) THEN
        dets_pub := dets_pub || ', escalation to os when reached.';
    END IF;

    -- status id 3 is hot
    IF (p_hot_reason IS NOT NULL AND p_status_id = 3) THEN
        -- hot status is currently private
        v_details_private := 'Hot because: ' || p_hot_reason || chr(10) || p_details_private;
    ELSE
        v_details_private := p_details_private;
    END IF;

    -- get ticket type -- S-TICKET-009 (site #16): STRICT, unhandled. l_ticket_type_id is
    -- read nowhere else (a dead local variable in Oracle source too) -- the SELECT INTO
    -- itself is kept for its STRICT/zero-row behavior, per this checklist's own
    -- discipline (the site carries the same hazard whether or not its result is used).
    SELECT type_id INTO STRICT l_ticket_type_id FROM tt.ticket WHERE id = p_ticket_id;

    -- handle changes from/to deferred status
    IF (p_status_id = 60 OR v_cur_status = 60) THEN
        IF (p_status_id = 60) THEN
            IF (p_escalate_after_defer) THEN
                UPDATE tt.ticket SET escalation_status_id = 20 WHERE ticket.id = p_ticket_id AND escalation_status_id NOT IN (10, 11);
                UPDATE tt.ticket SET last_deferral_escalated = 1 WHERE ticket.id = p_ticket_id;
            ELSE
                UPDATE tt.ticket SET last_deferral_escalated = 0 WHERE ticket.id = p_ticket_id;
            END IF;
        END IF;
        CALL tt.ticket_interface__handledeferredtransitions(p_ticket_id, p_status_id, v_cur_status, p_valid_until_date, p_contact_id, p_zitadel_contact_id);
    END IF;

    -- calculate the event type id, 101XXX is the prefix for status change events
    v_event_type_id := 101000 + p_status_id;

    -- create a new status change event (event_id is an OUT parameter)
    CALL tt.event_interface_add_history_event(event_id,
        p_ticket_id,
        v_event_type_id,
        NULL,     -- no host_id specified
        NULL,     -- no company_id specified
        dets_pub,
        v_details_private,
        TRUE,     -- it is a public event
        statement_timestamp(),  -- event date not specified, use now
        p_contact_id,
        p_zitadel_contact_id);

    -- status id 3 is hot -- add the "hot non-MCC ticket" event if appropriate
    IF (p_status_id = 3 AND v_handled_by_mcc = 0) THEN
        -- event type 100008 is "hot non-MCC ticket"
        CALL tt.event_interface_add_history_event(v_hot_event_id,
            p_ticket_id,
            100008,
            NULL,
            NULL,
            NULL,  -- this event is always private
            'This non-MCC ticket just became hot.',
            FALSE, -- private
            statement_timestamp(),
            p_contact_id,
            p_zitadel_contact_id);
    END IF;

    -- resolved event
    IF (p_status_id = 101) THEN
        UPDATE tt.ticket SET last_resolved_date = statement_timestamp() WHERE ticket.id = p_ticket_id;
    END IF;

    -- delete event -- set resolved date and clear escalation status
    IF (p_status_id = 120) THEN
        -- delete ticket specific notifications
        CALL tt.osag_notify_delete_ticket_notifications(p_ticket_id);

        UPDATE tt.ticket SET last_resolved_date = statement_timestamp(), escalation_status_id = 0 WHERE ticket.id = p_ticket_id;
    END IF;

    -- pending escalations have to be stopped, if the ticket is opened (2) or
    -- acknowledged (4), furthermore if its status is recovered which might result in
    -- waiting (11), third-party (12), deferred (60), waiting for sign-off (61), or
    -- resolved (101) unless the current status is 60, then those transitions are already
    -- handled in handleDeferredTransitions
    IF (p_status_id IN (2, 4, 11, 12, 60, 61, 101) AND v_cur_status != 60 AND (p_contact_id IS NOT NULL OR p_zitadel_contact_id IS NOT NULL)) THEN
        -- in case of an escalation to the customer (20)
        IF (v_escalation_status_id = 20) THEN
            CALL tt.event_interface_addevent_new(event_id, p_ticket_id, 60102, NULL, 'Open Systems Mission Control engineer has acknowledged this ticket.'||chr(10)||'The escalation process has finished.', NULL, p_contact_id, TRUE, statement_timestamp(), FALSE, p_zitadel_contact_id);
            UPDATE tt.ticket SET escalation_status_id = 0 WHERE id = p_ticket_id;
            -- otherwise we have an escalation to open systems (10 or 11)
        ELSIF (v_escalation_status_id IN (10, 11)) THEN
            CALL tt.event_interface_addevent_new(event_id, p_ticket_id, 60002, NULL, 'Open Systems Mission Control engineer has acknowledged this ticket.'||chr(10)||'The escalation process has finished.', NULL, p_contact_id, TRUE, statement_timestamp(), FALSE, p_zitadel_contact_id);
            UPDATE tt.ticket SET escalation_status_id = 0 WHERE id = p_ticket_id;
        END IF;
    END IF;

    -- update ticket status_valid_until field, status waiting (11), third party (12),
    -- waiting for sign-off (61)
    IF (p_status_id IN (11, 12, 61) AND p_valid_until_date IS NOT NULL) THEN
        CALL tt.util_update_status_valid_until(p_ticket_id, p_valid_until_date);
    ELSE
        CALL tt.util_update_status_valid_until(p_ticket_id);
    END IF;

    -- if the new status is "hot" (3), "acknowledged" (4), "open" (2), then check whether
    -- the current status is recoverable, unless the customer requests to resolve the
    -- ticket (30016)
    IF (p_status_id IN (2, 3, 4) AND v_last_public_event_type_id IS DISTINCT FROM 30016) THEN
        -- "resolved" (101) is always recoverable
        IF (v_cur_status = 101) THEN
            UPDATE tt.ticket SET recoverable_status_id = v_cur_status WHERE id = p_ticket_id;
            -- "waiting" (11), "third party" (12) and "waiting for sign-off" (61) are
            -- recoverable if the ticket is a non-mcc ticket or the current "valid until
            -- date" is still in the future
        ELSIF (v_cur_status IN (11, 12, 61) AND (v_handled_by_mcc = 0 OR v_cur_valid_until_date > v_now)) THEN
            UPDATE tt.ticket SET recoverable_status_id = v_cur_status WHERE id = p_ticket_id;
            -- "deferred" (60) is only recoverable, if the current "valid until date" is
            -- still in the future
        ELSIF (v_cur_status = 60 AND v_cur_valid_until_date > v_now) THEN
            UPDATE tt.ticket SET recoverable_status_id = v_cur_status WHERE id = p_ticket_id;
        END IF;
    ELSE
        UPDATE tt.ticket SET recoverable_status_id = NULL WHERE id = p_ticket_id;
    END IF;

    -- update ux timeout -- if the new status is "open"(2), "hot"(3) or "acknowledged"(4)
    -- and the ticket was "waiting"(11), "third party"(12), "deferred"(60), "waiting for
    -- sign-off"(61) or "resolved"(101)
    IF (p_status_id IN (2, 3, 4) AND v_cur_status IN (11, 12, 60, 61, 101)) THEN
        -- S-TICKET-010 (site #17): STRICT, unhandled. event_id here is the OUT parameter
        -- this same routine just populated via add_history_event moments earlier in the
        -- SAME transaction -- zero rows is structurally near-impossible, EVENT_PK makes
        -- TOO_MANY_ROWS impossible regardless.
        SELECT eventdate INTO STRICT v_ux_timeout_start FROM tt.event WHERE id = event_id;
        UPDATE tt.ticket SET ux_timeout_start = v_ux_timeout_start WHERE id = p_ticket_id;
    END IF;
    CALL tt.ticket_interface_update_ux_timeout_for_ticket(p_ticket_id, FALSE);

    -- current is actually previous at this stage of the process
    CALL tt.ticket_interface_updateticketflow(p_ticket_id, v_cur_status, v_cur_status_changed_date);
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- change_status (S-TICKET-007): pure delegator to change_status_event_id_out, discarding
-- its event_id OUT parameter into a local variable never read. No SELECT INTO and no
-- EXCEPTION block of its own -- every strictness/exception fact of
-- change_status_event_id_out applies transitively.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.ticket_interface_change_status(
    p_ticket_id numeric,
    p_status_id numeric,
    p_contact_id numeric,
    p_details_public varchar,
    p_details_private varchar DEFAULT NULL,
    p_valid_until_date timestamp DEFAULT NULL,
    p_defer_event numeric DEFAULT NULL,
    p_escalate_after_defer boolean DEFAULT NULL,
    p_hot_reason varchar DEFAULT NULL,
    p_zitadel_contact_id numeric DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
DECLARE
    ev_id numeric;
BEGIN
    CALL tt.ticket_interface_change_status_event_id_out(ev_id,
        p_ticket_id, p_status_id, p_contact_id, p_details_public, p_details_private,
        p_valid_until_date, p_defer_event, p_escalate_after_defer, p_hot_reason, p_zitadel_contact_id);
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- update_ux_timeout_for_ticket (S-TICKET-011..012). No EXCEPTION block anywhere.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.ticket_interface_update_ux_timeout_for_ticket(
    p_ticket_id numeric, p_is_initial boolean)
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_type_id numeric;
    v_emergency numeric;
    v_handled_by_mcc numeric;
    v_status_id numeric;
    v_ux_timeout timestamp;
    v_ux_timeout_start timestamp;
    v_service_window_end timestamp;
    v_ux_timeout_delta interval;
    v_ticket_has_service_window numeric;
BEGIN
    -- S-TICKET-011 (site #18): STRICT, unhandled. "no data found" message-parity shim
    -- (XCUT-01 convention, matching tt.event_interface's demote_event/promote_event
    -- precedent): re-raises the SAME SQLSTATE (P0002) with Oracle's ORA-01403 text
    -- instead of PL/pgSQL's native "query returned no rows" -- required for regress
    -- golden parity (migration/test/regress/expected/tt__ticket_interface__errors.out).
    BEGIN
        SELECT type_id, emergency, ux_timeout_start, handled_by_mcc, status_id
        INTO STRICT v_type_id, v_emergency, v_ux_timeout_start, v_handled_by_mcc, v_status_id
        FROM tt.ticket
        WHERE id = p_ticket_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE EXCEPTION 'no data found' USING ERRCODE = 'P0002';
    END;

    -- no timeouts for: tickets of type "third party incident"(4) or "customer
    -- incident"(5); non MCC tickets; ticket status other than "new"(1), "open"(2),
    -- "hot"(3) and "acknowledged"(4)
    IF (v_type_id = 4 OR v_type_id = 5 OR v_handled_by_mcc = 0 OR v_status_id > 4) THEN
        UPDATE tt.ticket SET ux_timeout = NULL WHERE id = p_ticket_id;
        RETURN;
    END IF;

    -- emergency timeouts
    IF (v_emergency = 1) THEN
        IF (p_is_initial) THEN
            v_ux_timeout_delta := interval '60 minutes';
        ELSE
            v_ux_timeout_delta := interval '120 minutes';
        END IF;
    ELSE
        -- for ticket types "incident", "monitoring incident"
        IF (v_type_id = 1 OR v_type_id = 6) THEN
            IF (p_is_initial) THEN
                v_ux_timeout_delta := interval '120 minutes';
            ELSE
                v_ux_timeout_delta := interval '240 minutes';
            END IF;
            -- for ticket types "change", "request", "installation", "migration"
        ELSIF (v_type_id = 2 OR v_type_id = 14 OR v_type_id = 15 OR v_type_id = 8) THEN
            v_ux_timeout_delta := interval '480 minutes';
            -- for ticket type "problem"
        ELSIF (v_type_id = 11) THEN
            v_ux_timeout_delta := interval '960 minutes';
            -- for ticket type "purchase order"
        ELSIF (v_type_id = 9) THEN
            v_ux_timeout_delta := interval '720 minutes';
            -- for ticket type "maintenance"
        ELSIF (v_type_id = 12) THEN
            -- S-TICKET-012 (site #19): COUNT aggregate, no STRICT concern.
            SELECT COUNT(*) INTO v_ticket_has_service_window
            FROM tt.service_window s
            WHERE p_ticket_id = s.ticket_id;

            IF (v_ticket_has_service_window > 0) THEN
                -- S-TICKET-012 (site #20): STRICT, unhandled. Oracle's trailing
                -- ROWNUM=1 structurally caps this at one row before SELECT INTO can see
                -- more than one -- translated as LIMIT 1 (not merely dropped), so
                -- STRICT here likewise never sees TOO_MANY_ROWS. tt.service_window also
                -- carries a genuine UNIQUE INDEX on ticket_id (ticket_id_uk1), so
                -- multi-row is structurally impossible from the schema too.
                SELECT end_date INTO STRICT v_service_window_end
                FROM tt.service_window
                WHERE ticket_id = p_ticket_id
                LIMIT 1;

                IF (v_service_window_end > v_ux_timeout_start) THEN
                    -- set timeout to 60 minutes after service window end
                    v_ux_timeout_start := v_service_window_end;
                    v_ux_timeout_delta := interval '60 minutes';
                ELSE
                    v_ux_timeout_delta := interval '480 minutes';
                END IF;
            ELSE
                v_ux_timeout_delta := interval '480 minutes';
            END IF;
        END IF;
    END IF;

    v_ux_timeout := v_ux_timeout_start + v_ux_timeout_delta;
    UPDATE tt.ticket SET ux_timeout = v_ux_timeout WHERE id = p_ticket_id;
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- change_worker (S-TICKET-013..014). Two local NO_DATA_FOUND blocks (each defaulting to
-- a synthetic "MCC" label); one final unguarded site (#23) propagates unhandled since
-- change_worker has no procedure-level EXCEPTION block.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.ticket_interface_change_worker(
    p_ticket_id numeric,
    p_worker_id numeric,
    p_contact_id numeric,
    p_handled_by_mcc numeric DEFAULT 0,
    p_is_emergency numeric DEFAULT 0,
    p_reason varchar DEFAULT NULL,
    p_zitadel_contact_id numeric DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
DECLARE
    cust_id numeric;
    new_shrt varchar;
    old_shrt varchar;
    new_mcc_flag varchar := NULL;
    old_mcc_flag varchar := NULL;
    v_handled_by_mcc numeric;
    v_private_detail varchar;
    v_worker_id numeric;
BEGIN
    BEGIN
        -- S-TICKET-013 (site #21): STRICT + local NO_DATA_FOUND handler.
        SELECT short, id INTO STRICT new_shrt, v_worker_id
        FROM stop.contact
        WHERE id = p_worker_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            new_shrt := 'MCC';
            new_mcc_flag := '';
            v_worker_id := NULL;
    END;

    BEGIN
        -- S-TICKET-014 (site #22): STRICT + local NO_DATA_FOUND handler.
        SELECT c.short, t.handled_by_mcc INTO STRICT old_shrt, v_handled_by_mcc
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
    UPDATE tt.ticket
    SET worker_id = v_worker_id
    WHERE ticket.id = p_ticket_id;

    -- set the handled by mcc flag for the ticket to the new p_handled_by_mcc
    IF (v_handled_by_mcc != p_handled_by_mcc) THEN
        UPDATE tt.ticket
        SET handled_by_mcc = p_handled_by_mcc
        WHERE ticket.id = p_ticket_id;

        CALL tt.ticket_interface_update_ux_timeout_for_ticket(p_ticket_id, FALSE);
    END IF;

    -- get the customer id -- S-TICKET-014 (site #23): STRICT, unhandled -- change_worker
    -- has no procedure-level EXCEPTION block.
    SELECT company_id INTO STRICT cust_id
    FROM tt.ticket WHERE id = p_ticket_id;

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
        v_private_detail := v_private_detail || chr(10) || 'Reason: ' || p_reason;
    END IF;

    INSERT INTO tt.event
        (id, public_event, type_id, host_id, company_id, ticket_id, contact_id, details_private, contact_zitadel_id)
    VALUES (nextval('tt.event_sequence'),
            0,
            100003,
            NULL,
            cust_id,
            p_ticket_id,
            p_contact_id,
            v_private_detail,
            p_zitadel_contact_id::varchar);

    CALL tt.ticket_interface_updateticketflow(p_ticket_id);
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- change_service_host (S-TICKET-015..016). One unguarded site (#24) propagates
-- unhandled; four independent local NO_DATA_FOUND blocks follow, none reachable by an
-- outer handler since this routine has none.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.ticket_interface_change_service_host(
    p_ticket_id numeric,
    p_service_id numeric,
    p_host_id numeric,
    p_contact_id numeric,
    p_zitadel_contact_id numeric DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
DECLARE
    cust_id numeric;
    v_host_label_old varchar;
    v_host_label_new varchar;
    v_service_id_old numeric;
    v_service_label_old varchar;
    v_service_label_new varchar;
    v_details_public varchar;
BEGIN
    -- get the customer id -- S-TICKET-015 (site #24): STRICT, unhandled --
    -- change_service_host has no procedure-level EXCEPTION block.
    SELECT company_id INTO STRICT cust_id
    FROM tt.ticket WHERE id = p_ticket_id;

    BEGIN
        -- S-TICKET-016 (site #25): STRICT + local NO_DATA_FOUND handler.
        SELECT s.id, st.name INTO STRICT v_service_id_old, v_service_label_old
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
        -- S-TICKET-016 (site #26): STRICT + local NO_DATA_FOUND handler.
        SELECT st.name INTO STRICT v_service_label_new
        FROM mss.service_type st, mss.service s
        WHERE s.service_type_id = st.id AND
            s.id = p_service_id;

        v_service_label_new := ' (' || v_service_label_new || ' [' || p_service_id || '])';
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_service_label_new := NULL;
    END;

    BEGIN
        -- S-TICKET-016 (site #27): STRICT + local NO_DATA_FOUND handler.
        SELECT h.name INTO STRICT v_host_label_old
        FROM mss.host h, tt.ticket t
        WHERE t.id = p_ticket_id AND h.id = t.host_id;

        v_host_label_old := ' ' || v_host_label_old;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_host_label_old := ' <empty>';
    END;

    BEGIN
        -- S-TICKET-016 (site #28): STRICT + local NO_DATA_FOUND handler.
        SELECT name INTO STRICT v_host_label_new
        FROM mss.host
        WHERE id = p_host_id;
        v_host_label_new := ' ' || v_host_label_new;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_host_label_new := ' <empty>';
    END;

    v_details_public := 'service changed from' || v_host_label_old || v_service_label_old || ' to' || v_host_label_new || v_service_label_new;

    -- add a ticket "attribute change event" to the ticket
    INSERT INTO tt.event
        (id, type_id, company_id, details_public, contact_id, ticket_id, contact_zitadel_id)
    VALUES (nextval('tt.event_sequence'),
            100003,
            cust_id,
            v_details_public,
            p_contact_id,
            p_ticket_id,
            p_zitadel_contact_id::varchar);

    -- update the service/host in the ticket
    UPDATE tt.ticket
    SET mss_service_id = p_service_id,
        host_id = p_host_id
    WHERE id = p_ticket_id;
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- change_subject (S-TICKET-017). Both sites propagate fully unhandled -- no EXCEPTION
-- block of its own.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.ticket_interface_change_subject(
    p_ticket_id numeric,
    p_subject varchar,
    p_contact_id numeric,
    p_zitadel_contact_id numeric DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
DECLARE
    cust_id numeric;
    sub_old varchar;
BEGIN
    CALL osag.osag_plog_debug('change_subject called');

    -- S-TICKET-017 (site #29): STRICT, unhandled.
    SELECT company_id INTO STRICT cust_id
    FROM tt.ticket WHERE id = p_ticket_id;

    -- S-TICKET-017 (site #30): STRICT, unhandled.
    SELECT t.subject INTO STRICT sub_old FROM tt.ticket t
    WHERE t.id = p_ticket_id;

    -- add a ticket "attribute change event" to the ticket
    INSERT INTO tt.event
        (id, type_id, company_id, ticket_id, contact_id, details_public, contact_zitadel_id)
    VALUES (nextval('tt.event_sequence'),
            100003,
            cust_id,
            p_ticket_id,
            p_contact_id,
            'ticket subject changed:' || chr(10) || 'old: ' || sub_old || chr(10) || 'new: ' || p_subject,
            p_zitadel_contact_id::varchar);

    -- update the subject in the ticket
    UPDATE tt.ticket
    SET subject = p_subject
    WHERE id = p_ticket_id;
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- change_customer_reference (S-TICKET-018, Checklist dimension 1 finding #1). Boundary
-- normalization (NULLIF) applied to the audit-text IS NOT NULL check ONLY -- the UPDATE
-- writes p_customer_reference verbatim, matching Oracle's own storage behavior exactly.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.ticket_interface_change_customer_reference(
    p_ticket_id numeric,
    p_customer_reference varchar,
    p_contact_id numeric,
    p_zitadel_contact_id numeric DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_change_text varchar;
    v_event_id numeric;
BEGIN
    IF (NULLIF(p_customer_reference, '') IS NOT NULL) THEN
        v_change_text := 'customer reference changed to ' || p_customer_reference;
    ELSE
        v_change_text := 'customer reference changed to <empty>';
    END IF;

    UPDATE tt.ticket
    SET customer_reference = p_customer_reference
    WHERE id = p_ticket_id;

    -- writing audit trail
    CALL tt.ticket_interface__add_status_change_event(v_event_id, p_ticket_id, v_change_text, p_contact_id, NULL, p_zitadel_contact_id);
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- change_label, 2-arg overload (S-TICKET-019): bare form, single UPDATE, no SELECT, no
-- EXCEPTION block. A nonexistent ticket id silently no-ops (no implicit row-count check
-- in either engine).
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.ticket_interface_change_label(
    p_ticket_id numeric,
    p_label_id numeric)
LANGUAGE plpgsql
AS $fn$
BEGIN
    UPDATE tt.ticket SET label_id = p_label_id
    WHERE id = p_ticket_id;
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- change_label, 4-arg overload (S-TICKET-020): the audited form. Calls the 2-arg
-- overload to perform the actual update, then inserts its own audit event directly. No
-- EXCEPTION block of its own -- all three SELECT INTO sites propagate fully unhandled.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.ticket_interface_change_label(
    p_ticket_id numeric,
    p_label_id numeric,
    p_contact_id numeric,
    p_zitadel_contact_id numeric DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_change_text varchar;
    v_company_id numeric;
    v_label_name varchar;
    v_old_label_id numeric;
    v_old_label_name varchar;
BEGIN
    -- S-TICKET-020 (site #31): STRICT, unhandled.
    SELECT company_id, label_id INTO STRICT v_company_id, v_old_label_id FROM tt.ticket WHERE id = p_ticket_id;

    -- get old label name
    IF (v_old_label_id IS NULL) THEN
        v_old_label_name := 'null';
    ELSE
        -- S-TICKET-020 (site #32): STRICT, unhandled.
        SELECT name INTO STRICT v_old_label_name FROM tt.label WHERE id = v_old_label_id;
    END IF;

    -- create audit event private text
    IF (p_label_id IS NULL) THEN
        v_change_text := 'Ticket label removed (was: ' || v_old_label_name || ')';
    ELSE
        -- S-TICKET-020 (site #33): STRICT, unhandled.
        SELECT name INTO STRICT v_label_name FROM tt.label WHERE id = p_label_id;
        IF (v_old_label_id IS NULL) THEN
            v_change_text := 'Ticket label ' || v_label_name || ' added';
        ELSE
            v_change_text := 'Ticket label changed to ' || v_label_name || ' (was: ' || v_old_label_name || ')';
        END IF;
    END IF;

    CALL tt.ticket_interface_change_label(p_ticket_id, p_label_id);

    -- add an "attribute change event" to the ticket
    INSERT INTO tt.event
        (id, public_event, type_id, company_id, ticket_id, contact_id, details_private, contact_zitadel_id)
    VALUES (nextval('tt.event_sequence'),
            0,
            100003,
            v_company_id,
            p_ticket_id,
            p_contact_id,
            v_change_text,
            p_zitadel_contact_id::varchar);
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- expire_status (S-TICKET-021). Genuine doc/body disagreement: Oracle's doc comment
-- claims it "calls change_label() and change_status()"; the body only calls
-- change_status -- p_label_id is accepted but never read. Reproduced faithfully (body is
-- authoritative), not "fixed" by inventing a change_label call Oracle does not make.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.ticket_interface_expire_status(
    p_ticket_id numeric,
    p_valid_until timestamp,
    p_last_change timestamp,
    p_status_id numeric,
    p_status_name varchar,
    p_label_id numeric)
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_private_details varchar;
    v_time_difference numeric := 0;
BEGIN
    -- time difference is computed in hours (Oracle: 24 * (DATE - DATE) days)
    v_time_difference := round((extract(epoch FROM (p_valid_until - p_last_change)) / 3600)::numeric, 2);
    v_private_details := 'Status changed to: hot (was ' || p_status_name || ' for ' || v_time_difference || ' hours)';
    -- change the current status to status hot (3)
    CALL tt.ticket_interface_change_status(p_ticket_id, 3, NULL, NULL, v_private_details);
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- change_partner_reference (S-TICKET-022, Checklist dimension 1 finding #1, structurally
-- identical to change_customer_reference). Note the deliberate public/private asymmetry
-- vs change_customer_reference: here the audit event's PUBLIC text is NULL and the
-- generated text goes into the PRIVATE slot -- reproduced exactly from Oracle source
-- (ddl/src/pkgb/tt_ticket_interface.sql:1043), not harmonized with its sibling routine.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.ticket_interface_change_partner_reference(
    p_ticket_id numeric,
    p_partner_reference varchar,
    p_contact_id numeric,
    p_zitadel_contact_id numeric DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_change_text varchar;
    v_event_id numeric;
BEGIN
    IF (NULLIF(p_partner_reference, '') IS NOT NULL) THEN
        v_change_text := 'partner reference changed to ' || p_partner_reference;
    ELSE
        v_change_text := 'partner reference changed to <empty>';
    END IF;

    UPDATE tt.ticket
    SET partner_reference = p_partner_reference
    WHERE id = p_ticket_id;

    -- writing audit trail (public=NULL, private=v_change_text -- see header note)
    CALL tt.ticket_interface__add_status_change_event(v_event_id, p_ticket_id, NULL, p_contact_id, v_change_text, p_zitadel_contact_id);
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- change_owner (S-TICKET-023). Three mutually exclusive branches; no EXCEPTION block of
-- its own -- whichever branch fires, the failure propagates fully unhandled.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.ticket_interface_change_owner(
    p_ticket_id numeric,
    p_owner_id numeric,
    p_contact_id numeric,
    p_zitadel_owner_id numeric DEFAULT NULL,
    p_zitadel_contact_id numeric DEFAULT NULL,
    p_company_id numeric DEFAULT NULL,
    p_owner_zitadel_first_name varchar DEFAULT NULL,
    p_owner_zitadel_last_name varchar DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
DECLARE
    first_name varchar;
    last_name varchar;
    v_details_public varchar;
    v_company_id numeric;
BEGIN
    -- if provided, use zitadel info
    IF (p_owner_zitadel_first_name IS NOT NULL AND p_owner_zitadel_last_name IS NOT NULL) THEN
        v_details_public := 'ticket owner changed to ' || p_owner_zitadel_first_name || ' ' || p_owner_zitadel_last_name;
    ELSIF (p_owner_id IS NOT NULL) THEN
        -- S-TICKET-023 (site #34): STRICT, unhandled.
        SELECT firstname, lastname INTO STRICT first_name, last_name
        FROM stop.contact
        WHERE id = p_owner_id;

        v_details_public := 'ticket owner changed to ' || first_name || ' ' || last_name;

        -- S-TICKET-023 (site #35): STRICT, unhandled -- re-query of the same row.
        SELECT company_id INTO STRICT v_company_id
        FROM stop.contact
        WHERE id = p_owner_id;
    ELSE
        v_details_public := 'ticket owner changed to <empty>';

        -- S-TICKET-023 (site #36): STRICT, unhandled.
        SELECT company_id INTO STRICT v_company_id
        FROM tt.ticket WHERE id = p_ticket_id;
    END IF;

    -- update the ticket owner and his company using zitadel ids if provided
    IF (p_zitadel_owner_id IS NOT NULL AND p_company_id IS NOT NULL) THEN
        UPDATE tt.ticket
        SET contact_zitadel_id = p_zitadel_owner_id::varchar,
            company_id = p_company_id
        WHERE id = p_ticket_id;
    ELSE
        UPDATE tt.ticket
        SET contact_id = p_owner_id,
            company_id = v_company_id
        WHERE id = p_ticket_id;
    END IF;

    -- add an "attribute change event" to the ticket
    INSERT INTO tt.event
        (id, type_id, company_id, ticket_id, contact_id, details_public, contact_zitadel_id)
    VALUES (nextval('tt.event_sequence'),
            100003,
            v_company_id,
            p_ticket_id,
            p_contact_id,
            v_details_public,
            p_zitadel_contact_id::varchar);
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- change_company (S-TICKET-024). Sites #37-#39 propagate fully unhandled; site #40 has
-- its own local NO_DATA_FOUND handler -- the only one of the four.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.ticket_interface_change_company(
    p_ticket_id numeric,
    p_company_id numeric,
    p_contact_id numeric,
    p_zitadel_contact_id numeric DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_companyshort varchar;
    v_old_company_short varchar;
    v_old_company_id numeric;
    v_old_host_name varchar;
    v_old_host_id numeric;
BEGIN
    -- collect old data for history -- S-TICKET-024 (site #37): STRICT, unhandled.
    SELECT t.company_id, t.host_id INTO STRICT v_old_company_id, v_old_host_id FROM tt.ticket t WHERE t.id = p_ticket_id;

    IF (v_old_host_id IS NOT NULL) THEN
        -- S-TICKET-024 (site #38): STRICT, unhandled.
        SELECT h.name INTO STRICT v_old_host_name FROM mss.host h WHERE id = v_old_host_id;
    ELSE
        v_old_host_name := '<none>';
    END IF;

    IF (v_old_company_id IS NOT NULL) THEN
        -- S-TICKET-024 (site #39): STRICT, unhandled.
        SELECT c.short INTO STRICT v_old_company_short FROM stop.company c WHERE c.id = v_old_company_id;
    ELSE
        v_old_company_short := '<empty>';
    END IF;

    -- update the ticket owner and his company -- make sure that service and owner is
    -- also reset!
    UPDATE tt.ticket
    SET company_id = p_company_id, contact_id = NULL, contact_zitadel_id = NULL, mss_service_id = NULL, host_id = NULL
    WHERE id = p_ticket_id;

    BEGIN
        -- S-TICKET-024 (site #40): STRICT + local NO_DATA_FOUND handler.
        SELECT short INTO STRICT v_companyshort
        FROM stop.company
        WHERE id = p_company_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_companyshort := '<empty>';
    END;

    -- add an "attribute change event" to the ticket
    INSERT INTO tt.event
        (id, type_id, company_id, ticket_id, contact_id, details_private, public_event, contact_zitadel_id)
    VALUES (nextval('tt.event_sequence'),
            100003,
            p_company_id,
            p_ticket_id,
            p_contact_id,
            'company changed to ' || v_companyshort || chr(10) || 'old company: '||v_old_company_short
                ||chr(10)||'old assigned host: '||v_old_host_name,
            0,
            p_zitadel_contact_id::varchar);

    -- delete notifications for non-OSAG logins which are assigned to this ticket
    DELETE FROM tt.event_notification en
    WHERE EXISTS
              (SELECT en.id FROM auth.login l
               WHERE en.ticket_id = p_ticket_id
                 AND en.login_id = l.id
                 AND l.company_id != 6);  -- company_id = 6 means OSAG

    -- adapt the company reference of existing notifications of OSAG logins
    UPDATE tt.event_notification en
    SET company_id = p_company_id
    WHERE EXISTS
              (SELECT en.id FROM auth.login l
               WHERE en.ticket_id = p_ticket_id
                 AND en.login_id = l.id
                 AND l.company_id = 6); -- company_id = 6 means OSAG
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- change_emergency (S-TICKET-025). GENUINE ORACLE BUG (see file header): the
-- add_status_change_event call below has only 5 positional args -- p_zitadel_contact_id
-- lands in add_status_change_event's p_private_change_text slot (::varchar cast makes
-- the implicit Oracle NUMBER->VARCHAR2 conversion explicit), and the real zitadel contact
-- id is never forwarded. Reproduced exactly, not fixed.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.ticket_interface_change_emergency(
    p_ticket_id numeric,
    p_emergency numeric,
    p_contact_id numeric,
    p_is_new_ticket numeric DEFAULT 0,
    p_zitadel_contact_id numeric DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
DECLARE
    change_text varchar;
    v_event_id numeric;
BEGIN
    IF (p_emergency = 1) THEN
        change_text := 'ticket changed to emergency';
    ELSE
        change_text := 'ticket changed to non-emergency';
    END IF;

    -- ORACLE BUG (5 positional args against a 6-param signature) -- see file header.
    CALL tt.ticket_interface__add_status_change_event(v_event_id, p_ticket_id, change_text, p_contact_id, p_zitadel_contact_id::varchar);

    UPDATE tt.ticket
    SET emergency = p_emergency, was_emergency = GREATEST(p_emergency, was_emergency)
    WHERE id = p_ticket_id;

    -- update ux timeout
    IF (p_is_new_ticket = 0) THEN
        CALL tt.ticket_interface_update_ux_timeout_for_ticket(p_ticket_id, FALSE);
    ELSE
        CALL tt.ticket_interface_update_ux_timeout_for_ticket(p_ticket_id, TRUE);
    END IF;
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- change_always_visible (S-TICKET-026). SAME ORACLE BUG as change_emergency -- see file
-- header. No SELECT INTO, no EXCEPTION block.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.ticket_interface_change_always_visible(
    p_ticket_id numeric,
    p_always_visible numeric,
    p_contact_id numeric,
    p_zitadel_contact_id numeric DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
DECLARE
    change_text varchar;
    v_event_id numeric;
BEGIN
    IF (p_always_visible = 1) THEN
        change_text := 'ticket changed to always visible';
    ELSE
        change_text := 'ticket changed to not always visible';
    END IF;

    -- ORACLE BUG (5 positional args against a 6-param signature) -- see file header.
    CALL tt.ticket_interface__add_status_change_event(v_event_id, p_ticket_id, change_text, p_contact_id, p_zitadel_contact_id::varchar);

    UPDATE tt.ticket
    SET always_visible = p_always_visible
    WHERE id = p_ticket_id;
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- change_notification (S-TICKET-027, Checklist dimension 1 finding #2 -- CORRECTLY
-- handled already, no divergence: the prefix is only concatenated inside an IS NOT NULL
-- guard, so there is no NULL||'x' collapsing-vs-not divergence to translate).
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.ticket_interface_change_notification(
    p_ticket_id numeric,
    p_change_text_public varchar,
    p_change_text_private varchar,
    p_contact_id numeric,
    p_zitadel_contact_id numeric DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
DECLARE
    EVENT_DETAILS_PREFIX CONSTANT varchar := 'Notification settings changed' || chr(10);
    v_event_id numeric;
    v_event_details_public varchar;
    v_event_details_private varchar;
BEGIN
    IF (p_change_text_public IS NOT NULL) THEN
        v_event_details_public := EVENT_DETAILS_PREFIX || p_change_text_public;
    END IF;

    IF (p_change_text_private IS NOT NULL) THEN
        v_event_details_private := EVENT_DETAILS_PREFIX || p_change_text_private;
    END IF;

    CALL tt.ticket_interface__add_status_change_event(v_event_id, p_ticket_id, v_event_details_public, p_contact_id, v_event_details_private, p_zitadel_contact_id);
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- change_summary (S-TICKET-028..029). GENUINE ORACLE BUG on the PUBLIC-summary branch
-- ONLY (see file header) -- the private-summary branch's add_status_change_event call is
-- the full 6-arg form and has no bug. No EXCEPTION block of its own.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.ticket_interface_change_summary(
    p_ticket_id numeric,
    p_summary_private varchar,
    p_summary_public varchar,
    p_contact_id numeric,
    p_zitadel_contact_id numeric DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
DECLARE
    old_summary_private varchar;
    old_summary_public varchar;
    v_event_id numeric;
    p_summary_rel_events_count numeric;
BEGIN
    -- get the old summary -- S-TICKET-028 (site #41): STRICT, unhandled.
    SELECT summary_private, summary_public, summary_relevant_events_count
    INTO STRICT old_summary_private, old_summary_public, p_summary_rel_events_count
    FROM tt.ticket WHERE id = p_ticket_id;

    -- S-TICKET-029: standard three-valued !=-with-NULLs logic, identical in both engines.
    IF ((old_summary_private != p_summary_private OR
         old_summary_private IS NULL OR
         p_summary_private IS NULL) AND
        NOT (old_summary_private IS NULL AND p_summary_private IS NULL)) THEN

        CALL tt.ticket_interface__add_status_change_event(v_event_id, p_ticket_id, NULL, p_contact_id,
            'private summary changed to:' || chr(10) || substr(COALESCE(p_summary_private, '<empty>'), 1, 3900), p_zitadel_contact_id);

        UPDATE tt.ticket
        SET summary_private = p_summary_private
        WHERE id = p_ticket_id;
    END IF;

    IF ((old_summary_public != p_summary_public OR
         old_summary_public IS NULL OR
         p_summary_public IS NULL) AND
        NOT (old_summary_public IS NULL AND p_summary_public IS NULL)) THEN

        -- ORACLE BUG (5 positional args against a 6-param signature) -- see file header.
        CALL tt.ticket_interface__add_status_change_event(v_event_id, p_ticket_id,
            'public summary changed to:' || chr(10) || substr(COALESCE(p_summary_public, '<empty>'), 1, 3900), p_contact_id, p_zitadel_contact_id::varchar);
        p_summary_rel_events_count := 0;

        UPDATE tt.ticket
        SET summary_public = p_summary_public,
            summary_relevant_events_count = p_summary_rel_events_count,
            last_summary_update = statement_timestamp()
        WHERE id = p_ticket_id;
    END IF;
END;
$fn$;

-- =====================================================================================
-- PUBLIC routines, Task 2 scope: change_type through deleteTicket (routines 20-38 of 38).
-- =====================================================================================

-- ------------------------------------------------------------------------------------
-- change_type (S-TICKET-030..031). No EXCEPTION block -- all three sites propagate fully
-- unhandled.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.ticket_interface_change_type(
    OUT p_event_id numeric,
    p_ticket_id numeric,
    p_type_id numeric,
    p_contact_id numeric,
    p_zitadel_contact_id numeric DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_company_id numeric;
    v_old_type_name varchar;
    v_type_name varchar;
BEGIN
    -- S-TICKET-030 (site #42): STRICT, unhandled.
    SELECT company_id INTO STRICT v_company_id FROM tt.ticket WHERE id = p_ticket_id;

    -- S-TICKET-030 (site #43): STRICT, unhandled.
    SELECT type.name INTO STRICT v_old_type_name FROM tt.ticket_type type, tt.ticket t WHERE type.id = t.type_id AND t.id = p_ticket_id;

    -- S-TICKET-030 (site #44): STRICT, unhandled.
    SELECT name INTO STRICT v_type_name FROM tt.ticket_type WHERE id = p_type_id;

    UPDATE tt.ticket SET type_id = p_type_id WHERE id = p_ticket_id;

    INSERT INTO tt.event
        (id, type_id, company_id, ticket_id, contact_id, details_public, contact_zitadel_id)
    VALUES (nextval('tt.event_sequence'), 100005, v_company_id, p_ticket_id, p_contact_id,
            'type changed from ' || v_old_type_name || ' to ' || v_type_name, p_zitadel_contact_id::varchar);

    -- S-TICKET-031 (site #45): session-local sequence state, no STRICT concern.
    SELECT currval('tt.event_sequence') INTO STRICT p_event_id;

    CALL tt.ticket_interface_update_ux_timeout_for_ticket(p_ticket_id, FALSE);
    CALL tt.ticket_interface_updateticketflow(p_ticket_id);
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- change_service_component (S-TICKET-032). Site #46 propagates unhandled; sites #47-#50
-- are each locally swallowed by one of two NO_DATA_FOUND blocks.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.ticket_interface_change_service_component(
    OUT p_event_id numeric,
    p_ticket_id numeric,
    p_service_component_id numeric,
    p_contact_id numeric,
    p_zitadel_contact_id numeric DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_company_id numeric;
    v_old_service_component_code varchar;
    v_old_service_component_name varchar;
    v_service_component_code varchar;
    v_service_component_name varchar;
BEGIN
    -- S-TICKET-032 (site #46): STRICT, unhandled.
    SELECT company_id INTO STRICT v_company_id FROM tt.ticket WHERE id = p_ticket_id;

    BEGIN
        -- S-TICKET-032 (sites #47-#48): STRICT + local NO_DATA_FOUND handler covering both.
        SELECT sc.internal_code INTO STRICT v_old_service_component_code FROM mss.service_component sc, tt.ticket t WHERE sc.id = t.service_component_id AND t.id = p_ticket_id;
        SELECT sc.name INTO STRICT v_old_service_component_name FROM mss.service_component sc, tt.ticket t WHERE sc.id = t.service_component_id AND t.id = p_ticket_id;
    EXCEPTION WHEN NO_DATA_FOUND THEN
        v_old_service_component_code := '';
        v_old_service_component_name := '<empty>';
    END;

    BEGIN
        -- S-TICKET-032 (sites #49-#50): STRICT + local NO_DATA_FOUND handler covering both.
        SELECT internal_code INTO STRICT v_service_component_code FROM mss.service_component WHERE id = p_service_component_id;
        SELECT name INTO STRICT v_service_component_name FROM mss.service_component WHERE id = p_service_component_id;
    EXCEPTION WHEN NO_DATA_FOUND THEN
        v_service_component_code := '';
        v_service_component_name := '<empty>';
    END;

    UPDATE tt.ticket SET service_component_id = p_service_component_id WHERE id = p_ticket_id;

    INSERT INTO tt.event
        (id, type_id, company_id, ticket_id, contact_id, details_public, details_private, contact_zitadel_id)
    VALUES (nextval('tt.event_sequence'), 100003, v_company_id, p_ticket_id, p_contact_id,
            'service component changed',
            'service component changed from ' || v_old_service_component_name || ' (' || v_old_service_component_code || ') to ' || v_service_component_name || ' (' || v_service_component_code || ')',
            p_zitadel_contact_id::varchar);

    -- S-TICKET-031 (site #51): session-local sequence state, no STRICT concern.
    SELECT currval('tt.event_sequence') INTO STRICT p_event_id;

    CALL tt.ticket_interface_update_ux_timeout_for_ticket(p_ticket_id, FALSE);
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- get_next_recent_ticket (S-TICKET-033, S-TICKET-046). One of the corpus's two
-- FUNCTIONs. Closes the FUNCTION/PROCEDURE-COMMIT question per the spec's own trace: no
-- INSERT/UPDATE/DELETE, calls nothing else -- cannot transitively reach a COMMIT. Has its
-- own whole-function EXCEPTION WHEN OTHERS that logs and returns NULL.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION tt.ticket_interface_get_next_recent_ticket(
    p_last_ticket_id numeric, p_host_id numeric, p_ticket_type_id numeric, p_resolve_age numeric)
RETURNS numeric
LANGUAGE plpgsql
AS $fn$
DECLARE
    c_prefix CONSTANT text := 'get_next_recent_ticket(): ';
    v_ticketid numeric := NULL;
BEGIN
    -- only look at tickets that haven't been closed (status 102) yet and are not
    -- deferred (status 60). S-TICKET-033 (site #52): MIN aggregate, no STRICT concern.
    SELECT MIN(t.id) INTO v_ticketid
    FROM tt.ticket t
    WHERE (t.status_id < 102) AND (t.status_id <> 60)
      AND (p_last_ticket_id IS NULL OR (t.id > p_last_ticket_id))
      AND (p_host_id IS NULL OR (t.host_id = p_host_id) OR (p_host_id = 0 AND t.host_id IS NULL))
      AND (p_ticket_type_id IS NULL OR (t.type_id = p_ticket_type_id))
      AND (p_resolve_age IS NULL
        OR t.status_id < 60   -- ticket not resolved yet
        OR ((t.last_resolved_date IS NULL) OR extract(epoch FROM (statement_timestamp()::timestamp - t.last_resolved_date)) <= p_resolve_age)); -- ticket resolved

    RETURN v_ticketid;
EXCEPTION
    WHEN OTHERS THEN
        CALL osag.osag_plog_err(c_prefix||'unexpected error 99: '||SQLERRM);
        RETURN NULL;
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- merge_tickets (S-TICKET-034..036). Merges the SOURCE ticket into the TARGET ticket. No
-- procedure-level EXCEPTION block of its own -- every unhandled SELECT INTO here
-- propagates fully.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.ticket_interface_merge_tickets(
    p_ticket_id numeric,
    p_mticket_id numeric,
    p_contact_id numeric,
    p_zitadel_contact_id numeric DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_event_id numeric;
    v_partner_ref varchar;
    v_mpartner_ref varchar;
    v_fast_resolvable numeric;
    v_mfast_resolvable numeric;
    v_last_public_event_id numeric;
    v_mlast_public_event_id numeric;
    v_last_public_event_date timestamp;
    v_mlast_public_event_date timestamp;
    v_cust_rating_id numeric;
    v_mcust_rating_id numeric;
    v_eng_rating_id numeric;
    v_meng_rating_id numeric;
    v_mstatus_id numeric;
    v_mrecoverable_status_id numeric;
    v_ux_timeout_start timestamp;
    v_mux_timeout_start timestamp;
BEGIN
    -- S-TICKET-034 (site #53): STRICT, unhandled -- merge_tickets has no EXCEPTION block.
    SELECT partner_reference, fast_resolvable, last_public_event_id, ux_timeout_start, customer_ticket_rating_id, engineer_ticket_rating_id
    INTO STRICT v_partner_ref, v_fast_resolvable, v_last_public_event_id, v_ux_timeout_start, v_cust_rating_id, v_eng_rating_id
    FROM tt.ticket
    WHERE id = p_ticket_id;

    IF (v_last_public_event_id IS NOT NULL) THEN
        -- S-TICKET-034 (site #54): STRICT, unhandled.
        SELECT eventdate INTO STRICT v_last_public_event_date FROM tt.event WHERE id = v_last_public_event_id;
    END IF;

    -- S-TICKET-034 (site #55): STRICT, unhandled -- mirror query for the target ticket.
    SELECT partner_reference, fast_resolvable, last_public_event_id, recoverable_status_id, status_id, ux_timeout_start, customer_ticket_rating_id, engineer_ticket_rating_id
    INTO STRICT v_mpartner_ref, v_mfast_resolvable, v_mlast_public_event_id, v_mrecoverable_status_id, v_mstatus_id, v_mux_timeout_start, v_mcust_rating_id, v_meng_rating_id
    FROM tt.ticket
    WHERE id = p_mticket_id;

    IF (v_mlast_public_event_id IS NOT NULL) THEN
        -- S-TICKET-034 (site #56): STRICT, unhandled.
        SELECT eventdate INTO STRICT v_mlast_public_event_date FROM tt.event WHERE id = v_mlast_public_event_id;
    END IF;

    -- S-TICKET-035: handle ratings (take most recent by id) -- customer
    IF (v_cust_rating_id IS NOT NULL) THEN
        UPDATE tt.ticket SET customer_ticket_rating_id = COALESCE(GREATEST(v_cust_rating_id, v_mcust_rating_id), v_cust_rating_id) WHERE id = p_mticket_id;
    END IF;

    -- engineer
    IF (v_eng_rating_id IS NOT NULL) THEN
        UPDATE tt.ticket SET engineer_ticket_rating_id = COALESCE(GREATEST(v_eng_rating_id, v_meng_rating_id), v_eng_rating_id) WHERE id = p_mticket_id;
    END IF;

    -- merge all events from ticket to mticket by changing the ticket id in the event
    -- table, but backup the original ticket id
    UPDATE tt.event
    SET org_ticket_id = ticket_id
    WHERE ticket_id = p_ticket_id AND org_ticket_id IS NULL;

    UPDATE tt.event
    SET ticket_id = p_mticket_id
    WHERE ticket_id = p_ticket_id;

    -- add a mergeticket event (event type 100004) to ticket -- we write the p_mticket_id
    -- in the private details field to give addevent a hint where to redirect when trying
    -- to add an event to a merged ticket. so do not remove (Oracle's own comment).
    CALL tt.event_interface_addevent_new(v_event_id,
        p_mticket_id,
        100004,
        NULL,
        'ticket ' || p_ticket_id || ' merged with ticket no ' || p_mticket_id,
        p_mticket_id::varchar,
        p_contact_id,
        TRUE, statement_timestamp(), FALSE,
        p_zitadel_contact_id);

    -- Instead of simply connecting this event (in mticket) with the p_ticket, we create
    -- an exact duplicate of the event and connect p_ticket to this duplicate -> prepare
    -- migration to MC 7.1 where we don't have shared events anymore.
    INSERT INTO tt.event
        (id, company_id, details_private, details_public, eventdate, public_event, type_id, ticket_id, contact_id, host_id, contact_zitadel_id)
    SELECT nextval('tt.event_sequence'), company_id, details_private, details_public, eventdate, public_event, type_id, p_ticket_id, contact_id, host_id, contact_zitadel_id
    FROM tt.event
    WHERE id = v_event_id;

    -- set the merged into ticket field of the source ticket to hold the target ticket
    UPDATE tt.ticket SET merged_into_ticket_id = p_mticket_id WHERE id = p_ticket_id;

    -- S-TICKET-036: set the p_ticket status to merged (status 110) and set the close and
    -- resolve date
    CALL tt.ticket_interface_change_status(p_ticket_id, 110, p_contact_id, NULL, NULL, NULL, NULL, NULL, NULL, p_zitadel_contact_id);
    UPDATE tt.ticket
    SET close_date = statement_timestamp(), last_resolved_date = statement_timestamp(), last_public_event_id = NULL
    WHERE id = p_ticket_id;

    -- delete duplicate ticket notifications
    DELETE FROM tt.event_notification en1
    WHERE en1.ticket_id = p_ticket_id
      AND EXISTS (SELECT * FROM tt.event_notification en2
                  WHERE en2.ticket_id = p_mticket_id
                    AND en2.event_notification_type_id = en1.event_notification_type_id
                    AND en2.login_id = en1.login_id
                    AND (
                      ((en2.event_type_id IS NULL AND en1.event_type_id IS NULL) OR (en2.event_type_id = en1.event_type_id))
                          OR
                      ((en2.event_type_group_id IS NULL AND en1.event_type_group_id IS NULL) OR (en2.event_type_group_id = en1.event_type_group_id))
                      ));

    -- move ticket notifications from p_ticket to p_mticket
    UPDATE tt.event_notification
    SET ticket_id = p_mticket_id
    WHERE ticket_id = p_ticket_id;

    -- move any existing change requests from p_ticket to p_mticket
    UPDATE tt.change_request
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

    -- if both tickets have a "last public event", choose the newest -- if the last
    -- public event changes, the recoverable status is cleared.
    IF (v_last_public_event_id IS NOT NULL AND v_mlast_public_event_id IS NOT NULL AND v_last_public_event_date > v_mlast_public_event_date) THEN
        v_mlast_public_event_id := v_last_public_event_id;
        v_mrecoverable_status_id := NULL;
        -- if only the source ticket has one, merge it into the target
    ELSIF (v_last_public_event_id IS NOT NULL AND v_mlast_public_event_id IS NULL) THEN
        v_mlast_public_event_id := v_last_public_event_id;
        v_mrecoverable_status_id := NULL;
    END IF;

    -- update the ux_timeout start if the one from the source ticket is newer -- the
    -- timeout itself will be updated when the status of the ticket is changed to hot
    IF (v_ux_timeout_start > v_mux_timeout_start) THEN
        v_mux_timeout_start := v_ux_timeout_start;
    END IF;

    -- To make life easier: if the target ticket was resolved (101), make the status
    -- recoverable
    IF (v_mstatus_id = 101) THEN
        v_mrecoverable_status_id := 101;
    END IF;

    -- move suppressed events to new ticket
    UPDATE guma2.suppressed_signature
    SET ticket_id = p_mticket_id
    WHERE ticket_id = p_ticket_id;

    -- update all requirement attributes of the target ticket
    UPDATE tt.ticket
    SET partner_reference = v_mpartner_ref, fast_resolvable = v_mfast_resolvable, last_public_event_id = v_mlast_public_event_id, recoverable_status_id = v_mrecoverable_status_id, ux_timeout_start = v_mux_timeout_start
    WHERE id = p_mticket_id;

    -- set the status of the merged to ticket to hot (status 3)
    CALL tt.ticket_interface_change_status(p_mticket_id, 3, p_contact_id, NULL, NULL, NULL, NULL, NULL, 'ticket ' || p_ticket_id || ' merged into this ticket', p_zitadel_contact_id);
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- replace_id_placeholders (S-TICKET-037, S-TICKET-046). The package's OTHER FUNCTION.
-- Pure string substitution, no SELECT of any kind, no call to any other routine, no
-- EXCEPTION block -- closes the FUNCTION/PROCEDURE-COMMIT question for this routine too:
-- it cannot transitively reach a COMMIT because it calls nothing at all.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION tt.ticket_interface_replace_id_placeholders(
    p_text varchar, p_ticket_id numeric, p_event_id numeric)
RETURNS varchar
LANGUAGE plpgsql
IMMUTABLE
AS $fn$
DECLARE
    v_text varchar;
BEGIN
    v_text := substr(replace(p_text, '##ticket_id##', p_ticket_id::varchar), 1, 30000);
    v_text := substr(replace(v_text, '##event_id##', p_event_id::varchar), 1, 30000);
    RETURN v_text;
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- trigger_escalation (S-TICKET-038). No SELECT INTO at this routine's own level. Has its
-- own EXCEPTION WHEN OTHERS that logs and swallows, never propagates.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.ticket_interface_trigger_escalation(
    p_ticket_id numeric, p_contact_id numeric, p_triggering_event_id numeric,
    p_zitadel_contact_id numeric DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
DECLARE
    c_prefix CONSTANT text := 'trigger_escalation(): ';
    v_event_id numeric;
BEGIN
    -- event type id is 100007 = escalation triggering event
    CALL tt.event_interface_add_history_event(v_event_id,
        p_ticket_id,
        100007,
        NULL,     -- no host_id specified
        NULL,     -- no company_id specified
        'Explicitly trigger escalation',
        'Escalation triggered by event '||p_triggering_event_id,
        TRUE,     -- it is a public event
        statement_timestamp(),
        p_contact_id,
        p_zitadel_contact_id);

    -- execute the event type actions
    CALL tt.event_interface_exec_event_type_actions(v_event_id);
EXCEPTION
    WHEN OTHERS THEN
        CALL osag.osag_plog_err(c_prefix||'unexpected error: '||SQLERRM);
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- rate_ticket (S-TICKET-039). No EXCEPTION block of its own -- any INSERT/UPDATE failure
-- propagates fully unhandled.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.ticket_interface_rate_ticket(
    OUT p_rating_id numeric,
    p_ticket_id numeric,
    p_rating_event_id numeric,
    p_contact_id numeric,
    p_by_engineer numeric,
    p_rating_value numeric,
    p_zitadel_contact_id numeric DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
BEGIN
    -- S-TICKET-039 (site #58): sequence pull, no STRICT concern.
    SELECT nextval('tt.ticketrating_seq') INTO STRICT p_rating_id;

    INSERT INTO tt.ticket_rating(id, rating, event_id)
    VALUES (p_rating_id, p_rating_value, p_rating_event_id);

    -- rating by engineer
    IF (p_by_engineer > 0) THEN
        UPDATE tt.ticket
        SET engineer_ticket_rating_id = p_rating_id
        WHERE id = p_ticket_id;
        -- rating by customer
    ELSE
        UPDATE tt.ticket
        SET customer_ticket_rating_id = p_rating_id
        WHERE id = p_ticket_id;
        -- if the rating by customer was bad (< 3), make the ticket hot (status 3)
        IF (p_rating_value < 3) THEN
            CALL tt.ticket_interface_change_status(p_ticket_id, 3, p_contact_id, NULL, NULL, NULL, NULL, NULL, NULL, p_zitadel_contact_id);
        END IF;
    END IF;
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- add_docs_page (S-TICKET-040). Has its own EXCEPTION WHEN OTHERS covering the entire
-- body -- logs and swallows, never propagates.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.ticket_interface_add_docs_page(
    OUT p_ticket_docs_page_id numeric,
    p_ticket_id numeric,
    p_page_id numeric,
    p_page_version numeric,
    p_page_title varchar,
    p_hot_issue numeric,
    p_contact_id numeric,
    p_zitadel_contact_id numeric DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_details_private varchar;
    v_event_id numeric;
BEGIN
    -- S-TICKET-040 (site #59): sequence pull, no STRICT concern; whole-routine WHEN
    -- OTHERS below covers it regardless.
    SELECT nextval('tt.ticketdocspage_seq') INTO STRICT p_ticket_docs_page_id;

    INSERT INTO tt.ticket_docs_page(id, ticket_id, page_id, page_version, hot_issue)
    VALUES (p_ticket_docs_page_id, p_ticket_id, p_page_id, p_page_version, p_hot_issue);

    -- NOTE: if you change the private details, the text might not be replaced by a link
    -- anymore (see the DOCS_URL_PATTERN in HTML.java -- Oracle's own comment).
    v_details_private := 'Docs Page "' || p_page_title || '" (ID ' || p_page_id || ', v' || p_page_version
        || ') has been added to the ticket.';
    IF (p_hot_issue > 0) THEN
        v_details_private := 'Hot issue ' || v_details_private;
    END IF;
    CALL tt.event_interface_addevent_new(v_event_id, p_ticket_id, 100009, NULL, '', v_details_private, p_contact_id, FALSE, statement_timestamp(), FALSE, p_zitadel_contact_id);
EXCEPTION
    WHEN OTHERS THEN
        CALL osag.osag_plog_err('tt.ticketInterface.add_docs_page: Unexpected error: ' || SQLERRM);
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- remove_docs_page (S-TICKET-041). 2-arm handler: NO_DATA_FOUND silently does nothing
-- further; WHEN OTHERS logs.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.ticket_interface_remove_docs_page(
    p_ticket_docs_page_id numeric,
    p_page_title varchar,
    p_contact_id numeric,
    p_zitadel_contact_id numeric DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_details_private varchar;
    v_page_id numeric;
    v_page_version numeric;
    v_ticket_id numeric;
    v_event_id numeric;
BEGIN
    -- S-TICKET-041 (site #60): STRICT + 2-arm handler.
    SELECT page_id, page_version, ticket_id
    INTO STRICT v_page_id, v_page_version, v_ticket_id
    FROM tt.ticket_docs_page
    WHERE id = p_ticket_docs_page_id;

    DELETE FROM tt.ticket_docs_page WHERE id = p_ticket_docs_page_id;
    v_details_private := 'Docs Page "' || p_page_title || '" (ID ' || v_page_id || ', v' || v_page_version
        || ') has been removed from the ticket.';
    CALL tt.event_interface_addevent_new(v_event_id, v_ticket_id, 100010, NULL, '', v_details_private, p_contact_id, FALSE, statement_timestamp(), FALSE, p_zitadel_contact_id);
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        NULL;
    WHEN OTHERS THEN
        CALL osag.osag_plog_err('tt.ticketInterface.remove_docs_page: Unexpected error: ' || SQLERRM);
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- add_related_ticket (S-TICKET-042). v_counter != 2 (bad id(s) OR equal ids) logs and
-- RETURNs early -- a normal early exit, not an exception path. Has its own EXCEPTION
-- WHEN OTHERS.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.ticket_interface_add_related_ticket(
    p_ticket_id numeric, p_related_ticket_id numeric, p_contact_id numeric,
    p_zitadel_contact_id numeric DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
DECLARE
    c_prefix CONSTANT text := 'add_related_ticket(): ';
    v_details_private varchar;
    v_counter numeric;
    v_event_id numeric;
BEGIN
    -- both tickets have to exist. S-TICKET-042 (site #62): COUNT aggregate, no STRICT
    -- concern.
    SELECT COUNT(*) INTO v_counter FROM tt.ticket t
    WHERE t.id IN (p_ticket_id, p_related_ticket_id);

    IF (v_counter != 2) THEN
        CALL osag.osag_plog_err(c_prefix || 'One of the tickets involved does not exist or they are equal. Aborted!');
        RETURN;
    END IF;

    INSERT INTO tt.ticket2related_ticket (ticket_id, related_ticket_id)
    VALUES (p_ticket_id, p_related_ticket_id);

    v_details_private := 'Related ticket ' || p_related_ticket_id || ' has been added to the ticket.';
    CALL tt.event_interface_addevent_new(v_event_id, p_ticket_id, 100016, NULL, NULL, v_details_private, p_contact_id, FALSE, statement_timestamp(), FALSE, p_zitadel_contact_id);
EXCEPTION
    WHEN OTHERS THEN
        CALL osag.osag_plog_err(c_prefix || 'Unexpected error: ' || SQLERRM);
        RETURN;
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- remove_related_ticket (S-TICKET-043). Mirror of add_related_ticket -- zero matches is
-- a normal silent no-op.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.ticket_interface_remove_related_ticket(
    p_ticket_id numeric, p_related_ticket_id numeric, p_contact_id numeric,
    p_zitadel_contact_id numeric DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
DECLARE
    c_prefix CONSTANT text := 'remove_related_ticket(): ';
    v_counter numeric;
    v_details_private varchar;
    v_event_id numeric;
BEGIN
    -- S-TICKET-043 (site #63): COUNT aggregate, no STRICT concern.
    SELECT COUNT(*) INTO v_counter FROM tt.ticket2related_ticket rt
    WHERE rt.ticket_id = p_ticket_id AND rt.related_ticket_id = p_related_ticket_id;

    IF (v_counter > 0) THEN
        DELETE FROM tt.ticket2related_ticket
        WHERE ticket_id = p_ticket_id AND related_ticket_id = p_related_ticket_id;

        v_details_private := 'Removed ticket ' || p_related_ticket_id || ' from the list of related tickets.';
        CALL tt.event_interface_addevent_new(v_event_id, p_ticket_id, 100017, NULL, NULL, v_details_private, p_contact_id, FALSE, statement_timestamp(), FALSE, p_zitadel_contact_id);
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        CALL osag.osag_plog_err(c_prefix || 'Unexpected error: ' || SQLERRM);
        RETURN;
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- add_related_file (S-TICKET-044). The t.company_id = r.company_id join predicate is a
-- DELIBERATE same-company authorization guard (Oracle's own inline comment) -- a
-- cross-company mismatch is EXPECTED to raise NO_DATA_FOUND here, not incidental.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.ticket_interface_add_related_file(
    p_ticket_id numeric, p_related_file_id numeric, p_contact_id numeric, p_zitadel_contact_id numeric DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
DECLARE
    c_prefix CONSTANT text := 'add_related_file(): ';
    v_file_display_name varchar;
    v_details_private varchar;
    v_event_id numeric;
BEGIN
    -- S-TICKET-044 (site #64): STRICT + 2-arm handler.
    SELECT f.display_name INTO STRICT v_file_display_name FROM mc.mc_file f, mc.mc_file_release r, tt.ticket t
    WHERE t.id = p_ticket_id AND f.id = p_related_file_id AND r.mc_file_id = f.id
      AND t.company_id = r.company_id;

    INSERT INTO tt.ticket2mc_file (ticket_id, mc_file_id)
    VALUES (p_ticket_id, p_related_file_id);

    v_details_private := 'Related file "' || v_file_display_name || '" (' || p_related_file_id || ') has been added to the ticket.';
    CALL tt.event_interface_addevent_new(v_event_id, p_ticket_id, 100018, NULL, NULL, v_details_private, p_contact_id, FALSE, statement_timestamp(), FALSE, p_zitadel_contact_id);
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        CALL osag.osag_plog_err(c_prefix || 'MC File or ticket does not exits or they belong to different companies.');
        RETURN;
    WHEN OTHERS THEN
        CALL osag.osag_plog_err(c_prefix || 'Unexpected error: ' || SQLERRM);
        RETURN;
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- remove_related_file (S-TICKET-045). No same-company guard here (unlike
-- add_related_file) -- a deliberate asymmetry between the two mirror routines, not
-- harmonized. No NO_DATA_FOUND arm -- a bad p_related_file_id falls to WHEN OTHERS.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.ticket_interface_remove_related_file(
    p_ticket_id numeric, p_related_file_id numeric, p_contact_id numeric,
    p_zitadel_contact_id numeric DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
DECLARE
    c_prefix CONSTANT text := 'remove_related_file(): ';
    v_counter numeric;
    v_details_private varchar;
    v_event_id numeric;
    v_file_display_name varchar;
BEGIN
    -- S-TICKET-045 (site #65): COUNT aggregate, no STRICT concern.
    SELECT COUNT(*) INTO v_counter FROM tt.ticket2mc_file t2f
    WHERE t2f.ticket_id = p_ticket_id AND t2f.mc_file_id = p_related_file_id;

    IF (v_counter > 0) THEN
        -- S-TICKET-045 (site #66): STRICT, no local handler.
        SELECT mcf.display_name INTO STRICT v_file_display_name FROM mc.mc_file mcf
        WHERE mcf.id = p_related_file_id;

        DELETE FROM tt.ticket2mc_file
        WHERE ticket_id = p_ticket_id AND mc_file_id = p_related_file_id;

        v_details_private := 'Removed file "' || v_file_display_name || '" (' || p_related_file_id || ') from the list of related files.';
        CALL tt.event_interface_addevent_new(v_event_id, p_ticket_id, 100019, NULL, NULL, v_details_private, p_contact_id, FALSE, statement_timestamp(), FALSE, p_zitadel_contact_id);
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        CALL osag.osag_plog_err(c_prefix || 'Unexpected error: ' || SQLERRM);
        RETURN;
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- classify_request (S-TICKET-047). A classification value outside {1,2,3} (including
-- NULL) silently defaults to 2 ("standard") -- no error raised, contradicting the doc
-- comment's implication that only 1/2/3 are valid. Reproduced faithfully.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.ticket_interface_classify_request(
    p_ticket_id numeric, p_classification numeric, p_contact_id numeric,
    p_zitadel_contact_id numeric DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
DECLARE
    c_prefix CONSTANT text := 'classify_request(): ';
    v_counter numeric;
    v_details_private varchar;
    v_classification numeric;
    v_classification_text varchar;
    v_event_id numeric;
BEGIN
    v_classification := p_classification;

    IF (p_classification = 1) THEN
        v_classification_text := 'very precise';
    ELSIF (p_classification = 2) THEN
        v_classification_text := 'standard';
    ELSIF (p_classification = 3) THEN
        v_classification_text := 'imprecise';
    ELSE
        -- default to "standard" in case an invalid option (or NULL) is given
        v_classification := 2;
        v_classification_text := 'standard';
    END IF;

    -- S-TICKET-047 (site #67): COUNT aggregate, no STRICT concern.
    SELECT COUNT(*) INTO v_counter FROM tt.ticket_request_classification
    WHERE ticket_id = p_ticket_id;

    IF (v_counter > 0) THEN
        UPDATE tt.ticket_request_classification SET classification = v_classification
        WHERE ticket_id = p_ticket_id;
    ELSE
        INSERT INTO tt.ticket_request_classification (id, ticket_id, classification)
        VALUES (nextval('tt.ticketreqclassification_seq'), p_ticket_id, v_classification);
    END IF;

    v_details_private := 'Classified initial request: ' || v_classification_text;
    CALL tt.event_interface_addevent_new(v_event_id, p_ticket_id, 100021, NULL, NULL, v_details_private, p_contact_id, FALSE, statement_timestamp(), FALSE, p_zitadel_contact_id);
EXCEPTION
    WHEN OTHERS THEN
        CALL osag.osag_plog_err(c_prefix || 'Unexpected error: ' || SQLERRM);
        RETURN;
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- clear_todo_list (S-TICKET-048). Deletes ALL todo_item rows unconditionally; the
-- SELECT INTO site is reached only if p_add_history_event = 1 (the default). No
-- EXCEPTION block of its own.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.ticket_interface_clear_todo_list(
    p_ticket_id numeric, p_contact_id numeric, p_add_history_event numeric DEFAULT 1,
    p_zitadel_contact_id numeric DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_event_id numeric;
    v_event_type_id numeric;
    v_host_id numeric;
    v_company_id numeric;
    v_private_details varchar;
BEGIN
    DELETE FROM tt.todo_item WHERE ticket_id = p_ticket_id;

    IF (p_add_history_event = 1) THEN
        -- Add a "todo list cleared" history event (ID 100013)
        v_event_type_id := 100013;

        -- S-TICKET-048 (site #68): STRICT, unhandled -- clear_todo_list has no
        -- EXCEPTION block of its own. If p_add_history_event = 0, this SELECT INTO
        -- never executes at all -- a bad p_ticket_id in that mode still succeeds in
        -- deleting zero todo items and resetting the step counters. "no data found"
        -- message-parity shim (XCUT-01, same rationale as
        -- update_ux_timeout_for_ticket's site #18 above) -- required for regress golden
        -- parity (migration/test/regress/expected/tt__ticket_interface__errors.out).
        BEGIN
            SELECT t.host_id, t.company_id
            INTO STRICT v_host_id, v_company_id
            FROM tt.ticket t
            WHERE id = p_ticket_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE EXCEPTION 'no data found' USING ERRCODE = 'P0002';
        END;

        v_private_details := 'Todo list cleared';
        CALL tt.event_interface_add_history_event(v_event_id,
            p_ticket_id,
            v_event_type_id,
            v_host_id,
            v_company_id,
            NULL,
            v_private_details,
            FALSE,
            statement_timestamp(),
            p_contact_id,
            p_zitadel_contact_id);
    END IF;

    -- set step count of ticket to 0
    UPDATE tt.ticket
    SET steps_total = 0, steps_completed = 0
    WHERE id = p_ticket_id;
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- add_todo_item (S-TICKET-049). Per its own doc comment, deliberately does NOT write a
-- history event itself -- callers batch multiple calls under one shared history event.
-- No EXCEPTION block.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.ticket_interface_add_todo_item(
    OUT p_todo_item_id numeric,
    p_ticket_id numeric,
    p_seq_no numeric,
    p_details varchar,
    p_todo_item_status_id numeric,
    p_contact_id numeric,
    p_todo_item_is_public numeric DEFAULT 0,
    p_zitadel_contact_id numeric DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
BEGIN
    -- S-TICKET-049 (site #69): sequence pull, no STRICT concern.
    SELECT nextval('tt.todoitem_seq') INTO STRICT p_todo_item_id;

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

        UPDATE tt.ticket
        SET todo_relevant_events_count = 0
        WHERE id = p_ticket_id;
    END IF;
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- update_todo_item_status (S-TICKET-050). No EXCEPTION block anywhere -- all three sites
-- propagate fully unhandled.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.ticket_interface_update_todo_item_status(
    p_ticket_id numeric,
    p_seq_no numeric,
    p_todo_item_status_id numeric,
    p_contact_id numeric,
    p_zitadel_contact_id numeric DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_event_id numeric;
    v_event_type_id numeric;
    v_host_id numeric;
    v_company_id numeric;
    v_private_details varchar;
    v_public_details varchar;
    v_status_name varchar;
    v_old_status_name varchar;
    v_old_status_id numeric;
    v_details varchar;
    v_is_public numeric;
    v_is_public_bool boolean;
BEGIN
    -- S-TICKET-050 (site #70): STRICT, unhandled. The LEFT JOIN means zero rows here
    -- specifically means "no todo item row at all for this (ticket_id, seq_no) pair".
    SELECT tis.name, ti.details, ti.is_public, tis.id
    INTO STRICT v_old_status_name, v_details, v_is_public, v_old_status_id
    FROM tt.todo_item ti LEFT JOIN tt.todo_item_status tis ON (ti.todo_item_status_id = tis.id)
    WHERE ti.ticket_id = p_ticket_id AND ti.seq_no = p_seq_no;

    UPDATE tt.todo_item
    SET todo_item_status_id = p_todo_item_status_id
    WHERE ticket_id = p_ticket_id AND seq_no = p_seq_no;

    -- Add a "todo item updated" history event (ID 100015)
    v_event_type_id := 100015;

    -- S-TICKET-050 (site #71): STRICT, unhandled.
    SELECT t.host_id, t.company_id
    INTO STRICT v_host_id, v_company_id
    FROM tt.ticket t
    WHERE id = p_ticket_id;

    -- S-TICKET-050 (site #72): STRICT, unhandled.
    SELECT tis.name
    INTO STRICT v_status_name
    FROM tt.todo_item_status tis
    WHERE tis.id = p_todo_item_status_id;

    IF (v_is_public = 1) THEN
        v_public_details := 'New status of todo item (was: ' || v_old_status_name || '):' || chr(13)
            || v_status_name || ' ' || v_details;
        v_private_details := NULL;
        v_is_public_bool := TRUE;

        -- adjust steps_completed
        IF (v_old_status_id IN (1, 3) AND p_todo_item_status_id IN (2, 4)) THEN
            -- if a public todo item changed from (todo or active) to (done or skipped)
            -- increase steps_completed
            UPDATE tt.ticket
            SET steps_completed = steps_completed + 1
            WHERE id = p_ticket_id;
        ELSIF (v_old_status_id IN (2, 4) AND p_todo_item_status_id IN (1, 3)) THEN
            -- if a public todo item changed from (done or skipped) to (todo or active)
            -- decrease steps_completed
            UPDATE tt.ticket
            SET steps_completed = steps_completed - 1
            WHERE id = p_ticket_id;
        END IF;

        UPDATE tt.ticket
        SET todo_relevant_events_count = 0
        WHERE id = p_ticket_id;
    ELSE
        v_public_details := NULL;
        v_private_details := 'New status of todo item ' || (p_seq_no + 1) || ' (was: ' || v_old_status_name || '):' || chr(13)
            || v_status_name || ' ' || v_details;
        v_is_public_bool := FALSE;
    END IF;

    CALL tt.event_interface_add_history_event(v_event_id,
        p_ticket_id,
        v_event_type_id,
        v_host_id,
        v_company_id,
        v_public_details,
        v_private_details,
        v_is_public_bool,
        statement_timestamp(),
        p_contact_id,
        p_zitadel_contact_id);
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- updateTicketFlow (S-TICKET-051, S-TICKET-056). Called by every routine that changes
-- status/type/worker (see S-TICKET-056). No EXCEPTION block of its own -- site #77
-- propagates fully unhandled, unlike site #76's local NO_DATA_FOUND handler.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.ticket_interface_updateticketflow(
    p_ticket_id numeric, p_prev_status_id numeric DEFAULT NULL, p_prev_status_change_date timestamptz DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_status_id numeric;
    v_mcc_flag numeric;
    v_ticket_type_id numeric;
    v_flow_id numeric;
    v_last_status_change_date timestamp;
    v_flow_in_date timestamp;
    v_status_time numeric;
BEGIN
    -- check if we have a flow entry in the queue for the ticket
    BEGIN
        -- S-TICKET-051 (site #76): STRICT + local NO_DATA_FOUND handler -- zero rows (no
        -- open flow entry) is the EXPECTED common case for a ticket not currently in the
        -- MCC queue, not an error.
        SELECT tf.id, tf.flow_in_date INTO STRICT v_flow_id, v_flow_in_date FROM tt.ticket_flow tf WHERE ticket_id = p_ticket_id AND flow_out_date IS NULL;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_flow_id := NULL;
    END;

    -- check if the ticket should be in the MCC queue -- get required data.
    -- S-TICKET-051 (site #77): STRICT, unhandled -- updateTicketFlow has no
    -- procedure-level EXCEPTION block.
    SELECT t.handled_by_mcc, t.type_id, t.status_id, t.last_status_change_date
    INTO STRICT v_mcc_flag, v_ticket_type_id, v_status_id, v_last_status_change_date
    FROM tt.ticket t WHERE t.id = p_ticket_id;

    -- if the ticket is MCC responsibility and the status is in progress, the ticket
    -- should be in the queue
    IF (v_flow_id IS NULL
        AND (v_status_id IN (1, 2, 3, 4))
        AND (v_ticket_type_id NOT IN (4, 5))
        AND (v_mcc_flag = 1)) THEN

        -- put ticket in
        INSERT INTO tt.ticket_flow (id, ticket_id, flow_in_date, open_time) VALUES (nextval('tt.ticketflow_seq'), p_ticket_id, statement_timestamp(), 0);

    ELSIF (v_flow_id IS NOT NULL
        AND
           (v_status_id NOT IN (1, 2, 3, 4)
               OR v_ticket_type_id IN (4, 5)
               OR v_mcc_flag = 0)
        ) THEN

        -- take ticket out
        UPDATE tt.ticket_flow SET flow_out_date = statement_timestamp() WHERE id = v_flow_id;

        -- update flow relevant open time if the status is still open
        IF v_status_id = 2 THEN
            v_status_time := extract(epoch FROM (statement_timestamp()::timestamp - GREATEST(v_flow_in_date, v_last_status_change_date)));
            UPDATE tt.ticket_flow SET open_time = open_time + v_status_time WHERE id = v_flow_id;
            -- update flow relevant open time if status change was reason for queue exit
        ELSIF (p_prev_status_id = 2) THEN
            v_status_time := extract(epoch FROM (statement_timestamp()::timestamp - GREATEST(v_flow_in_date, p_prev_status_change_date::timestamp)));
            UPDATE tt.ticket_flow SET open_time = open_time + v_status_time WHERE id = v_flow_id;
        END IF;

        -- only open time change iff ticket was open before, but is no longer
    ELSIF (v_flow_id IS NOT NULL AND p_prev_status_id = 2 AND v_status_id != 2) THEN
        v_status_time := extract(epoch FROM (statement_timestamp()::timestamp - GREATEST(v_flow_in_date, p_prev_status_change_date::timestamp)));
        UPDATE tt.ticket_flow SET open_time = open_time + v_status_time WHERE id = v_flow_id;
    END IF;
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- deleteTicket (S-TICKET-052). The precise cascade enumeration, in the exact statement
-- order Oracle executes them (31 statements total). No SELECT INTO anywhere. No
-- EXCEPTION block at all -- a constraint violation partway through propagates fully
-- unhandled, leaving whatever statements already ran committed-pending in the CALLER's
-- transaction (no COMMIT anywhere in this package).
--
-- fw.change is referenced by the very last-but-one DELETE below -- see the schema-fix
-- note in this file's header (migration/test/schema-fixes/24_p12_fixes.sql adds the
-- table, missing from ddl/migrated/ entirely despite existing in the Oracle export).
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.ticket_interface_deleteticket(p_ticket_id numeric)
LANGUAGE plpgsql
AS $fn$
BEGIN
    UPDATE prx.prx_policy_item SET ticket_id = NULL WHERE ticket_id = p_ticket_id;
    UPDATE tt.ticket SET merged_into_ticket_id = NULL WHERE merged_into_ticket_id = p_ticket_id;
    UPDATE tt.ticket SET last_public_event_id = NULL WHERE ticket.id = p_ticket_id;
    UPDATE tt.ticket SET customer_ticket_rating_id = NULL WHERE ticket.id IN (SELECT id FROM tt.ticket_rating WHERE event_id IN (SELECT id FROM tt.event WHERE ticket_id = p_ticket_id));
    UPDATE tt.ticket SET engineer_ticket_rating_id = NULL WHERE ticket.id IN (SELECT id FROM tt.ticket_rating WHERE event_id IN (SELECT id FROM tt.event WHERE ticket_id = p_ticket_id));
    UPDATE tt.ticket SET customer_ticket_rating_id = NULL WHERE customer_ticket_rating_id IN (SELECT id FROM tt.ticket_rating WHERE event_id IN (SELECT id FROM tt.event WHERE ticket_id = p_ticket_id));
    UPDATE tt.ticket SET engineer_ticket_rating_id = NULL WHERE engineer_ticket_rating_id IN (SELECT id FROM tt.ticket_rating WHERE event_id IN (SELECT id FROM tt.event WHERE ticket_id = p_ticket_id));
    UPDATE mcaudit.record SET ticket_id = NULL WHERE ticket_id = p_ticket_id;
    DELETE FROM tt.ticket_docs_page WHERE ticket_id = p_ticket_id;
    DELETE FROM tt.ticket_flow WHERE ticket_id = p_ticket_id;
    DELETE FROM tt.ticket2related_ticket WHERE ticket_id = p_ticket_id;
    DELETE FROM tt.ticket2related_ticket WHERE related_ticket_id = p_ticket_id;
    DELETE FROM tt.attachment WHERE ticket_id = p_ticket_id;
    UPDATE mc.isp_link_history SET event_id = NULL WHERE event_id IN (SELECT id FROM tt.event WHERE ticket_id = p_ticket_id);
    DELETE FROM tt.ticket_time_statistic WHERE ticket_id = p_ticket_id;
    UPDATE mss.installation_project_item SET ticket_id = NULL WHERE ticket_id = p_ticket_id;
    DELETE FROM guma2.suppressed_signature WHERE ticket_id = p_ticket_id;
    UPDATE mc.isp_link_maintenance_history SET ticket_id = NULL WHERE ticket_id = p_ticket_id;
    UPDATE mc.host_maintenance_history SET ticket_id = NULL WHERE ticket_id = p_ticket_id;
    DELETE FROM nids.ticket2rule WHERE ticket_id = p_ticket_id;
    DELETE FROM fw.rule2ticket WHERE ticket_id = p_ticket_id;
    DELETE FROM fw.source_nat_rule2ticket WHERE ticket_id = p_ticket_id;
    DELETE FROM fw.destination_nat_rule2ticket WHERE ticket_id = p_ticket_id;
    DELETE FROM tt.ticket2mc_file WHERE ticket_id = p_ticket_id;
    DELETE FROM tt.ticket_rating WHERE event_id IN (SELECT id FROM tt.event WHERE ticket_id = p_ticket_id);
    DELETE FROM tt.ticket_rating WHERE id IN (SELECT t.customer_ticket_rating_id FROM tt.ticket t WHERE t.id = p_ticket_id);
    DELETE FROM tt.ticket_rating WHERE id IN (SELECT t.engineer_ticket_rating_id FROM tt.ticket t WHERE t.id = p_ticket_id);
    DELETE FROM tt.event WHERE ticket_id = p_ticket_id;
    DELETE FROM tt.maintenance_window WHERE service_window_id IN (SELECT sw.id FROM tt.service_window sw WHERE ticket_id = p_ticket_id);
    DELETE FROM tt.cust_maintenance_window WHERE service_window_id IN (SELECT sw.id FROM tt.service_window sw WHERE ticket_id = p_ticket_id);
    DELETE FROM tt.host2service_window WHERE service_window_id IN (SELECT sw.id FROM tt.service_window sw WHERE ticket_id = p_ticket_id);
    DELETE FROM mss.deleted_host2service_window WHERE service_window_id IN (SELECT sw.id FROM tt.service_window sw WHERE ticket_id = p_ticket_id);
    DELETE FROM tt.service_window WHERE ticket_id = p_ticket_id;
    DELETE FROM tt.event_notification WHERE ticket_id = p_ticket_id;
    DELETE FROM tt.todo_item WHERE ticket_id = p_ticket_id;
    DELETE FROM tt.ticket_request_classification WHERE ticket_id = p_ticket_id;
    DELETE FROM tt.change_request WHERE ticket_id = p_ticket_id;
    DELETE FROM fw.change WHERE ticket_id = p_ticket_id;
    DELETE FROM tt.ticket WHERE id = p_ticket_id;
END;
$fn$;
