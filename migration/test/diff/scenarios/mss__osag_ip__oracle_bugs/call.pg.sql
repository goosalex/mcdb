-- mss__osag_ip__oracle_bugs / call.pg.sql -- PostgreSQL twin of call.ora.sql.
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

CREATE FUNCTION pg_temp.t_ipv6left(p_step text, p_in varchar) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    INSERT INTO diff_probe (step, n) VALUES (p_step, mss.osag_ip_ipv6left(p_in));
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.t_ipv6right(p_step text, p_in varchar) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    INSERT INTO diff_probe (step, n) VALUES (p_step, mss.osag_ip_ipv6right(p_in));
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
    PERFORM pg_temp.t_ip2num('bug01 ip2num 1.a.3.4', '1.a.3.4');
    PERFORM pg_temp.t_ip2num('bug02 ip2num a.b.c.d', 'a.b.c.d');
    PERFORM pg_temp.t_ip2num('bug03 ip2num 10.0.0.1x', '10.0.0.1x');
    PERFORM pg_temp.t_ip2num('bug04 ip2num 1.2.3.4.5', '1.2.3.4.5');
    PERFORM pg_temp.t_num2ip('bug05 num2ip 1.5', 1.5);
    PERFORM pg_temp.t_ipv6left('bug06 ipv6left 1:2:3:4:5', '1:2:3:4:5');
    PERFORM pg_temp.t_ipv6right('bug07 ipv6right 1:2:3:4:5', '1:2:3:4:5');
    PERFORM pg_temp.t_ipv6left('bug08 ipv6left g::', 'g::');
    PERFORM pg_temp.t_ipv6right('bug09 ipv6right ::12345', '::12345');
    PERFORM pg_temp.t_ipv6left('bug10 ipv6left 1:2:3:4:5:6:7:8:9', '1:2:3:4:5:6:7:8:9');
    PERFORM pg_temp.t_ipv6right('bug11 ipv6right 1:2:3:4:5:6:7:8:9', '1:2:3:4:5:6:7:8:9');
    PERFORM pg_temp.t_ipv6left('bug12 ipv6left 7 groups 0:0:0:0:0:0:0001', '0:0:0:0:0:0:0001');
    PERFORM pg_temp.t_ipv6right('bug13 ipv6right 7 groups 0:0:0:0:0:0:0001', '0:0:0:0:0:0:0001');
    PERFORM pg_temp.t_num2ipv6('bug14 num2ipv6 NULL,NULL', NULL, NULL);
    PERFORM pg_temp.t_num2ipv6('bug15 num2ipv6 NULL,1', NULL, 1);
    PERFORM pg_temp.t_num2ipv6('bug16 num2ipv6 -1,0', -1, 0);
    PERFORM pg_temp.t_num2ipv6('bug17 num2ipv6 1.5,0', 1.5, 0);
    PERFORM pg_temp.t_num2ipv6('bug18 num2ipv6 2^64,0', 18446744073709551616, 0);
END $$;
