--liquibase formatted sql logicalFilePath:pkgb/mc_osag_maintsync.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE BODY MC.OSAG_MAINTSYNC IS


    --
    -- Updates the maintenance status of all hosts
    -- (called by a job)
    --
    PROCEDURE update_host_maint_status AS

        S_PREFIX CONSTANT VARCHAR2(64) := 'update_host_maint_status(): ';

        -- select all hosts with their maintenance status (newly calculated and current one)
        -- that have a change between calculated and current
        -- or none assigned yet
        CURSOR c_maint_status_changed IS
            -- maintenance status calculation
            SELECT h.id as host_id,
                   CASE WHEN h.active = 0 THEN 3
                        WHEN sw.ticket_id IS NULL THEN 2
                        ELSE 4
                       END as maintenance_status_new,
                   h.maintenance_status_id as maintenance_status_old,
                   sw.ticket_id as ticket_id
            FROM mss.host h,
                 -- subquery to include currently open service windows (latest ticket is taken)
                 (SELECT max(t.id) AS ticket_id, h2s.host_id

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
                          t.status_id < 101 AND s.end_date > SYSTIMESTAMP AND s.start_date < SYSTIMESTAMP
                    AND (m.disable_conn_escalation = 1 OR m.disable_events = 1 OR cm.disable_conn_escalation = 1 OR cm.disable_events = 1)
                  GROUP BY h2s.host_id) sw

            WHERE h.id = sw.host_id(+) and h.operating_system_id != 21 AND
                (h.maintenance_status_id IS NULL OR
                 (h.active = 0 AND h.maintenance_status_id != 3) OR
                 (sw.ticket_id IS NULL AND h.active = 1 AND h.maintenance_status_id != 2) OR
                 (sw.ticket_id IS NOT NULL AND h.active = 1 AND h.maintenance_status_id != 4))
                FOR UPDATE OF h.maintenance_status_id;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- let's go over the cursor
        FOR r_maint_status_changed IN c_maint_status_changed
            LOOP

                INSERT INTO mc.host_maintenance_history (id, host_id, change_date, new_maintenance_status_id, old_maintenance_status_id, ticket_id)
                VALUES (mc.host_maint_history_seq.nextval, r_maint_status_changed.host_id, SYSTIMESTAMP, r_maint_status_changed.maintenance_status_new,
                        NVL(r_maint_status_changed.maintenance_status_old, 1), r_maint_status_changed.ticket_id);

                UPDATE mss.host h SET h.maintenance_status_id = r_maint_status_changed.maintenance_status_new WHERE h.id = r_maint_status_changed.host_id;

            END LOOP;

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);

    END update_host_maint_status;

    --
    -- Updates the maintenance status of all isp links
    -- currently in use (i.e. attached to an interface)
    -- (called by a job)
    --
    PROCEDURE update_isp_link_maint_status AS

        S_PREFIX CONSTANT VARCHAR2(64) := 'update_isp_link_maint_status(): ';

        -- select all isp links that are associated with an interface with their maintenance status (newly calculated and current one)
        -- that have a change between calculated and current or none assigned yet
        CURSOR c_maint_status_changed IS
            -- maintenance status calculation
            SELECT l.id AS isp_link_id,
                   CASE WHEN hosts.host_active = 0 THEN 3
                        WHEN sw.ticket_id IS NULL THEN 2
                        ELSE 4
                       END as maintenance_status_new,
                   l.maintenance_status_id as maintenance_status_old,
                   sw.ticket_id as ticket_id
            FROM  mss.isp_link l,
                  -- get the service window of the latest ticket over all linked host
                  (SELECT max(t.id) as ticket_id, i2l.isp_link_id

                   FROM tt.ticket t
                            INNER JOIN tt.service_window s
                                       ON (s.ticket_id = t.id)
                            INNER JOIN tt.host2service_window h2s
                                       ON (h2s.service_window_id = s.id)
                            INNER JOIN mss.interface i
                                       ON (h2s.host_id = i.host_id)
                            INNER JOIN mss.interface2isp_link i2l
                                       ON (i.id = i2l.interface_id)

                            LEFT JOIN tt.maintenance_window m
                                      ON (s.id = m.service_window_id)
                            LEFT JOIN tt.cust_maintenance_window cm
                                      ON (s.id = cm.service_window_id)

                   WHERE
                           t.status_id < 101 AND s.end_date > SYSTIMESTAMP AND s.start_date < SYSTIMESTAMP
                     AND (m.disable_conn_escalation = 1 OR m.disable_events = 1 OR cm.disable_conn_escalation = 1 OR cm.disable_events = 1)
                   GROUP BY i2l.isp_link_id) sw,
                  -- get a linked host that is active, if possible
                  (SELECT MAX(h.active) as host_active, i2l_a.isp_link_id as isp_link_id FROM mss.host h, mss.interface i_a, mss.interface2isp_link i2l_a
                   WHERE h.id = i_a.host_id and i2l_a.interface_id = i_a.id group by i2l_a.isp_link_id) hosts
            WHERE l.id = hosts.isp_link_id AND l.id = sw.isp_link_id(+) AND
              -- status is unknown or null
                (l.maintenance_status_id IS NULL or l.maintenance_status_id = 1 OR
                    -- now inactive, but not before
                 (hosts.host_active = 0 AND l.maintenance_status_id != 3) OR
                    -- no service window now, active, but not active before
                 (sw.ticket_id IS NULL AND hosts.host_active = 1 AND l.maintenance_status_id != 2) OR
                    -- a service window now, active, but not maintenance before
                 (sw.ticket_id IS NOT NULL AND hosts.host_active = 1 AND l.maintenance_status_id != 4))
                FOR UPDATE OF l.maintenance_status_id;

        -- select all links that are no longer associated with an interface, but still have their maintenance status
        -- set to something different than unknown (1)
        CURSOR c_maint_status_obsolete IS

            SELECT l.id AS isp_link_id,
                   l.maintenance_status_id as maintenance_status_old
            FROM mss.isp_link l
            WHERE (l.maintenance_status_id != 1 OR l.maintenance_status_id IS NULL) AND NOT EXISTS (SELECT 1 FROM mss.interface2isp_link i2l WHERE i2l.isp_link_id = l.id)
                FOR UPDATE OF l.maintenance_status_id;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- let's go over the cursor for the currently assignged isp links
        FOR r_maint_status_changed IN c_maint_status_changed
            LOOP

                plog.notice('updating status for link ' || r_maint_status_changed.isp_link_id
                    || ': new status is ' || r_maint_status_changed.maintenance_status_new
                    || ': old status is ' || r_maint_status_changed.maintenance_status_old);

                INSERT INTO mc.isp_link_maintenance_history (id, isp_link_id, change_date, new_maintenance_status_id, old_maintenance_status_id, ticket_id)
                VALUES (mc.isp_link_maint_history_seq.nextval, r_maint_status_changed.isp_link_id, SYSTIMESTAMP, r_maint_status_changed.maintenance_status_new,
                        NVL(r_maint_status_changed.maintenance_status_old, 1), r_maint_status_changed.ticket_id);

                UPDATE mss.isp_link l SET l.maintenance_status_id = r_maint_status_changed.maintenance_status_new WHERE l.id = r_maint_status_changed.isp_link_id;

            END LOOP;

        -- set previously assigned isp links maintenance status back to unknown
        FOR r_maint_status_obsolete IN c_maint_status_obsolete
            LOOP

                INSERT INTO mc.isp_link_maintenance_history (id, isp_link_id, change_date, new_maintenance_status_id, old_maintenance_status_id)
                VALUES (mc.isp_link_maint_history_seq.nextval, r_maint_status_obsolete.isp_link_id, SYSTIMESTAMP, 1, NVL(r_maint_status_obsolete.maintenance_status_old,1));

                UPDATE mss.isp_link l SET l.maintenance_status_id = 1 WHERE l.id =r_maint_status_obsolete.isp_link_id;

            END LOOP;


    EXCEPTION
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);

    END update_isp_link_maint_status;

    --
    -- Update the maintenance status of a single host
    --
    PROCEDURE update_single_host(p_host_id MSS.HOST.ID%TYPE) AS

        S_PREFIX CONSTANT VARCHAR2(32) := 'update_single_host(): ';

        v_current_status MC.MAINTENANCE_STATUS.ID%TYPE;
        v_old_status MC.MAINTENANCE_STATUS.ID%TYPE;
        v_maint_ticket TT.TICKET.ID%TYPE;
    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- maintenance status calculation
        SELECT CASE WHEN h.active = 0 THEN 3
                    WHEN sw.ticket_id IS NULL THEN 2
                    ELSE 4
                   END as maintenance_status_new,
               h.maintenance_status_id as maintenance_status_old,
               sw.ticket_id
        INTO v_current_status, v_old_status, v_maint_ticket
        FROM mss.host h,
             -- subquery to include currently open service windows (latest ticket is taken)
             (SELECT max(t.id) AS ticket_id, h2s.host_id

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
                      t.status_id < 101 AND s.end_date > SYSTIMESTAMP AND s.start_date < SYSTIMESTAMP
                AND (m.disable_conn_escalation = 1 OR m.disable_events = 1 OR cm.disable_conn_escalation = 1 OR cm.disable_events = 1)
              GROUP BY h2s.host_id) sw

        WHERE h.id = p_host_id AND h.id = sw.host_id(+) and h.operating_system_id != 21 AND
            (h.maintenance_status_id IS NULL OR
             (h.active = 0 AND h.maintenance_status_id != 3) OR
             (sw.ticket_id IS NULL AND h.active = 1 AND h.maintenance_status_id != 2) OR
             (sw.ticket_id IS NOT NULL AND h.active = 1 AND h.maintenance_status_id != 4));

        IF (v_current_status != v_old_status OR v_old_status IS NULL) THEN

            INSERT INTO mc.host_maintenance_history (id, host_id, change_date, new_maintenance_status_id, old_maintenance_status_id, ticket_id)
            VALUES (mc.host_maint_history_seq.nextval, p_host_id, SYSTIMESTAMP, v_current_status,
                    NVL(v_old_status, 1), v_maint_ticket);

            UPDATE mss.host h SET h.maintenance_status_id = v_current_status WHERE h.id = p_host_id;

        END IF;


    EXCEPTION
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);

    END update_single_host;

    --
    -- Update the maintenance of a single isp link
    --
    PROCEDURE update_single_isp_link(p_isp_link_id MSS.ISP_LINK.ID%TYPE) AS

        S_PREFIX CONSTANT VARCHAR2(32) := 'update_single_isp_link(): ';

        v_current_status MC.MAINTENANCE_STATUS.ID%TYPE;
        v_old_status MC.MAINTENANCE_STATUS.ID%TYPE;
        v_maint_ticket TT.TICKET.ID%TYPE;
    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        SELECT l.maintenance_status_id INTO v_old_status FROM mss.isp_link l WHERE l.id = p_isp_link_id;

        BEGIN
            SELECT CASE WHEN hosts.host_active = 0 THEN 3
                        WHEN sw.ticket_id IS NULL THEN 2
                        ELSE 4
                       END as maintenance_status_new,
                   sw.ticket_id
            INTO v_current_status, v_maint_ticket
            FROM  mss.isp_link l,
                  -- get the service window of the latest ticket over all linked host
                  (SELECT max(t.id) as ticket_id, i2l.isp_link_id

                   FROM tt.ticket t
                            INNER JOIN tt.service_window s
                                       ON (s.ticket_id = t.id)
                            INNER JOIN tt.host2service_window h2s
                                       ON (h2s.service_window_id = s.id)
                            INNER JOIN mss.interface i
                                       ON (h2s.host_id = i.host_id)
                            INNER JOIN mss.interface2isp_link i2l
                                       ON (i.id = i2l.interface_id)

                            LEFT JOIN tt.maintenance_window m
                                      ON (s.id = m.service_window_id)
                            LEFT JOIN tt.cust_maintenance_window cm
                                      ON (s.id = cm.service_window_id)

                   WHERE
                           t.status_id < 101 AND s.end_date > SYSTIMESTAMP AND s.start_date < SYSTIMESTAMP
                     AND (m.disable_conn_escalation = 1 OR m.disable_events = 1 OR cm.disable_conn_escalation = 1 OR cm.disable_events = 1)
                   GROUP BY i2l.isp_link_id) sw,
                  -- get a linked host that is active, if possible
                  (SELECT MAX(h.active) as host_active, i2l_a.isp_link_id as isp_link_id FROM mss.host h, mss.interface i_a, mss.interface2isp_link i2l_a
                   WHERE h.id = i_a.host_id and i2l_a.interface_id = i_a.id group by i2l_a.isp_link_id) hosts
            WHERE l.id = hosts.isp_link_id AND l.id = sw.isp_link_id(+) AND
              -- status is unknown or null
                (l.maintenance_status_id = NULL or l.maintenance_status_id = 1 OR
                    -- now inactive, but not before
                 (hosts.host_active = 0 AND l.maintenance_status_id != 3) OR
                    -- no service window now, active, but not active before
                 (sw.ticket_id IS NULL AND hosts.host_active = 1 AND l.maintenance_status_id != 2) OR
                    -- a service window now, active, but not maintenance before
                 (sw.ticket_id IS NOT NULL AND hosts.host_active = 1 AND l.maintenance_status_id != 4));

        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                -- if we have no data here, the isp link is not attached to an interface, so
                -- the current status should be unknown (1), no maintenance ticket
                v_current_status := 1;
                v_maint_ticket := NULL;
        END;

        IF (v_old_status != v_current_status OR v_old_status IS NULL) THEN
            INSERT INTO mc.isp_link_maintenance_history (id, isp_link_id, change_date, new_maintenance_status_id, old_maintenance_status_id, ticket_id)
            VALUES (mc.isp_link_maint_history_seq.nextval, p_isp_link_id, SYSTIMESTAMP, v_current_status, NVL(v_old_status, 1), v_maint_ticket);

            UPDATE mss.isp_link l SET l.maintenance_status_id = v_current_status WHERE l.id = p_isp_link_id;
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(S_PREFIX||'caught exception: '||sqlerrm);

    END update_single_isp_link;


END OSAG_MAINTSYNC;
/
