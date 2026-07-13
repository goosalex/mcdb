-- migration/pgsql/auth/osag_auth.sql
--
-- Translation of AUTH.OSAG_AUTH (spec: migration/spec/auth.osag_auth.md; Oracle body:
-- ddl/src/pkgb/auth_osag_auth.sql, 156 lines). Names copied verbatim from
-- migration/mapping/name-map.csv's 3 OSAG_AUTH rows.
--
-- Oracle's usage-audit call (package-state tracking, XCUT-06): all 3 call sites DELETED,
-- not ported. Count: 3 (delete_login line 20, grant_role line 93, grant_user_role line
-- 116 of the Oracle body). See osag_auth.FINDINGS.md.
--
-- delete_login calls TT.OSAG_NOTIFY.delete_notifications_for_login (S-AUTH-002),
-- name-mapped to tt.osag_notify_delete_notifications_for_login -- a transitive
-- dependency this plan does not translate (plan 02-10, same wave). PL/pgSQL does not
-- resolve CALL targets at CREATE time, so this file loads cleanly regardless; the
-- success-path pgTAP assertions that reach this CALL (S-AUTH-004/005) will stay RED
-- until 02-10 lands -- expected and documented in the pgtap file's own header comment
-- and in this plan's SUMMARY.md.
--
-- "no data found" message-parity shim: see osag_auth.FINDINGS.md. Every unhandled
-- Oracle NO_DATA_FOUND propagation in this package is translated as SELECT ... INTO
-- STRICT immediately followed by a transparent WHEN NO_DATA_FOUND handler that ONLY
-- corrects the message text to "no data found" (matching Oracle's real ORA-01403
-- SQLERRM) before re-raising -- it does not swallow, log, or otherwise change control
-- flow, and the exception still propagates onward exactly as the Oracle source (with no
-- local handler at all) does.

-- ------------------------------------------------------------------------------------
-- delete_login (S-AUTH-001..007)
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE auth.osag_auth_delete_login(p_login_id bigint)
LANGUAGE plpgsql
AS $fn$
DECLARE
    s_prefix CONSTANT text := 'OSAG_AUTH.delete_login(): ';
    v_contact_id numeric;
    r_perm RECORD;
    r_prof RECORD;
BEGIN
    -- S-AUTH-001: login.id is the PK, so TOO_MANY_ROWS is structurally impossible; no
    -- local handler in Oracle -- the "no data found" shim below preserves that (it does
    -- not add real handling, only corrects the propagated message text).
    BEGIN
        SELECT contact_id INTO STRICT v_contact_id FROM auth.login WHERE id = p_login_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE EXCEPTION 'no data found' USING ERRCODE = 'P0002';
    END;

    -- S-AUTH-002: unconditional, before any of this routine's own DELETEs.
    CALL tt.osag_notify_delete_notifications_for_login(p_login_id);

    -- S-AUTH-003: unconditional deletes, no existence check, no error on zero rows.
    DELETE FROM auth.consented_term WHERE login_id = p_login_id;
    DELETE FROM mss.news_entry_2_login WHERE login_id = p_login_id;

    -- S-AUTH-004: both loops are cursor FOR loops, not SELECT INTO -- zero rows is a
    -- normal empty loop, never NO_DATA_FOUND (so the WHEN NO_DATA_FOUND THEN NULL arm
    -- below is dead code with respect to these loops, exactly as in Oracle -- kept only
    -- for structural fidelity to the source). A real error from inside either loop body
    -- propagates via the bare WHEN OTHERS THEN RAISE.
    BEGIN
        FOR r_perm IN
            SELECT up.id
            FROM auth.login2profile l2p
            JOIN auth.profile p ON l2p.profile_id = p.id
            JOIN auth.user_permission up ON p.id = up.profile_id
            WHERE l2p.login_id = p_login_id
        LOOP
            DELETE FROM auth.user_company_scope WHERE permission_id = r_perm.id;
            DELETE FROM auth.user_company_unit_scope WHERE permission_id = r_perm.id;
            DELETE FROM auth.user_unit_scope WHERE permission_id = r_perm.id;
            DELETE FROM auth.user_service_scope WHERE permission_id = r_perm.id;
            DELETE FROM auth.user_service_type_scope WHERE permission_id = r_perm.id;
            DELETE FROM auth.user_permission WHERE id = r_perm.id;
        END LOOP;

        FOR r_prof IN
            SELECT p.id
            FROM auth.login2profile l2p
            JOIN auth.profile p ON l2p.profile_id = p.id
            WHERE l2p.login_id = p_login_id AND p.is_automatic = 1
        LOOP
            DELETE FROM auth.login2profile WHERE profile_id = r_prof.id;
            DELETE FROM auth.profile WHERE id = r_prof.id;
        END LOOP;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            NULL;
        WHEN OTHERS THEN
            RAISE;
    END;

    -- S-AUTH-005: only reached once S-AUTH-001 has already confirmed p_login_id exists.
    DELETE FROM auth.login WHERE id = p_login_id;

    -- S-AUTH-006: the ONE place an exception is deliberately absorbed, not propagated --
    -- a contact-cleanup failure must never abort the overall delete_login call.
    BEGIN
        DELETE FROM stop.contact
        WHERE id = v_contact_id
          AND id NOT IN (SELECT contact_id FROM auth.login WHERE id != p_login_id)
          AND NOT EXISTS (SELECT 1 FROM mcaudit.record WHERE contact_id = v_contact_id);

        UPDATE stop.contact
        SET short = NULL
        WHERE id = v_contact_id
          AND id NOT IN (SELECT contact_id FROM auth.login WHERE id != p_login_id);
    EXCEPTION
        WHEN OTHERS THEN
            CALL osag.osag_plog_notice(s_prefix || 'caught exception when deleting contact: ' || SQLERRM);
    END;

    CALL osag.osag_plog_notice(s_prefix || 'deleted login id "' || p_login_id || '"');

-- S-AUTH-007: outermost catch-all -- logs exactly once, then bare re-raise (preserves
-- whatever the original exception was, including the "no data found" shim above and any
-- real error from the S-AUTH-004 nested block).
EXCEPTION
    WHEN OTHERS THEN
        CALL osag.osag_plog_err(s_prefix || 'caught exception: ' || SQLERRM);
        RAISE;
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- grant_role (S-AUTH-008) -- DEPRECATED per Oracle's own header comment; preserved
-- AS-WRITTEN (not assumed dead code -- see FINDINGS.md/spec Assumptions).
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE auth.osag_auth_grant_role(p_login_id bigint, p_role_id bigint)
LANGUAGE plpgsql
AS $fn$
DECLARE
    s_prefix CONSTANT text := 'OSAG_AUTH.grant_user_role(): ';
BEGIN
    IF p_role_id = 3 THEN
        -- Only use case should be ad-sync, creating only users with password change access
        CALL auth.osag_auth_grant_user_role(p_login_id, 1000);
    ELSE
        CALL osag.osag_plog_notice(s_prefix || 'Can only grant permissions to the mc-cust-radius radius role, use grant_user_role instead');
        -- VALUE_ERROR (ORA-06502) -> PostgreSQL invalid_parameter_value (22023),
        -- provisional pending Phase 3 XCUT-01's authoritative mapping.
        RAISE EXCEPTION 'value_error: p_role_id must be 3' USING ERRCODE = '22023';
    END IF;
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- grant_user_role (S-AUTH-009..011)
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE auth.osag_auth_grant_user_role(p_login_id bigint, p_user_role_id bigint)
LANGUAGE plpgsql
AS $fn$
DECLARE
    s_prefix CONSTANT text := 'OSAG_AUTH.grant_user_role(): ';
    v_count integer := 0;
    v_ap_id bigint := 0;
    v_new_permission_id bigint := 0;
    v_company_id bigint := 0;
BEGIN
    -- S-AUTH-009: COUNT(*) aggregate, always exactly one row -- STRICT can never trip.
    -- Oracle's own "AND ROWNUM = 1" clamps the counted set to at most 1 row before
    -- aggregation (an existence check dressed as a count, not a true row count) --
    -- reproduced AS-WRITTEN via the same limit-then-count shape, not "fixed" to a true
    -- COUNT(*) over every match (Pitfall 1: preserve the AS-WRITTEN contract).
    SELECT count(*) INTO STRICT v_count
    FROM (
        SELECT 1
        FROM auth.user_permission up
        JOIN auth.profile p ON up.profile_id = p.id
        JOIN auth.login2profile l2p ON p.id = l2p.profile_id
        WHERE up.user_role_id = p_user_role_id AND l2p.login_id = p_login_id
        LIMIT 1
    ) lim;

    -- Same AS-WRITTEN ROWNUM=1-then-aggregate shape for the automatic-profile lookup.
    SELECT coalesce(min(ap.id), 0) INTO STRICT v_ap_id
    FROM (
        SELECT p.id
        FROM auth.profile p
        JOIN auth.login2profile l2p ON p.id = l2p.profile_id
        WHERE p.is_automatic = 1 AND l2p.login_id = p_login_id
        LIMIT 1
    ) ap;

    -- S-AUTH-009: plain (non-aggregate) PK lookup -- NO_DATA_FOUND reachable, no local
    -- Oracle handler; "no data found" shim (see file header) preserves the propagation.
    BEGIN
        SELECT company_id INTO STRICT v_company_id FROM auth.login WHERE id = p_login_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE EXCEPTION 'no data found' USING ERRCODE = 'P0002';
    END;

    -- S-AUTH-010: create an automatic profile if none exists yet, then always grant.
    IF v_count = 0 THEN
        IF v_ap_id = 0 THEN
            SELECT nextval('auth.seq_profile') INTO STRICT v_ap_id;
            INSERT INTO auth.profile (id, name, is_automatic) VALUES (v_ap_id, 'automatic profile', 1);
            INSERT INTO auth.login2profile (login_id, profile_id) VALUES (p_login_id, v_ap_id);
        END IF;
        SELECT nextval('auth.seq_user_permission') INTO STRICT v_new_permission_id;

        INSERT INTO auth.user_permission (id, user_role_id, profile_id)
            VALUES (v_new_permission_id, p_user_role_id, v_ap_id);
        INSERT INTO auth.user_company_scope (id, company_id, permission_id, sdp_access)
            VALUES (nextval('auth.seq_user_company_scope'), v_company_id, v_new_permission_id, 1);
    END IF;

    CALL osag.osag_plog_debug(s_prefix || 'granted company scope role id "' || p_user_role_id || '" to login id "' || p_login_id || '"');

-- S-AUTH-011: swallow ONLY a unique-constraint violation (23505 -- PostgreSQL's
-- equivalent of Oracle's ORA-00001/SQLCODE -1) -- genuine idempotent-re-grant business
-- logic, not incidental logging suppression. Every other error is logged and re-raised.
EXCEPTION
    WHEN OTHERS THEN
        IF SQLSTATE != '23505' THEN
            CALL osag.osag_plog_err(s_prefix || 'caught exception: ' || SQLERRM);
            RAISE;
        END IF;
END;
$fn$;
