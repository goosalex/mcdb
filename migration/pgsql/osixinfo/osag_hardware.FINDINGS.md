# OSIXINFO.OSAG_HARDWARE -- FINDINGS

**Source:** `ddl/src/pkg/osixinfo_osag_hardware.sql` (spec, 71 lines),
`ddl/src/pkgb/osixinfo_osag_hardware.sql` (body, 206 lines),
`ddl/src/pkg/osixinfo_osag_exceptions.sql` (companion exceptions package, 16 lines, empty
body). **Spec:** `migration/spec/osixinfo.osag_hardware.md` (14 clauses, S-HW-001..014).
**Target:** `migration/pgsql/osixinfo/osag_hardware.sql`. **Tests:**
`migration/test/pgtap/osixinfo__osag_hardware__spec.sql` (78 assertions). No regress golden:
the error paths are pinned by `throws_ok`/`throws_like` with their SQLSTATEs and texts.

Second TT caller of phase 06 batch B: `check_replaced_hw_for_host` raises a 10017 "hardware
installation" event through `tt.event_interface_newevent_new` after swapping a host's
hardware; the tests assert the full replacement footprint (history row, lifecycle items,
host swap) and the TT side effect (the event and the ticket `newevent_new` opens).

## Deviations from Oracle

**None.** Every clause is Oracle-faithful, including:

- `check_replaced_hw_for_host`'s procedure-wide `WHEN no_data_found THEN return` (S-HW-013),
  which also swallows `NO_DATA_FOUND` raised INSIDE `replace_hardware -> dump_to_hw_history`
  (a matched host with no `mss.host2service` row is silently treated as "nothing to
  replace"). It hides a data problem, but it is explicitly Oracle's contract and the data
  stays consistent (the failing selects precede all DML). Flagged for the owner, not changed.
- `TOO_MANY_ROWS` for a host mapped to two services propagating out of BOTH entry points
  (S-HW-006), and NOT NULL violations from the history insert (S-HW-007) likewise.
- The `IF (l_replacement_mac = p_reported_mac)` after a `WHERE` that already guarantees it
  (S-HW-008): kept.

## AuditUsage deletion count

**4 of 4** `plog.AuditUsage(...)` call sites deleted outright, one per routine including the
private helper (`dump_to_hw_history` line 24, `add_hardware_lifecycle_item` 91,
`replace_hardware` 121, `check_replaced_hw_for_host` 175) -- confirmed by
`grep -c AuditUsage ddl/src/pkgb/osixinfo_osag_hardware.sql` -> 4. Per XCUT-06, deleted, not
stubbed.

## `pg_kind` verdict: correct for all three

All three public routines and the private helper are Oracle `PROCEDURE`s; `name-map.csv` says
`pg_kind=procedure` for the three public ones; all four are PostgreSQL `PROCEDURE`s
(`prokind='p'`, S-HW-001 assertions). No `COMMIT`/`ROLLBACK`/autonomous transaction
(inventory and full read agree). Internal calls are `CALL`s between procedures; the TT call
is `CALL tt.event_interface_newevent_new(v_event_id, 10017, p_host_id, <public>, <private>)`.

## OSIXINFO.OSAG_EXCEPTIONS: no object, two SQLSTATEs (PROVISIONAL, XCUT-01)

| Oracle | Declared | Raised / caught | PostgreSQL SQLSTATE | Status |
|---|---|---|---|---|
| `OSAG_EXCEPTIONS.e_abort` | `ddl/src/pkg/osixinfo_osag_exceptions.sql:10` | raised `osixinfo_osag_hardware.sql:34, 39`; caught 200 | **`OS010`** | in use (this translation) |
| `OSAG_EXCEPTIONS.e_silentexit` | `ddl/src/pkg/osixinfo_osag_exceptions.sql:11` | nowhere in `ddl/src/**` (grep) | **`OS011`** | reserved, never emitted |

Rationale: `sqlstate-map.md` rules 3-4 (custom class `OS`, raised with `USING ERRCODE`,
caught with `WHEN SQLSTATE`) and its `OS000` precedent for an unnumbered control-flow
exception (`MSS.OSAG_DBPROP_STATE.e_abort`). `OS010`/`OS011` are distinct from every code in
the table and from `GUMA2.SECONDARY_ISP.E_ABORT`'s `OS020` (same plan), so no handler can
mistake one package's abort for another's. Oracle clients saw `ORA-06510: PL/SQL: unhandled
user-defined exception` (no code to branch on), so no client depends on the value. **The two
rows still have to be added to the shared `sqlstate-map.md` table by the integration plan
(06-07)**; not edited here to avoid concurrent edits by wave-parallel plans. The package spec's
two public constants (`HW_CHANGED_EVENT_TYPE = '10017'` -- a string literal implicitly
converted to NUMBER -- and `TODO_PRIVATE_HW_MIG`) are inlined; no object for them either.

## The carried log line (plog stub is transactional)

Oracle's `plog.err` at the two `e_abort` raise sites (lines 33, 38) ran in an autonomous
transaction (`ddl/src/pkgb/osag_osag_plog.sql:47, 54`) and survived the raise. The
PostgreSQL plog stub writes into the caller's transaction (`osag_plog.FINDINGS.md`,
"Rollback limitation"); the catching handler's subtransaction rollback erases a row written
just before `RAISE` -- the first GREEN attempt would have lost the S-HW-004 line. Mechanic:
`RAISE EXCEPTION '%', <log text> USING ERRCODE = 'OS010', DETAIL = 'ERR'`; the
`check_replaced_hw_for_host` handler emits `SQLERRM` through `osag.osag_plog_err` and then
its own `WARNING` -- same two lines, same order as Oracle (S-HW-010). When `e_abort` leaves
the package through a direct `replace_hardware` call (S-HW-011) nothing can persist a log
row (the caller rolls back), so the exception message IS the log line; the S-HW-004 test for
that path reads it via `throws_like` (TEST-AMENDMENTS A-021, spec amended first). Oracle's
`e_abort` carried no text, so this is additive.

## SELECT INTO strictness (6 sites, matching the spec's table and the inventory)

- Sites #1-#3 (`dump_to_hw_history`: hardware row, log-text join, host/service/company
  join): `STRICT`, no local handler. `NO_DATA_FOUND` is externally reachable and unhandled
  through `replace_hardware`, so the **"no data found" message-parity shim** (XCUT-01 rule
  2) wraps `replace_hardware`'s body once -- same SQLSTATE `P0002`, Oracle's wording;
  `check_replaced_hw_for_host`'s own `NO_DATA_FOUND` arm catches the re-raised `P0002`
  exactly as Oracle's catches the original (S-HW-013). `TOO_MANY_ROWS` from site #3 is not
  shimmed (rule-2 scope is `no data found` only) and propagates as `P0003`.
- Site #4 (`add_hardware_lifecycle_item` sequence pull): `SELECT nextval(...) INTO STRICT`.
- Site #5 (`replace_hardware`'s `CASE ... FROM dual`): a plain assignment from `EXISTS`.
- Site #6 (`check_replaced_hw_for_host` MAC join): `STRICT` + the procedure-wide
  `NO_DATA_FOUND` arm.

## Translation mechanics worth knowing

- **`%ROWTYPE` kept** (`v_oldhardware mss.hardware%ROWTYPE; SELECT * INTO STRICT ...`).
- **`mss.hardware_history` NOT NULL columns** (`company_short`, `host_name`,
  `purchase_date`, `disposal_date`, `history_date`, three ids): an old hardware row without
  `purchase_date` or a service company without `short` fails the insert with `23502` in
  both engines, unhandled (S-HW-007; test on host 7).
- **NULL concatenation:** `concat()` for the history log text (`stop.contact.email` is
  nullable -> `disposal_contact=;`, S-HW-005, tested); plain `||` elsewhere (all operands
  `NOT NULL` by the time they are used).
- **Pitfall 2 boundary:** `p_reported_mac` is normalised with `NULLIF(p_reported_mac, '')`
  so a PostgreSQL `''` behaves like Oracle's `''` (= NULL): no row matches, silent return
  (S-HW-008, tested).
- **`SYSDATE` -> `statement_timestamp()`** into `timestamp(0)` columns (assignment cast in
  INSERT/UPDATE); `NVL(disposal_date, SYSDATE)` -> `COALESCE(...)`.
- **Sequences:** `mss.hardwarehistory_seq`, `mss.hardware_lifecycle_item_seq` (both ported
  by `bootstrap/30_sequences.sql`).
- **Unqualified `hardware.id` / `host.id`** in Oracle's `UPDATE ... WHERE hardware.id = ...`
  resolve to the updated table and are valid PostgreSQL as written.
- **`service_company_id = 6` -> location 9 ("Internal")**: the meaning of company 6 is a data
  fact outside the repo (no `stop.company` masterdata); the literal is kept and the test
  inserts company 6 `ON CONFLICT DO NOTHING`.

## Schema / masterdata facts the tests depend on

- `tt.event_type` 10017 ("hardware installation") exists in masterdata;
  `ticket_type_for_event_type(10017)` = 1, so with no recent type-8/15 ticket `newevent_new`
  opens a type-1 ticket with subject `hardware installation`.
- `mss.hardware_lc_state` 4/6, `mss.hardware_lc_location` 3/9,
  `mss.hardware_disposal_reason` 1/2, `mss.hardware_deploy_reason` 2, `mss.service_type` 6
  (`internal_code = 'sitevpn'`) exist in masterdata; `mss.hardware_type`, `stop.contact`,
  `stop.company`, `mss.host`, `mss.hardware`, `mss.service` do not -- plan-owned 931xxx rows.
- `stop.contact.short` is `varchar(10)` (a fixture short had to be shortened);
  `stop.company.short` has a `lower(short) = short` CHECK.
- `mss.host.hardware_id` / `replacement_hardware_id` carry UNIQUE indexes; every fixture
  host has its own hardware pair.

## Red/green status (verified live against `mcdb_test_p0602`, cloned from `mcdb_tmpl`)

**RED (before the translation existed, every other translation installed):**

```
PACKAGE                                  | PGTAP (pass/total) | REGRESS (pass/total) | RESULT
osixinfo.osag_hardware                   | 24/78              | 0/0                | FAIL
```

The 24 pre-passing assertions are the "did NOT happen"/unchanged checks sitting next to
failing `lives_ok`/`throws_ok` calls (an absent procedure changes nothing) plus the vacuous
"no OSAG_EXCEPTIONS object" / "EXECUTE revoked from PUBLIC" checks.

**GREEN (translation installed), this package:**

```
osixinfo.osag_hardware                   | 78/78              | 0/0                | PASS
```

Whole-harness table: see `migration/pgsql/guma2/secondary_isp.FINDINGS.md` (same run,
16 packages, 15 pass; the single FAIL is the known `auth.osag_auth` 9/10).

## Verification performed

- `python3 migration/spec/spec_lint.py migration/spec/osixinfo.osag_hardware.md` (OK),
  `python3 migration/spec/trace_lint.py migration/test/pgtap/osixinfo__osag_hardware__spec.sql`
  (OK, 14/14 clauses cited), `bash migration/spec/provenance_lint.sh` (OK once the
  translation commit landed: spec `a44532a` and RED suite `bce5c09` are ancestors; the spec
  amendment `09b4ae2` and the test amendment `7c15c78` are test/spec-only commits, the
  latter logged as A-021 in `migration/spec/TEST-AMENDMENTS.md`).
- `grep -nEi "dbms_|utl_|auditusage|dblink|pg_background"` over the translation: zero
  matches outside comments.
- `pg_proc.prokind = 'p'` for all four routines; `osag_exceptions%` absent (S-HW-001/012).

## Open questions (could not be settled from the Oracle source)

- **Silent skip of a matched host without a service** (S-HW-013): Oracle-faithful, but it
  hides a data problem behind silence. Should the PostgreSQL version log it? Owner's call.
- **`OS010`/`OS011` rows in `sqlstate-map.md`**: to be added by 06-07 together with
  06-03/06-04's codes.
- **`GUMA2.OSAG_GUMA` carries an older copy of these three routines**
  (`ddl/src/pkg/guma2_osag_guma.sql:34-55`, translated by 06-03). Which copy the external
  heartbeat receiver / gumaserver calls after migration is a client-side decision; both
  names exist in `pgmig.oracle_name_map`.
- **Company 6 = "Internal"** is a data fact; if the company ids change in the PostgreSQL
  masterdata the literal must follow.
