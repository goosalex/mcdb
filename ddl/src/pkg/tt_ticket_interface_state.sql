--liquibase formatted sql logicalFilePath:pkg/tt_ticket_interface_state.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE tt.ticket_interface_state AS

    -- Application specific exceptions

    ticket_not_scheduled EXCEPTION;
    S_ERRNO_TICKET_NOT_SCHEDULED CONSTANT NUMBER := -20981;
    PRAGMA EXCEPTION_INIT (ticket_not_scheduled, -20981);

    ticket_scheduling_open EXCEPTION;
    S_ERRNO_TICKET_SCHEDULING_OPEN CONSTANT NUMBER := -20982;
    PRAGMA EXCEPTION_INIT (ticket_scheduling_open, -20982);

END ticket_interface_state;
/
