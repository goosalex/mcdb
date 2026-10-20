-- migration/pgsql/mc/osag_maintsync.sql
--
-- Translation of MC.OSAG_MAINTSYNC (spec: migration/spec/mc.osag_maintsync.md; Oracle body:
-- ddl/src/pkgb/mc_osag_maintsync.sql, 319 lines). Names copied verbatim from
-- migration/mapping/name-map.csv's 4 OSAG_MAINTSYNC rows (all pg_kind=procedure). No private
-- routines, no package state, no *_STATE companion.
--
-- Oracle's usage-audit call (XCUT-06): all 4 plog.AuditUsage sites (lines 54, 141, 187, 250
-- -- one per routine) DELETED, not ported. See osag_maintsync.FINDINGS.md.
--
-- Oracle NUMBER -> the %TYPE-anchored column types (bigint ids), SYSTIMESTAMP ->
-- statement_timestamp(), NVL -> coalesce, seq.nextval -> nextval('mc.<seq>'), `(+)` -> LEFT
-- JOIN, comma-joins -> explicit JOINs, cursor FOR loops -> FOR r IN <query> LOOP, FOR UPDATE OF
-- <table>.<column> -> FOR UPDATE OF <alias> (S-MAINT-021), plog.<level>() ->
-- CALL osag.osag_plog_<level>(). Every SELECT INTO is STRICT and carries the clause id of
-- the spec's strictness table row.
--
-- THE FIVE-TABLE MAINTENANCE-WINDOW JOIN (S-MAINT-002) IS WRITTEN OUT FOUR TIMES, exactly as
-- in Oracle (body lines 28-44, 95-115, 198-214, 262-282). Deliberately NOT factored into a
-- shared view in this plan (instruction: translate the join faithfully); recorded as a
-- follow-up in osag_maintsync.FINDINGS.md.
--
-- FOUR DELIBERATE DEVIATIONS FROM ORACLE, all in the two single-entity routines, all marked
-- `-- DEVIATION(ORACLE-BUG)` at the site and specified as corrected behaviour in the spec
-- (project-owner instruction: do not mimic broken Oracle behaviour, annotate the correction):
--   * update_single_host (S-MAINT-012): Oracle's SELECT INTO copies the batch cursor's
--     "a change is needed" filter into its WHERE clause (217-220), so the normal nothing-to-do
--     case raised NO_DATA_FOUND and was logged as an ERROR, and the IF at 222 was dead code.
--     The filter is dropped; the IF decides.
--   * update_single_isp_link (S-MAINT-016): the status query had NO `l.id = p_isp_link_id`
--     predicate (286) -- it ranged over every changed link in the database. Added.
--   * update_single_isp_link (S-MAINT-017): same copied filter (288-294) + a NO_DATA_FOUND
--     handler that assumes "no row" means "no interface" -> an up-to-date attached link was
--     flipped to 1 (unknown) and flip-flopped on every call. The filter is dropped; the IF at
--     304 decides, which is exactly the batch routine's selection logic.
--   * update_single_isp_link (S-MAINT-018): `l.maintenance_status_id = NULL` (288), never
--     true. Disappears with the filter.
-- Everything else -- including the two batch routines -- is Oracle-faithful.
--
-- NULL concatenation (Pitfall 2 / spec Checklist 1): the one `||` site with a nullable
-- operand is update_isp_link_maint_status's plog.notice (146-148, maintenance_status_old
-- can be NULL) -> concat(), which has Oracle's NULL-as-empty semantics (S-MAINT-008).
--
-- Transaction-scope delta (XCUT-05, recorded in FINDINGS): each routine's WHEN OTHERS
-- handler is a PL/pgSQL subtransaction, so a failure in loop iteration N also rolls back
-- iterations 1..N-1 of the same call (Oracle kept them). The next minute's job run redoes
-- them; the steady state is identical.

-- ------------------------------------------------------------------------------------
-- update_host_maint_status (S-MAINT-002..006, S-MAINT-021): every host (OS <> 21) whose
-- derived maintenance status differs from the stored one gets a history row + update.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE mc.osag_maintsync_update_host_maint_status()
LANGUAGE plpgsql
AS $fn$
DECLARE
    s_prefix CONSTANT varchar := 'update_host_maint_status(): ';
    r_maint_status_changed RECORD;
BEGIN
    -- select all hosts with their maintenance status (newly calculated and current one)
    -- that have a change between calculated and current or none assigned yet
    FOR r_maint_status_changed IN
        -- maintenance status calculation (S-MAINT-003)
        SELECT h.id AS host_id,
               CASE WHEN h.active = 0 THEN 3
                    WHEN sw.ticket_id IS NULL THEN 2
                    ELSE 4
               END AS maintenance_status_new,
               h.maintenance_status_id AS maintenance_status_old,
               sw.ticket_id AS ticket_id
        FROM mss.host h
             -- subquery to include currently open service windows (latest ticket is taken)
             -- (S-MAINT-002, copy 1 of 4)
             LEFT JOIN (SELECT max(t.id) AS ticket_id, h2s.host_id
                        FROM tt.ticket t
                             INNER JOIN tt.service_window s ON (s.ticket_id = t.id)
                             INNER JOIN tt.host2service_window h2s ON (h2s.service_window_id = s.id)
                             LEFT JOIN tt.maintenance_window m ON (s.id = m.service_window_id)
                             LEFT JOIN tt.cust_maintenance_window cm ON (s.id = cm.service_window_id)
                        WHERE t.status_id < 101
                          AND s.end_date > statement_timestamp()
                          AND s.start_date < statement_timestamp()
                          AND (m.disable_conn_escalation = 1 OR m.disable_events = 1
                               OR cm.disable_conn_escalation = 1 OR cm.disable_events = 1)
                        GROUP BY h2s.host_id) sw ON h.id = sw.host_id
        -- S-MAINT-004: which hosts need a change
        WHERE h.operating_system_id <> 21
          AND (h.maintenance_status_id IS NULL OR
               (h.active = 0 AND h.maintenance_status_id <> 3) OR
               (sw.ticket_id IS NULL AND h.active = 1 AND h.maintenance_status_id <> 2) OR
               (sw.ticket_id IS NOT NULL AND h.active = 1 AND h.maintenance_status_id <> 4))
        FOR UPDATE OF h   -- S-MAINT-021 (Oracle: FOR UPDATE OF h.maintenance_status_id)
    LOOP
        -- S-MAINT-005
        INSERT INTO mc.host_maintenance_history
            (id, host_id, change_date, new_maintenance_status_id, old_maintenance_status_id, ticket_id)
        VALUES (nextval('mc.host_maint_history_seq'), r_maint_status_changed.host_id, statement_timestamp(),
                r_maint_status_changed.maintenance_status_new,
                coalesce(r_maint_status_changed.maintenance_status_old, 1), r_maint_status_changed.ticket_id);

        UPDATE mss.host h SET maintenance_status_id = r_maint_status_changed.maintenance_status_new
        WHERE h.id = r_maint_status_changed.host_id;
    END LOOP;

EXCEPTION
    WHEN OTHERS THEN
        -- S-MAINT-006: log and swallow (SQLERRM text is PostgreSQL's, prefix is Oracle's)
        CALL osag.osag_plog_err(s_prefix || 'caught exception: ' || SQLERRM);
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- update_isp_link_maint_status (S-MAINT-007..010, S-MAINT-021): loop 1 -- attached links
-- whose derived status differs; loop 2 -- unattached links reset to 1 (unknown).
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE mc.osag_maintsync_update_isp_link_maint_status()
LANGUAGE plpgsql
AS $fn$
DECLARE
    s_prefix CONSTANT varchar := 'update_isp_link_maint_status(): ';
    r_maint_status_changed RECORD;
    r_maint_status_obsolete RECORD;
BEGIN
    -- select all isp links that are associated with an interface with their maintenance
    -- status (newly calculated and current one) that have a change between calculated and
    -- current or none assigned yet
    FOR r_maint_status_changed IN
        -- maintenance status calculation (S-MAINT-003)
        SELECT l.id AS isp_link_id,
               CASE WHEN hosts.host_active = 0 THEN 3
                    WHEN sw.ticket_id IS NULL THEN 2
                    ELSE 4
               END AS maintenance_status_new,
               l.maintenance_status_id AS maintenance_status_old,
               sw.ticket_id AS ticket_id
        FROM mss.isp_link l
             -- get a linked host that is active, if possible (S-MAINT-007: inner join -> attached links only)
             INNER JOIN (SELECT max(h.active) AS host_active, i2l_a.isp_link_id AS isp_link_id
                         FROM mss.host h
                              INNER JOIN mss.interface i_a ON (h.id = i_a.host_id)
                              INNER JOIN mss.interface2isp_link i2l_a ON (i2l_a.interface_id = i_a.id)
                         GROUP BY i2l_a.isp_link_id) hosts ON l.id = hosts.isp_link_id
             -- get the service window of the latest ticket over all linked hosts
             -- (S-MAINT-002, copy 2 of 4)
             LEFT JOIN (SELECT max(t.id) AS ticket_id, i2l.isp_link_id
                        FROM tt.ticket t
                             INNER JOIN tt.service_window s ON (s.ticket_id = t.id)
                             INNER JOIN tt.host2service_window h2s ON (h2s.service_window_id = s.id)
                             INNER JOIN mss.interface i ON (h2s.host_id = i.host_id)
                             INNER JOIN mss.interface2isp_link i2l ON (i.id = i2l.interface_id)
                             LEFT JOIN tt.maintenance_window m ON (s.id = m.service_window_id)
                             LEFT JOIN tt.cust_maintenance_window cm ON (s.id = cm.service_window_id)
                        WHERE t.status_id < 101
                          AND s.end_date > statement_timestamp()
                          AND s.start_date < statement_timestamp()
                          AND (m.disable_conn_escalation = 1 OR m.disable_events = 1
                               OR cm.disable_conn_escalation = 1 OR cm.disable_events = 1)
                        GROUP BY i2l.isp_link_id) sw ON l.id = sw.isp_link_id
        WHERE
            -- status is unknown or null
            (l.maintenance_status_id IS NULL OR l.maintenance_status_id = 1 OR
             -- now inactive, but not before
             (hosts.host_active = 0 AND l.maintenance_status_id <> 3) OR
             -- no service window now, active, but not active before
             (sw.ticket_id IS NULL AND hosts.host_active = 1 AND l.maintenance_status_id <> 2) OR
             -- a service window now, active, but not maintenance before
             (sw.ticket_id IS NOT NULL AND hosts.host_active = 1 AND l.maintenance_status_id <> 4))
        FOR UPDATE OF l   -- S-MAINT-021
    LOOP
        -- S-MAINT-008: concat() -- maintenance_status_old may be NULL, Oracle rendered it as ''
        CALL osag.osag_plog_notice(concat('updating status for link ', r_maint_status_changed.isp_link_id,
            ': new status is ', r_maint_status_changed.maintenance_status_new,
            ': old status is ', r_maint_status_changed.maintenance_status_old));

        INSERT INTO mc.isp_link_maintenance_history
            (id, isp_link_id, change_date, new_maintenance_status_id, old_maintenance_status_id, ticket_id)
        VALUES (nextval('mc.isp_link_maint_history_seq'), r_maint_status_changed.isp_link_id, statement_timestamp(),
                r_maint_status_changed.maintenance_status_new,
                coalesce(r_maint_status_changed.maintenance_status_old, 1), r_maint_status_changed.ticket_id);

        UPDATE mss.isp_link l SET maintenance_status_id = r_maint_status_changed.maintenance_status_new
        WHERE l.id = r_maint_status_changed.isp_link_id;
    END LOOP;

    -- S-MAINT-009: set previously assigned isp links maintenance status back to unknown
    FOR r_maint_status_obsolete IN
        SELECT l.id AS isp_link_id,
               l.maintenance_status_id AS maintenance_status_old
        FROM mss.isp_link l
        WHERE (l.maintenance_status_id <> 1 OR l.maintenance_status_id IS NULL)
          AND NOT EXISTS (SELECT 1 FROM mss.interface2isp_link i2l WHERE i2l.isp_link_id = l.id)
        FOR UPDATE OF l   -- S-MAINT-021
    LOOP
        INSERT INTO mc.isp_link_maintenance_history
            (id, isp_link_id, change_date, new_maintenance_status_id, old_maintenance_status_id)
        VALUES (nextval('mc.isp_link_maint_history_seq'), r_maint_status_obsolete.isp_link_id, statement_timestamp(),
                1, coalesce(r_maint_status_obsolete.maintenance_status_old, 1));

        UPDATE mss.isp_link l SET maintenance_status_id = 1
        WHERE l.id = r_maint_status_obsolete.isp_link_id;
    END LOOP;

EXCEPTION
    WHEN OTHERS THEN
        -- S-MAINT-010: log and swallow
        CALL osag.osag_plog_err(s_prefix || 'caught exception: ' || SQLERRM);
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- update_single_host (S-MAINT-011..013): derive one host's status; write iff it changed.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE mc.osag_maintsync_update_single_host(p_host_id mss.host.id%TYPE)
LANGUAGE plpgsql
AS $fn$
DECLARE
    s_prefix CONSTANT varchar := 'update_single_host(): ';
    v_current_status mc.maintenance_status.id%TYPE;
    v_old_status     mc.maintenance_status.id%TYPE;
    v_maint_ticket   tt.ticket.id%TYPE;
BEGIN
    -- S-MAINT-011 (strictness site #1): maintenance status calculation for exactly p_host_id.
    -- STRICT: a missing host or an OS-21 host yields no row -> NO_DATA_FOUND -> the WHEN
    -- OTHERS below, exactly as Oracle (S-MAINT-013).
    SELECT CASE WHEN h.active = 0 THEN 3
                WHEN sw.ticket_id IS NULL THEN 2
                ELSE 4
           END AS maintenance_status_new,
           h.maintenance_status_id AS maintenance_status_old,
           sw.ticket_id
    INTO STRICT v_current_status, v_old_status, v_maint_ticket
    FROM mss.host h
         -- subquery to include currently open service windows (latest ticket is taken)
         -- (S-MAINT-002, copy 3 of 4)
         LEFT JOIN (SELECT max(t.id) AS ticket_id, h2s.host_id
                    FROM tt.ticket t
                         INNER JOIN tt.service_window s ON (s.ticket_id = t.id)
                         INNER JOIN tt.host2service_window h2s ON (h2s.service_window_id = s.id)
                         LEFT JOIN tt.maintenance_window m ON (s.id = m.service_window_id)
                         LEFT JOIN tt.cust_maintenance_window cm ON (s.id = cm.service_window_id)
                    WHERE t.status_id < 101
                      AND s.end_date > statement_timestamp()
                      AND s.start_date < statement_timestamp()
                      AND (m.disable_conn_escalation = 1 OR m.disable_events = 1
                           OR cm.disable_conn_escalation = 1 OR cm.disable_events = 1)
                    GROUP BY h2s.host_id) sw ON h.id = sw.host_id
    WHERE h.id = p_host_id AND h.operating_system_id <> 21;
    -- DEVIATION(ORACLE-BUG) S-MAINT-012: Oracle (ddl/src/pkgb/mc_osag_maintsync.sql:217-220)
    -- ANDs the batch cursor's "a change is needed" filter onto this WHERE clause, so a host
    -- whose stored status already equals the derived one returns NO row, raises
    -- NO_DATA_FOUND and is logged as `update_single_host(): caught exception: ORA-01403: no
    -- data found` -- an ERROR for the normal nothing-to-do case -- while the IF below (Oracle
    -- line 222), written precisely to decide that, could never be false. The filter is
    -- dropped here; the IF decides. Missing host / OS 21 still raise (S-MAINT-013).

    IF (v_current_status <> v_old_status OR v_old_status IS NULL) THEN

        INSERT INTO mc.host_maintenance_history
            (id, host_id, change_date, new_maintenance_status_id, old_maintenance_status_id, ticket_id)
        VALUES (nextval('mc.host_maint_history_seq'), p_host_id, statement_timestamp(), v_current_status,
                coalesce(v_old_status, 1), v_maint_ticket);

        UPDATE mss.host h SET maintenance_status_id = v_current_status WHERE h.id = p_host_id;

    END IF;

EXCEPTION
    WHEN OTHERS THEN
        -- S-MAINT-013: log and swallow
        CALL osag.osag_plog_err(s_prefix || 'caught exception: ' || SQLERRM);
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- update_single_isp_link (S-MAINT-014..019): derive one link's status (1/unknown when it
-- is attached to no interface); write iff it changed.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE mc.osag_maintsync_update_single_isp_link(p_isp_link_id mss.isp_link.id%TYPE)
LANGUAGE plpgsql
AS $fn$
DECLARE
    s_prefix CONSTANT varchar := 'update_single_isp_link(): ';
    v_current_status mc.maintenance_status.id%TYPE;
    v_old_status     mc.maintenance_status.id%TYPE;
    v_maint_ticket   tt.ticket.id%TYPE;
BEGIN
    -- S-MAINT-014 (strictness site #2): stored status; a missing link -> NO_DATA_FOUND ->
    -- the WHEN OTHERS below, as Oracle.
    SELECT l.maintenance_status_id INTO STRICT v_old_status FROM mss.isp_link l WHERE l.id = p_isp_link_id;

    BEGIN
        -- S-MAINT-019 (strictness site #3): maintenance status calculation for exactly
        -- p_isp_link_id. Zero rows <=> the link is attached to no interface (inner join on
        -- `hosts`), handled below (S-MAINT-015); >1 row impossible (l.id is the PK, both
        -- derived tables are grouped by isp_link_id).
        SELECT CASE WHEN hosts.host_active = 0 THEN 3
                    WHEN sw.ticket_id IS NULL THEN 2
                    ELSE 4
               END AS maintenance_status_new,
               sw.ticket_id
        INTO STRICT v_current_status, v_maint_ticket
        FROM mss.isp_link l
             -- get a linked host that is active, if possible
             INNER JOIN (SELECT max(h.active) AS host_active, i2l_a.isp_link_id AS isp_link_id
                         FROM mss.host h
                              INNER JOIN mss.interface i_a ON (h.id = i_a.host_id)
                              INNER JOIN mss.interface2isp_link i2l_a ON (i2l_a.interface_id = i_a.id)
                         GROUP BY i2l_a.isp_link_id) hosts ON l.id = hosts.isp_link_id
             -- get the service window of the latest ticket over all linked hosts
             -- (S-MAINT-002, copy 4 of 4)
             LEFT JOIN (SELECT max(t.id) AS ticket_id, i2l.isp_link_id
                        FROM tt.ticket t
                             INNER JOIN tt.service_window s ON (s.ticket_id = t.id)
                             INNER JOIN tt.host2service_window h2s ON (h2s.service_window_id = s.id)
                             INNER JOIN mss.interface i ON (h2s.host_id = i.host_id)
                             INNER JOIN mss.interface2isp_link i2l ON (i.id = i2l.interface_id)
                             LEFT JOIN tt.maintenance_window m ON (s.id = m.service_window_id)
                             LEFT JOIN tt.cust_maintenance_window cm ON (s.id = cm.service_window_id)
                        WHERE t.status_id < 101
                          AND s.end_date > statement_timestamp()
                          AND s.start_date < statement_timestamp()
                          AND (m.disable_conn_escalation = 1 OR m.disable_events = 1
                               OR cm.disable_conn_escalation = 1 OR cm.disable_events = 1)
                        GROUP BY i2l.isp_link_id) sw ON l.id = sw.isp_link_id
        WHERE l.id = p_isp_link_id;
        -- DEVIATION(ORACLE-BUG) S-MAINT-016: Oracle (ddl/src/pkgb/mc_osag_maintsync.sql:286)
        -- has NO `l.id = p_isp_link_id` predicate here (its sibling update_single_host has one
        -- at line 216), so the SELECT INTO ranged over EVERY attached link needing a change:
        -- one such link anywhere -> its status written to p_isp_link_id; several ->
        -- TOO_MANY_ROWS, missed by the NO_DATA_FOUND handler, logged by WHEN OTHERS. Added.
        -- DEVIATION(ORACLE-BUG) S-MAINT-017: Oracle (288-294) also ANDs the batch cursor's
        -- "a change is needed" filter here, so an up-to-date attached link returned NO row,
        -- the handler below set 1 (unknown), line 304 saw `stored <> 1` and wrote status 1 +
        -- a history row; the next call wrote 2/3/4 back -- a flip-flop with a spurious
        -- history row per call. The filter is dropped; for an attached link this query always
        -- returns exactly one row and the IF below decides (= the batch routine's logic).
        -- DEVIATION(ORACLE-BUG) S-MAINT-018: Oracle's `l.maintenance_status_id = NULL` (288,
        -- never true; the batch cursor's line 121 says IS NULL) disappears with that filter.
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            -- S-MAINT-015: if we have no data here, the isp link is not attached to an
            -- interface, so the current status should be unknown (1), no maintenance ticket
            v_current_status := 1;
            v_maint_ticket := NULL;
    END;

    IF (v_old_status <> v_current_status OR v_old_status IS NULL) THEN
        INSERT INTO mc.isp_link_maintenance_history
            (id, isp_link_id, change_date, new_maintenance_status_id, old_maintenance_status_id, ticket_id)
        VALUES (nextval('mc.isp_link_maint_history_seq'), p_isp_link_id, statement_timestamp(), v_current_status,
                coalesce(v_old_status, 1), v_maint_ticket);

        UPDATE mss.isp_link l SET maintenance_status_id = v_current_status WHERE l.id = p_isp_link_id;
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        -- S-MAINT-014: log and swallow
        CALL osag.osag_plog_err(s_prefix || 'caught exception: ' || SQLERRM);
END;
$fn$;
