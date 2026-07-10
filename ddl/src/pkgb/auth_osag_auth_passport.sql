--liquibase formatted sql logicalFilePath:pkgb/auth_osag_auth_passport.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE BODY AUTH.OSAG_AUTH_PASSPORT IS

    FUNCTION is_password_only_allowed (p_homeauthhost_id authhost.id%TYPE) RETURN BOOLEAN;

    -----------------------------------------------------------------------------
    -- add_login2groups: assign a group to a login
    -----------------------------------------------------------------------------
    PROCEDURE add_login2groups(p_login_id passport_login.id%TYPE, p_group_id groups.id%TYPE) IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.add_login2groups(): ';

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        INSERT INTO passport_login2groups (login_id, group_id)
        VALUES (p_login_id, p_group_id);

        plog.notice(S_PREFIX||'assigned group id "'||p_group_id||'" to login id "'||p_login_id||'"');

    EXCEPTION
        WHEN OTHERS THEN
            IF (SQLCODE != -00001) THEN
                plog.err(S_PREFIX||'caught exception: '||sqlerrm);
                RAISE;
            END IF;

    END add_login2groups;


    -----------------------------------------------------------------------------
    -- add_alias: add an alias to a login
    -----------------------------------------------------------------------------
    PROCEDURE add_alias(p_login_id passport_login.id%TYPE, p_alias passport_alias.alias%TYPE, p_nocheck NUMBER DEFAULT 0) IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.add_alias(): ';
        v_homeauthhost_id passport_login.homeauthhost_id%TYPE;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        SELECT homeauthhost_id INTO v_homeauthhost_id
        FROM passport_login
        WHERE id = p_login_id;

        IF (check_login_unique(p_alias, v_homeauthhost_id)) THEN
            INSERT INTO passport_alias (id, login_id, alias)
            VALUES (seq_alias_id.nextval, p_login_id, p_alias);

            plog.notice(S_PREFIX||'added alias "'||p_alias||'" for login id "'||p_login_id||'"');
        ELSE
            RAISE_APPLICATION_ERROR(OSAG_AUTH_STATE.S_ERRNO_DUPLICATE_ALIAS, 'alias "'||p_alias||'" is not unique');
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            IF (SQLCODE != -00001) THEN
                IF (p_nocheck != 1) THEN
                    plog.err(S_PREFIX||'caught exception: '||sqlerrm);
                END IF;
                RAISE;
            END IF;

    END add_alias;

    -----------------------------------------------------------------------------
    -- add_softtoken: creates a softtoken
    -----------------------------------------------------------------------------
    PROCEDURE add_softtoken(p_token_id OUT token.id%TYPE, p_tokenserial OUT token.serial%TYPE,
                            p_company_id token.company_id%TYPE, p_softtokenexpiry token.expirydate%TYPE,
                            p_softtokenseed token.seed%TYPE, p_softtoken_validfrom token.validfrom%TYPE) IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.add_softtoken(): ';

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        SELECT seq_token_id.nextval INTO p_token_id
        FROM dual;
        SELECT 'MC-'||to_char(p_token_id,'FM000000000') into p_tokenserial
        FROM dual;

        INSERT INTO token (id, company_id, enabled, expirydate, seed, serial, seciddrift,
                           actercount, dpblob, tokenform_id,
                           tokentype_id, token_pool_id, validfrom, activated)
        VALUES (p_token_id, p_company_id, 1, p_softtokenexpiry, p_softtokenseed, p_tokenserial, 0,
                0, NULL, OSAG_AUTH_STATE.C_OSAG_TOKENFORM_SOFT,
                OSAG_AUTH_STATE.C_OSAG_TOKENTYPE_SOFTTOKEN, NULL, p_softtoken_validfrom, 0);

        plog.debug(S_PREFIX||'created token "'||p_tokenserial||'"');

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);
            RAISE;

    END add_softtoken;

    -----------------------------------------------------------------------------
    -- check_auth_login_email_unique: checks the global uniqueness of an email address (if
    -- it is non-null), see Issue AUT-105. This is also enforced through a unique constraint on
    -- auth.passport_login.email. However, for the purpose of auth synchronization we
    -- want a well-defined exception, so we can recognize this particular
    -- condition (the alternative is to track the name of the actual unique
    -- constraint). The check is case insensitive.
    -----------------------------------------------------------------------------
    FUNCTION check_auth_login_email_unique(p_email auth.passport_login.email%TYPE) RETURN BOOLEAN IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.check_auth_login_email_unique(): ';

        v_count NUMBER;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- email addresse may be null
        IF (p_email IS NULL) THEN
            RETURN(TRUE);
        END IF;

        SELECT count(*) INTO v_count
        FROM auth.passport_login l
        WHERE LOWER(l.email) = LOWER(p_email);

        IF (v_count = 0) THEN
            plog.debug(S_PREFIX||'auth email is unique: "'||p_email||'"');
            RETURN(TRUE);
        END IF;

        plog.debug(S_PREFIX||'auth email is not unique: "'||p_email||'"');
        RETURN(FALSE);

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);
            RAISE;

    END check_auth_login_email_unique;

    -----------------------------------------------------------------------------
    -- check_auth_email_unique: Issue AUT-105
    -----------------------------------------------------------------------------
    PROCEDURE check_auth_email_unique(p_email auth.passport_login.email%TYPE) IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.check_auth_email_unique(): ';

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        IF (NOT check_auth_login_email_unique(p_email)) THEN
            RAISE_APPLICATION_ERROR(OSAG_AUTH_STATE.S_ERRNO_DUPLICATE_EMAIL, 'email "'||p_email||'" is not unique');
            plog.notice(S_PREFIX||'auth email address is not unique "'||p_email||'"');
        END IF;

        plog.debug(S_PREFIX||'checked auth email "'||p_email||'"');

    EXCEPTION
        WHEN OTHERS THEN
            IF (SQLCODE != -00001) THEN
                plog.err(S_PREFIX||'caught exception: '||sqlerrm);
                RAISE;
            END IF;

    END check_auth_email_unique;

    -----------------------------------------------------------------------------
    -- add_login2tunnelgroup: assign a group to a login
    -----------------------------------------------------------------------------
    PROCEDURE add_login2tunnelgroup(p_login_id passport_login.id%TYPE, p_tunnelgroup_id tunnelgroup.id%TYPE) IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.add_login2tunnelgroup(): ';

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        INSERT INTO passport_login2tunnelgroup (login_id, tunnelgroup_id)
        VALUES (p_login_id, p_tunnelgroup_id);

        plog.notice(S_PREFIX||'assigned tunnelgroup id "'||p_tunnelgroup_id||'" to login id "'||p_login_id||'"');

    EXCEPTION
        WHEN OTHERS THEN
            IF (SQLCODE != -00001) THEN
                plog.err(S_PREFIX||'caught exception: '||sqlerrm);
                RAISE;
            END IF;

    END add_login2tunnelgroup;

    -----------------------------------------------------------------------------
    -- check_login_unique: checks the uniqueness of a login (or alias) across the same
    -- customer
    -----------------------------------------------------------------------------
    FUNCTION check_login_unique(p_login passport_login.login%TYPE,
                                p_homeauthhost_id passport_login.homeauthhost_id%TYPE) RETURN BOOLEAN IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.check_login_unique(): ';

        v_count NUMBER;
        v_company_id stop.company.id%TYPE;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- The lookup up of company_id by way ot the homeauthhost has historical
        -- reasons.  Nowadays we could pass the company_id directly.
        SELECT company_id INTO v_company_id
        FROM authhost2authsys a2a, authsys
        WHERE a2a.authhost_id = p_homeauthhost_id
          AND a2a.authsys_id = authsys.id;

        SELECT count(*) INTO v_count
        FROM passport_login l
        WHERE lower(l.login) = lower(p_login)
          AND company_id = v_company_id;

        IF (v_count = 0) THEN
            SELECT count(*) INTO v_count
            FROM passport_alias a, passport_login l
            WHERE lower(a.alias) = lower(p_login)
              AND a.login_id = l.id
              AND l.company_id = v_company_id;

            IF (v_count = 0) THEN
                plog.debug(S_PREFIX||'login/alias "'||p_login||'" is unique');
                RETURN(true);
            END IF;
            plog.debug(S_PREFIX||'login/alias "'||p_login||'" collides with existing alias');
        END IF;

        plog.debug(S_PREFIX||'login/alias "'||p_login||'" is not unique');
        RETURN(false);

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);
            RAISE;

    END check_login_unique;

    -----------------------------------------------------------------------------
    -- check_email_unique: checks the global uniqueness of an email address (if
    -- it is non-null). This is also enforced through a unique constraint on
    -- stop.passport_contact.email. However, for the purpose of auth synchronization we
    -- want a well-defined exception, so we can recognize this particular
    -- condition (the alternative is to track the name of the actual unique
    -- constraint). The check is case insensitive.

    -- Note: this will also not be enforced any more by a unique constraint: Issue AUT-105
    -----------------------------------------------------------------------------
    FUNCTION check_email_unique(p_email stop.passport_contact.email%TYPE) RETURN BOOLEAN IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.check_email_unique(): ';

        v_count NUMBER;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- email addresse may be null
        IF (p_email IS NULL) THEN
            RETURN(TRUE);
        END IF;

        SELECT count(*) INTO v_count
        FROM stop.passport_contact sc
        WHERE LOWER(sc.email) = LOWER(p_email);

        IF (v_count = 0) THEN
            RETURN(TRUE);
        END IF;

        RETURN(FALSE);

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);
            RAISE;

    END check_email_unique;

    -----------------------------------------------------------------------------
    -- check_recent_password: check if the password was recently used by the given
    -- login, but only if the login's authsys has the passwordexpiryenabled
    -- attribute set (recently means: the password was already used for one
    -- of the last 5 password changes)
    -- [rv] maybe a flag like "checkrecentpasswordenabled" for authsys would have
    -- been better than reusing "passwordexpiryenabled", however no time for that now
    -----------------------------------------------------------------------------
    PROCEDURE check_recent_password(p_login_id passport_login.id%TYPE, p_password IN VARCHAR2) IS
        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.check_recent_password(): ';

        v_passwordexpiryenabled AUTHSYS.PASSWORDEXPIRYENABLED%TYPE;
        v_recentpassword_count NUMBER;
    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        SELECT authsys.passwordexpiryenabled INTO v_passwordexpiryenabled
        FROM auth.passport_login l, auth.authhost2authsys h2a, auth.authsys
        WHERE l.id = p_login_id
          AND l.homeauthhost_id = h2a.authhost_id
          AND h2a.authsys_id = authsys.id;

        IF (v_passwordexpiryenabled = 1) THEN
            SELECT count(id) INTO v_recentpassword_count
            FROM passport_recentpassword
            WHERE login_id = p_login_id
              AND password = hash_password(p_password, salt);

            IF (v_recentpassword_count > 0) THEN
                -- the password was recently used
                RAISE_APPLICATION_ERROR(OSAG_AUTH_STATE.S_ERRNO_PASSWORD_RECENTLY_USED, 'The password has been recently used.');
            END IF;
        END IF;

    EXCEPTION
        WHEN OSAG_AUTH_STATE.password_recently_used THEN
            plog.debug(S_prefix||'recently used password detected: '||sqlerrm);
            RAISE;

        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);
            RAISE;

    END check_recent_password;

    -----------------------------------------------------------------------------
    -- count_available_authsys: count the available authentication systems for a
    -- passport_login. This can be used to decide whether a user can be attached to a
    -- customer authentication system
    -----------------------------------------------------------------------------
    FUNCTION count_available_authsys(p_login_id passport_login.id%TYPE) return NUMBER IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.count_available_authsys(): ';

        v_count NUMBER := 0;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        SELECT count(1) INTO v_count
        FROM auth.authsys a, auth.passport_login l, stop.passport_contact c
        WHERE l.id = p_login_id
          AND l.contact_id = c.id
          AND c.company_id = a.company_id;

        RETURN v_count;

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);
            RAISE;

    END count_available_authsys;

    -----------------------------------------------------------------------------
    -- count_token_users: count how many logins use a given token
    -----------------------------------------------------------------------------
    FUNCTION count_token_users(p_token_id token.id%TYPE,
                               p_login_id passport_login.id%TYPE) return NUMBER IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.count_token_users(): ';

        v_count NUMBER := 0;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        SELECT count(1) INTO v_count
        FROM auth.passport_login
        WHERE token_id = p_token_id
          AND id != nvl(p_login_id, -1);

        RETURN v_count;

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);
            RAISE;

    END count_token_users;

    -----------------------------------------------------------------------------
    -- delete_login: delete a login
    -----------------------------------------------------------------------------
    PROCEDURE delete_login(p_login_id passport_login.id%TYPE) IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.delete_login(): ';

        v_contact_id stop.passport_contact.id%TYPE;
        v_token_id auth.token.id%TYPE;
        v_replacementtoken_id auth.token.id%TYPE;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        SELECT contact_id, token_id, replacementtoken_id INTO v_contact_id, v_token_id, v_replacementtoken_id
        FROM passport_login
        WHERE id = p_login_id;

        DELETE FROM auth.passport_login2groups WHERE login_id = p_login_id;
        DELETE FROM auth.passport_login2tunnelgroup WHERE login_id = p_login_id;
        DELETE FROM auth.passport_alias WHERE login_id = p_login_id;
        DELETE FROM auth.passport_recentpassword WHERE login_id = p_login_id;
        DELETE FROM auth.passport_temp_access_key WHERE login_id = p_login_id;

        DELETE FROM auth.passport_login WHERE id = p_login_id;

        -- delete the contact if no other login references it and if it wouldn't break any constraints
        BEGIN
            DELETE FROM stop.passport_contact_sync
            WHERE contact_id = v_contact_id;

            DELETE FROM stop.passport_contact
            WHERE id = v_contact_id
              AND id NOT IN (SELECT contact_id FROM passport_login WHERE id != p_login_id);
        EXCEPTION
            WHEN OTHERS THEN
                plog.notice(S_PREFIX||'caught exception when deleting contact: '||sqlerrm);
        END;

        -- delete softtokens (TOKENFORM = 3)
        BEGIN
            DELETE FROM auth.token
            WHERE (id = v_token_id OR id = v_replacementtoken_id) AND tokenform_id = 3;
        EXCEPTION
            WHEN OTHERS THEN
                plog.err(S_PREFIX||'caught exception when deleting softokens: '||sqlerrm);
        END;

        plog.notice(S_PREFIX||'deleted login id "'||p_login_id||'"');

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);
            RAISE;

    END delete_login;

    -----------------------------------------------------------------------------
    -- delete_login_sync: delete a login synchronized from external source
    -----------------------------------------------------------------------------
    PROCEDURE delete_login_sync(p_login_id OUT passport_login.id%TYPE, p_contact_id OUT passport_login.contact_id%TYPE,
                                p_login passport_login.login%TYPE, p_syncdomain_id syncdomain.id%TYPE) IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.delete_login_ads(): ';

        v_login passport_login%ROWTYPE;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        BEGIN
            SELECT l.* INTO v_login FROM passport_login l, stop.passport_contact_sync scs
            WHERE l.login = p_login
              AND l.contact_id = scs.contact_id
              AND scs.syncdomain_id = p_syncdomain_id;

        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(OSAG_AUTH_STATE.S_ERRNO_NO_LOGIN_RECORD, 'no record found for login="'||p_login||'", syncdomain_id='||p_syncdomain_id);
            WHEN OTHERS THEN
                RAISE;

        END;


        p_login_id := v_login.id;
        p_contact_id := v_login.contact_id;

        delete_login(v_login.id);

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);
            RAISE;

    END delete_login_sync;

    -----------------------------------------------------------------------------
    -- delete_aliases: delete all aliases for the specified login id.
    -----------------------------------------------------------------------------
    PROCEDURE delete_aliases(p_login_id passport_login.id%TYPE) IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.delete_aliases(): ';

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        DELETE FROM auth.passport_alias WHERE login_id = p_login_id;

        plog.notice(S_PREFIX||'deleted aliases for login id "'||p_login_id||'"');

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);
            RAISE;

    END delete_aliases;

    -----------------------------------------------------------------------------
    -- delete_alias: delete alias for the specified login id.
    -- mds@open.ch: this procedure is needed to dynamically update aliases
    -----------------------------------------------------------------------------
    PROCEDURE delete_alias(p_alias passport_alias.alias%TYPE) IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.delete_alias(): ';

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        DELETE FROM auth.passport_alias WHERE alias LIKE p_alias;

        plog.notice(S_PREFIX||'deleted alias "'||p_alias||'"');

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);
            RAISE;

    END delete_alias;

    -----------------------------------------------------------------------------
    -- delete_login2groups: delete all group assignments for the specified login
    -- id.
    -----------------------------------------------------------------------------
    PROCEDURE delete_login2groups(p_login_id passport_login.id%TYPE) IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.delete_login2groups(): ';

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        DELETE FROM auth.passport_login2groups WHERE login_id = p_login_id;

        plog.notice(S_PREFIX||'deleted group assignments for login id "'||p_login_id||'"');

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);
            RAISE;

    END delete_login2groups;

    -----------------------------------------------------------------------------
    -- delete_login2tunnelgroup: delete all group assignments for the specified login
    -- id.
    -----------------------------------------------------------------------------
    PROCEDURE delete_login2tunnelgroup(p_login_id passport_login.id%TYPE) IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.delete_login2tunnelgroup(): ';

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        DELETE FROM auth.passport_login2tunnelgroup WHERE login_id = p_login_id;

        plog.notice(S_PREFIX||'deleted tunnel group assignments for login id "'||p_login_id||'"');

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);
            RAISE;

    END delete_login2tunnelgroup;

    -----------------------------------------------------------------------------
    -- encrypt_password: encrypt a plaintext password (MD5 for now)
    -----------------------------------------------------------------------------
    FUNCTION encrypt_password(p_password VARCHAR2) return VARCHAR2 IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.encrypt_password(): ';

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- md5 hash in lowercase
        RETURN lower(OSAG_DIGEST.md5(p_password));

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);
            RAISE;

    END encrypt_password;


    -----------------------------------------------------------------------------
    -- hash_password: hashes a password and a given salt using
    -- SHA256(salt + MD5(password))
    --
    -- We do the workaround with the additional MD5 hash because we needed to
    -- migrate MD5 password hashes when we switched to SHA256. The original passwords
    -- were not known during this migration. See MC-4356 for details.
    -----------------------------------------------------------------------------
    FUNCTION hash_password(p_password VARCHAR2, p_salt VARCHAR2) return passport_login.pwhash%TYPE IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.hash_password(): ';

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- sha256 hash in lowercase of password prepended with salt
        RETURN lower(OSAG_DIGEST.sha256(p_salt || encrypt_password(p_password)));

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);
            RAISE;

    END hash_password;

    -----------------------------------------------------------------------------
    -- grant a role to a login (DEPRECATED: use grant_user_role)
    -----------------------------------------------------------------------------
    PROCEDURE grant_role(p_login_id passport_login.id%TYPE, p_role_id role.id%TYPE) IS
        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.grant_user_role(): ';
    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        IF (p_role_id = 3) THEN
            -- Only use case should be ad-sync, creating only users with password change access
            AUTH.OSAG_AUTH_PASSPORT.grant_user_role(p_login_id, 1000);
        ELSE
            plog.notice(S_PREFIX||'Can only grant permissions to the mc-cust-radius radius role, use grant_user_role instead');
            RAISE VALUE_ERROR;
        END IF;

    END grant_role;
    -----------------------------------------------------------------------------
    -- grant a role to a login
    -----------------------------------------------------------------------------
    PROCEDURE grant_user_role(p_login_id passport_login.id%TYPE, p_user_role_id user_role.id%TYPE) IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.grant_user_role(): ';

        v_count NUMBER := 0;
        v_ap_id NUMBER :=0;
        v_new_permission_id NUMBER :=0;
        v_company_id NUMBER :=0;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);

        -- does nothing in osag_auth_passport
    EXCEPTION
        WHEN OTHERS THEN
            -- Don't raise an exception if it's only a unique constraint
            -- exception (e.g. the record exists already)
            IF (SQLCODE != -00001) THEN
                plog.err(S_PREFIX||'caught exception: '||sqlerrm);
                RAISE;
            END IF;

    END grant_user_role;

    -----------------------------------------------------------------------------
    -- insert_login: Inserts a new login
    -----------------------------------------------------------------------------
    PROCEDURE insert_login(p_login_id OUT passport_login.id%TYPE, p_login passport_login.login%TYPE, p_passwordtype_id passwordtype.id%TYPE,
                           p_password VARCHAR2, p_twofactorenabled passport_login.twofactorenabled%TYPE, p_token_id token.id%TYPE,
                           p_replacementtoken_id token.id%TYPE, p_homeauthhost_id authhost.id%TYPE, p_locked passport_login.locked%TYPE,
                           p_maxretries passport_login.maxretries%TYPE, p_firstname stop.passport_contact.firstname%TYPE,
                           p_lastname stop.passport_contact.lastname%TYPE, p_direct stop.passport_contact.direct%TYPE,
                           p_mobile stop.passport_contact.mobile%TYPE, p_home stop.passport_contact.home%TYPE, p_fax stop.passport_contact.fax%TYPE,
                           p_email stop.passport_contact.email%TYPE, p_authemail auth.passport_login.email%TYPE, p_company_id stop.company.id%TYPE,
                           p_anytunnelgroup passport_login.anytunnelgroup%TYPE DEFAULT 0,
                           p_passwordexpiry passport_login.passwordexpiry%TYPE DEFAULT NULL,
                           p_cost_center_id mss.cost_center.id%TYPE DEFAULT NULL, p_function stop.passport_contact.function%TYPE DEFAULT NULL, p_comments stop.passport_contact.comments%TYPE DEFAULT NULL,
                           p_authtype_id auth.authtype.id%TYPE, p_smsauthnumber passport_login.smsauthnumber%TYPE) IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.insert_login(): ';

        v_contact_id stop.passport_contact.id%TYPE;
        v_nopasswordonly NUMBER; -- auth.authsys.nopasswordonly%TYPE;
        v_default_uuid auth.user_unit.id%TYPE;
        v_logintype auth.passport_login.logintype_id%TYPE;
    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        plog.debug(S_PREFIX||'inserting into auth.passport_login.email: "'||p_authemail||'" for login "'||p_login||'"');

        IF (NOT check_login_unique(p_login, p_homeauthhost_id)) THEN
            RAISE_APPLICATION_ERROR(OSAG_AUTH_STATE.S_ERRNO_DUPLICATE_LOGIN, 'login "'||p_login||'" is not unique');
        END IF;


        -- this is not done any more. see Issue AUT-105
        --IF (NOT check_email_unique(p_email)) THEN
        --RAISE_APPLICATION_ERROR(OSAG_AUTH_STATE.S_ERRNO_DUPLICATE_EMAIL, 'email "'||p_email||'" is not unique');
        --END IF;

        -- check whether password only is allowed
        -- this is currently checked for unlocked users only
        -- 0: password only mode auth type
        IF p_twofactorenabled = 0 AND p_locked = 0 AND (NOT is_password_only_allowed(p_homeauthhost_id)) THEN
            RAISE_APPLICATION_ERROR(OSAG_AUTH_STATE.S_ERRNO_NO_PASSWORD_ONLY, 'Password-only authentication is not allowed for unlocked users.');
        END IF;

        -- determine id of the company's default user unit
        SELECT id INTO v_default_uuid FROM auth.user_unit WHERE company_id = p_company_id AND default_unit = 1;

        -- get a contact id from the sequence
        SELECT stop.contact_seq.nextval INTO v_contact_id
        FROM dual;

        -- create the contact
        INSERT INTO stop.passport_contact (id, firstname, lastname, direct, mobile, home, fax,
                                  email, company_id, function, created, modified, comments)
        VALUES (v_contact_id,
                substrb(p_firstname, 1, 50),
                substrb(p_lastname, 1, 50),
                substrb(p_direct, 1, 30),
                substrb(p_mobile, 1, 30),
                substrb(p_home, 1, 30),
                substrb(p_fax, 1, 30),
                substrb(p_email, 1, 250),
                p_company_id,
                substrb(p_function, 1, 100),
                systimestamp,
                systimestamp,
                substrb(p_comments, 1, 200));

        plog.debug(S_PREFIX||'created contact id "'||v_contact_id||'" for login "'||p_login||'"');

        BEGIN

            -- get a login id from the sequence
            SELECT seq_login_id.nextval INTO p_login_id
            FROM dual;

            -- no mc-cust-radius yet, no tunnel groups yet. So if we have p_anytunnelgroup it's a MEP-only login, otherwise we don't know yet.
            v_logintype := NULL;
            IF p_anytunnelgroup = 1 THEN
              v_logintype := 1; -- MEP
            END IF;
            -- Note that by newly inserting the auth.passport_login.email, the business logic with tests for uniqueness etc. are done on the Perl level. If p_authemail is not null, it will be inserted here
            INSERT INTO passport_login (id, login, contact_id, passwordtype_id, twofactorenabled, token_id, replacementtoken_id,
                               enabled, homeauthhost_id, locked, maxretries, anytunnelgroup, passwordexpiry, cost_center_id, user_unit_id, email, authtype_id, smsauthnumber, creationdate, logintype_id)
            VALUES (p_login_id, p_login, v_contact_id, p_passwordtype_id, p_twofactorenabled, p_token_id, p_replacementtoken_id,
                    1, p_homeauthhost_id, p_locked, p_maxretries, p_anytunnelgroup, p_passwordexpiry, p_cost_center_id, v_default_uuid, p_authemail, p_authtype_id, p_smsauthnumber, SYSTIMESTAMP, v_logintype);

        EXCEPTION
            WHEN OTHERS THEN
                IF (sqlcode = -00001) THEN
                    RAISE_APPLICATION_ERROR(OSAG_AUTH_STATE.S_ERRNO_DUPLICATE_LOGIN, 'login "'||p_login||'" is not unique');
                ELSE
                    RAISE;
                END IF;
        END;

        -- set the password
        IF (p_password IS NOT NULL) THEN
            set_password(p_login_id, p_password, FALSE, TRUE);
        END IF;

        plog.notice(S_PREFIX||'created login id  "'||p_login_id||'" for login "'||p_login||'"');

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);
            RAISE;

    END insert_login;

    -----------------------------------------------------------------------------
    -- insert_login_sync: Inserts a new login synchronized from Active Directory
    -----------------------------------------------------------------------------
    PROCEDURE insert_login_sync(p_contact_id OUT stop.passport_contact.id%TYPE, p_login_id OUT passport_login.id%TYPE, p_login passport_login.login%TYPE,
                                p_homeauthhost_id authhost.id%TYPE, p_maxretries passport_login.maxretries%TYPE,
                                p_passwordtype_id passport_login.passwordtype_id%TYPE, p_password VARCHAR2,
                                p_passwordexpiryoffset authsys.passwordexpiryoffset%TYPE,
                                p_twofactorenabled passport_login.twofactorenabled%TYPE, p_locked passport_login.locked%TYPE,
                                p_firstname stop.passport_contact.firstname%TYPE, p_lastname stop.passport_contact.lastname%TYPE,
                                p_direct stop.passport_contact.direct%TYPE, p_mobile stop.passport_contact.mobile%TYPE, p_home stop.passport_contact.home%TYPE,
                                p_fax stop.passport_contact.fax%TYPE, p_email stop.passport_contact.email%TYPE, p_authemail auth.passport_login.email%TYPE, p_syncdomain_id auth.syncdomain.id%TYPE,
                                p_synctype auth.synctype.short%TYPE, p_sid stop.passport_contact_sync.sid%TYPE,
                                p_guid stop.passport_contact_sync.guid%TYPE, p_domain stop.passport_contact_sync.domain%TYPE,
                                p_usnchanged stop.passport_contact_sync.usnchanged%TYPE, p_cost_center_id mss.cost_center.id%TYPE DEFAULT NULL,
                                p_function stop.passport_contact.function%TYPE DEFAULT NULL, p_merge NUMBER DEFAULT 0, p_comments stop.passport_contact.comments%TYPE DEFAULT NULL,
                                p_authtype_id auth.authtype.id%TYPE, p_smsauthnumber passport_login.smsauthnumber%TYPE, p_softtokenseed token.seed%TYPE DEFAULT NULL,
                                p_softtokenexpiry VARCHAR2 DEFAULT NULL, p_softtoken_validfrom VARCHAR2 DEFAULT NULL) IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.insert_login_sync(): ';

        v_company_id stop.company.id%TYPE;
        v_autoemailaliasesenabled authsys.autoemailaliasesenabled%TYPE;
        v_token_id token.id%TYPE;
        v_tokenserial token.serial%TYPE;
        v_login passport_login%ROWTYPE;
        v_contact stop.passport_contact%ROWTYPE;
        v_authemail auth.passport_login.email%TYPE;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);

        -- retrieve company_id by way of the authhost
        SELECT company_id, authsys.autoemailaliasesenabled INTO v_company_id, v_autoemailaliasesenabled FROM authsys, syncdomain
        WHERE authsys.id = syncdomain.authsys_id
          AND syncdomain.id = p_syncdomain_id;

        BEGIN

            insert_login(p_login_id, p_login, p_passwordtype_id, NULL, p_twofactorenabled, NULL, NULL, p_homeauthhost_id,
                         p_locked, p_maxretries, p_firstname, p_lastname, p_direct, p_mobile, p_home, p_fax, p_email, p_authemail, v_company_id,
                         0, NULL, p_cost_center_id, p_function, p_comments, p_authtype_id, p_smsauthnumber);

            IF (p_password IS NOT NULL) THEN
                set_password(p_login_id, p_password, TRUE, TRUE, p_passwordexpiryoffset, FALSE);
            END IF;

            IF (p_softtokenseed IS NOT NULL) THEN
                add_softtoken(v_token_id, v_tokenserial, v_company_id, TO_DATE(p_softtokenexpiry,'DD-MM-YYYY'), p_softtokenseed, TO_DATE(p_softtoken_validfrom,'DD-MM-YYYY'));
                -- softToken created, assign to current user
                UPDATE passport_login SET token_id=v_token_id WHERE id=p_login_id;
                plog.notice(S_PREFIX||'assigned token "'||v_tokenserial||'" to login "'||p_login||'" ('||p_login_id||')');
            END IF;

            -- Note: there should not come a duplicate_email email exception any more, see Issue AUT-105
        EXCEPTION
            WHEN OSAG_AUTH_STATE.duplicate_login OR OSAG_AUTH_STATE.duplicate_email THEN

                -- here is the merge switch
                ----------------------------------
                IF (p_merge != 0) THEN
                    plog.notice('encountered non-unique login '''||p_login||''' when ''merge'' flag set');

                    -- select the duplicate login / contact ID. Exclude any records that are associated
                    -- with a different home auth host or sync domain. This should also get rid of
                    -- multiple rows.

                    -- Note: sc.email will not be a collision condition any more, see Isse AUT-105
                    BEGIN
                        SELECT l.* INTO v_login FROM passport_login l, stop.passport_contact sc
                        WHERE (LOWER(l.login) = LOWER(p_login))
                          AND l.homeauthhost_id = p_homeauthhost_id
                          AND l.contact_id = sc.id
                        MINUS
                        SELECT l.* FROM passport_login l, stop.passport_contact_sync scs
                        WHERE LOWER(l.login) = LOWER(p_login)
                          AND l.homeauthhost_id = p_homeauthhost_id
                          AND l.contact_id = scs.contact_id;

                        -- now that we have login / contact ID, we try to update it as per the same strategy as
                        -- used in update_login_sync (select all the current values and only change the values
                        -- that are 'syncable'). It's somewhat unfortunate that I can't call update_login_sync()
                        -- but that function relies on the fact that a stop.passport_contact_sync row already exists.
                        -- If all goes we'll, we continue below with inserting the stop.passport_contact_sync row.
                        SELECT * INTO v_contact FROM stop.passport_contact
                        WHERE v_login.contact_id = id;

                        p_contact_id := v_contact.id;
                        p_login_id := v_login.id;
                        v_authemail := v_login.email;

                        plog.notice('found eligible login ID '''||p_login_id||''', contact ID '''||p_contact_id||''' to merge with');

                        -- Note: the p_authemail unique constraint logic is handled in a higher level (Perl code), see Issue AUT-105
                        update_login(v_login.id, p_login, p_passwordtype_id, NULL, v_login.twofactorenabled, v_login.token_id, v_login.replacementtoken_id,
                                     v_login.homeauthhost_id, v_login.locked, v_login.maxretries, p_firstname, p_lastname, p_direct, p_mobile, p_home, p_fax, NVL(p_email,
                                                                                                                                                                  v_contact.email), v_authemail, v_contact.company_id, v_login.anytunnelgroup, v_login.passwordexpiry, p_cost_center_id, p_function, p_comments, p_smsauthnumber);

                    EXCEPTION
                        WHEN no_data_found THEN
                            RAISE_APPLICATION_ERROR(OSAG_AUTH_STATE.S_ERRNO_DUPLICATE_LOGIN, 'duplicate login "'||p_login||'" doesn''t qualify for merging (assigned to different authhost or sync domain)');
                        WHEN OTHERS THEN
                            RAISE;
                    END;

                ELSE
                    RAISE;
                END IF;

            WHEN OTHERS THEN
                RAISE;


        END;

        SELECT contact_id INTO p_contact_id FROM passport_login
        WHERE id = p_login_id;


        INSERT INTO stop.passport_contact_sync (contact_id, syncdomain_id, synctype_id, sid, guid, domain, usnchanged)
        VALUES (p_contact_id, p_syncdomain_id, (SELECT id FROM auth.synctype WHERE short = p_synctype),
                p_sid, p_guid, p_domain, p_usnchanged);

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);
            RAISE;

    END insert_login_sync;

    -----------------------------------------------------------------------------
    -- insert_login_sync2: Inserts a new login synchronized from external source (AUT-927: with distinguishedname)
    -----------------------------------------------------------------------------
    PROCEDURE insert_login_sync2(p_contact_id OUT stop.passport_contact.id%TYPE, p_login_id OUT passport_login.id%TYPE, p_login passport_login.login%TYPE,
                                 p_homeauthhost_id authhost.id%TYPE, p_maxretries passport_login.maxretries%TYPE,
                                 p_passwordtype_id passport_login.passwordtype_id%TYPE, p_password VARCHAR2,
                                 p_passwordexpiryoffset authsys.passwordexpiryoffset%TYPE,
                                 p_twofactorenabled passport_login.twofactorenabled%TYPE, p_locked passport_login.locked%TYPE,
                                 p_firstname stop.passport_contact.firstname%TYPE, p_lastname stop.passport_contact.lastname%TYPE,
                                 p_direct stop.passport_contact.direct%TYPE, p_mobile stop.passport_contact.mobile%TYPE, p_home stop.passport_contact.home%TYPE,
                                 p_fax stop.passport_contact.fax%TYPE, p_email stop.passport_contact.email%TYPE, p_authemail auth.passport_login.email%TYPE, p_syncdomain_id auth.syncdomain.id%TYPE,
                                 p_synctype auth.synctype.short%TYPE, p_sid stop.passport_contact_sync.sid%TYPE,
                                 p_guid stop.passport_contact_sync.guid%TYPE, p_domain stop.passport_contact_sync.domain%TYPE,
                                 p_usnchanged stop.passport_contact_sync.usnchanged%TYPE, p_cost_center_id mss.cost_center.id%TYPE DEFAULT NULL,
                                 p_function stop.passport_contact.function%TYPE DEFAULT NULL, p_merge NUMBER DEFAULT 0, p_comments stop.passport_contact.comments%TYPE DEFAULT NULL,
                                 p_authtype_id auth.authtype.id%TYPE, p_smsauthnumber passport_login.smsauthnumber%TYPE, p_softtokenseed token.seed%TYPE DEFAULT NULL,
                                 p_softtokenexpiry VARCHAR2 DEFAULT NULL, p_softtoken_validfrom VARCHAR2 DEFAULT NULL,
                                 p_distinguishedname stop.passport_contact_sync.distinguishedname%TYPE DEFAULT NULL) IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.insert_login_sync2(): ';

        v_company_id stop.company.id%TYPE;
        v_autoemailaliasesenabled authsys.autoemailaliasesenabled%TYPE;
        v_token_id token.id%TYPE;
        v_tokenserial token.serial%TYPE;
        v_login passport_login%ROWTYPE;
        v_contact stop.passport_contact%ROWTYPE;
        v_authemail auth.passport_login.email%TYPE;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);

        -- retrieve company_id by way of the authhost
        SELECT company_id, authsys.autoemailaliasesenabled INTO v_company_id, v_autoemailaliasesenabled FROM authsys, syncdomain
        WHERE authsys.id = syncdomain.authsys_id
          AND syncdomain.id = p_syncdomain_id;

        BEGIN
            insert_login(p_login_id, p_login, p_passwordtype_id, NULL, p_twofactorenabled, NULL, NULL, p_homeauthhost_id,
                         p_locked, p_maxretries, p_firstname, p_lastname, p_direct, p_mobile, p_home, p_fax, p_email, p_authemail, v_company_id,
                         0, NULL, p_cost_center_id, p_function, p_comments, p_authtype_id, p_smsauthnumber);

            IF (p_password IS NOT NULL) THEN
                set_password(p_login_id, p_password, TRUE, TRUE, p_passwordexpiryoffset, FALSE);
            END IF;

            IF (p_softtokenseed IS NOT NULL) THEN
                add_softtoken(v_token_id, v_tokenserial, v_company_id, TO_DATE(p_softtokenexpiry,'DD-MM-YYYY'), p_softtokenseed, TO_DATE(p_softtoken_validfrom,'DD-MM-YYYY'));
                -- softToken created, assign to current user
                UPDATE passport_login SET token_id=v_token_id WHERE id=p_login_id;
                plog.notice(S_PREFIX||'assigned token "'||v_tokenserial||'" to login "'||p_login||'" ('||p_login_id||')');
            END IF;

            -- Note: there should not come a duplicate_email email exception any more, see Issue AUT-105
        EXCEPTION
            WHEN OSAG_AUTH_STATE.duplicate_login OR OSAG_AUTH_STATE.duplicate_email THEN

                -- here is the merge switch
                ----------------------------------
                IF (p_merge != 0) THEN
                    plog.notice('encountered non-unique login '''||p_login||''' when ''merge'' flag set');

                    -- select the duplicate login / contact ID. Exclude any records that are associated
                    -- with a different home auth host or sync domain. This should also get rid of
                    -- multiple rows.
                    -- Note: sc.email will not be a collision condition any more, see Isse AUT-105
                    BEGIN
                        SELECT l.* INTO v_login FROM passport_login l, stop.passport_contact sc
                        WHERE (LOWER(l.login) = LOWER(p_login))
                          AND l.homeauthhost_id = p_homeauthhost_id
                          AND l.contact_id = sc.id
                        MINUS
                        SELECT l.* FROM passport_login l, stop.passport_contact_sync scs
                        WHERE LOWER(l.login) = LOWER(p_login)
                          AND l.homeauthhost_id = p_homeauthhost_id
                          AND l.contact_id = scs.contact_id;

                        -- now that we have login / contact ID, we try to update it as per the same strategy as
                        -- used in update_login_sync (select all the current values and only change the values
                        -- that are 'syncable'). It's somewhat unfortunate that I can't call update_login_sync()
                        -- but that function relies on the fact that a stop.passport_contact_sync row already exists.
                        -- If all goes we'll, we continue below with inserting the stop.passport_contact_sync row.
                        SELECT * INTO v_contact FROM stop.passport_contact
                        WHERE v_login.contact_id = id;

                        p_contact_id := v_contact.id;
                        p_login_id := v_login.id;
                        v_authemail := v_login.email;

                        plog.notice('found eligible login ID '''||p_login_id||''', contact ID '''||p_contact_id||''' to merge with');

                        -- Note: the p_authemail unique constraint logic is handled in a higher level (Perl code), see Issue AUT-105
                        update_login(v_login.id, p_login, p_passwordtype_id, NULL, v_login.twofactorenabled, v_login.token_id, v_login.replacementtoken_id,
                                     v_login.homeauthhost_id, v_login.locked, v_login.maxretries, p_firstname, p_lastname, p_direct, p_mobile, p_home, p_fax, NVL(p_email,
                                                                                                                                                                  v_contact.email), v_authemail, v_contact.company_id, v_login.anytunnelgroup, v_login.passwordexpiry, p_cost_center_id, p_function, p_comments, p_smsauthnumber);

                    EXCEPTION
                        WHEN no_data_found THEN
                            RAISE_APPLICATION_ERROR(OSAG_AUTH_STATE.S_ERRNO_DUPLICATE_LOGIN, 'duplicate login "'||p_login||'" doesn''t qualify for merging (assigned to different authhost or sync domain)');
                        WHEN OTHERS THEN
                            RAISE;
                    END;

                ELSE
                    RAISE;
                END IF;
            WHEN OTHERS THEN
                RAISE;
        END;

        SELECT contact_id INTO p_contact_id FROM passport_login
        WHERE id = p_login_id;

        INSERT INTO stop.passport_contact_sync (contact_id, syncdomain_id, synctype_id, sid, guid, domain, usnchanged, distinguishedname)
        VALUES (p_contact_id, p_syncdomain_id, (SELECT id FROM auth.synctype WHERE short = p_synctype),
                p_sid, p_guid, p_domain, p_usnchanged, p_distinguishedname);

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);
            RAISE;
    END insert_login_sync2;

    -----------------------------------------------------------------------------
    -- is_dirty: Returns dirty status of an authentication system
    -----------------------------------------------------------------------------
    FUNCTION is_dirty(p_authsys_id authsys.id%TYPE) RETURN NUMBER IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.is_dirty(): ';

        CURSOR c_dirtyauthhost IS
            SELECT (login + token + groups + login2groups + tunnelgroup + login2tunnelgroup + alias) dirty
            FROM dirtyauthhost
            WHERE authhost_id IN (SELECT authhost_id
                                  FROM authhost2authsys
                                  WHERE authsys_id = p_authsys_id);

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        FOR r_dirtyauthhost IN c_dirtyauthhost LOOP
                IF (r_dirtyauthhost.dirty != 0) THEN
                    RETURN(1);
                END IF;
            END LOOP;

        RETURN(0);

    EXCEPTION

        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);
            RAISE;

    END is_dirty;

    -----------------------------------------------------------------------------
    -- lock_login: lock a login
    -----------------------------------------------------------------------------
    PROCEDURE lock_login(p_login_id passport_login.id%TYPE) IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.lock_login(): ';

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        UPDATE passport_login
        SET locked = 1
        WHERE id = p_login_id;

        IF (SQL%NOTFOUND) THEN
            plog.err(S_PREFIX||'failed to lock login id "'||p_login_id||'"');
            RAISE NO_DATA_FOUND;
        ELSE
            plog.notice(S_PREFIX||'locked login id "'||p_login_id);
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);
            RAISE;

    END lock_login;

    -----------------------------------------------------------------------------
    -- set_authsys_dirty: sets an entire authentication system to dirty status
    -----------------------------------------------------------------------------
    PROCEDURE set_authsys_dirty(p_authsys_id authsys.id%TYPE) IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.set_authsys_dirty(): ';

        v_authhost_id authhost2authsys.authhost_id%TYPE;

        CURSOR c_authhost2authsys IS
            SELECT authhost_id
            FROM authhost2authsys
            WHERE authsys_id = p_authsys_id;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- set all dirty bits of this authsys to 1
        FOR r_authhost2authsys IN c_authhost2authsys LOOP
                UPDATE dirtyauthhost
                SET login = 1, token = 1, groups = 1, login2groups = 1, tunnelgroup = 1, login2tunnelgroup = 1, alias = 1
                WHERE authhost_id = r_authhost2authsys.authhost_id;

                IF (SQL%FOUND) THEN
                    plog.debug(S_PREFIX||'set authhost id "'||r_authhost2authsys.authhost_id||'" ('||p_authsys_id||') to dirty');
                ELSE
                    INSERT INTO dirtyauthhost (authhost_id, login, token, groups, login2groups, tunnelgroup, login2tunnelgroup, alias)
                    VALUES (r_authhost2authsys.authhost_id, 1, 1, 1, 1, 1, 1, 1);
                END IF;
            END LOOP;

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);
            RAISE;

    END set_authsys_dirty;

    -----------------------------------------------------------------------------
    -- set_password: set a login's password
    -----------------------------------------------------------------------------
    PROCEDURE set_password(p_login_id passport_login.id%TYPE, p_password VARCHAR2,
                           p_update_password_expiry BOOLEAN DEFAULT FALSE,
                           p_update_recent_password BOOLEAN DEFAULT TRUE,
                           p_password_expiry_offset authsys.passwordexpiryoffset%TYPE DEFAULT NULL,
                           p_check_password BOOLEAN DEFAULT FALSE) IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.set_password(): ';

        v_passwordexpiry DATE;
        v_passwordexpiryoffset AUTHSYS.PASSWORDEXPIRYOFFSET%TYPE;
        v_passwordexpiryenabled AUTHSYS.PASSWORDEXPIRYENABLED%TYPE;
        v_password_hash PASSPORT_LOGIN.PWHASH%TYPE;
        v_salt passport_login.SALT%TYPE;

        v_version PASSPORT_RECENTPASSWORD.VERSION%TYPE;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- generate a new salt and a hash of the salt and password
        v_salt := lower(rawtohex(DBMS_CRYPTO.RANDOMBYTES(32)));
        v_password_hash := hash_password(p_password, v_salt);

        UPDATE passport_login
        SET salt = v_salt,
            pwhash = v_password_hash,
            lastpwchange = SYSDATE
        WHERE id = p_login_id;

        IF (p_update_password_expiry) THEN
            IF (p_password_expiry_offset IS NOT NULL) THEN
                v_passwordexpiry := SYSDATE + p_password_expiry_offset / (24 * 60 * 60);
            ELSE
                -- update the password expiry date for this login according to the
                -- authsys offset setting
                SELECT l.passwordexpiry, authsys.passwordexpiryoffset, authsys.passwordexpiryenabled INTO v_passwordexpiry, v_passwordexpiryoffset, v_passwordexpiryenabled
                FROM auth.passport_login l, auth.authhost2authsys h2a, auth.authsys
                WHERE l.id = p_login_id
                  AND l.homeauthhost_id = h2a.authhost_id
                  AND h2a.authsys_id = authsys.id;

                -- password expiry is set explicitly to 'never expire'
                -- in case password expiration is not enabled for the authsys
                IF (v_passwordexpiryenabled = 0) THEN
                    v_passwordexpiry := NULL;

                    -- update the password expiry in according authsys if
                    -- * the current expiry is not null (i.e. do not touch never expiries)
                    -- * the configured offset is not null and greater than 0
                ELSIF (v_passwordexpiry IS NOT NULL AND v_passwordexpiryoffset IS NOT NULL
                    AND v_passwordexpiryoffset > 0) THEN
                    -- v_passwordexpiryoffset is in seconds, convert to days
                    v_passwordexpiry := SYSDATE + v_passwordexpiryoffset / (24 * 60 * 60);
                END IF;
            END IF;

            UPDATE passport_login
            SET passwordexpiry = v_passwordexpiry
            WHERE id = p_login_id;
            plog.notice(S_PREFIX||'updated password expiry for login id "'||p_login_id||'" to ' || v_passwordexpiry);
        END IF;

        IF (p_update_recent_password) THEN
            -- add an entry to the recent password table for this login containing the
            -- new password using a new version number
            SELECT NVL(MAX(version), 0) + 1 INTO v_version
            FROM passport_recentpassword
            WHERE login_id = p_login_id;

            INSERT INTO passport_recentpassword (id, login_id, password, version, salt)
            VALUES (seq_recentpassword_id.nextval, p_login_id, v_password_hash, v_version, v_salt);

            -- clean up older passwords (keep up to 5 passwords)
            DELETE FROM passport_recentpassword
            WHERE login_id = p_login_id
              AND version < (v_version-4);
        END IF;

        plog.notice(S_PREFIX||'updated password for login id "'||p_login_id||'"');

    EXCEPTION
        WHEN OTHERS THEN
            IF (sqlcode = -00001) THEN
                plog.err(S_PREFIX||'login id "'||p_login_id||'" is not unique:: '||sqlerrm);
                RAISE_APPLICATION_ERROR(OSAG_AUTH_STATE.S_ERRNO_DUPLICATE_LOGIN, 'login id "'||p_login_id||'" is not unique');
            ELSE
                plog.err(S_PREFIX||'caught exception: '||sqlerrm);
                RAISE;
            END IF;

    END set_password;

    -----------------------------------------------------------------------------
    -- update_authsys: update an authentication system
    -----------------------------------------------------------------------------
    PROCEDURE update_authsys(p_authsys_id authsys.id%TYPE) IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.update_authsys(): ';

        S_COMMAND CONSTANT VARCHAR2(128) := OSAG_AUTH_STATE.C_OSAG_AUTHSYNC_HOME||'/bin/update_authsys --config '||
                                            OSAG_AUTH_STATE.C_OSAG_AUTHSYNC_HOME||'/etc/update_authsys.conf '||p_authsys_id;

        S_PROXY_COMMAND CONSTANT VARCHAR2(256) := OSAG_AUTH_STATE.GET_JUMP_SSH_CALL||OSAG_AUTH_STATE.C_OSAG_AUTHSYNC_HOME||'/bin/update_authsys --config '||
                                                  OSAG_AUTH_STATE.C_OSAG_AUTHSYNC_HOME||'/etc/update_authsys.conf '||p_authsys_id||'"';

        v_exit NUMBER;
        v_output VARCHAR2(2048);
        v_name authsys.name%TYPE;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        select name into v_name from authsys where id = p_authsys_id;

        OSAG_EXT.runOsCmdGetResult(S_PROXY_COMMAND, 512, v_output, v_exit);

        -- trim leading / trailing spaces and cr
        v_output := ltrim(rtrim(v_output, ' '||chr(10)||chr(13)), ' '||chr(10)||chr(13));

        IF (v_exit != 0) THEN
          if v_output is null or length(v_output) = 0 then
            -- update_authsys errors without message: check known exit codes
            if v_exit = 1 then
              v_output := 'exit code 1: No update of authentication system '||v_name||': No active hosts';
            elsif v_exit = -1 then
              v_output := 'exit code -1: Update of authentication system '||v_name||' failed: internal error.';
            elsif v_exit = -2 then
              v_output := 'exit code -2: Update of authentication system '||v_name||' failed: initialization error.';
            elsif v_exit = -3 then
              v_output := 'exit code -3: Update of authentication system '||v_name||' failed: database error.';
            elsif v_exit = -4 then
              v_output := 'exit code -4: Update of authentication system '||v_name||' failed: data dump error.';
            elsif v_exit = -5 then
              v_output := 'exit code -5: Update of authentication system  '||v_name||' failed: synchronization error.';
            elsif v_exit = -6 then
              v_output := 'exit code -6: Update of authentication system  '||v_name||' failed for some passport servers.';
            elsif v_exit = 254 then
              v_output := 'exit code 254: Update of authentication system  '||v_name||' failed: signal received (likely timeout or kill).';
            elsif v_exit = 255 then
              v_output := 'exit code 255: Update of authentication system  '||v_name||' failed: config error.';
            else
              v_output := 'unknown exit code '||v_exit||' from update_authsys for authentication system '|| v_name ||', check /var/log/messages on auth host';
            end if;
          end if;
        END IF;

        -- detect a partial update (exit code is -6, comes as 250)
        IF (v_exit = 250) THEN
            plog.notice(S_PREFIX||'update failed partly for authsys id "'||p_authsys_id||'"');
            RAISE_APPLICATION_ERROR(OSAG_AUTH_STATE.S_ERRNO_AUTHSYS_UPDATE_PARTIAL, v_output);
        ELSIF (v_exit = 1) THEN
            RAISE_APPLICATION_ERROR(OSAG_AUTH_STATE.S_ERRNO_AUTHSYS_UPDATE_WARNING, v_output);
        ELSIF (v_exit != 0) THEN
            RAISE_APPLICATION_ERROR(OSAG_AUTH_STATE.S_ERRNO_AUTHSYS_UPDATE_FAILED, v_output);
        END IF;

        plog.notice(S_PREFIX||'updated authsys id "'||p_authsys_id||'"');

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);
            RAISE;

    END update_authsys;

    -----------------------------------------------------------------------------
    -- update_authsys_for_login: update the authentication system the login
    -- belongs to
    -----------------------------------------------------------------------------
    PROCEDURE update_authsys_for_login(p_login_id passport_login.id%TYPE) IS
        v_authsys_id authsys.id%TYPE;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        SELECT h2a.authsys_id INTO v_authsys_id
        FROM auth.passport_login l, auth.authhost2authsys h2a
        WHERE l.id = p_login_id AND l.homeauthhost_id = h2a.authhost_id;

        update_authsys(v_authsys_id);
    END update_authsys_for_login;

    -----------------------------------------------------------------------------
    -- sync_domain: synchronize a sync domain
    -----------------------------------------------------------------------------
    PROCEDURE sync_domain(p_syncdomain_id syncdomain.id%TYPE, p_scheduled BOOLEAN DEFAULT FALSE,
                          p_force BOOLEAN DEFAULT FALSE) IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.sync_domain(): ';

        S_COMMAND CONSTANT VARCHAR2(128) := OSAG_AUTH_STATE.C_OSAG_AUTHSYNC_HOME||'/bin/authsync --config '||
                                            OSAG_AUTH_STATE.C_OSAG_AUTHSYNC_HOME||'/etc/authsync.conf -D';

        v_exit NUMBER;
        v_output VARCHAR2(512);
        v_command VARCHAR2(128) := S_COMMAND;
        v_proxy_command VARCHAR2(512);
        v_short SYNCDOMAIN.SHORT%TYPE;

        e_external_cmd_timed_out EXCEPTION;
        PRAGMA EXCEPTION_INIT (e_external_cmd_timed_out, -20103);
    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);

        select short into v_short from AUTH.SYNCDOMAIN d where d.id = p_syncdomain_id;

        IF (p_scheduled) THEN
            v_command := v_command||' -S';
        END IF;

        IF (p_force) THEN
            v_command := v_command|| ' -f';
        END IF;

        v_command := v_command||' '||p_syncdomain_id ||'"';
        v_proxy_command := OSAG_AUTH_STATE.GET_JUMP_SSH_CALL|| v_command;

        -- switched below lines to activate proxying of commands to mgmt server
        -- OSAG_EXT.runOsCmdGetResult(v_command, 512, v_output, v_exit);
        OSAG_EXT.runOsCmdGetResult(v_proxy_command, 512, v_output, v_exit);

        -- trim leading / trailing spaces and cr
        v_output := ltrim(rtrim(v_output, ' '||chr(10)||chr(13)), ' '||chr(10)||chr(13));

        IF (v_exit != 0) THEN
            if v_output is null or length(v_output) = 0 then
              -- syncdump errors without message: check known exit codes
              if v_exit = 1 then
                v_output := 'exit code 1: syncdump config error, check /var/log/messages on auth host';
              elsif v_exit = 2 then
                v_output := 'exit code 2: syncdump LDAP problem, check /var/log/messages on auth host';
              elsif v_exit = 3 then
                v_output := 'exit code 3: syncdump can not resolve DC/GC, check /var/log/messages on auth host';
              elsif v_exit = 4 then
                v_output := 'exit code 4: syncdump could not contact any DC/GC, check /var/log/messages on auth host';
              elsif v_exit = 5 then
                v_output := 'exit code 5: syncdump timeout, check /var/log/messages on auth host';
              elsif v_exit = 255 then
                v_output := 'exit code 255: authsync communication error, auth host reachable?';
              else
                v_output := 'unknown exit code '||v_exit||', check /var/log/messages on auth host';
              end if;
            end if;

            if v_output like 'Could not get an exclusive lock for authsys%' then
              RAISE_APPLICATION_ERROR(OSAG_AUTH_STATE.S_ERRNO_AUTHSYS_UPDATE_WARNING, v_output);
            end if;

            RAISE_APPLICATION_ERROR(OSAG_AUTH_STATE.S_ERRNO_DOMAIN_SYNC_FAILED, v_output);
        END IF;

        plog.notice(S_PREFIX||'synchronized domain id "'||p_syncdomain_id||'"');

    EXCEPTION
        WHEN OSAG_AUTH_STATE.authsys_update_warning THEN
            -- sync is already running, ignore
            plog.notice(S_PREFIX||'caught exception in authsys '|| v_short ||': '||sqlerrm);
            null;
        WHEN e_external_cmd_timed_out THEN
            RAISE;
        WHEN OTHERS THEN
            -- no log/ticket: interactive callers will get the exception, scheduler has its own log
            RAISE;

    END sync_domain;

    -----------------------------------------------------------------------------
    -- sync_domain_scheduler: scheduler for domain synchronization
    -----------------------------------------------------------------------------
    PROCEDURE sync_domain_scheduler IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.sync_domain_scheduler(): ';
        v_backoff_wait NUMBER := 0;
        v_runattempt NUMBER := 0;
        v_last_return_code NUMBER := 0;
        v_last_err_msg VARCHAR(4000) := '';
        e_external_cmd_timed_out EXCEPTION;
    --  S_ERRNO_EXTERNAL_CMD_TIMEOUT CONSTANT NUMBER := -20103;
        PRAGMA EXCEPTION_INIT (e_external_cmd_timed_out, -20103);

        CURSOR c_syncdomain IS
            SELECT * FROM syncdomain WHERE syncperiod IS NOT NULL AND SYNCPERIOD > 0;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        FOR r_syncdomain IN c_syncdomain LOOP
                IF ((r_syncdomain.nextrun IS NULL) OR (r_syncdomain.nextrun <= systimestamp)) THEN
                    IF (r_syncdomain.nextrun IS NULL) THEN
                        plog.notice('started initial synchronization for domain '||r_syncdomain.id);
                    ELSE
                        plog.notice('started synchronization for domain '||r_syncdomain.id||' scheduled at '||
                                    TO_CHAR(r_syncdomain.nextrun, 'YYYY-MM-DD HH24:MI:SS TZH:TZM'));
                    END IF;

                    BEGIN
                        v_last_err_msg := '';
                        v_last_return_code := 0;
                        v_backoff_wait := 0;
                        v_runattempt := 0;
                        OSAG_AUTH_PASSPORT.sync_domain(r_syncdomain.id, true);
                        OSAG_AUTH_PASSPORT.update_authsys(r_syncdomain.authsys_id);
                    EXCEPTION
                        WHEN OSAG_AUTH_STATE.domain_sync_failed THEN
                            -- already logged
                            v_runattempt := r_syncdomain.RUN_ATTEMPT + 1;

                        WHEN e_external_cmd_timed_out THEN BEGIN
                            -- simply retry after a while
                            v_last_err_msg := SQLERRM;
                            v_last_return_code := SQLCODE;
                            v_runattempt := r_syncdomain.RUN_ATTEMPT + 1;
                            IF (COALESCE(r_syncdomain.RUN_ATTEMPT,0) = COALESCE(r_syncdomain.MAX_ATTEMPT,0))
                                -- this was the last allowed attempt
                                THEN
                                plog.err(S_PREFIX||'No further retry of ' || r_syncdomain.DESCRIPTION || ' permitted after caught exception: '||sqlerrm);
                            ELSIF (COALESCE(r_syncdomain.RUN_ATTEMPT,0) = 0)
                                -- this was the first attempt
                                THEN
                                IF (r_syncdomain.SYNCPERIOD >3600)
                                    -- syncperiod is in the order of days
                                    THEN
                                    v_backoff_wait := 3600; -- try again in one hour
                                ELSE
                                    -- try again after timeout (can be 0), but at least 6 minutes
                                    v_backoff_wait := GREATEST(r_syncdomain.TIMEOUT, 360);
                                end if;
                            ELSE
                                -- try again after an increased timeout, min. 6, maximum 60 minutes
                                v_backoff_wait := LEAST(GREATEST(r_syncdomain.RUN_ATTEMPT * r_syncdomain.TIMEOUT, 360), 3600);
                            end if;
                        end;
                        WHEN OTHERS THEN
                            v_last_err_msg := SQLERRM;
                            v_last_return_code := SQLCODE;
                            v_runattempt := r_syncdomain.RUN_ATTEMPT + 1;
                            plog.err(S_PREFIX||'caught exception while running ' || r_syncdomain.DESCRIPTION || ': '||sqlerrm);
                    END;

                    -- re-read nextrun from the database; the value in r_syncdomain is stale
                    -- (read before sync_domain() was called and may have been modified during the sync run)
                    SELECT nextrun INTO r_syncdomain.nextrun FROM AUTH.syncdomain WHERE id = r_syncdomain.id;

                    -- make sure that we the next scheduled time is actually in the future (in case
                    -- we've missed the last scheduled run for some reason). The easier solution of
                    -- adding syncperiod to systimestamp doesn't work as we want to maintain a defined
                    -- offset to the intial schedule without drifting due to script execution times
                    -- and other scheduling artefacts.
                    WHILE (NVL(r_syncdomain.nextrun, systimestamp) <= systimestamp) LOOP
                        -- when dealing with datetimes with timezones, it's important to use interval based
                        -- arithmetic and not the more idiomatic day fractions (e.g. `+86400/r_syncdomain.syncperiod')
                        -- because the latter seems to lose the original TZ information and assumes the session TZ for
                        -- the result. This is a problem if the procedure is called from a system session, e.g. as
                        -- a DBA job. Interval based arithmetic doesn't seem to have this issue. Don't ask me,
                        -- im only stabbing around in the dark....
                        if v_backoff_wait > 0 then
                          r_syncdomain.nextrun := systimestamp +  NUMTODSINTERVAL(v_backoff_wait, 'SECOND');
                        else
                          r_syncdomain.nextrun := NVL(r_syncdomain.nextrun, systimestamp)
                            + NUMTODSINTERVAL(r_syncdomain.syncperiod, 'SECOND');
                        end if;
                    END LOOP;

                    UPDATE AUTH.syncdomain
                    SET nextrun = r_syncdomain.nextrun,
                        LAST_RESULTCODE = v_last_return_code,
                        LAST_RESULTMSG  = v_last_err_msg,
                        RUN_ATTEMPT     = v_runattempt
                    WHERE id = r_syncdomain.id;

                    plog.notice('next synchronization for domain '||r_syncdomain.id||' scheduled at '||
                                TO_CHAR(r_syncdomain.nextrun, 'YYYY-MM-DD HH24:MI:SS TZH:TZM'));
                END IF;

                COMMIT;
            END LOOP;

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);
            RAISE;

    END sync_domain_scheduler;

    -----------------------------------------------------------------------------
    -- unlock_login: lock a login
    -----------------------------------------------------------------------------
    PROCEDURE unlock_login(p_login_id passport_login.id%TYPE) IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.unlock_login(): ';

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        UPDATE passport_login
        SET locked = 0
        WHERE id = p_login_id;

        IF (SQL%NOTFOUND) THEN
            plog.err(S_PREFIX||'failed to unlock login id "'||p_login_id||'"');
            RAISE NO_DATA_FOUND;
        ELSE
            plog.notice(S_PREFIX||'unlocked login id "'||p_login_id);
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);
            RAISE;

    END unlock_login;

    -----------------------------------------------------------------------------
    -- update_login: Updates a login
    -----------------------------------------------------------------------------
    PROCEDURE update_login(p_login_id passport_login.id%TYPE, p_login passport_login.login%TYPE, p_passwordtype_id passwordtype.id%TYPE,
                           p_password VARCHAR2, p_twofactorenabled passport_login.twofactorenabled%TYPE,
                           p_token_id token.id%TYPE, p_replacementtoken_id token.id%TYPE, p_homeauthhost_id authhost.id%TYPE,
                           p_locked passport_login.locked%TYPE, p_maxretries passport_login.maxretries%TYPE, p_firstname stop.passport_contact.firstname%TYPE,
                           p_lastname stop.passport_contact.lastname%TYPE, p_direct stop.passport_contact.direct%TYPE, p_mobile stop.passport_contact.mobile%TYPE,
                           p_home stop.passport_contact.home%TYPE, p_fax stop.passport_contact.fax%TYPE, p_email stop.passport_contact.email%TYPE, p_authemail auth.passport_login.email%TYPE,
                           p_company_id stop.company.id%TYPE DEFAULT NULL, p_anytunnelgroup passport_login.anytunnelgroup%TYPE DEFAULT 0,
                           p_passwordexpiry passport_login.passwordexpiry%TYPE DEFAULT NULL,
                           p_cost_center_id mss.cost_center.id%TYPE DEFAULT NULL, p_function stop.passport_contact.function%TYPE DEFAULT NULL, p_comments stop.passport_contact.comments%TYPE DEFAULT NULL,
                           p_smsauthnumber passport_login.smsauthnumber%TYPE) IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.update_login(): ';

        v_contact_id stop.passport_contact.id%TYPE;
        v_homeauthhost_id passport_login.homeauthhost_id%TYPE;
        v_login passport_login.login%TYPE;
        v_email stop.passport_contact.email%TYPE;
        v_cost_center_company stop.company.id%TYPE;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        IF (p_login_id IS NULL) THEN
            RAISE value_error;
        END IF;

        -- Fetch current data
        SELECT login, contact_id, homeauthhost_id, sc.email
        INTO v_login, v_contact_id, v_homeauthhost_id, v_email
        FROM passport_login l, stop.passport_contact sc
        WHERE l.id = p_login_id
          AND l.contact_id = sc.id;

        BEGIN
            -- check that a new homeauthhost_id is in the same
            -- authentication system
            IF (p_homeauthhost_id IS NOT NULL) THEN
                SELECT authhost_id INTO v_homeauthhost_id
                FROM authhost2authsys
                WHERE authhost_id = p_homeauthhost_id
                  AND authsys_id = (SELECT authsys_id FROM authhost2authsys WHERE authhost_id = v_homeauthhost_id);
            END IF;

        EXCEPTION
            WHEN no_data_found THEN
                RAISE_APPLICATION_ERROR(OSAG_AUTH_STATE.S_ERRNO_HOMEAH_CONSTRAINT, 'authhost id "'||p_homeauthhost_id||
                                                                                   '" not same authentication system');
        END;

        -- check that the login stays unique for this customer
        IF ((p_login IS NOT NULL) AND (lower(p_login) != lower(v_login))) THEN
            IF (NOT check_login_unique(p_login, v_homeauthhost_id)) THEN
                RAISE_APPLICATION_ERROR(OSAG_AUTH_STATE.S_ERRNO_DUPLICATE_LOGIN, 'login "'||p_login||'" is not unique');
            END IF;
        END IF;

        -- The check that the auth.passport_login.email stays unique for this customer is done on a higher level (Perl): see Issue AUT-105
        --IF (((LOWER(p_email) != LOWER(v_email)) OR v_email IS NULL) AND NOT check_email_unique(p_email)) THEN
        --  RAISE_APPLICATION_ERROR(OSAG_AUTH_STATE.S_ERRNO_DUPLICATE_EMAIL, 'email "'||p_email||'" is not unique');
        --END IF;

        -- check whether password only is allowed
        -- this is currently checked for unlocked users only
        -- 0: password only mode auth type
        IF ((p_twofactorenabled = 0) AND (p_locked = 0) AND (NOT is_password_only_allowed(p_homeauthhost_id))) THEN
            RAISE_APPLICATION_ERROR(OSAG_AUTH_STATE.S_ERRNO_NO_PASSWORD_ONLY, 'Password-only authentication is not allowed for unlocked users.');
        END IF;

        -- update the login and the token company
        BEGIN

            -- Note that if p_authemail is provided, the login is updated with it. The logic is  on a higher level (Perl): see Issue AUT-105
            UPDATE passport_login
            SET login = nvl(p_login, login), passwordtype_id = nvl(p_passwordtype_id, passwordtype_id),
                twofactorenabled = nvl(p_twofactorenabled, twofactorenabled),
                token_id = p_token_id, replacementtoken_id = p_replacementtoken_id,
                homeauthhost_id = nvl(p_homeauthhost_id, homeauthhost_id), locked = nvl(p_locked, locked),
                maxretries = nvl(p_maxretries, maxretries), anytunnelgroup = p_anytunnelgroup,
                passwordexpiry = p_passwordexpiry, cost_center_id = p_cost_center_id, email = p_authemail, smsauthnumber = p_smsauthnumber
            WHERE id = p_login_id;

        EXCEPTION
            WHEN OTHERS THEN
                IF (sqlcode = -00001) THEN
                    RAISE_APPLICATION_ERROR(OSAG_AUTH_STATE.S_ERRNO_DUPLICATE_LOGIN, 'login "'||p_login||'" is not unique');
                ELSE
                    RAISE;
                END IF;
        END;

        -- update the password if one was supplied
        IF (p_password IS NOT NULL) THEN
            set_password(p_login_id, p_password, FALSE, TRUE);
        END IF;

        plog.notice(S_PREFIX||'updated login id "'||p_login_id||'"');


        -- update the contact
        UPDATE stop.passport_contact
        SET firstname = substrb(p_firstname, 1, 50),
            lastname = substrb(p_lastname, 1, 50),
            comments = substrb(p_comments, 1, 200),
            direct = substrb(p_direct, 1, 30),
            mobile = substrb(p_mobile, 1, 30),
            home = substrb(p_home, 1, 30),
            fax = substrb(p_fax, 1, 30),
            email = substrb(p_email, 1, 250),
            company_id = nvl(p_company_id, company_id),
            function = substrb(p_function, 1, 100),
            modified = systimestamp
        WHERE id = v_contact_id;

        plog.notice(S_PREFIX||'updated contact id "'||v_contact_id||'"');

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);
            RAISE;

    END update_login;

    -----------------------------------------------------------------------------
    -- update_login_sync: Updates a login synchronized from external source
    -----------------------------------------------------------------------------
    PROCEDURE update_login_sync(p_contact_id OUT stop.passport_contact.id%TYPE, p_login_id passport_login.id%TYPE,
                                p_login passport_login.login%TYPE, p_password VARCHAR2, p_locked passport_login.locked%TYPE, p_firstname stop.passport_contact.firstname%TYPE,
                                p_lastname stop.passport_contact.lastname%TYPE, p_direct stop.passport_contact.direct%TYPE, p_mobile stop.passport_contact.mobile%TYPE,
                                p_home stop.passport_contact.home%TYPE, p_fax stop.passport_contact.fax%TYPE, p_email stop.passport_contact.email%TYPE, p_authemail auth.passport_login.email%TYPE,
                                p_syncdomain_id auth.syncdomain.id%TYPE, p_domain stop.passport_contact_sync.domain%TYPE,
                                p_usnchanged stop.passport_contact_sync.usnchanged%TYPE, p_cost_center_id mss.cost_center.id%TYPE DEFAULT NULL,
                                p_function stop.passport_contact.function%TYPE DEFAULT NULL, p_comments stop.passport_contact.comments%TYPE DEFAULT NULL, p_smsauthnumber passport_login.smsauthnumber%TYPE) IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.update_login_sync(): ';

        v_login passport_login%ROWTYPE;
        v_contact stop.passport_contact%ROWTYPE;
        v_autoemailaliasesenabled authsys.autoemailaliasesenabled%TYPE;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        SELECT authsys.autoemailaliasesenabled INTO v_autoemailaliasesenabled FROM authsys, syncdomain
        WHERE authsys.id = syncdomain.authsys_id
          AND syncdomain.id = p_syncdomain_id;

        -- Retrieve the old values for this user from the login table. This is necessary
        -- because we have to pass some of these values on to update_login() to make sure
        -- they are not changed by external synchronization, e.g. the token ID. Not overly clever,
        -- but I dare not touch the innards of update_login() lest it breaks something else.
        BEGIN
            SELECT l.* INTO v_login FROM passport_login l
            WHERE l.id = p_login_id;

        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(OSAG_AUTH_STATE.S_ERRNO_NO_LOGIN_RECORD, 'no record found for login ID "'||p_login_id||'"');
            WHEN OTHERS THEN
                RAISE;
        END;

        SELECT * INTO v_contact FROM stop.passport_contact
        WHERE id = v_login.contact_id;

        p_contact_id := v_contact.id;

        update_login(v_login.id, p_login, v_login.passwordtype_id, NULL, v_login.twofactorenabled, v_login.token_id, v_login.replacementtoken_id,
                     v_login.homeauthhost_id, p_locked, v_login.maxretries, p_firstname, p_lastname, p_direct, p_mobile, p_home, p_fax, p_email, p_authemail,
                     v_contact.company_id, v_login.anytunnelgroup, v_login.passwordexpiry, p_cost_center_id, p_function, p_comments, p_smsauthnumber);

        UPDATE stop.passport_contact_sync
        SET domain = p_domain, usnchanged = p_usnchanged
        WHERE contact_id = v_contact.id;

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);
            RAISE;

    END update_login_sync;

    -----------------------------------------------------------------------------
    -- update_login_sync2: Updates a login synchronized from external source (AUT-927: with distinguishedname)
    -----------------------------------------------------------------------------
    PROCEDURE update_login_sync2(p_contact_id OUT stop.passport_contact.id%TYPE, p_login_id passport_login.id%TYPE,
                                 p_login passport_login.login%TYPE, p_password VARCHAR2, p_locked passport_login.locked%TYPE, p_firstname stop.passport_contact.firstname%TYPE,
                                 p_lastname stop.passport_contact.lastname%TYPE, p_direct stop.passport_contact.direct%TYPE, p_mobile stop.passport_contact.mobile%TYPE,
                                 p_home stop.passport_contact.home%TYPE, p_fax stop.passport_contact.fax%TYPE, p_email stop.passport_contact.email%TYPE, p_authemail auth.passport_login.email%TYPE,
                                 p_syncdomain_id auth.syncdomain.id%TYPE, p_domain stop.passport_contact_sync.domain%TYPE,
                                 p_usnchanged stop.passport_contact_sync.usnchanged%TYPE, p_cost_center_id mss.cost_center.id%TYPE DEFAULT NULL,
                                 p_function stop.passport_contact.function%TYPE DEFAULT NULL, p_comments stop.passport_contact.comments%TYPE DEFAULT NULL,
                                 p_smsauthnumber passport_login.smsauthnumber%TYPE,
                                 p_distinguishedname stop.passport_contact_sync.distinguishedname%TYPE DEFAULT NULL) IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.update_login_sync2(): ';

        v_login passport_login%ROWTYPE;
        v_contact stop.passport_contact%ROWTYPE;
        v_autoemailaliasesenabled authsys.autoemailaliasesenabled%TYPE;
        v_function stop.passport_contact.function%TYPE;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        SELECT authsys.autoemailaliasesenabled INTO v_autoemailaliasesenabled FROM authsys, syncdomain
        WHERE authsys.id = syncdomain.authsys_id
          AND syncdomain.id = p_syncdomain_id;

        -- Retrieve the old values for this user from the login table. This is necessary
        -- because we have to pass some of these values on to update_login() to make sure
        -- they are not changed by external synchronization, e.g. the token ID. Not overly clever,
        -- but I dare not touch the innards of update_login() lest it breaks something else.
        BEGIN
            SELECT l.* INTO v_login FROM passport_login l
            WHERE l.id = p_login_id;

        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(OSAG_AUTH_STATE.S_ERRNO_NO_LOGIN_RECORD, 'no record found for login ID "'||p_login_id||'"');
            WHEN OTHERS THEN
                RAISE;
        END;

        SELECT * INTO v_contact FROM stop.passport_contact
        WHERE id = v_login.contact_id;

        p_contact_id := v_contact.id;
        v_function := SUBSTR(CONVERT(p_function, 'US7ASCII'), 1, 100);

        update_login(v_login.id, p_login, v_login.passwordtype_id, NULL, v_login.twofactorenabled, v_login.token_id, v_login.replacementtoken_id,
                     v_login.homeauthhost_id, p_locked, v_login.maxretries, p_firstname, p_lastname, p_direct, p_mobile, p_home, p_fax, p_email,
                     p_authemail, v_contact.company_id, v_login.anytunnelgroup, v_login.passwordexpiry, p_cost_center_id, v_function, p_comments, p_smsauthnumber);

        UPDATE stop.passport_contact_sync
        SET domain = p_domain, usnchanged = p_usnchanged, distinguishedname = p_distinguishedname
        WHERE contact_id = v_contact.id;
    EXCEPTION
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);
            RAISE;
    END update_login_sync2;

    -----------------------------------------------------------------------------
    -- update_login_details: update the login record with details communicated
    --                       from the auth server trough GUMA
    -----------------------------------------------------------------------------
    PROCEDURE update_login_details(p_login_id passport_login.id%TYPE, p_lastaccept passport_login.lastaccept%TYPE,
                                   p_lastreject passport_login.lastreject%TYPE, p_locked passport_login.locked%TYPE) IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.update_login_details(): ';

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        UPDATE passport_login
        SET lastaccept = nvl(p_lastaccept, lastaccept),
            lastreject = nvl(p_lastreject, lastreject)
        WHERE id = p_login_id;

        -- handle the 'locked' flag seperatly because it fires the set_dirtyauthhost trigger
        -- of the login table which we don't want unless we really do lock the login
        IF (p_locked IS NOT NULL) THEN
            IF (p_locked = 0) THEN
                OSAG_AUTH_PASSPORT.unlock_login(p_login_id);
            ELSE
                OSAG_AUTH_PASSPORT.lock_login(p_login_id);
            END IF;
        END IF;

        IF (SQL%NOTFOUND) THEN
            plog.err(S_PREFIX||'failed to update details of login ID "'||p_login_id||'"');
            RAISE NO_DATA_FOUND;
        ELSE
            plog.notice(S_PREFIX||'updated details of login id "'||p_login_id||'" to "'||p_lastaccept||':'||
                        p_lastreject||':'||p_locked||'"');
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);
            RAISE;

    END update_login_details;

    -----------------------------------------------------------------------------
    -- update_login_details2: update the login record with details communicated
    --                        from the auth server trough GUMA
    -----------------------------------------------------------------------------
    PROCEDURE update_login_details2(p_login_id passport_login.id%TYPE, p_lastaccept passport_login.lastaccept%TYPE,
                                    p_lastreject passport_login.lastreject%TYPE, p_locked passport_login.locked%TYPE,
                                    p_token_id token.id%TYPE DEFAULT NULL, p_replacementtoken_id token.id%TYPE DEFAULT NULL) IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.update_login_details2(): ';

        l_token_id            token.id%TYPE;
        l_replacementtoken_id token.id%TYPE;
        l_tokentype_id        token.tokentype_id%TYPE;
        l_locked              passport_login.locked%TYPE;
        l_company_id          passport_login.company_id%TYPE;
        l_login_name          passport_login.login%TYPE;
        l_transaction_id	  NUMBER(18);
        l_lock_pfix           VARCHAR(3);
        l_replacement_token_count NUMBER(10);
        l_token_count         NUMBER(10);

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        plog.debug(S_PREFIX||'login ID: '||p_login_id||', locked: '||p_locked||', token ID: '||p_token_id||
                   ', replacement token ID: '||p_replacementtoken_id);

        UPDATE passport_login
        SET lastaccept = nvl(p_lastaccept, lastaccept),
            lastreject = nvl(p_lastreject, lastreject)
        WHERE id = p_login_id;

        IF (SQL%NOTFOUND) THEN
          plog.err(S_PREFIX||'login ID "'||p_login_id||' does not exist", mod '|| SYS_CONTEXT('USERENV', 'MODULE') ||' of client '|| SYS_CONTEXT('USERENV', 'CLIENT_PROGRAM_NAME') ||' from '|| SYS_CONTEXT('USERENV','IP_ADDRESS'));
          RAISE NO_DATA_FOUND;
        ELSE
          plog.notice(S_PREFIX||'updated details of login id "'||p_login_id||'" to "'||p_lastaccept||':'||
                      p_lastreject||':'||p_locked||':'||p_token_id||':'||p_replacementtoken_id||'"');
        END IF;

        -- can't update the token IDs and locked flag unconditionally because this
        -- would fire the dirty trigger for the login table for every message. Could
        -- be fixed in the trigger I guess, but it's so complicated already, I dare
        -- not touch it
        SELECT token_id, replacementtoken_id, locked, company_id, login
        INTO l_token_id, l_replacementtoken_id, l_locked, l_company_id, l_login_name
        FROM passport_login
        WHERE id = p_login_id;

        -- check if the user has any token assigned
        IF (l_token_id IS NOT NULL) THEN
            l_transaction_id := NULL;
            l_replacement_token_count := 0;
            l_token_count := 0;

            -- check existence of tokens
            SELECT COUNT(*) INTO l_token_count FROM auth.token WHERE id = p_token_id;
            SELECT COUNT(*) INTO l_replacement_token_count FROM auth.token WHERE id = p_replacementtoken_id;

            -- if the provided tokens (assigned and replacement) do not exist in the db (softtokens could have been deleted),
            -- we log an according message and do not mess with the tokens

            IF (l_token_count = 0 OR (p_replacementtoken_id IS NOT NULL AND l_replacement_token_count = 0)) THEN

                plog.notice(S_PREFIX||'Could not find token with ID '||p_token_id || ' or replacement token with ID '|| p_replacementtoken_id ||' provided for login ID '||p_login_id|| ', company '||l_company_id||'. Stopping update attempt.');
                RETURN;
                -- token replacement/update case
            ELSIF ((NVL(p_token_id, -1) != NVL(l_token_id, -1)) AND (NVL(p_replacementtoken_id, -1) != NVL(l_replacementtoken_id, -1))  AND (l_replacementtoken_id IS NOT NULL) ) THEN

                UPDATE passport_login
                SET token_id = p_token_id, replacementtoken_id = p_replacementtoken_id
                WHERE id = p_login_id;

                SELECT tokentype_id
                INTO l_tokentype_id
                FROM token
                WHERE id = l_token_id;

                IF (l_tokentype_id = OSAG_AUTH_STATE.C_OSAG_TOKENTYPE_SOFTTOKEN) THEN
                    DELETE FROM auth.passport_temp_access_key WHERE token_id = l_token_id;
                    DELETE FROM auth.token WHERE id = l_token_id;
                ELSE
                    UPDATE token
                    SET enabled = 0
                    WHERE id = l_token_id;
                END IF;

                osag_audit.add_record('guma', 'authsys', 'login_modify', 'info', l_transaction_id,
                                      'replacement token activated for user '||l_login_name, '<details><auth.passport_login ID="'||p_login_id||'" TOKEN_ID="'||p_token_id||'" REPLACEMENTTOKEN_ID="'
                                          ||p_replacementtoken_id||'" /><AUTH.TOKEN ID="'||l_token_id||'" ENABLED="0" /></details>',
                                      l_company_id, NULL, 'AUTH.PASSPORT_LOGIN', p_login_id, NULL);

                -- If the update is caused by RADIUS server side activation of a replacement token, write notifications and
                -- deactivate the old primary token
                IF ((p_token_id = l_replacementtoken_id) AND p_replacementtoken_id is NULL) THEN
                    plog.notice(S_PREFIX||'assigned replacement token ID '||p_token_id||' as primary token for login ID '||p_login_id||
                                ', disabled previous primary token ID '||l_token_id);
                END IF;
            END IF;
        ELSE
            plog.debug(S_PREFIX||'user '||p_login_id|| ', company '||l_company_id||' has no token assigned.');
        END IF;

        -- handle the 'locked' flag separately because it fires the set_dirtyauthhost trigger
        -- of the login table which we don't want unless we really do lock the login
        IF ((p_locked IS NOT NULL) AND (p_locked != l_locked)) THEN
            IF (p_locked = 0) THEN
                OSAG_AUTH_PASSPORT.unlock_login(p_login_id);
                l_lock_pfix := 'un';
            ELSE
                OSAG_AUTH_PASSPORT.lock_login(p_login_id);
                l_lock_pfix := '';
            END IF;

            osag_audit.add_record('guma', 'authsys', 'login_modify', 'info', l_transaction_id,
                                  l_lock_pfix||'locked user '||l_login_name, '<details><auth.passport_login ID="'||p_login_id||'" LOCKED="'||p_locked||'" /></details>',
                                  l_company_id, NULL, 'AUTH.PASSPORT_LOGIN', p_login_id, NULL);
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);
            RAISE;

    END update_login_details2;

    -----------------------------------------------------------------------------
    -- update_token_details: update the token record with details communicated
    --                       from the auth server trough GUMA
    -----------------------------------------------------------------------------
    PROCEDURE update_token_details(p_token_id token.id%TYPE, p_actercount token.actercount%TYPE,
                                   p_seciddrift token.seciddrift%TYPE, p_dpblob token.dpblob%TYPE) IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.update_token_details(): ';

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        UPDATE token
        SET actercount = nvl(p_actercount, actercount),
            seciddrift = nvl(p_seciddrift, seciddrift),
            dpblob = nvl(p_dpblob, dpblob)
        WHERE id = p_token_id;

        IF (SQL%NOTFOUND) THEN
            plog.err(S_PREFIX||'failed to update token id "'||p_token_id||'"');
            RAISE NO_DATA_FOUND;
        ELSE
            plog.notice(S_PREFIX||'updated seciddrift/actercount/dpblob of token id "'||p_token_id||'"');
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);
            RAISE;

    END update_token_details;

    -----------------------------------------------------------------------------
    -- update_token_details2: update the token record with details communicated
    --                        from the auth server trough GUMA
    -----------------------------------------------------------------------------
    PROCEDURE update_token_details2(p_token_id token.id%TYPE, p_details VARCHAR2) IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.update_token_details2(): ';

        l_tokentype_id tokentype.id%TYPE;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        SELECT tokentype_id
        INTO l_tokentype_id
        FROM token
        WHERE id = p_token_id;

        IF (l_tokentype_id = 0 OR l_tokentype_id = 8 OR l_tokentype_id = 9) THEN
            UPDATE token
            SET seciddrift = NVL(TO_NUMBER(p_details), seciddrift)
            WHERE id = p_token_id;
        ELSIF (l_tokentype_id = 1 OR l_tokentype_id = 7) THEN
            UPDATE token
            SET actercount = NVL(TO_NUMBER(p_details), actercount)
            WHERE id = p_token_id;
        ELSIF ((l_tokentype_id = 2) OR (l_tokentype_id = 3) OR (l_tokentype_id = 5) OR (l_tokentype_id = 6)) THEN
            plog.debug(S_PREFIX||'foo:'||p_details);
            UPDATE token
            SET dpblob = NVL(p_details, dpblob)
            WHERE id = p_token_id;
        ELSE
            plog.err(S_PREFIX||'caught exception: unknown token type ID '||l_tokentype_id);
            RAISE NO_DATA_FOUND;
        END IF;

        IF (SQL%NOTFOUND) THEN
            plog.err(S_PREFIX||'failed to update token ID "'||p_token_id||'"');
            RAISE NO_DATA_FOUND;
        ELSE
            plog.notice(S_PREFIX||'updated seciddrift/actercount/dpblob of token ID "'||p_token_id||'"');
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);
            RAISE;

    END update_token_details2;

    -----------------------------------------------------------------------------
    -- reset_dpblob: reset a Vasco Digipass token blob to enable clock
    --               synchronisation
    -----------------------------------------------------------------------------
    PROCEDURE reset_dpblob(p_token_id IN token.id%TYPE) IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.reset_dpblob(): ';

        v_authhost_id passport_login.homeauthhost_id%TYPE;
        v_old_dpblob token.dpblob%TYPE;
        v_exit NUMBER;
        v_output VARCHAR2(512);
        v_proxy_command VARCHAR2(512);

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        SELECT dpblob INTO v_old_dpblob FROM token
        WHERE id = p_token_id;

        IF ((v_old_dpblob IS NULL) OR (v_old_dpblob = '')) THEN
            RAISE NO_DATA_FOUND;
        END IF;

        v_proxy_command := OSAG_AUTH_STATE.GET_JUMP_SSH_CALL||'/opt/OSAGrad/bin/dpcheck -r \"'||v_old_dpblob||'\""';
        -- switched below lines to activate proxying of commands to mgmt server
        OSAG_EXT.runOsCmdGetResult(v_proxy_command, 512, v_output, v_exit);
        --OSAG_EXT.runOsCmdGetResult('/opt/OSAGrad/bin/dpcheck -r "'||v_old_dpblob||'"', 512, v_output, v_exit);

        IF (v_exit != 0) THEN
            RAISE_APPLICATION_ERROR(OSAG_AUTH_STATE.S_COMMAND_FAILED, v_output||', rc: '||v_exit);
        END IF;

        -- trim leading / trailing spaces and cr
        v_output := ltrim(rtrim(v_output, ' '||chr(10)||chr(13)), ' '||chr(10)||chr(13));

        plog.debug(S_PREFIX||'cmd output: '''||v_output||'''');

        -- rudimentary sanity checking on the blob. Wouldn't want to overwrite with some crap!
        IF (length(v_output) != 248) THEN
            RAISE_APPLICATION_ERROR(OSAG_AUTH_STATE.S_COMMAND_FAILED, 'output does not have expected length (249), is '||length(v_output)||' instead');
        END IF;

        UPDATE token
        SET dpblob = v_output
        WHERE id = p_token_id;

        -- a dpblob update normally doesn't affect the dirty table due to the frequent updates.
        BEGIN
            SELECT homeauthhost_id INTO v_authhost_id FROM passport_login
            WHERE token_id = p_token_id
               OR replacementtoken_id = p_token_id;

            UPDATE dirtyauthhost
            SET token = 1
            WHERE authhost_id = v_authhost_id;

            IF (SQL%FOUND) THEN
                plog.debug(S_PREFIX||'updated dirtyauthhost.token entry for authhost id "'||v_authhost_id||'"');
            ELSE
                INSERT INTO dirtyauthhost (authhost_id, login, token, groups, login2groups, tunnelgroup, login2tunnelgroup, alias)
                VALUES (v_authhost_id, 0, 1, 0, 0, 0, 0, 0);
                plog.debug(S_PREFIX||'inserted dirtyauthhost.token entry for authhost id "'||v_authhost_id||'"');
            END IF;

        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                -- token not associated with a login, don't have to do anything
                NULL;
            WHEN OTHERS THEN
                RAISE;
        END;

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);
            RAISE;

    END reset_dpblob;


    -----------------------------------------------------------------------------
    -- reset_totp: reset a time based OATH token to enable clock
    --               synchronisation
    -----------------------------------------------------------------------------
    PROCEDURE reset_totp(p_token_id IN token.id%TYPE) IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.reset_totp(): ';

        v_authhost_id passport_login.homeauthhost_id%TYPE;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        UPDATE token
        SET seciddrift = 9999
        WHERE id = p_token_id;

        -- a seciddrift update normally doesn't affect the dirty table due to the frequent updates.
        BEGIN
            SELECT homeauthhost_id INTO v_authhost_id FROM passport_login
            WHERE token_id = p_token_id
               OR replacementtoken_id = p_token_id;

            UPDATE dirtyauthhost
            SET token = 1
            WHERE authhost_id = v_authhost_id;

            IF (SQL%FOUND) THEN
                plog.debug(S_PREFIX||'updated dirtyauthhost.token entry for authhost id "'||v_authhost_id||'"');
            ELSE
                INSERT INTO dirtyauthhost (authhost_id, login, token, groups, login2groups, tunnelgroup, login2tunnelgroup, alias)
                VALUES (v_authhost_id, 0, 1, 0, 0, 0, 0, 0);
                plog.debug(S_PREFIX||'inserted dirtyauthhost.token entry for authhost id "'||v_authhost_id||'"');
            END IF;

        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                -- token not associated with a login, don't have to do anything
                NULL;
            WHEN OTHERS THEN
                RAISE;
        END;

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);
            RAISE;

    END reset_totp;

    -----------------------------------------------------------------------------
    -- reset_token: reset a time based token to enable clock
    --              synchronisation
    -----------------------------------------------------------------------------
    PROCEDURE reset_token(p_token_id IN token.id%TYPE) IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.reset_token(): ';

        v_tokentype_id token.tokentype_id%TYPE;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        SELECT tokentype_id INTO v_tokentype_id FROM token
        WHERE id = p_token_id;

        IF (v_tokentype_id = 2) THEN
            plog.debug(S_PREFIX||'resetting digipass token: "'||p_token_id||'"');
            reset_dpblob(p_token_id);
        ELSIF (v_tokentype_id = 8) THEN
            plog.debug(S_PREFIX||'resetting TOTP token: "'||p_token_id||'"');
            reset_totp(p_token_id);
        ELSE
            plog.notice(S_PREFIX||'resetting token not supported: "'||p_token_id||'"');
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);
            RAISE;

    END reset_token;

    -----------------------------------------------------------------------------
    -- unlock_dptoken: unlock PIN locked Vasco Digipass token
    -----------------------------------------------------------------------------
    PROCEDURE unlock_dptoken(p_token_id IN token.id%TYPE, p_random_number VARCHAR2,
                             p_unlock_code OUT NOCOPY VARCHAR2) IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.unlock_dptoken(): ';

        v_authhost_id passport_login.homeauthhost_id%TYPE;
        v_old_dpblob token.dpblob%TYPE;

        v_exit NUMBER;
        v_output VARCHAR2(512);
        v_proxy_command VARCHAR2(512);

        pos NUMBER;
        n NUMBER;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- the random number generated by the token is 8 digits at most
        IF ((length(p_random_number) > 8) OR (length(p_random_number) < 1)) THEN
            RAISE_APPLICATION_ERROR(OSAG_AUTH_STATE.S_COMMAND_FAILED, 'user supplied code must be 1..8 digits long');
        END IF;

        SELECT dpblob INTO v_old_dpblob FROM token
        WHERE id = p_token_id;

        IF ((v_old_dpblob IS NULL) OR (v_old_dpblob = '')) THEN
            RAISE NO_DATA_FOUND;
        END IF;

        v_proxy_command := OSAG_AUTH_STATE.GET_JUMP_SSH_CALL||'/opt/OSAGrad/bin/dpcheck -u \"'||v_old_dpblob||'\"'||p_random_number||'"';
        -- switched below lines to activate proxying of commands to mgmt server
        OSAG_EXT.runOsCmdGetResult(v_proxy_command, 512, v_output, v_exit);
        -- OSAG_EXT.runOsCmdGetResult('/opt/OSAGrad/bin/dpcheck -u "'||v_old_dpblob||'" '||p_random_number, 512, v_output, v_exit);

        IF (v_exit != 0) THEN
            RAISE_APPLICATION_ERROR(OSAG_AUTH_STATE.S_COMMAND_FAILED, v_output||', rc: '||v_exit);
        END IF;

        -- trim leading / trailing spaces and cr
        v_output := ltrim(rtrim(v_output, ' '||chr(10)||chr(13)), ' '||chr(10)||chr(13));

        plog.debug(S_PREFIX||'cmd output: '''||v_output||'''');

        -- split blob and unlock code
        pos := INSTR(v_output, ':', -1);
        pos := pos - 1;

        -- rudimentary sanity checking on the output.
        -- * check that blob part has the necessary length
        -- * check that the total output is long enough to
        --   to contain both blob and unlock code
        -- * check that the blob/unlock code separator is found
        IF (pos != 248) THEN
            RAISE_APPLICATION_ERROR(OSAG_AUTH_STATE.S_COMMAND_FAILED, 'Digipass blob does not have expected length (expected=248, actual='||pos||')');
        END IF;

        IF (length(v_output) <= 249) THEN
            RAISE_APPLICATION_ERROR(OSAG_AUTH_STATE.S_COMMAND_FAILED, 'command output does not contain an unlock code');
        END IF;

        p_unlock_code := substr(v_output, pos + 2);

        -- ensure that the unlock code is all digits
        n := TO_NUMBER(p_unlock_code);

        UPDATE token
        SET dpblob = substr(v_output, 1, pos)
        WHERE id = p_token_id;

        -- a dpblob update normally doesn't affect the dirty table due to the frequent updates.
        BEGIN
            SELECT homeauthhost_id INTO v_authhost_id FROM passport_login
            WHERE token_id = p_token_id;

            UPDATE dirtyauthhost
            SET token = 1
            WHERE authhost_id = v_authhost_id;

            IF (SQL%FOUND) THEN
                plog.debug(S_PREFIX||'updated dirtyauthhost.token entry for authhost id "'||v_authhost_id||'"');
            ELSE
                INSERT INTO dirtyauthhost (authhost_id, login, token, groups, login2groups, tunnelgroup, login2tunnelgroup, alias)
                VALUES (v_authhost_id, 0, 1, 0, 0, 0, 0, 0);
                plog.debug(S_PREFIX||'inserted dirtyauthhost.token entry for authhost id "'||v_authhost_id||'"');
            END IF;

        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                -- token not associated with a login, don't have to do anything
                NULL;
            WHEN OTHERS THEN
                RAISE;
        END;

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);
            RAISE;

    END unlock_dptoken;

    -----------------------------------------------------------------------------
    -- delete_contact: delete a contact given its id
    --                 this procedure does not check any referential constraints
    --                 It's just a wrapper, implemented because of access rights web -> contact
    --                 just contact cl@open.ch for questions
    -----------------------------------------------------------------------------
    PROCEDURE delete_contact(p_contact_id IN stop.passport_contact.id%TYPE) IS

        S_PREFIX CONSTANT VARCHAR2(64) := 'OSAG_AUTH_PASSPORT.delete_contact(): ';

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        DELETE FROM STOP.PASSPORT_CONTACT WHERE ID = p_contact_id;

    END delete_contact;

    ----------------------------------------------------------------------
    -- is_password_only_allowed
    -- private procedure to check whether for a given authhost
    -- the password only authtype is allowed or not
    ----------------------------------------------------------------------
    FUNCTION is_password_only_allowed (p_homeauthhost_id authhost.id%TYPE) RETURN BOOLEAN IS

        v_passwordonlyallowed NUMBER; -- authsys.nopasswordonly%TYPE;
    BEGIN

        SELECT passwordonlyallowed INTO v_passwordonlyallowed FROM auth.authsys asys, auth.authhost2authsys ah2as
        WHERE asys.id = ah2as.authsys_id AND ah2as.authhost_id = p_homeauthhost_id;


        IF v_passwordonlyallowed IS NULL OR v_passwordonlyallowed = 0 THEN
            RETURN FALSE;
        END IF;

        RETURN TRUE;

    END is_password_only_allowed;

    -----------------------------------------------------------------------------
    -- add_auth_secret: add an auth secret to an auth system. Replaces any existing entries
    -- This procedure exists as we don't want to expose access to auth.authsecret to other users
    -----------------------------------------------------------------------------
    PROCEDURE add_auth_secret(p_authsys_id authsys.id%TYPE, p_secret VARCHAR2) IS
    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        DELETE FROM auth.authsecret where authsys_id = p_authsys_id;
        INSERT INTO auth.authsecret (authsys_id, secret) VALUES (p_authsys_id, p_secret);
    END add_auth_secret;
END OSAG_AUTH_PASSPORT;
/
