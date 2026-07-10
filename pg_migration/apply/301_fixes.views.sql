SET search_path = mc,public;
CREATE OR REPLACE VIEW mc.v_host_connection_status (host_id, status, live_status, ticket_id) AS
SELECT host.id                                                                     host_id,
       (CASE
            WHEN host.active = 0 THEN 0
            ELSE
                (CASE
                     WHEN ((cio.down_date IS NOT NULL AND cio.down_date::text <> '')
                         AND
                           CAST(EXTRACT(EPOCH FROM (statement_timestamp() - cio.down_date) * 24 * 60)/60 AS BIGINT) > host.escalation_timeout)
                         THEN coalesce(cio.type_id, -1)
                     ELSE -1 END) END)                                             status,
       (CASE WHEN host.active = 0 THEN 0 ELSE coalesce(cio.type_id, -1) END)       live_status,
       (CASE
            WHEN coalesce(cio.event_id::text, '') = ''
                THEN NULL
            ELSE (SELECT ticket_id FROM tt.event e WHERE e.id = cio.event_id) END) ticket_id
FROM mss.host host
         LEFT OUTER JOIN mc.connection_interrupt_open cio ON (host.id = cio.host_id);


SET search_path = mc,public;
CREATE OR REPLACE VIEW mc.connection_interrupt
            (id, down_date, up_date, type_id, minutes, details, event_id, host_id, interrupt_review_status_id) AS
SELECT id,
       down_date,
       (CASE WHEN up_date < down_date THEN down_date ELSE up_date END)              up_date,
       type_id,
       CAST((CASE WHEN up_date < down_date THEN 0 ELSE minutes END) as numeric(22)) minutes,
       details,
       event_id,
       host_id,
       INTERRUPT_REVIEW_STATUS_ID
FROM mc.connection_interrupt_closed

UNION ALL

SELECT id,
       down_date,
       up_date,
       type_id,
       CAST((CASE
                 WHEN coalesce(up_date::text, '') = ''
                     THEN CAST(EXTRACT(EPOCH FROM (statement_timestamp() - down_date)) AS BIGINT) END) as numeric(22)) minutes,
       details,
       event_id,
       host_id,
       INTERRUPT_REVIEW_STATUS_ID
FROM mc.connection_interrupt_open;

-- TODO: Fix this, with https://stackoverflow.com/questions/58766398/error-ora-00001-for-ghost-column-sys-nc00008-in-oracle-sql-developer
-- SET search_path = bireader,public;
-- CREATE OR REPLACE VIEW bireader.v_tt_service_window (sys_nc00008$, sys_nc00009$, id, ticket_id, start_date, end_date, description, title, company_id) AS SELECT SYS_NC00008$, SYS_NC00009$, ID, TICKET_ID, START_DATE, END_DATE, DESCRIPTION, TITLE, COMPANY_ID FROM TT.SERVICE_WINDOW;


-- TODO: Fix missing MV: mss.mv_value_host_default
CREATE OR REPLACE VIEW mss.v_host_key_value (host_id, key_name, scope, object_id, string_value) AS
select distinct v.host_id,
                v.key_name             as key_name,
                CASE
                    WHEN v.n_scope = 1 THEN 'host'
                    WHEN v.n_scope = 2 THEN 'service'
                    WHEN v.n_scope = 3 THEN 'group'
                    WHEN v.n_scope = 4 THEN 'vpn'
                    WHEN v.n_scope = 5 THEN 'company'
                    ELSE 'default' END as scope,
                v.object_id,
                v.string_value
FROM (select v.*,
             min(v.n_scope) over (partition by v.HOST_ID, v.key_name) as min_scope
      from mss.mv_value_host_default v) v
where v.min_scope = v.n_scope;