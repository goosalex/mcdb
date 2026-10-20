# GUMA2.SECONDARY_ISP -- FINDINGS

**Source:** `ddl/src/pkg/guma2_secondary_isp.sql` (spec, 34 lines),
`ddl/src/pkgb/guma2_secondary_isp.sql` (body, 445 lines). **Spec:**
`migration/spec/guma2.secondary_isp.md` (19 clauses, S-SISP-001..019). **Target:**
`migration/pgsql/guma2/secondary_isp.sql`. **Tests:**
`migration/test/pgtap/guma2__secondary_isp__spec.sql` (76 assertions). No regress golden:
every error path is a logged swallow and the pgTAP file pins the exact log texts.

This is the first TT caller translated in phase 06 batch B: both public procedures call
`tt.event_interface_newevent_new` (event types 10050 "ISP down" and 10100 "connection up")
and the tests assert the TT side effects end to end (the ticket `newevent_new` opens for the
outage, the OK event appended to that same ticket and the ticket going hot).

## Deviations from Oracle (project-owner instruction: correct broken behaviour, annotate it)

One, marked `-- DEVIATION(ORACLE-BUG)` at the site and specified as corrected behaviour in
S-SISP-009; the tests assert the corrected contract.

| # | routine | Oracle behaviour (lines) | why it is broken | corrected behaviour |
|---|---|---|---|---|
| 1 | `is_host_up` (private, feeds `is_secondaryisp_all_peers_down` -> `secondaryisp_alert`) | `SELECT status INTO ... FROM mc.mon_server_connection WHERE mon_server_id IS NULL AND host_id = i_host_id` (140-142); `NO_DATA_FOUND` -> `RETURN FALSE` (151-153). | `MON_SERVER_ID` is part of the table's primary key `(HOST_ID, MON_SERVER_ID)` and `NOT NULL` (`ddl/export/schema.oracle.sql:126`, same in the migrated schema). The predicate can never match: every call raises `NO_DATA_FOUND`, every peer is "down", `is_secondaryisp_all_peers_down` is constantly TRUE and `secondaryisp_alert` has ALWAYS exited through the "Ignoring secondary ISP outage, because all peers down" notice. **A 10050 event is unreachable in Oracle.** The body's own comment (135-138) says "code using new mc.host_connection_status table (not yet available)" and spells out the intended query. | The intended query: `SELECT con_int_type_id FROM mc.host_connection_status WHERE host_id = i_host_id` (the table exists and is maintained by `MC.MONITORING.collate_conn_status`). "Up" = `COALESCE(con_int_type_id, 0) = 0`, which is `MC.MONITORING`'s own definition (`nvl(v_status,0) = 0`, `mc_monitoring.sql:459`; `SANG_UP = 0`, `mc_monitoring_state.sql:38`; NULL and 0 treated alike at `mc_monitoring.sql:706`) rather than the literal `IS NULL` of line 144. No row -> FALSE (Oracle's own `NO_DATA_FOUND` arm, kept). `WHEN OTHERS` arm kept. |

**Operational consequence the project owner must weigh (open question):** after migration,
`secondaryisp_alert` WILL raise 10050 events for WAN-managed links whose VPN peers are not
all down -- something production Oracle has never done since the primary key made the query
dead. Whether MON-215's alert should be revived, or the peers check dropped, or the whole
alert retired, is a product decision; the translation implements the author's documented
intent.

**NOT treated as defects, deliberately:**

- The `secondary_interface_info` prefix in the interface-lookup error (line 172 names a
  routine that does not exist; the real name is `secondaryisp_interface_info`): log text,
  reproduced verbatim (S-SISP-006).
- `i_logdate` unused in both procedures (S-SISP-001): the event date is the processing time.
  Preserved.
- The parse error text says `NURSE:SECONDARYISP:ALERT line (N)` even when called from
  `secondaryisp_ok` (S-SISP-004). Preserved.
- `secondaryisp_ok` checks for an unresolved ticket but does NOT pass it to `newevent_new`
  (S-SISP-015/016): where the OK event lands is `newevent_new`'s heuristic. Preserved; the
  test shows it lands on the outage ticket for the common case.

## AuditUsage deletion count

**2 of 2** `plog.AuditUsage(...)` call sites deleted outright, one per public procedure
(`secondaryisp_alert` line 295, `secondaryisp_ok` line 373) -- confirmed by
`grep -c AuditUsage ddl/src/pkgb/guma2_secondary_isp.sql` -> 2. Per XCUT-06, deleted, not
stubbed.

## `pg_kind` verdict: correct for both

Both public routines are Oracle `PROCEDURE`s, `name-map.csv` says `pg_kind=procedure`, both
are created as PostgreSQL `PROCEDURE`s (`prokind='p'`, S-SISP-001 assertions). No
`COMMIT`/`ROLLBACK`/autonomous transaction anywhere (inventory and full read agree). The
seven private helpers: `is_host_up`, `is_secondaryisp_all_peers_down`,
`pretty_print_host_id_list` are Oracle FUNCTIONs and stay FUNCTIONs; `get_next_token`,
`secondaryisp_parse_syslog`, `secondaryisp_interface_info` are Oracle PROCEDUREs whose only
outputs are OUT parameters and are translated as FUNCTIONs with OUT columns (so a caller
reads them with one `SELECT ... INTO ... FROM f(...) t`); `comma_join` keeps its `IN OUT`
shape as a PROCEDURE with an `INOUT` parameter. All seven are `guma2.secondary_isp__<name>`
with `REVOKE ALL ... FROM PUBLIC` (S-SISP-018).

## Exception mapping

- Package-private `E_ABORT` (body line 8) -> SQLSTATE **`OS020`** (PROVISIONAL, XCUT-01).
  Follows `migration/mapping/sqlstate-map.md`'s precedent for unnumbered control-flow
  exceptions (`MSS.OSAG_DBPROP_STATE.e_abort` -> `OS000`); distinct from every code in that
  table and from this plan's `OS010`/`OS011` (OSIXINFO). `E_ABORT` never leaves the package
  (both public handlers catch it), so no client can observe the value. **The row still has
  to be added to the shared `sqlstate-map.md` table by the integration plan (06-07)** -- not
  edited here to avoid concurrent edits by wave-parallel plans (06-03/06-04 map their own
  `*_STATE` exceptions).
- Predefined exceptions crossing routine boundaries: `NO_DATA_FOUND` handled locally at all
  three sites; `TOO_MANY_ROWS` from the interface lookup and `22P02` from a non-numeric peer
  token (Oracle `VALUE_ERROR`) land in the public `WHEN OTHERS` and are logged, never raised
  (S-SISP-007/010/014/017). Nothing escapes either public procedure.

## The carried log line (plog stub is transactional)

Oracle's `plog.Log` runs in an autonomous transaction and commits
(`ddl/src/pkgb/osag_osag_plog.sql:47, 54`), so `plog.err(...); RAISE E_ABORT;` left the log
line in place when the public handler caught the abort. The PostgreSQL plog stub writes into
the caller's transaction (`osag_plog.FINDINGS.md`, "Rollback limitation"); a PL/pgSQL
`EXCEPTION` block is a subtransaction, so a row written just before `RAISE` is erased when
the handler catches it -- the first GREEN attempt lost every one of the 11 "log then abort"
lines. Translation mechanic, applied at all 11 raise sites: `RAISE EXCEPTION '%', <log text>
USING ERRCODE = 'OS020', DETAIL = 'ERR'|'NOTICE'`; the public handler's `WHEN SQLSTATE
'OS020'` arm reads `MESSAGE_TEXT`/`PG_EXCEPTION_DETAIL` and emits the line through
`osag.osag_plog_err`/`_notice` once. Same line, same level, same order as Oracle; recorded
in the spec's Assumptions so it is not mistaken for a behavioural change. When XCUT-02
replaces the stub with a non-transactional shipper this stays correct (the line is still
emitted exactly once, from the handler).

## SELECT INTO strictness (3 sites, matching the spec's table and the inventory)

- Site #1 (`is_host_up`, corrected query): `STRICT` + Oracle's two-arm handler.
- Site #2 (`secondaryisp_interface_info`): `STRICT` + `NO_DATA_FOUND` arm only;
  `TOO_MANY_ROWS` propagates to the public `OTHERS` (an interface may be linked to several
  ISP links -- `interface2isp_link` PK is `(interface_id, isp_link_id)`).
- Site #3 (`pretty_print_host_id_list`): `STRICT` + Oracle's `unknown(hostid:N)` arm.
- The `OPEN/FETCH/CLOSE` cursor in `secondaryisp_ok` -> non-`STRICT` `SELECT ... INTO ...
  ORDER BY id DESC LIMIT 1` (NULL on zero rows, like the cursor).
- No message-parity shim needed: no unhandled `NO_DATA_FOUND` can leave the package.

## Translation mechanics worth knowing

- **Tokenizer** (`get_next_token`): `INSTR(s, d, 1, 1)` -> `strpos(s, d)`; Oracle's
  `substr(s, 0, p-1)` -> `substr(s, 1, p-1)` (Oracle treats position 0 as 1; PostgreSQL's
  `substr(s, 0, n)` would return `n-1` characters -- a silent off-by-one). The `LENGTH('')
  = 0` early return that never fired in Oracle (`LENGTH('')` is NULL) is made explicit
  (`IS NULL OR length = 0`) so `''` and `NULL` both yield two NULL outputs, Oracle's
  observable result.
- **`TO_NUMBER` -> `::bigint`** (`mss.host.id%TYPE` is `bigint`): a non-numeric token
  raises `22P02` where Oracle raised `VALUE_ERROR`; both end in the public `OTHERS`. The
  test puts the bad token FIRST in the list (`abc|930101`) because the loop returns at the
  first peer that is up -- a bad token after an up peer is never evaluated (in Oracle too).
- **`INOUT` argument must be a plain variable of the parameter's type**: the first GREEN
  attempt declared `pretty_print_host_id_list`'s accumulator `varchar` while
  `comma_join`'s `INOUT` is `text`, and PL/pgSQL refused the CALL ("procedure parameter
  "io_string" is an output parameter but corresponding argument is not writable"). The
  accumulator is `text`.
- **Pitfall 2, the one genuine site:** `l_pretty_string := ''` (Oracle NULL) -> `:= NULL`,
  otherwise the first `comma_join` would produce a leading `', '` (S-SISP-012).
- **NULL concatenation:** `concat()` for every event-text and log line whose operands can be
  NULL (`l_interface`, both pretty-printed lists, `l_down_since`/`l_up_since`,
  `l_isp_company`, `i_host_id` in log lines). The S-SISP-019 test proves `observed=]` yields
  `Down since: ` + line break, not a NULL text.
- **`newevent_new` call shape:** OUT variable first, then `(10050|10100, i_host_id,
  <public>, <private>)`, all other parameters defaulted as in Oracle. `i_host_id` is
  `bigint` and the parameter `numeric` (implicit cast); the texts are `text` into `varchar`
  (implicit).
- **Public signatures keep the `%TYPE` anchors** (`mss.host.id%TYPE`,
  `guma2.syslog_message.log_date%TYPE` = `timestamp(0)`,
  `guma2.syslog_message.message%TYPE` = `text`). Callers must pass a naive `timestamp` for
  `i_logdate` (no implicit `timestamptz -> timestamp` cast in CALL resolution) -- the
  external gumaserver caller is Perl, which binds text literals, so this only matters for
  PL/pgSQL callers.

## Schema / masterdata facts the tests depend on

- `tt.event_type` 10050 ("ISP down"), 10100 ("connection up"), 10003 exist in masterdata;
  `ticket_type_for_event_type(10050)` = 1 (trouble ticket), subject = event type name.
- `mc.host_connection_status` exists in the migrated schema (PK `host_id`,
  `con_int_type_id` nullable FK to `mc.con_int_type`); `mc.con_int_type` has NO masterdata
  in the template (the `MC` schema is not loaded) -- the test inserts ids 0/2 `ON CONFLICT
  DO NOTHING`.
- `mss.interface.description` is `NOT NULL` (the `' (desc)'` part always has text);
  `stop.company.name` and `mss.isp_link.company_id` are nullable; `mss.isp_link` needs
  `router_ip_address1`, `event_type_id`, `currency_id`, `isp_link_sourcing_type_id`
  (`mss.currency` 1 and `mss.isp_link_sourcing_type` 1 exist in masterdata).
- `mss.host.active` defaults to 0: every fixture host sets it to 1, otherwise
  `newevent_new` drops the event.

## Red/green status (verified live against `mcdb_test_p0602`, cloned from `mcdb_tmpl`)

**RED (before the translation existed, every other translation installed):**

```
PACKAGE                                  | PGTAP (pass/total) | REGRESS (pass/total) | RESULT
guma2.secondary_isp                      | 1/76               | 0/0                | FAIL
```

The one pre-passing assertion is the vacuous "EXECUTE revoked from PUBLIC" check next to
its failing existence check; the transaction aborts at the first private-helper call
(`function guma2.secondary_isp__get_next_token(...) does not exist`).

**First GREEN attempt:** 47/76 -- the 11 "log then abort" lines were lost to the handler's
subtransaction rollback and the `INOUT` call failed (both explained above).

**GREEN (translation installed), this package:**

```
guma2.secondary_isp                      | 76/76              | 0/0                | PASS
```

**GREEN, whole harness (`run-tests.sh --db mcdb_test_p0602 --install migration/pgsql`):**

```
PACKAGE                                  | PGTAP (pass/total) | REGRESS (pass/total) | RESULT
_canary.canary                           | 2/2                | 1/1                | PASS
_support.pgmig                           | 10/10              | 0/0                | PASS
auth.osag_auth                           | 9/10               | 0/0                | FAIL
guma2.secondary_isp                      | 76/76              | 0/0                | PASS
mss.osag_dbprop                          | 10/10              | 1/1                | PASS
mss.osag_ip                              | 108/108            | 0/0                | PASS
osag.osag_msg                            | 63/63              | 0/0                | PASS
osixinfo.osag_hardware                   | 78/78              | 0/0                | PASS
ticketevolution.calculator               | 62/62              | 1/1                | PASS
tt.escalation_interface                  | 74/74              | 1/1                | PASS
tt.event_interface                       | 30/30              | 1/1                | PASS
tt.osag_notify                           | 23/23              | 1/1                | PASS
tt.ticket_interface                      | 144/144            | 1/1                | PASS
tt.ticket_update_trg                     | 17/17              | 0/0                | PASS
tt.todo_item_update_trg                  | 12/12              | 0/0                | PASS
tt.util                                  | 10/10              | 1/1                | PASS
TOTAL: 16 packages, 15 pass, 1 fail
```

The single FAIL (`auth.osag_auth` 9/10, S-AUTH-007) is the known, accepted red named in the
plan brief; no sibling count changed.

## Verification performed

- `python3 migration/spec/spec_lint.py migration/spec/guma2.secondary_isp.md` (OK),
  `python3 migration/spec/trace_lint.py migration/test/pgtap/guma2__secondary_isp__spec.sql`
  (OK, 18/19 clauses cited -- uncited: S-SISP-005, the join-shape clause whose observable
  consequences are covered by 006/007/008/013), `bash migration/spec/provenance_lint.sh`
  (OK once the translation commit landed: spec `c53d862` and RED suite `69b8889` are both
  ancestors; the spec amendment `09b4ae2` touches no test; no commit touches translation
  and test files together).
- `grep -nEi "dbms_|utl_|auditusage|dblink|pg_background"` over the translation: zero
  matches outside comments.
- `pg_proc.prokind = 'p'` for both public routines; 7 private helpers present with EXECUTE
  revoked from PUBLIC (S-SISP-001/018 assertions).

## Open questions (could not be settled from the Oracle source)

- **Revive or retire MON-215?** The corrected `is_host_up` makes `secondaryisp_alert`
  raise 10050 events for the first time ever (see Deviations). Needs the project owner's
  call before the PostgreSQL cut-over; the alternative (faithful dead code) would make the
  alert a guaranteed no-op in PostgreSQL as in Oracle.
- **"Up" semantics** (`COALESCE(con_int_type_id, 0) = 0` vs the literal `IS NULL`): taken
  from `MC.MONITORING`; 06-04 (MC.MONITORING translation) should confirm.
- **`OS020` row in `sqlstate-map.md`**: to be added by 06-07 together with 06-03/06-04's
  codes.
- **Transaction-scope delta on the `WHEN OTHERS` paths** (S-SISP-014/017): Oracle keeps
  DML `newevent_new` executed before failing; PL/pgSQL's handler undoes it. XCUT-05's call;
  not asserted.
- **Who calls these procedures today?** The header says `GUMA2.submit_msg()`; no PL/SQL
  caller exists in `ddl/src/**`. The external caller (gumaserver / nursed message pipeline)
  must switch to `CALL guma2.secondary_isp_secondaryisp_alert(...)` /
  `..._secondaryisp_ok(...)` -- rows for both already exist in `pgmig.oracle_name_map`.
