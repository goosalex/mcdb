--liquibase formatted sql logicalFilePath:pkg/mc_monitoring_ticket_processes.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE mc.monitoring_ticket_processes IS
    -------------------------------------------------------------------------------
    --
    -- monitoring_ticket_processes: package that encapsulates all logic
    --                              that generates events and tickets
    --
    -- written by Ramon Schwammberger <ras@open.ch>, December 2010;
    -- copyright 2002-2010 Open Systems AG, Switzerland
    --
    -- This package implements all the logic for evaluating the connection
    -- information in mc.mon_server_connection and, if neccessary, create
    -- events for the ticketing system
    --
    -- DOCUMENTATION: https://control.open.ch/docs/x/O4flAw
    --
    --
    -------------------------------------------------------------------------------

    -------------------------------------------------------------------------------
    -- CONSTANTS for this PLSQL package are defined in the separate package:
    -- 'monitoring_state.sql'
    -------------------------------------------------------------------------------
    -------------------------------------------------------------------------------
    -- new_event: trigger a new ticket event, add it to an existing ticket
    --            or open new ticket. This is a wrapper for tt.new_event().
    --
    -- parameter: p_host_id, the host_id to which the event refers to
    --            p_sang_status, the status reported by SANG
    --            p_mode, the mode of the state machine (active, inactive, SW)
    --            p_event_id, the ID of the last event for this interrupt (if any)
    -- return:    -
    -------------------------------------------------------------------------------
    PROCEDURE new_event(
        p_host_id     mss.host.id%TYPE,
        p_sang_status NUMBER,
        p_mode        NUMBER,
        p_event_id    tt.event.id%TYPE DEFAULT NULL);

END monitoring_ticket_processes;
/
