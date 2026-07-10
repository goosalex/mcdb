--liquibase formatted sql logicalFilePath:pkg/tt_ticket_interface.sql
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE tt.ticket_interface AS

    /*
     * this package offers procedures to deal with mission control tickets.
     *
     * It offers procedures to open a ticket or modify ticket attributes
     * and merge to tickets together
     */

------------------------------------------------------------
-- open a new ticket
------------------------------------------------------------
/*
* procedure name: newticket_new
*
* this procedure opens a new ticket and ads
* one event to the ticket.
* placeholders '##ticket_id##' and '##event_id##' in the given
* details are replaced (see replace_id_placeholders)
*
* parameters
* p_ticket_id  returns the ticket id for the new ticket
* p_event_id retunrs the event id for the event added to the ticket
* p_ticket_type_id ticket type id
* p_event_type_id event_type id of the event (tt.event_type.id)
* p_host_id id of the host (mss.host)
* p_details_public
* p_details_private
* p_contact_id contact (stop.contact.id) that has opend the ticket
*/
    PROCEDURE newticket_new(p_ticket_id OUT NUMBER,
                            p_event_id OUT NUMBER,
                            p_ticket_type_id NUMBER,
                            p_subject VARCHAR2,
                            p_event_type_id NUMBER,
                            p_host_id NUMBER,
                            p_details_public VARCHAR2,
                            p_details_private VARCHAR2 DEFAULT NULL,
                            p_contact_id NUMBER DEFAULT NULL,
                            p_worker_id NUMBER DEFAULT NULL,
                            p_public_event BOOLEAN DEFAULT TRUE,
                            p_eventdate DATE DEFAULT sysdate,
                            p_company_id NUMBER DEFAULT NULL,
                            p_service_component_id NUMBER DEFAULT NULL,
                            p_zitadel_contact_id NUMBER DEFAULT NULL);

------------------------------------------------------------
-- change deferral date
------------------------------------------------------------
    /* change_deferral_date()
     * this procedure changes the date of a deferred ticket
     * to track the statuschanges a status change event is added to the ticket.
     *
     */
    PROCEDURE change_deferral_date(p_ticket_id NUMBER,
                                   p_contact_id NUMBER,
                                   p_defer_date DATE,
                                   p_details_public tt.event.details_public%TYPE,
                                   p_zitadel_contact_id NUMBER DEFAULT NULL);

------------------------------------------------------------
-- change ticket status
------------------------------------------------------------
    /* changestatus()
     * this procedure changes the status of a ticket.
     * to track the statuschanges a status change event is added to the ticket.
     * the statuschange event includes information about the status change reason
     * the date of the status change and who changed the ticket
     */
    PROCEDURE change_status_event_id_out(event_id OUT NUMBER,
                                         p_ticket_id NUMBER,
                                         p_status_id NUMBER,
                                         p_contact_id NUMBER,
                                         p_details_public VARCHAR2,
                                         p_details_private VARCHAR2 DEFAULT NULL,
                                         p_valid_until_date DATE DEFAULT null,
                                         p_defer_event NUMBER DEFAULT null,
                                         p_escalate_after_defer BOOLEAN DEFAULT NULL,
                                         p_hot_reason VARCHAR2 DEFAULT NULL,
                                         p_zitadel_contact_id NUMBER DEFAULT NULL);


    PROCEDURE change_status(p_ticket_id NUMBER,
                            p_status_id NUMBER,
                            p_contact_id NUMBER,
                            p_details_public VARCHAR2,
                            p_details_private VARCHAR2 DEFAULT NULL,
                            p_valid_until_date DATE DEFAULT null,
                            p_defer_event NUMBER DEFAULT null,
                            p_escalate_after_defer BOOLEAN DEFAULT NULL,
                            p_hot_reason VARCHAR2 DEFAULT NULL,
                            p_zitadel_contact_id NUMBER DEFAULT NULL);

------------------------------------------------------------
-- update ux timeout for the ticket
------------------------------------------------------------
    /* update_ux_timeout_for_ticket()
     * update the ux timeout for the given ticket
     *
     * parameters:
     * p_ticket_id: the ticket id
     * p_is_initial: whether the ticket has just been created or not
     */
    PROCEDURE update_ux_timeout_for_ticket(p_ticket_id tt.ticket.id%TYPE,
                                           p_is_initial BOOLEAN);

------------------------------------------------------------
-- change ticket worker
------------------------------------------------------------
    /* change_worker()
     * changes the worker of a ticket
     *
     * parameters:
     * p_ticket_id: ticket id (tt.ticket.id)
     * p_worker_id: new ticket worker (stop.contact.id)
     * p_contact_id: id who changed the owner (stop.contact.id)
     * p_handled_by_mcc: whether or not the ticket is an MCC ticket
     * p_is_emergency: whether the ticket is an emergency ticket
     * p_reason: optional reason for automatic worker change
     */
    PROCEDURE change_worker(p_ticket_id NUMBER,
                            p_worker_id NUMBER,
                            p_contact_id NUMBER,
                            p_handled_by_mcc NUMBER DEFAULT 0,
                            p_is_emergency NUMBER DEFAULT 0,
                            p_reason VARCHAR2 DEFAULT NULL,
                            p_zitadel_contact_id NUMBER DEFAULT NULL);

------------------------------------------------------------
-- change the ticket subject
------------------------------------------------------------
-- change_subject()
-- changes the worker of a ticket
----------------------------------------
    PROCEDURE change_subject(p_ticket_id NUMBER,
                             p_subject VARCHAR2,
                             p_contact_id NUMBER,
                             p_zitadel_contact_id NUMBER DEFAULT NULL);

------------------------------------------------------------
-- change the customer reference
------------------------------------------------------------
    /* change_customer_reference()
     * changes the customer reference of a ticket
     *
     * parameters:
     * p_ticket_id: ticket id (tt.ticket.id)
     * p_customer_reference: new customer reference string
     * p_contact_id: id who changed the customer reference (stop.contact.id)
      */
    PROCEDURE change_customer_reference(p_ticket_id NUMBER,
                                        p_customer_reference tt.ticket.customer_reference%TYPE,
                                        p_contact_id NUMBER,
                                        p_zitadel_contact_id NUMBER DEFAULT NULL);

------------------------------------------------------------
-- change label
------------------------------------------------------------
/* change_label()
 * changes the label of a ticket
 *
 * parameters:
 * p_ticket_id: ticket id (tt.ticket.id)
 * p_label_id: label id (can be null)
  */
    PROCEDURE change_label(p_ticket_id NUMBER,
                           p_label_id NUMBER);


------------------------------------------------------------
-- change label
------------------------------------------------------------
/* change_label()
 * changes the label of a ticket with history event
 *
 * parameters:
 * p_ticket_id: ticket id (tt.ticket.id)
 * p_label_id: label id (can be null)
 * p_contact_id: id who changed the ticket label
 */
    PROCEDURE change_label(p_ticket_id NUMBER,
                           p_label_id NUMBER,
                           p_contact_id NUMBER,
                           p_zitadel_contact_id NUMBER DEFAULT NULL);

------------------------------------------------------------
-- expire status
------------------------------------------------------------
/* expire_status()
 * sets private details text
 * then calls change_label() and change_status()
 *
 * parameters:
 * p_ticket_id: ticket id (tt.ticket.id)
 * p_valid_until: status valid until date
 * p_last_change: last status change date
 * p_status_id: current status id
 * p_status_name: current status name
 * p_label_name: current label id (can be null)
  */
    PROCEDURE expire_status(p_ticket_id NUMBER,
                            p_valid_until DATE,
                            p_last_change DATE,
                            p_status_id NUMBER,
                            p_status_name VARCHAR2,
                            p_label_id NUMBER);

------------------------------------------------------------
-- change the partner reference
------------------------------------------------------------
    /* change_partner_reference()
     * changes the partner reference of a ticket
     *
     * parameters:
     * p_ticket_id: ticket id (tt.ticket.id)
     * p_partner_reference: new partner reference string
     * p_contact_id: id who changed the partner reference (stop.contact.id)
      */
    PROCEDURE change_partner_reference(p_ticket_id NUMBER,
                                       p_partner_reference tt.ticket.partner_reference%TYPE,
                                       p_contact_id NUMBER,
                                       p_zitadel_contact_id NUMBER DEFAULT NULL);

------------------------------------------------------------
-- change the service and optionally host
------------------------------------------------------------
-- change_service_host()
-- changes the mss.service and optionally the host correlated
-- with the ticket.
----------------------------------------

    PROCEDURE change_service_host(p_ticket_id NUMBER,
                                  p_service_id NUMBER,
                                  p_host_id NUMBER,
                                  p_contact_id NUMBER,
                                  p_zitadel_contact_id NUMBER DEFAULT NULL);

------------------------------------------------------------
-- change the ticket owner
------------------------------------------------------------
    /* change_owner()
     * changes the owner of a ticket
     * sets the ticket owner and company
     *
     * parameters:
     * p_ticket_id: ticket id (tt.ticket.id)
     * p_owner_id: new ticket owner (stop.contact.id)
     * p_contact_id: worker id who changed the owner (stop.contact.id)
     */
    PROCEDURE change_owner(p_ticket_id NUMBER,
                           p_owner_id NUMBER,
                           p_contact_id NUMBER,
                           p_zitadel_owner_id NUMBER DEFAULT NULL,
                           p_zitadel_contact_id NUMBER DEFAULT NULL,
                           p_company_id NUMBER DEFAULT NULL,
                           p_owner_zitadel_first_name VARCHAR2 DEFAULT NULL,
                           p_owner_zitadel_last_name VARCHAR2 DEFAULT NULL);

------------------------------------------------------------
-- change the ticket company
------------------------------------------------------------
    /* change_company()
     * changes the company of a ticket
     * sets the company attribute and deletes the service id and the contact
     * if they dont belong to the same company
     *
     * parameters:
     * p_ticket_id: ticket id (tt.ticket.id)
     * p_company_id: new ticket company (stop.company.id)
     * p_contact_id: worker id who changed the owner (stop.contact.id)
     */
    PROCEDURE change_company(p_ticket_id NUMBER,
                             p_company_id NUMBER,
                             p_contact_id NUMBER,
                             p_zitadel_contact_id NUMBER DEFAULT NULL);

------------------------------------------------------------
-- change the emergency status of this ticket
------------------------------------------------------------
    /* change_emergency()
     *
     * parameters:
     * p_ticket_id: ticket id (tt.ticket.id)
     * p_emergency: 0 (no emergency) or 1 (emergency)
     * p_contact_id: worker id who did the change
     * p_is_new_ticket: 0 (not new) or 1 (new), is optional
     */
    PROCEDURE change_emergency(p_ticket_id NUMBER,
                               p_emergency NUMBER,
                               p_contact_id NUMBER,
                               p_is_new_ticket NUMBER DEFAULT 0,
                               p_zitadel_contact_id NUMBER DEFAULT NULL);

------------------------------------------------------------
-- change whether this ticket is always visible
------------------------------------------------------------
    /* change_always_visible()
     *
     * parameters:
     * p_ticket_id: ticket id (tt.ticket.id)
     * p_always_visible: 0 (not always visible) or 1 (always visible)
     * p_contact_id: worker id who did the change
     */
    PROCEDURE change_always_visible(p_ticket_id NUMBER,
                                    p_always_visible NUMBER,
                                    p_contact_id NUMBER,
                                    p_zitadel_contact_id NUMBER DEFAULT NULL);

------------------------------------------------------------
-- add an event which describes the ticket notification changes
------------------------------------------------------------
    /* change_notification()
     *
     * parameters:
     * p_ticket_id           : ticket id (tt.ticket.id)
     * p_change_text_public  : a text describing the changes made in the notification
     * p_change_text_private : a text describing the changes made in the notification
     * p_contact_id          : id of the contact  who did the change (stop.contact.id)
     */
    PROCEDURE change_notification(p_ticket_id NUMBER,
                                  p_change_text_public VARCHAR2,
                                  p_change_text_private VARCHAR2,
                                  p_contact_id NUMBER,
                                  p_zitadel_contact_id NUMBER DEFAULT NULL);

------------------------------------------------------------
-- change the private/public summary of this ticket
------------------------------------------------------------
    /* change_summary()
     *
     * parameters:
     * p_ticket_id: ticket id (tt.ticket.id)
     * p_summary_private: ticket summary only meant for OS engineers
     * p_summary_public: general ticket summary
     * p_contact_id: worker id who did the change
     */
    PROCEDURE change_summary(p_ticket_id NUMBER,
                             p_summary_private VARCHAR2,
                             p_summary_public VARCHAR2,
                             p_contact_id NUMBER,
                             p_zitadel_contact_id NUMBER DEFAULT NULL);

------------------------------------------------------------
-- change the ticket type
------------------------------------------------------------
    /* change_type()
     * changes the type of a ticket and returns the id of the status change event.
     *
     * parameters:
     * p_event_id: the id of the generated status change event.
     * p_ticket_id: ticket id (tt.ticket.id)
     * p_type_id: new ticket type (tt.ticket_type.id)
     * p_contact_id: worker id who changed the owner (stop.contact.id)
     */
    PROCEDURE change_type(p_event_id OUT NUMBER,
                          p_ticket_id NUMBER,
                          p_type_id NUMBER,
                          p_contact_id NUMBER,
                          p_zitadel_contact_id NUMBER DEFAULT NULL);

------------------------------------------------------------
-- change service component of the ticket
------------------------------------------------------------
    /* change_service_component()
     * changes the service component of a ticket and returns the id of the status change event.
     *
     * parameters:
     * p_event_id: the id of the generated status change event.
     * p_ticket_id: ticket id (tt.ticket.id)
     * p_service_component_id: new service component (mss.service_component.id)
     * p_contact_id: worker id who changed the owner (stop.contact.id)
     */
    PROCEDURE change_service_component(p_event_id OUT NUMBER,
                                       p_ticket_id NUMBER,
                                       p_service_component_id NUMBER,
                                       p_contact_id NUMBER,
                                       p_zitadel_contact_id NUMBER DEFAULT NULL);


------------------------------------------------------------
-- get unclosed ticket given its host id, type and resolve time
------------------------------------------------------------
    /* get_next_recent_ticket()
     * find a particular ticket
     *
     * parameters:
     * p_last_ticket_id: the resulting ticket_id must be greater
     * p_host_id: host to which ticket is assigned (NULL for any, 0 for unassigned!)
     * p_ticket_type_id: the requested ticket type (NULL for any)
     * p_resolve_age: return tickets with resolve time not longer ago than this (in secs)
     */
    FUNCTION  get_next_recent_ticket(p_last_ticket_id NUMBER,
                                     p_host_id NUMBER,
                                     p_ticket_type_id NUMBER,
                                     p_resolve_age NUMBER) RETURN NUMBER;

------------------------------------------------------------
-- merge tickets
------------------------------------------------------------
    /* This procedure merges two tickets
     * parameters are:
     * p_ticket_id ticket id of the ticket that is merged.
     * p_mticket_id ticket id of the ticket in which the first ticket is merged
     */

    PROCEDURE merge_tickets(p_ticket_id NUMBER,
                            p_mticket_id NUMBER,
                            p_contact_id NUMBER,
                            p_zitadel_contact_id NUMBER DEFAULT NULL);

------------------------------------------------------------
-- replace_id_placeholders
------------------------------------------------------------
    /* Utility function:
     * Replace strings '##event_id##' and '##ticket_id##' in the
     * given text with the given IDs.
     * If the result string is larger than 4000 characters
     * after the replacement, it is truncated.
     */

    FUNCTION replace_id_placeholders(p_text VARCHAR2,
                                     p_ticket_id NUMBER,
                                     p_event_id NUMBER) RETURN VARCHAR2;


------------------------------------------------------------
-- trigger_escalation
------------------------------------------------------------
    /* Triggers explicit escalation for the given ticket
     * ticket_id : the ticket to escalate
     * p_contact_id: the contact triggering the escalation
     * p_triggering_event_id: the event that triggered the escalation
     */
    PROCEDURE trigger_escalation(p_ticket_id NUMBER, p_contact_id NUMBER, p_triggering_event_id NUMBER,
                                 p_zitadel_contact_id NUMBER DEFAULT NULL);


------------------------------------------------------------
-- rate_ticket
------------------------------------------------------------
    /* Creates a ticket rating
     * p_rating_id: returns the new rating ID
     * p_ticket_id: the ticket to rate
     * p_rating_event_id: the corresponding event
     * p_contact_id: the user who rated the ticket
     * p_by_engineer: rating created by engineer
     * p_rating_value: the rating value
     */
    PROCEDURE rate_ticket(p_rating_id OUT NUMBER, p_ticket_id NUMBER, p_rating_event_id NUMBER, p_contact_id NUMBER,
                          p_by_engineer NUMBER, p_rating_value NUMBER, p_zitadel_contact_id NUMBER DEFAULT NULL);

------------------------------------------------------------
-- add_docs_page
------------------------------------------------------------
    /**
     * Add a Docs page to the ticket
     * p_ticket_docs_page_id: Returns the new ticket-docs-page ID
     * p_ticket_id: The ID of the ticket
     * p_page_id: The ID of the page to be attached
     * p_page_version: The version of the page to be attached
     * p_page_title: The title of the page to be attached
     * p_hot_issue: Whether the page documents a currently hot issue
     * p_contact_id: The contact who adds the Docs page
     */
    PROCEDURE add_docs_page(p_ticket_docs_page_id OUT NUMBER,
                            p_ticket_id NUMBER,
                            p_page_id NUMBER,
                            p_page_version NUMBER,
                            p_page_title VARCHAR2,
                            p_hot_issue NUMBER,
                            p_contact_id NUMBER,
                            p_zitadel_contact_id NUMBER DEFAULT NULL);

------------------------------------------------------------
-- remove_docs_page
------------------------------------------------------------
    /**
     * Removes a Docs page from the ticket
     * p_ticket_docs_page_id: The ID of the ticket-docs-page
     * p_page_title: The title of the page to be removed
     * p_contact_id: The contact who removes the Docs page
     */
    PROCEDURE remove_docs_page(p_ticket_docs_page_id NUMBER,
                               p_page_title VARCHAR2,
                               p_contact_id NUMBER,
                               p_zitadel_contact_id NUMBER DEFAULT NULL);

------------------------------------------------------------
-- add_related_ticket
------------------------------------------------------------
    /**
     * adds a ticket to the list of related tickets for a ticket
     * p_ticket_id: The ID of the ticket
     * p_related_ticket_id: The ID of the related ticket to add
     * p_contact_id: ID of the contact who added the related ticket
     */
    PROCEDURE add_related_ticket(p_ticket_id tt.ticket.id%TYPE, p_related_ticket_id tt.ticket.id%TYPE, p_contact_id stop.contact.id%TYPE,
                                 p_zitadel_contact_id NUMBER DEFAULT NULL);


------------------------------------------------------------
-- remove_related_ticket
------------------------------------------------------------
    /**
     * removes a ticket from the list of related tickets for a ticket
     * p_ticket_id: The ID of the ticket
     * p_related_ticket_id: The ID of the related ticket to remove
     * p_contact_id: ID of the contact who removeded the related ticket
     */
    PROCEDURE remove_related_ticket(p_ticket_id tt.ticket.id%TYPE, p_related_ticket_id tt.ticket.id%TYPE, p_contact_id stop.contact.id%TYPE,
                                    p_zitadel_contact_id NUMBER DEFAULT NULL);

------------------------------------------------------------
-- add_related_file
------------------------------------------------------------
    /**
     * adds a file to the list of related MC files of a ticket
     * p_ticket_id: The ID of the ticket
     * p_related_file_id: The ID of the related file to add
     * p_contact_id: ID of the contact who added the related file
     */
    PROCEDURE add_related_file(p_ticket_id tt.ticket.id%TYPE, p_related_file_id mc.mc_file.id%TYPE, p_contact_id stop.contact.id%TYPE,
                               p_zitadel_contact_id NUMBER DEFAULT NULL);


------------------------------------------------------------
-- remove_related_file
------------------------------------------------------------
    /**
     * removes a mc file from the list of related file of a ticket
     * p_ticket_id: The ID of the ticket
     * p_related_file_id: The ID of the related file to remove
     * p_contact_id: ID of the contact who removeded the related file
     */
    PROCEDURE remove_related_file(p_ticket_id tt.ticket.id%TYPE, p_related_file_id mc.mc_file.id%TYPE, p_contact_id stop.contact.id%TYPE,
                                  p_zitadel_contact_id NUMBER DEFAULT NULL);


------------------------------------------------------------
-- classify_request
------------------------------------------------------------
    /**
     * Classifies the initial request based on the "customer's skill level".
     * p_ticket_id: The ID of the ticket
     * p_classification: 1 = very precise, 2 = standard, 3 = imprecise
     * p_contact_id: ID of the contact who change the comment marking
     *
     * Note that only one of the three classifications (precise, standard, imprecise) can be given at a time.
     */
    PROCEDURE classify_request(p_ticket_id tt.ticket.id%TYPE, p_classification tt.ticket_request_classification.classification%TYPE,
                               p_contact_id stop.contact.id%TYPE, p_zitadel_contact_id NUMBER DEFAULT NULL);


------------------------------------------------------------
-- clear_todo_list
------------------------------------------------------------
    /**
     * Clears the todo list of the given ticket
     * p_ticket_id: The ID of the ticket
     * p_contact_id: ID of the contact who cleared the todo list
     * p_add_history_event: if true, adds a history event
     */
    PROCEDURE clear_todo_list(p_ticket_id NUMBER, p_contact_id NUMBER, p_add_history_event NUMBER DEFAULT 1, p_zitadel_contact_id NUMBER DEFAULT NULL);

------------------------------------------------------------
-- add_todo_item
------------------------------------------------------------
    /**
     * Adds a new todo item to a ticket
     * p_todo_item_id: Returns the ID of the new todo item
     * p_ticket_id: The ID of the ticket
     * p_seq_no: The sequence number of the todo item
     * p_details: The details
     * p_todo_item_status_id: The status ID
     * p_contact_id: ID of the contact who added the todo item
     * p_todo_item_is_public: boolint indicating whether this event is public or not
     */
    PROCEDURE add_todo_item(p_todo_item_id OUT NUMBER,
                            p_ticket_id NUMBER,
                            p_seq_no NUMBER,
                            p_details VARCHAR2,
                            p_todo_item_status_id NUMBER,
                            p_contact_id NUMBER,
                            p_todo_item_is_public NUMBER DEFAULT 0,
                            p_zitadel_contact_id NUMBER DEFAULT NULL);

------------------------------------------------------------
-- update_todo_item_status
------------------------------------------------------------
    /**
     * Updates the status of a todo item.
     *
     * p_ticket_id: The ID of the ticket
     * p_seq_no: The sequence number of the todo item
     * p_todo_item_status_id: The status ID
     * p_contact_id: ID of the contact who updated the status
     */
    PROCEDURE update_todo_item_status(p_ticket_id NUMBER,
                                      p_seq_no NUMBER,
                                      p_todo_item_status_id NUMBER,
                                      p_contact_id NUMBER,
                                      p_zitadel_contact_id NUMBER DEFAULT NULL);


------------------------------------------------------------
-- updateTicketFlow
------------------------------------------------------------
    /**
     * Checks if a flow entry for a ticket needs to be updated
     * Should be called by state/type/worker changes
     * that may influence if a ticket is in the MCC queue or not
     */
    PROCEDURE updateTicketFlow(p_ticket_id NUMBER, p_prev_status_id NUMBER DEFAULT NULL, p_prev_status_change_date DATE DEFAULT NULL);

------------------------------------------------------------
-- deleteTicket
------------------------------------------------------------
    /**
     * Deletes a ticket from the database.
     * CAUTION: This should only be done in exceptional cases to redact data (like exam tickets).
     */
    PROCEDURE deleteTicket(p_ticket_id NUMBER);

END ticket_interface;
/