--liquibase formatted sql logicalFilePath:pkg/tt_event_interface.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE tt.event_interface AS

    /*
     * this package is the primary db-interface for our ticketing system
     * it enables to write new event to the db or to add events to existing tickets
     */

    -- -------------------------------------------------------------------
    -- NOTE:
    -- Please declare constants, exceptions, and global variables
    -- in the according state package (e.g. event_interface_state)
    -- -------------------------------------------------------------------

    /* newevent_new
     * this procedure can be used to add a new event to the ticket system
     * the system tries to find an already open ticket for this event
     * if it cant find an open ticket to add the event to, the system creates a new ticket
     * the event is dropped, if there is an open service window belonging to this host_id
     * which requires "disable events".
     *
     * parameters
     * p_event_id event id that is assigned to this event OUT
     * p_type_id event_type id of the event (tt.event_type.id)
     * p_host_id (mss.host)
     * p_details_public
     * p_details_private
     * p_contact_id contact that has generated this event.
     * p_zitadel_contact_id zitadel user that has generated this event.
     * p_company_id company that is linked to this event: used togher with p_zitadel_contact_id
                    because in this case we cannpt lookup the company in the DB
     */
    PROCEDURE newevent_new(p_event_id OUT NUMBER,
                           p_type_id NUMBER,
                           p_host_id NUMBER,
                           p_details_public VARCHAR2,
                           p_details_private VARCHAR2 DEFAULT NULL,
                           p_contact_id NUMBER DEFAULT NULL,
                           p_public_event BOOLEAN DEFAULT TRUE,
                           p_eventdate DATE DEFAULT sysdate,
                           p_ticket_type_id NUMBER DEFAULT NULL,
                           p_service_component_id NUMBER DEFAULT NULL,
                           p_zitadel_contact_id NUMBER DEFAULT NULL,
                           p_company_id NUMBER DEFAULT NULL);



    /* addevent_new
     * this procedure adds an event to a ticket
     * this may change the status, priority or subject of the ticket
     * the event id is provided to the caller as an out parameter
     */
    PROCEDURE addevent_new(p_event_id OUT NUMBER,
                           p_ticket_id NUMBER,
                           p_type_id NUMBER,
                           p_host_id NUMBER,
                           details_public VARCHAR2,
                           details_private VARCHAR2 DEFAULT NULL,
                           p_contact_id NUMBER DEFAULT NULL,
                           public_event BOOLEAN DEFAULT TRUE,
                           eventdate DATE DEFAULT sysdate,
                           notify_event BOOLEAN DEFAULT FALSE,
                           p_zitadel_contact_id NUMBER DEFAULT NULL,
                           p_peer_contact_id NUMBER DEFAULT NULL);

    /* moveevent
     * this procedure moves an event from one ticket to another. If the event
     * does not belong to the old ticket or the event is already attached to
     * the new ticket then nothing happens. Howver if the event does not exist,
     * or the new ticket does not exist a warning is written to the log.
     *
     */
    PROCEDURE moveevent(p_event_id NUMBER, p_oldticket_id NUMBER, p_newticket_id NUMBER);

    /*
     * determines the ticket_type for a new ticket that is
     * created by an event of type p_event_type_id
     */
    FUNCTION ticket_type_for_event_type(p_event_type_id NUMBER) RETURN NUMBER;

    /* exec_event_type_actions
     *
     * this procedure runs the event type actions specified in the
     * event_action table
     * it looks for matching event type actions for the event type,
     * if a key id for a procedure is defined and the event is associated
     * with a host, a lookup in the dbprop is done. If no key id is given,
     * the procedure_name field of the table is taken, if there are no values
     * at all (i.e. dbprop is null, procedure_name also null) nothing is done.
     *
     * Parameters:
     *
     * p_event_id: id of the event for which we execute the event type actions
     *
     */
    PROCEDURE exec_event_type_actions(p_event_id NUMBER);

    /* add_history_event
     *
     * This procedure creates a new event and linkes the event to the specified
     * ticket. If a contact_id is specified also a linking between the contact and
     * the event is created.
     * The procedure then calls the notification procedure from TT.OSAG_NOTIFY
     * to start the notification process.
     *
     * Parameters:
     *
     * p_event_id:              id of the event which is created in the procedure
     * p_ticket_id:             id of the ticket this event is linked with
     * p_event_type_id:         id of the type of this event
     * p_host_id:               id of the host this event is linked to
     * p_company_id:            id of the company this event is linked with
     * p_details_public:        public details of the event
     * p_details_private:       private details of the event
     * p_public_event:          specifies whether this event is public or not
     * p_eventdate:             date of this event
     * p_contact_id:            id of the contact this event is linked with
     * p_zitadel_contact_id:    zitadel user this event is linked with
     */
    PROCEDURE add_history_event(p_event_id OUT NUMBER,
                                p_ticket_id NUMBER,
                                p_event_type_id NUMBER,
                                p_host_id NUMBER,
                                p_company_id NUMBER,
                                p_details_public VARCHAR2,
                                p_details_private VARCHAR2 DEFAULT NULL,
                                p_public_event BOOLEAN DEFAULT TRUE,
                                p_eventdate DATE DEFAULT sysdate,
                                p_contact_id NUMBER DEFAULT NULL,
                                p_zitadel_contact_id NUMBER DEFAULT NULL
             );

    /* demote_event
     *
     * Demotes the given event
     *
     * parameters:
     * p_event_id: ID of the event to be demoted
     * p_contact_id: ID of the contact who demoted the event
     */
    PROCEDURE demote_event(p_event_id NUMBER, p_contact_id NUMBER);

    /* promote_event
     *
     * Promotes the given event
     *
     * parameters:
     * p_event_id: ID of the event to be promoted
     * p_contact_id: ID of the contact who promoted the event
     */
    PROCEDURE promote_event(p_event_id NUMBER, p_contact_id NUMBER);

END event_interface;
/
