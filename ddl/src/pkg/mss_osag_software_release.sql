--liquibase formatted sql logicalFilePath:pkg/mss_osag_software_release.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE mss.osag_software_release AS
    /*
     *
     * package OSAG_SOFTWARE_RELEASE
     *
     * Used to update the MSS.RELEASE_INSTALLATIONS.
     *
     */

    PROCEDURE update_release_installations;


END osag_software_release;
/
