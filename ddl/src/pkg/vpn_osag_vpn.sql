--liquibase formatted sql logicalFilePath:pkg/vpn_osag_vpn.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE VPN.OSAG_VPN AS
    -------------------------------------------------------------------------------
    --
    -- create_package_OSAG_VPN.sql: various functions for the VPN user
    --
    -- Written by Goetz von Escher, Juli 2003
    -- Copyright (c) 2003 Open Systems AG, Switzerland
    -- All Rights Reserved.
    --
    -------------------------------------------------------------------------------

-- ----------------------------------------------------------------------------------------
-- some constants
-- ----------------------------------------------------------------------------------------

    e_abort        EXCEPTION;    -- abort this procedure
    e_silentexit   EXCEPTION;    -- exit procedure silently (without exception)

-- ----------------------------------------------------------------------------------------
-- get_illegal_tunnel_info
-- Purpose: Get a descriptive error message about the first ambigious tunnel of the given
--          mss.host
--          Returns NULL if the host does not exist or no ambigious tunnels are found
-- ----------------------------------------------------------------------------------------
    FUNCTION  get_illegal_tunnel_info(
        i_host_id NUMBER	-- an id of an existing mss.host
    ) RETURN VARCHAR2;

-- ----------------------------------------------------------------------------------------
-- get_tunnelcost_by_id
-- Purpose: calculate the OSPF cost of a tunnel given by its id
-- ----------------------------------------------------------------------------------------
    FUNCTION  get_tunnelcost_by_id(
        i_tunnel_id NUMBER -- vpn.tunnel.id of the tunnel we are interested in
    ) RETURN NUMBER;

-- ----------------------------------------------------------------------------------------
-- get_tunnelcost_partition
-- Purpose: calculate the OSPF cost of a tunnel given by its endpoints, Full Mesh ALF test
-- ----------------------------------------------------------------------------------------
    FUNCTION  get_tunnelcost_partition(
        i_partition_id NUMBER, -- vpn.partition.id of the partition we are interested in
        i_hostid1 NUMBER,      -- the mss.host.id of the first host
        i_hostid2 NUMBER       -- the mss.host.id of the second host (order is relevant)
    ) RETURN NUMBER;

-- ----------------------------------------------------------------------------------------
-- update_peer_status
-- Purpose: Update the actual status of all tunnels of the given host. The peer list
--          arguments contain comma separated lists of mss.host ids.
-- ----------------------------------------------------------------------------------------
    PROCEDURE update_peer_status(
        i_host_id NUMBER,
        i_logdate DATE,
        i_default_status NUMBER,
        i_csv_unknown_peers VARCHAR2,
        i_csv_down_peers VARCHAR2,
        i_csv_up_peers VARCHAR2,
        i_csv_slow_peers VARCHAR2);

END OSAG_VPN;
/
