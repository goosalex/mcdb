# TT.UTIL -- FINDINGS

**Source:** `ddl/src/pkg/tt_util.sql` (spec, 63 lines), `ddl/src/pkgb/tt_util.sql` (body,
248 lines). **Spec:** `migration/spec/tt.util.md`. **Target:**
`migration/pgsql/tt/util.sql`.

This is the pilot's primary evidence for Phase 3's XCUT-04 (FUNCTION-vs-PROCEDURE
finalization) and XCUT-05 (autonomous-transaction/COMMIT-semantics decision). Nothing
below settles either decision -- that is explicitly out of scope for Phase 2 -- but every
fact XCUT-04/05 needs is traced here with call-chain evidence, not asserted.

## AuditUsage deletion count

**6 of 6** `plog.AuditUsage(...)` call sites deleted outright: one per public routine
(`check_resolved_tickets` line 19, `check_ticket_status` line 59,
`update_status_valid_until` line 94, `check_dnids_tickets_to_resolve` line 166,
`close_old_dev_tickets` line 221) plus the private helper `despam_ticket` (line 180) --
6 total, confirmed by `grep -c AuditUsage ddl/src/pkgb/tt_util.sql` -> 6. Per XCUT-06,
deleted, not stubbed.

## `pg_kind` verdict: correct for all 5 routines (first live test)

`migration/README.md`'s "Standing warnings" flags `pg_kind` as provisional pending
Phase 3's COMMIT/transaction-semantics audit. This package is the pilot's first live
test of that provisional label, and it holds up: all 5 public routines are declared
`PROCEDURE` in Oracle (`ddl/src/pkg/tt_util.sql:20,30,39,44,56`), `name-map.csv` carries
`pg_kind=procedure` for all 5, and this translation creates all 5 as PostgreSQL
`PROCEDURE`s (`prokind='p'`) -- verified live: `pg_proc.prokind = 'p'` for
`tt.util_check_resolved_tickets`, `tt.util_check_ticket_status`,
`tt.util_update_status_valid_until`, `tt.util_check_dnids_tickets_to_resolve`,
`tt.util_close_old_dev_tickets`. No discrepancy found for this package.

## THE central question: does any pilot FUNCTION transitively reach a TT.UTIL COMMIT?

Traced by hand, full-body read, for all three candidate FUNCTIONs the plan names --
`TT.TICKET_INTERFACE.get_next_recent_ticket`, `TT.TICKET_INTERFACE.replace_id_placeholders`,
`TT.EVENT_INTERFACE.ticket_type_for_event_type` -- plus, for completeness, a check of
whether ANY other routine they call in turn reaches `TT.UTIL`.

| Candidate FUNCTION | Oracle body (full) | Calls out to any other package routine? | Reaches TT.UTIL? |
|---|---|---|---|
| `get_next_recent_ticket` (`ddl/src/pkgb/tt_ticket_interface.sql:1437-1465`) | One `SELECT MIN(t.id) INTO v_ticketid FROM tt.ticket ...`, `RETURN v_ticketid`, a `WHEN OTHERS` handler that logs and `RETURN`s `NULL`. | **No.** Every statement in the body is a bare `SELECT`/`RETURN`/`plog.err` -- zero calls to any other package routine of any kind. | **No.** |
| `replace_id_placeholders` (`ddl/src/pkgb/tt_ticket_interface.sql:1647-1657`) | Two `SUBSTRB(REPLACE(...))` string operations, `RETURN v_text`. | **No.** Pure string manipulation; zero calls to anything. | **No.** |
| `ticket_type_for_event_type` (`ddl/src/pkgb/tt_event_interface.sql:833-861`) | An `IF`/`ELSIF`/`ELSE` chain assigning `v_ticket_type_id` from a hardcoded event-type-id mapping, `RETURN v_ticket_type_id`. | **No.** Pure branching logic on the input parameter; zero calls to anything. | **No.** |

**Verdict: none of the three candidate FUNCTIONs calls any other package routine at
all**, let alone `TT.UTIL` specifically -- so the "PostgreSQL PROCEDURE that COMMITs
cannot be CALLed from inside a FUNCTION body" hazard does **not** bite any of them
today. This extends (does not merely repeat) the spec's own S-UTIL-015 finding, which
only traced `update_status_valid_until`'s two current callers
(`TT.EVENT_INTERFACE.addevent_new`, `TT.TICKET_INTERFACE.change_status_event_id_out` --
both `PROCEDURE`): across the FULL pilot scope named in `02-CONTEXT.md`
(`AUTH.OSAG_AUTH`, `MSS.OSAG_DBPROP`, `TT.EVENT_INTERFACE`, `TT.TICKET_INTERFACE`, plus
`TT.OSAG_NOTIFY`/`TT.UTIL`), **zero FUNCTIONs anywhere in the pilot's static call graph
transitively reach any `TT.UTIL` routine, COMMIT-bearing or not.**

This is an input to XCUT-04, not a substitute for it. If Phase 3's `pg_kind`
finalization ever reclassifies `get_next_recent_ticket`, `replace_id_placeholders`, or
`ticket_type_for_event_type` themselves in a way that adds a NEW call into `TT.UTIL`
(none exists today -- this is a finding about the CURRENT static call graph, not a
constraint on future code), or if any FUTURE caller of `TT.UTIL` is a FUNCTION, this
constraint re-applies immediately per Pitfall 6.

## The autonomous-transaction/COMMIT decision this package forces (S-UTIL-010/012/013/014)

`close_old_dev_tickets` carries `PRAGMA AUTONOMOUS_TRANSACTION`
(`ddl/src/pkgb/tt_util.sql:209`) plus two per-iteration `COMMIT`s (lines 234, 244) --
one of exactly two table-writing autonomous-transaction sites in the whole corpus
(`.planning/research/PITFALLS.md` Pitfall 4). PostgreSQL has no autonomous-transaction
equivalent at all. Per `migration/spec/tt.util.md`'s own "Assumptions / Unresolved"
section (verbatim, not reinterpreted here): **this translation implements option 1 --
a plain PROCEDURE with a REAL `COMMIT`, accepting the semantic delta** rather than
reaching for `dblink`/`pg_background` (explicitly rejected, PITFALLS.md) or dropping the
per-iteration commit entirely (option 3, not chosen).

**The exact semantic delta this introduces:**

- **Oracle:** the autonomous transaction is TRULY isolated from the caller's own
  transaction -- it cannot see the caller's uncommitted writes, and its own `COMMIT`
  persists regardless of what the caller later does (including a caller `ROLLBACK`).
  This is the entire point of the pragma: partial progress survives a later failure
  ANYWHERE in the calling transaction.
- **This translation:** PostgreSQL has only one transaction per session. A `COMMIT`
  inside `CALL tt.util_close_old_dev_tickets()` commits the ENTIRE session's current
  transaction -- including whatever the CALLER had done before calling this procedure,
  not just this procedure's own writes. A caller that expected to still be able to roll
  back its OWN prior work after this call returns cannot -- that work is now permanently
  committed too. This is NOT symmetric with Oracle's true isolation.
- **Per-iteration visibility (S-UTIL-013/014):** after each `COMMIT`, execution
  continues in a brand-new transaction. Any lock or snapshot-visibility assumption the
  rest of the loop held from before that `COMMIT` is gone. A concurrent session
  observes each closed ticket/despammed event group become durably visible the moment
  its OWN iteration's `COMMIT` runs, not only when the whole procedure finishes --
  matching Oracle's per-iteration-commit behavior for THIS specific property (the
  isolation-from-caller property above is what differs, not the per-iteration
  granularity itself).

**The test that WOULD catch this, which Phase 2 deliberately does not write:** a
rollback-survival test that (1) starts a transaction, (2) does some unrelated write,
(3) calls `close_old_dev_tickets` (via a nested, non-top-level path so its `COMMIT`
would need to be caught -- which itself is impossible in the current design, since a
`COMMIT` inside a `CALL` chain requires the WHOLE chain back to the top-level `CALL`/`DO`
to be uninterrupted, per Pitfall 6), (4) rolls back the OUTER transaction, and (5)
asserts the unrelated write from step 2 did NOT survive while `close_old_dev_tickets`'s
own closures DID. `migration/spec/tt.util.md`'s "Assumptions / Unresolved" section
states this explicitly ("this pilot's tests therefore do NOT assert rollback-survival
for it") -- confirmed still true: `migration/test/regress/sql/tt__util__txn.sql` only
calls `close_old_dev_tickets` as a bare top-level `CALL` with no wrapping transaction to
roll back, which is exactly the scenario where this translation's chosen behavior is
indistinguishable from Oracle's. XCUT-05 owns writing the actual rollback-survival test
alongside its final decision.

## `V$INSTANCE` (S-UTIL-011): still unresolved, placeholder reused from the locked test

No PostgreSQL equivalent exists. This translation uses
`current_setting('mcdb.force_dev_instance', true) = 'true'` as the dev-instance gate --
deliberately reusing the EXACT custom GUC name the already-locked regress test
(`migration/test/regress/sql/tt__util__txn.sql`, written in plan 02-04, not touched by
this plan) sets, rather than inventing a different mechanism the test could never
observe. This is NOT a claim about what XCUT-04/05 will decide (a session/database GUC,
a config table, and a naming convention on the connection string were all named as
candidates in the spec's own Assumptions section, none chosen) -- it is the minimum
needed to make the ALREADY-WRITTEN test exercise this routine's logic at all.

## SELECT INTO strictness (all 3 sites, matching the spec exactly)

- `update_status_valid_until`'s `tt.ticket` lookup (S-UTIL-003): `STRICT`, with a
  message-only "no data found" shim (see below) -- this package has ZERO real exception
  handlers anywhere, matching the spec's "unhandled propagates" contract exactly.
- `despam_ticket`'s `MIN`/`MAX` aggregate (S-UTIL-009): `STRICT`, no handler --
  structurally safe.
- `close_old_dev_tickets`'s dev-instance `COUNT` (S-UTIL-011): `STRICT`, no handler --
  structurally safe (the hard problem here is the missing `V$INSTANCE` data source, not
  strictness).

## "no data found" message-parity shim

Same decision as `auth/osag_auth.sql` (see that file's FINDINGS.md for the full
rationale): `update_status_valid_until`'s one genuinely-unhandled `NO_DATA_FOUND`
propagation (S-UTIL-003) gets a transparent, message-only
`WHEN NO_DATA_FOUND THEN RAISE EXCEPTION 'no data found' USING ERRCODE = 'P0002';`
immediately after the `STRICT` select -- matching this package's own spec note that
PL/pgSQL's default `SQLSTATE P0002` "must propagate to `update_status_valid_until`'s
callers exactly as Oracle's unhandled `ORA-01403` does today", and the pgTAP suite's
pinned `%no data found%` substring (S-UTIL-003 assertion). No new handling is added --
the exception still propagates fully unhandled to whatever calls this routine, exactly
as the zero-exception-handler Oracle source does.

## `oracle.regexp_instr` (orafce)

`check_dnids_tickets_to_resolve`'s two `REGEXP_INSTR(text, pattern, position,
occurrence, return_opt, modifiers)` calls translate mechanically to orafce's
`oracle.regexp_instr` (same 6-argument signature, verified live against this exact
argument shape) -- a genuine, narrow, mechanical fit for an Oracle built-in per the
project's orafce policy (Pitfall 8), not a substitute for understanding the surrounding
logic.

## Sequences / package state

None used directly by this package (its callees use sequences, not this package
itself). `package_state: []` confirmed by reading the full 248-line body.

## Red/green status (verified live against `mcdb_test_p09`)

- **pgTAP (`tt__util__spec.sql`): 10/10 GREEN.** All 5 routines confirmed to exist as
  `prokind='p'` PROCEDUREs; `update_status_valid_until`'s full business-logic surface
  (deferred no-op, "other status" reset, waiting-family offset + last_deferral_date
  overwrite, nonexistent-ticket-id propagation) passes -- this routine calls nothing
  from `TT.TICKET_INTERFACE`/`TT.OSAG_NOTIFY`, so it needed no cycle sibling to be
  independently green.
- **Expected-output (`tt__util__txn.sql`): RED, and CORRECTLY so.**
  `close_old_dev_tickets` calls `tt.ticket_interface_change_status`
  (`TT.TICKET_INTERFACE`, plan 02-11, same wave, not yet landed) -- the `CALL` fails with
  "procedure ... does not exist". This is expected and documented: `migration/spec/tt.util.md`
  and this plan's own text both anticipate this suite staying partially RED pending its
  TT cycle-group siblings; plan 02-13 is the integration gate that re-runs this once
  02-10/02-11/02-12 have all landed.

## Verification performed

- Loaded cleanly into a `bootstrap.sh --template mcdb_tmpl` clone with `osag_plog.sql` +
  `mss/osag_dbprop.sql` + `auth/osag_auth.sql` already installed.
- `run-tests.sh --package tt.util`: pgTAP 10/10 PASS; regress 0/1 FAIL (expected, see
  above -- not a defect in this package's own translation).
- `grep -nEi "dbms_|utl_|auditusage"` over this file: zero matches.
- `grep -nEi "dblink|pg_background"` over this file: zero matches.
- `pg_proc.prokind = 'p'` confirmed for all 5 public routines plus the private helper.
