--liquibase formatted sql logicalFilePath:pkgb/mc_monitoring.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE BODY mc.monitoring IS
-------------------------------------------------------------------------------
-- update_host_status: updates or inserts a connection status for a host to the
-- mon_server_connection table. Note that this procedure does not update
-- the "overall status" of the host.
-- this procedure is now a wrapper for update_host_status_with_ip()
-------------------------------------------------------------------------------
    PROCEDURE update_host_status
    (
        p_host_id       mc.mon_server_connection.host_id%TYPE,
        p_mon_server_id mc.mon_server_connection.mon_server_id%TYPE,
        p_con_timestamp mc.mon_server_connection.con_timestamp%TYPE,
        p_status        mc.mon_server_connection.status%TYPE,
        p_details       mc.mon_server_connection.details%TYPE
    ) IS

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        update_host_status_with_ip(
                p_host_id,
                p_mon_server_id,
                p_con_timestamp,
                p_status,
                p_details,
                NULL,
                NULL,
                NULL
            );
    END update_host_status;

-------------------------------------------------------------------------------
-- update_host_status_with_ip: updates or inserts a connection status for a host to the
-- mon_server_connection table. Note that this procedure does not update
-- the "overall status" of the host.
-- this procedure allows to specify what IP address could be reach.
-------------------------------------------------------------------------------
    PROCEDURE update_host_status_with_ip
    (
        p_host_id        mc.mon_server_connection.host_id%TYPE,
        p_mon_server_id  mc.mon_server_connection.mon_server_id%TYPE,
        p_con_timestamp  mc.mon_server_connection.con_timestamp%TYPE,
        p_status         mc.mon_server_connection.status%TYPE,
        p_details        mc.mon_server_connection.details%TYPE,
        p_ipv4_address   mc.mon_server_connection.ipv4_address%TYPE,
        p_ipv6_address_1 mc.mon_server_connection.ipv6_address_1%TYPE,
        p_ipv6_address_2 mc.mon_server_connection.ipv6_address_2%TYPE
    ) IS

        -- Variable declarations
        S_PREFIX CONSTANT VARCHAR2(32) := 'update_host_status_with_ip(): ';

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        UPDATE mon_server_connection
        SET con_timestamp  = p_con_timestamp,
            status         = p_status,
            entry_date     = SYSDATE,
            details        = p_details,
            ipv4_address   = p_ipv4_address,
            ipv6_address_1 = p_ipv6_address_1,
            ipv6_address_2 = p_ipv6_address_2
        WHERE host_id        = p_host_id
          AND mon_server_id  = p_mon_server_id;

        IF ( SQL%ROWCOUNT=0 ) THEN
            -- there was no row to update
            -- insert a new row
            INSERT INTO mon_server_connection (
                con_timestamp,
                status,
                entry_date,
                details,
                host_id,
                mon_server_id,
                ipv4_address,
                ipv6_address_1,
                ipv6_address_2)
            VALUES (p_con_timestamp,
                    p_status,
                    SYSTIMESTAMP,
                    p_details,
                    p_host_id,
                    p_mon_server_id,
                    p_ipv4_address,
                    p_ipv6_address_1,
                    p_ipv6_address_2);
        END IF;
    END update_host_status_with_ip;

-------------------------------------------------------------------------------
-- has_active_SW: return 1 if host has active Service Window, else 0
--
-- parameter:  host_id
-- returns:    boolean
-------------------------------------------------------------------------------
    FUNCTION has_active_SW(p_host_id mss.host.id%TYPE) RETURN BOOLEAN IS

        S_PREFIX CONSTANT VARCHAR2(32) := 'has_active_SW(): ';
        v_has_SW NUMBER;

    BEGIN
        -- see if there is a service window that disables escalations currently open
        SELECT COUNT(*) INTO v_has_SW
        FROM tt.ticket t
                 INNER JOIN tt.service_window s
                            ON (s.ticket_id = t.id)
                 INNER JOIN tt.host2service_window h2s
                            ON (h2s.service_window_id = s.id)

                 LEFT JOIN tt.maintenance_window m
                           ON (s.id = m.service_window_id)
                 LEFT JOIN tt.cust_maintenance_window cm
                           ON (s.id = cm.service_window_id)

        WHERE
                t.status_id < mc.monitoring_state.TICKET_STATUS_RESOLVED AND s.end_date > SYSTIMESTAMP AND s.start_date < SYSTIMESTAMP
          AND (m.disable_conn_escalation = 1 OR cm.disable_conn_escalation = 1) AND h2s.host_id = p_host_id;

        IF ( v_has_SW > 0 ) THEN
            RETURN TRUE;
        ELSE
            RETURN FALSE;
        END IF;
    END has_active_SW;

-------------------------------------------------------------------------------
-- (local) migrate_event_id: copy event_id from last connection_interrupt_closed
--                   into connection_interrupt_open for hosts that just
--                   switch the down state (hence the switch date parameter).
--
-- example: - old: inactive down
--          - new: active down
--          This function copies event_id from closed entry into open entry
--                              if and only if 'new' follows 'old'
--
-- param: p_host_id
--        p_switch_date
-- return: -
-------------------------------------------------------------------------------
    PROCEDURE migrate_event_id(p_host_id     mss.host.id%TYPE,
                               p_switch_date DATE
    ) IS
        S_PREFIX CONSTANT VARCHAR2(32) := 'migrate_event_id(): ';
        v_event_id mc.connection_interrupt_closed.event_id%TYPE;

    BEGIN
        SELECT max(event_id) INTO v_event_id
        FROM mc.connection_interrupt_closed cic
        WHERE cic.host_id = p_host_id
          AND cic.up_date = p_switch_date;

        UPDATE mc.connection_interrupt_open cio
        SET cio.event_id = v_event_id
        WHERE cio.host_id = p_host_id
          AND cio.down_date = p_switch_date;

    EXCEPTION
        WHEN no_data_found THEN
            -- nothing to migrate, do not escalate
            NULL;
        WHEN others THEN
            plog.err(S_PREFIX||'caught exception:'||sqlerrm);
    END migrate_event_id;

-------------------------------------------------------------------------------
-- get_old_mode: returns old mode
--
-- parameter:  host_id
-- returns:    0 if active, 1 if SW, 2 if inactive
-------------------------------------------------------------------------------
    FUNCTION get_old_mode(p_host_id mss.host.id%TYPE) RETURN NUMBER IS
        S_PREFIX CONSTANT VARCHAR2(32) := 'get_old_mode(): ';
        v_interrupt_type mc.connection_interrupt_open.type_id%TYPE;
        v_active mc.connection_interrupt_open.active%TYPE;
        v_result NUMBER := 0;

    BEGIN
        SELECT type_id,active INTO v_interrupt_type,v_active
        FROM mc.connection_interrupt_open cio
        WHERE cio.host_id = p_host_id;

        IF ( v_active = 0 ) THEN
            v_result := mc.monitoring_state.MODE_INACTIVE;
        ELSE
            v_result := CASE v_interrupt_type
                            WHEN mc.monitoring_state.STATE_ISP
                                THEN mc.monitoring_state.MODE_ACTIVE
                --
                            WHEN mc.monitoring_state.STATE_DOWN
                                THEN mc.monitoring_state.MODE_ACTIVE
                --
                            WHEN mc.monitoring_state.STATE_ISP_SW
                                THEN mc.monitoring_state.MODE_SW
                --
                            WHEN mc.monitoring_state.STATE_DOWN_SW
                                THEN mc.monitoring_state.MODE_SW
                --
                END;
        END IF;
        RETURN v_result;
    EXCEPTION
        WHEN no_data_found THEN
            -- connection_interrupt_open is empty for this host:
            -- either the host is up or
            -- the host is new (assume old mode was inactive)
            RETURN mc.monitoring_state.MODE_INACTIVE;
    END get_old_mode;

-------------------------------------------------------------------------------
-- get_sang_status_from_state: returns SANG_ value for given STATE_ parameter
--
-- parameter: p_state, a STATE_ value
--
-- returns: one of SANG_UP,SANG_DOWN,SANG_ISP
-------------------------------------------------------------------------------
    FUNCTION get_sang_status_from_state(
        p_state     NUMBER
    ) RETURN NUMBER IS

        S_PREFIX CONSTANT VARCHAR2(32) := 'get_sang_status_from_state(): ';
        S_ERROR  NUMBER := -1;
        v_result NUMBER;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- map state values to sang status
        v_result := CASE p_state
                        WHEN mc.monitoring_state.STATE_ISP
                            THEN mc.monitoring_state.SANG_ISP
            --
                        WHEN mc.monitoring_state.STATE_DOWN
                            THEN mc.monitoring_state.SANG_DOWN
            --
                        WHEN mc.monitoring_state.STATE_ISP_SW
                            THEN mc.monitoring_state.SANG_ISP
            --
                        WHEN mc.monitoring_state.STATE_DOWN_SW
                            THEN mc.monitoring_state.SANG_DOWN
            -- ERROR
                        ELSE S_ERROR
            END;
        IF ( v_result = S_ERROR ) THEN
            plog.err(S_PREFIX||'unknown state '||p_state);
        END IF;

        RETURN v_result;
    END get_sang_status_from_state;

-------------------------------------------------------------------------------
-- get_mode_from_state: returns MODE_ value for given STATE_ parameter
--
-- parameter: p_state, a STATE_ value
--
-- returns: one of MODE_ACTIVE,MODE_INACTIVE or MODE_SW
-------------------------------------------------------------------------------
    FUNCTION get_mode_from_state(
        p_state     NUMBER
    ) RETURN NUMBER IS

        S_PREFIX CONSTANT VARCHAR2(32) := 'get_mode_from_state(): ';
        S_ERROR  NUMBER := -1;
        v_result NUMBER;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- map state values to mode
        v_result := CASE p_state
                        WHEN mc.monitoring_state.STATE_ISP
                            THEN mc.monitoring_state.MODE_ACTIVE
            --
                        WHEN mc.monitoring_state.STATE_DOWN
                            THEN mc.monitoring_state.MODE_ACTIVE
            --
                        WHEN mc.monitoring_state.STATE_ISP_SW
                            THEN mc.monitoring_state.MODE_SW
            --
                        WHEN mc.monitoring_state.STATE_DOWN_SW
                            THEN mc.monitoring_state.MODE_SW
            -- ERROR
                        ELSE S_ERROR
            END;
        IF ( v_result = S_ERROR ) THEN
            plog.err(S_PREFIX||'unknown state '||p_state);
        END IF;

        RETURN v_result;

    END get_mode_from_state;

-------------------------------------------------------------------------------
-- get_state: returns STATE_ value for given SANG_ and MODE_ values
--
-- parameter: p_mode, a MODE_ value
--            p_sang, a SANG_ value
--
-- returns: STATE_ value
--          ( there are only states for ACTIVE and SW modes )
-------------------------------------------------------------------------------
    FUNCTION get_state(
        p_mode     NUMBER,
        p_sang     NUMBER
    ) RETURN NUMBER IS

        S_PREFIX CONSTANT VARCHAR2(32) := 'get_state(): ';
        v_result NUMBER;

    BEGIN
        IF ( p_mode = mc.monitoring_state.MODE_ACTIVE ) THEN
            RETURN p_sang;
        ELSE
            IF ( p_sang = 1 ) THEN
                RETURN mc.monitoring_state.STATE_ISP_SW;
            ELSE
                RETURN mc.monitoring_state.STATE_DOWN_SW;
            END IF;
        END IF;

    END get_state;

-------------------------------------------------------------------------------
-- get_mode: get the current monitoring mode for a host
--
-- parameter: host_id
--            active flag
--
-- returns: MODE_ACTIVE,MODE_INACTIVE or MODE_SW
-------------------------------------------------------------------------------
    FUNCTION get_mode(
        p_host_id     mss.host.id%TYPE,
        p_active      mss.host.active%TYPE
    ) RETURN NUMBER IS

    BEGIN
        IF ( p_active != 0 ) THEN
            -- case ACTIVE
            IF ( has_active_SW(p_host_id) ) THEN
                -- mode: SW
                RETURN mc.monitoring_state.MODE_SW;
            ELSE
                RETURN mc.monitoring_state.MODE_ACTIVE;
            END IF;
        ELSE
            -- case INACTIVE
            RETURN mc.monitoring_state.MODE_INACTIVE;
        END IF;
    END get_mode;

-------------------------------------------------------------------------------
-- start_interrupt: insert a new entry in table connection_interrupt_open
--
-- parameter:  p_host_id
--             p_sang_state [0,1,2]
--             p_details
--             p_down_date
-------------------------------------------------------------------------------
    PROCEDURE start_interrupt(
        p_host_id             mss.host.id%TYPE,
        p_sang_state          NUMBER,
        p_mode                NUMBER,
        p_details             mc.connection_interrupt_open.details%TYPE,
        p_down_date           mc.connection_interrupt_open.down_date%TYPE
    ) IS

        S_PREFIX CONSTANT VARCHAR2(32) := 'start_interrupt(): ';
        v_count NUMBER;
        v_interrupt_type mc.connection_interrupt_open.type_id%TYPE := p_sang_state;
        v_active         mc.connection_interrupt_open.active%TYPE  := 1;

    BEGIN
        IF ( p_sang_state = mc.monitoring_state.SANG_UP ) THEN
            -- do not open an interrupt if SANG reports the connection to be UP
            RETURN;
        END IF;

        SELECT count(1) INTO v_count
        FROM mc.connection_interrupt_closed
        WHERE host_id = p_host_id;

        IF ( v_count < 1 ) THEN
            RETURN; -- this service has not yet been activated, skip it
        END IF;

        -- determine interrupt type
        v_interrupt_type := get_state( p_mode, p_sang_state );
        IF ( p_mode = mc.monitoring_state.MODE_INACTIVE ) THEN
            v_active := 0;
        ELSE
            v_active := 1;
        END IF;

        -- ADD entry
        INSERT INTO connection_interrupt_open (id, down_date,
                                               type_id, details, host_id, event_id, active)
        VALUES (connection_interrupt_sequence.nextval,
                p_down_date, v_interrupt_type, p_details, p_host_id, NULL, v_active);

    END start_interrupt;

-------------------------------------------------------------------------------
-- end_interrupt: read data from connection_interrupt_open,
-- insert a new entry in table connection_interrupt_closed,
-- delete the read entry from table connection_interrupt_open.
--
-- parameter:  p_host_id
--             p_up_date
-- returns:    event_id of generated event (if any) or NULL
-------------------------------------------------------------------------------
    FUNCTION end_interrupt(
        p_host_id    mss.host.id%TYPE,
        p_up_date    mc.connection_interrupt_closed.up_date%TYPE
    ) RETURN NUMBER IS

        S_PREFIX CONSTANT VARCHAR2(32) := 'end_interrupt(): ';
        row_interrupt  mc.connection_interrupt_open%ROWTYPE;
        v_id           mc.connection_interrupt_closed.id%TYPE;

        v_result       mc.connection_interrupt_open.event_id%TYPE := NULL;
        v_status       mc.host_connection_status.con_int_type_id%TYPE;
        v_active       mss.host.active%TYPE;

    BEGIN
        SELECT * INTO row_interrupt
        FROM connection_interrupt_open
        WHERE host_id = p_host_id
            FOR UPDATE;

        -- insert the record into the connection_interrupt_closed table
        INSERT INTO connection_interrupt_closed (id, down_date, up_date,
                                                 type_id, minutes, details, event_id, host_id, active,
                                                 interrupt_review_status_id)
        VALUES (row_interrupt.id, row_interrupt.down_date, p_up_date, row_interrupt.type_id,
                round((p_up_date - row_interrupt.down_date) * 24*60), row_interrupt.details,
                row_interrupt.event_id, p_host_id, row_interrupt.active, row_interrupt.interrupt_review_status_id);

        v_result := row_interrupt.event_id;

        -- delete the record from the connection_interrupt_open table
        DELETE FROM connection_interrupt_open
        WHERE id = row_interrupt.id;
        RETURN v_result;

    EXCEPTION
        WHEN no_data_found THEN
            -- potentially a service that started for the first time
            BEGIN
                SELECT id into v_id
                FROM connection_interrupt_closed
                WHERE host_id = p_host_id;
            EXCEPTION
                WHEN no_data_found THEN
                    -- startup of new service, if service is UP
                    SELECT hcs.con_int_type_id, mh.active INTO v_status,v_active
                    FROM mc.host_connection_status hcs
                             JOIN mss.host mh ON ( mh.id = hcs.host_id )
                    WHERE host_id = p_host_id;

                    IF ( nvl(v_status,0) = 0 AND v_active > 0) THEN
                        INSERT INTO connection_interrupt_closed (id, up_date, details, host_id, active)
                        VALUES (connection_interrupt_sequence.nextval, p_up_date, 'service activation', p_host_id, v_active);
                    END IF;
                    RETURN v_result;

                WHEN too_many_rows THEN
                    RETURN v_result;
            END;
            -- not a new service and no open interrupt open
            RETURN v_result;

        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception:'||sqlerrm);
            RETURN v_result;
    END end_interrupt;

-------------------------------------------------------------------------------
-- check_mode_changed: Check if the monitoring mode (active/SW/inactive) has
-- changed and trigger necessary actions
--
-- parameter: p_host_id
--            p_sang_status, the last sang status which has been stored in db
--            p_mode, the mode (MODE_ACTIVE,MODE_INACTIVE,MODE_SW)
-------------------------------------------------------------------------------

    PROCEDURE check_mode_changed(
        p_host_id     mss.host.id%TYPE,
        p_sang_status NUMBER,
        p_mode        NUMBER
    ) IS

        S_PREFIX CONSTANT VARCHAR2(32) := 'check_mode_changed(): ';
        row_old           connection_interrupt_open%ROWTYPE;
        v_now_date        DATE;
        v_event_id        NUMBER;
        v_old_mode        NUMBER;
        v_details         mc.host_connection_status.details%TYPE;
        v_last_event_id   NUMBER := NULL;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        v_old_mode := get_old_mode(p_host_id);
        -- change state if mode changed
        -- trigger events if necessary
        IF ( p_mode != v_old_mode) THEN

            BEGIN
                SELECT * INTO row_old
                FROM connection_interrupt_open
                WHERE host_id = p_host_id;
            EXCEPTION
                WHEN no_data_found THEN
                    -- end_interrupt will create 'first time up entry in connection_interrupt_closed' if appropriate:
                    v_now_date := SYSDATE;
                    v_last_event_id := end_interrupt(p_host_id,v_now_date);
                    -- skip this host: there is no mode to change
                    RETURN;
            END;

            -- switch mode ( = close old interrupt, open new one )
            v_now_date := SYSDATE;
            -- end_interrupt also handles hosts that report for the first time a connection status
            v_last_event_id := end_interrupt(p_host_id,v_now_date);

            -- special case for inact -> act and SW -> act
            IF ( p_mode = mc.monitoring_state.MODE_ACTIVE AND v_old_mode != mc.monitoring_state.MODE_ACTIVE ) THEN
                -- host has become active, check for event to generate
                SELECT details INTO v_details
                FROM mc.host_connection_status hcs
                WHERE hcs.host_id = p_host_id;

                start_interrupt(p_host_id,p_sang_status,p_mode,v_details,v_now_date);
            ELSE
                start_interrupt(p_host_id,p_sang_status,p_mode,row_old.details,v_now_date);
            END IF; -- end if special case inact->act, SW->act
            migrate_event_id(p_host_id,v_now_date);
            monitoring_ticket_processes.new_event(p_host_id,p_sang_status,p_mode,v_last_event_id);
        END IF; -- mode changed

    EXCEPTION
        WHEN no_data_found THEN
            -- no old mode to compare too
            IF ( p_mode = mc.monitoring_state.MODE_ACTIVE ) THEN
                -- in this case, "end_interrupt" failed to insert first entry
                plog.info(S_PREFIX||'could not find old connection_interrupt_open entry for '||p_host_id||'. This should only happen after SANG has been started. ' ||sqlerrm);
            END IF;
        -- else: nothing to do
        WHEN others THEN
            plog.err(S_PREFIX||'caught exception:'||sqlerrm);
    END check_mode_changed;

-------------------------------------------------------------------------------
-- check_all_status_changed: We have old "all" sang status and new "all" sang status,
-- trigger any required action
-- (e.g. insert entry in conn_interrupt_open because host became down)
--
-- parameter:  p_host_id
--             p_details
--             p_mode
--             p_old_status (valid sang status: the all status from mon_server_connection table)
--             p_new_status (valid sang status: the newly computed consolidated all status)
-------------------------------------------------------------------------------
    PROCEDURE check_all_status_changed(
        p_host_id       mss.host.id%TYPE,
        p_details       mc.connection_interrupt_open.details%TYPE,
        p_mode          NUMBER,
        p_old_status    NUMBER DEFAULT 0,
        p_new_status    NUMBER
    ) IS

        S_PREFIX        CONSTANT VARCHAR2(32) := 'check_all_status_changed(): ';
        v_now_date      DATE;
        r_interrupt     connection_interrupt_open%ROWTYPE;
        v_last_event_id NUMBER := NULL;

    BEGIN
        IF ( p_old_status = mc.monitoring_state.SANG_UP ) THEN
            IF ( p_new_status = mc.monitoring_state.SANG_DOWN OR p_new_status = mc.monitoring_state.SANG_ISP ) THEN
                -- UP => DOWN/ISP
                start_interrupt(p_host_id,p_new_status,p_mode,p_details,SYSDATE);
            END IF;
        ELSIF ( p_old_status = mc.monitoring_state.SANG_DOWN ) THEN
            IF ( p_new_status = mc.monitoring_state.SANG_UP ) THEN
                -- DOWN => UP
                v_last_event_id := end_interrupt(p_host_id,SYSDATE);
                monitoring_ticket_processes.new_event(p_host_id,p_new_status,p_mode,v_last_event_id);
            ELSIF ( p_new_status = mc.monitoring_state.SANG_ISP ) THEN
                -- DOWN => ISP
                v_now_date      := SYSDATE;
                v_last_event_id := end_interrupt(p_host_id,v_now_date);
                start_interrupt(p_host_id,p_new_status,p_mode,p_details,v_now_date);
                migrate_event_id(p_host_id,v_now_date);
            END IF;
        ELSIF ( p_old_status = mc.monitoring_state.SANG_ISP ) THEN
            IF ( p_new_status = mc.monitoring_state.SANG_UP ) THEN
                -- ISP => UP
                v_last_event_id := end_interrupt(p_host_id,SYSDATE);
                monitoring_ticket_processes.new_event(p_host_id,p_new_status,p_mode,v_last_event_id);
            ELSIF ( p_new_status = mc.monitoring_state.SANG_DOWN ) THEN
                -- ISP => DOWN
                v_now_date      := SYSDATE;
                v_last_event_id := end_interrupt(p_host_id,v_now_date);
                start_interrupt(p_host_id,p_new_status,p_mode,p_details,v_now_date);
                migrate_event_id(p_host_id,v_now_date);
            END IF;
        ELSE
            plog.debug(S_PREFIX||'unknown old sang status in parameter ('||p_old_status||')!');
        END IF;

    EXCEPTION
        WHEN others THEN
            plog.warning(S_PREFIX||'caught exception:'||sqlerrm);
    END check_all_status_changed;

-------------------------------------------------------------------------------
-- collate_conn_status: calculates the collated connection status of a given
-- service from the connection states written to mon_server_connection by
-- the different monitoring servers. The collated state is written into the
-- table host_connection_status.
--
-- parameters:
--   p_host_id: ID of host for which state is collated
-------------------------------------------------------------------------------
    PROCEDURE collate_conn_status(p_host_id mc.mon_server_connection.host_id%TYPE) IS

        S_PREFIX CONSTANT VARCHAR2(32) := 'collate_conn_status(): ';


        resource_busy EXCEPTION;
        S_ERRNO_RESOURCE_BUSY CONSTANT NUMBER := -30006;
        PRAGMA EXCEPTION_INIT (resource_busy, -30006);

        r_hcs_prev host_connection_status%ROWTYPE;

        v_old_con_int_type_id mc.host_connection_status.con_int_type_id%TYPE;
        v_old_details         mc.host_connection_status.details%TYPE;
        v_old_con_timestamp   mc.host_connection_status.con_timestamp%TYPE;

        v_new_con_int_type_id mc.host_connection_status.con_int_type_id%TYPE;
        v_new_details         mc.host_connection_status.details%TYPE;
        v_new_con_timestamp   mc.host_connection_status.con_timestamp%TYPE;

        v_new_mode        NUMBER;
        v_active          mss.host.active%TYPE;

        CURSOR host_connection_status_cur IS
            SELECT con_timestamp,con_int_type_id,details
            FROM mc.host_connection_status
            WHERE host_id = p_host_id
                FOR UPDATE WAIT 3;

        CURSOR mon_server_connection_cur IS
            SELECT status,details,con_timestamp
            FROM mon_server_connection
            WHERE host_id = p_host_id
              AND COALESCE(status, mc.monitoring_state.SANG_UP) < mc.monitoring_state.SANG_ERROR
            ORDER BY CASE COALESCE(status, mc.monitoring_state.SANG_UP)
                         WHEN mc.monitoring_state.SANG_UP THEN 0
                         WHEN mc.monitoring_state.SANG_DOWN THEN 1
                         WHEN mc.monitoring_state.SANG_ISP THEN 2
                         END;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- 1. open/fetch host_connection_status_cur
        OPEN host_connection_status_cur;
        FETCH host_connection_status_cur INTO v_old_con_timestamp,v_old_con_int_type_id,v_old_details;

        -- 2. calculate new collated status with mon_server_connection_cur
        OPEN mon_server_connection_cur;
        FETCH mon_server_connection_cur INTO v_new_con_int_type_id,v_new_details,v_new_con_timestamp;
        IF ( mon_server_connection_cur%NOTFOUND ) THEN
            -- if there is an old host_connection_status entry: remove it
            IF ( host_connection_status_cur%FOUND ) THEN
                DELETE FROM mc.host_connection_status
                WHERE host_id=p_host_id;
                RETURN;
            END IF;
            -- unix epoch
            v_new_con_timestamp :=  (cast(systimestamp at time zone 'UTC' as date) - to_date('1970-01-01', 'YYYY-MM-DD') ) * 86400;
        END IF;
        CLOSE mon_server_connection_cur;

        -- 3. if host_connection_status_cur returned no rows -> INSERT
        IF ( host_connection_status_cur%NOTFOUND ) THEN
            v_old_con_int_type_id := mc.monitoring_state.STATE_DOWN; -- assume state DOWN

            BEGIN
                INSERT INTO mc.host_connection_status
                (host_id,con_timestamp,details,con_int_type_id)
                VALUES
                    (p_host_id,v_new_con_timestamp,v_new_details,v_new_con_int_type_id);
            EXCEPTION
                WHEN DUP_VAL_ON_INDEX THEN
                    RETURN; -- ignore, another SANG server was faster.
            END;
        END IF;

        -- 4. UPDATE ... WHERE CURRENT OF host_connection_status_cur
        --    (ONLY IF something has changed)
        SELECT active INTO v_active
        FROM mss.host
        WHERE id = p_host_id;
        v_new_mode := get_mode(p_host_id,v_active);
        -- con_int_type_id of connection_interrupt_open must be up to date before check_all_status is called
        check_mode_changed(p_host_id,nvl(v_old_con_int_type_id,0),v_new_mode);
        IF ( nvl(v_old_con_int_type_id,0) != nvl(v_new_con_int_type_id,0) ) THEN
            -- status has changed -> update host_connection_status
            IF (host_connection_status_cur%FOUND) THEN
                UPDATE host_connection_status
                SET con_int_type_id = v_new_con_int_type_id,
                    con_timestamp   = v_new_con_timestamp,
                    details         = v_new_details
                WHERE CURRENT OF host_connection_status_cur;
            END IF;
            check_all_status_changed(p_host_id,v_new_details,v_new_mode,nvl(v_old_con_int_type_id,0),nvl(v_new_con_int_type_id,0));
        END IF;

        CLOSE host_connection_status_cur;

    EXCEPTION
        WHEN resource_busy THEN
           -- could not lock record for update
           NULL;

        -- default exception handler
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);

    END collate_conn_status;

-------------------------------------------------------------------------------
-- package INITIALIZATION
-------------------------------------------------------------------------------
BEGIN
    SELECT CASE WHEN UTL_INADDR.get_host_name like 'ora%dev%'
                    THEN '100'
                ELSE '30' END
    INTO MON_DOWN_LEVEL FROM dual;

END monitoring;
/
