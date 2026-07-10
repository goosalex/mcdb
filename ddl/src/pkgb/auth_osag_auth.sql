--liquibase formatted sql logicalFilePath:pkgb/auth_osag_auth.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE BODY AUTH.OSAG_AUTH IS
    -----------------------------------------------------------------------------
    -- delete_login: delete a login
    -----------------------------------------------------------------------------
    PROCEDURE delete_login(p_login_id login.id%TYPE) IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH.delete_login(): ';

        v_contact_id stop.contact.id%TYPE;

        CURSOR c_all_user_permission_ids IS
            SELECT up.id FROM auth.login2profile l2p
                                  JOIN auth.profile p ON l2p.profile_id = p.id
                                  JOIN auth.user_permission up ON p.id = up.profile_id
            WHERE l2p.login_id = p_login_id;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        SELECT contact_id INTO v_contact_id
        FROM login
        WHERE id = p_login_id;

        TT.OSAG_NOTIFY.delete_notifications_for_login(p_login_id);

        DELETE FROM auth.consented_term WHERE login_id = p_login_id;
        DELETE FROM mss.news_entry_2_login WHERE login_id = p_login_id;

        BEGIN

            FOR lv_user_permission IN c_all_user_permission_ids LOOP
                    DELETE FROM auth.user_company_scope where permission_id = lv_user_permission.id;
                    DELETE FROM auth.user_company_unit_scope where permission_id = lv_user_permission.id;
                    DELETE FROM auth.user_unit_scope where permission_id = lv_user_permission.id;
                    DELETE FROM auth.user_service_scope where permission_id = lv_user_permission.id;
                    DELETE FROM auth.user_service_type_scope where permission_id = lv_user_permission.id;
                    DELETE FROM auth.user_permission WHERE id = lv_user_permission.id;
            END LOOP;

            FOR lv_p IN ( SELECT p.id
                          FROM auth.login2profile l2p JOIN auth.profile p ON l2p.profile_id = p.id
                          WHERE l2p.login_id = p_login_id AND p.is_automatic = 1) LOOP
                DELETE FROM auth.login2profile WHERE profile_id = lv_p.id;
                DELETE FROM auth.profile WHERE id = lv_p.id;
            END LOOP;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                -- there is no profile for this login -> nothing to do
                NULL;
            WHEN OTHERS THEN
                RAISE;
        END;

        DELETE FROM auth.login WHERE id = p_login_id;

        -- delete the contact if no other login references it and if it wouldn't break any constraints
        BEGIN

            DELETE FROM stop.contact
            WHERE id = v_contact_id
              AND id NOT IN (SELECT contact_id FROM login WHERE id != p_login_id)
              AND NOT EXISTS (select 1 from mcaudit.record where contact_id = v_contact_id);

            -- if the contact was left behind because it is still referenced (e.g. by an
            -- audit record) but no login uses it anymore, clear its short: it is unique
            -- and not needed on an orphaned contact, and a stale value would otherwise
            -- collide when the login is re-created later.
            UPDATE stop.contact
            SET short = NULL
            WHERE id = v_contact_id
              AND id NOT IN (SELECT contact_id FROM login WHERE id != p_login_id);
        EXCEPTION
            WHEN OTHERS THEN
                plog.notice(S_PREFIX||'caught exception when deleting contact: '||sqlerrm);
        END;

        plog.notice(S_PREFIX||'deleted login id "'||p_login_id||'"');

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);
            RAISE;

    END delete_login;

    -----------------------------------------------------------------------------
    -- grant a role to a login (DEPRECATED: use grant_user_role)
    -----------------------------------------------------------------------------
    PROCEDURE grant_role(p_login_id login.id%TYPE, p_role_id role.id%TYPE) IS
        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH.grant_user_role(): ';
    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        IF (p_role_id = 3) THEN
            -- Only use case should be ad-sync, creating only users with password change access
            AUTH.OSAG_AUTH.grant_user_role(p_login_id, 1000);
        ELSE
            plog.notice(S_PREFIX||'Can only grant permissions to the mc-cust-radius radius role, use grant_user_role instead');
            RAISE VALUE_ERROR;
        END IF;

    END grant_role;
    -----------------------------------------------------------------------------
    -- grant a role to a login
    -----------------------------------------------------------------------------
    PROCEDURE grant_user_role(p_login_id login.id%TYPE, p_user_role_id user_role.id%TYPE) IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH.grant_user_role(): ';

        v_count NUMBER := 0;
        v_ap_id NUMBER :=0;
        v_new_permission_id NUMBER :=0;
        v_company_id NUMBER :=0;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        SELECT COUNT(*) INTO v_count
        FROM auth.user_permission up join auth.profile p on up.PROFILE_ID = p.id join auth.login2profile l2p on p.id = l2p.profile_id
        WHERE user_role_id = p_user_role_id and l2p.login_id = p_login_id AND ROWNUM = 1;

        SELECT nvl(min(p.id), 0) INTO v_ap_id
        FROM auth.profile p join auth.login2profile l2p on p.id = l2p.profile_id
        WHERE p.is_automatic = 1 and l2p.login_id = p_login_id AND ROWNUM = 1;

        SELECT company_id into v_company_id
        FROM auth.login where id = p_login_id;

        -- add to auth.permission if necessary
        IF (v_count = 0) THEN
            IF (v_ap_id = 0) THEN
                -- No automatic profile, let's create one!
                SELECT auth.seq_profile.nextVal INTO v_ap_id FROM dual;
                INSERT INTO auth.profile (id, name, is_automatic) values (v_ap_id, 'automatic profile', 1);
                INSERT INTO auth.login2profile (login_id, profile_id) values (p_login_id, v_ap_id);
            END IF;
            SELECT auth.seq_user_permission.nextVal INTO v_new_permission_id FROM dual;

            INSERT INTO auth.user_permission(id, user_role_id, profile_id) values (v_new_permission_id, p_user_role_id, v_ap_id);
            INSERT INTO auth.user_company_scope(id, company_id, permission_id, sdp_access) values (auth.seq_user_company_scope.nextval, v_company_id, v_new_permission_id, 1);
        END IF;

        plog.debug(S_PREFIX||'granted company scope role id "'||p_user_role_id||'" to login id "'||p_login_id||'"');

    EXCEPTION
        WHEN OTHERS THEN
            -- Don't raise an exception if it's only a unique constraint
            -- exception (e.g. the record exists already)
            IF (SQLCODE != -00001) THEN
                plog.err(S_PREFIX||'caught exception: '||sqlerrm);
                RAISE;
            END IF;

    END grant_user_role;

END OSAG_AUTH;
/
