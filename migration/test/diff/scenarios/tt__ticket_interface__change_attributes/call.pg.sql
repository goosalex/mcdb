-- tt__ticket_interface__change_attributes / call.pg.sql -- PostgreSQL twin of call.ora.sql.
-- Names from migration/mapping/name-map.csv: tt.ticket_interface.<name> ->
-- tt.ticket_interface_<name> (procedures -> CALL). change_label keeps both overloads;
-- PostgreSQL dispatches on the argument count exactly as Oracle does (S-TICKET-020).
CREATE FUNCTION pg_temp.ok(p_step text) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    INSERT INTO diff_probe (step, s) VALUES (p_step, 'ok');
END $f$;

CREATE FUNCTION pg_temp.cust_ref(p_step text, p_ticket numeric, p_ref text) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.ticket_interface_change_customer_reference(p_ticket, p_ref, 952002);
    PERFORM pg_temp.ok(p_step);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.partner_ref(p_step text, p_ticket numeric, p_ref text) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.ticket_interface_change_partner_reference(p_ticket, p_ref, 952002);
    PERFORM pg_temp.ok(p_step);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

-- the bare 2-arg overload (S-TICKET-019)
CREATE FUNCTION pg_temp.label2(p_step text, p_ticket numeric, p_label numeric) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.ticket_interface_change_label(p_ticket, p_label);
    PERFORM pg_temp.ok(p_step);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

-- the audited 3/4-arg overload (S-TICKET-020)
CREATE FUNCTION pg_temp.label4(p_step text, p_ticket numeric, p_label numeric) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.ticket_interface_change_label(p_ticket, p_label, 952002);
    PERFORM pg_temp.ok(p_step);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.always_visible(p_step text, p_ticket numeric, p_flag numeric, p_zitadel numeric) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.ticket_interface_change_always_visible(p_ticket, p_flag, 952002, p_zitadel);
    PERFORM pg_temp.ok(p_step);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.notification(p_step text, p_ticket numeric, p_pub text, p_priv text) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.ticket_interface_change_notification(p_ticket, p_pub, p_priv, 952002);
    PERFORM pg_temp.ok(p_step);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.summary(p_step text, p_ticket numeric, p_priv text, p_pub text) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.ticket_interface_change_summary(p_ticket, p_priv, p_pub, 952002);
    PERFORM pg_temp.ok(p_step);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

DO $$
BEGIN
    PERFORM pg_temp.cust_ref('01 customer_reference CR-1',          952010, 'CR-1');
    PERFORM pg_temp.cust_ref('02 customer_reference NULL',          952010, NULL);
    PERFORM pg_temp.cust_ref('03 customer_reference empty string',  952010, '');
    PERFORM pg_temp.partner_ref('04 partner_reference PR-1',        952010, 'PR-1');
    PERFORM pg_temp.partner_ref('05 partner_reference NULL',        952010, NULL);
    PERFORM pg_temp.label2('06 label2 null->1',                     952010, 1);
    PERFORM pg_temp.label4('07 label4 1->3',                        952010, 3);
    PERFORM pg_temp.label4('08 label4 3->null',                     952010, NULL);
    PERFORM pg_temp.label4('09 label4 null->4',                     952010, 4);
    PERFORM pg_temp.label4('10 label4 nonexistent label',           952010, 952999);
    PERFORM pg_temp.label2('11 label2 nonexistent ticket',          952999999, 1);
    PERFORM pg_temp.label4('12 label4 nonexistent ticket',          952999999, 1);
    PERFORM pg_temp.always_visible('13 always_visible 1',           952010, 1, NULL);
    PERFORM pg_temp.always_visible('14 always_visible 0 with zitadel', 952010, 0, 952777);
    PERFORM pg_temp.notification('15 notification pub and priv',    952010, 'added email', 'added sms');
    PERFORM pg_temp.notification('16 notification priv only',       952010, NULL, 'removed sms');
    PERFORM pg_temp.notification('17 notification empty pub, priv', 952010, '', 'empty public');
    PERFORM pg_temp.summary('18 summary private only',              952011, 'new private', 'old public');
    PERFORM pg_temp.summary('19 summary public only',               952011, 'new private', 'new public');
    PERFORM pg_temp.summary('20 summary both NULL',                 952011, NULL, NULL);
    PERFORM pg_temp.summary('21 summary both NULL again no-op',     952011, NULL, NULL);
    PERFORM pg_temp.summary('22 summary both empty string',         952011, '', '');
    PERFORM pg_temp.cust_ref('23 customer_reference nonexistent ticket', 952999999, 'x');
END $$;
