-- mss__osag_ip__oracle_bugs / call.ora.sql
-- Inputs on which Oracle misbehaves (raises or returns a non-address) and the translation
-- was corrected to return NULL. Each row is expected to DIFFER; see known.diff.
DECLARE
    PROCEDURE t_ip2num(p_step VARCHAR2, p_in VARCHAR2) IS
    BEGIN
        INSERT INTO diff_probe (step, n) VALUES (p_step, mss.osag_ip.ip2num(p_in));
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO diff_probe (step, code, msg) VALUES (p_step, TO_CHAR(SQLCODE), SUBSTR(SQLERRM, 1, 4000));
    END;

    PROCEDURE t_num2ip(p_step VARCHAR2, p_in NUMBER) IS
    BEGIN
        INSERT INTO diff_probe (step, s) VALUES (p_step, mss.osag_ip.num2ip(p_in));
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO diff_probe (step, code, msg) VALUES (p_step, TO_CHAR(SQLCODE), SUBSTR(SQLERRM, 1, 4000));
    END;

    -- left and right are evaluated separately so a raise in one half does not hide the
    -- other half's value (S-IP-020 documents 'left partial, right NULL' shapes)
    PROCEDURE t_ipv6left(p_step VARCHAR2, p_in VARCHAR2) IS
    BEGIN
        INSERT INTO diff_probe (step, n) VALUES (p_step, mss.osag_ip.ipv6left(p_in));
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO diff_probe (step, code, msg) VALUES (p_step, TO_CHAR(SQLCODE), SUBSTR(SQLERRM, 1, 4000));
    END;

    PROCEDURE t_ipv6right(p_step VARCHAR2, p_in VARCHAR2) IS
    BEGIN
        INSERT INTO diff_probe (step, n) VALUES (p_step, mss.osag_ip.ipv6right(p_in));
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO diff_probe (step, code, msg) VALUES (p_step, TO_CHAR(SQLCODE), SUBSTR(SQLERRM, 1, 4000));
    END;

    PROCEDURE t_num2ipv6(p_step VARCHAR2, p_left NUMBER, p_right NUMBER) IS
    BEGIN
        INSERT INTO diff_probe (step, s) VALUES (p_step, mss.osag_ip.num2ipv6(p_left, p_right));
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO diff_probe (step, code, msg) VALUES (p_step, TO_CHAR(SQLCODE), SUBSTR(SQLERRM, 1, 4000));
    END;
BEGIN
    -- S-IP-008: non-numeric byte -> Oracle ORA-06502, translation NULL
    t_ip2num('bug01 ip2num 1.a.3.4', '1.a.3.4');
    t_ip2num('bug02 ip2num a.b.c.d', 'a.b.c.d');
    t_ip2num('bug03 ip2num 10.0.0.1x', '10.0.0.1x');
    -- S-IP-009: more than three dots -> Oracle 16909060.5, translation NULL
    t_ip2num('bug04 ip2num 1.2.3.4.5', '1.2.3.4.5');
    -- S-IP-014: fractional input -> Oracle '0.0.0.1.5', translation NULL
    t_num2ip('bug05 num2ip 1.5', 1.5);
    -- S-IP-020: malformed IPv6 -> Oracle partial value / NULL / ORA-01722, translation NULL
    t_ipv6left('bug06 ipv6left 1:2:3:4:5', '1:2:3:4:5');
    t_ipv6right('bug07 ipv6right 1:2:3:4:5', '1:2:3:4:5');
    t_ipv6left('bug08 ipv6left g::', 'g::');
    t_ipv6right('bug09 ipv6right ::12345', '::12345');
    t_ipv6left('bug10 ipv6left 1:2:3:4:5:6:7:8:9', '1:2:3:4:5:6:7:8:9');
    t_ipv6right('bug11 ipv6right 1:2:3:4:5:6:7:8:9', '1:2:3:4:5:6:7:8:9');
    t_ipv6left('bug12 ipv6left 7 groups 0:0:0:0:0:0:0001', '0:0:0:0:0:0:0001');
    t_ipv6right('bug13 ipv6right 7 groups 0:0:0:0:0:0:0001', '0:0:0:0:0:0:0001');
    -- S-IP-023: NULL / negative / fractional / >= 2^64 halves -> Oracle renders something, translation NULL
    t_num2ipv6('bug14 num2ipv6 NULL,NULL', NULL, NULL);
    t_num2ipv6('bug15 num2ipv6 NULL,1', NULL, 1);
    t_num2ipv6('bug16 num2ipv6 -1,0', -1, 0);
    t_num2ipv6('bug17 num2ipv6 1.5,0', 1.5, 0);
    t_num2ipv6('bug18 num2ipv6 2^64,0', 18446744073709551616, 0);
END;
/
