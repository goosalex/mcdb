--liquibase formatted sql logicalFilePath:pkg/report_osag_channel.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE REPORT.OSAG_CHANNEL AS
    /*
     * Provides the procedure responsible for running the
     * report queries as registered in REPORT.CHANNELKEY
     */


/**
 * Run the queries specified in report.channelkey
 * (according the specified schedule)
 * and write the results back to report.channelvalue
 *
 * Clean up the value history
 *
 * This procedure is run as a job every minute.
 */
    PROCEDURE run_queries;

/**
 * Host counter to be run monthly to get count required for dashboards in Qlik
 **/
    PROCEDURE count_hosts;

END OSAG_CHANNEL;
/
