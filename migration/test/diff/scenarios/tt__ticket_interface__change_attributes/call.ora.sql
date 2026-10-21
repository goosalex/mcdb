-- tt__ticket_interface__change_attributes / call.ora.sql
-- Every step records 'ok' in s, or the error code (SQLCODE) in code. Contact 952002 is the
-- acting contact throughout. Spec clauses: S-TICKET-015/018 (customer reference),
-- S-TICKET-022 (partner reference), S-TICKET-019/020 (change_label overloads),
-- S-TICKET-026 (always_visible), S-TICKET-027 (notification), S-TICKET-028/029 (summary).
DECLARE
    -- SQLCODE/SQLERRM may not appear inside a SQL statement (ORA-00984); pass them as arguments.
    PROCEDURE log_err(p_step VARCHAR2, p_code NUMBER, p_msg VARCHAR2) IS
    BEGIN
        INSERT INTO diff_probe (step, code, msg) VALUES (p_step, TO_CHAR(p_code), SUBSTR(p_msg, 1, 4000));
    END;

    PROCEDURE ok(p_step VARCHAR2) IS
    BEGIN
        INSERT INTO diff_probe (step, s) VALUES (p_step, 'ok');
    END;

    PROCEDURE cust_ref(p_step VARCHAR2, p_ticket NUMBER, p_ref VARCHAR2) IS
    BEGIN
        tt.ticket_interface.change_customer_reference(p_ticket, p_ref, 952002);
        ok(p_step);
    EXCEPTION WHEN OTHERS THEN log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE partner_ref(p_step VARCHAR2, p_ticket NUMBER, p_ref VARCHAR2) IS
    BEGIN
        tt.ticket_interface.change_partner_reference(p_ticket, p_ref, 952002);
        ok(p_step);
    EXCEPTION WHEN OTHERS THEN log_err(p_step, SQLCODE, SQLERRM);
    END;

    -- the bare 2-arg overload (S-TICKET-019)
    PROCEDURE label2(p_step VARCHAR2, p_ticket NUMBER, p_label NUMBER) IS
    BEGIN
        tt.ticket_interface.change_label(p_ticket, p_label);
        ok(p_step);
    EXCEPTION WHEN OTHERS THEN log_err(p_step, SQLCODE, SQLERRM);
    END;

    -- the audited 3/4-arg overload (S-TICKET-020)
    PROCEDURE label4(p_step VARCHAR2, p_ticket NUMBER, p_label NUMBER) IS
    BEGIN
        tt.ticket_interface.change_label(p_ticket, p_label, 952002);
        ok(p_step);
    EXCEPTION WHEN OTHERS THEN log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE always_visible(p_step VARCHAR2, p_ticket NUMBER, p_flag NUMBER, p_zitadel NUMBER) IS
    BEGIN
        tt.ticket_interface.change_always_visible(p_ticket, p_flag, 952002, p_zitadel);
        ok(p_step);
    EXCEPTION WHEN OTHERS THEN log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE notification(p_step VARCHAR2, p_ticket NUMBER, p_pub VARCHAR2, p_priv VARCHAR2) IS
    BEGIN
        tt.ticket_interface.change_notification(p_ticket, p_pub, p_priv, 952002);
        ok(p_step);
    EXCEPTION WHEN OTHERS THEN log_err(p_step, SQLCODE, SQLERRM);
    END;

    PROCEDURE summary(p_step VARCHAR2, p_ticket NUMBER, p_priv VARCHAR2, p_pub VARCHAR2) IS
    BEGIN
        tt.ticket_interface.change_summary(p_ticket, p_priv, p_pub, 952002);
        ok(p_step);
    EXCEPTION WHEN OTHERS THEN log_err(p_step, SQLCODE, SQLERRM);
    END;
BEGIN
    cust_ref('01 customer_reference CR-1',          952010, 'CR-1');
    cust_ref('02 customer_reference NULL',          952010, NULL);
    cust_ref('03 customer_reference empty string',  952010, '');
    partner_ref('04 partner_reference PR-1',        952010, 'PR-1');
    partner_ref('05 partner_reference NULL',        952010, NULL);
    label2('06 label2 null->1',                     952010, 1);
    label4('07 label4 1->3',                        952010, 3);
    label4('08 label4 3->null',                     952010, NULL);
    label4('09 label4 null->4',                     952010, 4);
    label4('10 label4 nonexistent label',           952010, 952999);
    label2('11 label2 nonexistent ticket',          952999999, 1);
    label4('12 label4 nonexistent ticket',          952999999, 1);
    always_visible('13 always_visible 1',           952010, 1, NULL);
    always_visible('14 always_visible 0 with zitadel', 952010, 0, 952777);
    notification('15 notification pub and priv',    952010, 'added email', 'added sms');
    notification('16 notification priv only',       952010, NULL, 'removed sms');
    notification('17 notification empty pub, priv', 952010, '', 'empty public');
    summary('18 summary private only',              952011, 'new private', 'old public');
    summary('19 summary public only',               952011, 'new private', 'new public');
    summary('20 summary both NULL',                 952011, NULL, NULL);
    summary('21 summary both NULL again no-op',     952011, NULL, NULL);
    summary('22 summary both empty string',         952011, '', '');
    cust_ref('23 customer_reference nonexistent ticket', 952999999, 'x');
END;
/
