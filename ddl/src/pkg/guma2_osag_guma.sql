--liquibase formatted sql logicalFilePath:pkg/guma2_osag_guma.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE GUMA2.OSAG_GUMA AS
    -- -----------------------------------------------------------------------------
    -- Written by: goetz@open.ch, sm@open.ch
    -- Copyright 2003-2005 Open Systems AG, Switzerland
    -- All Rights Reserved.
    --
    -- Contains a bunch of functions that are used by the VPN GUI (and
    -- possibly other GUIs) to administrate various aspects of the
    -- GUMA database.
    --
    -- -----------------------------------------------------------------------------

    -- -------------------------------------------------------------------
    -- NOTE:
    -- Please declare constants, exceptions, and global variables
    -- in the according state package (e.g. OSAG_AUTH_STATE for OSAG_AUTH
    -- -------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- pattern management
-- Purpose: Helper procedures to administrate the pattern table, in particular
-- for global pattern position management
    PROCEDURE free_pattern_pos(i_pos NUMBER);
    PROCEDURE pack_pattern_pos;
    PROCEDURE prune_syslog_message(age NUMBER);

-- -----------------------------------------------------------------------------
-- check_replaced_hw_for_host (MON-93)
-- checks if the given host reports a new mac address that matches the
-- set replacement hardware. If so, the hardware is replaced in the database.
-- -----------------------------------------------------------------------------
    PROCEDURE check_replaced_hw_for_host(p_host_id      mss.host.id%TYPE,
                                         p_reported_mac mss.hardware.mac_address%TYPE );

-- PROCEDURE add_hardware_lifecycle_item
--
-- add a new hardware lifecycle item to a hardware
-- IN: hardware_id, hardware_lc_state_id, hardware_lc_location_id, creator
-- -----------------------------------------------------------------------------
    PROCEDURE add_hardware_lifecycle_item (
        p_hardware_id mss.hardware.id%TYPE,
        p_hardware_lc_state_id mss.hardware_lifecycle_item.hardware_lc_state_id%TYPE,
        p_hardware_lc_location_id mss.hardware_lifecycle_item.hardware_lc_location_id%TYPE,
        p_creator mss.hardware_lifecycle_item.creator%TYPE);

-- -----------------------------------------------------------------------------
-- replace_hardware:
--   do all replacement changes to the hardware tables.
--   this function is called by the gumaserver.
-- -----------------------------------------------------------------------------
    PROCEDURE replace_hardware (p_host_id   mss.host.id%TYPE,
                                p_old_hw_id mss.hardware.id%TYPE,
                                p_new_hw_id mss.hardware.id%TYPE);

-- -----------------------------------------------------------------------------
-- log_version: write an audit trail entry for the changed version number
-- -----------------------------------------------------------------------------
    PROCEDURE log_version(p_host_id     number,
                          p_old_version varchar2,
                          p_new_version varchar2,
                          p_build       varchar2);

-- -----------------------------------------------------------------------------
-- clean_suppressed_signature: remove old signature suppressions
-- -----------------------------------------------------------------------------
    PROCEDURE clean_suppressed_signature;

-- -----------------------------------------------------------------------------
-- HB_CHECK_MAX_DELAY: heartbeats are not allowed to be older than
--                     HB_CHECK_MAX_DELAY dictates.
--
-- The scheduled time intervall to check on heartbeats is at the time of writing
-- every hour.
--
-- NOTE: database table fields of type DATE are prone to time jumps when
--       DST starts or ends (no time zone included in the field).
--       Therefore, a threshold of more than 1 hour has been chosen.
--
-- calculations: DST ends: event generation after 3 hours of missing HB
--               DST starts: event generation after 1 hour of missing HB
--               on average: event generation after 2 hours
-- -----------------------------------------------------------------------------
    HB_CHECK_MAX_DELAY CONSTANT NUMBER :=  4 / ( 24 * 3 ); -- 80 minutes
    -- every "1 hour and 20 minutes"

-- -----------------------------------------------------------------------------
-- FAKE_HB_CHECK_MAX_DELAY: fake heartbeats are not allowed to be older than
--                          FAKE_HB_CHECK_MAX_DELAY.
--
-- fake heartbeats are created once per day between 3 and 4 am.
-- -----------------------------------------------------------------------------
    FAKE_HB_CHECK_MAX_DELAY CONSTANT NUMBER := 1; -- 1 day

-- -----------------------------------------------------------------------------
-- HW_CHANGED_EVENT_TYPE: event is triggered if FIRST GUMA heartbeat is received
-- or if hardware replacement process has been triggered.
    HW_CHANGED_EVENT_TYPE CONSTANT NUMBER := '10017';

-- -----------------------------------------------------------------------------
-- EVENT_TYPE_SYSTEM_NOTIFICATION: this event type is used for
--  still missing hearbeat events
-- -----------------------------------------------------------------------------
    EVENT_TYPE_SYSTEM_NOTIFICATION CONSTANT NUMBER := '10008'; -- system notification

-- -----------------------------------------------------------------------------
-- EVENT_TYPE_SYSTEM_FAILURE: this event type is used for hearbeat events,
--  events will be escalated to Mission Control
-- -----------------------------------------------------------------------------
    EVENT_TYPE_SYSTEM_FAILURE CONSTANT NUMBER := '10009'; -- system notification

-- -----------------------------------------------------------------------------
-- MON_EVENT_TYPE: event type of a monitoring event
-- -----------------------------------------------------------------------------
    MON_EVENT_TYPE CONSTANT NUMBER := '10013'; -- monitoring event

-- -----------------------------------------------------------------------------
-- MAX_MISSING_HB: if more than MAX_MISSING_HB heartbeats are missing, then
--                 NO event is generated. there is likely a monitoring problem.
-- -----------------------------------------------------------------------------
    MAX_MISSING_HB CONSTANT NUMBER := '200';

-- -----------------------------------------------------------------------------
-- Ticket Types
-- -----------------------------------------------------------------------------
    TICKET_TYPE_HARDWARE_CHANGE CONSTANT NUMBER := '8';

-- -----------------------------------------------------------------------------
-- Link to Docs for 'General GUMA outage'
-- -----------------------------------------------------------------------------
    TODO_GUMA_OUTAGE CONSTANT VARCHAR2(256) := 'To Do:'||CHR(10)
        ||'https://control.open.ch/docs/x/ngUCB';

-- -----------------------------------------------------------------------------
-- Link to Docs for 'Heartbeat missing'
-- -----------------------------------------------------------------------------
    TODO_HB_MISSING CONSTANT VARCHAR2(256) := 'To Do:'||CHR(10)
        ||'https://control.open.ch/docs/x/IgIOB';

-- -----------------------------------------------------------------------------
-- private to do text for 'hardware migration' tickets
--
-- the text describes the steps necessary for the case in which no suitable
-- hardware migration ticket has been found
-- -----------------------------------------------------------------------------
    TODO_PRIVATE_HW_MIG CONSTANT VARCHAR2(1024) :=
            'To Do:'||CHR(10)
            ||' - Check ticket type. Must be: migration'||CHR(10)
            ||' - Check that this ticket is a hardware migration tracking ticket.'||CHR(10)
            ||'   If not: check if a matching migration ticket is deferred. Inform TAM.';

END OSAG_GUMA;
/
