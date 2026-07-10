--liquibase formatted sql logicalFilePath:pkg/auth_osag_auth.sql
--changeset sys:1 runOnChange:true endDelimiter:/
CREATE OR REPLACE PACKAGE AUTH.OSAG_AUTH IS
    -- written by ok@open.ch, January 2002;
    -- copyright 2002-2003 Open Systems AG, Switzerland
    --
    -- Manages the scheme auth - provides function for altering
    -- records - selects are done directly

    -- -------------------------------------------------------------------
    -- NOTE:
    -- Please declare constants, exceptions, and global variables
    -- in the according state package (e.g. OSAG_AUTH_STATE for OSAG_AUTH
    -- -------------------------------------------------------------------

    -----------------------------------------------------------------------------
    -- delete_login: delete a login
    -----------------------------------------------------------------------------
    PROCEDURE delete_login(p_login_id login.id%TYPE);
    -----------------------------------------------------------------------------
    -- grant_user_role: grant a role to a login
    -----------------------------------------------------------------------------
    PROCEDURE grant_role(p_login_id login.id%TYPE, p_role_id role.id%TYPE);

    -----------------------------------------------------------------------------
    -- grant_user_role: grant a role to a login
    -----------------------------------------------------------------------------
    PROCEDURE grant_user_role(p_login_id login.id%TYPE, p_user_role_id user_role.id%TYPE);

END OSAG_AUTH;
/
--changeset sys:2 runOnChange:true
CREATE OR REPLACE PUBLIC SYNONYM osag_auth FOR auth.osag_auth;
