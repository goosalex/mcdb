--liquibase formatted sql logicalFilePath:pkg/tt_osag_notify.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE TT.OSAG_NOTIFY IS
    -- ----------------------------------------------------------------------------
    --
    -- This package contains procedures to automate sending of notifications
    -- from the ticket system. It will replace the package tt.notify and
    -- is written in course of the notification improvements in summer 2008.
    --
    -- It sends notifications to listeners registered in the
    -- tt.event_notification table.
    --
    -- Copyright (c) 2008 Open Systems AG, Switzerland
    -- All Rights Reserved.
    -------------------------------------------------------------------------------

-------------------------------------------------------------------------------
/* This procedure sends notifications to registered listeners of this event.
 *
 * Parameters:
 *
 * p_event_id  : id of the event (tt.event)
 * p_ticket_id : id of the ticket (tt.ticket) linked with the event
 * p_question  : question to be asked in the notification
 *
 *****************************************************************************/
    PROCEDURE event_notify(p_event_id NUMBER,
                           p_ticket_id NUMBER DEFAULT NULL,
                           p_question VARCHAR2 DEFAULT NULL);
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
/* This procedure composes and sends a test notification message to the
 * destination address specified. A notification message is composed
 * according to the event notification type and sent via the specified
 * channel (email, sms).
 *
 * Parameters:
 *
 * p_destination_address     : destination address (e.g. mobile number) for the test notification message
 * p_notification_type_id    : ID of the event notification type to use to send this message
 * p_ticket_id               : ID of associated ticket
 * p_ticket_subject          : subject of the ticket
 * p_host_name               : name of the host
 * p_event_type_id           : id of the event type
 * p_eventdate               : the date the event occured
 * p_contact_last_name       : last name of the contact for whom this message is composed
 * p_contact_first_name      : first name of the contact for whom this message is composed
 *
 *****************************************************************************/
    PROCEDURE send_test_notification(p_destination_address VARCHAR2,
                                     p_notification_type_id NUMBER,
                                     p_ticket_id NUMBER,
                                     p_ticket_subject VARCHAR2,
                                     p_host_name VARCHAR2,
                                     p_event_type_id NUMBER,
                                     p_eventdate TIMESTAMP WITH TIME ZONE,
                                     p_contact_last_name VARCHAR2 DEFAULT NULL,
                                     p_contact_first_name VARCHAR2 DEFAULT NULL);

-------------------------------------------------------------------------------
/* This procedure deletes notifications which are assigned to a specific login.
 * In a first step ticket related notifications are deleted. For those
 * notifications ticket history events are added to the tickets, describing that
 * notifications for the specific login have been deleted. In a second
 * step the remaining notifications of the login are deleted.
 *
 * Parameters:
 *
 * p_login_id          : ID of associated login
 *
 *****************************************************************************/
    PROCEDURE delete_notifications_for_login(p_login_id NUMBER);
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
/* This procedure deletes notifications which are assigned to a specific ticket.
 * If a login id is specified only ticket notifications of this login are
 * deleted. The function adds a history event to the ticket, describing which
 * notifications have been deleted.
 *
 * Parameters:
 *
 * p_ticket_id            : ID of associated ticket
 * p_login_id             : optional ID of a login if only ticket notifications
 *                          for a specific login shall be deleted
 * p_event_details_suffix : optional suffix which is added to the ticket history
 *                          event
 *
 *****************************************************************************/
    PROCEDURE delete_ticket_notifications(p_ticket_id NUMBER,
                                          p_login_id NUMBER DEFAULT NULL,
                                          p_event_details_suffix VARCHAR DEFAULT NULL);
-------------------------------------------------------------------------------

--------------------------------------------------------------------------
/* This procedure adds a notification event to a ticket
 *
 * Parameters:
 *
 * p_ticket_id       : ID of associated ticket
 * p_event_type_id   : Type of event
 * p_text            : Content of notification
 * p_contact         : ID of contact associated with the event
 * p_is_public_event : Specifies whether the event is a public/private event
 *
 ***********************************************************************/
    PROCEDURE add_notification_event(p_ticket_id NUMBER,
                                     p_event_type_id NUMBER,
                                     p_text VARCHAR2,
                                     p_contact_id NUMBER,
                                     p_peer_contact_id NUMBER DEFAULT NULL,
                                     p_is_public_event DECIMAL DEFAULT 1);
-------------------------------------------------------------------------

--------------------------------------------------------------------------
/* This procedure checks whether a service window is active which
 * suppresses notifications for the host associated with the event/ticket.
 *
 * Parameters:
 *
 * p_host_id       : ID of associated host
 *
 ***********************************************************************/
    FUNCTION is_notify_suppressor_active(p_host_id NUMBER) RETURN BOOLEAN;
-------------------------------------------------------------------------


END OSAG_NOTIFY;
/
