--liquibase formatted sql logicalFilePath:pkgb/vpn_osag_vpn.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE BODY VPN.OSAG_VPN IS
-- ----------------------------------------------------------------------------------------
-- FUNCTION get_illegal_tunnel_info
-- ----------------------------------------------------------------------------------------
    FUNCTION  get_illegal_tunnel_info(
        i_host_id NUMBER        -- an id of an existing mss.host
    ) RETURN VARCHAR2
        IS
        c_prefix         CONSTANT VARCHAR2(32) := 'get_illegal_tunnel_info';
        l_info           VARCHAR2(255) := NULL;
    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- detect ambigious tunnel setups (host1 connected to the same interface of host2 twice, via different local interfaces)
        SELECT h1.name || ':' || i1.name || '/' || i3.name || ' -- ' || h2.name || ':' || i4.name INTO l_info
        FROM mss.host h1, mss.host h2, mss.interface i1, mss.interface i2, mss.interface i3, mss.interface i4,
             vpn.vpn_member m1, vpn.vpn_member m2, vpn.vpn_member m3, vpn.vpn_member m4,
             vpn.tunnel t1, vpn.tunnel t2
        WHERE h1.id = i1.host_id AND h1.id = i3.host_id
          AND h2.id = i2.host_id AND h2.id = i4.host_id
          AND m1.INTERFACE_ID = i1.id AND m2.INTERFACE_ID = i2.id AND m3.interface_id = i3.id AND m4.interface_id = i4.id
          AND t1.vpn_member_id1 = m1.id AND t1.vpn_member_id2 = m2.id
          AND t2.vpn_member_id1 = m3.id AND t2.vpn_member_id2 = m4.id
          AND i1.id != i3.id AND i2.id = i4.id
          AND t1.id < t2.id
          AND h1.id = i_host_id
          AND t1.tunnelmode != 0 AND t2.tunnelmode != 0;
        RETURN l_info;

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN NULL;
        WHEN OTHERS THEN
            plog.err(c_prefix||'unexpected error: '||sqlerrm);
            RETURN c_prefix||'internal error: '||sqlerrm;
    END get_illegal_tunnel_info;

-- ----------------------------------------------------------------------------------------
-- FUNCTION get_tunnelcost_by_id
-- ----------------------------------------------------------------------------------------

    FUNCTION get_tunnelcost_by_id(
        i_tunnel_id NUMBER  -- vpn.tunnel.id of the tunnel we want the ospf cost for
    ) RETURN NUMBER
        IS
        c_prefix         CONSTANT VARCHAR2(32) := 'get_tunnelcost_by_id: ';
        c_defaultcost    CONSTANT NUMBER := 100;  -- the default OSPF cost
        c_hubreduction   CONSTANT NUMBER := 1;    -- hubs have reduced cost
        l_cost           NUMBER := c_defaultcost;
        l_cost_tunnel    NUMBER := NULL;
        l_cost_member1   NUMBER := NULL;
        l_cost_member2   NUMBER := NULL;
        l_cost_partition NUMBER := NULL;
        l_hub1           NUMBER := 0;
        l_hub2           NUMBER := 0;
        l_vpnid          NUMBER := 0;
    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);

        -- get all existing cost definitions for this tunnel
        -- in case of an error all values are NULL (as set above)

        BEGIN
            -- Step 1 --
            -- Lookup hub flag and cost for given hosts for the tunnel
            -- between the two hosts and interfaces.
            SELECT vm1.hub, vm2.hub, t.ospf_cost, vm1.ospf_cost, vm2.ospf_cost, p.ospf_cost
            INTO l_hub1, l_hub2, l_cost_tunnel, l_cost_member1, l_cost_member2, l_cost_partition
            FROM vpn.vpn_member vm1, vpn.vpn_member vm2, vpn.partition p, vpn.tunnel t
            WHERE t.id = i_tunnel_id
              AND t.vpn_member_id1 = vm1.id
              AND t.vpn_member_id2 = vm2.id
              AND p.id = vm2.partition_id
              AND p.id = vm1.partition_id;
        END;

        -- Step 2 --
        -- The OSPF cost is equal to (first match wins):
        --
        --    1. the explicit cost of the tunnel [vpn.tunnel.ospf_cost]
        --    2. the average of the costs of the two endpoints, while endpoints are:
        --       2.1. explicit cost of the target vpn_member [vpn.vpn_member.ospf_cost]
        --       2.2. the suggested cost of the partition (-1 if hub!) [vpn.partition.ospf_cost]
        --       2.3. 100 (-1 if hub!)

        IF ( l_cost_tunnel IS NOT NULL ) THEN
            l_cost := l_cost_tunnel;
        ELSE
            IF ( l_cost_member1 IS NULL ) THEN
                IF ( l_cost_partition IS NULL ) THEN
                    l_cost_member1 := c_defaultcost;
                ELSE
                    l_cost_member1 := l_cost_partition;
                END IF;
                IF ( (l_hub1 = 1) AND (l_cost_member1 > (1+c_hubreduction)) ) THEN
                    l_cost_member1 := l_cost_member1 - c_hubreduction;
                END IF;
            END IF;
            IF ( l_cost_member2 IS NULL ) THEN
                IF ( l_cost_partition IS NULL ) THEN
                    l_cost_member2 := c_defaultcost;
                ELSE
                    l_cost_member2 := l_cost_partition;
                END IF;
                IF ( (l_hub2 = 1) AND (l_cost_member2 > (1+c_hubreduction)) ) THEN
                    l_cost_member2 := l_cost_member2 - c_hubreduction;
                END IF;
            END IF;
            l_cost := TRUNC ( ( l_cost_member1 + l_cost_member2 ) / 2);

        END IF;

        RETURN l_cost;

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(c_prefix||'unexpected error [pos99]: '||sqlerrm);
    END get_tunnelcost_by_id;

-- ----------------------------------------------------------------------------------------
-- FUNCTION get_tunnelcost_partition
-- ----------------------------------------------------------------------------------------

    FUNCTION get_tunnelcost_partition(
        i_partition_id NUMBER,  -- vpn.partition.id of the partition we are interested in
        i_hostid1 NUMBER,       -- the mss.host.id of the first host (source)
        i_hostid2 NUMBER        -- the mss.host.id of the second host (target, order is relevant!)
    ) RETURN NUMBER
        IS
        c_prefix         CONSTANT VARCHAR2(32) := 'get_tunnelcost_partition: ';
        c_defaultcost    CONSTANT NUMBER := 100;  -- the default OSPF cost
        c_hubreduction   CONSTANT NUMBER := 1;    -- hubs have reduced cost
        l_cost           NUMBER := c_defaultcost;
        l_cost_tunnel    NUMBER := NULL;
        l_cost_member1   NUMBER := NULL;
        l_cost_member2   NUMBER := NULL;
        l_cost_partition NUMBER := NULL;
        l_hub1           NUMBER := 0;
        l_hub2           NUMBER := 0;
        l_interface1     NUMBER := 0;
        l_interface2     NUMBER := 0;
        l_interface1_name VARCHAR2(32) := NULL;
        l_interface2_name VARCHAR2(32) := NULL;
        l_vpnid          NUMBER := 0;
        i_first_tunnel   NUMBER := 0;
        tmp_cost         NUMBER := 0;
    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- get all existing cost definitions for this tunnel
        -- in case of an error all values are NULL (as set above)
        BEGIN
            -- Step 1 --
            -- Lookup physical interfaces and vpn ID involved between the two
            -- hosts in the desired partition.
            -- There might be several tunnels in different partitions between
            -- these two interfaces. If they have different costs, we issue a
            -- warning.
            -- (rha, 09.03.2010)
            -- Due to Full Mesh ALF it is now possible to have several tunnels
            -- with different costs. In this case we use the lowest ospf cost.
            -- (jah, 19.11.2013)
            FOR v_tunnel_data IN (
                SELECT i1.id as id1, i1.name as name1, i2.id id2, i2.name as name2, p.vpn_id as vpn_id, t.ospf_cost as cost
                FROM vpn.vpn_member vm1, vpn.vpn_member vm2, mss.interface i1, mss.interface i2, vpn.tunnel t, vpn.partition p
                WHERE
                        p.id = i_partition_id
                  AND vm1.partition_id = i_partition_id
                  AND vm2.partition_id = i_partition_id
                  AND t.vpn_member_id1 = vm1.id
                  AND t.vpn_member_id2 = vm2.id
                  AND vm1.interface_id = i1.id
                  AND vm2.interface_id = i2.id
                  AND i1.host_id = i_hostid1
                  AND i2.host_id = i_hostid2
                )
                LOOP
                    IF ( ( i_first_tunnel = 0 ) OR  ( v_tunnel_data.cost IS NOT NULL AND v_tunnel_data.cost < tmp_cost ) ) THEN
                        l_interface1 := v_tunnel_data.id1;
                        l_interface1_name := v_tunnel_data.name1;
                        l_interface2 := v_tunnel_data.id2;
                        l_interface2_name := v_tunnel_data.name2;
                        l_vpnid := v_tunnel_data.vpn_id;
                        tmp_cost := v_tunnel_data.cost;
                        i_first_tunnel := 1;
                    END IF;
                END LOOP;
        END;

        BEGIN
            -- Step 2 --
            -- Lookup hub flag and cost for given hosts for the best tunnel
            -- between the two hosts and interfaces. If we find tunnels in more than
            -- one partition between those interfaces, we yield an error.
            -- (rha, 09.03.2010)

            SELECT vm1.hub, vm2.hub, t.ospf_cost, vm1.ospf_cost, vm2.ospf_cost, p.ospf_cost
            INTO l_hub1, l_hub2, l_cost_tunnel, l_cost_member1, l_cost_member2, l_cost_partition
            FROM vpn.vpn_member vm1, mss.interface i1, vpn.vpn_member vm2, mss.interface i2,
                 vpn.partition p, vpn.tunnel t
            WHERE vm1.partition_id = p.id AND vm2.partition_id = p.id
              AND t.vpn_member_id1 = vm1.id
              AND t.vpn_member_id2 = vm2.id
              AND vm2.interface_id = i2.id
              AND vm1.interface_id = i1.id
              AND i1.host_id = i_hostid1
              AND i2.host_id = i_hostid2
              AND i1.id = l_interface1
              AND i2.id = l_interface2
              AND p.vpn_id = l_vpnid;

        EXCEPTION
            WHEN TOO_MANY_ROWS THEN
                plog.err(c_prefix||'multiple vpn tunnels between hosts:interfaces '||i_hostid1||':'||l_interface1_name||' and '||i_hostid2||':'||l_interface2_name);
            WHEN NO_DATA_FOUND THEN
                NULL;
        END;

        -- Step 3 --
        -- The OSPF cost is equal to (first match wins):
        --
        --    1. the explicit cost of the tunnel [vpn.tunnel.ospf_cost]
        --    2. the average of the costs of the two endpoints, while endpoints are:
        --       2.1. explicit cost of the target vpn_member [vpn.vpn_member.ospf_cost]
        --       2.2. the suggested cost of the partition (-1 if hub!) [vpn.partition.ospf_cost]
        --       2.3. 100 (-1 if hub!)

        IF ( l_cost_tunnel IS NOT NULL ) THEN
            l_cost := l_cost_tunnel;
        ELSE
            IF ( l_cost_member1 IS NULL ) THEN
                IF ( l_cost_partition IS NULL ) THEN
                    l_cost_member1 := c_defaultcost;
                ELSE
                    l_cost_member1 := l_cost_partition;
                END IF;
                IF ( (l_hub1 = 1) AND (l_cost_member1 > (1+c_hubreduction)) ) THEN
                    l_cost_member1 := l_cost_member1 - c_hubreduction;
                END IF;
            END IF;
            IF ( l_cost_member2 IS NULL ) THEN
                IF ( l_cost_partition IS NULL ) THEN
                    l_cost_member2 := c_defaultcost;
                ELSE
                    l_cost_member2 := l_cost_partition;
                END IF;
                IF ( (l_hub2 = 1) AND (l_cost_member2 > (1+c_hubreduction)) ) THEN
                    l_cost_member2 := l_cost_member2 - c_hubreduction;
                END IF;
            END IF;
            l_cost := TRUNC ( ( l_cost_member1 + l_cost_member2 ) / 2);

        END IF;

        RETURN l_cost;

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(c_prefix||'unexpected error [pos99]: '||sqlerrm);
    END get_tunnelcost_partition;

-- ----------------------------------------------------------------------------------------
-- update_peer_status (TMON 2 with new GRE names)
-- ----------------------------------------------------------------------------------------
    PROCEDURE update_peer_status_sub(	-- *** PRIVATE SUBROUTIUNE ***
        i_host_id        NUMBER,
        i_logdate        DATE,
        i_status         NUMBER,
        i_csv            VARCHAR2
    ) IS
        c_prefix         CONSTANT VARCHAR2(64) := 'OSAG_VPN.update_peer_status_sub: ';
        l_csv            VARCHAR2(16384);
        l_comma_pos      NUMBER := NULL;
        l_tunnel_id      VARCHAR2(64);
    BEGIN

        l_csv := i_csv;
        WHILE ( LENGTH(l_csv)>0 ) LOOP

                -- extract tunnel_id
                BEGIN
                    -- make sure that the tunnel name starts either with t4_ or t6_
                    IF ( NOT ( l_csv LIKE 't4_%' OR l_csv LIKE 't6_%' ) )
                    THEN
                        RAISE e_abort;
                    END IF;

                    l_comma_pos      := INSTR(l_csv, ',', 1, 1);
                    IF ( l_comma_pos = 0 ) THEN
                        l_tunnel_id := l_csv;
                        l_tunnel_id := SUBSTR(l_csv,4);
                        l_csv := '';
                    ELSIF ( l_comma_pos < 5 ) THEN
                        RAISE e_abort;
                    ELSE
                        l_tunnel_id := SUBSTR(l_csv,4,l_comma_pos-4);
                        l_csv := substr(l_csv, l_comma_pos + 1);
                    END IF;
                EXCEPTION
                    WHEN OTHERS THEN
                        plog.err(c_prefix||'error parsing list of tunnel names: '||l_csv||', host_id='||i_host_id||', '||sqlerrm);
                        RAISE e_abort;
                END;

                -- update tunnel
                BEGIN
                    UPDATE vpn.tunnel set status=i_status, status_date=i_logdate
                    WHERE id = l_tunnel_id;
                EXCEPTION
                    WHEN OTHERS THEN
                        plog.err(c_prefix||'unable to update tunnel: host_id='||i_host_id||', tunnel_id='||l_tunnel_id||': '||sqlerrm);
                END;
            END LOOP;
    EXCEPTION
        WHEN e_abort THEN
            NULL;
        WHEN OTHERS THEN
            plog.err(c_prefix||'unexpected error: '||sqlerrm);
    END update_peer_status_sub;


    PROCEDURE update_peer_status(			-- *** THE REAL PROCEDURE***
        i_host_id           NUMBER,
        i_logdate           DATE,
        i_default_status    NUMBER,
        i_csv_unknown_peers VARCHAR2,
        i_csv_down_peers    VARCHAR2,
        i_csv_up_peers      VARCHAR2,
        i_csv_slow_peers    VARCHAR2
    ) IS
        c_prefix         CONSTANT VARCHAR2(32) := 'OSAG_VPN.update_peer_status: ';
    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- the DEFAULT status is only written to tunnels that already do have
        -- an entry. This way we don't set tunnels that have not been committed
        -- to the client yet! If the client program tmon detects that a previously
        -- UNKNOWN tunnel gets a new value it will explicitely list that tunnel
        -- in the TMON:UPDATE message by forcing the default value to be U

        BEGIN
            UPDATE vpn.tunnel SET status=i_default_status, status_date=i_logdate WHERE id IN (
                SELECT t.id FROM vpn.tunnel t, vpn.vpn_member vm1, mss.interface i1
                WHERE t.vpn_member_id1 = vm1.id
                  AND vm1.interface_id = i1.id
                  AND i1.host_id = i_host_id
                  AND t.status IS NOT NULL
            );
        EXCEPTION
            WHEN OTHERS THEN
                plog.err(c_prefix||'cannot set default status to '||i_default_status||' for all tunnels of host '||i_host_id||': '||sqlerrm);
                RAISE e_abort;
        END;

        -- then overwrite those tunnels with an explicit value given
        -- as Oracle has complicated string functions we use a private subroutine here...

        IF ( i_csv_unknown_peers IS NOT NULL ) THEN
            update_peer_status_sub(i_host_id,i_logdate,NULL,i_csv_unknown_peers);
        END IF;

        IF ( i_csv_down_peers IS NOT NULL ) THEN
            update_peer_status_sub(i_host_id,i_logdate,0,i_csv_down_peers);
        END IF;

        IF ( i_csv_up_peers IS NOT NULL ) THEN
            update_peer_status_sub(i_host_id,i_logdate,1,i_csv_up_peers);
        END IF;

        IF ( i_csv_slow_peers IS NOT NULL ) THEN
            update_peer_status_sub(i_host_id,i_logdate,2,i_csv_slow_peers);
        END IF;

    EXCEPTION
        WHEN e_abort THEN
            NULL;
        WHEN OTHERS THEN
            plog.err(c_prefix||'unexpected error: '||sqlerrm);
    END update_peer_status;

END OSAG_VPN;
/
