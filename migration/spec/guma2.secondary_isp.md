---
oracle_schema: GUMA2
oracle_package: SECONDARY_ISP
pg_schema: guma2
pg_prefix: secondary_isp
clause_prefix: SISP
oracle_spec: ddl/src/pkg/guma2_secondary_isp.sql
oracle_body: ddl/src/pkgb/guma2_secondary_isp.sql
public_routines: 2
---

# GUMA2.SECONDARY_ISP — PostgreSQL spec

Per its header comment (`ddl/src/pkg/guma2_secondary_isp.sql:10-15`), this package
"contains the procedures making up the 'Secondary ISP Outage' logic" (MON-215) and its
two procedures "are only called by GUMA2.submit_msg()" — an external (gumaserver) caller;
no PL/SQL object in `ddl/src/` calls them (grep over `ddl/src/**` finds the names only
inside this package). Each procedure receives a host id, a syslog timestamp (never used,
S-SISP-001) and a nursed syslog line of the shape

    ... NURSE:SECONDARYISP:ALERT All tunnels down (interface=eth0, peers=1027|1028|1029) [state=Alert, observed=420s]

(`ddl/src/pkgb/guma2_secondary_isp.sql:63-64`), parses interface name, VPN peer host
ids and the observed duration out of it with a hand-rolled tokenizer, looks up the
interface's ISP link, and — if the link is WAN managed and the situation warrants it —
raises a TT event through `TT.EVENT_INTERFACE.newevent_new`: type **10050** ("ISP down")
for `secondaryisp_alert`, type **10100** ("connection up") for `secondaryisp_ok`
(`ddl/src/pkgb/guma2_secondary_isp.sql:10-14`). Every failure path is swallowed inside
the package (a package-private `E_ABORT` for the expected "ignore this message" cases,
`WHEN OTHERS` + `plog.err` for everything else): neither public procedure ever raises.

**This spec deliberately specifies CORRECTED behaviour at one site** (S-SISP-009,
`is_host_up`): the Oracle body queries `mc.mon_server_connection` with `mon_server_id IS
NULL`, a column that is part of the table's primary key and `NOT NULL`, so the query can
never return a row, every peer is reported "down", `is_secondaryisp_all_peers_down` is
always TRUE, and `secondaryisp_alert` has therefore NEVER raised a 10050 event in Oracle.
The body's own comment (lines 135-138) names the intended replacement query against
`mc.host_connection_status` — "not yet available" when written, available now. Per the
project owner's standing instruction (correct provably broken Oracle behaviour, annotate
the correction), S-SISP-009 specifies that intended query. Every other clause is
Oracle-faithful.

## Routines

### secondaryisp_alert

- **Oracle signature:** `PROCEDURE secondaryisp_alert(i_host_id mss.host.id%TYPE, i_logdate syslog_message.log_date%TYPE, i_data syslog_message.message%TYPE)`
- **PostgreSQL name:** `guma2.secondary_isp_secondaryisp_alert` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/guma2_secondary_isp.sql:22-26`
- **Defined:** `ddl/src/pkgb/guma2_secondary_isp.sql:281-347`
- Parses the `NURSE:SECONDARYISP:ALERT` line, resolves the named interface's ISP link,
  ignores the message (logged `plog.notice`, no event) if the link is not WAN managed or
  if all listed VPN peers are down, otherwise raises a 10050 event for the host via
  `newevent_new` with a composed public/private text. Swallows every error (`E_ABORT`
  silently, anything else via `plog.err`). Never raises.

### secondaryisp_ok

- **Oracle signature:** `PROCEDURE secondaryisp_ok(i_host_id mss.host.id%TYPE, i_logdate syslog_message.log_date%TYPE, i_data syslog_message.message%TYPE)`
- **PostgreSQL name:** `guma2.secondary_isp_secondaryisp_ok` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/guma2_secondary_isp.sql:28-32`
- **Defined:** `ddl/src/pkgb/guma2_secondary_isp.sql:352-442`
- Same parse and interface lookup; ignores the message if the link is not WAN managed
  or if the host has no unresolved ticket (`tt.ticket.status_id < 100`); otherwise raises
  a 10100 event for the host via `newevent_new`. Same swallow-everything shape; the
  `WHEN OTHERS` text differs from `secondaryisp_alert`'s (S-SISP-017). Never raises.

Private helpers (body only, not declared in the package spec, hence not part of the
public surface — S-SISP-018): `get_next_token` (line 20), `secondaryisp_parse_syslog`
(66), `is_host_up` (126), `secondaryisp_interface_info` (164),
`is_secondaryisp_all_peers_down` (194), `comma_join` (220), `pretty_print_host_id_list`
(238).

## Clauses

### S-SISP-001

- **routines:** secondaryisp_alert, secondaryisp_ok
- **claim:** Both public routines are Oracle `PROCEDURE`s with exactly three `IN`
  parameters — `i_host_id mss.host.id%TYPE` (NUMBER), `i_logdate
  syslog_message.log_date%TYPE` (DATE), `i_data syslog_message.message%TYPE` (CLOB in
  `GUMA2.SYSLOG_MESSAGE`) — no `OUT` parameter, no return value, no `COMMIT`/`ROLLBACK`,
  no `PRAGMA AUTONOMOUS_TRANSACTION`. `name-map.csv` carries `pg_kind=procedure` for
  both. **`i_logdate` is never referenced in either body** (the identifier appears only in
  the two signatures, lines 283 and 354): the event date is left to `newevent_new`'s
  `SYSDATE` default. `i_host_id` is passed to `secondaryisp_parse_syslog` (line 297/375)
  which never uses it either (lines 76-118 reference only `i_data`).
- **source:** `ddl/src/pkg/guma2_secondary_isp.sql:22-32`, `ddl/src/pkgb/guma2_secondary_isp.sql:281-285, 297, 352-356, 375`

### S-SISP-002

- **routines:** secondaryisp_alert, secondaryisp_ok
- **claim:** The tokenizer `get_next_token(i_delim, i_string, o_token OUT, o_rest OUT)`
  used by every parse step splits `i_string` at the FIRST occurrence of `i_delim`
  (`INSTR(i_string, i_delim, 1, 1)`, line 38): (a) delimiter not found → `o_token` =
  the whole string, `o_rest` = `NULL` (lines 41-44); (b) delimiter found at position
  `p > 1` → `o_token` = the first `p-1` characters (`substr(i_string, 0, p-1)`, line 47
  — Oracle treats position 0 as 1); delimiter found at position 1 → `o_token` stays
  `NULL` (line 46); (c) `o_rest` = everything after the delimiter (`substr(i_string, p +
  length(i_delim))`, line 51) ONLY IF at least one character follows it (line 50) —
  a delimiter at the very end leaves `o_rest` `NULL`, never `''`; (d) a `NULL`/empty
  `i_string` yields `o_token = o_rest = NULL` (Oracle's `LENGTH('')` is `NULL`, so line
  34's `= 0` test never fires, but every later condition is then `NULL`-false and both
  outputs keep their line 30-31 initial `NULL`s — same observable result). Its `WHEN
  OTHERS` arm logs `'SECONDARY_ISP.get_next_token(): unexpected error 99: ' || sqlerrm`
  and re-raises (lines 54-57); nothing in the body can realistically reach it.
- **source:** `ddl/src/pkgb/guma2_secondary_isp.sql:20-59`

### S-SISP-003

- **routines:** secondaryisp_alert, secondaryisp_ok
- **claim:** `secondaryisp_parse_syslog` applies S-SISP-002 six times, each step
  consuming the REST of the previous one: (1) up to `'NURSE:SECONDARYISP:'` (line 78);
  (2) up to `'(interface='` (85); (3) up to `', peers='` (92) — the token before it is
  `o_interface` (98); (4) up to `') [state='` (101) — the token before it is `o_peers`
  (107); (5) up to `'observed='` (110); (6) up to `']'` (117) — the token before it is
  `o_since` (118). For the canonical line `'Jul 29 16:51:27 v1 nursed:
  NURSE:SECONDARYISP:ALERT All tunnels down (interface=eth0, peers=1027|1028|1029)
  [state=Alert, observed=420s]'` (line 64) this yields `o_interface = 'eth0'`, `o_peers =
  '1027|1028|1029'`, `o_since = '420s'`. Text between the markers that is not captured
  (`'ALERT All tunnels down '`, `'Alert, '`) is discarded; the message prefix before
  `NURSE:SECONDARYISP:` is irrelevant. Step 6 is NOT checked: a line ending in
  `observed=420s` without `]` yields `o_since = '420s'` as well (S-SISP-002 (a)).
- **source:** `ddl/src/pkgb/guma2_secondary_isp.sql:63-64, 76-118`

### S-SISP-004

- **routines:** secondaryisp_alert, secondaryisp_ok
- **claim:** If any of parse steps 1-5 leaves the REST `NULL` (marker missing, or marker
  at the very end of the line), `secondaryisp_parse_syslog` logs via `plog.err` the text
  `'SECONDARY_ISP.secondaryisp_parse_syslog(): can''t  parse NURSE:SECONDARYISP:ALERT
  line (N): ' || i_data` — N is the step number 1..5, the wording (including the double
  space in `can't  parse` and the literal `ALERT` even when called from `secondaryisp_ok`)
  is identical for all five — and raises `E_ABORT`. Both public procedures catch
  `E_ABORT` with `NULL;` (lines 343-344, 438-439): the message is dropped silently apart
  from that one `plog.err` line — no interface lookup, no notice, no event, no exception
  to the caller. Checked by the tests: a line without `NURSE:SECONDARYISP:` (step 1) and a
  line without `, peers=` (step 3).
- **source:** `ddl/src/pkgb/guma2_secondary_isp.sql:79-82, 86-89, 93-96, 102-105, 111-114, 342-344, 437-439`

### S-SISP-005

- **routines:** secondaryisp_alert, secondaryisp_ok
- **claim:** `secondaryisp_interface_info(i_host_id, i_interface_name, ...)` resolves,
  in ONE `SELECT ... INTO`, `mss.interface.description`, `mss.isp_link.wan_managed` and
  the ISP company's `stop.company.name` by `mss.interface i JOIN mss.interface2isp_link
  i2isp ON i2isp.interface_id = i.id JOIN mss.isp_link isp ON isp.id = i2isp.isp_link_id
  JOIN stop.company ispc ON isp.company_id = ispc.id WHERE i.host_id = i_host_id AND
  i.name = i_interface_name`. Every join is INNER, so an interface whose ISP link has
  `company_id IS NULL` (nullable column, "the ISP company", Oracle DDL) yields NO row. The
  three outputs feed the event text (S-SISP-013/016): `wan_managed` gates it, the
  description is shown in parentheses after the interface name, the company name after
  `'ISP name:   '`.
- **source:** `ddl/src/pkgb/guma2_secondary_isp.sql:164-180`

### S-SISP-006

- **routines:** secondaryisp_alert, secondaryisp_ok
- **claim:** When the S-SISP-005 join finds no row (`NO_DATA_FOUND`: no such interface
  on that host, no `interface2isp_link` row, missing `isp_link`, or `isp_link.company_id`
  `NULL`/dangling), `secondaryisp_interface_info` logs via `plog.err` exactly
  `'SECONDARY_ISP.secondary_interface_info(): can''t get information about interface ' ||
  i_interface_name || ' of host ' || i_host_id` — note the prefix says
  `secondary_interface_info`, NOT the routine's real name `secondaryisp_interface_info`;
  the body text is authoritative and is reproduced verbatim — and raises `E_ABORT`, which
  the public procedures swallow silently (S-SISP-004): no notice, no event, no exception.
- **source:** `ddl/src/pkgb/guma2_secondary_isp.sql:172, 182-185`

### S-SISP-007

- **routines:** secondaryisp_alert, secondaryisp_ok
- **claim:** `mss.interface2isp_link`'s primary key is `(interface_id, isp_link_id)`, so
  one interface may be linked to SEVERAL ISP links and the S-SISP-005 `SELECT ... INTO`
  can raise `TOO_MANY_ROWS`. `secondaryisp_interface_info` handles only `NO_DATA_FOUND`
  (line 183); `TOO_MANY_ROWS` propagates to the public procedure's `WHEN OTHERS` arm,
  which logs via `plog.err` `'SECONDARY_ISP.secondaryisp_alert(): unexpected error 99: '
  || sqlerrm` (alert, line 346) / `'SECONDARY_ISP.secondaryisp_ok(): unexpected error: '
  || sqlerrm` (ok, line 441 — no "99") and returns normally: no event, no exception to
  the caller. The `sqlerrm` suffix is engine text (Oracle `ORA-01422: exact fetch returns
  more than requested number of rows`; PostgreSQL `query returned more than one row`) —
  tests pin the prefix only.
- **source:** `ddl/src/pkgb/guma2_secondary_isp.sql:174-186, 345-346, 440-441`

### S-SISP-008

- **routines:** secondaryisp_alert, secondaryisp_ok
- **claim:** If the interface's ISP link has `wan_managed = 0`, the message is ignored:
  `secondaryisp_alert` logs via `plog.notice` `'SECONDARY_ISP.secondaryisp_alert():
  Ignoring secondary ISP outage, because not WAN managed (host: ' || i_host_id || ',
  interface: ' || l_interface || ')'` (lines 304-307); `secondaryisp_ok` logs
  `'SECONDARY_ISP.secondaryisp_ok(): Ignoring secondary ISP ok event, because not WAN
  managed (host: ' || i_host_id || ', interface: ' || l_interface || ')'` (lines
  383-386). Both then raise `E_ABORT` → swallowed silently: no event, no exception. The
  test is `= 0` (the column is `NUMBER(1) DEFAULT 0 NOT NULL`), so any non-zero value
  (1) passes the gate. This check runs BEFORE the peers check (alert) / unresolved-ticket
  check (ok).
- **source:** `ddl/src/pkgb/guma2_secondary_isp.sql:303-307, 382-386`

### S-SISP-009

- **routines:** secondaryisp_alert
- **claim:** **CORRECTED BEHAVIOUR (Oracle defect).** `is_host_up(i_host_id)` returns
  TRUE iff connection monitoring reports the host as up, i.e. iff
  `mc.host_connection_status` has a row for `host_id = i_host_id` whose
  `con_int_type_id` is `NULL` or `0` (`MC.MONITORING_STATE.SANG_UP = 0`,
  `ddl/src/pkg/mc_monitoring_state.sql:38`; `MC.MONITORING.end_interrupt`'s own "service
  is UP" test is `nvl(v_status,0) = 0`, `ddl/src/pkgb/mc_monitoring.sql:459`); it returns
  FALSE when the row carries any other connection-interrupt type AND when no row exists
  at all (Oracle's `NO_DATA_FOUND` arm, "Host apparently doesn't exist! It certainly
  isn't up...", lines 151-153, preserved). *Oracle's actual behaviour, and why it is a
  defect:* the body queries `mc.mon_server_connection ... WHERE mon_server_id IS NULL AND
  host_id = i_host_id` (lines 140-142). `MON_SERVER_ID` is part of that table's primary
  key `(HOST_ID, MON_SERVER_ID)` and `NOT NULL` (Oracle export `ddl/export/schema.oracle.sql`
  line 126, and the migrated schema), so the predicate can never match: the `SELECT INTO`
  raises `NO_DATA_FOUND` for EVERY host and `is_host_up` is constantly FALSE. Hence
  `is_secondaryisp_all_peers_down` (S-SISP-010) is constantly TRUE and `secondaryisp_alert`
  has ALWAYS taken the S-SISP-011 "all peers down" exit — in Oracle a 10050 event is
  unreachable. The body's own comment (lines 135-138, "code using new
  mc.host_connection_status table (not yet available)") spells out the intended query —
  `SELECT conn.con_int_type_id ... FROM mc.host_connection_status conn WHERE conn.host_id
  = i_host_id` — and that table exists in the current schema and is maintained by
  `MC.MONITORING.collate_conn_status` (`ddl/src/pkgb/mc_monitoring.sql:615-623`). The
  correction uses that query. The "up" test is widened from the literal `IS NULL` (line
  144) to `COALESCE(con_int_type_id, 0) = 0` because `collate_conn_status` copies the raw
  monitoring-server status into `con_int_type_id` (NULL or 0 both mean SANG_UP, the two
  are treated as equal at `ddl/src/pkgb/mc_monitoring.sql:706`). The `WHEN OTHERS` arm
  (`plog.err('SECONDARY_ISP.is_host_up(): error: ' || sqlerrm)` + `E_ABORT`, lines
  154-156) is kept as written.
- **source:** `ddl/src/pkgb/guma2_secondary_isp.sql:126-157`, `ddl/src/pkgb/mc_monitoring.sql:459, 615-623, 706`, `ddl/src/pkg/mc_monitoring_state.sql:38`

### S-SISP-010

- **routines:** secondaryisp_alert
- **claim:** `is_secondaryisp_all_peers_down(i_peers)` tokenizes `i_peers` on `'|'`
  (S-SISP-002) and returns FALSE at the FIRST peer for which `is_host_up` (S-SISP-009)
  is TRUE; if no peer is up it returns TRUE. A `NULL`/empty peers string never enters the
  loop (`WHILE l_after_token IS NOT NULL`) and yields TRUE. Each token is converted with
  `TO_NUMBER` (line 207): a non-numeric token raises `VALUE_ERROR`, unhandled in this
  function, caught by `secondaryisp_alert`'s `WHEN OTHERS` (S-SISP-007 text `unexpected
  error 99`). A `NULL` token (leading `|`) becomes `NULL` and `is_host_up(NULL)` is FALSE
  (no row matches), so the loop continues.
- **source:** `ddl/src/pkgb/guma2_secondary_isp.sql:194-214`

### S-SISP-011

- **routines:** secondaryisp_alert
- **claim:** When `is_secondaryisp_all_peers_down(l_peers)` is TRUE (every listed peer
  is down or unknown — S-SISP-009/010), `secondaryisp_alert` logs via `plog.notice`
  `'SECONDARY_ISP.secondaryisp_alert(): Ignoring secondary ISP outage, because all peers
  down (host: ' || i_host_id || ', interface: ' || l_interface || ')'` and raises
  `E_ABORT` → swallowed: no event, no exception. The body's rationale (lines 309-310):
  "because this is likely the reason for all tunnels to be down". `secondaryisp_ok` has
  NO peers check (lines 388-402 explain why the OK side uses the unresolved-ticket test
  instead, S-SISP-015).
- **source:** `ddl/src/pkgb/guma2_secondary_isp.sql:309-314, 388-402`

### S-SISP-012

- **routines:** secondaryisp_alert, secondaryisp_ok
- **claim:** `pretty_print_host_id_list(i_peers)` turns `'ID1|ID2|ID3'` into
  `'name1, name2, name3'`: for each `'|'` token (S-SISP-002) it `TO_NUMBER`s the token,
  looks up `mss.host.name` by `id` (line 257-259) and appends it via `comma_join`
  (`io_string IS NULL` → the element alone, else `io_string || ', ' || element`, lines
  226-230); a token with no `mss.host` row appends `'unknown(hostid:' || l_host_id || ')'`
  instead (local `WHEN NO_DATA_FOUND`, lines 266-270). The accumulator is initialised to
  `''` (line 247), which in Oracle IS `NULL`, so the first element gets NO leading `', '`
  — Pitfall 2: a PostgreSQL port that keeps `''` would emit `', name1, name2'`. For a
  `NULL`/empty list the function returns `NULL` (Oracle) — the callers' `||` then simply
  omits it (S-SISP-019). The function is also called with the single host id
  (`pretty_print_host_id_list(i_host_id)`, lines 328/426), yielding that host's name.
- **source:** `ddl/src/pkgb/guma2_secondary_isp.sql:220-231, 238-274, 328, 426`

### S-SISP-013

- **routines:** secondaryisp_alert
- **claim:** When the parse succeeds, the link is WAN managed and at least one peer is
  up, `secondaryisp_alert` calls `TT.event_interface.newevent_new(l_event_id OUT, 10050,
  i_host_id, <public>, <private>)` with every other `newevent_new` parameter at its
  default (no contact, public event, `SYSDATE`, no ticket type / service component /
  company override). `<public>` is, with `CHR(10)` line breaks (a trailing `CHR(10)`
  included): `'Secondary ISP Outage'`, blank, `'All VPN tunnels through one ISP link are
  down. This could mean that the ISP link is down.'`, blank, `'Open Systems Mission
  Control will start the WAN Management ISP Down process.'`, blank, `'Host:       ' ||
  pretty_print_host_id_list(i_host_id)`, `'Interface:  ' || l_interface || ' (' ||
  l_interface_desc || ')'`, `'ISP name:   ' || l_isp_company`, `'VPN peers:  ' ||
  pretty_print_host_id_list(l_peers)`, `'Down since: ' || l_down_since`. `<private>` is
  `'This host is subscribed to WAN Management.'`, blank, `'To Do:'`, blank, `'Execute
  this process: https://control.open.ch/docs/x/wBlbB'`. Observable TT side effect (per
  `migration/spec/tt.event_interface.md`, S-EVENT-010/011/014 for a host with no recent
  automatic ticket): a new `tt.ticket` (type 1, subject `'ISP down'` = the event type's
  name, `host_id = i_host_id`, company = the host's `service_company_id`) and one
  `tt.event` row with `type_id = 10050`, `host_id = i_host_id`, `public_event = 1`,
  `details_public`/`details_private` equal to the two texts above.
- **source:** `ddl/src/pkgb/guma2_secondary_isp.sql:11, 316-340`

### S-SISP-014

- **routines:** secondaryisp_alert
- **claim:** `secondaryisp_alert` has ONE procedure-level `EXCEPTION` block with two
  arms: `WHEN E_ABORT THEN NULL;` (the expected ignore paths S-SISP-004/006/008/011 end
  here, silently) and `WHEN OTHERS THEN plog.err('SECONDARY_ISP.secondaryisp_alert():
  unexpected error 99: ' || sqlerrm)` (everything else — S-SISP-007, S-SISP-010's
  `VALUE_ERROR`, and ANY error propagating out of `newevent_new`, which has no handler
  of its own around most of its body). The procedure therefore NEVER raises to its caller.
  Transaction-scope note (recorded, not asserted): if `newevent_new` fails after it has
  already inserted a ticket, Oracle's handler leaves that partial insert in place, whereas
  a PL/pgSQL `EXCEPTION` block rolls the whole procedure body back — the PostgreSQL
  outcome (no half-created ticket) is the saner one; see Assumptions.
- **source:** `ddl/src/pkgb/guma2_secondary_isp.sql:342-347`

### S-SISP-015

- **routines:** secondaryisp_ok
- **claim:** After the WAN-managed gate, `secondaryisp_ok` opens the cursor `SELECT t.id
  FROM tt.ticket t WHERE t.status_id < 100 AND host_id = i_host_id ORDER BY t.id DESC`,
  fetches ONE row (the highest-id unresolved ticket of the host — any ticket type, any
  status below 100, i.e. not resolved/closed/merged/deleted) and closes it (lines
  404-406). If none exists (`l_unresolved_ticket_id IS NULL`), it logs via `plog.notice`
  `'SECONDARY_ISP.secondaryisp_ok(): Ignoring secondary ISP ok event, because no
  unresolved ticket was found (host: ' || i_host_id || ', interface: ' || l_interface ||
  ')'` and raises `E_ABORT` → swallowed: no event, no exception. The fetched ticket id is
  used ONLY for this existence test — it is NOT passed to `newevent_new` (S-SISP-016).
- **source:** `ddl/src/pkgb/guma2_secondary_isp.sql:365-371, 404-412`

### S-SISP-016

- **routines:** secondaryisp_ok
- **claim:** When the parse succeeds, the link is WAN managed and an unresolved ticket
  exists, `secondaryisp_ok` calls `TT.event_interface.newevent_new(l_event_id OUT, 10100,
  i_host_id, <public>, <private>)`, all other parameters defaulted. `<public>`, with
  `CHR(10)` breaks and a trailing `CHR(10)`: `'Secondary ISP OK'`, blank, `'One or more
  VPN tunnels through one ISP link are up. The ISP link is thus apparently up.'`, blank,
  `'The WAN Management ISP Down process will be stopped.'`, blank, `'Host:       ' ||
  pretty_print_host_id_list(i_host_id)`, `'Interface:  ' || l_interface || ' (' ||
  l_interface_desc || ')'`, `'ISP name:   ' || l_isp_company`, `'VPN peers:  ' ||
  pretty_print_host_id_list(l_peers)`, `'Up since:   ' || l_up_since`. `<private>`:
  `'To Do:'`, blank, `'Try to find a corresponding "Secondary ISP Outage" event. If there
  isn''t one, fast-resolve.'` (one apostrophe in the output). Where the event lands is
  `newevent_new`'s decision alone: for a host whose unresolved ticket is a recent
  automatically generated trouble ticket (the S-SISP-013 ticket), `newevent_new` appends
  the 10100 event to THAT ticket (`migration/spec/tt.event_interface.md`, S-EVENT-008/009
  "found recent ticket for automatically generated event") and moves it to status 3
  (hot); the observable result is one `tt.event` row with `type_id = 10100`, `host_id =
  i_host_id`, `ticket_id` = the outage ticket, and the two texts above.
- **source:** `ddl/src/pkgb/guma2_secondary_isp.sql:14, 414-436`

### S-SISP-017

- **routines:** secondaryisp_ok
- **claim:** `secondaryisp_ok`'s procedure-level handler mirrors S-SISP-014 — `WHEN
  E_ABORT THEN NULL;` and `WHEN OTHERS THEN plog.err(...)` — but its error text is
  `'SECONDARY_ISP.secondaryisp_ok(): unexpected error: ' || sqlerrm` (no `99`). The
  procedure never raises to its caller.
- **source:** `ddl/src/pkgb/guma2_secondary_isp.sql:357, 437-442`

### S-SISP-018

- **routines:** secondaryisp_alert, secondaryisp_ok
- **claim:** The package's public surface is exactly the two procedures declared in the
  spec (lines 22-32). The seven body-only helpers (`get_next_token` 20,
  `secondaryisp_parse_syslog` 66, `is_host_up` 126, `secondaryisp_interface_info` 164,
  `is_secondaryisp_all_peers_down` 194, `comma_join` 220, `pretty_print_host_id_list`
  238) are private: Oracle clients cannot call them, and the translation exposes them as
  `guma2.secondary_isp__<name>` with `EXECUTE` revoked from `PUBLIC` (the project's
  private-routine convention), never under a public `secondary_isp_<name>` name. The
  package body declares three constants/exceptions and NO mutable state (lines 8-14).
- **source:** `ddl/src/pkg/guma2_secondary_isp.sql:22-32`, `ddl/src/pkgb/guma2_secondary_isp.sql:8-14, 20, 66, 126, 164, 194, 220, 238`

### S-SISP-019

- **routines:** secondaryisp_alert, secondaryisp_ok
- **claim:** Every `||` in the event texts (S-SISP-013/016) and log lines (S-SISP-004/
  006/008/011/015) follows Oracle's NULL-as-empty concatenation: a `NULL` operand drops
  out and the REST of the text survives. Operands that CAN be `NULL` on a path that still
  reaches the text: `l_interface` (S-SISP-002 (b): marker `', peers='` directly after
  `'(interface='`), `pretty_print_host_id_list(l_peers)` (empty peers list, S-SISP-012),
  `l_down_since`/`l_up_since` (`observed=]`), `l_isp_company` (`stop.company.name` is
  nullable in the Oracle DDL). Example: an empty peers list yields the line `'VPN peers:
  '` followed by the line break, not a `NULL` event text. A PostgreSQL port must use
  `concat()`-style concatenation at every such site; `newevent_new` would otherwise
  receive a `NULL` public text and, for these event types, store a `NULL`
  `details_public`.
- **source:** `ddl/src/pkgb/guma2_secondary_isp.sql:305, 312, 322-339, 384, 410, 420-435`

## Checklist

### 1. Empty-string / NULL handling

String-typed values that take part in `IS NULL` checks, comparisons or `||`:

- `i_data` (CLOB parameter, both routines): consumed only by `get_next_token` via
  `secondaryisp_parse_syslog`. `''` is reachable from a PostgreSQL caller (Oracle collapses
  it to `NULL`). `LENGTH('')` is `NULL` in Oracle so line 34's early return never fires;
  the outcome for `''`/`NULL` is nevertheless "both outputs `NULL`" (S-SISP-002 (d)), and
  step 1 then aborts with the `(1)` message (S-SISP-004). Decision: the translation makes
  the empty check explicit (`i_string IS NULL OR length(i_string) = 0`) so `''` and `NULL`
  behave identically — same observable result as Oracle.
- `o_token`/`o_rest` of `get_next_token` (lines 30-52): initialised `NULL`; assigned from
  `substr` only under guards that make the result non-empty (position `> 1` for the token,
  "at least one character follows" for the rest). `''` is unreachable for both; the
  `IS NULL` tests on `l_after_token` (lines 79, 86, 93, 102, 111, 204, 250) therefore
  translate 1:1.
- `l_pretty_string := ''` (line 247) — the ONE genuine Pitfall-2 site: Oracle's `''` is
  `NULL`, so `comma_join`'s `io_string IS NULL` (line 226) is TRUE for the first element.
  Decision: initialise to `NULL` in PL/pgSQL (S-SISP-012).
- `i_interface_name` in `secondaryisp_interface_info`'s `i.name = i_interface_name` (line
  180): `NULL` (marker at position 1) matches nothing → `NO_DATA_FOUND` → S-SISP-006, same
  in both engines.
- All `||` sites (S-SISP-019): translation uses `concat()` where an operand can be `NULL`
  (`l_interface`, `l_interface_desc` is `NOT NULL`, `l_isp_company`, both
  `pretty_print_host_id_list` results, `l_down_since`/`l_up_since`, `sqlerrm` never
  `NULL`); plain `||` only where every operand is provably non-`NULL`.
- No string equality/inequality other than line 180 exists in the package (full body
  grep for `=`/`!=` against VARCHAR2 identifiers: only `i.name = i_interface_name`).

### 2. SELECT INTO strictness

Three `SELECT ... INTO` sites, matching the Phase 1 inventory's `select_into_sites`
`[140, 174, 257]` exactly. The cursor at lines 367-371/404-406 is an explicit
`OPEN`/`FETCH`/`CLOSE` (zero rows → variable stays `NULL`, never `NO_DATA_FOUND`) and is
translated as a `SELECT ... INTO` WITHOUT `STRICT` (plain PL/pgSQL `INTO` leaves the
variable `NULL` on zero rows — exactly the cursor's semantics) — or equivalently
`LIMIT 1`.

| # | line | routine | zero rows possible? | >1 row possible? | Oracle handler | translation |
|---|---|---|---|---|---|---|
| 1 | 140 | is_host_up | ALWAYS in Oracle (defect, S-SISP-009); after correction: yes (host not monitored) | no (`host_connection_status` PK is `host_id`) | local `WHEN NO_DATA_FOUND` → `RETURN FALSE`; `WHEN OTHERS` → `plog.err` + `E_ABORT` (150-156) | `STRICT` + same two-arm handler, corrected query |
| 2 | 174 | secondaryisp_interface_info | yes (S-SISP-006 cases) | **yes** (`interface2isp_link` PK `(interface_id, isp_link_id)`, S-SISP-007) | local `WHEN NO_DATA_FOUND` → `plog.err` + `E_ABORT` (182-185); `TOO_MANY_ROWS` unhandled → public `OTHERS` | `STRICT` + `NO_DATA_FOUND` handler only; `TOO_MANY_ROWS` propagates to the public handler as in Oracle |
| 3 | 257 | pretty_print_host_id_list | yes (unknown peer id) | no (`mss.host` PK) | local `WHEN NO_DATA_FOUND` → `'unknown(hostid:N)'` (266-270) | `STRICT` + same handler |

Inventory cross-check: `exception_handlers: NO_DATA_FOUND 3, TOO_MANY_ROWS 0, OTHERS 4`
— confirmed by reading (NDF at 151, 183, 267; OTHERS at 55, 154, 345, 440). No
externally reachable unhandled `NO_DATA_FOUND` exists (both public procedures end in
`WHEN OTHERS`), so the "no data found" message-parity shim is not needed anywhere.

### 3. Exception codes

No `RAISE_APPLICATION_ERROR` anywhere (inventory `raise_application_error: []`,
confirmed by reading the 445-line body). ONE named exception, package-private:
`E_ABORT` (declared line 8; raised at 81, 88, 95, 104, 113, 156, 185, 306, 313, 385,
411; caught at 343 and 438). It never leaves the package — both public procedures catch
it — so no Oracle client can observe it. Translation: `RAISE EXCEPTION ... USING ERRCODE
= 'OS020'` / `WHEN SQLSTATE 'OS020'`. **PROVISIONAL (XCUT-01):** `OS020` follows
`migration/mapping/sqlstate-map.md`'s precedent for unnumbered, control-flow-only
package exceptions (`MSS.OSAG_DBPROP_STATE.e_abort` → `OS000`); it is distinct from every
code in that table and from this plan's OSIXINFO codes (`OS010`/`OS011`,
`migration/spec/osixinfo.osag_hardware.md`) so a handler can never mistake one package's
abort for another's; adding the row to `sqlstate-map.md` is left to the phase's
integration plan (06-07) to avoid concurrent edits of the shared table. The two bare
re-raises: `get_next_token`'s `WHEN OTHERS ... RAISE` (57, practically unreachable) and
none other. Predefined exceptions that cross routine boundaries inside the package:
`NO_DATA_FOUND` (handled locally at every site), `TOO_MANY_ROWS` (site #2 → public
`OTHERS`), `VALUE_ERROR` from `TO_NUMBER` (lines 207, 253 → public `OTHERS`; PostgreSQL
`22P02 invalid_text_representation`, caught by the same `OTHERS`). Nothing escapes either
public procedure.

### 4. Package state

None mutable. The body's declare section (lines 4-14) holds `E_ABORT EXCEPTION` and two
`CONSTANT NUMBER`s (`C_SEC_ISP_OUTAGE_EVENT_TYPE := 10050`, `C_SEC_ISP_OK_EVENT_TYPE :=
10100`); no package-level variable, no trailing initialisation block (file ends `END
SECONDARY_ISP;` at line 444). The package spec declares no types or variables (lines
3-33). Matches the inventory's `package_state: []`, `has_init_block: false`. The two
constants are inlined as literals in the translation (commented with their Oracle names).

### 5. FUNCTION vs PROCEDURE

Both public routines are `PROCEDURE`s (`ddl/src/pkg/guma2_secondary_isp.sql:22, 28`);
`name-map.csv` says `pg_kind=procedure` for both. No `COMMIT`, `ROLLBACK` or `PRAGMA
AUTONOMOUS_TRANSACTION` in the body (inventory `has_commit: false`, `has_rollback:
false`, `autonomous_transaction: false`; confirmed by reading). Callers: none in
`ddl/src/**` (the header's "GUMA2.submit_msg()" is an external gumaserver entry point;
`grep -rn secondaryisp_alert ddl/src` finds only this package). Callee:
`TT.event_interface.newevent_new`, a `PROCEDURE` with a leading `OUT` parameter →
`CALL tt.event_interface_newevent_new(l_event_id, 10050, i_host_id, <public>,
<private>)` (OUT variable first). Private helpers: `is_host_up`,
`is_secondaryisp_all_peers_down`, `pretty_print_host_id_list` are Oracle `FUNCTION`s
(translated as `FUNCTION`s returning `boolean`/`varchar`), the rest `PROCEDURE`s; none
of them commits, so FUNCTION bodies calling `CALL osag.osag_plog_*` are fine (plog stub
performs no transaction control). No XCUT-04 collision.

## Assumptions / Unresolved

- **Deviation from Oracle is intentional at S-SISP-009 and nowhere else.** The
  `mon_server_id IS NULL` predicate is provably dead against the current primary key
  (`ddl/export/schema.oracle.sql:126`), the author's own comment names the replacement
  query, and the replacement table is live. Consequence for operations, which this spec
  cannot weigh: after migration, `secondaryisp_alert` WILL raise 10050 events for
  WAN-managed links whose peers are not all down — something production Oracle has never
  done since the primary key made the query dead. Whether MON-215's alert should be
  revived at all, or the whole "all peers down" check should rather be dropped, is a
  product decision for the project owner; the translation marks the site
  `-- DEVIATION(ORACLE-BUG)` and the tests assert the corrected behaviour.
- **`host_connection_status` "up" semantics** (`COALESCE(con_int_type_id, 0) = 0`) are
  taken from `MC.MONITORING`'s own code (`nvl(v_status,0) = 0`, `ddl/src/pkgb/mc_monitoring.sql:459`,
  and the NULL/0 equivalence at line 706), not from this package. If the monitoring team
  considers only `NULL` as "up", the correction would need the literal `IS NULL` test
  instead; recorded for 06-04 (MC.MONITORING translation) to confirm.
- **Log lines written immediately before `RAISE E_ABORT`** (S-SISP-004/006/008/009/011/
  015): Oracle's `plog` ran in an autonomous transaction
  (`ddl/src/pkgb/osag_osag_plog.sql:47, 54`), so the line survived the raise; the PostgreSQL
  plog stub is transactional (`migration/pgsql/osag/osag_plog.FINDINGS.md`) and the catching
  handler's subtransaction rollback would erase it. The translation lets `E_ABORT` carry its
  log line (exception message + level) and the public handler emits it once — same line, same
  level, same order, and since `E_ABORT` never leaves the package the line is always
  observable. Not a behavioural difference; recorded so the mechanic is not mistaken for one.
- **Message-text parity of `sqlerrm`** (S-SISP-007/014/017): the `unexpected error`
  log lines embed engine text that necessarily differs between Oracle and PostgreSQL;
  tests pin the fixed prefix only. Not a behavioural difference a client can observe
  (nothing is raised).
- **Transaction-scope delta on the S-SISP-014/017 `WHEN OTHERS` paths**: Oracle keeps
  DML already executed by `newevent_new` before the failure; PL/pgSQL's handler
  subtransaction undoes it. Not asserted; owned by XCUT-05.
- **The ISP company name is `stop.company.name`**, nullable in Oracle; the test fixture
  gives it a value. `mss.interface.description` is `NOT NULL` in both schemas, so
  `' (' || l_interface_desc || ')'` always carries text.
- **`i_logdate` is unused** (S-SISP-001) — the event timestamp is the processing time,
  not the syslog time. Whether that was intended cannot be known from source; preserved.
- Nothing else is unresolved: all three `SELECT INTO` sites, the cursor, all seven
  `E_ABORT` raise sites, both public handlers, both `newevent_new` call sites and the
  (constant-only) declare section were reviewed against the full text of both Oracle
  files; `tt.event_type` 10050/10100 exist in `masterdata/TT/event_type.csv`.
