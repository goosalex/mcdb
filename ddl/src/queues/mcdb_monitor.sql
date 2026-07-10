BEGIN
    DBMS_AQADM.CREATE_QUEUE_TABLE(
            queue_table => 'MCDB_MONITOR.plog_messages_table',
            queue_payload_type => 'MCDB_MONITOR.plog_message_type',
            multiple_consumers =>  true
        );

    DBMS_AQADM.CREATE_QUEUE(
            queue_name => 'MCDB_MONITOR.plog_messages',
            queue_table => 'MCDB_MONITOR.plog_messages_table'
        );

    DBMS_AQADM.START_QUEUE(
            queue_name => 'MCDB_MONITOR.plog_messages'
        );

    DBMS_AQADM.START_QUEUE('MCDB_MONITOR.AQ$_PLOG_MESSAGES_TABLE_E', false, true);


    -- permissions
    DBMS_AQADM.GRANT_SYSTEM_PRIVILEGE(
            privilege          =>    'DEQUEUE_ANY',
            grantee            =>    'MCDB_MONITOR',
            admin_option       =>     FALSE);
    DBMS_AQADM.GRANT_SYSTEM_PRIVILEGE(
            privilege          =>    'ENQUEUE_ANY',
            grantee            =>    'OSAG',
            admin_option       =>     FALSE);

    -- subscribers
    IF SYS_CONTEXT('userenv','con_name') LIKE 'XEPDB_' THEN
        -- subscribers
        dbms_aqadm.add_subscriber(
                queue_name => 'MCDB_MONITOR.plog_messages',
                subscriber =>  sys.aq$_agent(
                        name     => 'local_plog_consumer',
                        address  =>  null,
                        protocol =>  null
                    )
            );

        dbms_aq.register(
                sys.aq$_reg_info_list(
                        sys.aq$_reg_info(
                                name      => 'MCDB_MONITOR.plog_messages:local_plog_consumer',
                                namespace =>  DBMS_AQ.NAMESPACE_AQ,
                                callback  => 'plsql://MCDB_MONITOR.NOOP_CONSUMER.localdebug_callback',
                                context   =>  utl_raw.cast_to_raw('Log last result consumer')
                            )
                    ),
                1);
    end if;

END;
/
