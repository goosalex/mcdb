-- tt__ticket_interface__change_owner_company / call.pg.sql -- PostgreSQL twin of call.ora.sql.
-- Names from migration/mapping/name-map.csv: tt.ticket_interface.<name> ->
-- tt.ticket_interface_<name> (procedures -> CALL). OUT parameters (change_type,
-- change_service_component) are received in a local variable, trailing optional
-- arguments of change_owner are passed by name.
CREATE FUNCTION pg_temp.ok(p_step text, p_s text DEFAULT 'ok') RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    INSERT INTO diff_probe (step, s) VALUES (p_step, p_s);
END $f$;

CREATE FUNCTION pg_temp.owner(p_step text, p_ticket numeric, p_owner numeric) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.ticket_interface_change_owner(p_ticket, p_owner, 952103);
    PERFORM pg_temp.ok(p_step);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

-- the Zitadel branch: names supplied, no DB lookup; ids + company drive the UPDATE
CREATE FUNCTION pg_temp.owner_zitadel(p_step text, p_ticket numeric) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.ticket_interface_change_owner(p_ticket, NULL, 952103,
                                          p_zitadel_owner_id => 952777, p_company_id => 952101,
                                          p_owner_zitadel_first_name => 'Zita', p_owner_zitadel_last_name => 'Del');
    PERFORM pg_temp.ok(p_step);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.service_host(p_step text, p_ticket numeric, p_service numeric, p_host numeric) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.ticket_interface_change_service_host(p_ticket, p_service, p_host, 952103);
    PERFORM pg_temp.ok(p_step);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.component(p_step text, p_ticket numeric, p_component numeric) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_e numeric;
BEGIN
    CALL tt.ticket_interface_change_service_component(v_e, p_ticket, p_component, 952103);
    PERFORM pg_temp.ok(p_step, CASE WHEN v_e IS NOT NULL THEN 'event id set' ELSE 'event id null' END);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.ctype(p_step text, p_ticket numeric, p_type numeric) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_e numeric;
BEGIN
    CALL tt.ticket_interface_change_type(v_e, p_ticket, p_type, 952103);
    PERFORM pg_temp.ok(p_step, CASE WHEN v_e IS NOT NULL THEN 'event id set' ELSE 'event id null' END);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.company(p_step text, p_ticket numeric, p_company numeric) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.ticket_interface_change_company(p_ticket, p_company, 952103);
    PERFORM pg_temp.ok(p_step);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

DO $$
BEGIN
    PERFORM pg_temp.owner('01 owner -> contact of company B',          952110, 952104);
    PERFORM pg_temp.owner('02 owner -> NULL',                          952110, NULL);
    PERFORM pg_temp.owner_zitadel('03 owner zitadel names and ids',    952110);
    PERFORM pg_temp.owner('04 owner nonexistent contact',              952110, 952999999);
    PERFORM pg_temp.owner('05 owner nonexistent ticket',               952999999, 952104);
    PERFORM pg_temp.service_host('06 service_host full -> svc b host b',    952110, 952109, 952107);
    PERFORM pg_temp.service_host('07 service_host bare -> svc a host a',    952111, 952108, 952106);
    PERFORM pg_temp.service_host('08 service_host full -> nonexistent both', 952110, 952999999, 952999999);
    PERFORM pg_temp.service_host('09 service_host nonexistent ticket',      952999999, 952108, 952106);
    PERFORM pg_temp.component('10 component 1 -> 5',                   952110, 5);
    PERFORM pg_temp.component('11 component null -> 2',                952111, 2);
    PERFORM pg_temp.component('12 component 2 -> nonexistent',         952111, 952999999);
    PERFORM pg_temp.component('13 component nonexistent ticket',       952999999, 1);
    PERFORM pg_temp.ctype('14 type 1 -> 2',                            952110, 2);
    PERFORM pg_temp.ctype('15 type nonexistent',                       952110, 952999);
    PERFORM pg_temp.ctype('16 type nonexistent ticket',                952999999, 2);
    PERFORM pg_temp.company('17 company A -> B with notifications',    952112, 952102);
    PERFORM pg_temp.company('18 company bare -> nonexistent company',  952111, 952999999);
    PERFORM pg_temp.company('19 company nonexistent ticket',           952999999, 952102);
END $$;
