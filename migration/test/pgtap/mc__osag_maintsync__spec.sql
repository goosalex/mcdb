-- migration/test/pgtap/mc__osag_maintsync__spec.sql
--
-- pgTAP verification for migration/spec/mc.osag_maintsync.md. RED by construction: none
-- of mc.osag_maintsync_* exists yet. Every assertion's description starts with the spec
-- clause ID it verifies (HARN-05, trace_lint.py). Source of expected values is the SPEC
-- only -- never pg_migration/output/, never a PL/pgSQL translation.
--
-- Four clauses (S-MAINT-012, -016, -017, -018) assert CORRECTED behaviour, not Oracle's
-- (see the spec for the line-by-line trace of each defect).
--
-- Fixture-initial values always DIFFER from the post-CALL expected value where the
-- clause claims a change, and every "did NOT happen" assertion sits next to a lives_ok
-- proving the CALL actually ran. Plan-owned rows use the 92xxxx id range: hosts 9200xx,
-- tickets 9201xx, service windows 9202xx, maintenance windows 9203xx, customer
-- maintenance windows 9204xx, ISP links 9205xx, interfaces 9206xx, company 920701.
--
-- Section A (batch fixtures + the two batch routines) runs BEFORE Section B's fixtures
-- exist, so the batch assertions count exactly the Section A rows; Section B (single-
-- entity routines) then adds its own rows. The log-count assertions rely on that order
-- too: the "nothing to do" calls run before any failing call of the same routine.
--
-- mc.maintenance_status (1 unknown, 2 active, 3 inactive, 4 maintenance) comes from
-- masterdata/MC/maintenance_status.csv, which the template does not load (its loader
-- covers AUTH/TT/MSS/MCAUDIT/OSAG only); inserted here idempotently.

BEGIN;
SET CONSTRAINTS ALL DEFERRED;
SELECT plan(109);

-------------------------------------------------------------------------------
-- S-MAINT-001: all four routines exist as PostgreSQL PROCEDUREs (prokind='p').
-------------------------------------------------------------------------------

SELECT ok(
    EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'mc' AND p.proname = 'osag_maintsync_update_host_maint_status' AND p.prokind = 'p'),
    'S-MAINT-001: mc.osag_maintsync_update_host_maint_status exists as a PostgreSQL PROCEDURE (prokind=p)'
);
SELECT ok(
    EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'mc' AND p.proname = 'osag_maintsync_update_isp_link_maint_status' AND p.prokind = 'p'),
    'S-MAINT-001: mc.osag_maintsync_update_isp_link_maint_status exists as a PostgreSQL PROCEDURE (prokind=p)'
);
SELECT ok(
    EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'mc' AND p.proname = 'osag_maintsync_update_single_host' AND p.prokind = 'p'),
    'S-MAINT-001: mc.osag_maintsync_update_single_host exists as a PostgreSQL PROCEDURE (prokind=p)'
);
SELECT ok(
    EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'mc' AND p.proname = 'osag_maintsync_update_single_isp_link' AND p.prokind = 'p'),
    'S-MAINT-001: mc.osag_maintsync_update_single_isp_link exists as a PostgreSQL PROCEDURE (prokind=p)'
);

-------------------------------------------------------------------------------
-- Section A fixtures. Reference rows reused from masterdata: mss.operating_system 2
-- (sunos) and 21 (UNKNOWN), tt.status 2 (open) / 102 (closed), tt.ticket_type 1,
-- tt.event_type 10001, mss.currency 1, mss.isp_link_sourcing_type 1.
-------------------------------------------------------------------------------

INSERT INTO mc.maintenance_status (id, name, description) VALUES
    (1, 'unknown',     'Maintenance status is unknown'),
    (2, 'active',      'Entity is active, no maintenance in progress'),
    (3, 'inactive',    'Entity is inactive, maintenance not explicitly tracked'),
    (4, 'maintenance', 'Entity is under maintenance')
ON CONFLICT (id) DO NOTHING;

INSERT INTO stop.company (id, name, short) VALUES (920701, 'P0601 Maint Co', 'p0601m');

-- hosts: (id, name, os, company, author, active, stored maintenance status)
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author, active, maintenance_status_id) VALUES
    (920001, 'p0601-h01-null-active',   2,  920701, 'p0601', 1, NULL),  -- -> 2
    (920002, 'p0601-h02-null-inactive', 2,  920701, 'p0601', 0, NULL),  -- -> 3
    (920003, 'p0601-h03-window',        2,  920701, 'p0601', 1, 2),     -- in a maintenance window -> 4
    (920004, 'p0601-h04-expired',       2,  920701, 'p0601', 1, 4),     -- window expired -> 2
    (920005, 'p0601-h05-closed-tkt',    2,  920701, 'p0601', 1, 2),     -- window on a CLOSED ticket -> unchanged
    (920006, 'p0601-h06-flags-zero',    2,  920701, 'p0601', 1, 2),     -- maintenance_window with all flags 0 -> unchanged
    (920007, 'p0601-h07-os21',          21, 920701, 'p0601', 1, NULL),  -- operating system 21 -> excluded
    (920008, 'p0601-h08-uptodate',      2,  920701, 'p0601', 1, 2),     -- unchanged (also the active host for links)
    (920009, 'p0601-h09-inactive',      2,  920701, 'p0601', 0, 3),     -- unchanged (also the inactive host for links)
    (920010, 'p0601-h10-two-windows',   2,  920701, 'p0601', 1, 2),     -- two qualifying tickets -> 4, max ticket id
    (920011, 'p0601-h11-future',        2,  920701, 'p0601', 1, 2),     -- window not started yet -> unchanged
    (920012, 'p0601-h12-cust-window',   2,  920701, 'p0601', 1, 4),     -- cust_maintenance_window, already 4 -> unchanged
    (920013, 'p0601-h13-no-mw-row',     2,  920701, 'p0601', 1, 2);     -- running service window with NO maintenance rows -> unchanged

-- tickets (all type 1; status 2 = open unless noted)
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, last_status_change_date) VALUES
    (920101, 1, 2,   920701, 920003, 0, now() - interval '1 hour'),
    (920102, 1, 2,   920701, 920004, 0, now() - interval '1 hour'),
    (920103, 1, 102, 920701, 920005, 0, now() - interval '1 hour'),   -- CLOSED
    (920104, 1, 2,   920701, 920006, 0, now() - interval '1 hour'),
    (920105, 1, 2,   920701, 920010, 0, now() - interval '1 hour'),
    (920106, 1, 2,   920701, 920010, 0, now() - interval '1 hour'),
    (920107, 1, 2,   920701, 920011, 0, now() - interval '1 hour'),
    (920108, 1, 2,   920701, 920012, 0, now() - interval '1 hour'),
    (920109, 1, 2,   920701, 920013, 0, now() - interval '1 hour');

-- service windows (one per ticket: tt.service_window.ticket_id is UNIQUE)
INSERT INTO tt.service_window (id, ticket_id, start_date, end_date, company_id) VALUES
    (920201, 920101, now() - interval '1 hour',  now() + interval '1 hour',   920701),  -- running
    (920202, 920102, now() - interval '2 hours', now() - interval '1 minute', 920701),  -- expired
    (920203, 920103, now() - interval '1 hour',  now() + interval '1 hour',   920701),  -- running, closed ticket
    (920204, 920104, now() - interval '1 hour',  now() + interval '1 hour',   920701),  -- running, flags 0
    (920205, 920105, now() - interval '1 hour',  now() + interval '1 hour',   920701),  -- running
    (920206, 920106, now() - interval '1 hour',  now() + interval '1 hour',   920701),  -- running
    (920207, 920107, now() + interval '1 hour',  now() + interval '2 hours',  920701),  -- future
    (920208, 920108, now() - interval '1 hour',  now() + interval '1 hour',   920701),  -- running, cust window
    (920209, 920109, now() - interval '1 hour',  now() + interval '1 hour',   920701);  -- running, no maintenance rows

INSERT INTO tt.host2service_window (host_id, service_window_id) VALUES
    (920003, 920201), (920004, 920202), (920005, 920203), (920006, 920204),
    (920010, 920205), (920010, 920206), (920011, 920207), (920012, 920208), (920013, 920209);

INSERT INTO tt.maintenance_window (id, service_window_id, disable_events, disable_conn_escalation) VALUES
    (920301, 920201, 1, 0),
    (920302, 920202, 1, 0),
    (920303, 920204, 0, 0),   -- all flags 0: NOT a maintenance window
    (920304, 920205, 0, 1),
    (920305, 920206, 0, 1),
    (920306, 920207, 1, 0);

INSERT INTO tt.cust_maintenance_window (id, service_window_id, disable_events, disable_conn_escalation) VALUES
    (920401, 920203, 0, 1),
    (920402, 920208, 1, 0);

-- ISP links: (id, router ip, event type, currency, sourcing type, stored maintenance status)
INSERT INTO mss.isp_link (id, router_ip_address1, event_type_id, currency_id, isp_link_sourcing_type_id, maintenance_status_id) VALUES
    (920501, 1, 10001, 1, 1, NULL),  -- iface on active h08           -> 2
    (920502, 1, 10001, 1, 1, NULL),  -- iface on inactive h09         -> 3
    (920503, 1, 10001, 1, 1, 2),     -- iface on h03 (window 920101)  -> 4
    (920504, 1, 10001, 1, 1, 2),     -- NO iface, status 2            -> obsolete -> 1
    (920505, 1, 10001, 1, 1, 1),     -- NO iface, status 1            -> untouched
    (920506, 1, 10001, 1, 1, NULL),  -- NO iface, status NULL         -> obsolete -> 1 (old 1)
    (920507, 1, 10001, 1, 1, 2),     -- iface on h08, status 2        -> unchanged
    (920508, 1, 10001, 1, 1, 3),     -- ifaces on h09 AND h08: MAX(active)=1 -> 2
    (920509, 1, 10001, 1, 1, 1),     -- iface on h08, status 1        -> re-derived -> 2
    (920510, 1, 10001, 1, 1, 4);     -- iface on h03, status 4        -> unchanged

INSERT INTO mss.interface (id, name, host_id, author, description, network_id) VALUES
    (920601, 'p0601-i01', 920008, 'p0601', 'p0601 iface', NULL),
    (920602, 'p0601-i02', 920009, 'p0601', 'p0601 iface', NULL),
    (920603, 'p0601-i03', 920003, 'p0601', 'p0601 iface', NULL),
    (920607, 'p0601-i07', 920008, 'p0601', 'p0601 iface', NULL),
    (920608, 'p0601-i08', 920009, 'p0601', 'p0601 iface', NULL),
    (920609, 'p0601-i09', 920008, 'p0601', 'p0601 iface', NULL),
    (920610, 'p0601-i10', 920008, 'p0601', 'p0601 iface', NULL),
    (920611, 'p0601-i11', 920003, 'p0601', 'p0601 iface', NULL);

INSERT INTO mss.interface2isp_link (interface_id, isp_link_id) VALUES
    (920601, 920501), (920602, 920502), (920603, 920503), (920607, 920507),
    (920608, 920508), (920609, 920508), (920610, 920509), (920611, 920510);

-------------------------------------------------------------------------------
-- update_host_maint_status (S-MAINT-002..006, S-MAINT-021)
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL mc.osag_maintsync_update_host_maint_status()$$,
    'S-MAINT-004: update_host_maint_status runs without error over the Section A hosts'
);

-- S-MAINT-003/005: NULL stored status, active, no window -> 2 with old status NVL -> 1
SELECT is(
    (SELECT maintenance_status_id FROM mss.host WHERE id = 920001),
    2::bigint,
    'S-MAINT-003: an active host in no maintenance window is set to status 2 (fixture started NULL)'
);
SELECT is(
    (SELECT count(*) FROM mc.host_maintenance_history
     WHERE host_id = 920001 AND new_maintenance_status_id = 2 AND old_maintenance_status_id = 1 AND ticket_id IS NULL),
    1::bigint,
    'S-MAINT-005: exactly one history row for the NULL->2 host, with old status NVL(NULL,1)=1 and no ticket'
);
SELECT ok(
    (SELECT id IS NOT NULL AND id > 0 FROM mc.host_maintenance_history WHERE host_id = 920001),
    'S-MAINT-005: the history row id comes from the sequence (not NULL, positive)'
);
SELECT ok(
    (SELECT change_date > now() - interval '1 minute' AND change_date <= now() + interval '1 second'
     FROM mc.host_maintenance_history WHERE host_id = 920001),
    'S-MAINT-005: the history row change_date is the current timestamp'
);

-- S-MAINT-003: inactive -> 3
SELECT is(
    (SELECT maintenance_status_id FROM mss.host WHERE id = 920002),
    3::bigint,
    'S-MAINT-003: an inactive host (active = 0) is set to status 3 regardless of windows (fixture started NULL)'
);
SELECT is(
    (SELECT count(*) FROM mc.host_maintenance_history
     WHERE host_id = 920002 AND new_maintenance_status_id = 3 AND old_maintenance_status_id = 1),
    1::bigint,
    'S-MAINT-005: one history row NULL->3 for the inactive host'
);

-- S-MAINT-002/003: running window with maintenance_window.disable_events = 1 -> 4 + ticket
SELECT is(
    (SELECT maintenance_status_id FROM mss.host WHERE id = 920003),
    4::bigint,
    'S-MAINT-002: an active host inside a running maintenance window (maintenance_window.disable_events = 1) is set to 4 (fixture started 2)'
);
SELECT is(
    (SELECT count(*) FROM mc.host_maintenance_history
     WHERE host_id = 920003 AND new_maintenance_status_id = 4 AND old_maintenance_status_id = 2 AND ticket_id = 920101),
    1::bigint,
    'S-MAINT-005: the 2->4 history row carries the maintenance ticket id 920101 and the real old status 2'
);

-- S-MAINT-002: expired window -> no longer in maintenance -> 2
SELECT is(
    (SELECT maintenance_status_id FROM mss.host WHERE id = 920004),
    2::bigint,
    'S-MAINT-002: a host whose maintenance window has ended (end_date in the past) goes back to 2 (fixture started 4)'
);
SELECT is(
    (SELECT count(*) FROM mc.host_maintenance_history
     WHERE host_id = 920004 AND new_maintenance_status_id = 2 AND old_maintenance_status_id = 4 AND ticket_id IS NULL),
    1::bigint,
    'S-MAINT-005: the 4->2 history row has old status 4 and no ticket'
);

-- S-MAINT-002: two qualifying tickets -> max(t.id)
SELECT is(
    (SELECT maintenance_status_id FROM mss.host WHERE id = 920010),
    4::bigint,
    'S-MAINT-002: a host in two running maintenance windows is set to 4'
);
SELECT is(
    (SELECT ticket_id FROM mc.host_maintenance_history WHERE host_id = 920010),
    920106::bigint,
    'S-MAINT-002: with two qualifying tickets the history row carries the HIGHEST ticket id (max(t.id))'
);

-- S-MAINT-002/004: the five "not a window" / "unchanged" / "excluded" hosts are untouched.
SELECT is(
    (SELECT maintenance_status_id FROM mss.host WHERE id = 920005),
    2::bigint,
    'S-MAINT-002: a running window on a CLOSED ticket (status_id 102, not < 101) is not a maintenance window -- host stays 2'
);
SELECT is(
    (SELECT maintenance_status_id FROM mss.host WHERE id = 920006),
    2::bigint,
    'S-MAINT-002: a maintenance_window row with disable_events = 0 and disable_conn_escalation = 0 is not a maintenance window -- host stays 2'
);
SELECT is(
    (SELECT maintenance_status_id FROM mss.host WHERE id = 920011),
    2::bigint,
    'S-MAINT-002: a service window that has not started yet (start_date in the future) is not a maintenance window -- host stays 2'
);
SELECT is(
    (SELECT maintenance_status_id FROM mss.host WHERE id = 920013),
    2::bigint,
    'S-MAINT-002: a running service window with neither a maintenance_window nor a cust_maintenance_window row is not a maintenance window -- host stays 2'
);
SELECT is(
    (SELECT maintenance_status_id FROM mss.host WHERE id = 920012),
    4::bigint,
    'S-MAINT-004: a host already at 4 inside a cust_maintenance_window (disable_events = 1) window is unchanged'
);
SELECT is(
    (SELECT maintenance_status_id FROM mss.host WHERE id = 920007),
    NULL::bigint,
    'S-MAINT-004: a host with operating_system_id 21 is excluded -- its NULL status stays NULL'
);
SELECT is(
    (SELECT count(*) FROM mc.host_maintenance_history
     WHERE host_id IN (920005, 920006, 920007, 920008, 920009, 920011, 920012, 920013)),
    0::bigint,
    'S-MAINT-004: no history row for any unchanged or excluded host'
);
SELECT is(
    (SELECT count(*) FROM mc.host_maintenance_history WHERE host_id BETWEEN 920001 AND 920013),
    5::bigint,
    'S-MAINT-005: exactly five history rows in total -- one per changed host (h01, h02, h03, h04, h10)'
);

-- S-MAINT-006: a failing INSERT inside the loop is logged with the fixed prefix and
-- swallowed; the call completes. Provoked on the FIRST (only) iteration by a primary-key
-- collision on mc.host_maintenance_history (the next sequence value is pre-inserted), so
-- Oracle and PostgreSQL agree on the outcome: nothing written.
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author, active, maintenance_status_id)
    VALUES (920026, 'p0601-h26-collision', 2, 920701, 'p0601', 1, NULL);
INSERT INTO mc.host_maintenance_history (id, host_id, change_date, new_maintenance_status_id, old_maintenance_status_id)
    VALUES (nextval('mc.host_maint_history_seq') + 1, 920008, now(), 2, 2);
SELECT lives_ok(
    $$CALL mc.osag_maintsync_update_host_maint_status()$$,
    'S-MAINT-006: update_host_maint_status does NOT raise when the history INSERT fails (WHEN OTHERS swallows)'
);
SELECT ok(
    (SELECT count(*) FROM osag.plog_stub_log
     WHERE levelname = 'ERR' AND message LIKE 'update_host_maint_status(): caught exception: %') >= 1,
    'S-MAINT-006: the failure is logged via plog.err with the prefix "update_host_maint_status(): caught exception: "'
);
SELECT is(
    (SELECT maintenance_status_id FROM mss.host WHERE id = 920026),
    NULL::bigint,
    'S-MAINT-006: the host whose history INSERT failed keeps its stored status (NULL)'
);
SELECT is(
    (SELECT count(*) FROM mc.host_maintenance_history WHERE host_id = 920026),
    0::bigint,
    'S-MAINT-006: no history row for the host whose INSERT failed'
);
DELETE FROM mc.host_maintenance_history WHERE host_id = 920008;   -- remove the collision row again

-------------------------------------------------------------------------------
-- update_isp_link_maint_status (S-MAINT-007..010, S-MAINT-021)
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL mc.osag_maintsync_update_isp_link_maint_status()$$,
    'S-MAINT-007: update_isp_link_maint_status runs without error over the Section A links'
);

SELECT is(
    (SELECT maintenance_status_id FROM mss.isp_link WHERE id = 920501),
    2::bigint,
    'S-MAINT-007: a NULL-status link attached to an active host in no window is set to 2'
);
SELECT is(
    (SELECT count(*) FROM mc.isp_link_maintenance_history
     WHERE isp_link_id = 920501 AND new_maintenance_status_id = 2 AND old_maintenance_status_id = 1 AND ticket_id IS NULL),
    1::bigint,
    'S-MAINT-008: one history row NULL->2 with old status NVL(NULL,1)=1 and no ticket'
);
SELECT ok(
    (SELECT change_date > now() - interval '1 minute' FROM mc.isp_link_maintenance_history WHERE isp_link_id = 920501),
    'S-MAINT-008: the ISP link history row change_date is the current timestamp'
);
SELECT ok(
    (SELECT count(*) FROM osag.plog_stub_log
     WHERE levelname = 'NOTICE'
       AND message = 'updating status for link 920501: new status is 2: old status is ') >= 1,
    'S-MAINT-008: plog.notice text for a NULL old status renders Oracle-style: "updating status for link 920501: new status is 2: old status is " (nothing after the colon)'
);
SELECT is(
    (SELECT maintenance_status_id FROM mss.isp_link WHERE id = 920502),
    3::bigint,
    'S-MAINT-003: a link whose only host is inactive is set to 3'
);
SELECT is(
    (SELECT maintenance_status_id FROM mss.isp_link WHERE id = 920503),
    4::bigint,
    'S-MAINT-002: a link whose host is inside a running maintenance window is set to 4 (fixture started 2)'
);
SELECT is(
    (SELECT count(*) FROM mc.isp_link_maintenance_history
     WHERE isp_link_id = 920503 AND new_maintenance_status_id = 4 AND old_maintenance_status_id = 2 AND ticket_id = 920101),
    1::bigint,
    'S-MAINT-008: the 2->4 link history row carries ticket 920101 and old status 2'
);
SELECT ok(
    (SELECT count(*) FROM osag.plog_stub_log
     WHERE levelname = 'NOTICE'
       AND message = 'updating status for link 920503: new status is 4: old status is 2') >= 1,
    'S-MAINT-008: plog.notice text "updating status for link 920503: new status is 4: old status is 2"'
);
SELECT is(
    (SELECT maintenance_status_id FROM mss.isp_link WHERE id = 920508),
    2::bigint,
    'S-MAINT-007: a link with one inactive and one active host is active (MAX(h.active) = 1) -> 2 (fixture started 3)'
);
SELECT is(
    (SELECT count(*) FROM mc.isp_link_maintenance_history
     WHERE isp_link_id = 920508 AND new_maintenance_status_id = 2 AND old_maintenance_status_id = 3),
    1::bigint,
    'S-MAINT-008: the 3->2 link history row has old status 3'
);
SELECT is(
    (SELECT maintenance_status_id FROM mss.isp_link WHERE id = 920509),
    2::bigint,
    'S-MAINT-007: an attached link at status 1 (unknown) is always re-derived -> 2'
);
SELECT is(
    (SELECT count(*) FROM mc.isp_link_maintenance_history
     WHERE isp_link_id = 920509 AND new_maintenance_status_id = 2 AND old_maintenance_status_id = 1),
    1::bigint,
    'S-MAINT-008: the 1->2 link history row has old status 1'
);
SELECT is(
    (SELECT maintenance_status_id FROM mss.isp_link WHERE id = 920507),
    2::bigint,
    'S-MAINT-007: an attached link already at its derived status (2) is unchanged'
);
SELECT is(
    (SELECT maintenance_status_id FROM mss.isp_link WHERE id = 920510),
    4::bigint,
    'S-MAINT-007: an attached link already at 4 inside a window is unchanged'
);
SELECT is(
    (SELECT count(*) FROM mc.isp_link_maintenance_history WHERE isp_link_id IN (920507, 920510, 920505)),
    0::bigint,
    'S-MAINT-007: no history row for the unchanged attached links nor for the unattached link already at 1'
);

-- S-MAINT-009: obsolete (unattached) links
SELECT is(
    (SELECT maintenance_status_id FROM mss.isp_link WHERE id = 920504),
    1::bigint,
    'S-MAINT-009: an unattached link at status 2 is reset to 1 (unknown)'
);
SELECT is(
    (SELECT count(*) FROM mc.isp_link_maintenance_history
     WHERE isp_link_id = 920504 AND new_maintenance_status_id = 1 AND old_maintenance_status_id = 2 AND ticket_id IS NULL),
    1::bigint,
    'S-MAINT-009: the obsolete-link history row is 2->1 with no ticket id'
);
SELECT is(
    (SELECT maintenance_status_id FROM mss.isp_link WHERE id = 920506),
    1::bigint,
    'S-MAINT-009: an unattached link with NULL status is set to 1'
);
SELECT is(
    (SELECT count(*) FROM mc.isp_link_maintenance_history
     WHERE isp_link_id = 920506 AND new_maintenance_status_id = 1 AND old_maintenance_status_id = 1),
    1::bigint,
    'S-MAINT-009: the NULL-status obsolete link gets a history row 1->1 (old status NVL(NULL,1))'
);
SELECT is(
    (SELECT maintenance_status_id FROM mss.isp_link WHERE id = 920505),
    1::bigint,
    'S-MAINT-009: an unattached link already at 1 stays 1'
);
SELECT is(
    (SELECT count(*) FROM mc.isp_link_maintenance_history WHERE isp_link_id BETWEEN 920501 AND 920510),
    7::bigint,
    'S-MAINT-008: exactly seven link history rows in total (L1, L2, L3, L4, L6, L8, L9)'
);

-- S-MAINT-010: failing INSERT -> logged with prefix, swallowed, nothing written.
INSERT INTO mss.isp_link (id, router_ip_address1, event_type_id, currency_id, isp_link_sourcing_type_id, maintenance_status_id)
    VALUES (920529, 1, 10001, 1, 1, NULL);
INSERT INTO mss.interface (id, name, host_id, author, description, network_id)
    VALUES (920629, 'p0601-i29', 920008, 'p0601', 'p0601 iface', NULL);
INSERT INTO mss.interface2isp_link (interface_id, isp_link_id) VALUES (920629, 920529);
INSERT INTO mc.isp_link_maintenance_history (id, isp_link_id, change_date, new_maintenance_status_id, old_maintenance_status_id)
    VALUES (nextval('mc.isp_link_maint_history_seq') + 1, 920507, now(), 2, 2);
SELECT lives_ok(
    $$CALL mc.osag_maintsync_update_isp_link_maint_status()$$,
    'S-MAINT-010: update_isp_link_maint_status does NOT raise when the history INSERT fails (WHEN OTHERS swallows)'
);
SELECT ok(
    (SELECT count(*) FROM osag.plog_stub_log
     WHERE levelname = 'ERR' AND message LIKE 'update_isp_link_maint_status(): caught exception: %') >= 1,
    'S-MAINT-010: the failure is logged via plog.err with the prefix "update_isp_link_maint_status(): caught exception: "'
);
SELECT is(
    (SELECT maintenance_status_id FROM mss.isp_link WHERE id = 920529),
    NULL::bigint,
    'S-MAINT-010: the link whose history INSERT failed keeps its stored status (NULL)'
);
SELECT is(
    (SELECT count(*) FROM mc.isp_link_maintenance_history WHERE isp_link_id = 920529),
    0::bigint,
    'S-MAINT-010: no history row for the link whose INSERT failed'
);
DELETE FROM mc.isp_link_maintenance_history WHERE isp_link_id = 920507;   -- remove the collision row again

-------------------------------------------------------------------------------
-- Section B fixtures (single-entity routines).
-------------------------------------------------------------------------------

INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author, active, maintenance_status_id) VALUES
    (920021, 'p0601-h21-null-active', 2,  920701, 'p0601', 1, NULL),  -- -> 2
    (920022, 'p0601-h22-window',      2,  920701, 'p0601', 1, 2),     -- window -> 4
    (920023, 'p0601-h23-uptodate',    2,  920701, 'p0601', 1, 2),     -- nothing to do (S-MAINT-012)
    (920024, 'p0601-h24-os21',        21, 920701, 'p0601', 1, NULL),  -- OS 21 -> logged, untouched
    (920025, 'p0601-h25-inactive',    2,  920701, 'p0601', 0, 2);     -- -> 3

INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, escalation_status_id, last_status_change_date)
    VALUES (920110, 1, 2, 920701, 920022, 0, now() - interval '1 hour');
INSERT INTO tt.service_window (id, ticket_id, start_date, end_date, company_id)
    VALUES (920210, 920110, now() - interval '1 hour', now() + interval '1 hour', 920701);
INSERT INTO tt.host2service_window (host_id, service_window_id) VALUES (920022, 920210);
INSERT INTO tt.maintenance_window (id, service_window_id, disable_events, disable_conn_escalation)
    VALUES (920307, 920210, 0, 1);

INSERT INTO mss.isp_link (id, router_ip_address1, event_type_id, currency_id, isp_link_sourcing_type_id, maintenance_status_id) VALUES
    (920521, 1, 10001, 1, 1, NULL),  -- iface on h08, NULL      -> 2 (S-MAINT-018)
    (920522, 1, 10001, 1, 1, 2),     -- iface on h08, up to date -> nothing (S-MAINT-017)
    (920523, 1, 10001, 1, 1, 2),     -- NO iface, status 2       -> 1 (S-MAINT-015)
    (920524, 1, 10001, 1, 1, 1),     -- NO iface, status 1       -> nothing (S-MAINT-015)
    (920525, 1, 10001, 1, 1, 2),     -- iface on h03 (window)    -> 4 + ticket (S-MAINT-019)
    (920526, 1, 10001, 1, 1, 2),     -- iface on inactive h09    -> 3 (S-MAINT-019)
    (920527, 1, 10001, 1, 1, 2),     -- iface on h08, up to date -- the S-MAINT-016 target
    (920528, 1, 10001, 1, 1, 2);     -- iface on h09, NEEDS 3    -- the S-MAINT-016 bystander

INSERT INTO mss.interface (id, name, host_id, author, description, network_id) VALUES
    (920621, 'p0601-i21', 920008, 'p0601', 'p0601 iface', NULL),
    (920622, 'p0601-i22', 920008, 'p0601', 'p0601 iface', NULL),
    (920625, 'p0601-i25', 920003, 'p0601', 'p0601 iface', NULL),
    (920626, 'p0601-i26', 920009, 'p0601', 'p0601 iface', NULL),
    (920627, 'p0601-i27', 920008, 'p0601', 'p0601 iface', NULL),
    (920628, 'p0601-i28', 920009, 'p0601', 'p0601 iface', NULL);
INSERT INTO mss.interface2isp_link (interface_id, isp_link_id) VALUES
    (920621, 920521), (920622, 920522), (920625, 920525), (920626, 920526), (920627, 920527), (920628, 920528);

-------------------------------------------------------------------------------
-- update_single_host (S-MAINT-011..013)
-------------------------------------------------------------------------------

-- S-MAINT-012 (CORRECTED) first, while no update_single_host ERR line exists yet.
SELECT lives_ok(
    $$CALL mc.osag_maintsync_update_single_host(920023)$$,
    'S-MAINT-012: update_single_host succeeds for a host whose stored status already equals the derived one'
);
SELECT is(
    (SELECT maintenance_status_id FROM mss.host WHERE id = 920023),
    2::bigint,
    'S-MAINT-012: the up-to-date host keeps status 2'
);
SELECT is(
    (SELECT count(*) FROM mc.host_maintenance_history WHERE host_id = 920023),
    0::bigint,
    'S-MAINT-012: no history row for the up-to-date host'
);
SELECT is(
    (SELECT count(*) FROM osag.plog_stub_log WHERE message LIKE 'update_single_host(): caught exception: %'),
    0::bigint,
    'S-MAINT-012: the nothing-to-do case logs NO "caught exception" line (Oracle logged ORA-01403 as an ERROR here)'
);

-- S-MAINT-011: NULL -> 2
SELECT lives_ok(
    $$CALL mc.osag_maintsync_update_single_host(920021)$$,
    'S-MAINT-011: update_single_host succeeds for an active host with NULL status'
);
SELECT is(
    (SELECT maintenance_status_id FROM mss.host WHERE id = 920021),
    2::bigint,
    'S-MAINT-011: update_single_host sets an active no-window host from NULL to 2'
);
SELECT is(
    (SELECT count(*) FROM mc.host_maintenance_history
     WHERE host_id = 920021 AND new_maintenance_status_id = 2 AND old_maintenance_status_id = 1 AND ticket_id IS NULL),
    1::bigint,
    'S-MAINT-011: one history row NULL->2 (old status NVL(NULL,1)=1, no ticket) for the single host'
);
SELECT ok(
    (SELECT id IS NOT NULL AND change_date > now() - interval '1 minute' FROM mc.host_maintenance_history WHERE host_id = 920021),
    'S-MAINT-011: the single-host history row has a sequence id and the current change_date'
);

-- S-MAINT-011: 2 -> 4 with ticket
SELECT lives_ok(
    $$CALL mc.osag_maintsync_update_single_host(920022)$$,
    'S-MAINT-011: update_single_host succeeds for a host inside a running maintenance window'
);
SELECT is(
    (SELECT maintenance_status_id FROM mss.host WHERE id = 920022),
    4::bigint,
    'S-MAINT-011: update_single_host sets a host in a maintenance window (disable_conn_escalation = 1) from 2 to 4'
);
SELECT is(
    (SELECT count(*) FROM mc.host_maintenance_history
     WHERE host_id = 920022 AND new_maintenance_status_id = 4 AND old_maintenance_status_id = 2 AND ticket_id = 920110),
    1::bigint,
    'S-MAINT-011: the 2->4 single-host history row carries ticket 920110'
);

-- S-MAINT-011: inactive -> 3
SELECT lives_ok(
    $$CALL mc.osag_maintsync_update_single_host(920025)$$,
    'S-MAINT-011: update_single_host succeeds for an inactive host'
);
SELECT is(
    (SELECT maintenance_status_id FROM mss.host WHERE id = 920025),
    3::bigint,
    'S-MAINT-011: update_single_host sets an inactive host from 2 to 3'
);
SELECT is(
    (SELECT count(*) FROM mc.host_maintenance_history
     WHERE host_id = 920025 AND new_maintenance_status_id = 3 AND old_maintenance_status_id = 2),
    1::bigint,
    'S-MAINT-011: the 2->3 single-host history row has old status 2'
);

-- S-MAINT-013: nonexistent host -> logged, swallowed, nothing written.
SELECT lives_ok(
    $$CALL mc.osag_maintsync_update_single_host(929999)$$,
    'S-MAINT-013: update_single_host does NOT raise for a nonexistent host id'
);
SELECT is(
    (SELECT count(*) FROM osag.plog_stub_log
     WHERE levelname = 'ERR' AND message LIKE 'update_single_host(): caught exception: %'),
    1::bigint,
    'S-MAINT-013: the nonexistent host is logged via plog.err with the prefix "update_single_host(): caught exception: "'
);
SELECT is(
    (SELECT count(*) FROM mc.host_maintenance_history WHERE host_id = 929999),
    0::bigint,
    'S-MAINT-013: no history row for a nonexistent host'
);

-- S-MAINT-013: operating system 21 -> logged, swallowed, nothing written.
SELECT lives_ok(
    $$CALL mc.osag_maintsync_update_single_host(920024)$$,
    'S-MAINT-013: update_single_host does NOT raise for a host with operating_system_id 21'
);
SELECT is(
    (SELECT count(*) FROM osag.plog_stub_log
     WHERE levelname = 'ERR' AND message LIKE 'update_single_host(): caught exception: %'),
    2::bigint,
    'S-MAINT-013: the OS-21 host adds a second "update_single_host(): caught exception: " ERR line'
);
SELECT is(
    (SELECT maintenance_status_id FROM mss.host WHERE id = 920024),
    NULL::bigint,
    'S-MAINT-013: the OS-21 host keeps its NULL status'
);
SELECT is(
    (SELECT count(*) FROM mc.host_maintenance_history WHERE host_id = 920024),
    0::bigint,
    'S-MAINT-013: no history row for the OS-21 host'
);

-------------------------------------------------------------------------------
-- update_single_isp_link (S-MAINT-014..019)
-------------------------------------------------------------------------------

-- S-MAINT-017 (CORRECTED): up-to-date attached link -> nothing. Runs before any
-- failing update_single_isp_link call, so the ERR-line count must be 0.
SELECT lives_ok(
    $$CALL mc.osag_maintsync_update_single_isp_link(920522)$$,
    'S-MAINT-017: update_single_isp_link succeeds for an attached link already at its derived status'
);
SELECT is(
    (SELECT maintenance_status_id FROM mss.isp_link WHERE id = 920522),
    2::bigint,
    'S-MAINT-017: the up-to-date attached link keeps status 2 (Oracle flipped it to 1)'
);
SELECT is(
    (SELECT count(*) FROM mc.isp_link_maintenance_history WHERE isp_link_id = 920522),
    0::bigint,
    'S-MAINT-017: no history row for the up-to-date attached link (Oracle wrote a 2->1 row)'
);
SELECT is(
    (SELECT count(*) FROM osag.plog_stub_log WHERE message LIKE 'update_single_isp_link(): caught exception: %'),
    0::bigint,
    'S-MAINT-017: the nothing-to-do case logs no "caught exception" line'
);
-- and calling it again still changes nothing (no flip-flop)
SELECT lives_ok(
    $$CALL mc.osag_maintsync_update_single_isp_link(920522)$$,
    'S-MAINT-017: a second call on the same up-to-date link succeeds'
);
SELECT is(
    (SELECT maintenance_status_id FROM mss.isp_link WHERE id = 920522),
    2::bigint,
    'S-MAINT-017: the second call leaves status 2 as well -- no flip-flop'
);
SELECT is(
    (SELECT count(*) FROM mc.isp_link_maintenance_history WHERE isp_link_id = 920522),
    0::bigint,
    'S-MAINT-017: still no history row after the second call'
);

-- S-MAINT-016 (CORRECTED): only p_isp_link_id is evaluated; a bystander link that
-- needs a change (920528: inactive host, status 2) influences nothing and is not written.
SELECT lives_ok(
    $$CALL mc.osag_maintsync_update_single_isp_link(920527)$$,
    'S-MAINT-016: update_single_isp_link(920527) succeeds while another link (920528) needs a change'
);
SELECT is(
    (SELECT maintenance_status_id FROM mss.isp_link WHERE id = 920527),
    2::bigint,
    'S-MAINT-016: the target link keeps its own derived status 2 (Oracle would have applied the bystander''s 3 to it)'
);
SELECT is(
    (SELECT count(*) FROM mc.isp_link_maintenance_history WHERE isp_link_id IN (920527, 920528)),
    0::bigint,
    'S-MAINT-016: neither the target nor the bystander link gets a history row'
);
SELECT is(
    (SELECT maintenance_status_id FROM mss.isp_link WHERE id = 920528),
    2::bigint,
    'S-MAINT-016: the bystander link is not written by a call for another link'
);

-- S-MAINT-018 (CORRECTED): attached link with NULL status -> derived status, not 1.
SELECT lives_ok(
    $$CALL mc.osag_maintsync_update_single_isp_link(920521)$$,
    'S-MAINT-018: update_single_isp_link succeeds for an attached link with NULL status'
);
SELECT is(
    (SELECT maintenance_status_id FROM mss.isp_link WHERE id = 920521),
    2::bigint,
    'S-MAINT-018: an attached NULL-status link on an active host gets 2 (Oracle''s `= NULL` test set it to 1)'
);
SELECT is(
    (SELECT count(*) FROM mc.isp_link_maintenance_history
     WHERE isp_link_id = 920521 AND new_maintenance_status_id = 2 AND old_maintenance_status_id = 1 AND ticket_id IS NULL),
    1::bigint,
    'S-MAINT-018: one history row NULL->2 with old status NVL(NULL,1)=1'
);

-- S-MAINT-015: unattached links.
SELECT lives_ok(
    $$CALL mc.osag_maintsync_update_single_isp_link(920523)$$,
    'S-MAINT-015: update_single_isp_link succeeds for an unattached link at status 2'
);
SELECT is(
    (SELECT maintenance_status_id FROM mss.isp_link WHERE id = 920523),
    1::bigint,
    'S-MAINT-015: an unattached link at status 2 is set to 1 (unknown)'
);
SELECT is(
    (SELECT count(*) FROM mc.isp_link_maintenance_history
     WHERE isp_link_id = 920523 AND new_maintenance_status_id = 1 AND old_maintenance_status_id = 2 AND ticket_id IS NULL),
    1::bigint,
    'S-MAINT-015: the unattached link history row is 2->1 with no ticket'
);
SELECT lives_ok(
    $$CALL mc.osag_maintsync_update_single_isp_link(920524)$$,
    'S-MAINT-015: update_single_isp_link succeeds for an unattached link already at 1'
);
SELECT is(
    (SELECT maintenance_status_id FROM mss.isp_link WHERE id = 920524),
    1::bigint,
    'S-MAINT-015: an unattached link already at 1 stays 1'
);
SELECT is(
    (SELECT count(*) FROM mc.isp_link_maintenance_history WHERE isp_link_id = 920524),
    0::bigint,
    'S-MAINT-015: no history row for an unattached link already at 1'
);
SELECT is(
    (SELECT count(*) FROM osag.plog_stub_log WHERE message LIKE 'update_single_isp_link(): caught exception: %'),
    0::bigint,
    'S-MAINT-015: the unattached-link cases log no "caught exception" line (NO_DATA_FOUND is handled locally)'
);

-- S-MAINT-019: attached links that need a change.
SELECT lives_ok(
    $$CALL mc.osag_maintsync_update_single_isp_link(920525)$$,
    'S-MAINT-019: update_single_isp_link succeeds for a link whose host is in a maintenance window'
);
SELECT is(
    (SELECT maintenance_status_id FROM mss.isp_link WHERE id = 920525),
    4::bigint,
    'S-MAINT-019: a link whose host is inside a running maintenance window is set to 4 (fixture started 2)'
);
SELECT is(
    (SELECT count(*) FROM mc.isp_link_maintenance_history
     WHERE isp_link_id = 920525 AND new_maintenance_status_id = 4 AND old_maintenance_status_id = 2 AND ticket_id = 920101),
    1::bigint,
    'S-MAINT-019: the 2->4 single-link history row carries ticket 920101 and old status 2'
);
SELECT ok(
    (SELECT id IS NOT NULL AND change_date > now() - interval '1 minute' FROM mc.isp_link_maintenance_history WHERE isp_link_id = 920525),
    'S-MAINT-019: the single-link history row has a sequence id and the current change_date'
);
SELECT lives_ok(
    $$CALL mc.osag_maintsync_update_single_isp_link(920526)$$,
    'S-MAINT-019: update_single_isp_link succeeds for a link whose only host is inactive'
);
SELECT is(
    (SELECT maintenance_status_id FROM mss.isp_link WHERE id = 920526),
    3::bigint,
    'S-MAINT-019: a link whose only host is inactive is set to 3 (fixture started 2)'
);
SELECT is(
    (SELECT count(*) FROM mc.isp_link_maintenance_history
     WHERE isp_link_id = 920526 AND new_maintenance_status_id = 3 AND old_maintenance_status_id = 2 AND ticket_id IS NULL),
    1::bigint,
    'S-MAINT-019: the 2->3 single-link history row has old status 2 and no ticket'
);

-- S-MAINT-014: nonexistent link -> logged, swallowed, nothing written.
SELECT lives_ok(
    $$CALL mc.osag_maintsync_update_single_isp_link(929998)$$,
    'S-MAINT-014: update_single_isp_link does NOT raise for a nonexistent link id'
);
SELECT is(
    (SELECT count(*) FROM osag.plog_stub_log
     WHERE levelname = 'ERR' AND message LIKE 'update_single_isp_link(): caught exception: %'),
    1::bigint,
    'S-MAINT-014: the nonexistent link is logged via plog.err with the prefix "update_single_isp_link(): caught exception: "'
);
SELECT is(
    (SELECT count(*) FROM mc.isp_link_maintenance_history WHERE isp_link_id = 929998),
    0::bigint,
    'S-MAINT-014: no history row for a nonexistent link'
);

-------------------------------------------------------------------------------
-- S-MAINT-021: the batch loops hold a row lock on the rows they iterate -- observable
-- as the translation's query text carrying FOR UPDATE OF the base table alias.
-------------------------------------------------------------------------------

SELECT ok(
    (SELECT prosrc ~* 'FOR UPDATE OF h\M' FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'mc' AND p.proname = 'osag_maintsync_update_host_maint_status'),
    'S-MAINT-021: update_host_maint_status iterates its hosts FOR UPDATE OF h'
);
SELECT ok(
    (SELECT (regexp_count(prosrc, 'FOR UPDATE OF l\M', 1, 'i')) = 2 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'mc' AND p.proname = 'osag_maintsync_update_isp_link_maint_status'),
    'S-MAINT-021: update_isp_link_maint_status iterates both of its link cursors FOR UPDATE OF l'
);

SELECT * FROM finish();
ROLLBACK;
