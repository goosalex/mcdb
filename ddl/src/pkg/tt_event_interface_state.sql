--liquibase formatted sql logicalFilePath:pkg/tt_event_interface_state.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE tt.event_interface_state AS

    -- Application specific exceptions

    ticket_closed EXCEPTION;
    S_ERRNO_TICKET_CLOSED CONSTANT NUMBER := -20980;
    PRAGMA EXCEPTION_INIT (ticket_closed, -20980);

END event_interface_state;
/
