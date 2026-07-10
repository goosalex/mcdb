--liquibase formatted sql logicalFilePath:pkg/auth_osag_auth_state.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
/************************************************************
 *
 * Exceptions for the PL/SQL package OSAG_AUTH
 *
 ************************************************************/
CREATE OR REPLACE PACKAGE AUTH.OSAG_AUTH_STATE IS

    duplicate_alias EXCEPTION;
    S_ERRNO_DUPLICATE_ALIAS CONSTANT NUMBER := -20987;
    PRAGMA EXCEPTION_INIT (duplicate_alias, -20987);

    -- Application specific exceptions
    authsys_update_warning EXCEPTION;
    S_ERRNO_AUTHSYS_UPDATE_WARNING CONSTANT NUMBER := -20986;
    PRAGMA EXCEPTION_INIT (authsys_update_warning, -20986);

    authsys_update_partial EXCEPTION;
    S_ERRNO_AUTHSYS_UPDATE_PARTIAL CONSTANT NUMBER := -20988;
    PRAGMA EXCEPTION_INIT (authsys_update_partial, -20988);

    duplicate_email EXCEPTION;
    S_ERRNO_DUPLICATE_EMAIL CONSTANT NUMBER := -20989;
    PRAGMA EXCEPTION_INIT (duplicate_email, -20989);

    domain_sync_failed EXCEPTION;
    S_ERRNO_DOMAIN_SYNC_FAILED CONSTANT NUMBER := -20990;
    PRAGMA EXCEPTION_INIT (domain_sync_failed, -20990);

    no_login_record EXCEPTION;
    S_ERRNO_NO_LOGIN_RECORD CONSTANT NUMBER := -20991;
    PRAGMA EXCEPTION_INIT (no_login_record, -20991);

    no_password_only EXCEPTION;
    S_ERRNO_NO_PASSWORD_ONLY CONSTANT NUMBER := -20992;
    PRAGMA EXCEPTION_INIT (no_password_only, -20992);

    command_failed EXCEPTION;
    S_COMMAND_FAILED CONSTANT NUMBER := -20993;
    PRAGMA EXCEPTION_INIT (command_failed, -20993);

    password_recently_used EXCEPTION;
    S_ERRNO_PASSWORD_RECENTLY_USED CONSTANT NUMBER := -20994;
    PRAGMA EXCEPTION_INIT (password_recently_used, -20994);

    authsys_update_failed EXCEPTION;
    S_ERRNO_AUTHSYS_UPDATE_FAILED CONSTANT NUMBER := -20995;
    PRAGMA EXCEPTION_INIT (authsys_update_failed, -20995);

    homeauthhost_constraint EXCEPTION;
    S_ERRNO_HOMEAH_CONSTRAINT CONSTANT NUMBER := -20996;
    PRAGMA EXCEPTION_INIT (homeauthhost_constraint, -20996);

    token_constraint EXCEPTION;
    S_ERRNO_TOKEN_CONSTRAINT CONSTANT NUMBER := -20997;
    PRAGMA EXCEPTION_INIT (token_constraint, -20997);

    duplicate_login EXCEPTION;
    S_ERRNO_DUPLICATE_LOGIN CONSTANT NUMBER := -20998;
    PRAGMA EXCEPTION_INIT (duplicate_login, -20998);

    weak_password EXCEPTION;
    S_ERRNO_WEAK_PASSWORD CONSTANT NUMBER := -20999;
    PRAGMA EXCEPTION_INIT (weak_password, -20999);


    C_OSAG_AUTHSYNC_HOME CONSTANT VARCHAR2(64) := '/opt/OSAGauthsync';

    C_OSAG_TOKENTYPE_SOFTTOKEN CONSTANT NUMBER := 9;
    C_OSAG_TOKENFORM_SOFT CONSTANT NUMBER := 3;

    FUNCTION GET_JUMP_SSH_CALL RETURN VARCHAR2;

END OSAG_AUTH_STATE;
/
