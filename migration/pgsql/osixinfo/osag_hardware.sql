-- migration/pgsql/osixinfo/osag_hardware.sql
--
-- Translation of OSIXINFO.OSAG_HARDWARE (spec: migration/spec/osixinfo.osag_hardware.md;
-- Oracle body: ddl/src/pkgb/osixinfo_osag_hardware.sql, 206 lines). Public names copied
-- verbatim from migration/mapping/name-map.csv's 3 OSAG_HARDWARE rows (all
-- pg_kind=procedure). The one body-only helper is private:
-- osixinfo.osag_hardware__dump_to_hw_history, EXECUTE revoked from PUBLIC (S-HW-001).
--
-- OSIXINFO.OSAG_EXCEPTIONS (ddl/src/pkg/osixinfo_osag_exceptions.sql: e_abort, e_silentexit,
-- empty body) gets NO PostgreSQL object (S-HW-012): e_abort -> SQLSTATE 'OS010' (raised with
-- RAISE EXCEPTION ... USING ERRCODE = 'OS010', caught with WHEN SQLSTATE 'OS010');
-- e_silentexit -> 'OS011', reserved, never raised anywhere in ddl/src. PROVISIONAL (XCUT-01),
-- see osag_hardware.FINDINGS.md. The e_abort exception's MESSAGE_TEXT is the S-HW-004 log
-- line itself (Oracle's ORA-06510 carried no text): the plog stub is transactional (Oracle's
-- plog was autonomous), so a row written just before RAISE would be erased by the catching
-- handler's subtransaction rollback -- the catcher (check_replaced_hw_for_host) emits the
-- carried line, and a caller of replace_hardware that sees the exception can read the
-- reason from its message. The package spec's two public constants are inlined:
-- HW_CHANGED_EVENT_TYPE = 10017, TODO_PRIVATE_HW_MIG = the four-line to-do text (S-HW-001).
--
-- Oracle's usage-audit call (XCUT-06): all 4 plog.AuditUsage sites (lines 24, 91, 121, 175 --
-- one per routine incl. the private helper) DELETED, not ported.
--
-- No deviation from Oracle in this package: every clause of the spec is Oracle-faithful,
-- including check_replaced_hw_for_host's procedure-wide NO_DATA_FOUND swallow (S-HW-013).
--
-- Oracle NUMBER -> bigint/numeric (%TYPE anchors kept on every signature), VARCHAR2 ->
-- varchar, DATE -> timestamp, SYSDATE -> statement_timestamp(), seq.nextval -> nextval('seq'),
-- %ROWTYPE kept, plog.<level>() -> CALL osag.osag_plog_<level>(), SELECT ... FROM dual ->
-- expression. Every SELECT INTO is STRICT and carries the clause id / strictness-table site
-- number of the spec. The "no data found" message-parity shim (sqlstate-map.md rule 2) wraps
-- replace_hardware's body once: NO_DATA_FOUND from dump_to_hw_history is externally reachable
-- and unhandled there (S-HW-011); check_replaced_hw_for_host's own NO_DATA_FOUND arm catches
-- the re-raised P0002 exactly as Oracle's does.
--
-- NULL concatenation (Pitfall 2 / spec checklist 1): concat() where an operand can be NULL
-- (stop.contact.email in the history log text, S-HW-005); plain `||` where every operand is
-- provably NOT NULL. p_reported_mac is normalised with NULLIF(..., '') so a PostgreSQL ''
-- behaves like Oracle's '' (= NULL): no row matches, silent return (S-HW-008).

-- ------------------------------------------------------------------------------------
-- dump_to_hw_history (S-HW-004..007, private): archive the hardware with the given id to
-- mss.hardware_history. Called from replace_hardware only. Raises e_abort (OS010) on a
-- NULL disposal contact/reason; NO_DATA_FOUND / TOO_MANY_ROWS / NOT NULL violations
-- propagate unhandled. Runs BEFORE any DML of the replacement (S-HW-003 (1)).
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE osixinfo.osag_hardware__dump_to_hw_history(
    p_host_id mss.host.id%TYPE,            -- id of the host where the hw belonged to
    p_old_hardware_id mss.hardware.id%TYPE -- id of the hw to dump
)
LANGUAGE plpgsql
AS $fn$
DECLARE
    c_prefix CONSTANT varchar := 'dump_to_hw_history: ';

    v_oldhardware mss.hardware%ROWTYPE;
    v_hostname mss.host.name%TYPE;
    v_compshort stop.company.short%TYPE;
    v_stypeicode mss.service_type.internal_code%TYPE;
    v_log mss.hardware_history.log%TYPE;
BEGIN
    -- get the old hardware record. Strictness table site #1: STRICT, unhandled here.
    SELECT * INTO STRICT v_oldhardware
    FROM mss.hardware WHERE id = p_old_hardware_id;

    -- check data sanity (S-HW-004: contact first, then reason)
    IF v_oldhardware.hardware_disposal_contact_id IS NULL THEN
        -- e_abort carries its log line (see the file header): emitted by the catcher.
        RAISE EXCEPTION '%', c_prefix || 'hardware_disposal_contact_id is NULL while replacing hw for host_id: ' || p_host_id || ' hw_id: ' || p_old_hardware_id
            USING ERRCODE = 'OS010', DETAIL = 'ERR';
    END IF;
    IF v_oldhardware.hardware_disposal_reason_id IS NULL THEN
        RAISE EXCEPTION '%', c_prefix || 'hardware_disposal_reason_id is NULL while replacing hw for host_id: ' || p_host_id || ' hw_id: ' || p_old_hardware_id
            USING ERRCODE = 'OS010', DETAIL = 'ERR';
    END IF;

    -- get log information (S-HW-005). Strictness table site #2: STRICT, unhandled.
    -- concat(): stop.contact.email is nullable -- Oracle kept the rest of the text.
    SELECT concat('hardware_type=', ht.short, ';disposal_contact=', c.email, ';disposal_reason=', dr.name)
    INTO STRICT v_log
    FROM mss.hardware hw
             INNER JOIN mss.hardware_type ht ON (hw.hardware_type_id = ht.id)
             INNER JOIN mss.hardware_disposal_reason dr ON (hw.hardware_disposal_reason_id = dr.id)
             INNER JOIN stop.contact c ON (hw.hardware_disposal_contact_id = c.id)
    WHERE hw.id = p_old_hardware_id;

    -- get host, service and company (S-HW-006). Strictness table site #3: STRICT, unhandled
    -- -- a host with two services raises TOO_MANY_ROWS out of the whole package.
    SELECT h.name, co.short, st.internal_code
    INTO STRICT v_hostname, v_compshort, v_stypeicode
    FROM mss.host h
             INNER JOIN stop.company co ON (h.service_company_id = co.id)
             INNER JOIN mss.host2service h2s ON (h.id = h2s.host_id)
             INNER JOIN mss.service s ON (h2s.service_id = s.id)
             INNER JOIN mss.service_type st ON (s.service_type_id = st.id)
    WHERE h.id = p_host_id;

    -- insert record to mss.hardware_history (S-HW-007). NOT NULL columns (company_short,
    -- purchase_date, ...) make this fail with 23502 when the source is NULL -- unhandled,
    -- as in Oracle.
    INSERT INTO mss.hardware_history (id, barcode, company_short, disposal_date, hardware_disposal_comments,
                                      hardware_disposal_contact_id, hardware_disposal_reason_id, hardware_type_id, history_date,
                                      host_name, log, mac_address, purchase_date, serial_number, service_type_internal_code, hardware_deploy_reason_id)
    VALUES (nextval('mss.hardwarehistory_seq'), v_oldhardware.barcode, v_compshort, COALESCE(v_oldhardware.disposal_date, statement_timestamp()),
            v_oldhardware.hardware_disposal_comments, v_oldhardware.hardware_disposal_contact_id,
            v_oldhardware.hardware_disposal_reason_id, v_oldhardware.hardware_type_id, statement_timestamp(),
            v_hostname, v_log, v_oldhardware.mac_address, v_oldhardware.purchase_date, v_oldhardware.serial_number,
            v_stypeicode, v_oldhardware.hardware_deploy_reason_id);
END;
$fn$;
REVOKE ALL ON PROCEDURE osixinfo.osag_hardware__dump_to_hw_history(bigint, bigint) FROM PUBLIC;

-- ------------------------------------------------------------------------------------
-- add_hardware_lifecycle_item (S-HW-002): one lifecycle row + the back-link on
-- mss.hardware. No exception handler.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE osixinfo.osag_hardware_add_hardware_lifecycle_item(
    p_hardware_id mss.hardware.id%TYPE,
    p_hardware_lc_state_id mss.hardware_lifecycle_item.hardware_lc_state_id%TYPE,
    p_hardware_lc_location_id mss.hardware_lifecycle_item.hardware_lc_location_id%TYPE,
    p_creator mss.hardware_lifecycle_item.creator%TYPE)
LANGUAGE plpgsql
AS $fn$
DECLARE
    l_hardware_lifecycle_item_id mss.hardware_lifecycle_item.id%TYPE;
BEGIN
    -- Strictness table site #4: sequence pull.
    SELECT nextval('mss.hardware_lifecycle_item_seq') INTO STRICT l_hardware_lifecycle_item_id;

    -- add hardware lifecycle item
    INSERT INTO mss.hardware_lifecycle_item
    (id, hardware_id, hardware_lc_state_id, hardware_lc_location_id, creator)
    VALUES (l_hardware_lifecycle_item_id, p_hardware_id, p_hardware_lc_state_id, p_hardware_lc_location_id, p_creator);

    -- link hardware to new hardware lifecycle item
    UPDATE mss.hardware
    SET hardware_lifecycle_item_id = l_hardware_lifecycle_item_id
    WHERE hardware.id = p_hardware_id;
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- replace_hardware (S-HW-003, S-HW-011, S-HW-014): replace the hardware ID in the database
-- with the stored replacement hardware id. No exception handler of its own in Oracle; the
-- outer block here is ONLY the "no data found" message-parity shim (same SQLSTATE, Oracle's
-- wording) -- it re-raises, it does not handle.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE osixinfo.osag_hardware_replace_hardware(
    p_host_id mss.host.id%TYPE,
    p_old_hw_id mss.hardware.id%TYPE,
    p_new_hw_id mss.hardware.id%TYPE)
LANGUAGE plpgsql
AS $fn$
DECLARE
    l_hardware_lc_location_id mss.hardware_lifecycle_item.hardware_lc_location_id%TYPE;
BEGIN
    BEGIN
        -- (1) archive first -- every failure in here leaves the database untouched
        CALL osixinfo.osag_hardware__dump_to_hw_history(p_host_id, p_old_hw_id);

        -- (2) set hardware disposal date
        UPDATE mss.hardware
        SET disposal_date = statement_timestamp()
        WHERE hardware.id = p_old_hw_id;

        -- (3) replace the hardware
        UPDATE mss.host
        SET hardware_id = p_new_hw_id,
            replacement_hardware_id = NULL
        WHERE id = p_host_id;

        -- (4) S-HW-014: location 9 (Internal) for a host of service company 6, else 3
        -- (Customer). Strictness table site #5: Oracle's CASE ... FROM dual, always one row.
        l_hardware_lc_location_id := CASE
                                         WHEN EXISTS(SELECT 1 FROM mss.host h
                                                     WHERE h.id = p_host_id AND h.service_company_id = 6)
                                             THEN 9
                                         ELSE 3
                                         END;

        -- (5)/(6) add hardware lifecycle items: 6 = Disposed (old), 4 = Installed (new)
        CALL osixinfo.osag_hardware_add_hardware_lifecycle_item(p_old_hw_id, 6, l_hardware_lc_location_id, NULL);
        CALL osixinfo.osag_hardware_add_hardware_lifecycle_item(p_new_hw_id, 4, l_hardware_lc_location_id, NULL);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            -- "no data found" message-parity shim (XCUT-01 rule 2): STRICT says "query
            -- returned no rows", Oracle callers pin "no data found". Same SQLSTATE P0002, so
            -- check_replaced_hw_for_host's NO_DATA_FOUND arm still catches it (S-HW-013).
            RAISE EXCEPTION 'no data found' USING ERRCODE = 'P0002';
    END;
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- check_replaced_hw_for_host (S-HW-008..010, S-HW-013): hardware replacement procedure,
-- called by the (external) 'submit_heartbeat' when a host reports a MAC address.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE osixinfo.osag_hardware_check_replaced_hw_for_host(
    p_host_id mss.host.id%TYPE,
    p_reported_mac mss.hardware.mac_address%TYPE)
LANGUAGE plpgsql
AS $fn$
DECLARE
    c_prefix CONSTANT varchar := 'check_replaced_hw_for_host: ';
    -- Pitfall 2 boundary: Oracle's '' is NULL; `= NULL` matches nothing -> silent return.
    v_reported_mac mss.hardware.mac_address%TYPE := NULLIF(p_reported_mac, '');
    l_replacement_mac mss.hardware.mac_address%TYPE;
    l_old_hardware_id mss.hardware.id%TYPE;
    l_hostname mss.host.name%TYPE;
    v_event_id numeric;
    l_replacement_id mss.hardware.id%TYPE;
BEGIN
    -- check if replacement_mac matches new mac address (S-HW-008). Strictness table site
    -- #6: STRICT + the procedure-wide NO_DATA_FOUND arm below.
    SELECT new_hardware.mac_address, old_hardware.id, h.name, new_hardware.id
    INTO STRICT l_replacement_mac, l_old_hardware_id, l_hostname, l_replacement_id
    FROM mss.host h
             JOIN mss.hardware new_hardware ON (h.replacement_hardware_id = new_hardware.id)
             JOIN mss.hardware old_hardware ON (h.hardware_id = old_hardware.id)
    WHERE h.id = p_host_id
      AND new_hardware.mac_address = v_reported_mac;

    IF (l_replacement_mac = v_reported_mac) THEN
        CALL osixinfo.osag_hardware_replace_hardware(p_host_id, l_old_hardware_id, l_replacement_id);

        -- generate event HW_CHANGED (S-HW-009): HW_CHANGED_EVENT_TYPE = 10017 ("hardware
        -- installation"), private text = TODO_PRIVATE_HW_MIG (package spec lines 56, 64-68).
        CALL tt.event_interface_newevent_new(v_event_id, 10017, p_host_id,
                                             'First heartbeat received ' || chr(10) || chr(10) ||
                                             'Received first heartbeat from hardware with the MAC address: ' || l_replacement_mac || '. ' ||
                                             'The heartbeat was sent from the host: ' || l_hostname || '. ' ||
                                             'This usually happens when a replacement hardware is plugged in for the first time.', -- public comment
                                             'To Do:' || chr(10)
                                             || ' - Check ticket type. Must be: migration' || chr(10)
                                             || ' - Check that this ticket is a hardware migration tracking ticket.' || chr(10)
                                             || '   If not: check if a matching migration ticket is deferred. Inform TAM.'); -- private comment
    END IF;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        -- nothing to replace (S-HW-008) -- also swallows NO_DATA_FOUND raised inside
        -- replace_hardware -> dump_to_hw_history, exactly as Oracle's procedure-wide arm
        -- does (S-HW-013; no DML has happened at that point).
        RETURN;

    WHEN SQLSTATE 'OS010' THEN
        -- OSAG_EXCEPTIONS.e_abort (S-HW-010). Oracle's plog.err at the raise site ran in an
        -- autonomous transaction and survived; the transactional plog stub's row would be
        -- erased by this handler's subtransaction rollback, so the raise site handed the
        -- line over as the exception's MESSAGE_TEXT and it is emitted here first -- same
        -- two lines, same order as Oracle.
        CALL osag.osag_plog_err(SQLERRM);
        CALL osag.osag_plog_warning(c_prefix || 'skipped host ' || p_host_id);
END;
$fn$;
