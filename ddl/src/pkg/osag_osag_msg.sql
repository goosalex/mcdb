--liquibase formatted sql logicalFilePath:pkg/osag_osag_msg.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE OSAG.OSAG_MSG AS
    -- ----------------------------------------------------------------------------
    --
    -- OSAG_MSG: Implements generalized methods to send Email and SMS messages
    --
    -- Written by Stefan Moser sm@open.ch, July 2006
    -- Copyright (c) 2006 Open Systems AG, Switzerland
    -- All Rights Reserved.
    --
    -- Implements generalized methods to send Email and SMS messages. Behind the
    -- scenes, the actually all send email - by using the appropriate domain name,
    -- SMS messages are routed to the SMS gateway for further delivery.
    -- The methods use the UTL_SMTP module to send the messages - as opposed to earlier
    -- attempts that used external scripts, this eliminates several problem areas such
    -- as command line quoting, host trust, trackability and run time behaviour. The
    -- intent is that it doesn't introduce any new ones ;)
    --
    -- ----------------------------------------------------------------------------
    SUBTYPE smtp_header_name_t IS VARCHAR2(64);
    SUBTYPE smtp_header_value_t IS VARCHAR(256);
    TYPE smtp_header_t IS RECORD (h_name smtp_header_name_t, h_value smtp_header_value_t);
    TYPE smtp_headers_t IS TABLE OF smtp_header_t;


    --------------------------------------------------------------------------
    /* This procedure sends an email message
     *
     * PARAMETERS
     * p_reply_to    : Reply to address, will be used in Reply-To SMTP header
     * p_from        : If not null, address that will be used in From SMTP header, otherwise p_reply_to is used
     * p_mail_from   : If not null, address that will be used as envelope address, (i.e. MAIL FROM), otherwise p_reply_to is used
     * p_recipient   : Recipient email address
     * p_subject     : Subject of email message
     * p_body        : Body of email message
     * p_opt_headers : Optional headers to be added to email message (nested table of smtp_header_t records), can be NULL
     *
     ***********************************************************************/
    PROCEDURE send_mail(p_reply_to VARCHAR2, p_from VARCHAR2, p_mail_from VARCHAR2, p_recipient VARCHAR2, p_subject VARCHAR2,
                        p_body VARCHAR2, p_opt_headers smtp_headers_t := NULL);
    -------------------------------------------------------------------------

    --------------------------------------------------------------------------
    /* This procedure sends an SMS message
     *
     * PARAMETERS
     * p_sms_no       : Mobile number of recipient
     * p_body         : Body of SMS message
     ***********************************************************************/
    PROCEDURE send_sms(p_sms_no VARCHAR2, p_body VARCHAR2);
    -------------------------------------------------------------------------
END OSAG_MSG;
/

CREATE OR REPLACE PUBLIC SYNONYM OSAG_MSG FOR OSAG.OSAG_MSG
/

