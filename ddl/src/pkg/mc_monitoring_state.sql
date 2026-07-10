--liquibase formatted sql logicalFilePath:pkg/mc_monitoring_state.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE mc.monitoring_state IS
    -------------------------------------------------------------------------------
    -- reworked by ras@open.ch, November 2010;
    -- copyright 2002-2010 Open Systems AG, Switzerland
    --
    -- This package defines constants which are use by the monitoring.sql package.
    --
    -- DOCUMENTATION: https://control.open.ch/docs/x/O4flAw
    --
    --
    -------------------------------------------------------------------------------

    -------------------------------------------------------------------------------
    -- TODO_CONN_DOWN: string with a link to the official Docs page
    -- with a TODO list for MC in case connection is down
    -------------------------------------------------------------------------------
    TODO_CONN_DOWN CONSTANT VARCHAR2(256) := 'To Do:' || CHR(10) || 'Execute this process: '
        || 'https://open-systems.atlassian.net/wiki/x/kU--/';

    -------------------------------------------------------------------------------
    -- TODO_ISP_OUTAGE: string with a link to the official Docs page
    -- with a TODO list for MC in case ISP link has an outage
    -------------------------------------------------------------------------------
    TODO_ISP_DOWN CONSTANT VARCHAR2(256) := NULL;

    -------------------------------------------------------------------------------
    -- TODO_MON_DOWN: string with a link to the official Docs page
    -- with a TODO list for MC in case monitoring is down
    -------------------------------------------------------------------------------
    TODO_MON_DOWN CONSTANT VARCHAR2(256) := 'To Do:' || CHR(10) || 'Execute this process '
        || 'https://control.open.ch/docs/x/P4nNAw';

    -------------------------------------------------------------------------------
    -- SANG status and mode constants
    -------------------------------------------------------------------------------
    SANG_UP    CONSTANT NUMBER := 0;
    SANG_ISP   CONSTANT NUMBER := 1;
    SANG_DOWN  CONSTANT NUMBER := 2;
    SANG_ERROR CONSTANT NUMBER := 3;

    MODE_ACTIVE   CONSTANT NUMBER := 0;
    MODE_SW       CONSTANT NUMBER := 1;
    MODE_INACTIVE CONSTANT NUMBER := 2;

    -- see also: get_sang_status_from_state to derive SANG_ from STATE_
    STATE_ISP           CONSTANT NUMBER :=  1;
    STATE_DOWN          CONSTANT NUMBER :=  2;
    STATE_ISP_SW        CONSTANT NUMBER := 11;
    STATE_DOWN_SW       CONSTANT NUMBER := 12;

    -- states like the following would be consistent with the initial design
    -- but the requirement was not to change the database... --FIXME
--  STATE_ISP_INACTIVE  NUMBER := 21;
--  STATE_DOWN_INACTIVE NUMBER := 22;

    EVENT_TYPE_DOWN       CONSTANT NUMBER :=  10001;
    EVENT_TYPE_ISP        CONSTANT NUMBER :=  10003;
    EVENT_TYPE_MONITORING CONSTANT NUMBER :=  10013;
    EVENT_TYPE_TRACEROUTE CONSTANT NUMBER :=  10016;
    EVENT_TYPE_UP         CONSTANT NUMBER :=  10100;
    EVENT_TYPE_ATTR_CHG   CONSTANT NUMBER := 100003;

    TICKET_STATUS_HOT      CONSTANT NUMBER :=   3;
    TICKET_STATUS_RESOLVED CONSTANT NUMBER := 101;
    TICKET_STATUS_CLOSED   CONSTANT NUMBER := 102;
    TICKET_STATUS_MERGED   CONSTANT NUMBER := 110;

END monitoring_state;
/
