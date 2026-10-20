-- migration/test/pgtap/guma2__secondary_isp__spec.sql
--
-- pgTAP verification for migration/spec/guma2.secondary_isp.md. RED by construction:
-- none of guma2.secondary_isp_* (nor the private guma2.secondary_isp__* helpers) exists
-- yet. Every assertion's description starts with the spec clause ID it verifies
-- (HARN-05, trace_lint.py). Source of expected values is the SPEC only -- never
-- pg_migration/output/, never a PL/pgSQL translation.
--
-- One clause (S-SISP-009) asserts CORRECTED behaviour, not Oracle's: Oracle's is_host_up
-- queries mc.mon_server_connection WHERE mon_server_id IS NULL (a NOT NULL PK column), so
-- every peer is "down" and secondaryisp_alert has never raised a 10050 event. The tests
-- below pin the corrected contract (peer status from mc.host_connection_status,
-- NULL/0 = up) -- which is the ONLY way the 10050 happy path (S-SISP-013) can be
-- exercised at all.
--
-- Every "did NOT happen" assertion sits next to a lives_ok proving the CALL ran
-- (PITFALLS.md's asymmetric-coverage tell). Both public procedures swallow every error
-- (S-SISP-014/017), so every CALL is a lives_ok; the data and plog assertions carry the
-- proof. Plan-owned rows use the 930xxx id range (disjoint from every earlier suite).
-- i_logdate is passed as a naive timestamp literal (the parameter is anchored to
-- guma2.syslog_message.log_date, timestamp(0); CALL resolution has no implicit
-- timestamptz -> timestamp cast).

BEGIN;
SET CONSTRAINTS ALL DEFERRED;
SELECT plan(76);

-------------------------------------------------------------------------------
-- S-SISP-001 / S-SISP-018: public surface -- two PROCEDUREs with three arguments; the
-- seven helpers exist ONLY under the private __ convention, EXECUTE revoked from PUBLIC.
-------------------------------------------------------------------------------

SELECT ok(
    EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'guma2' AND p.proname = 'secondary_isp_secondaryisp_alert'
             AND p.prokind = 'p' AND p.pronargs = 3),
    'S-SISP-001: guma2.secondary_isp_secondaryisp_alert exists as a PostgreSQL PROCEDURE (prokind=p) with three arguments'
);
SELECT ok(
    EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'guma2' AND p.proname = 'secondary_isp_secondaryisp_ok'
             AND p.prokind = 'p' AND p.pronargs = 3),
    'S-SISP-001: guma2.secondary_isp_secondaryisp_ok exists as a PostgreSQL PROCEDURE (prokind=p) with three arguments'
);
SELECT is(
    (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'guma2' AND p.proname LIKE 'secondary\_isp\_%' AND p.proname NOT LIKE 'secondary\_isp\_\_%'),
    2::bigint,
    'S-SISP-018: exactly two PUBLIC secondary_isp_* objects exist -- no helper leaked under a public name'
);
SELECT ok(
    (SELECT count(DISTINCT p.proname) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'guma2' AND p.proname IN (
        'secondary_isp__get_next_token', 'secondary_isp__secondaryisp_parse_syslog', 'secondary_isp__is_host_up',
        'secondary_isp__secondaryisp_interface_info', 'secondary_isp__is_secondaryisp_all_peers_down',
        'secondary_isp__comma_join', 'secondary_isp__pretty_print_host_id_list')) = 7,
    'S-SISP-018: all seven body-only helpers exist as guma2.secondary_isp__<name>'
);
SELECT ok(
    NOT EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace,
             LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
        WHERE n.nspname = 'guma2' AND p.proname LIKE 'secondary\_isp\_\_%'
          AND a.grantee = 0 AND a.privilege_type = 'EXECUTE'),
    'S-SISP-018: EXECUTE on every guma2.secondary_isp__* helper is revoked from PUBLIC'
);

-------------------------------------------------------------------------------
-- S-SISP-002: the tokenizer, pinned directly on the private helper (the only way to
-- observe cases (b)/(c)/(d) in isolation). FUNCTION with two OUT columns.
-------------------------------------------------------------------------------

SELECT is(
    (SELECT o_token FROM guma2.secondary_isp__get_next_token('|', '1027|1028|1029')),
    '1027'::text,
    'S-SISP-002: token = the text before the FIRST delimiter occurrence'
);
SELECT is(
    (SELECT o_rest FROM guma2.secondary_isp__get_next_token('|', '1027|1028|1029')),
    '1028|1029'::text,
    'S-SISP-002: rest = everything after the first delimiter'
);
SELECT is(
    (SELECT o_token FROM guma2.secondary_isp__get_next_token('|', '1027')),
    '1027'::text,
    'S-SISP-002: delimiter not found -> token is the whole string (case a)'
);
SELECT ok(
    (SELECT o_rest IS NULL FROM guma2.secondary_isp__get_next_token('|', '1027')),
    'S-SISP-002: delimiter not found -> rest is NULL (case a)'
);
SELECT ok(
    (SELECT o_token IS NULL AND o_rest = '1028' FROM guma2.secondary_isp__get_next_token('|', '|1028')),
    'S-SISP-002: delimiter at position 1 -> token NULL, rest = the remainder (case b)'
);
SELECT ok(
    (SELECT o_token = '1027' AND o_rest IS NULL FROM guma2.secondary_isp__get_next_token('|', '1027|')),
    'S-SISP-002: delimiter at the very end -> token = text before it, rest NULL (never '''') (case c)'
);
SELECT is(
    (SELECT o_token FROM guma2.secondary_isp__get_next_token(', peers=', 'eth0, peers=1|2) [state=Alert, observed=420s]')),
    'eth0'::text,
    'S-SISP-002: multi-character delimiter -> token before it, Oracle substr(s, 0, p-1) semantics (first p-1 chars)'
);
SELECT is(
    (SELECT o_rest FROM guma2.secondary_isp__get_next_token(', peers=', 'eth0, peers=1|2) [state=Alert, observed=420s]')),
    '1|2) [state=Alert, observed=420s]'::text,
    'S-SISP-002: multi-character delimiter -> rest starts right after the whole delimiter'
);
SELECT ok(
    (SELECT o_token IS NULL AND o_rest IS NULL FROM guma2.secondary_isp__get_next_token('|', NULL)),
    'S-SISP-002: NULL input -> both outputs NULL (case d)'
);
SELECT ok(
    (SELECT o_token IS NULL AND o_rest IS NULL FROM guma2.secondary_isp__get_next_token('|', '')),
    'S-SISP-002: empty-string input -> both outputs NULL, same as NULL (case d, Pitfall 2 boundary)'
);

-------------------------------------------------------------------------------
-- Fixtures. Reference rows reused from the template's masterdata: mss.operating_system 2,
-- mss.service_type 6 (sitevpn), mss.service_level 1, mss.currency 1,
-- mss.isp_link_sourcing_type 1, tt.event_type 10003/10050/10100. stop.company, mss.host,
-- mss.service, mss.interface, mss.isp_link, mc.host_connection_status and mc.con_int_type
-- carry no masterdata in the template -- plan-owned rows below.
-------------------------------------------------------------------------------

INSERT INTO stop.company (id, name, short) VALUES (930001, 'P0602 Service Co', 'p0602co');
INSERT INTO stop.company (id, name, short) VALUES (930002, 'P0602 ISP Co', 'p0602isp');

INSERT INTO mss.service (id, service_type_id, company_id, service_level_id, name) VALUES (930010, 6, 930001, 1, 'p0602-sisp-svc-a');
INSERT INTO mss.service (id, service_type_id, company_id, service_level_id, name) VALUES (930011, 6, 930001, 1, 'p0602-sisp-svc-c1');
INSERT INTO mss.service (id, service_type_id, company_id, service_level_id, name) VALUES (930012, 6, 930001, 1, 'p0602-sisp-svc-c2');
INSERT INTO mss.service (id, service_type_id, company_id, service_level_id, name) VALUES (930013, 6, 930001, 1, 'p0602-sisp-svc-d');

-- Host A: the main alert/ok host. Host B: the "0 means up" + NULL-concat host.
-- Host C: mapped to TWO services (newevent_new raises TOO_MANY_ROWS -> swallowed here).
-- Host D: the secondaryisp_ok "unresolved ticket" host. Peers: up / down / zero / no row.
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author, active) VALUES (930100, 'p0602-sisp-host', 2, 930001, 'p0602', 1);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author, active) VALUES (930110, 'p0602-sisp-host-b', 2, 930001, 'p0602', 1);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author, active) VALUES (930120, 'p0602-sisp-host-c', 2, 930001, 'p0602', 1);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author, active) VALUES (930130, 'p0602-sisp-host-d', 2, 930001, 'p0602', 1);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author, active) VALUES (930101, 'p0602-peer-up', 2, 930001, 'p0602', 1);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author, active) VALUES (930102, 'p0602-peer-down', 2, 930001, 'p0602', 1);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author, active) VALUES (930103, 'p0602-peer-zero', 2, 930001, 'p0602', 1);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author, active) VALUES (930104, 'p0602-peer-norow', 2, 930001, 'p0602', 1);
INSERT INTO mss.host2service (host_id, service_id) VALUES (930100, 930010);
INSERT INTO mss.host2service (host_id, service_id) VALUES (930110, 930010);
INSERT INTO mss.host2service (host_id, service_id) VALUES (930120, 930011);
INSERT INTO mss.host2service (host_id, service_id) VALUES (930120, 930012);
INSERT INTO mss.host2service (host_id, service_id) VALUES (930130, 930013);

-- Connection monitoring (S-SISP-009): NULL and 0 both mean up (SANG_UP = 0); 2 = down;
-- 930104 deliberately has NO row.
INSERT INTO mc.con_int_type (id, name) VALUES (0, 'unknown') ON CONFLICT (id) DO NOTHING;
INSERT INTO mc.con_int_type (id, name) VALUES (2, 'service down') ON CONFLICT (id) DO NOTHING;
INSERT INTO mc.host_connection_status (host_id, con_timestamp, con_int_type_id) VALUES (930101, 1700000000, NULL);
INSERT INTO mc.host_connection_status (host_id, con_timestamp, con_int_type_id) VALUES (930102, 1700000000, 2);
INSERT INTO mc.host_connection_status (host_id, con_timestamp, con_int_type_id) VALUES (930103, 1700000000, 0);

-- Interfaces + ISP links. Host A: eth0 WAN managed; eth1 NOT WAN managed; eth2 linked to
-- TWO isp links (TOO_MANY_ROWS); eth3 linked to an isp link with NO company (NDF).
INSERT INTO mss.interface (id, name, host_id, author, description) VALUES (930200, 'eth0', 930100, 'p0602', 'P0602 uplink eth0');
INSERT INTO mss.interface (id, name, host_id, author, description) VALUES (930201, 'eth1', 930100, 'p0602', 'P0602 uplink eth1');
INSERT INTO mss.interface (id, name, host_id, author, description) VALUES (930202, 'eth2', 930100, 'p0602', 'P0602 uplink eth2');
INSERT INTO mss.interface (id, name, host_id, author, description) VALUES (930203, 'eth3', 930100, 'p0602', 'P0602 uplink eth3');
INSERT INTO mss.interface (id, name, host_id, author, description) VALUES (930210, 'eth0', 930110, 'p0602', 'P0602 uplink b');
INSERT INTO mss.interface (id, name, host_id, author, description) VALUES (930220, 'eth0', 930120, 'p0602', 'P0602 uplink c');
INSERT INTO mss.interface (id, name, host_id, author, description) VALUES (930230, 'eth0', 930130, 'p0602', 'P0602 uplink d');

INSERT INTO mss.isp_link (id, company_id, router_ip_address1, event_type_id, currency_id, isp_link_sourcing_type_id, wan_managed)
    VALUES (930300, 930002, 1, 10003, 1, 1, 1);
INSERT INTO mss.isp_link (id, company_id, router_ip_address1, event_type_id, currency_id, isp_link_sourcing_type_id, wan_managed)
    VALUES (930301, 930002, 1, 10003, 1, 1, 0);
INSERT INTO mss.isp_link (id, company_id, router_ip_address1, event_type_id, currency_id, isp_link_sourcing_type_id, wan_managed)
    VALUES (930302, 930002, 1, 10003, 1, 1, 1);
INSERT INTO mss.isp_link (id, company_id, router_ip_address1, event_type_id, currency_id, isp_link_sourcing_type_id, wan_managed)
    VALUES (930303, 930002, 1, 10003, 1, 1, 1);
INSERT INTO mss.isp_link (id, company_id, router_ip_address1, event_type_id, currency_id, isp_link_sourcing_type_id, wan_managed)
    VALUES (930304, NULL, 1, 10003, 1, 1, 1);
INSERT INTO mss.isp_link (id, company_id, router_ip_address1, event_type_id, currency_id, isp_link_sourcing_type_id, wan_managed)
    VALUES (930310, 930002, 1, 10003, 1, 1, 1);
INSERT INTO mss.isp_link (id, company_id, router_ip_address1, event_type_id, currency_id, isp_link_sourcing_type_id, wan_managed)
    VALUES (930320, 930002, 1, 10003, 1, 1, 1);
INSERT INTO mss.isp_link (id, company_id, router_ip_address1, event_type_id, currency_id, isp_link_sourcing_type_id, wan_managed)
    VALUES (930330, 930002, 1, 10003, 1, 1, 1);

INSERT INTO mss.interface2isp_link (interface_id, isp_link_id) VALUES (930200, 930300);
INSERT INTO mss.interface2isp_link (interface_id, isp_link_id) VALUES (930201, 930301);
INSERT INTO mss.interface2isp_link (interface_id, isp_link_id) VALUES (930202, 930302);
INSERT INTO mss.interface2isp_link (interface_id, isp_link_id) VALUES (930202, 930303);
INSERT INTO mss.interface2isp_link (interface_id, isp_link_id) VALUES (930203, 930304);
INSERT INTO mss.interface2isp_link (interface_id, isp_link_id) VALUES (930210, 930310);
INSERT INTO mss.interface2isp_link (interface_id, isp_link_id) VALUES (930220, 930320);
INSERT INTO mss.interface2isp_link (interface_id, isp_link_id) VALUES (930230, 930330);

-- Host D: one RESOLVED ticket (status 101, must be ignored) and, later, one open ticket.
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, subject, last_status_change_date)
    VALUES (930900, 1, 101, 930001, 930130, 'p0602 resolved ticket', now() - interval '1 hour');

-------------------------------------------------------------------------------
-- secondaryisp_alert: the ignore paths first (host A has NO event yet, so every
-- "no event" assertion below is a real check against an untouched host).
-------------------------------------------------------------------------------

-- S-SISP-004: parse failure at step 1 (no NURSE:SECONDARYISP: marker) and step 3 (no
-- ', peers=' marker). Logged via plog.err with the step number, then silently dropped.
SELECT lives_ok(
    $$CALL guma2.secondary_isp_secondaryisp_alert(930100, '2026-07-29 16:51:27'::timestamp,
        'Jul 29 16:51:27 v1 nursed: something else entirely')$$,
    'S-SISP-004: secondaryisp_alert does not raise for a line without the NURSE:SECONDARYISP: marker'
);
SELECT is(
    (SELECT count(*) FROM osag.plog_stub_log WHERE levelname = 'ERR'
       AND message = 'SECONDARY_ISP.secondaryisp_parse_syslog(): can''t  parse NURSE:SECONDARYISP:ALERT line (1): Jul 29 16:51:27 v1 nursed: something else entirely'),
    1::bigint,
    'S-SISP-004: step-1 parse failure logs the Oracle-verbatim ERR text (double space in "can''t  parse", step number 1, full line appended)'
);
SELECT lives_ok(
    $$CALL guma2.secondary_isp_secondaryisp_alert(930100, '2026-07-29 16:51:27'::timestamp,
        'Jul 29 16:51:27 v1 nursed: NURSE:SECONDARYISP:ALERT All tunnels down (interface=eth0) [state=Alert, observed=420s]')$$,
    'S-SISP-004: secondaryisp_alert does not raise for a line without the ", peers=" marker'
);
SELECT is(
    (SELECT count(*) FROM osag.plog_stub_log WHERE levelname = 'ERR'
       AND message LIKE 'SECONDARY_ISP.secondaryisp_parse_syslog(): can''t  parse NURSE:SECONDARYISP:ALERT line (3): %'),
    1::bigint,
    'S-SISP-004: step-3 parse failure logs step number 3'
);
SELECT is(
    (SELECT count(*) FROM tt.event WHERE host_id = 930100),
    0::bigint,
    'S-SISP-004: a parse failure raises NO event (E_ABORT swallowed before any lookup)'
);

-- S-SISP-006: interface lookup finds nothing -- unknown interface, and an interface whose
-- ISP link has no company (inner join drops it). Oracle-verbatim prefix
-- "secondary_interface_info" (NOT the routine's real name).
SELECT lives_ok(
    $$CALL guma2.secondary_isp_secondaryisp_alert(930100, '2026-07-29 16:51:27'::timestamp,
        'Jul 29 16:51:27 v1 nursed: NURSE:SECONDARYISP:ALERT All tunnels down (interface=eth9, peers=930101) [state=Alert, observed=420s]')$$,
    'S-SISP-006: secondaryisp_alert does not raise for an interface the host does not have'
);
SELECT is(
    (SELECT count(*) FROM osag.plog_stub_log WHERE levelname = 'ERR'
       AND message = 'SECONDARY_ISP.secondary_interface_info(): can''t get information about interface eth9 of host 930100'),
    1::bigint,
    'S-SISP-006: unknown interface logs the Oracle-verbatim ERR text with the "secondary_interface_info" prefix'
);
SELECT lives_ok(
    $$CALL guma2.secondary_isp_secondaryisp_alert(930100, '2026-07-29 16:51:27'::timestamp,
        'Jul 29 16:51:27 v1 nursed: NURSE:SECONDARYISP:ALERT All tunnels down (interface=eth3, peers=930101) [state=Alert, observed=420s]')$$,
    'S-SISP-006: secondaryisp_alert does not raise for an interface whose ISP link has no company'
);
SELECT is(
    (SELECT count(*) FROM osag.plog_stub_log WHERE levelname = 'ERR'
       AND message = 'SECONDARY_ISP.secondary_interface_info(): can''t get information about interface eth3 of host 930100'),
    1::bigint,
    'S-SISP-006: an ISP link without company_id makes the inner join empty -> same "can''t get information" ERR'
);
SELECT is(
    (SELECT count(*) FROM tt.event WHERE host_id = 930100),
    0::bigint,
    'S-SISP-006: an interface-lookup failure raises NO event'
);

-- S-SISP-007: interface linked to two ISP links -> TOO_MANY_ROWS -> public WHEN OTHERS,
-- "unexpected error 99" (alert wording), swallowed.
SELECT lives_ok(
    $$CALL guma2.secondary_isp_secondaryisp_alert(930100, '2026-07-29 16:51:27'::timestamp,
        'Jul 29 16:51:27 v1 nursed: NURSE:SECONDARYISP:ALERT All tunnels down (interface=eth2, peers=930101) [state=Alert, observed=420s]')$$,
    'S-SISP-007: secondaryisp_alert does not raise when the interface is linked to two ISP links (TOO_MANY_ROWS swallowed)'
);
SELECT is(
    (SELECT count(*) FROM osag.plog_stub_log WHERE levelname = 'ERR'
       AND message LIKE 'SECONDARY_ISP.secondaryisp_alert(): unexpected error 99: %'),
    1::bigint,
    'S-SISP-007: TOO_MANY_ROWS from the interface lookup is logged by the alert''s WHEN OTHERS arm as "unexpected error 99: <sqlerrm>"'
);
SELECT is(
    (SELECT count(*) FROM tt.event WHERE host_id = 930100),
    0::bigint,
    'S-SISP-007: the swallowed TOO_MANY_ROWS raises NO event'
);

-- S-SISP-008: link not WAN managed -> NOTICE, no event.
SELECT lives_ok(
    $$CALL guma2.secondary_isp_secondaryisp_alert(930100, '2026-07-29 16:51:27'::timestamp,
        'Jul 29 16:51:27 v1 nursed: NURSE:SECONDARYISP:ALERT All tunnels down (interface=eth1, peers=930101) [state=Alert, observed=420s]')$$,
    'S-SISP-008: secondaryisp_alert does not raise for a link that is not WAN managed'
);
SELECT is(
    (SELECT count(*) FROM osag.plog_stub_log WHERE levelname = 'NOTICE'
       AND message = 'SECONDARY_ISP.secondaryisp_alert(): Ignoring secondary ISP outage, because not WAN managed (host: 930100, interface: eth1)'),
    1::bigint,
    'S-SISP-008: a non-WAN-managed link logs the Oracle-verbatim NOTICE naming host and interface'
);
SELECT is(
    (SELECT count(*) FROM tt.event WHERE host_id = 930100),
    0::bigint,
    'S-SISP-008: a non-WAN-managed link raises NO event'
);

-- S-SISP-011 / S-SISP-009 / S-SISP-010: all peers down (one down, one without a
-- monitoring row) -> NOTICE, no event; an EMPTY peers list counts as "all down" too.
SELECT lives_ok(
    $$CALL guma2.secondary_isp_secondaryisp_alert(930100, '2026-07-29 16:51:27'::timestamp,
        'Jul 29 16:51:27 v1 nursed: NURSE:SECONDARYISP:ALERT All tunnels down (interface=eth0, peers=930102|930104) [state=Alert, observed=420s]')$$,
    'S-SISP-011: secondaryisp_alert does not raise when every listed peer is down or unmonitored'
);
SELECT is(
    (SELECT count(*) FROM osag.plog_stub_log WHERE levelname = 'NOTICE'
       AND message = 'SECONDARY_ISP.secondaryisp_alert(): Ignoring secondary ISP outage, because all peers down (host: 930100, interface: eth0)'),
    1::bigint,
    'S-SISP-011: all peers down logs the Oracle-verbatim NOTICE'
);
SELECT is(
    (SELECT count(*) FROM tt.event WHERE host_id = 930100),
    0::bigint,
    'S-SISP-009: a peer with con_int_type_id 2 and a peer without a host_connection_status row are both "down" -> NO event'
);
SELECT lives_ok(
    $$CALL guma2.secondary_isp_secondaryisp_alert(930100, '2026-07-29 16:51:27'::timestamp,
        'Jul 29 16:51:27 v1 nursed: NURSE:SECONDARYISP:ALERT All tunnels down (interface=eth0, peers=) [state=Alert, observed=420s]')$$,
    'S-SISP-010: secondaryisp_alert does not raise for an empty peers list'
);
SELECT is(
    (SELECT count(*) FROM osag.plog_stub_log WHERE levelname = 'NOTICE'
       AND message = 'SECONDARY_ISP.secondaryisp_alert(): Ignoring secondary ISP outage, because all peers down (host: 930100, interface: eth0)'),
    2::bigint,
    'S-SISP-010: an empty peers list never enters the loop -> "all peers down" -> second identical NOTICE, no event'
);

-- S-SISP-010: a non-numeric peer token -> VALUE_ERROR -> WHEN OTHERS "unexpected error 99".
SELECT lives_ok(
    $$CALL guma2.secondary_isp_secondaryisp_alert(930100, '2026-07-29 16:51:27'::timestamp,
        'Jul 29 16:51:27 v1 nursed: NURSE:SECONDARYISP:ALERT All tunnels down (interface=eth0, peers=abc|930101) [state=Alert, observed=420s]')$$,
    'S-SISP-010: secondaryisp_alert does not raise for a non-numeric peer token'
);
SELECT is(
    (SELECT count(*) FROM osag.plog_stub_log WHERE levelname = 'ERR'
       AND message LIKE 'SECONDARY_ISP.secondaryisp_alert(): unexpected error 99: %'),
    2::bigint,
    'S-SISP-010: TO_NUMBER on a non-numeric token is caught by the alert''s WHEN OTHERS arm (second "unexpected error 99" line)'
);
SELECT is(
    (SELECT count(*) FROM tt.event WHERE host_id = 930100),
    0::bigint,
    'S-SISP-014: none of the seven ignore/error paths above produced an event on host A'
);

-------------------------------------------------------------------------------
-- S-SISP-013 / S-SISP-003 / S-SISP-012 / S-SISP-019: the happy path on host A -- one peer
-- up (NULL con_int_type_id), one down. A 10050 event with the Oracle-verbatim texts; a
-- new ticket opened by newevent_new (subject = event type name "ISP down").
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL guma2.secondary_isp_secondaryisp_alert(930100, '2026-07-29 16:51:27'::timestamp,
        'Jul 29 16:51:27 v1 nursed: NURSE:SECONDARYISP:ALERT All tunnels down (interface=eth0, peers=930101|930102) [state=Alert, observed=420s]')$$,
    'S-SISP-013: secondaryisp_alert succeeds for a WAN-managed link with at least one peer up'
);
SELECT is(
    (SELECT count(*) FROM tt.event WHERE host_id = 930100 AND type_id = 10050 AND public_event = 1),
    1::bigint,
    'S-SISP-013: exactly one public 10050 (ISP down) event now exists for host A (fixture started with none)'
);
SELECT is(
    (SELECT details_public FROM tt.event WHERE host_id = 930100 AND type_id = 10050),
    ('Secondary ISP Outage' || chr(10) || chr(10)
     || 'All VPN tunnels through one ISP link are down. This could mean that the ISP link is down.' || chr(10) || chr(10)
     || 'Open Systems Mission Control will start the WAN Management ISP Down process.' || chr(10) || chr(10)
     || 'Host:       p0602-sisp-host' || chr(10)
     || 'Interface:  eth0 (P0602 uplink eth0)' || chr(10)
     || 'ISP name:   P0602 ISP Co' || chr(10)
     || 'VPN peers:  p0602-peer-up, p0602-peer-down' || chr(10)
     || 'Down since: 420s' || chr(10))::text,
    'S-SISP-013: the public text is Oracle-verbatim -- host name, "eth0 (description)", ISP company name, comma-joined peer names, "Down since: 420s", trailing line break'
);
SELECT is(
    (SELECT details_private FROM tt.event WHERE host_id = 930100 AND type_id = 10050),
    ('This host is subscribed to WAN Management.' || chr(10) || chr(10)
     || 'To Do:' || chr(10) || chr(10)
     || 'Execute this process: https://control.open.ch/docs/x/wBlbB')::text,
    'S-SISP-013: the private text is the Oracle-verbatim WAN Management to-do'
);
SELECT is(
    (SELECT count(*) FROM tt.ticket t WHERE t.host_id = 930100 AND t.type_id = 1 AND t.subject = 'ISP down' AND t.company_id = 930001
       AND EXISTS (SELECT 1 FROM tt.event e WHERE e.ticket_id = t.id AND e.type_id = 10050)),
    1::bigint,
    'S-SISP-013: newevent_new opened exactly one trouble ticket (type 1, subject "ISP down", the host''s service company) carrying the 10050 event'
);
SELECT ok(
    (SELECT details_public LIKE '%' || chr(10) || 'VPN peers:  p0602-peer-up, p0602-peer-down' || chr(10) || '%'
     FROM tt.event WHERE host_id = 930100 AND type_id = 10050),
    'S-SISP-012: pretty_print_host_id_list joins the peer host names with ", " and no leading separator (Oracle''s '''' accumulator is NULL)'
);
SELECT ok(
    (SELECT details_public LIKE '%Interface:  eth0 (P0602 uplink eth0)%Down since: 420s%'
     FROM tt.event WHERE host_id = 930100 AND type_id = 10050),
    'S-SISP-003: the parser extracted interface "eth0" (step 3) and the observed duration "420s" (step 6) from the canonical line'
);

-------------------------------------------------------------------------------
-- S-SISP-009 (0 = up) / S-SISP-012 (unknown host) / S-SISP-019 (NULL concat) on host B:
-- the single peer carries con_int_type_id 0 (SANG_UP), plus an unknown peer id; the
-- observed duration is empty.
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL guma2.secondary_isp_secondaryisp_alert(930110, '2026-07-29 16:51:27'::timestamp,
        'Jul 29 16:51:27 v1 nursed: NURSE:SECONDARYISP:ALERT All tunnels down (interface=eth0, peers=930103|939999) [state=Alert, observed=]')$$,
    'S-SISP-009: secondaryisp_alert succeeds when the only monitored peer carries con_int_type_id 0'
);
SELECT is(
    (SELECT count(*) FROM tt.event WHERE host_id = 930110 AND type_id = 10050),
    1::bigint,
    'S-SISP-009: a peer with con_int_type_id 0 counts as UP (SANG_UP = 0, same as NULL) -> the 10050 event is raised'
);
SELECT ok(
    (SELECT details_public LIKE '%' || chr(10) || 'VPN peers:  p0602-peer-zero, unknown(hostid:939999)' || chr(10) || '%'
     FROM tt.event WHERE host_id = 930110 AND type_id = 10050),
    'S-SISP-012: a peer id with no mss.host row is rendered as "unknown(hostid:939999)" after the known peer''s name'
);
SELECT ok(
    (SELECT details_public LIKE '%' || chr(10) || 'Down since: ' || chr(10)
     FROM tt.event WHERE host_id = 930110 AND type_id = 10050),
    'S-SISP-019: an empty "observed=" yields a NULL duration -- "Down since: " plus the line break survive (Oracle NULL-as-empty concatenation), the text is not NULL'
);
SELECT ok(
    (SELECT details_public LIKE '%' || chr(10) || 'Host:       p0602-sisp-host-b' || chr(10) || '%'
     FROM tt.event WHERE host_id = 930110 AND type_id = 10050),
    'S-SISP-012: pretty_print_host_id_list(i_host_id) renders the single host id as its name'
);

-------------------------------------------------------------------------------
-- S-SISP-014: an error raised INSIDE newevent_new (host C is mapped to two services ->
-- TOO_MANY_ROWS, re-raised unhandled by newevent_new) is swallowed by the alert's
-- WHEN OTHERS and logged -- the procedure never raises.
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL guma2.secondary_isp_secondaryisp_alert(930120, '2026-07-29 16:51:27'::timestamp,
        'Jul 29 16:51:27 v1 nursed: NURSE:SECONDARYISP:ALERT All tunnels down (interface=eth0, peers=930101) [state=Alert, observed=420s]')$$,
    'S-SISP-014: secondaryisp_alert does not raise when newevent_new itself fails (host mapped to two services)'
);
SELECT is(
    (SELECT count(*) FROM osag.plog_stub_log WHERE levelname = 'ERR'
       AND message LIKE 'SECONDARY_ISP.secondaryisp_alert(): unexpected error 99: %'),
    3::bigint,
    'S-SISP-014: the newevent_new failure is logged by the alert''s WHEN OTHERS arm (third "unexpected error 99" line)'
);
SELECT is(
    (SELECT count(*) FROM tt.event WHERE host_id = 930120),
    0::bigint,
    'S-SISP-014: no event exists for host C after the swallowed failure'
);

-------------------------------------------------------------------------------
-- secondaryisp_ok
-------------------------------------------------------------------------------

-- S-SISP-004 (ok side): the parse ERR text says "ALERT" even for an OK line.
SELECT lives_ok(
    $$CALL guma2.secondary_isp_secondaryisp_ok(930100, '2026-07-29 17:01:27'::timestamp,
        'Jul 29 17:01:27 v1 nursed: NURSE:SECONDARYISP:OK Some tunnels up (interface=eth0 peers=930101) [state=OK, observed=12s]')$$,
    'S-SISP-004: secondaryisp_ok does not raise for a line without the ", peers=" marker'
);
SELECT is(
    (SELECT count(*) FROM osag.plog_stub_log WHERE levelname = 'ERR'
       AND message LIKE 'SECONDARY_ISP.secondaryisp_parse_syslog(): can''t  parse NURSE:SECONDARYISP:ALERT line (3): %OK Some tunnels up%'),
    1::bigint,
    'S-SISP-004: the parse ERR text names "ALERT" regardless of the calling procedure (Oracle-verbatim)'
);

-- S-SISP-008 (ok side): not WAN managed -> the ok-specific NOTICE.
SELECT lives_ok(
    $$CALL guma2.secondary_isp_secondaryisp_ok(930100, '2026-07-29 17:01:27'::timestamp,
        'Jul 29 17:01:27 v1 nursed: NURSE:SECONDARYISP:OK Some tunnels up (interface=eth1, peers=930101) [state=OK, observed=12s]')$$,
    'S-SISP-008: secondaryisp_ok does not raise for a link that is not WAN managed'
);
SELECT is(
    (SELECT count(*) FROM osag.plog_stub_log WHERE levelname = 'NOTICE'
       AND message = 'SECONDARY_ISP.secondaryisp_ok(): Ignoring secondary ISP ok event, because not WAN managed (host: 930100, interface: eth1)'),
    1::bigint,
    'S-SISP-008: secondaryisp_ok logs its own "Ignoring secondary ISP ok event, because not WAN managed" NOTICE'
);
SELECT is(
    (SELECT count(*) FROM tt.event WHERE host_id = 930100 AND type_id = 10100),
    0::bigint,
    'S-SISP-008: a non-WAN-managed link raises NO 10100 event'
);

-- S-SISP-007 / S-SISP-017 (ok side): TOO_MANY_ROWS -> "unexpected error: " (no 99).
SELECT lives_ok(
    $$CALL guma2.secondary_isp_secondaryisp_ok(930100, '2026-07-29 17:01:27'::timestamp,
        'Jul 29 17:01:27 v1 nursed: NURSE:SECONDARYISP:OK Some tunnels up (interface=eth2, peers=930101) [state=OK, observed=12s]')$$,
    'S-SISP-017: secondaryisp_ok does not raise when the interface lookup hits TOO_MANY_ROWS'
);
SELECT is(
    (SELECT count(*) FROM osag.plog_stub_log WHERE levelname = 'ERR'
       AND message LIKE 'SECONDARY_ISP.secondaryisp_ok(): unexpected error: %'),
    1::bigint,
    'S-SISP-017: secondaryisp_ok''s WHEN OTHERS text is "unexpected error: <sqlerrm>" -- no "99"'
);
SELECT is(
    (SELECT count(*) FROM osag.plog_stub_log WHERE levelname = 'ERR'
       AND message LIKE 'SECONDARY_ISP.secondaryisp_ok(): unexpected error 99%'),
    0::bigint,
    'S-SISP-007: the ok-side OTHERS line never carries the alert''s "99"'
);

-- S-SISP-015: host D has only a RESOLVED ticket (status 101) -> "no unresolved ticket" NOTICE.
SELECT lives_ok(
    $$CALL guma2.secondary_isp_secondaryisp_ok(930130, '2026-07-29 17:01:27'::timestamp,
        'Jul 29 17:01:27 v1 nursed: NURSE:SECONDARYISP:OK Some tunnels up (interface=eth0, peers=930101) [state=OK, observed=12s]')$$,
    'S-SISP-015: secondaryisp_ok does not raise for a host whose only ticket is resolved'
);
SELECT is(
    (SELECT count(*) FROM osag.plog_stub_log WHERE levelname = 'NOTICE'
       AND message = 'SECONDARY_ISP.secondaryisp_ok(): Ignoring secondary ISP ok event, because no unresolved ticket was found (host: 930130, interface: eth0)'),
    1::bigint,
    'S-SISP-015: a host with no ticket below status 100 logs the Oracle-verbatim "no unresolved ticket was found" NOTICE'
);
SELECT is(
    (SELECT count(*) FROM tt.event WHERE host_id = 930130),
    0::bigint,
    'S-SISP-015: no event is raised when no unresolved ticket exists'
);

-- S-SISP-015 / S-SISP-016: give host D an OPEN ticket (status 2, no events) -> the OK
-- event IS raised; where it lands is newevent_new's decision (here: a new ticket, since
-- the fixture ticket has no first event to classify).
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, subject, last_status_change_date)
    VALUES (930901, 1, 2, 930001, 930130, 'p0602 open ticket', now() - interval '1 hour');
SELECT lives_ok(
    $$CALL guma2.secondary_isp_secondaryisp_ok(930130, '2026-07-29 17:01:27'::timestamp,
        'Jul 29 17:01:27 v1 nursed: NURSE:SECONDARYISP:OK Some tunnels up (interface=eth0, peers=930101) [state=OK, observed=12s]')$$,
    'S-SISP-015: secondaryisp_ok succeeds once the host has an unresolved ticket'
);
SELECT is(
    (SELECT count(*) FROM tt.event WHERE host_id = 930130 AND type_id = 10100),
    1::bigint,
    'S-SISP-015: an open ticket (status 2) passes the unresolved-ticket gate -> exactly one 10100 event for host D'
);
SELECT is(
    (SELECT details_public FROM tt.event WHERE host_id = 930130 AND type_id = 10100),
    ('Secondary ISP OK' || chr(10) || chr(10)
     || 'One or more VPN tunnels through one ISP link are up. The ISP link is thus apparently up.' || chr(10) || chr(10)
     || 'The WAN Management ISP Down process will be stopped.' || chr(10) || chr(10)
     || 'Host:       p0602-sisp-host-d' || chr(10)
     || 'Interface:  eth0 (P0602 uplink d)' || chr(10)
     || 'ISP name:   P0602 ISP Co' || chr(10)
     || 'VPN peers:  p0602-peer-up' || chr(10)
     || 'Up since:   12s' || chr(10))::text,
    'S-SISP-016: the OK public text is Oracle-verbatim, ending in "Up since:   12s" plus a line break'
);
SELECT is(
    (SELECT details_private FROM tt.event WHERE host_id = 930130 AND type_id = 10100),
    ('To Do:' || chr(10) || chr(10)
     || 'Try to find a corresponding "Secondary ISP Outage" event. If there isn''t one, fast-resolve.')::text,
    'S-SISP-016: the OK private text is the Oracle-verbatim to-do with one apostrophe in "isn''t"'
);

-- S-SISP-016 on host A: the unresolved ticket is the 10050 outage ticket -> newevent_new
-- appends the 10100 event to THAT ticket and makes it hot.
SELECT lives_ok(
    $$CALL guma2.secondary_isp_secondaryisp_ok(930100, '2026-07-29 17:01:27'::timestamp,
        'Jul 29 17:01:27 v1 nursed: NURSE:SECONDARYISP:OK Some tunnels up (interface=eth0, peers=930101|930102) [state=OK, observed=12s]')$$,
    'S-SISP-016: secondaryisp_ok succeeds for the host carrying the open 10050 outage ticket'
);
SELECT is(
    (SELECT count(*) FROM tt.event o
     WHERE o.host_id = 930100 AND o.type_id = 10100
       AND o.ticket_id = (SELECT e.ticket_id FROM tt.event e WHERE e.host_id = 930100 AND e.type_id = 10050)),
    1::bigint,
    'S-SISP-016: the 10100 event is appended to the SAME ticket as the 10050 outage event (newevent_new''s recent-ticket heuristic, not this package''s cursor)'
);
SELECT is(
    (SELECT t.status_id FROM tt.ticket t JOIN tt.event e ON e.ticket_id = t.id WHERE e.host_id = 930100 AND e.type_id = 10050),
    3::numeric,
    'S-SISP-016: appending the OK event moved the outage ticket to status 3 (hot)'
);
SELECT ok(
    (SELECT details_public LIKE '%' || chr(10) || 'VPN peers:  p0602-peer-up, p0602-peer-down' || chr(10) || 'Up since:   12s' || chr(10)
     FROM tt.event WHERE host_id = 930100 AND type_id = 10100),
    'S-SISP-016: the OK text on host A lists both peers and the parsed "12s"'
);
SELECT is(
    (SELECT count(*) FROM tt.event WHERE host_id = 930100),
    2::bigint,
    'S-SISP-013: host A carries exactly two events in total (one 10050, one 10100) -- none of the ignore paths leaked one'
);

-- S-SISP-001: i_logdate is ignored -- the event date is the processing time, not the
-- syslog time (both events on host A were given a 2026-07-29 syslog timestamp).
SELECT is(
    (SELECT count(*) FROM tt.event WHERE host_id = 930100 AND eventdate < now() - interval '1 day'),
    0::bigint,
    'S-SISP-001: i_logdate is never used -- no event carries the 2026-07-29 syslog timestamp as its eventdate'
);
SELECT is(
    (SELECT count(*) FROM tt.event WHERE host_id = 930100 AND eventdate >= now() - interval '1 day'),
    2::bigint,
    'S-SISP-001: both host-A events carry the processing time (newevent_new''s SYSDATE default) as eventdate'
);

SELECT * FROM finish();
ROLLBACK;
