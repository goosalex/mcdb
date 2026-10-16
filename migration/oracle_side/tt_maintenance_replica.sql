--liquibase formatted sql logicalFilePath:oracle_side/tt_maintenance_replica.sql
--changeset phoenix:tt_replica runOnChange:true endDelimiter:/ splitStatements:true
-- =====================================================================================
-- Read replicas for the TT data the Oracle side still queries directly after the split.
-- Refreshed by the tt-bridge service (PostgreSQL -> Oracle, every 60 s; MERGE by key).
-- UNTESTED DRAFT -- no Oracle instance available (README.md).
--
-- Replaces these seven copy-pasted 5-table joins (line numbers in ddl/src/pkgb/):
--   mc_monitoring.sql:102              has_active_SW            -> SELECT count(*) FROM tt.v_host_maintenance WHERE host_id = :h
--   mc_osag_maintsync.sql:13, 81       c_maint_status_changed   -> JOIN tt.v_host_maintenance m ON m.host_id = h.id (LEFT JOIN, flag = m.host_id IS NOT NULL)
--   mc_osag_maintsync.sql:188, 252     update_single_*          -> same
--   nids_osag_nids.sql:203             disable-events check     -> SELECT count(*) ... WHERE host_id = :h AND disable_events = 1
--   nids_osag_nids.sql:229             collect-events ticket    -> SELECT MAX(ticket_id) ... WHERE host_id = :h AND collect_events = 1
-- and these direct selects:
--   mc_monitoring_ticket_processes.sql:23, 32, 109   tt.event / tt.ticket  -> tt.v_event_min / tt.v_ticket_min
--   guma2_secondary_isp.sql:366                       tt.ticket cursor      -> tt.v_ticket_min
--   nids_osag_nids.sql:274                            tt.event_type name    -> tt.event_type_ref (static reference copy)
--   MC.V_HOST_CONNECTION_STATUS                       tt.event.ticket_id    -> tt.v_event_min
-- =====================================================================================

-- One row per (host, active service window). Source query on PostgreSQL (the same
-- join every Oracle caller used, evaluated once where the data lives):
--   SELECT h2s.host_id, t.id AS ticket_id, s.id AS service_window_id, s.start_date, s.end_date,
--          GREATEST(COALESCE(m.disable_events,0), COALESCE(cm.disable_events,0)) AS disable_events,
--          GREATEST(COALESCE(m.collect_events,0), COALESCE(cm.collect_events,0)) AS collect_events
--   FROM tt.ticket t JOIN tt.service_window s ON s.ticket_id = t.id
--        JOIN tt.host2service_window h2s ON h2s.service_window_id = s.id
--        LEFT JOIN tt.maintenance_window m ON m.service_window_id = s.id
--        LEFT JOIN tt.cust_maintenance_window cm ON cm.service_window_id = s.id
--   WHERE t.status_id < 101 AND s.start_date < now() AND s.end_date > now();
CREATE TABLE tt.host_maintenance_state (
    host_id           NUMBER NOT NULL,
    ticket_id         NUMBER NOT NULL,
    service_window_id NUMBER NOT NULL,
    start_date        DATE   NOT NULL,
    end_date          DATE   NOT NULL,
    disable_events    NUMBER(1) DEFAULT 0 NOT NULL,
    collect_events    NUMBER(1) DEFAULT 0 NOT NULL,
    refreshed_at      DATE   DEFAULT SYSDATE NOT NULL,
    CONSTRAINT host_maintenance_state_pk PRIMARY KEY (host_id, service_window_id)
)
/
CREATE OR REPLACE VIEW tt.v_host_maintenance AS
SELECT host_id, ticket_id, service_window_id, start_date, end_date, disable_events, collect_events, refreshed_at
FROM tt.host_maintenance_state
WHERE start_date < SYSDATE AND end_date > SYSDATE   -- re-evaluated locally between refreshes
/

-- Minimal event / ticket projections for the five direct-select sites.
CREATE TABLE tt.event_min (
    id          NUMBER NOT NULL,
    ticket_id   NUMBER,
    type_id     NUMBER NOT NULL,
    host_id     NUMBER,
    eventdate   DATE,
    subject_changed NUMBER(1) DEFAULT 0 NOT NULL,   -- derived flag MC.resolve_isp_ticket counts (line 23)
    refreshed_at DATE DEFAULT SYSDATE NOT NULL,
    CONSTRAINT event_min_pk PRIMARY KEY (id)
)
/
CREATE OR REPLACE VIEW tt.v_event_min AS SELECT * FROM tt.event_min
/

CREATE TABLE tt.ticket_min (
    id          NUMBER NOT NULL,
    type_id     NUMBER NOT NULL,
    status_id   NUMBER NOT NULL,
    host_id     NUMBER,
    company_id  NUMBER,
    subject     VARCHAR2(256),
    open_date   DATE,
    refreshed_at DATE DEFAULT SYSDATE NOT NULL,
    CONSTRAINT ticket_min_pk PRIMARY KEY (id)
)
/
CREATE OR REPLACE VIEW tt.v_ticket_min AS SELECT * FROM tt.ticket_min
/

-- Static reference data the Oracle side reads by id (NIDS: event type name). Loaded
-- once from masterdata/TT/event_type.csv, refreshed with the others.
CREATE TABLE tt.event_type_ref (
    id   NUMBER        NOT NULL,
    name VARCHAR2(128) NOT NULL,
    CONSTRAINT event_type_ref_pk PRIMARY KEY (id)
)
/

-- A monitoring hook: MC.OSAG_MAINTSYNC must refuse to act on a stale replica.
CREATE OR REPLACE FUNCTION tt.replica_age_seconds RETURN NUMBER IS
    v_age NUMBER;
BEGIN
    SELECT NVL((SYSDATE - MIN(refreshed_at)) * 86400, 1e9) INTO v_age
    FROM (SELECT MAX(refreshed_at) refreshed_at FROM tt.host_maintenance_state
          UNION ALL SELECT MAX(refreshed_at) FROM tt.event_min
          UNION ALL SELECT MAX(refreshed_at) FROM tt.ticket_min);
    RETURN v_age;
END;
/
