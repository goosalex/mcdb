--liquibase formatted sql logicalFilePath:pkg/guma2_secondary_isp.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE GUMA2.SECONDARY_ISP AS
    -- ----------------------------------------------------------------------------------------
    --
    -- Written by: dws@open.ch
    -- Copyright 2011, Open Systems AG, Switzerland
    -- All Rights Reserved.
    --
    -- Package contains the procedures making up a the "Secondary ISP Outage"
    -- logic, as described here:
    --
    --   https://control.open.ch/jira/browse/MON-215
    --
    -- These procedures are only called by GUMA2.submit_msg()
    -- ----------------------------------------------------------------------------------------

-- ----------------------------------------------------------------------------------------
-- procedures (called by GUMA2.submit_msg()
-- ----------------------------------------------------------------------------------------

    PROCEDURE secondaryisp_alert(
        i_host_id       mss.host.id%TYPE,
        i_logdate       syslog_message.log_date%TYPE,
        i_data          syslog_message.message%TYPE
    );

    PROCEDURE secondaryisp_ok(
        i_host_id       mss.host.id%TYPE,
        i_logdate       syslog_message.log_date%TYPE,
        i_data             syslog_message.message%TYPE
    );
END SECONDARY_ISP;
/
