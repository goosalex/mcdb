--liquibase formatted sql logicalFilePath:pkgb/mcdb_monitor_noop_consumer.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE BODY MCDB_MONITOR.NOOP_CONSUMER AS
    procedure clean_queue(
        queue_name VARCHAR2
    ) IS
        dequeue_options    DBMS_AQ.dequeue_options_t;
        message_properties DBMS_AQ.message_properties_t;
        dq_msgid           RAW(16);
        payload            RAW(1);
        no_messages exception;
        end_of_fetch exception ;
        pragma exception_init (no_messages, -25263);
        pragma exception_init ( end_of_fetch, -25228 );
        msg_count number(2);
        has_more  BOOLEAN DEFAULT true;
    BEGIN
        dequeue_options.consumer_name := null;
        dequeue_options.wait := DBMS_AQ.NO_WAIT;
        dequeue_options.navigation := DBMS_AQ.FIRST_MESSAGE;
        dequeue_options.dequeue_mode := dbms_aq.remove_nodata;
        while has_more
            loop
                msg_count := 0;
                DBMS_AQ.DEQUEUE(queue_name => queue_name,
                                dequeue_options => dequeue_options,
                                message_properties => message_properties,
                                payload => payload,
                                msgid => dq_msgid
                    );
                dbms_output.put_line('Message id : ' || UTL_RAW.CAST_TO_VARCHAR2(dq_msgid) || ' removed');
                msg_count := msg_count + 1;
                dequeue_options.msgid := null;
                dequeue_options.navigation := DBMS_AQ.NEXT_MESSAGE;
            END LOOP;
    EXCEPTION
        WHEN no_messages OR end_of_fetch THEN
            DBMS_OUTPUT.PUT_LINE('No of Messages Removed: ' || msg_count);
            has_more := FALSE;
    END;

    procedure noop_callback(
        context  raw,
        reginfo  sys.aq$_reg_info,
        descr    sys.aq$_descriptor,
        payload  raw,
        payloadl number
    )

    as
        dequeue_options    dbms_aq.dequeue_options_t;
        message_properties dbms_aq.message_properties_t;
        message_handle     raw(16);
        msg                raw(1);
    begin
        dequeue_options.consumer_name := null;
        dequeue_options.wait := DBMS_AQ.NO_WAIT;
        dequeue_options.navigation := DBMS_AQ.FIRST_MESSAGE;
        dequeue_options.dequeue_mode := dbms_aq.remove_nodata;

        dbms_aq.dequeue(
                queue_name         => descr.queue_name,
                dequeue_options    => dequeue_options,
                message_properties => message_properties,
                payload            => msg,
                msgid              => message_handle
            );
    end noop_callback;

    procedure localdebug_callback(
        context  raw,
        reginfo  sys.aq$_reg_info,
        descr    sys.aq$_descriptor,
        payload  raw,
        payloadl number
    )

    as
        dequeue_options    dbms_aq.dequeue_options_t;
        message_properties dbms_aq.message_properties_t;
        message_handle     raw(16);
        msg                MCDB_MONITOR.PLOG_MESSAGE_TYPE;
    begin
        dequeue_options.msgid         := descr.msg_id;
        dequeue_options.consumer_name := descr.consumer_name;

        dbms_aq.dequeue(
                queue_name         => descr.queue_name,
                dequeue_options    => dequeue_options,
                message_properties => message_properties,
                payload            => msg,
                msgid              => message_handle
            );
        INSERT INTO MCDB_MONITOR.PLOG_OUTPUT (
            message,severity,loglevel,sender_user,sender_session,sender_proc
        )
        VALUES (
            msg.message,msg.severity,msg.loglevel,msg.sender_user,msg.sender_session,msg.sender_proc
            );

    end localdebug_callback;


END NOOP_CONSUMER;
/
