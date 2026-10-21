-- tt__ticket_interface__change_owner_company / call.ora.sql
-- Contact 952103 acts throughout. Every step records 'ok' (or 'event id set' for the two
-- OUT-parameter routines) in s, or the error code in code. Spec clauses: S-TICKET-023
-- (change_owner), S-TICKET-015/016 (change_service_host), S-TICKET-032 (service component),
-- S-TICKET-030/031 (change_type), S-TICKET-024 (change_company).
DECLARE
    -- SQLCODE/SQLERRM may not appear inside a SQL statement (ORA-00984); pass them as arguments.
    PROCEDURE log_err(p_step VARCHAR2, p_code NUMBER, p_msg VARCHAR2) IS
    BEGIN
        INSERT INTO diff_probe (step, code, msg) VALUES (p_step, TO_CHAR(p_code), SUBSTR(p_msg, 1, 4000));
    END;

    PROCEDURE ok(p_step VARCHAR2, p_s VARCHAR2 DEFAULT 'ok') IS
    BEGIN
        INSERT INTO diff_probe (step, s) VALUES (p_step, p_s);
    END;

    PROCEDURE owner(p_step VARCHAR2, p_ticket NUMBER, p_owner NUMBER) IS
    BEGIN
        tt.ticket_interface.change_owner(p_ticket, p_owner, 952103);
        ok(p_step);
    EXCEPTION WHEN OTHERS THEN log_err(p_step, SQLCODE, SQLERRM);
    END;

    -- the Zitadel branch: names supplied, no DB lookup; ids + company drive the UPDATE
    PROCEDURE owner_zitadel(p_step VARCHAR2, p_ticket NUMBER) IS
    BEGIN
        tt.ticket_interface.change_owner(p_ticket, NULL, 952103,
                                         p_zitadel_owner_id => 952777, p_company_id => 952101,
                                         p_owner_zitadel_first_name => 'Zita', p_owner_zitadel_last_name => 'Del');
        ok(p_step);
    EXCEPTION WHEN OTHERS THEN log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE service_host(p_step VARCHAR2, p_ticket NUMBER, p_service NUMBER, p_host NUMBER) IS
    BEGIN
        tt.ticket_interface.change_service_host(p_ticket, p_service, p_host, 952103);
        ok(p_step);
    EXCEPTION WHEN OTHERS THEN log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE component(p_step VARCHAR2, p_ticket NUMBER, p_component NUMBER) IS
        v_e NUMBER;
    BEGIN
        tt.ticket_interface.change_service_component(v_e, p_ticket, p_component, 952103);
        ok(p_step, CASE WHEN v_e IS NOT NULL THEN 'event id set' ELSE 'event id null' END);
    EXCEPTION WHEN OTHERS THEN log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE ctype(p_step VARCHAR2, p_ticket NUMBER, p_type NUMBER) IS
        v_e NUMBER;
    BEGIN
        tt.ticket_interface.change_type(v_e, p_ticket, p_type, 952103);
        ok(p_step, CASE WHEN v_e IS NOT NULL THEN 'event id set' ELSE 'event id null' END);
    EXCEPTION WHEN OTHERS THEN log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE company(p_step VARCHAR2, p_ticket NUMBER, p_company NUMBER) IS
    BEGIN
        tt.ticket_interface.change_company(p_ticket, p_company, 952103);
        ok(p_step);
    EXCEPTION WHEN OTHERS THEN log_err(p_step, SQLCODE, SQLERRM);
    END;
BEGIN
    owner('01 owner -> contact of company B',          952110, 952104);
    owner('02 owner -> NULL',                          952110, NULL);
    owner_zitadel('03 owner zitadel names and ids',    952110);
    owner('04 owner nonexistent contact',              952110, 952999999);
    owner('05 owner nonexistent ticket',               952999999, 952104);
    service_host('06 service_host full -> svc b host b',    952110, 952109, 952107);
    service_host('07 service_host bare -> svc a host a',    952111, 952108, 952106);
    service_host('08 service_host full -> nonexistent both', 952110, 952999999, 952999999);
    service_host('09 service_host nonexistent ticket',      952999999, 952108, 952106);
    component('10 component 1 -> 5',                   952110, 5);
    component('11 component null -> 2',                952111, 2);
    component('12 component 2 -> nonexistent',         952111, 952999999);
    component('13 component nonexistent ticket',       952999999, 1);
    ctype('14 type 1 -> 2',                            952110, 2);
    ctype('15 type nonexistent',                       952110, 952999);
    ctype('16 type nonexistent ticket',                952999999, 2);
    company('17 company A -> B with notifications',    952112, 952102);
    company('18 company bare -> nonexistent company',  952111, 952999999);
    company('19 company nonexistent ticket',           952999999, 952102);
END;
/
