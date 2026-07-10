--liquibase formatted sql logicalFilePath:pkg/mc_osag_isp_monitoring.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE mc.osag_isp_monitoring IS
    -------------------------------------------------------------------------------
    -- osag_isp_monitoring: isp link monitoring package
    --
    -- written by ras@open.ch, July 2012;
    -- copyright 2002-2011 Open Systems AG, Switzerland
    --
    -- This package manages the entries in mc.isp_link_status
    -- and mc.isp_link_status_history. It does not do any ticketing.
    --
    -- DOCUMENTATION: none
    -------------------------------------------------------------------------------


    -------------------------------------------------------------------------------
    -- update_link_status:
    -- !! takes a timestamp argument, but it ignores that parameter. !!
    -- ( this procedure is used for a smooth transition )
    -- * updates the mss.isp_link and mc.isp_link_history tables
    -- * does a sanity check with p_revious_status
    -------------------------------------------------------------------------------
    PROCEDURE update_isp_link_status(p_isp_link_id      mc.isp_link_history.isp_link_id%type,
                                     p_status           mc.isp_link_status_type.id%type,
                                     p_previous_status  mc.isp_link_status_type.id%type,
                                     p_change_timestamp PLS_INTEGER,
                                     p_reported_by      mc.isp_link_history.reporting_host_id%type);

    -------------------------------------------------------------------------------
    -- update_link_status2:
    -- * updates the mss.isp_link and mc.isp_link_history tables
    -- * does a sanity check with p_revious_status
    -------------------------------------------------------------------------------
    PROCEDURE update_isp_link_status2(p_isp_link_id      mc.isp_link_history.isp_link_id%type,
                                      p_status           mc.isp_link_status_type.id%type,
                                      p_previous_status  mc.isp_link_status_type.id%type,
                                      p_reported_by      mc.isp_link_history.reporting_host_id%type);

    -------------------------------------------------------------------------------
    -- update_capacity_measurements
    -- * updates the mss.isp_link table with the newest link capacity measurements
    -------------------------------------------------------------------------------
    PROCEDURE update_capacity_measurements(p_isp_link_id      mss.isp_link.id%type,
                                           p_download         mss.isp_link.measured_download%type,
                                           p_upload           mss.isp_link.measured_upload%type,
                                           p_interface_id     mss.isp_link.usage_interface_id%TYPE);

END osag_isp_monitoring;
/
