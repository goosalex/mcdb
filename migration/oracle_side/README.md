# Oracle side of the TT-only split

**Scope.** Branch `phoenix/migrate_tt_only` moves the ticketing schemas — `TT` (34 tables,
7 packages, 2 triggers, 3 scheduler jobs) and `TICKETEVOLUTION` (3 tables, 1 package,
1 job) — to PostgreSQL while every other schema stays on Oracle 19c for now. This
directory holds what the **Oracle** side needs so that the code staying behind keeps
compiling and behaving: stubs (façade packages with the original signatures), the
external-call bridge they use, a read replica for the one TT query the Oracle side
runs itself, and the pruning list.

**Nothing in this directory has been executed against an Oracle instance** (none is
available to this project — see `.planning/STATE.md`, blocker ORA-01). Every file is
written to Oracle 19c syntax from the Oracle sources in `ddl/src/`, and must be
compiled and tested on the Oracle dev instance before use. Treat it as a reviewed draft,
not as verified code.

## What stays on Oracle and touches TT (from `.planning/reports/tt-callers-2026-10-14.html`)

| Caller (stays on Oracle) | Needs from TT | Mechanism here |
|---|---|---|
| `MC.MONITORING_TICKET_PROCESSES` (wave 5) | `event_interface.newevent_new/addevent_new`, `ticket_interface.change_status/change_subject`, `escalation_interface.clear_customer_escalation`; reads `tt.event`/`tt.ticket` directly (2 sites) | stub packages → bridge (write); `TT.V_EVENT_MIN` replica view (read) |
| `NIDS.OSAG_NIDS` (wave 4) | `event_interface.addevent_new/exec_event_type_actions/ticket_type_for_event_type`, `ticket_interface.newticket_new`; reads `tt.event_type` (1) and the maintenance-window join (2) | stubs → bridge; `ticket_type_for_event_type` stays **local** (pure function, no DB access — copied verbatim); `TT.V_HOST_MAINTENANCE` replica |
| `GUMA2.SECONDARY_ISP`, `GUMA2.OSAG_GUMA`, `OSIXINFO.OSAG_HARDWARE` (wave 4) | `event_interface.newevent_new`; `SECONDARY_ISP` reads `tt.ticket` (1 cursor) | stub → bridge; `TT.V_TICKET_MIN` replica view |
| `AUTH.OSAG_AUTH.delete_login` | `osag_notify.delete_notifications_for_login` | stub → bridge |
| `MC.MONITORING.has_active_SW`, `MC.OSAG_MAINTSYNC` (4 sites) | the 5-table maintenance-window join, read-only | `TT.V_HOST_MAINTENANCE` replica view (one shared view replaces 7 copy-pasted joins) |
| `MC.V_HOST_CONNECTION_STATUS` | `tt.event.ticket_id` for one event id | `TT.V_EVENT_MIN` replica |
| 12 `BIREADER.V_TT_*` views | 1:1 wrappers over TT tables | **drop on Oracle**; BIREADER gets a PostgreSQL role and reads the tables there (reporting must not read a replica of a replica) |
| 31 service accounts with direct grants (`SVC_API_TICKETING`, `MCA`, `SVC_MC_PORTAL`, `DECOMM`, `MCMGW`, `PERLTICKET`, `WEBSW`, ...) | tables + package EXECUTE | **move to PostgreSQL**: `ddl/migrated/grants/<ACCOUNT>.sql` restricted to TT/TICKETEVOLUTION objects, package EXECUTE fanned out per routine via `migration/mapping/rewrite_names.py --report` (P1 items). Their SQL goes through `client-rename.sed`. |

## Transport decision: synchronous HTTPS bridge, not DB links, not an outbox

The nine write entry points are called **inside** Oracle transactions whose later
statements depend on the result (`newevent_new` returns the event id that
`MC.MONITORING_TICKET_PROCESSES` then stores in `mc.isp_link_history.event_id`;
`new_event_up` chains `addevent_new → clear_customer_escalation → change_status` in
order). An asynchronous outbox would break both. The options were:

1. **Oracle Database Gateway for ODBC + DB link** (`DBMS_HS_PASSTHROUGH`): synchronous,
   but OUT parameters and PostgreSQL `CALL` are awkward through HS, it needs a gateway
   installation on the Oracle host, and it couples Oracle's transaction to PostgreSQL's
   without two-phase commit anyway.
2. **Synchronous HTTPS call** (`UTL_HTTP` → small `tt-bridge` service → `CALL` on
   PostgreSQL, JSON in/out): synchronous, returns OUT values, one network ACL and one
   wallet on Oracle, the service is trivially testable, and it is the same shape the
   existing `SVC_API_TICKETING` account implies already exists for the application tier.
   **Chosen.** `tt_bridge.sql` implements the Oracle half; the service is a ~100-line
   HTTP→libpq shim (not in this repo; contract below).
3. **Outbox table + poller**: rejected for the ordering/return-value reasons above. It
   remains the right shape for *fire-and-forget* notifications only, and PostgreSQL-side
   `osag.msg_outbox` (OSAG_MSG) uses exactly that.

**Transactional caveat (must be understood by every reviewer):** a bridge call commits
on PostgreSQL when the PostgreSQL `CALL` returns; if the Oracle transaction later rolls
back, the ticket/event stays. Oracle's own autonomous-transaction `plog` had the same
property, and every caller above already treats the TT call as a side effect it does
not undo. Callers that need atomicity across both databases do not exist in the
corpus (verified against the 16 call sites in the callers report).

## Bridge contract (`tt-bridge` service)

```
POST /call/<pg_schema>.<pg_routine>          e.g. /call/tt.event_interface_newevent_new
Authorization: Bearer <token from TT.BRIDGE_CONFIG>
Content-Type: application/json
{"args": {"p_type_id": 10003, "p_host_id": 4711, "p_details_public": "...", ...}}

200 {"out": {"p_event_id": 123456}}
409 {"sqlstate": "OS980", "message": "Ticket with id 42 is closed/deleted"}
4xx/5xx {"sqlstate": "...", "message": "..."}
```

- Named arguments only (the service builds `CALL routine(p_type_id => $1, ...)` from the
  keys; unknown keys are rejected, defaults apply for omitted ones — exactly Oracle's
  named-notation semantics the stubs rely on).
- Booleans are JSON booleans; dates are ISO-8601 strings in `Europe/Zurich`; numbers
  are JSON numbers (NUMBER → numeric, no precision loss for ids).
- Every error carries the PostgreSQL SQLSTATE. `TT.BRIDGE.raise_mapped` turns it back
  into the Oracle error the caller expects (`OS980` → `-20980 ticket_closed`, `P0002` →
  `NO_DATA_FOUND`, `P0003` → `TOO_MANY_ROWS`, anything else → `-20999` with the text).

## Read path: replica tables, refreshed by the same bridge

Seven Oracle-side read sites use one 5-table join (`tt.ticket` × `service_window` ×
`host2service_window` × `maintenance_window` × `cust_maintenance_window`) to answer "is
host H inside an active maintenance window, and does it disable events / collect
events / which ticket". `tt_maintenance_replica.sql` replaces all seven with one view
`TT.V_HOST_MAINTENANCE` over a replica table `TT.HOST_MAINTENANCE_STATE` that the bridge
refreshes every minute (`MC.OSAG_MAINTSYNC` runs on a minute cadence anyway; the join
result is tiny — one row per host with an active window). Two more minimal replicas
(`TT.V_EVENT_MIN`: event id → ticket id/type/subject; `TT.V_TICKET_MIN`: open tickets by
host/type/status) cover `MC.V_HOST_CONNECTION_STATUS`, `MC.MONITORING_TICKET_PROCESSES`'s
two direct selects and `GUMA2.SECONDARY_ISP`'s cursor. **The seven packages'
own SQL must be edited** to use the views — the exact sites are listed in
`tt_maintenance_replica.sql`'s header; they are 1-for-1 replacements of the join by
`SELECT ... FROM tt.v_host_maintenance WHERE host_id = :h`.

## Cross-schema foreign keys (the structural cost of the split)

`ddl/migrated/constraints/fk-constraints.pg.sql` shows **22 FKs from non-TT tables into
TT** (`tt.ticket.id` from CERTS, CHECKLIST, FW×3, FYI, MC×3, MCAUDIT, MSS, NIDS, PRX, TIM×2;
`tt.event.id` from MC×2, NIDS; `tt.event_type.id` / `tt.event_notification_type.id` from
MSS) and **25 FKs from TT out to STOP/MSS/AUTH/MC**. After the split:

- Inbound FKs are **dropped on Oracle** (`prune.sql`); the columns stay as logical
  references. `tt.ticket_interface_deleteticket` today runs 13 cross-schema statements
  (`ddl/src/pkgb/tt_ticket_interface.sql:2443-2480`: `fw.rule2ticket`,
  `fw.source_nat_rule2ticket`, `fw.destination_nat_rule2ticket`, `fw.change`,
  `nids.ticket2rule`, `prx.prx_policy_item`, `mcaudit.record`, `mc.isp_link_history`,
  `mc.isp_link_maintenance_history`, `mc.host_maintenance_history`,
  `mss.installation_project_item`, `mss.deleted_host2service_window`,
  `guma2.suppressed_signature`) and `merge_tickets` one (line 1630,
  `guma2.suppressed_signature`). Those cannot run on PostgreSQL against Oracle tables.
  Decision recorded in the scoping report: they become **outbound bridge calls to the
  Oracle-side `TT.BRIDGE_CALLBACK.on_ticket_deleted(p_ticket_id, p_event_ids)` /
  `on_tickets_merged(p_from, p_into)`** (in `tt_stubs.sql`, statements copied verbatim
  with their source line numbers), invoked by the PostgreSQL side through an HTTP call
  at the end of `deleteticket`/`merge_tickets`. Until that lands, the PostgreSQL
  translations keep the statements (no-ops against empty replica tables) and the
  FINDINGS of both routines flag it.
- Outbound FKs need the referenced reference data **in PostgreSQL**: `stop.company`,
  `stop.contact`, `stop.company_unit`, `mss.host`, `mss.deleted_host`, `mss.service`,
  `mss.service_type`, `mss.service_component`, `mss.software_release`, `mss.key`,
  `auth.login`, `mc.mc_file` — plus the tables the TT routines merely read
  (`mss.host2service`, `mss.isp_link`, `mss.address/city/country`, `mss.v_host_key_value`,
  `auth.permission`, `auth.mv_service_access`, `mc.isp_link_history`,
  `mc.connection_interrupt_open`, `guma2.suppressed_signature`). These are
  **replicated Oracle → PostgreSQL** (read-only in PostgreSQL, the FKs re-created as
  `NOT VALID` so replication lag never blocks a ticket insert). The replication job is
  the same `tt-bridge` service in the other direction (logical: periodic
  `SELECT` → `COPY`; the tables are small reference data except `stop.contact` and
  `mss.host`).

## Pruning list (Oracle objects that lose their purpose)

`prune.sql` drops, in order: the 3 TT scheduler jobs + the TICKETEVOLUTION job (they run
on PostgreSQL via `pg_cron`, see `migration/pgsql/_support/30_pg_cron_jobs.sql`), the 12
`BIREADER.V_TT_*` views, the 22 inbound FK constraints, the 7 TT package bodies and
specs (replaced by the stubs), the 2 TT triggers, and finally the 34 TT tables + 3
TICKETEVOLUTION tables **after** the data has been copied and verified (`ora2pg` data
export, `pg_migration/run_oradata2pg.sh`). `SYS.OSAG_TABLE_REDEFINITION` (Q13) is
untouched by this split and stays on Oracle.
