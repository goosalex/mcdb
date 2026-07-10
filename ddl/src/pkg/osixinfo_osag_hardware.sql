--liquibase formatted sql logicalFilePath:pkg/osixinfo_osag_hardware.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE OSIXINFO.OSAG_HARDWARE AS
    -- -----------------------------------------------------------------------------
    -- Written by: goetz@open.ch, sm@open.ch
    -- copied over from GUMA2.OSAG_GUMA by phm@open.ch in 2024
    -- to get rid of guma pipeline
    -- Copyright 2003-2024 Open Systems AG, Switzerland
    -- All Rights Reserved.
    --
    -- Contains a bunch of functions that are used related to the hardware replacement
    -- process.
    --
    -- -----------------------------------------------------------------------------

    -- -------------------------------------------------------------------
    -- NOTE:
    -- Please declare constants, exceptions, and global variables
    -- in the according state package (e.g. OSAG_AUTH_STATE for OSAG_AUTH
    -- -------------------------------------------------------------------


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

-- -----------------------------------------------------------------------------
-- HW_CHANGED_EVENT_TYPE: event is triggered if FIRST GUMA heartbeat is received
-- or if hardware replacement process has been triggered.
    HW_CHANGED_EVENT_TYPE CONSTANT NUMBER := '10017';

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

END OSAG_HARDWARE;
/
