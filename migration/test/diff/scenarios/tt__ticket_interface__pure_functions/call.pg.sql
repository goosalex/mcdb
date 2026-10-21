-- tt__ticket_interface__pure_functions / call.pg.sql -- PostgreSQL twin of call.ora.sql.
-- Names from migration/mapping/name-map.csv: tt.ticket_interface.get_next_recent_ticket ->
-- tt.ticket_interface_get_next_recent_ticket, replace_id_placeholders ->
-- tt.ticket_interface_replace_id_placeholders (both FUNCTIONs).
CREATE FUNCTION pg_temp.next_ticket(p_step text, p_last numeric, p_host numeric, p_type numeric, p_age numeric) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_n numeric;
BEGIN
    v_n := tt.ticket_interface_get_next_recent_ticket(p_last, p_host, p_type, p_age);
    INSERT INTO diff_probe (step, n, s) VALUES (p_step, v_n, CASE WHEN v_n IS NULL THEN 'null' ELSE 'found' END);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.placeholders(p_step text, p_text text, p_ticket numeric, p_event numeric) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_s text;
BEGIN
    v_s := tt.ticket_interface_replace_id_placeholders(p_text, p_ticket, p_event);
    INSERT INTO diff_probe (step, s) VALUES (p_step, CASE WHEN v_s IS NULL THEN '<null>' ELSE v_s END);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

DO $$
BEGIN
    PERFORM pg_temp.next_ticket('01 first on host',                 NULL,   954075, NULL, NULL);
    PERFORM pg_temp.next_ticket('02 after G1 on host',              954080, 954075, NULL, NULL);
    PERFORM pg_temp.next_ticket('03 after G1 resolve age 60s',      954080, 954075, NULL, 60);
    PERFORM pg_temp.next_ticket('04 after G1 resolve age 3h',       954080, 954075, NULL, 10800);
    PERFORM pg_temp.next_ticket('05 after G1 type 2',               954080, 954075, 2,    NULL);
    PERFORM pg_temp.next_ticket('06 after G5 on host none left',    954084, 954075, NULL, NULL);
    PERFORM pg_temp.next_ticket('07 host 0 means no host type 12',  NULL,   0,      12,   NULL);
    PERFORM pg_temp.next_ticket('08 host 0 type 1 none',            NULL,   0,      1,    NULL);
    PERFORM pg_temp.next_ticket('09 other host G7',                 NULL,   954076, NULL, NULL);
    PERFORM pg_temp.next_ticket('10 host without tickets',          NULL,   954077, NULL, NULL);
    PERFORM pg_temp.placeholders('11 both placeholders',  'Ticket ##ticket_id## has event ##event_id##', 954080, 42);
    PERFORM pg_temp.placeholders('12 no placeholders',    'plain text', 954080, 42);
    PERFORM pg_temp.placeholders('13 null text',          NULL, 954080, 42);
    PERFORM pg_temp.placeholders('14 repeated',           '##ticket_id##/##ticket_id##/##event_id##', 7, 8);
    PERFORM pg_temp.placeholders('15 null event id',      'e=##event_id## t=##ticket_id##', 954080, NULL);
    PERFORM pg_temp.placeholders('16 null ticket id',     'e=##event_id## t=##ticket_id##', NULL, 42);
    PERFORM pg_temp.placeholders('17 both ids null no placeholders', 'nothing to replace', NULL, NULL);
END $$;
