--liquibase formatted sql logicalFilePath:pkg/mc_monitoring.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE mc.monitoring IS
    -------------------------------------------------------------------------------
    -- written by sm@open.ch, June 2003;
    -- reworked by ras@open.ch, November 2010;
    -- copyright 2002-2011 Open Systems AG, Switzerland
    --
    -- This package implements all the logic for evaluating the connection
    -- information in mc.mon_server_connection and, if neccessary, create
    -- events for the ticketing system
    --
    -- DOCUMENTATION: https://control.open.ch/docs/x/O4flAw
    --
    -------------------------------------------------------------------------------

    -------------------------------------------------------------------------------
    -- CONSTANTS for this PLSQL package are defined in the separate package:
    -- 'monitoring_state.sql'
    -------------------------------------------------------------------------------

    -------------------------------------------------------------------------------
    -- specify at which percentage of services down we assume a monitoring
    -- infrastructure failure
    -- the actual value is different for our test environment,
    -- decide on package initialization which value to set
    -- FIXME use a local var, not package state!
    -------------------------------------------------------------------------------
    MON_DOWN_LEVEL NUMBER;

    -------------------------------------------------------------------------------
    -- update_host_status: writes a connection status for a host to the
    -- mon_server_connection table. Note that this procedure does not update
    -- the "overall status" of the host. Call "collate_conn_status()" in a separate
    -- transaction to update the overall status.
    -------------------------------------------------------------------------------
    PROCEDURE update_host_status(p_host_id mc.mon_server_connection.host_id%TYPE,
                                 p_mon_server_id mc.mon_server_connection.mon_server_id%TYPE,
                                 p_con_timestamp mc.mon_server_connection.con_timestamp%TYPE,
                                 p_status mc.mon_server_connection.status%TYPE,
                                 p_details mc.mon_server_connection.details%TYPE);

    -------------------------------------------------------------------------------
    -- update_host_status_with_ip: writes a connection status for a host to the
    -- mon_server_connection table. Note that this procedure does not update
    -- the "overall status" of the host. Call "collate_conn_status()" in a separate
    -- transaction to update the overall status.
    -- this procedure allows to specify what IP address could be reached.
    -------------------------------------------------------------------------------
    PROCEDURE update_host_status_with_ip(p_host_id mc.mon_server_connection.host_id%TYPE,
                                         p_mon_server_id  mc.mon_server_connection.mon_server_id%TYPE,
                                         p_con_timestamp  mc.mon_server_connection.con_timestamp%TYPE,
                                         p_status         mc.mon_server_connection.status%TYPE,
                                         p_details        mc.mon_server_connection.details%TYPE,
                                         p_ipv4_address   mc.mon_server_connection.ipv4_address%TYPE,
                                         p_ipv6_address_1 mc.mon_server_connection.ipv6_address_1%TYPE,
                                         p_ipv6_address_2 mc.mon_server_connection.ipv6_address_2%TYPE);

    -------------------------------------------------------------------------------
    -- collate_conn_status: calculates the collated connection status of a given
    -- service from the connection states written to mon_server_connection by
    -- the different monitoring servers. The collated state is written into the
    -- table host_connection_status.
    --
    -- parameters:
    --   p_host_id:  id of the host for which state is collated
    -------------------------------------------------------------------------------
    PROCEDURE collate_conn_status(p_host_id mc.mon_server_connection.host_id%TYPE);

    -------------------------------------------------------------------------------
    -- check_mode_changed: Check if the monitoring mode (active/SW/inactive) has
    -- changed and trigger necessary actions
    --
    -- parameter: p_host_id
    --            p_sang_status, the last sang status which has been stored in db
    --            p_mode, the mode (MODE_ACTIVE,MODE_INACTIVE,MODE_SW)
    -------------------------------------------------------------------------------
    PROCEDURE check_mode_changed(
        p_host_id     mss.host.id%TYPE,
        p_sang_status NUMBER,
        p_mode        NUMBER);

    -------------------------------------------------------------------------------
    -- get_sang_status_from_state: returns SANG_ value for given STATE_ parameter
    --
    -- parameter: p_state, a STATE_ value
    --
    -- returns: one of SANG_UP,SANG_DOWN,SANG_ISP
    -------------------------------------------------------------------------------
    FUNCTION get_sang_status_from_state( p_state NUMBER ) RETURN NUMBER;

    -------------------------------------------------------------------------------
    -- get_mode_from_state: returns MODE_ value for given STATE_ parameter
    --
    -- parameter: p_state, a STATE_ value
    --
    -- returns: one of MODE_ACTIVE,MODE_INACTIVE or MODE_SW
    -------------------------------------------------------------------------------
    FUNCTION get_mode_from_state( p_state NUMBER ) RETURN NUMBER;

END monitoring;
/
