--liquibase formatted sql logicalFilePath:pkg/mc_osag_maintsync.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE MC.OSAG_MAINTSYNC IS
    -------------------------------------------------------------------------------
    --
    -- OSAG_maintsync: package to manage synchroniyation of the maintenance status
    --                 host and ISP links
    --
    -- written by cl@open.ch
    -------------------------------------------------------------------------------

    --
    -- Updates the maintenance status of all hosts
    -- (called by a job)
    --
    PROCEDURE update_host_maint_status;

    --
    -- Updates the maintenance status of all isp links
    -- currently in use (i.e. attached to an interface)
    -- (called by a job)
    --
    PROCEDURE update_isp_link_maint_status;

    --
    -- Update the maintenance status of a single host
    --
    PROCEDURE update_single_host(p_host_id MSS.HOST.ID%TYPE);

    --
    -- Update the maintenance of a single isp link
    --
    PROCEDURE update_single_isp_link(p_isp_link_id MSS.ISP_LINK.ID%TYPE);

END OSAG_MAINTSYNC;
/
