--liquibase formatted sql logicalFilePath:pkg/ticketevolution_calculator.sql
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE TICKETEVOLUTION.CALCULATOR AS
  /**
   * Materializes a single ticket.
   */
  procedure materialize_tickev(p_ticket_id tt.EVENT.ticket_id%type);

  /**
   * Materializes all tickets since last run (see state table).
   * The transaction is committed within the procedure!
   */
  procedure materialize_incremental;
END CALCULATOR;
/
