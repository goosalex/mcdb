# Ticketing Interfaces

From panta PR #12609:
    
    This fixes the behaviour where (at least) the current internal ticketing
    API does not trigger escalation for _some_ events that were added to a
    ticket, even though escalation for events that are added to a new ticket
    works (for the same event type).
    
    There are two procedures exposed by the ticketing event interface
    `tt.event_interface` to generate new ticket events: `newevent_new` and
    `addevent_new`.
    
    Procedure `addevent_new` adds an event to an _existing_ ticket, which
    has to be provided, and can even deal with a provided ticket in status
    `110` `merged`. The internal ticketing API uses this stored procedure to
    update tickets.
    
    Procedure `newevent_new` does not take a ticket as parameter, but
    attempts to find a recent ticket based on the provided host_id (possibly
    also based on other information). If no recent ticket was found, then a
    new ticket is created automatically. The internal ticketing API uses
    this stored procedure to create new tickets.
    
    Note that this `newevent_new` procedure is indirectly used by the
    `submit_msg` procedure (via the `submit_msg_newevent` procedure) from
    the `GUMA2.OSAG_IMPLICATION` package, which is used by the GUMA server
    to post GUMA messages to tickets. It is the place where the current
    ticket merging logic for GUMA resides, and this is exactly what we want
    to do better in `alert-handler` with alert grouping (i.e. this procedure
    must not be used for updating tickets).
    
    Escalation of tickets is currently implemented as follows:
    - Procedure `escalate_os` in the escalation interface
      `tt.escalation_interface` triggers an escalation to Mission Control
      (as we know it). It guards against having multiple escalations at the
      same time for the same ticket.
    - The escalation interface is triggered by (at least) the procedure
      `exec_event_type_actions` in the ticket event interface. Given an
      event id, this calls `escalate_os` when the event type `TT.EVENT_TYPE`
      of the provided event id has `ESCALATION` set to `1`.
    
    Event type actions (i.e. escalation to OS) are always executed by
    `newevent_new` for each case new ticket and update ticket seperately.
    
    Event type actions are currently _not_ executed in the `addevent_new`
    procedure, which leads to this behaviour. This PR moves the call to
    execute event type actions from `newevent_new` to `addevent_new`, since
    the former anyway calls the latter when updating a ticket.
    
    This then automatically makes the internal ticketing API behave
    consistently regardless. The only point where we possibly introduce side
    effects is within the Java world, where a `escalateTicket` `boolean` is
    exposed. With the changes here, we would override this `escalateTicket`
    in the case when it is set to `false`, but the provided `eventType` has
    escalation set. Since 8 of 9 event types that have escalation configured
    are automatic events from a monitoring system (i.e. the RED events in a
    ticket) usually added through GUMA, the effect of this should be
    negligible, in particular since the ticketing viewer doesn't allow
    adding RED events (ok, aside from the host diary information, which
    doesn't escalate).
