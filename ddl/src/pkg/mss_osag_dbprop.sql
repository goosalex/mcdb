--liquibase formatted sql logicalFilePath:pkg/mss_osag_dbprop.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE MSS.OSAG_DBPROP AS
    /*
     *
     * package OSAG_DBPROP
     *
     * Procedures to work with DB Properties. At this time there are only
     * retrieval functions for non-file type properties. We will eventually
     * add procedures to set and or delete db properties.
     */

    -- -------------------------------------------------------------------
    -- NOTE:
    -- Please declare constants, exceptions, and global variables
    -- in the according state package (e.g. OSAG_AUTH_STATE for OSAG_AUTH)
    -- -------------------------------------------------------------------

-- ----------------------------------------------------------------------------------------
-- procedures
-- ----------------------------------------------------------------------------------------

    FUNCTION get_number_by_host(i_host_id NUMBER, i_property_name VARCHAR2) RETURN NUMBER;
    FUNCTION get_string_by_host(i_host_id NUMBER, i_property_name VARCHAR2) RETURN VARCHAR2;
    FUNCTION get_string_by_host_key_id(i_host_id NUMBER, i_property_key_id NUMBER) RETURN VARCHAR2;

END OSAG_DBPROP;
/

create or replace public synonym OSAG_DBPROP for MSS.OSAG_DBPROP
/

