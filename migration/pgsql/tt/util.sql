-- migration/pgsql/tt/util.sql
--
-- Translation of TT.UTIL (spec: migration/spec/tt.util.md; Oracle body:
-- ddl/src/pkgb/tt_util.sql, 248 lines). Names copied verbatim from
-- migration/mapping/name-map.csv's 5 TT.UTIL rows; the private helper
-- despam_ticket has no name-map row (not a public routine) and follows the
-- double-underscore private-routine convention plan 02-05 established for
-- TT.OSAG_NOTIFY (tt.util__despam_ticket, REVOKE ALL ... FROM PUBLIC).
--
-- Oracle's usage-audit call (package-state tracking, XCUT-06): all 6 call sites
-- (one per routine, including the private helper) deleted, not ported. See
-- util.FINDINGS.md.
--
-- All 5 public routines are PostgreSQL PROCEDUREs, matching pg_kind in name-map.csv --
-- see util.FINDINGS.md for the full FUNCTION-vs-COMMIT trace this package forces
-- (the pilot's primary XCUT-04/XCUT-05 evidence).
--
-- This package's callees (tt.ticket_interface_change_status,
-- tt.ticket_interface_expire_status, tt.osag_notify_delete_ticket_notifications) belong
-- to TT.TICKET_INTERFACE / TT.OSAG_NOTIFY -- the TT cycle-group siblings this same wave
-- lands in plans 02-10/02-11/02-12. PL/pgSQL does not resolve CALL targets at CREATE
-- time, so this file loads regardless of load order; only *running* check_resolved_tickets,
-- check_ticket_status, check_dnids_tickets_to_resolve, or close_old_dev_tickets requires
-- those siblings to exist first. update_status_valid_until (the one routine with a direct,
-- non-scheduled caller today, S-UTIL-015) calls none of them and is independently testable
-- now -- see util.FINDINGS.md for the full red/green breakdown.
--
-- "no data found" message-parity shim (see auth/osag_auth.sql's header for the full
-- rationale): update_status_valid_until's one genuinely-unhandled NO_DATA_FOUND site
-- gets the same transparent message-only correction, matching this package's own spec
-- note that PL/pgSQL's default STRICT SQLSTATE (P0002) must propagate to callers "exactly
-- as Oracle's unhandled ORA-01403 does today".

-- ------------------------------------------------------------------------------------
-- check_resolved_tickets (S-UTIL-001): cursor FOR loop, not SELECT INTO -- zero matches
-- is a normal empty loop, never an exception.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.util_check_resolved_tickets()
LANGUAGE plpgsql
AS $fn$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT t.id
        FROM tt.ticket t
        WHERE t.status_id = 101
          AND t.last_resolved_date <= statement_timestamp() - interval '14 days'
    LOOP
        CALL tt.ticket_interface_change_status(r.id, 102, NULL, 'ticket resolved for more than 2 weeks, closing it automatically');
        UPDATE tt.ticket SET close_date = statement_timestamp() WHERE id = r.id;
        CALL tt.osag_notify_delete_ticket_notifications(r.id);
    END LOOP;
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- check_ticket_status (S-UTIL-002): cursor FOR loop, same "empty loop, no exception"
-- pattern. c_prefix in the Oracle source is declared but never referenced (dead code,
-- confirmed by the spec) -- not carried into the translation.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.util_check_ticket_status()
LANGUAGE plpgsql
AS $fn$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT t.id AS t_id,
               t.status_valid_until_date AS t_valid_until,
               s.name AS s_name,
               t.last_status_change_date AS t_last_change,
               t.status_id AS t_status_id,
               t.label_id AS label_id
        FROM tt.ticket t, tt.status s
        WHERE t.status_id = s.id
          AND t.status_id IN (11, 12, 60, 61)
          AND t.status_valid_until_date < statement_timestamp()
    LOOP
        CALL tt.ticket_interface_expire_status(r.t_id, r.t_valid_until, r.t_last_change, r.t_status_id, r.s_name, r.label_id);
    END LOOP;
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- update_status_valid_until (S-UTIL-003..007): the ONE routine with a direct,
-- non-scheduled caller today (S-UTIL-015). Zero exception handlers in the Oracle source
-- except this package's total absence of any -- the one SELECT INTO site (S-UTIL-003)
-- is genuinely unhandled in Oracle; the "no data found" shim (file header) preserves
-- that propagation while matching the pinned test substring.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.util_update_status_valid_until(p_ticket_id numeric, p_valid_until_date timestamp DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
DECLARE
    l_type_id numeric;
    l_status_id numeric;
    l_emergency numeric;
    l_handled_by_mcc numeric;
    v_period_to_add numeric := 0;
    v_valid_until_date timestamp := NULL;
BEGIN
    BEGIN
        SELECT type_id, status_id, emergency, handled_by_mcc
          INTO STRICT l_type_id, l_status_id, l_emergency, l_handled_by_mcc
        FROM tt.ticket
        WHERE id = p_ticket_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE EXCEPTION 'no data found' USING ERRCODE = 'P0002';
    END;

    -- S-UTIL-004: deferred (60) is handled elsewhere -- immediate no-op return.
    IF l_status_id = 60 THEN
        RETURN;
    END IF;

    -- S-UTIL-005: waiting/third-party/waiting-for-signoff. Emergency default +4h
    -- (v_period_4h = 1/6 day), capped at +1d if an explicit valid-until date falls
    -- within that window; non-emergency default +20d, capped at +60d, same condition.
    IF l_status_id IN (11, 12, 61) THEN
        IF l_emergency = 1 THEN
            IF p_valid_until_date IS NOT NULL
               AND p_valid_until_date > statement_timestamp()
               AND p_valid_until_date - statement_timestamp() <= interval '1 day' THEN
                v_valid_until_date := p_valid_until_date;
                v_period_to_add := 0;
            ELSE
                v_period_to_add := 1.0 / 6;  -- 4h, matches Oracle's v_period_4h
            END IF;
        ELSE
            IF p_valid_until_date IS NOT NULL
               AND p_valid_until_date > statement_timestamp()
               AND p_valid_until_date - statement_timestamp() <= interval '60 days' THEN
                v_valid_until_date := p_valid_until_date;
                v_period_to_add := 0;
            ELSE
                v_period_to_add := 20;  -- 20d, matches Oracle's v_period_20d
            END IF;
        END IF;
    END IF;

    -- S-UTIL-006: ALWAYS writes status_valid_until_date -- the computed offset, the
    -- caller-supplied date verbatim, or (for every OTHER status) an explicit reset to
    -- NULL -- deliberate per the Oracle source's own inline comment.
    IF v_period_to_add > 0 THEN
        UPDATE tt.ticket SET status_valid_until_date = statement_timestamp() + (v_period_to_add * interval '1 day') WHERE id = p_ticket_id;
    ELSIF v_valid_until_date IS NOT NULL THEN
        UPDATE tt.ticket SET status_valid_until_date = v_valid_until_date WHERE id = p_ticket_id;
    ELSE
        UPDATE tt.ticket SET status_valid_until_date = NULL WHERE id = p_ticket_id;
    END IF;

    -- S-UTIL-007: waiting-family statuses ALSO unconditionally overwrite
    -- last_deferral_date with p_valid_until_date (NULL for the 1-arg form).
    IF l_status_id IN (11, 12, 61) THEN
        UPDATE tt.ticket SET last_deferral_date = p_valid_until_date WHERE id = p_ticket_id;
    END IF;
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- check_dnids_tickets_to_resolve (S-UTIL-008): cursor FOR loop, same "empty loop, no
-- exception" pattern. oracle.regexp_instr (orafce) is a genuine, mechanical fit for
-- Oracle's REGEXP_INSTR(text, pattern, position, occurrence, return_opt, modifiers).
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.util_check_dnids_tickets_to_resolve()
LANGUAGE plpgsql
AS $fn$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT t.id
        FROM tt.ticket t, tt.event e
        WHERE (statement_timestamp() - e.eventdate > interval '7 days'
               OR oracle.regexp_instr(e.details_public, '^DNIDS:SCAN:INFO:ALLCLEAN', 1, 1, 0, 'im')
                  + oracle.regexp_instr(e.details_public, '^DNIPS:SLOWDOWN:ALLCLEAN', 1, 1, 0, 'im') > 0)
          AND e.id = t.last_public_event_id
          AND t.type_id = 5
          AND t.status_id < 101
          AND e.type_id = 10020
    LOOP
        CALL tt.ticket_interface_change_status(r.id, 101, NULL, 'Automatically resolving ticket.');
    END LOOP;
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- despam_ticket (S-UTIL-009): PRIVATE -- no name-map.csv row of its own. Double-
-- underscore naming convention + REVOKE ALL, per plan 02-05's TT.OSAG_NOTIFY precedent.
-- Its own SELECT MIN/MAX INTO is an aggregate, always exactly one row -- STRICT, no
-- handler needed.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.util__despam_ticket(p_ticket_id numeric, p_limit numeric DEFAULT 1000)
LANGUAGE plpgsql
AS $fn$
DECLARE
    t RECORD;
    v_min numeric;
    v_max numeric;
BEGIN
    FOR t IN
        SELECT e.type_id, count(*) AS cnt
        FROM tt.event e
        WHERE e.ticket_id = p_ticket_id
        GROUP BY e.type_id
        HAVING count(*) > p_limit
    LOOP
        SELECT min(e.id), max(e.id) INTO STRICT v_min, v_max
        FROM tt.event e
        WHERE e.ticket_id = p_ticket_id AND e.type_id = t.type_id;

        DELETE FROM tt.event e
        WHERE e.ticket_id = p_ticket_id
          AND e.type_id = t.type_id
          AND e.id != (SELECT tk.last_public_event_id FROM tt.ticket tk WHERE tk.id = e.ticket_id)
          AND e.id != v_min
          AND e.id != v_max
          AND NOT EXISTS (SELECT 1 FROM mc.isp_link_history lh WHERE lh.event_id = e.id);
    END LOOP;
END;
$fn$;
REVOKE ALL ON PROCEDURE tt.util__despam_ticket(numeric, numeric) FROM PUBLIC;

-- ------------------------------------------------------------------------------------
-- close_old_dev_tickets (S-UTIL-010..014): the pilot's COMMIT/PRAGMA
-- AUTONOMOUS_TRANSACTION collision. Translated as a PLAIN PROCEDURE with a REAL COMMIT
-- per iteration (util.FINDINGS.md Checklist dimension 5, option 1) -- accepting the
-- semantic delta from Oracle's true autonomous-transaction isolation. XCUT-05 owns the
-- final decision; this is Phase 2's deliberate, documented placeholder, matching
-- migration/spec/tt.util.md's own "Assumptions / Unresolved" section verbatim.
--
-- V$INSTANCE (S-UTIL-011) has no PostgreSQL equivalent. DECISION (Q7, 2026-10-16,
-- phoenix/migrate_tt_only): an instance identifies its role through the GUC
-- `mcdb.instance_role` ('dev' | 'test' | 'prod'), set per database with
-- `ALTER DATABASE <db> SET mcdb.instance_role = 'dev'` (survives restarts, is visible to
-- every session, needs no table and no naming convention). Oracle's `HOST_NAME LIKE
-- '%-dev-%'` test becomes `current_setting('mcdb.instance_role', true) = 'dev'`. The
-- older test-only GUC `mcdb.force_dev_instance = 'true'` (set by
-- migration/test/regress/sql/tt__util__txn.sql) is still honoured so the locked regress
-- fixture keeps working; it is a session-level override, not the production mechanism.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.util_close_old_dev_tickets()
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_is_dev integer;
    r RECORD;
BEGIN
    SELECT count(*) INTO STRICT v_is_dev
    FROM (SELECT 1
          WHERE current_setting('mcdb.instance_role', true) = 'dev'
             OR current_setting('mcdb.force_dev_instance', true) = 'true') dev_check;

    IF v_is_dev = 0 THEN
        -- not a dev instance, nothing to do
        ROLLBACK;
        RETURN;
    END IF;

    FOR r IN
        SELECT t.id
        FROM tt.ticket t
        WHERE t.handled_by_mcc = 1
          AND t.status_id NOT IN (2, 102)  -- 2 open, 102 closed
          AND t.status_id < 100            -- merged, archived, deleted, etc.
          AND t.open_date < (statement_timestamp() - interval '30 days')
    LOOP
        CALL tt.ticket_interface_change_status(r.id, 102, NULL, 'Automatically closed after 30 days');
        COMMIT;
    END LOOP;

    FOR r IN
        SELECT e.ticket_id, count(*) AS cnt
        FROM tt.event e
        GROUP BY e.ticket_id
        HAVING count(*) > 5000
        ORDER BY e.ticket_id DESC
    LOOP
        CALL tt.util__despam_ticket(r.ticket_id, 100);
        COMMIT;
    END LOOP;
END;
$fn$;
