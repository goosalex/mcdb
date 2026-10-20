-- migration/test/pgtap/osixinfo__osag_hardware__spec.sql
--
-- pgTAP verification for migration/spec/osixinfo.osag_hardware.md. RED by construction:
-- none of osixinfo.osag_hardware_* (nor the private osixinfo.osag_hardware__dump_to_hw_history)
-- exists yet. Every assertion's description starts with the spec clause ID it verifies
-- (HARN-05, trace_lint.py). Source of expected values is the SPEC only -- never
-- pg_migration/output/, never a PL/pgSQL translation. No corrected behaviour in this
-- package: every assertion is Oracle-faithful.
--
-- Fixture-initial values are always chosen to DIFFER from the post-CALL expected value
-- where a clause claims a change (hosts start on their OLD hardware with a replacement
-- registered), and every "did NOT happen" assertion sits next to a lives_ok/throws_ok
-- proving the CALL actually ran (PITFALLS.md's asymmetric-coverage tell). Plan-owned
-- rows use the 931xxx id range; stop.company 6 ("internal", S-HW-014) is inserted
-- ON CONFLICT DO NOTHING because its meaning is a literal in the Oracle body.

BEGIN;
SET CONSTRAINTS ALL DEFERRED;
SELECT plan(78);

-------------------------------------------------------------------------------
-- S-HW-001 / S-HW-012: three public PROCEDUREs; one private helper under the __
-- convention with EXECUTE revoked from PUBLIC; NO object at all for OSAG_EXCEPTIONS.
-------------------------------------------------------------------------------

SELECT ok(
    EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'osixinfo' AND p.proname = 'osag_hardware_check_replaced_hw_for_host' AND p.prokind = 'p' AND p.pronargs = 2),
    'S-HW-001: osixinfo.osag_hardware_check_replaced_hw_for_host exists as a PostgreSQL PROCEDURE (prokind=p) with two arguments'
);
SELECT ok(
    EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'osixinfo' AND p.proname = 'osag_hardware_add_hardware_lifecycle_item' AND p.prokind = 'p' AND p.pronargs = 4),
    'S-HW-001: osixinfo.osag_hardware_add_hardware_lifecycle_item exists as a PostgreSQL PROCEDURE (prokind=p) with four arguments'
);
SELECT ok(
    EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'osixinfo' AND p.proname = 'osag_hardware_replace_hardware' AND p.prokind = 'p' AND p.pronargs = 3),
    'S-HW-001: osixinfo.osag_hardware_replace_hardware exists as a PostgreSQL PROCEDURE (prokind=p) with three arguments'
);
SELECT ok(
    EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'osixinfo' AND p.proname = 'osag_hardware__dump_to_hw_history' AND p.prokind = 'p'),
    'S-HW-001: the body-only helper exists as the private PROCEDURE osixinfo.osag_hardware__dump_to_hw_history'
);
SELECT ok(
    NOT EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace,
             LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
        WHERE n.nspname = 'osixinfo' AND p.proname = 'osag_hardware__dump_to_hw_history'
          AND a.grantee = 0 AND a.privilege_type = 'EXECUTE'),
    'S-HW-001: EXECUTE on osixinfo.osag_hardware__dump_to_hw_history is revoked from PUBLIC'
);
SELECT is(
    (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'osixinfo' AND p.proname LIKE 'osag\_hardware\_%' AND p.proname NOT LIKE 'osag\_hardware\_\_%'),
    3::bigint,
    'S-HW-001: exactly three PUBLIC osag_hardware_* objects exist -- the two spec constants get no object, the helper is not leaked'
);
SELECT is(
    (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'osixinfo' AND p.proname LIKE 'osag\_exceptions%'),
    0::bigint,
    'S-HW-012: OSIXINFO.OSAG_EXCEPTIONS has no PostgreSQL object -- its exceptions are SQLSTATEs, not routines'
);

-------------------------------------------------------------------------------
-- Fixtures. Reference rows reused from the template's masterdata: mss.operating_system 2,
-- mss.service_type 6 (internal_code sitevpn), mss.service_level 1,
-- mss.hardware_lc_state 4/6, mss.hardware_lc_location 3/9, mss.hardware_disposal_reason
-- 1 ("OS HW failure") / 2 ("OS HW end of life"), mss.hardware_deploy_reason 2,
-- tt.event_type 10017. stop.company, stop.contact, mss.hardware_type, mss.hardware,
-- mss.host, mss.service carry no masterdata -- plan-owned rows below.
-------------------------------------------------------------------------------

INSERT INTO stop.company (id, name, short) VALUES (931001, 'P0602 HW Customer', 'p0602hw');
INSERT INTO stop.company (id, name, short) VALUES (6, 'P0602 Internal (company 6)', 'p0602os') ON CONFLICT (id) DO NOTHING;
INSERT INTO stop.contact (id, lastname, short, company_id, email) VALUES (931010, 'P0602 Disposer', 'p0602disp', 931001, 'disposal@p0602.example');
INSERT INTO stop.contact (id, lastname, short, company_id, email) VALUES (931011, 'P0602 NoMail', 'p0602nml', 931001, NULL);
INSERT INTO mss.hardware_type (id, short, name) VALUES (931020, 'p0602ht', 'P0602 hardware type');

INSERT INTO mss.service (id, service_type_id, company_id, service_level_id, name) VALUES (931030, 6, 931001, 1, 'p0602-hw-svc');
INSERT INTO mss.service (id, service_type_id, company_id, service_level_id, name) VALUES (931031, 6, 931001, 1, 'p0602-hw-svc-2');
INSERT INTO mss.service (id, service_type_id, company_id, service_level_id, name) VALUES (931032, 6, 6, 1, 'p0602-hw-svc-int');

-- Hardware pairs (old, new) per host. Old hardware: disposal contact/reason set unless
-- the scenario needs them NULL; purchase_date set unless the scenario needs it NULL.
INSERT INTO mss.hardware (id, hardware_type_id, barcode, serial_number, mac_address, purchase_date, hardware_disposal_reason_id, hardware_disposal_comments, hardware_disposal_contact_id, hardware_deploy_reason_id)
    VALUES (931201, 931020, 'P0602-BC-01', 'P0602-SN-01', 'AA:BB:CC:00:00:01', '2019-05-05', 2, 'p0602 old box', 931010, 2);          -- H1 old
INSERT INTO mss.hardware (id, hardware_type_id, mac_address, purchase_date)
    VALUES (931202, 931020, 'AA:BB:CC:00:00:02', '2024-01-01');                                                                      -- H1 new
INSERT INTO mss.hardware (id, hardware_type_id, mac_address, purchase_date, hardware_disposal_reason_id, hardware_disposal_contact_id)
    VALUES (931211, 931020, 'AA:BB:CC:00:00:11', '2019-05-05', 2, NULL);                                                             -- H2 old: NO disposal contact
INSERT INTO mss.hardware (id, hardware_type_id, mac_address, purchase_date)
    VALUES (931212, 931020, 'AA:BB:CC:00:00:12', '2024-01-01');                                                                      -- H2 new
INSERT INTO mss.hardware (id, hardware_type_id, mac_address, purchase_date, hardware_disposal_reason_id, hardware_disposal_contact_id)
    VALUES (931221, 931020, 'AA:BB:CC:00:00:21', '2019-05-05', 1, 931010);                                                           -- H3 old (internal host)
INSERT INTO mss.hardware (id, hardware_type_id, mac_address, purchase_date)
    VALUES (931222, 931020, 'AA:BB:CC:00:00:22', '2024-01-01');                                                                      -- H3 new
INSERT INTO mss.hardware (id, hardware_type_id, mac_address, purchase_date, hardware_disposal_reason_id, hardware_disposal_contact_id)
    VALUES (931231, 931020, 'AA:BB:CC:00:00:31', '2019-05-05', NULL, 931010);                                                        -- H4 old: NO disposal reason
INSERT INTO mss.hardware (id, hardware_type_id, mac_address, purchase_date)
    VALUES (931232, 931020, 'AA:BB:CC:00:00:32', '2024-01-01');                                                                      -- H4 new
INSERT INTO mss.hardware (id, hardware_type_id, mac_address, purchase_date, hardware_disposal_reason_id, hardware_disposal_contact_id)
    VALUES (931241, 931020, 'AA:BB:CC:00:00:41', '2019-05-05', 2, 931010);                                                           -- H5 old (two-service host)
INSERT INTO mss.hardware (id, hardware_type_id, mac_address, purchase_date)
    VALUES (931242, 931020, 'AA:BB:CC:00:00:42', '2024-01-01');                                                                      -- H5 new
INSERT INTO mss.hardware (id, hardware_type_id, mac_address, purchase_date, hardware_disposal_reason_id, hardware_disposal_contact_id)
    VALUES (931251, 931020, 'AA:BB:CC:00:00:51', '2019-05-05', 2, 931010);                                                           -- H6 old (host without service)
INSERT INTO mss.hardware (id, hardware_type_id, mac_address, purchase_date)
    VALUES (931252, 931020, 'AA:BB:CC:00:00:52', '2024-01-01');                                                                      -- H6 new
INSERT INTO mss.hardware (id, hardware_type_id, mac_address, purchase_date, hardware_disposal_reason_id, hardware_disposal_contact_id)
    VALUES (931261, 931020, 'AA:BB:CC:00:00:61', NULL, 2, 931010);                                                                   -- H7 old: NO purchase date
INSERT INTO mss.hardware (id, hardware_type_id, mac_address, purchase_date)
    VALUES (931262, 931020, 'AA:BB:CC:00:00:62', '2024-01-01');                                                                      -- H7 new
INSERT INTO mss.hardware (id, hardware_type_id, mac_address, purchase_date, disposal_date, hardware_disposal_reason_id, hardware_disposal_contact_id)
    VALUES (931271, 931020, 'AA:BB:CC:00:00:71', '2019-05-05', '2020-01-01 00:00:00', 1, 931011);                                    -- H8 old: contact without e-mail, disposal date already set
INSERT INTO mss.hardware (id, hardware_type_id, mac_address, purchase_date)
    VALUES (931272, 931020, 'AA:BB:CC:00:00:72', '2024-01-01');                                                                      -- H8 new
INSERT INTO mss.hardware (id, hardware_type_id, mac_address, purchase_date)
    VALUES (931290, 931020, 'AA:BB:CC:00:00:90', '2024-01-01');                                                                      -- standalone (lifecycle tests)

INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author, active, hardware_id, replacement_hardware_id) VALUES (931100, 'p0602-hw-host1', 2, 931001, 'p0602', 1, 931201, 931202);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author, active, hardware_id, replacement_hardware_id) VALUES (931110, 'p0602-hw-host2', 2, 931001, 'p0602', 1, 931211, 931212);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author, active, hardware_id, replacement_hardware_id) VALUES (931120, 'p0602-hw-host3', 2, 6,      'p0602', 1, 931221, 931222);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author, active, hardware_id, replacement_hardware_id) VALUES (931130, 'p0602-hw-host4', 2, 931001, 'p0602', 1, 931231, 931232);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author, active, hardware_id, replacement_hardware_id) VALUES (931140, 'p0602-hw-host5', 2, 931001, 'p0602', 1, 931241, 931242);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author, active, hardware_id, replacement_hardware_id) VALUES (931150, 'p0602-hw-host6', 2, 931001, 'p0602', 1, 931251, 931252);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author, active, hardware_id, replacement_hardware_id) VALUES (931160, 'p0602-hw-host7', 2, 931001, 'p0602', 1, 931261, 931262);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author, active, hardware_id, replacement_hardware_id) VALUES (931170, 'p0602-hw-host8', 2, 931001, 'p0602', 1, 931271, 931272);
INSERT INTO mss.host2service (host_id, service_id) VALUES (931100, 931030);
INSERT INTO mss.host2service (host_id, service_id) VALUES (931110, 931030);
INSERT INTO mss.host2service (host_id, service_id) VALUES (931120, 931032);
INSERT INTO mss.host2service (host_id, service_id) VALUES (931130, 931030);
INSERT INTO mss.host2service (host_id, service_id) VALUES (931140, 931030);
INSERT INTO mss.host2service (host_id, service_id) VALUES (931140, 931031);   -- H5: TWO services
-- H6 (931150) deliberately has NO host2service row.
INSERT INTO mss.host2service (host_id, service_id) VALUES (931160, 931030);
INSERT INTO mss.host2service (host_id, service_id) VALUES (931170, 931030);

-------------------------------------------------------------------------------
-- S-HW-002: add_hardware_lifecycle_item on a standalone hardware row.
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL osixinfo.osag_hardware_add_hardware_lifecycle_item(931290, 1, 1, 931010)$$,
    'S-HW-002: add_hardware_lifecycle_item succeeds (state 1 Registered, location 1 Stock, creator contact)'
);
SELECT is(
    (SELECT count(*) FROM mss.hardware_lifecycle_item WHERE hardware_id = 931290),
    1::bigint,
    'S-HW-002: exactly one lifecycle item exists for the hardware after the first call (fixture started with none)'
);
SELECT ok(
    EXISTS (SELECT 1 FROM mss.hardware_lifecycle_item i
            WHERE i.hardware_id = 931290 AND i.hardware_lc_state_id = 1 AND i.hardware_lc_location_id = 1 AND i.creator = 931010
              AND i.created IS NOT NULL AND i.activated IS NOT NULL
              AND i.hardware_lc_transit_state_id IS NULL AND i.hardware_lc_transit_info_id IS NULL),
    'S-HW-002: the lifecycle row carries the four supplied values, defaulted created/activated timestamps and NULL transit columns'
);
SELECT is(
    (SELECT h.hardware_lifecycle_item_id FROM mss.hardware h WHERE h.id = 931290),
    (SELECT i.id FROM mss.hardware_lifecycle_item i WHERE i.hardware_id = 931290),
    'S-HW-002: mss.hardware.hardware_lifecycle_item_id points at the new lifecycle item (fixture started NULL)'
);
SELECT lives_ok(
    $$CALL osixinfo.osag_hardware_add_hardware_lifecycle_item(931290, 3, 1, NULL)$$,
    'S-HW-002: a second call (state 3 Staged, NULL creator) succeeds'
);
SELECT is(
    (SELECT count(*) FROM mss.hardware_lifecycle_item WHERE hardware_id = 931290),
    2::bigint,
    'S-HW-002: the second call adds a second lifecycle row (sequence-driven ids, nothing replaced)'
);
SELECT is(
    (SELECT i.hardware_lc_state_id FROM mss.hardware_lifecycle_item i JOIN mss.hardware h ON h.hardware_lifecycle_item_id = i.id WHERE h.id = 931290),
    3::bigint,
    'S-HW-002: the hardware back-link moves to the NEWEST lifecycle item (state 3)'
);
SELECT ok(
    (SELECT max(i.id) > min(i.id) FROM mss.hardware_lifecycle_item i WHERE i.hardware_id = 931290),
    'S-HW-002: lifecycle item ids come from mss.hardware_lifecycle_item_seq (strictly increasing)'
);

-------------------------------------------------------------------------------
-- S-HW-008: check_replaced_hw_for_host with a NON-matching MAC, a NULL MAC and an
-- empty-string MAC on host H1 -> silent "nothing to replace": no change, no log, no event.
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL osixinfo.osag_hardware_check_replaced_hw_for_host(931100, 'AA:BB:CC:00:00:99')$$,
    'S-HW-008: check_replaced_hw_for_host does not raise for a MAC that is not the replacement''s'
);
SELECT lives_ok(
    $$CALL osixinfo.osag_hardware_check_replaced_hw_for_host(931100, NULL)$$,
    'S-HW-008: check_replaced_hw_for_host does not raise for a NULL MAC'
);
SELECT lives_ok(
    $$CALL osixinfo.osag_hardware_check_replaced_hw_for_host(931100, '')$$,
    'S-HW-008: check_replaced_hw_for_host does not raise for an empty-string MAC (treated like NULL, Pitfall 2 boundary)'
);
SELECT lives_ok(
    $$CALL osixinfo.osag_hardware_check_replaced_hw_for_host(931999999, 'AA:BB:CC:00:00:02')$$,
    'S-HW-008: check_replaced_hw_for_host does not raise for a nonexistent host'
);
SELECT ok(
    (SELECT h.hardware_id = 931201 AND h.replacement_hardware_id = 931202 FROM mss.host h WHERE h.id = 931100),
    'S-HW-008: after the four non-matching calls host H1 still points at its OLD hardware with the replacement still registered'
);
SELECT is(
    (SELECT count(*) FROM mss.hardware_history WHERE host_name = 'p0602-hw-host1'),
    0::bigint,
    'S-HW-008: no history row was written for a non-matching MAC'
);
SELECT is(
    (SELECT count(*) FROM osag.plog_stub_log WHERE message LIKE '%931100%'),
    0::bigint,
    'S-HW-008: a non-matching MAC produces NO log line at all (silent NO_DATA_FOUND return)'
);
SELECT is(
    (SELECT count(*) FROM tt.event WHERE host_id = 931100),
    0::bigint,
    'S-HW-008: a non-matching MAC raises NO event'
);

-------------------------------------------------------------------------------
-- S-HW-009 / S-HW-003 / S-HW-005 / S-HW-007 / S-HW-014: the MAC matches on H1 -> full
-- replacement + 10017 event on a new ticket.
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL osixinfo.osag_hardware_check_replaced_hw_for_host(931100, 'AA:BB:CC:00:00:02')$$,
    'S-HW-009: check_replaced_hw_for_host succeeds when the reported MAC equals the replacement hardware''s MAC'
);
SELECT ok(
    (SELECT h.hardware_id = 931202 AND h.replacement_hardware_id IS NULL FROM mss.host h WHERE h.id = 931100),
    'S-HW-003: the host now points at the NEW hardware and its replacement_hardware_id is cleared (fixture started old/registered)'
);
SELECT ok(
    (SELECT disposal_date IS NOT NULL AND disposal_date >= now()::timestamp - interval '1 minute' FROM mss.hardware WHERE id = 931201),
    'S-HW-003: the old hardware''s disposal_date is stamped with the current time (fixture started NULL)'
);
SELECT is(
    (SELECT count(*) FROM mss.hardware_history WHERE host_name = 'p0602-hw-host1'),
    1::bigint,
    'S-HW-007: exactly one mss.hardware_history row was written for the host'
);
SELECT ok(
    EXISTS (SELECT 1 FROM mss.hardware_history hh
            WHERE hh.host_name = 'p0602-hw-host1' AND hh.company_short = 'p0602hw' AND hh.service_type_internal_code = 'sitevpn'
              AND hh.barcode = 'P0602-BC-01' AND hh.serial_number = 'P0602-SN-01' AND hh.mac_address = 'AA:BB:CC:00:00:01'
              AND hh.purchase_date = '2019-05-05'::timestamp AND hh.hardware_disposal_comments = 'p0602 old box'
              AND hh.hardware_disposal_contact_id = 931010 AND hh.hardware_disposal_reason_id = 2
              AND hh.hardware_type_id = 931020 AND hh.hardware_deploy_reason_id = 2),
    'S-HW-007: the history row copies barcode, serial, MAC, purchase date, disposal comments/contact/reason, type and deploy reason from the old hardware, plus host name, company short and service-type internal code'
);
SELECT is(
    (SELECT hh.log FROM mss.hardware_history hh WHERE hh.host_name = 'p0602-hw-host1'),
    'hardware_type=p0602ht;disposal_contact=disposal@p0602.example;disposal_reason=OS HW end of life'::varchar,
    'S-HW-005: the log text is hardware_type=<short>;disposal_contact=<email>;disposal_reason=<name>'
);
SELECT ok(
    (SELECT hh.disposal_date >= now()::timestamp - interval '1 minute' AND hh.history_date >= now()::timestamp - interval '1 minute'
     FROM mss.hardware_history hh WHERE hh.host_name = 'p0602-hw-host1'),
    'S-HW-007: with no prior disposal_date on the hardware, history.disposal_date = SYSDATE (NVL fallback) and history_date = SYSDATE'
);
SELECT ok(
    EXISTS (SELECT 1 FROM mss.hardware_lifecycle_item i WHERE i.hardware_id = 931201 AND i.hardware_lc_state_id = 6 AND i.hardware_lc_location_id = 3 AND i.creator IS NULL),
    'S-HW-003: the OLD hardware received a lifecycle item state 6 (Disposed), location 3 (Customer), NULL creator'
);
SELECT ok(
    EXISTS (SELECT 1 FROM mss.hardware_lifecycle_item i WHERE i.hardware_id = 931202 AND i.hardware_lc_state_id = 4 AND i.hardware_lc_location_id = 3 AND i.creator IS NULL),
    'S-HW-003: the NEW hardware received a lifecycle item state 4 (Installed), location 3 (Customer), NULL creator'
);
SELECT ok(
    (SELECT h1.hardware_lifecycle_item_id = i1.id AND h2.hardware_lifecycle_item_id = i2.id
     FROM mss.hardware h1, mss.hardware h2, mss.hardware_lifecycle_item i1, mss.hardware_lifecycle_item i2
     WHERE h1.id = 931201 AND h2.id = 931202 AND i1.hardware_id = 931201 AND i2.hardware_id = 931202),
    'S-HW-003: both hardware rows are linked to their new lifecycle item'
);
SELECT is(
    (SELECT count(*) FROM mss.hardware_lifecycle_item WHERE hardware_id IN (931201, 931202)),
    2::bigint,
    'S-HW-003: exactly two lifecycle items were added by the replacement'
);
SELECT is(
    (SELECT count(*) FROM tt.event WHERE host_id = 931100 AND type_id = 10017 AND public_event = 1),
    1::bigint,
    'S-HW-009: exactly one public 10017 (hardware installation) event was raised for the host'
);
SELECT is(
    (SELECT details_public FROM tt.event WHERE host_id = 931100 AND type_id = 10017),
    ('First heartbeat received ' || chr(10) || chr(10)
     || 'Received first heartbeat from hardware with the MAC address: AA:BB:CC:00:00:02. '
     || 'The heartbeat was sent from the host: p0602-hw-host1. '
     || 'This usually happens when a replacement hardware is plugged in for the first time.')::text,
    'S-HW-009: the public text is Oracle-verbatim (trailing space after "received", replacement MAC, host name)'
);
SELECT is(
    (SELECT details_private FROM tt.event WHERE host_id = 931100 AND type_id = 10017),
    ('To Do:' || chr(10)
     || ' - Check ticket type. Must be: migration' || chr(10)
     || ' - Check that this ticket is a hardware migration tracking ticket.' || chr(10)
     || '   If not: check if a matching migration ticket is deferred. Inform TAM.')::text,
    'S-HW-009: the private text is the TODO_PRIVATE_HW_MIG constant, inlined verbatim'
);
SELECT is(
    (SELECT count(*) FROM tt.ticket t WHERE t.host_id = 931100 AND t.type_id = 1 AND t.subject = 'hardware installation'
       AND EXISTS (SELECT 1 FROM tt.event e WHERE e.ticket_id = t.id AND e.type_id = 10017)),
    1::bigint,
    'S-HW-009: newevent_new opened a new trouble ticket (type 1, subject "hardware installation") for the event -- no migration/installation ticket existed to append to'
);
SELECT is(
    (SELECT count(*) FROM osag.plog_stub_log WHERE message LIKE '%931100%' AND levelname IN ('ERR', 'WARNING')),
    0::bigint,
    'S-HW-009: a successful replacement logs no ERR/WARNING line of this package'
);

-------------------------------------------------------------------------------
-- S-HW-010 / S-HW-004: H2's old hardware has NO disposal contact -> e_abort inside
-- dump_to_hw_history -> plog.err + "skipped host" WARNING, nothing changed, no event.
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL osixinfo.osag_hardware_check_replaced_hw_for_host(931110, 'AA:BB:CC:00:00:12')$$,
    'S-HW-010: check_replaced_hw_for_host does not raise when the old hardware has no disposal contact (e_abort swallowed)'
);
SELECT is(
    (SELECT count(*) FROM osag.plog_stub_log WHERE levelname = 'ERR'
       AND message = 'dump_to_hw_history: hardware_disposal_contact_id is NULL while replacing hw for host_id: 931110 hw_id: 931211'),
    1::bigint,
    'S-HW-004: the missing disposal contact is logged with the Oracle-verbatim ERR text naming host and hardware id'
);
SELECT is(
    (SELECT count(*) FROM osag.plog_stub_log WHERE levelname = 'WARNING' AND message = 'check_replaced_hw_for_host: skipped host 931110'),
    1::bigint,
    'S-HW-010: the e_abort arm logs the Oracle-verbatim WARNING "check_replaced_hw_for_host: skipped host 931110"'
);
SELECT ok(
    (SELECT h.hardware_id = 931211 AND h.replacement_hardware_id = 931212 FROM mss.host h WHERE h.id = 931110),
    'S-HW-010: the skipped host still points at its old hardware with the replacement still registered'
);
SELECT ok(
    (SELECT disposal_date IS NULL FROM mss.hardware WHERE id = 931211),
    'S-HW-010: the old hardware''s disposal_date was NOT stamped (abort precedes all DML)'
);
SELECT is(
    (SELECT count(*) FROM mss.hardware_history WHERE host_name = 'p0602-hw-host2'),
    0::bigint,
    'S-HW-010: no history row for the skipped host'
);
SELECT is(
    (SELECT count(*) FROM mss.hardware_lifecycle_item WHERE hardware_id IN (931211, 931212)),
    0::bigint,
    'S-HW-010: no lifecycle item for the skipped host''s hardware'
);
SELECT is(
    (SELECT count(*) FROM tt.event WHERE host_id = 931110),
    0::bigint,
    'S-HW-010: no 10017 event for the skipped host'
);

-------------------------------------------------------------------------------
-- S-HW-011 / S-HW-012 / S-HW-004: replace_hardware called DIRECTLY propagates e_abort as
-- SQLSTATE OS010 (H4: disposal reason NULL -> the REASON message, contact check passed).
-------------------------------------------------------------------------------

SELECT throws_ok(
    $$CALL osixinfo.osag_hardware_replace_hardware(931130, 931231, 931232)$$,
    'OS010',
    NULL,
    'S-HW-012: replace_hardware raises OSAG_EXCEPTIONS.e_abort as SQLSTATE OS010 when the old hardware has no disposal reason'
);
SELECT is(
    (SELECT count(*) FROM osag.plog_stub_log WHERE levelname = 'ERR'
       AND message = 'dump_to_hw_history: hardware_disposal_reason_id is NULL while replacing hw for host_id: 931130 hw_id: 931231'),
    1::bigint,
    'S-HW-004: with the contact present and the reason NULL, the REASON message is logged (checks run in order contact, reason)'
);
SELECT is(
    (SELECT count(*) FROM osag.plog_stub_log WHERE message LIKE 'dump_to_hw_history: hardware_disposal_contact_id is NULL%931130%'),
    0::bigint,
    'S-HW-004: the contact message is NOT logged when only the reason is missing'
);
SELECT ok(
    (SELECT h.hardware_id = 931231 AND h.replacement_hardware_id = 931232 FROM mss.host h WHERE h.id = 931130),
    'S-HW-011: a directly-called replace_hardware that aborts leaves the host unchanged'
);
SELECT is(
    (SELECT count(*) FROM mss.hardware_history WHERE host_name = 'p0602-hw-host4'),
    0::bigint,
    'S-HW-011: no history row after the aborted direct replace_hardware'
);

-------------------------------------------------------------------------------
-- S-HW-011: replace_hardware propagates NO_DATA_FOUND (nonexistent old hardware; host
-- without a service) with Oracle's "no data found" wording.
-------------------------------------------------------------------------------

SELECT throws_ok(
    $$CALL osixinfo.osag_hardware_replace_hardware(931100, 931999999, 931202)$$,
    'P0002',
    NULL,
    'S-HW-011: replace_hardware raises NO_DATA_FOUND (P0002) for a nonexistent old hardware id'
);
SELECT throws_like(
    $$CALL osixinfo.osag_hardware_replace_hardware(931100, 931999999, 931202)$$,
    '%no data found%',
    'S-HW-011: the NO_DATA_FOUND from replace_hardware carries Oracle''s "no data found" wording (message-parity shim)'
);
SELECT throws_ok(
    $$CALL osixinfo.osag_hardware_replace_hardware(931150, 931251, 931252)$$,
    'P0002',
    NULL,
    'S-HW-011: replace_hardware raises NO_DATA_FOUND (P0002) for a host with no mss.host2service row'
);
SELECT ok(
    (SELECT h.hardware_id = 931251 AND h.replacement_hardware_id = 931252 FROM mss.host h WHERE h.id = 931150),
    'S-HW-011: the host-without-service stays on its old hardware after the failed direct replace_hardware'
);

-------------------------------------------------------------------------------
-- S-HW-006: a host with TWO services -> TOO_MANY_ROWS (P0003) out of BOTH entry points;
-- nothing changed.
-------------------------------------------------------------------------------

SELECT throws_ok(
    $$CALL osixinfo.osag_hardware_check_replaced_hw_for_host(931140, 'AA:BB:CC:00:00:42')$$,
    'P0003',
    NULL,
    'S-HW-006: check_replaced_hw_for_host propagates TOO_MANY_ROWS (P0003) for a matched host mapped to two services -- handled nowhere in the package'
);
SELECT throws_ok(
    $$CALL osixinfo.osag_hardware_replace_hardware(931140, 931241, 931242)$$,
    'P0003',
    NULL,
    'S-HW-006: replace_hardware propagates TOO_MANY_ROWS (P0003) for a host mapped to two services'
);
SELECT ok(
    (SELECT h.hardware_id = 931241 AND h.replacement_hardware_id = 931242 FROM mss.host h WHERE h.id = 931140),
    'S-HW-006: the two-service host is unchanged after both failures'
);
SELECT is(
    (SELECT count(*) FROM tt.event WHERE host_id = 931140),
    0::bigint,
    'S-HW-006: no event for the two-service host'
);

-------------------------------------------------------------------------------
-- S-HW-013: check_replaced_hw_for_host on the MATCHED host without a service -> the
-- procedure-wide NO_DATA_FOUND arm swallows the failure from dump_to_hw_history: silent,
-- unchanged, no event.
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL osixinfo.osag_hardware_check_replaced_hw_for_host(931150, 'AA:BB:CC:00:00:52')$$,
    'S-HW-013: check_replaced_hw_for_host does not raise for a matched host that has no service (NO_DATA_FOUND from dump_to_hw_history swallowed)'
);
SELECT ok(
    (SELECT h.hardware_id = 931251 AND h.replacement_hardware_id = 931252 FROM mss.host h WHERE h.id = 931150),
    'S-HW-013: the host without service is silently left on its old hardware'
);
SELECT is(
    (SELECT count(*) FROM osag.plog_stub_log WHERE message LIKE '%931150%'),
    0::bigint,
    'S-HW-013: the swallowed NO_DATA_FOUND leaves NO log line (Oracle''s silent "nothing to replace")'
);
SELECT is(
    (SELECT count(*) FROM tt.event WHERE host_id = 931150),
    0::bigint,
    'S-HW-013: no 10017 event for the host without service'
);

-------------------------------------------------------------------------------
-- S-HW-007: old hardware without purchase_date -> NOT NULL violation (23502) out of the
-- history insert, propagated by both entry points.
-------------------------------------------------------------------------------

SELECT throws_ok(
    $$CALL osixinfo.osag_hardware_replace_hardware(931160, 931261, 931262)$$,
    '23502',
    NULL,
    'S-HW-007: replace_hardware propagates the NOT NULL violation (23502) when the old hardware has no purchase_date'
);
SELECT throws_ok(
    $$CALL osixinfo.osag_hardware_check_replaced_hw_for_host(931160, 'AA:BB:CC:00:00:62')$$,
    '23502',
    NULL,
    'S-HW-007: check_replaced_hw_for_host propagates the same NOT NULL violation (23502) -- only NO_DATA_FOUND and e_abort are handled'
);
SELECT ok(
    (SELECT h.hardware_id = 931261 AND h.replacement_hardware_id = 931262 FROM mss.host h WHERE h.id = 931160),
    'S-HW-007: the host whose history insert failed is unchanged (the failed statement block is rolled back)'
);

-------------------------------------------------------------------------------
-- S-HW-003 / S-HW-014: direct replace_hardware on the INTERNAL host (service company 6)
-- -> location 9 on both lifecycle items.
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL osixinfo.osag_hardware_replace_hardware(931120, 931221, 931222)$$,
    'S-HW-014: replace_hardware succeeds for a host whose service company is 6'
);
SELECT is(
    (SELECT count(*) FROM mss.hardware_lifecycle_item WHERE hardware_id IN (931221, 931222) AND hardware_lc_location_id = 9),
    2::bigint,
    'S-HW-014: BOTH lifecycle items of an internal host (service_company_id = 6) use location 9 (Internal)'
);
SELECT ok(
    EXISTS (SELECT 1 FROM mss.hardware_lifecycle_item WHERE hardware_id = 931221 AND hardware_lc_state_id = 6)
    AND EXISTS (SELECT 1 FROM mss.hardware_lifecycle_item WHERE hardware_id = 931222 AND hardware_lc_state_id = 4),
    'S-HW-014: states are fixed -- 6 (Disposed) on the old, 4 (Installed) on the new hardware'
);
SELECT ok(
    (SELECT h.hardware_id = 931222 AND h.replacement_hardware_id IS NULL FROM mss.host h WHERE h.id = 931120),
    'S-HW-003: the internal host now points at the new hardware with the replacement cleared'
);
SELECT is(
    (SELECT hh.company_short FROM mss.hardware_history hh WHERE hh.host_name = 'p0602-hw-host3'),
    'p0602os'::varchar,
    'S-HW-007: the history row''s company_short is the host''s SERVICE company short'
);
SELECT is(
    (SELECT count(*) FROM tt.event WHERE host_id = 931120),
    0::bigint,
    'S-HW-003: replace_hardware itself raises NO event -- only check_replaced_hw_for_host does'
);

-------------------------------------------------------------------------------
-- S-HW-005 / S-HW-007: H8 -- disposal contact without e-mail (NULL-concat) and an
-- already-stamped disposal_date (kept by NVL).
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL osixinfo.osag_hardware_replace_hardware(931170, 931271, 931272)$$,
    'S-HW-005: replace_hardware succeeds when the disposal contact has no e-mail'
);
SELECT is(
    (SELECT hh.log FROM mss.hardware_history hh WHERE hh.host_name = 'p0602-hw-host8'),
    'hardware_type=p0602ht;disposal_contact=;disposal_reason=OS HW failure'::varchar,
    'S-HW-005: a NULL contact e-mail yields "disposal_contact=;" -- the rest of the log text survives (Oracle NULL-as-empty concatenation)'
);
SELECT is(
    (SELECT hh.disposal_date FROM mss.hardware_history hh WHERE hh.host_name = 'p0602-hw-host8'),
    '2020-01-01 00:00:00'::timestamp,
    'S-HW-007: an already-set disposal_date on the old hardware is copied as-is (NVL keeps it, no SYSDATE)'
);
SELECT ok(
    (SELECT disposal_date >= now()::timestamp - interval '1 minute' FROM mss.hardware WHERE id = 931271),
    'S-HW-003: replace_hardware re-stamps the OLD hardware''s own disposal_date with SYSDATE regardless (the history keeps the old value)'
);
SELECT is(
    (SELECT count(*) FROM mss.hardware_lifecycle_item WHERE hardware_id IN (931271, 931272) AND hardware_lc_location_id = 3),
    2::bigint,
    'S-HW-014: a host with a non-6 service company gets location 3 (Customer) on both items'
);

SELECT * FROM finish();
ROLLBACK;
