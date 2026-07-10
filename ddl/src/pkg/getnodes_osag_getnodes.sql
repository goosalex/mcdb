--liquibase formatted sql logicalFilePath:pkg/getnodes_osag_getnodes.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE GETNODES.OSAG_GETNODES AS
    -- -----------------------------------------------------------------------------
    --
    -- create_pkg_OSAG_GETNODES.sql: helper functions used by getnodes users
    --
    -- Currently, gethosts from OSAGmssquery uses this package.
    --
    -- Written by: ras@open.ch
    -- Copyright 2010 Open Systems AG, Switzerland
    -- All Rights Reserved.
    -- -----------------------------------------------------------------------------

--------------------------------------------------------------------------------
/* get_tams_by_company_id
 *
 * This function concatenates the login short names of Technical Account
 * Managers of a Company and separates those login names with a comma.
 *
 * Parameters:
 *
 * p_company_id  : id of the company
 *
 * Returns : a comma separated string of login names of TAMs ordered by priority
 *
 ******************************************************************************/
    FUNCTION get_tams_by_company_id(p_company_id NUMBER)
        RETURN VARCHAR2;
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
/* get_ams_for_company_id
 *
 * This function concatenates the login short names of Account Managers of
 * a Company and separates those login names with a comma.
 *
 * Parameters:
 *
 * p_company_id  : id of the company
 *
 * Returns : a comma separated string of login names of AMs ordered by priority
 ******************************************************************************/
    FUNCTION get_ams_by_company_id(p_company_id NUMBER)
        RETURN VARCHAR2;
--------------------------------------------------------------------------------


END OSAG_GETNODES;
/
