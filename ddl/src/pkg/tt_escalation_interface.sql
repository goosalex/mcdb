--liquibase formatted sql logicalFilePath:pkg/tt_escalation_interface.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE tt.escalation_interface AS

    /*
     * this package implements all the logic that is needed for escalating events/tickets to
     * mission control, pikett, securitas and the customers.
     */

    TYPE ref_cursor IS REF CURSOR;

    /* this procedure adds a new escalation to open systems to a ticket
     * it should be called for every event that is escalated.
     * The procedure checks then if we really need to escalate the ticket for the given event.
     *
     * parameters:
     *
     * event id: event that is escalated (tt.event.id) note that tt.event.ticket_id must not be NULL
     */
    PROCEDURE escalate_os(p_event_id NUMBER);

    /* this procedure adds a new customer escalation to the ticket with the given id
     * Currently, it will be called if a connection_down event arises (cf. table EVENT_TYPE_ACTION)
     * The Securitas Wizard will pick it up and Securitas will try to reach a local contact.
     * Escalation to the customer is only done during off hours, otherwise OSAG is escalated
     *
     *
     * parameters:
     *
     * p_event_id: id of event that caused the escalation
     */
    PROCEDURE escalate_customer(p_event_id NUMBER);

    /* this procedure escalates an isp outage event (not necessarily from osag) to open system
     * in a unorthodox way:
     * a new trouble ticket for open systems associated to no service is created,
     * and the details of the isp outage are described in an incident report event
     * (which is then automatically escalated)
     *
     * p_event_id : the id of the original isp outage event
     */
    PROCEDURE escalate_isp_outage_to_os(p_event_id NUMBER);


    /* this procedure does nothing and is used as a nop procedure
     * for a nop event action (used for db properties)
     *
     * p_event_id : the id of the event that should not cause further actions
     */
    PROCEDURE nop(p_event_id NUMBER);

    /* this procedure clears the escalation status for customer escalations
     * of a given ticket.
     * Note that the escalation status is only cleared if the ticket has
     * it set to customer escalation
     * It's there to be used by other pl/sql procs (such as mc.monitoring)
     *
     * p_ticket_id: the id of the ticket to clear
     */
    PROCEDURE clear_customer_escalation(p_ticket_id tt.ticket.id%TYPE);

    /*
     * ==> NOTE on possible race conditions in the escalation procedure and their handling <==
     *
     * As of April 2007, it is possible that a ticket is escalated more than once. To provide this
     * functionality, the escalation status has been introduced (TT.ESCALATION_STATUS), which decides
     * whether a ticket has to be escalated or not.
     * Events that lead to an escalation of a ticket can be added by various sources including GUMA,
     * SANG, and MC Ticketing, furthermore the Securitas Wizard edits the escalation status.
     * This is why the subject race conditions has to be addressed, i.e. it has to be assured
     * that no escalation is lost when Murphy hits us and updates come in at the same time from
     * different sources.
     *
     * Here are the measures taken:
     * 1. We distinguish between escalation to open system (os) and escalation to customer/local contact
     * 2. Tickets that are marked for escalation to os get escalated even if they are deferred
     * 3. Tickets that are marked for escalation to the customer are not escalated if they are deferred,
     *    this is a feature!
     * 4. If a ticket should be marked for escalation to the customer, the according update statement always
     *    ensures that it has not been marked just before for escalation to os. This is done with an according
     *    WHERE clause in the update statement.
     * 5. If a ticket escalated to the customer gets its escalation status cleared, i.e. set to 0, there is also
     *    an according WHERE clause, which ensures that the update statement does not clear an escalation to os.
     * 7. If a ticket is already marked for escalation, it will not be escalated again, i.e. no new events will be
     *    added.
     * 8. If a deferred ticket marked for escalation to customer gets hot again, it will be marked for escalation to os.
     *    The same applies if it gets assigned one of the states 'waiting', 'third party', 'deferred', 'resolved'
     * 9. If a deferred ticket marked for escalation to customer gets acknowledged or opened, the escalation status will
     *    be set to 0. According events are added (escalation to os, acknowledged by MCE)
     *
     */

END escalation_interface;
/
