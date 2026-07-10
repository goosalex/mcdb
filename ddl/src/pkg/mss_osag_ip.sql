--liquibase formatted sql logicalFilePath:pkg/mss_osag_ip.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE MSS.OSAG_IP AS
    /*
     * Can be used to convert ip addresses between the string form (A.B.C.D)
     * and the numeric form (x = A*256^3+B*256^2+C*256+D)
     */

    FUNCTION getbcast(p_ip NUMBER, p_mask NUMBER) RETURN NUMBER DETERMINISTIC;
    FUNCTION getnet(p_ip NUMBER, p_mask NUMBER) RETURN NUMBER DETERMINISTIC;
    FUNCTION ip2num(p_string VARCHAR2) RETURN NUMBER DETERMINISTIC;
    FUNCTION num2ip(p_number NUMBER) RETURN VARCHAR2 DETERMINISTIC;

    -- returns the left (64 most significant bits) of an IPv6 address
    FUNCTION ipv6left(p_ip varchar2) return integer DETERMINISTIC;
    -- returns the right (64 least significant bits) of an IPv6 address
    FUNCTION ipv6right(p_ip varchar2) return integer DETERMINISTIC;
    -- formats an IPv6 address from most (left) and least (right) significant 64 bits values
    FUNCTION num2ipv6(p_left integer, p_right integer) return varchar2 DETERMINISTIC;
END OSAG_IP;
/

create or replace public synonym OSAG_IP for MSS.OSAG_IP
/

