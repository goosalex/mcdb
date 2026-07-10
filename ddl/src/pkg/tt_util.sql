--liquibase formatted sql logicalFilePath:pkg/tt_util.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE tt.util AS

    /*
     * this package contains procedures to automate the ticket system
     * i.e. reopen deferred tickets or close resolved tickets.
     *
     * use this package together with  the script tt.submit_user_jobs to
     * schedule the procedures defined in this package.
     */

    /*
     * procedure check_resolved_tickets
     *
     * this procedure looks for resolved tickets that are in
     * the state "resolved" for more thatn two weeks.
     * The tickets are set to the state closed.
     */
    PROCEDURE check_resolved_tickets;

    /*
     * procedure check_ticket_status
     *
     * this procedure looks for tickets that have been too long in
     * a non-hot state and changes the state to hot. the amount of time
     * a ticket can spend as non-hot depends on it's type, status and
     * emergency flag.
     */
    PROCEDURE check_ticket_status;

    /*
     * procedure update_status_valid_until
     *
     * this procedures updates the attribute status_valid_until_date of
     * tt.ticket with predefined time offsets for each ticket status/type
     * or to the given date, if the ticket status is waiting or third party
     */
    PROCEDURE update_status_valid_until(p_ticket_id NUMBER, p_valid_until_date DATE DEFAULT null);

    /*
     * Looks for DNIDS tickets that can be automatically resolved.
     */
    PROCEDURE check_dnids_tickets_to_resolve;


    /*
     * procedure close_old_dev_tickets
     *
     * this procedure automatically closes non-Project mode MC tickets that had no update in the last
     * 14 days. It is supposed to only be run on DEV hosts. Idea is to clear abandoned experiments to
     * improve user experience for actually ongoing work. Tickets are closed with a corresponding
     * event to provide context and avoid automatic re-opening.
     */

     PROCEDURE close_old_dev_tickets;
END util;
/
