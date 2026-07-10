--liquibase formatted sql logicalFilePath:pkg/nids_osag_nids.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE NIDS.OSAG_NIDS AS
-- ----------------------------------------------------------------------------------------
--
-- Written by: sm@open.ch, dws@open.ch
-- Copyright 2008 Open Systems AG, Switzerland
-- All Rights Reserved.
--
-- ----------------------------------------------------------------------------------------

-- ----------------------------------------------------------------------------------------
-- procedures
-- ----------------------------------------------------------------------------------------
    PROCEDURE submit_msg(
        i_log_date               nids_event.log_date%TYPE,
        i_sensor_name            VARCHAR2,
        i_sender_host_id         nids_event.sender_host_id%TYPE,
        i_event_id               nids_event.local_event_id%TYPE,
        i_signature_gid          signature.gid%TYPE,
        i_signature_sid          signature.sid%TYPE,
        i_signature_class        VARCHAR2,
        i_suppressed             nids_event.suppressed%TYPE,
        i_ip_source_address      nids_event.ip_source_address%TYPE,
        i_ip_source_port         nids_event.ip_source_port%TYPE,
        i_ip_destination_address nids_event.ip_destination_address%TYPE,
        i_ip_destination_port    nids_event.ip_destination_port%TYPE,
        i_ip_protocol            nids_event.ip_protocol%TYPE,
        i_direction_id           nids_event.direction_id%TYPE,
        i_description            VARCHAR2,
        i_escalation_level       INTEGER); -- 1: ticket-only, 2: escalate!

    PROCEDURE submit_msg_new(
        i_log_date               nids_event.log_date%TYPE,
        i_sensor_name            VARCHAR2,
        i_sender_host_id         nids_event.sender_host_id%TYPE,
        i_event_id               nids_event.local_event_id%TYPE,
        i_tt_event_id            OUT NUMBER,
        i_ticket_id              NUMBER,
        i_signature_gid          signature.gid%TYPE,
        i_signature_sid          signature.sid%TYPE,
        i_signature_class        VARCHAR2,
        i_suppressed             nids_event.suppressed%TYPE,
        i_ip_source_address      nids_event.ip_source_address%TYPE,
        i_ip_source_port         nids_event.ip_source_port%TYPE,
        i_ip_destination_address nids_event.ip_destination_address%TYPE,
        i_ip_destination_port    nids_event.ip_destination_port%TYPE,
        i_ip_protocol            nids_event.ip_protocol%TYPE,
        i_direction_id           nids_event.direction_id%TYPE,
        i_description            VARCHAR2,
        i_escalation_level       INTEGER); -- 1: ticket-only, 2: escalate!


END OSAG_NIDS;
/

create or replace public synonym OSAG_NIDS for osag_nids
/

