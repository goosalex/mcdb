---
phase: 06-tt-callers-and-oracle-differential
plan: 02
subsystem: database
tags: [postgresql-18, plpgsql, pgtap, spec-first, tt-callers, guma2, osixinfo]

requires:
  - phase: 06-tt-callers-and-oracle-differential
    provides: "TT.EVENT_INTERFACE translation (tt.event_interface_newevent_new) and the shared mcdb_tmpl template (plan 02-03 onwards)"
provides:
  - "migration/spec/guma2.secondary_isp.md -- 19 clauses, one corrected site (S-SISP-009)"
  - "migration/spec/osixinfo.osag_hardware.md -- 14 clauses, OSAG_EXCEPTIONS SQLSTATE mapping (S-HW-012)"
  - "migration/test/pgtap/guma2__secondary_isp__spec.sql (76) and osixinfo__osag_hardware__spec.sql (78), RED-proven"
  - "migration/pgsql/guma2/secondary_isp.sql + FINDINGS, migration/pgsql/osixinfo/osag_hardware.sql + FINDINGS, GREEN"
affects: ["06-03 (GUMA2.OSAG_GUMA carries an older copy of the three hardware routines)", "06-04 (MC.MONITORING: host_connection_status 'up' semantics)", "06-07 (sqlstate-map.md rows OS010/OS011/OS020; revive-or-retire decision for MON-215)"]

tech-stack:
  added: []
  patterns:
    - "Carried log line: when Oracle logged via the autonomous plog and then RAISEd a package exception caught further up, the PostgreSQL raise site puts the log text in MESSAGE_TEXT (+ level in DETAIL) and the catching handler emits it once -- the transactional plog stub would otherwise lose the row to the handler's subtransaction rollback"
    - "Oracle PROCEDUREs whose only outputs are OUT parameters become PL/pgSQL FUNCTIONs with OUT columns (read with one SELECT ... INTO ... FROM f() t); an IN OUT accumulator stays a PROCEDURE with INOUT and must be passed a plain variable of the exact parameter type"
    - "Oracle substr(s, 0, n) -> substr(s, 1, n) (PostgreSQL's position 0 silently drops a character)"

key-files:
  created:
    - migration/spec/guma2.secondary_isp.md
    - migration/spec/osixinfo.osag_hardware.md
    - migration/test/pgtap/guma2__secondary_isp__spec.sql
    - migration/test/pgtap/osixinfo__osag_hardware__spec.sql
    - migration/pgsql/guma2/secondary_isp.sql
    - migration/pgsql/guma2/secondary_isp.FINDINGS.md
    - migration/pgsql/osixinfo/osag_hardware.sql
    - migration/pgsql/osixinfo/osag_hardware.FINDINGS.md
  modified:
    - migration/spec/TEST-AMENDMENTS.md (A-019)
    - migration/db/pg.sh (partial cherry-pick of 1a8c31c, coordinator instruction)

key-decisions:
  - "is_host_up corrected (DEVIATION(ORACLE-BUG), S-SISP-009): Oracle's `mon_server_id IS NULL` predicate is dead against the NOT NULL PK column, so secondaryisp_alert never raised a 10050 event; the body's own commented-out mc.host_connection_status query is used, with MC.MONITORING's definition of up (COALESCE(con_int_type_id,0) = 0)"
  - "OSIXINFO.OSAG_EXCEPTIONS gets no PostgreSQL object: e_abort -> OS010, e_silentexit -> OS011; GUMA2.SECONDARY_ISP's package-private E_ABORT -> OS020 (all PROVISIONAL, documented in spec + FINDINGS; the shared sqlstate-map.md table was deliberately not edited by a wave-parallel plan)"
  - "No deviation in OSAG_HARDWARE: check_replaced_hw_for_host's procedure-wide NO_DATA_FOUND swallow (silently skips a matched host without a service) is preserved and flagged, not fixed"
  - "No schema fix file needed: every table/sequence both packages touch exists and is correct in the template"

requirements-completed: []

duration: ~2.5h
completed: 2026-10-20
status: complete
---

# Phase 06 Plan 02: GUMA2.SECONDARY_ISP + OSIXINFO.OSAG_HARDWARE Summary

**Two TT-caller packages specified from the Oracle source, tested RED against the live
template, translated to PL/pgSQL and taken GREEN -- including the TT side effects (the
10050/10100/10017 events and the tickets `newevent_new` opens) -- with one provable Oracle
defect corrected (a dead `IS NULL` predicate that had silently disabled the Secondary ISP
Outage alert) and the two companion exception declarations mapped to SQLSTATEs.**

## What was done

| Step | GUMA2.SECONDARY_ISP | OSIXINFO.OSAG_HARDWARE (+ OSAG_EXCEPTIONS) |
|---|---|---|
| Spec | `migration/spec/guma2.secondary_isp.md`, 19 clauses S-SISP-001..019, spec_lint OK | `migration/spec/osixinfo.osag_hardware.md`, 14 clauses S-HW-001..014, spec_lint OK |
| RED suite | `guma2__secondary_isp__spec.sql`, 76 assertions, 18/19 clauses cited | `osixinfo__osag_hardware__spec.sql`, 78 assertions, 14/14 clauses cited |
| RED proof | **1/76** (template clone + every existing translation, no guma2 translation) | **24/78** (same setup, no osixinfo translation) |
| Translation | `migration/pgsql/guma2/secondary_isp.sql`: 2 public PROCEDUREs + 7 private `secondary_isp__*` helpers | `migration/pgsql/osixinfo/osag_hardware.sql`: 3 public PROCEDUREs + private `osag_hardware__dump_to_hw_history` |
| GREEN | **76/76** | **78/78** |
| AuditUsage deleted | 2/2 | 4/4 |

Whole harness after both translations (`run-tests.sh --db mcdb_test_p0602 --install
migration/pgsql`): **16 packages, 15 pass, 1 fail** -- the single FAIL is the known, accepted
`auth.osag_auth` 9/10; no sibling count changed. `spec_lint.py` (14 specs OK) and
`trace_lint.py` (29 files OK) run clean over the whole tree; `provenance_lint.sh` reports
`OK` for both of this plan's packages and 4 PRE-EXISTING violations for `tt.ticket_interface`
(commits `b9ba1dd` and `0e5c990`, both ancestors of this plan's base `cc8a21a`, touched
translation and test files together without a ledger entry) -- not introduced here, not
touched here (another package's history), flagged for 06-07.

## Deviations from Oracle

1. **`GUMA2.SECONDARY_ISP.is_host_up` (S-SISP-009, `-- DEVIATION(ORACLE-BUG)`).** Oracle
   reads `mc.mon_server_connection WHERE mon_server_id IS NULL AND host_id = ...`;
   `MON_SERVER_ID` is a `NOT NULL` primary-key column, so the query never returns a row,
   every peer is "down", `is_secondaryisp_all_peers_down` is constantly TRUE and
   `secondaryisp_alert` has NEVER raised a 10050 event in Oracle. The body's own comment
   ("code using new mc.host_connection_status table (not yet available)") names the intended
   query; the translation uses it, with "up" = `COALESCE(con_int_type_id, 0) = 0` taken from
   `MC.MONITORING`'s own code (`SANG_UP = 0`). **This revives a dormant production alert** --
   see open questions.
2. **None in OSAG_HARDWARE.** The procedure-wide `NO_DATA_FOUND` swallow in
   `check_replaced_hw_for_host` (a matched host with no service is silently "nothing to
   replace") is Oracle's contract, preserved and flagged (S-HW-013).

## Translation mechanic worth propagating: the carried log line

Oracle's `plog` ran in an autonomous transaction, so `plog.err(...); RAISE e_abort;` left the
log line behind when a handler caught the abort. The PostgreSQL plog stub is transactional
(`osag_plog.FINDINGS.md`): the catching handler's subtransaction rollback erases the row. The
first GREEN attempt of SECONDARY_ISP lost all 11 "log then abort" lines (47/76). Fix, applied
in both packages: the raise site puts the log text into the exception
(`RAISE EXCEPTION '%', <text> USING ERRCODE = 'OS0xx', DETAIL = 'ERR'|'NOTICE'`) and the
catching handler emits it once via `osag.osag_plog_<level>` -- same line, same level, same
order as Oracle. Where the exception leaves the package (direct `replace_hardware` call) no
log row can survive the caller's rollback; the exception message carries the reason instead
(Oracle's `ORA-06510` carried no text). Recorded in both specs' Assumptions.

## Test amendment (escape hatch, fully logged)

One assertion of the committed OSAG_HARDWARE RED suite asserted a `plog_stub_log` row AFTER a
`throws_ok` on a direct `replace_hardware` call -- unobservable by construction with the
transactional stub. Per `migration/spec/README.md`: spec amended first (`09b4ae2`, S-HW-011),
test changed in a test-only commit (`7c15c78`: the same text is now pinned via `throws_like`
on the exception message; 78 assertions before and after), ledger entry **A-019** in
`migration/spec/TEST-AMENDMENTS.md` (`08d5e81`). `provenance_lint.sh` passes.

## Schema fixes

None needed. Every table, column and sequence both packages touch exists and is correct in
`mcdb_tmpl` (`mss.interface`/`interface2isp_link`/`isp_link`, `mc.host_connection_status`,
`mss.hardware`/`hardware_history`/`hardware_lifecycle_item`, `mss.hardwarehistory_seq`,
`mss.hardware_lifecycle_item_seq`). Masterdata gaps are handled inside the test fixtures
(`mc.con_int_type` 0/2 and `stop.company` 6 inserted `ON CONFLICT DO NOTHING`).

## Commits (in order)

| sha | subject |
|---|---|
| `c53d862` | spec(06-02): GUMA2.SECONDARY_ISP |
| `a44532a` | spec(06-02): OSIXINFO.OSAG_HARDWARE (+ OSAG_EXCEPTIONS mapping) |
| `172663e` | fix(pg.sh): resolve the project root to the main checkout from git worktrees (partial cherry-pick of `1a8c31c`, coordinator instruction; its two `container/` files conflict with this branch's base and are left to the merge) |
| `69b8889` | test(06-02): RED suite for GUMA2.SECONDARY_ISP (1/76) |
| `bce5c09` | test(06-02): RED suite for OSIXINFO.OSAG_HARDWARE (24/78) |
| `09b4ae2` | spec(06-02): record how log lines written before an abort stay observable |
| `7c15c78` | test(06-02): S-HW-004 reason message pinned via the exception, not the stub log |
| `08d5e81` | docs(06-02): TEST-AMENDMENTS A-019 for the S-HW-004 assertion |
| `3d1e811` | feat(06-02): translate GUMA2.SECONDARY_ISP |
| `24091f4` | feat(06-02): translate OSIXINFO.OSAG_HARDWARE (+ OSAG_EXCEPTIONS mapping) |

Plus this SUMMARY commit.

## Open questions (for the project owner / later plans)

1. **Revive or retire MON-215 (Secondary ISP Outage)?** With S-SISP-009 corrected,
   `secondaryisp_alert` will raise 10050 events for WAN-managed links whose VPN peers are not
   all down -- production Oracle has never done that. Owner's call before cut-over; the
   faithful alternative is a guaranteed no-op.
2. **"Up" semantics for `mc.host_connection_status.con_int_type_id`** (`COALESCE(...,0) = 0`
   vs the literal `IS NULL`): taken from `MC.MONITORING`; 06-04 should confirm.
3. **`sqlstate-map.md` rows** `OS010` (OSAG_EXCEPTIONS.e_abort), `OS011` (e_silentexit,
   reserved), `OS020` (SECONDARY_ISP.E_ABORT): to be added by 06-07 together with
   06-03/06-04's codes (not edited here to avoid concurrent edits of the shared table).
4. **Silent skip of a matched host without a service** (S-HW-013): should PostgreSQL log it?
5. **Transaction-scope delta** on the `WHEN OTHERS` swallow paths (S-SISP-014/017): Oracle
   keeps DML `newevent_new` executed before failing, PL/pgSQL undoes it. XCUT-05.
6. **Two copies of the hardware routines** (`OSIXINFO.OSAG_HARDWARE` here,
   `GUMA2.OSAG_GUMA` in 06-03): which one the external heartbeat receiver calls after
   migration is a client-side decision; both are in `pgmig.oracle_name_map`.
7. **No PL/SQL caller of either package exists in `ddl/src/**`** (external gumaserver /
   `submit_heartbeat`): the client regexp kit must cover
   `guma2.secondary_isp.*` and `osixinfo.osag_hardware.*` (rows already present).
8. **`tt.event_interface_newevent_new` needed no change.** One observation for its owners:
   its own NOTICE/DEBUG log lines are lost when it fails and the caller swallows (same stub
   limitation), which is only a test-observability matter.

## Issues encountered

- The shared `mcdb-pg` container was being recreated by `pg.sh start` from different
  worktrees (coordinator message); fixed by taking the `migration/db/pg.sh` part of `1a8c31c`.
- `stop.contact.short` is `varchar(10)`: one fixture value had to be shortened before the
  RED commit (fixture-only validation, rolled back).
- The command sandbox refuses compound shell constructs (`{ ...; }`, heredoc-into-file in
  chains); scratch scripts were written to the gitignored `migration/test/.build-scratch/`
  instead.

---
*Phase: 06-tt-callers-and-oracle-differential*
