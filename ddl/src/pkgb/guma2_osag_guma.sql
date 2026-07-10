--liquibase formatted sql logicalFilePath:pkgb/guma2_osag_guma.sql 
--changeset sys:1 runOnChange:true endDelimiter:/ splitStatements:true
CREATE OR REPLACE PACKAGE BODY GUMA2.OSAG_GUMA IS

-- -----------------------------------------------------------------------------
-- PROCEDURE free_pattern_pos: frees position i_pos in the pattern table. Used
--                             before  inserting a pattern to a specific
--                             position.
-- -----------------------------------------------------------------------------
    PROCEDURE free_pattern_pos(
        i_pos NUMBER
    ) IS
        c_prefix CONSTANT VARCHAR2(32) := 'free_pattern_pos: ';
        l_count  NUMBER;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- check whether the position is occupied
        SELECT count(*) INTO l_count
        FROM pattern
        WHERE position = i_pos;

        -- if it's free, don't do anything
        IF (l_count = 0) THEN
            RETURN;
        END IF;

        UPDATE PATTERN
        SET position = position + 1
        WHERE position >= i_pos;

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(c_prefix||'unexpected error: '||sqlerrm);
            RAISE OSAG_GUMA_STATE.e_abort;

    END free_pattern_pos;

-- -----------------------------------------------------------------------------
-- PROCEDURE pack_pattern_pos: Compacts the pattern position space. It's not
--                             really absolutely necessary to do this, but if
--                             you are obsessed about cleanliness...
-- ----------------------------------------------------------------------------------------
    PROCEDURE pack_pattern_pos
        IS
        c_prefix CONSTANT VARCHAR2(32) := 'pack_pattern_pos: ';
        l_pos    NUMBER := 1;

        CURSOR l_pattern_cur IS
            SELECT position
            FROM pattern
            ORDER BY position ASC
                FOR UPDATE OF position;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        FOR l_pattern_rec IN l_pattern_cur LOOP
                UPDATE pattern
                SET position = l_pos
                WHERE CURRENT OF l_pattern_cur;

                l_pos := l_pos + 1;
            END LOOP;

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(c_prefix||'unexpected error: '||sqlerrm);
            RAISE OSAG_GUMA_STATE.e_abort;

    END pack_pattern_pos;

-- -----------------------------------------------------------------------------
-- PROCEDURE prune_syslog_message: Removes entries from syslog_message which are
--                                 older than age days.
-- ----------------------------------------------------------------------------------------
    PROCEDURE prune_syslog_message(
        age NUMBER
    )
        IS
        c_prefix CONSTANT VARCHAR2(32) := 'prune_syslog_message: ';

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        DELETE FROM guma2.syslog_message
        WHERE log_date < sysdate - age;

        plog.notice(c_prefix||'removed '||SQL%ROWCOUNT||' entries older than '||age||' days from syslog_message');

        COMMIT;

    EXCEPTION
        WHEN OTHERS THEN
            plog.err(c_prefix||'unexpected error: '||sqlerrm);

    END prune_syslog_message;


-- -----------------------------------------------------------------------------
-- PRODEDURE dump_to_hw_history: dumps the hardware with the given id to the
--                               mss.hardware_history table.
-- this is a PRIVATE procedure and called from replace_hardware and check_and_replace_hardware.
--------------------------------------------------------------------------------
    PROCEDURE dump_to_hw_history(
        p_host_id mss.host.id%TYPE,        -- id of the host where the hw belonged to
        p_old_hardware_id mss.hardware.id%TYPE -- id of the hw to dump
    )
        IS
        c_prefix CONSTANT VARCHAR2(32) := 'dump_to_hw_history: ';

        v_oldhardware  mss.hardware%ROWTYPE;
        v_hostname mss.host.name%TYPE;
        v_compshort stop.company.short%TYPE;
        v_stypeicode mss.service_type.internal_code%TYPE;
        v_log mss.hardware_history.log%TYPE;

    BEGIN

        -- get the old hardware record
        SELECT * INTO v_oldhardware
        FROM mss.hardware WHERE id = p_old_hardware_id;

        -- check data sanity
        IF v_oldhardware.hardware_disposal_contact_id IS NULL
        THEN
            plog.err(c_prefix||'hardware_disposal_contact_id is NULL while replacing hw for host_id: '||p_host_id||' hw_id: '||p_old_hardware_id);
            RAISE OSAG_GUMA_STATE.e_abort;
        END IF;
        IF v_oldhardware.hardware_disposal_reason_id IS NULL
        THEN
            plog.err(c_prefix||'hardware_disposal_reason_id is NULL while replacing hw for host_id: '||p_host_id||' hw_id: '||p_old_hardware_id);
            RAISE OSAG_GUMA_STATE.e_abort;
        END IF;

        -- get log information
        SELECT 'hardware_type='||mss.hardware_type.short||';disposal_contact='||stop.contact.email||';disposal_reason='
                   ||mss.hardware_disposal_reason.name
        INTO v_log
        FROM mss.hardware
                 INNER JOIN mss.hardware_type ON (mss.hardware.hardware_type_id = mss.hardware_type.id)
                 INNER JOIN mss.hardware_disposal_reason ON (mss.hardware.hardware_disposal_reason_id = mss.hardware_disposal_reason.id)
                 INNER JOIN stop.contact ON (mss.hardware.hardware_disposal_contact_id = stop.contact.id)
        WHERE mss.hardware.id = p_old_hardware_id;

        -- get host, service and company
        SELECT mss.host.name, stop.company.short, mss.service_type.internal_code
        INTO v_hostname, v_compshort, v_stypeicode
        FROM mss.host
                 INNER JOIN stop.company ON (mss.host.service_company_id = stop.company.id)
                 INNER JOIN mss.host2service ON (mss.host.id = mss.host2service.host_id)
                 INNER JOIN mss.service ON (mss.host2service.service_id = mss.service.id)
                 INNER JOIN mss.service_type ON (mss.service.service_type_id = mss.service_type.id)
        WHERE mss.host.id = p_host_id;

        -- plog.notice('old hw: mac: '||oldhardware.mac_address||' barcode: '||oldhardware.barcode);

        -- insert record to mss.hardware_history
        INSERT INTO mss.hardware_history (id, barcode, company_short, disposal_date, hardware_disposal_comments,
                                          hardware_disposal_contact_id, hardware_disposal_reason_id, hardware_type_id, history_date,
                                          host_name, log, mac_address, purchase_date, serial_number, service_type_internal_code, hardware_deploy_reason_id)
        VALUES (mss.hardwarehistory_seq.nextval, v_oldhardware.barcode,  v_compshort, NVL(v_oldhardware.disposal_date, SYSDATE),
                v_oldhardware.hardware_disposal_comments, v_oldhardware.hardware_disposal_contact_id,
                v_oldhardware.hardware_disposal_reason_id, v_oldhardware.hardware_type_id, SYSDATE,
                v_hostname, v_log, v_oldhardware.mac_address, v_oldhardware.purchase_date, v_oldhardware.serial_number,
                v_stypeicode, v_oldhardware.hardware_deploy_reason_id);


    END dump_to_hw_history;

-- -----------------------------------------------------------------------------
-- PROCEDURE add_hardware_lifecycle_item
--
-- add a new hardware lifecycle item to a hardware
-- IN: hardware_id, hardware_lc_state_id, hardware_lc_location_id, creator
-- -----------------------------------------------------------------------------
    PROCEDURE add_hardware_lifecycle_item (
        p_hardware_id mss.hardware.id%TYPE,
        p_hardware_lc_state_id mss.hardware_lifecycle_item.hardware_lc_state_id%TYPE,
        p_hardware_lc_location_id mss.hardware_lifecycle_item.hardware_lc_location_id%TYPE,
        p_creator mss.hardware_lifecycle_item.creator%TYPE)
        IS
        l_hardware_lifecycle_item_id  mss.hardware_lifecycle_item.id%TYPE;
    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        SELECT mss.hardware_lifecycle_item_seq.nextval INTO l_hardware_lifecycle_item_id
        FROM dual;

        -- add hardware lifecycle item
        INSERT INTO mss.hardware_lifecycle_item
        (id, hardware_id, hardware_lc_state_id, hardware_lc_location_id, creator)
        VALUES(l_hardware_lifecycle_item_id, p_hardware_id, p_hardware_lc_state_id, p_hardware_lc_location_id, p_creator);

        -- link hardware to new hardware lifecycle item
        UPDATE mss.hardware
        SET hardware_lifecycle_item_id = l_hardware_lifecycle_item_id
        WHERE hardware.id = p_hardware_id;

    END add_hardware_lifecycle_item;

-- -----------------------------------------------------------------------------
-- PROCEDURE replace_hardware
--
-- replace the hardware ID in the database with the stored replacement
-- hardware id.
-- IN: host_id, old_hw_id, new_hw_id
-- -----------------------------------------------------------------------------
    PROCEDURE replace_hardware (
        p_host_id   mss.host.id%TYPE,
        p_old_hw_id mss.hardware.id%TYPE,
        p_new_hw_id mss.hardware.id%TYPE)
        IS
        l_hardware_lc_location_id mss.hardware_lifecycle_item.hardware_lc_location_id%TYPE;
    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        dump_to_hw_history(p_host_id, p_old_hw_id);

        -- set hardware disposal date
        UPDATE mss.hardware
        SET disposal_date = SYSDATE
        WHERE mss.hardware.id = p_old_hw_id;

        -- replace the hardware
        UPDATE mss.host
        SET hardware_id = p_new_hw_id,
            replacement_hardware_id = NULL
        WHERE id = p_host_id;

        SELECT CASE
                   WHEN EXISTS(
                           SELECT *
                           FROM mss.host h
                           WHERE h.id = p_host_id AND h.service_company_id = 6
                       )
                       THEN 9
                   ELSE 3
                   END INTO l_hardware_lc_location_id
        FROM dual;

        -- add hardware lifecycle item
        add_hardware_lifecycle_item(p_old_hw_id, 6, l_hardware_lc_location_id, NULL);
        add_hardware_lifecycle_item(p_new_hw_id, 4, l_hardware_lc_location_id, NULL);

    END replace_hardware;

-- -----------------------------------------------------------------------------
-- PROCEDURE check_replaced_hardware_for_host: hardware replacement procedure
--
-- NOTE:    This procedure is called by the 'submit_heartbeat' procedure.
--          p_reported_mac must match the mac address of the replacement hw.
--
-- p_host_id  : is the ID of the host which has a new mac address
-- p_reported_mac : the mac address which is reported by heartbeat.mac_address
-- -----------------------------------------------------------------------------
    PROCEDURE check_replaced_hw_for_host(
        p_host_id      mss.host.id%TYPE,
        p_reported_mac mss.hardware.mac_address%TYPE
    )
        IS
        c_prefix CONSTANT VARCHAR2(32) := 'check_replaced_hw_for_host: ';
        l_replacement_mac mss.hardware.mac_address%TYPE;
        l_old_hardware_id mss.hardware.id%TYPE;
        l_hostname        mss.host.name%TYPE;
        v_event_id        NUMBER;
        l_replacement_id  mss.hardware.id%TYPE;

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        -- check if replacement_mac matches new mac address
        SELECT new_hardware.mac_address,old_hardware.id,mss.host.name,new_hardware.id INTO l_replacement_mac,l_old_hardware_id,l_hostname, l_replacement_id
        FROM mss.host
                 JOIN mss.hardware new_hardware ON (mss.host.replacement_hardware_id = new_hardware.id)
                 JOIN mss.hardware old_hardware ON (mss.host.hardware_id = old_hardware.id)
        WHERE mss.host.id = p_host_id
          AND new_hardware.mac_address = p_reported_mac;

        IF ( l_replacement_mac = p_reported_mac ) THEN
            replace_hardware(p_host_id, l_old_hardware_id, l_replacement_id);

            -- generate event HW_CHANGED
            tt.event_interface.newevent_new(v_event_id,HW_CHANGED_EVENT_TYPE,p_host_id,
                                            'First heartbeat received '||CHR(10)||CHR(10)||
                                            'Received first heartbeat from hardware with the MAC address: '||l_replacement_mac||'. '||
                                            'The heartbeat was sent from the host: '||l_hostname||'. '||
                                            'This usually happens when a replacement hardware is plugged in for the first time.', -- public comment
                                            TODO_PRIVATE_HW_MIG); -- private comment
        END IF;

    EXCEPTION
        WHEN no_data_found THEN
            return; -- nothing to replace

        WHEN OSAG_GUMA_STATE.e_abort THEN
            plog.warning(c_prefix||'skipped host '||p_host_id);

    END check_replaced_hw_for_host;

--------------------------------------------------------------------------------
-- log_version: write an entry into the MC audit trial to
-- document the changed version string.
--------------------------------------------------------------------------------
    PROCEDURE log_version(p_host_id     number,
                          p_old_version varchar2,
                          p_new_version varchar2,
                          p_build       varchar2)
        IS
        c_prefix         CONSTANT VARCHAR2(32) := 'log_version: ';
        v_application    mcaudit.application.id%TYPE := 1;  -- "GUMA"
        v_component      mcaudit.component.id%TYPE   := 39; -- "OS Version"
        v_record_type    mcaudit.record_type.id%TYPE := 168;-- "OS version changed"
        v_severity       NUMBER                      := 10; -- "Info"
        v_transaction_id mcaudit.record.transaction_id%TYPE;
        v_details        mcaudit.record.details%TYPE;
        v_message        mcaudit.record.message%TYPE := 'OS version changed to '
            ||p_new_version||' ('||p_build||')';

        v_company        stop.company.id%TYPE;
        v_object_id      mcaudit.record.object_id%TYPE := p_host_id;

        c_contact_id     mcaudit.record.contact_id%TYPE := NULL;
        c_table_name     VARCHAR2(32) := 'MSS.HOST';

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        v_details := '<details>'
            || '<OSVERSION'
            || ' OLDVERSION="' || p_old_version || '"'
            || ' NEWVERSION="' || p_new_version || '"'
            || ' BUILD="' || p_build || '"'
            || '/>'
            || '</details>';

        SELECT service_company_id INTO v_company
        FROM mss.host
        WHERE id = p_host_id;

        OSAG_AUDIT.add_record_raw(v_application,
                                  v_component,
                                  v_record_type,
                                  v_severity,
                                  v_transaction_id,
                                  v_message,
                                  v_details,
                                  v_company,
                                  c_contact_id,
                                  c_table_name,
                                  v_object_id);
    EXCEPTION
        WHEN others THEN
            plog.info(c_prefix||'unexpected error while processing host '||p_host_id||': '||sqlerrm);

    END log_version;


-- -----------------------------------------------------------------------------
-- clean_suppressed_signature: remove old signature suppressions
-- -----------------------------------------------------------------------------
    PROCEDURE clean_suppressed_signature IS

        CURSOR guma_old_suppressions IS
            SELECT so.id, so.host_id, so.signature_id, so.date_start, so.date_end, so.ticket_id,
                   s.short_name, h.name, h.service_company_id
            FROM guma2.suppressed_signature so, mss.host h, guma2.signature s
            WHERE so.date_end < systimestamp and h.id = so.host_id and s.id = so.signature_id
                FOR UPDATE of so.id;

        c_prefix         CONSTANT VARCHAR2(32) := 'clean_suppressed_signature: ';
        c_application    mcaudit.application.id%TYPE := 8;  -- "Signature Suppression Clean up Job"
        c_component      mcaudit.component.id%TYPE   := 24; -- "GUMA Management"
        c_record_type    mcaudit.record_type.id%TYPE := 195;-- "Signature Suppression deleted"
        c_severity       NUMBER                      := 10; -- "Info"

        c_contact_id     mcaudit.record.contact_id%TYPE := NULL;
        c_transaction_id mcaudit.record.transaction_id%TYPE := NULL;
        c_table_name     VARCHAR2(32) := 'GUMA2.SUPPRESSED_SIGNATURE';

        v_details        mcaudit.record.details%TYPE;
        v_message        mcaudit.record.message%TYPE := '';

    BEGIN
        plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT);
        FOR sig IN guma_old_suppressions LOOP

                v_details := '<details>'
                    || '<GUMA2.SUPPRESSED_SIGNATURE'
                    || ' HOST_ID="' || sig.host_id || '"'
                    || ' SIGNATURE_ID="' || sig.signature_id || '"'
                    || ' START_DATE="' || TO_CHAR(sig.date_start, 'DD.MM.YYYY HH24:MI:SS TZH:TZM') || '"'
                    || ' END_DATE="' || TO_CHAR(sig.date_end, 'DD.MM.YYYY HH24:MI:SS TZH:TZM') || '"'
                    || ' TICKET_ID="' || sig.ticket_id || '"'
                    || ' _action="deleted" '
                    || '/>'
                    || '</details>';

                v_message := 'Deleted signature suppression for signature '''
                    || sig.short_name
                    || ''' and host ''' || sig.name || '''.';

                OSAG_AUDIT.add_record_raw(c_application,
                                          c_component,
                                          c_record_type,
                                          c_severity,
                                          c_transaction_id,
                                          v_message,
                                          v_details,
                                          sig.service_company_id,
                                          c_contact_id,
                                          c_table_name,
                                          sig.id);

                DELETE FROM GUMA2.SUPPRESSED_SIGNATURE WHERE ID = sig.id;

            END LOOP;


    END clean_suppressed_signature;

END OSAG_GUMA;
/
