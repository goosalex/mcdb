-- tt__ticket_interface__deferral_ux / call.pg.sql -- PostgreSQL twin of call.ora.sql.
-- Names from migration/mapping/name-map.csv: tt.ticket_interface.<name> ->
-- tt.ticket_interface_<name> (procedures -> CALL). p_defer_date is a timestamp parameter
-- (Oracle DATE); EXTRACT on CAST(ux_timeout AS TIMESTAMP) is valid in both dialects.
CREATE FUNCTION pg_temp.rec_ux(p_step text, p_ticket numeric) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_s text;
BEGIN
    SELECT CASE WHEN ux_timeout IS NULL THEN 'ux null'
                ELSE 'ux ' || EXTRACT(DAY FROM CAST(ux_timeout AS TIMESTAMP)) || '/' || EXTRACT(HOUR FROM CAST(ux_timeout AS TIMESTAMP)) END
    INTO STRICT v_s FROM tt.ticket WHERE id = p_ticket;
    INSERT INTO diff_probe (step, s) VALUES (p_step, v_s);
END $f$;

CREATE FUNCTION pg_temp.deferral(p_step text, p_ticket numeric, p_date timestamp, p_text text) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.ticket_interface_change_deferral_date(p_ticket, 952202, p_date, p_text);
    PERFORM pg_temp.rec_ux(p_step, p_ticket);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.ux(p_step text, p_ticket numeric, p_initial boolean) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.ticket_interface_update_ux_timeout_for_ticket(p_ticket, p_initial);
    PERFORM pg_temp.rec_ux(p_step, p_ticket);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.emergency(p_step text, p_ticket numeric, p_flag numeric, p_new numeric, p_zitadel numeric) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.ticket_interface_change_emergency(p_ticket, p_flag, 952202, p_new, p_zitadel);
    PERFORM pg_temp.rec_ux(p_step, p_ticket);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

DO $$
BEGIN
    PERFORM pg_temp.deferral('01 deferral_date on deferred ticket',   952210, TIMESTAMP '2026-01-20 10:00:00', 'moved the deferral');
    PERFORM pg_temp.deferral('02 deferral_date on open ticket',       952211, TIMESTAMP '2026-01-20 10:00:00', 'should only warn');
    PERFORM pg_temp.deferral('03 deferral_date nonexistent ticket',   952999999, TIMESTAMP '2026-01-20 10:00:00', 'x');
    PERFORM pg_temp.ux('04 ux incident not initial',                  952211, FALSE);
    PERFORM pg_temp.ux('05 ux incident initial',                      952211, TRUE);
    PERFORM pg_temp.ux('06 ux change',                                952212, FALSE);
    PERFORM pg_temp.ux('07 ux maintenance window after start',        952213, FALSE);
    PERFORM pg_temp.ux('08 ux maintenance no window',                 952214, FALSE);
    PERFORM pg_temp.ux('09 ux third party incident',                  952215, FALSE);
    PERFORM pg_temp.ux('10 ux non-mcc',                               952216, FALSE);
    PERFORM pg_temp.ux('11 ux waiting status',                        952217, FALSE);
    PERFORM pg_temp.ux('12 ux problem',                               952218, FALSE);
    PERFORM pg_temp.ux('13 ux purchase order',                        952219, FALSE);
    PERFORM pg_temp.ux('14 ux maintenance window before start',       952221, FALSE);
    PERFORM pg_temp.ux('15 ux nonexistent ticket',                    952999999, FALSE);
    PERFORM pg_temp.emergency('16 emergency 1 not new',               952211, 1, 0, NULL);
    PERFORM pg_temp.emergency('17 emergency 0 not new',               952211, 0, 0, NULL);
    PERFORM pg_temp.emergency('18 emergency 1 new ticket',            952211, 1, 1, NULL);
    PERFORM pg_temp.emergency('19 emergency 1 with zitadel',          952212, 1, 0, 952777);
    PERFORM pg_temp.emergency('20 emergency nonexistent ticket',      952999999, 1, 0, NULL);
END $$;
