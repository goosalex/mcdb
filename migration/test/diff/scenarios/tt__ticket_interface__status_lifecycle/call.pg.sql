-- tt__ticket_interface__status_lifecycle / call.pg.sql -- PostgreSQL twin of call.ora.sql.
-- Names from migration/mapping/name-map.csv: tt.ticket_interface.change_status ->
-- tt.ticket_interface_change_status (procedure -> CALL), change_subject likewise.
CREATE FUNCTION pg_temp.record_state(p_step text, p_ticket numeric) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
    v_status numeric;
    v_valid  text;
BEGIN
    SELECT status_id, CASE WHEN status_valid_until_date IS NULL THEN 'null' ELSE 'set' END
    INTO STRICT v_status, v_valid
    FROM tt.ticket WHERE id = p_ticket;
    INSERT INTO diff_probe (step, n, s) VALUES (p_step, v_status, v_valid);
END $f$;

CREATE FUNCTION pg_temp.step_status(p_step text, p_ticket numeric, p_status numeric, p_text text) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.ticket_interface_change_status(p_ticket, p_status, 950002, p_text);
    PERFORM pg_temp.record_state(p_step, p_ticket);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

CREATE FUNCTION pg_temp.step_subject(p_step text, p_ticket numeric, p_subject text) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    CALL tt.ticket_interface_change_subject(p_ticket, p_subject, 950002);
    PERFORM pg_temp.record_state(p_step, p_ticket);
EXCEPTION WHEN OTHERS THEN
    INSERT INTO diff_probe (step, code, msg) VALUES (p_step, SQLSTATE, left(SQLERRM, 4000));
END $f$;

DO $$
BEGIN
    PERFORM pg_temp.record_state('00 initial', 950010);
    PERFORM pg_temp.step_status('01 open->hot', 950010, 3, 'moved to hot');
    PERFORM pg_temp.step_status('02 hot->hot no-op', 950010, 3, 'same status again');
    PERFORM pg_temp.step_status('03 hot->waiting', 950010, 11, 'waiting for the customer');
    PERFORM pg_temp.step_status('04 waiting->closed', 950010, 102, 'closing');
    PERFORM pg_temp.step_subject('05 change_subject', 950010, 'changed subject');
    PERFORM pg_temp.step_status('06 nonexistent ticket', 950999999, 3, 'should fail with NO_DATA_FOUND');
    PERFORM pg_temp.step_subject('07 change_subject nonexistent', 950999999, 'x');
END $$;
