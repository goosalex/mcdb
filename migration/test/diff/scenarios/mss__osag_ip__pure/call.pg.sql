-- mss__osag_ip__pure / call.pg.sql -- PostgreSQL twin of call.ora.sql.
-- PL/pgSQL has no nested procedures: the Oracle block's local procedures become
-- session-temporary functions (pg_temp.*), dropped with the session. Names from
-- migration/mapping/name-map.csv: mss.osag_ip.<fn> -> mss.osag_ip_<fn>.
CREATE FUNCTION pg_temp.t_ip2num(p_step text, p_in varchar) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    INSERT INTO diff_probe (step, n) VALUES (p_step, mss.osag_ip_ip2num(p_in));
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.t_num2ip(p_step text, p_in numeric) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    INSERT INTO diff_probe (step, s) VALUES (p_step, mss.osag_ip_num2ip(p_in));
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.t_getnet(p_step text, p_ip numeric, p_mask numeric) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    INSERT INTO diff_probe (step, n) VALUES (p_step, mss.osag_ip_getnet(p_ip, p_mask));
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.t_getbcast(p_step text, p_ip numeric, p_mask numeric) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    INSERT INTO diff_probe (step, n) VALUES (p_step, mss.osag_ip_getbcast(p_ip, p_mask));
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.t_ipv6(p_step text, p_in varchar) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    INSERT INTO diff_probe (step, n, s)
    VALUES (p_step, mss.osag_ip_ipv6left(p_in), mss.osag_ip_ipv6right(p_in)::text);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.t_num2ipv6(p_step text, p_left numeric, p_right numeric) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    INSERT INTO diff_probe (step, s) VALUES (p_step, mss.osag_ip_num2ipv6(p_left, p_right));
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

DO $$
BEGIN
    PERFORM pg_temp.t_ip2num('ip2num 01 1.2.3.4', '1.2.3.4');
    PERFORM pg_temp.t_ip2num('ip2num 02 0.0.0.0', '0.0.0.0');
    PERFORM pg_temp.t_ip2num('ip2num 03 255.255.255.255', '255.255.255.255');
    PERFORM pg_temp.t_ip2num('ip2num 04 10.0.0.1', '10.0.0.1');
    PERFORM pg_temp.t_ip2num('ip2num 05 192.168.1.255 broadcast', '192.168.1.255');
    PERFORM pg_temp.t_ip2num('ip2num 06 NULL', NULL);
    PERFORM pg_temp.t_ip2num('ip2num 07 empty string', '');
    PERFORM pg_temp.t_ip2num('ip2num 08 1.2.3', '1.2.3');
    PERFORM pg_temp.t_ip2num('ip2num 09 10.0.0', '10.0.0');
    PERFORM pg_temp.t_ip2num('ip2num 10 10.0.0.01', '10.0.0.01');
    PERFORM pg_temp.t_ip2num('ip2num 11 010.0.0.1', '010.0.0.1');
    PERFORM pg_temp.t_ip2num('ip2num 12 10.0.0.+1', '10.0.0.+1');
    PERFORM pg_temp.t_ip2num('ip2num 13 trailing space', '10.0.0.1 ');
    PERFORM pg_temp.t_ip2num('ip2num 14 1.2.3.256', '1.2.3.256');
    PERFORM pg_temp.t_ip2num('ip2num 15 256.0.0.1', '256.0.0.1');
    PERFORM pg_temp.t_ip2num('ip2num 16 1..3.4', '1..3.4');
    PERFORM pg_temp.t_ip2num('ip2num 17 1.2.3.', '1.2.3.');
    PERFORM pg_temp.t_ip2num('ip2num 18 .1.2.3', '.1.2.3');
    PERFORM pg_temp.t_ip2num('ip2num 19 10.0.0.1.', '10.0.0.1.');

    PERFORM pg_temp.t_num2ip('num2ip 01 16909060', 16909060);
    PERFORM pg_temp.t_num2ip('num2ip 02 0', 0);
    PERFORM pg_temp.t_num2ip('num2ip 03 4294967295', 4294967295);
    PERFORM pg_temp.t_num2ip('num2ip 04 167772161', 167772161);
    PERFORM pg_temp.t_num2ip('num2ip 05 3232235777', 3232235777);
    PERFORM pg_temp.t_num2ip('num2ip 06 NULL', NULL);
    PERFORM pg_temp.t_num2ip('num2ip 07 -1', -1);
    PERFORM pg_temp.t_num2ip('num2ip 08 4294967296', 4294967296);

    PERFORM pg_temp.t_getnet('getnet 01 /24', 3232235853, 24);
    PERFORM pg_temp.t_getnet('getnet 02 /32', 3232235853, 32);
    PERFORM pg_temp.t_getnet('getnet 03 /0', 3232235853, 0);
    PERFORM pg_temp.t_getnet('getnet 04 /25', 3232235853, 25);
    PERFORM pg_temp.t_getnet('getnet 05 /16', 3232235853, 16);
    PERFORM pg_temp.t_getnet('getnet 06 NULL mask', 3232235853, NULL);
    PERFORM pg_temp.t_getnet('getnet 07 NULL ip', NULL, 24);
    PERFORM pg_temp.t_getbcast('getbcast 01 /24', 3232235853, 24);
    PERFORM pg_temp.t_getbcast('getbcast 02 /32', 3232235853, 32);
    PERFORM pg_temp.t_getbcast('getbcast 03 /0', 3232235853, 0);
    PERFORM pg_temp.t_getbcast('getbcast 04 /25', 3232235853, 25);
    PERFORM pg_temp.t_getbcast('getbcast 05 /16', 3232235853, 16);
    PERFORM pg_temp.t_getbcast('getbcast 06 NULL mask', 3232235853, NULL);
    PERFORM pg_temp.t_getbcast('getbcast 07 NULL ip', NULL, 24);

    PERFORM pg_temp.t_ipv6('ipv6 01 ::', '::');
    PERFORM pg_temp.t_ipv6('ipv6 02 ::1', '::1');
    PERFORM pg_temp.t_ipv6('ipv6 03 1::', '1::');
    PERFORM pg_temp.t_ipv6('ipv6 04 0:0:0:0:0:0:0:0001', '0:0:0:0:0:0:0:0001');
    PERFORM pg_temp.t_ipv6('ipv6 05 ::1:2:3:4:5:6:7', '::1:2:3:4:5:6:7');
    PERFORM pg_temp.t_ipv6('ipv6 06 1:2:3:4:5:6:7::', '1:2:3:4:5:6:7::');
    PERFORM pg_temp.t_ipv6('ipv6 07 1:2::6:7', '1:2::6:7');
    PERFORM pg_temp.t_ipv6('ipv6 08 1:0::7', '1:0::7');
    PERFORM pg_temp.t_ipv6('ipv6 09 1::0:7', '1::0:7');
    PERFORM pg_temp.t_ipv6('ipv6 10 1:1:1:1::1:1:1:1', '1:1:1:1::1:1:1:1');
    PERFORM pg_temp.t_ipv6('ipv6 11 ::ffff:c000:201', '::ffff:c000:201');
    PERFORM pg_temp.t_ipv6('ipv6 12 FFFF::', 'FFFF::');
    PERFORM pg_temp.t_ipv6('ipv6 13 ::00Ff', '::00Ff');
    PERFORM pg_temp.t_ipv6('ipv6 14 ffff:ffff:ffff:ffff::', 'ffff:ffff:ffff:ffff::');
    PERFORM pg_temp.t_ipv6('ipv6 15 NULL', NULL);
    PERFORM pg_temp.t_ipv6('ipv6 16 2001:db8::1', '2001:db8::1');

    PERFORM pg_temp.t_num2ipv6('num2ipv6 01 0,0', 0, 0);
    PERFORM pg_temp.t_num2ipv6('num2ipv6 02 0,1', 0, 1);
    PERFORM pg_temp.t_num2ipv6('num2ipv6 03 1::', 281474976710656, 0);
    PERFORM pg_temp.t_num2ipv6('num2ipv6 04 1000::', 1152921504606846976, 0);
    PERFORM pg_temp.t_num2ipv6('num2ipv6 05 f000::', 17293822569102704640, 0);
    PERFORM pg_temp.t_num2ipv6('num2ipv6 06 ::f', 0, 15);
    PERFORM pg_temp.t_num2ipv6('num2ipv6 07 1:1:1230::123:1:1', 281479576813568, 1249835548673);
    PERFORM pg_temp.t_num2ipv6('num2ipv6 08 1:1:ff0::ff0:1:1', 281479539064832, 17523466633217);
    PERFORM pg_temp.t_num2ipv6('num2ipv6 09 abcd::', 12379550950711361536, 0);
    PERFORM pg_temp.t_num2ipv6('num2ipv6 10 1:0:1::1:1:1', 281474976776192, 4295032833);
    PERFORM pg_temp.t_num2ipv6('num2ipv6 11 1::1:0:0:1:1', 281474976710657, 65537);
    PERFORM pg_temp.t_num2ipv6('num2ipv6 12 1:1:1:1:1:1:1:1', 281479271743489, 281479271743489);
    PERFORM pg_temp.t_num2ipv6('num2ipv6 13 quirk 0:0:1:1:1:1:1:1', 65537, 281479271743489);
    PERFORM pg_temp.t_num2ipv6('num2ipv6 14 1:1:1:1:1:1::', 281479271743489, 281479271677952);
    PERFORM pg_temp.t_num2ipv6('num2ipv6 15 2001:db8::1', 2306139568115548160, 1);
END $$;
