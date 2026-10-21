-- mss__osag_ip__pure / call.ora.sql
-- Every call is wrapped so that an exception becomes DATA (a diff_probe row with the
-- SQLCODE) instead of aborting the block. Results: numeric in n, string in s; for the
-- IPv6 pair the left half goes to n and the right half (as text) to s.
DECLARE
    -- SQLCODE/SQLERRM may not appear inside a SQL statement (ORA-00984); pass them as arguments.
    PROCEDURE log_err(p_step VARCHAR2, p_code NUMBER, p_msg VARCHAR2) IS
    BEGIN
        INSERT INTO diff_probe (step, code, msg) VALUES (p_step, TO_CHAR(p_code), SUBSTR(p_msg, 1, 4000));
    END;

    PROCEDURE t_ip2num(p_step VARCHAR2, p_in VARCHAR2) IS
    BEGIN
        INSERT INTO diff_probe (step, n) VALUES (p_step, mss.osag_ip.ip2num(p_in));
    EXCEPTION WHEN OTHERS THEN
        log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE t_num2ip(p_step VARCHAR2, p_in NUMBER) IS
    BEGIN
        INSERT INTO diff_probe (step, s) VALUES (p_step, mss.osag_ip.num2ip(p_in));
    EXCEPTION WHEN OTHERS THEN
        log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE t_getnet(p_step VARCHAR2, p_ip NUMBER, p_mask NUMBER) IS
    BEGIN
        INSERT INTO diff_probe (step, n) VALUES (p_step, mss.osag_ip.getnet(p_ip, p_mask));
    EXCEPTION WHEN OTHERS THEN
        log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE t_getbcast(p_step VARCHAR2, p_ip NUMBER, p_mask NUMBER) IS
    BEGIN
        INSERT INTO diff_probe (step, n) VALUES (p_step, mss.osag_ip.getbcast(p_ip, p_mask));
    EXCEPTION WHEN OTHERS THEN
        log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE t_ipv6(p_step VARCHAR2, p_in VARCHAR2) IS
    BEGIN
        INSERT INTO diff_probe (step, n, s)
        VALUES (p_step, mss.osag_ip.ipv6left(p_in), TO_CHAR(mss.osag_ip.ipv6right(p_in)));
    EXCEPTION WHEN OTHERS THEN
        log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE t_num2ipv6(p_step VARCHAR2, p_left NUMBER, p_right NUMBER) IS
    BEGIN
        INSERT INTO diff_probe (step, s) VALUES (p_step, mss.osag_ip.num2ipv6(p_left, p_right));
    EXCEPTION WHEN OTHERS THEN
        log_err(p_step, SQLCODE, SQLERRM);
    END;
BEGIN
    -- ip2num: well-formed (S-IP-004), NULL/'' (S-IP-003), too few dots (S-IP-005),
    -- non-canonical bytes (S-IP-006), byte > 255 (S-IP-007), empty byte (S-IP-010)
    t_ip2num('ip2num 01 1.2.3.4', '1.2.3.4');
    t_ip2num('ip2num 02 0.0.0.0', '0.0.0.0');
    t_ip2num('ip2num 03 255.255.255.255', '255.255.255.255');
    t_ip2num('ip2num 04 10.0.0.1', '10.0.0.1');
    t_ip2num('ip2num 05 192.168.1.255 broadcast', '192.168.1.255');
    t_ip2num('ip2num 06 NULL', NULL);
    t_ip2num('ip2num 07 empty string', '');
    t_ip2num('ip2num 08 1.2.3', '1.2.3');
    t_ip2num('ip2num 09 10.0.0', '10.0.0');
    t_ip2num('ip2num 10 10.0.0.01', '10.0.0.01');
    t_ip2num('ip2num 11 010.0.0.1', '010.0.0.1');
    t_ip2num('ip2num 12 10.0.0.+1', '10.0.0.+1');
    t_ip2num('ip2num 13 trailing space', '10.0.0.1 ');
    t_ip2num('ip2num 14 1.2.3.256', '1.2.3.256');
    t_ip2num('ip2num 15 256.0.0.1', '256.0.0.1');
    t_ip2num('ip2num 16 1..3.4', '1..3.4');
    t_ip2num('ip2num 17 1.2.3.', '1.2.3.');
    t_ip2num('ip2num 18 .1.2.3', '.1.2.3');
    -- '10.0.0.1.' is listed under S-IP-009 but Oracle's own path yields NULL for it:
    -- TO_NUMBER('1.') = 1 and TO_CHAR(1) = '1' != '1.' takes the RETURN NULL branch.
    t_ip2num('ip2num 19 10.0.0.1.', '10.0.0.1.');

    -- num2ip (S-IP-011..013)
    t_num2ip('num2ip 01 16909060', 16909060);
    t_num2ip('num2ip 02 0', 0);
    t_num2ip('num2ip 03 4294967295', 4294967295);
    t_num2ip('num2ip 04 167772161', 167772161);
    t_num2ip('num2ip 05 3232235777', 3232235777);
    t_num2ip('num2ip 06 NULL', NULL);
    t_num2ip('num2ip 07 -1', -1);
    t_num2ip('num2ip 08 4294967296', 4294967296);

    -- getnet / getbcast around 192.168.1.77 = 3232235853 (S-IP-001, S-IP-002)
    t_getnet('getnet 01 /24', 3232235853, 24);
    t_getnet('getnet 02 /32', 3232235853, 32);
    t_getnet('getnet 03 /0', 3232235853, 0);
    t_getnet('getnet 04 /25', 3232235853, 25);
    t_getnet('getnet 05 /16', 3232235853, 16);
    t_getnet('getnet 06 NULL mask', 3232235853, NULL);
    t_getnet('getnet 07 NULL ip', NULL, 24);
    t_getbcast('getbcast 01 /24', 3232235853, 24);
    t_getbcast('getbcast 02 /32', 3232235853, 32);
    t_getbcast('getbcast 03 /0', 3232235853, 0);
    t_getbcast('getbcast 04 /25', 3232235853, 25);
    t_getbcast('getbcast 05 /16', 3232235853, 16);
    t_getbcast('getbcast 06 NULL mask', 3232235853, NULL);
    t_getbcast('getbcast 07 NULL ip', NULL, 24);

    -- ipv6left / ipv6right (S-IP-015..019)
    t_ipv6('ipv6 01 ::', '::');
    t_ipv6('ipv6 02 ::1', '::1');
    t_ipv6('ipv6 03 1::', '1::');
    t_ipv6('ipv6 04 0:0:0:0:0:0:0:0001', '0:0:0:0:0:0:0:0001');
    t_ipv6('ipv6 05 ::1:2:3:4:5:6:7', '::1:2:3:4:5:6:7');
    t_ipv6('ipv6 06 1:2:3:4:5:6:7::', '1:2:3:4:5:6:7::');
    t_ipv6('ipv6 07 1:2::6:7', '1:2::6:7');
    t_ipv6('ipv6 08 1:0::7', '1:0::7');
    t_ipv6('ipv6 09 1::0:7', '1::0:7');
    t_ipv6('ipv6 10 1:1:1:1::1:1:1:1', '1:1:1:1::1:1:1:1');
    t_ipv6('ipv6 11 ::ffff:c000:201', '::ffff:c000:201');
    t_ipv6('ipv6 12 FFFF::', 'FFFF::');
    t_ipv6('ipv6 13 ::00Ff', '::00Ff');
    t_ipv6('ipv6 14 ffff:ffff:ffff:ffff::', 'ffff:ffff:ffff:ffff::');
    t_ipv6('ipv6 15 NULL', NULL);
    t_ipv6('ipv6 16 2001:db8::1', '2001:db8::1');

    -- num2ipv6 (S-IP-021, S-IP-022 incl. the preserved leading-two-zero-groups quirk)
    t_num2ipv6('num2ipv6 01 0,0', 0, 0);
    t_num2ipv6('num2ipv6 02 0,1', 0, 1);
    t_num2ipv6('num2ipv6 03 1::', 281474976710656, 0);
    t_num2ipv6('num2ipv6 04 1000::', 1152921504606846976, 0);
    t_num2ipv6('num2ipv6 05 f000::', 17293822569102704640, 0);
    t_num2ipv6('num2ipv6 06 ::f', 0, 15);
    t_num2ipv6('num2ipv6 07 1:1:1230::123:1:1', 281479576813568, 1249835548673);
    t_num2ipv6('num2ipv6 08 1:1:ff0::ff0:1:1', 281479539064832, 17523466633217);
    t_num2ipv6('num2ipv6 09 abcd::', 12379550950711361536, 0);
    t_num2ipv6('num2ipv6 10 1:0:1::1:1:1', 281474976776192, 4295032833);
    t_num2ipv6('num2ipv6 11 1::1:0:0:1:1', 281474976710657, 65537);
    t_num2ipv6('num2ipv6 12 1:1:1:1:1:1:1:1', 281479271743489, 281479271743489);
    t_num2ipv6('num2ipv6 13 quirk 0:0:1:1:1:1:1:1', 65537, 281479271743489);
    t_num2ipv6('num2ipv6 14 1:1:1:1:1:1::', 281479271743489, 281479271677952);
    t_num2ipv6('num2ipv6 15 2001:db8::1', 2306139568115548160, 1);
END;
/
