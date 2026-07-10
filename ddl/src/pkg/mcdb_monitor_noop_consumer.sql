--liquibase formatted sql logicalFilePath:pkg/mcdb_monitor_noop_consumer.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE MCDB_MONITOR.NOOP_CONSUMER authid definer AS
    procedure clean_queue(
        queue_name VARCHAR2
    );
    procedure noop_callback(
        context  IN raw,
        reginfo  IN sys.aq$_reg_info,
        descr    IN sys.aq$_descriptor,
        payload  IN raw,
        payloadl IN number
    );

    procedure localdebug_callback(
        context  IN raw,
        reginfo  IN sys.aq$_reg_info,
        descr    IN sys.aq$_descriptor,
        payload  IN raw,
        payloadl IN number
    );
END NOOP_CONSUMER;
/
