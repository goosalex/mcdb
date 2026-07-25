# REDGREEN-EVIDENCE.md — the whole pilot, proven red-before/green-after, in one scripted run

Phase 2 success criterion 5, mechanised: `redgreen.sh` builds a fresh database from
`mcdb_tmpl` **without** any translation, runs the full suite (must fail hard), then
rebuilds, installs everything, and runs again. This is the first time all seven pilot
packages — including the complete four-member `TT.EVENT_INTERFACE` /
`TT.OSAG_NOTIFY` / `TT.TICKET_INTERFACE` / `TT.UTIL` cycle group — were exercised
together in one scripted gate, not package-by-package in isolation.

**Read this document's verdict section before trusting the word "PROVEN" anywhere else
in this phase's docs.** The RED phase behaves exactly as designed. The GREEN phase does
**not** reach the literal string `RED->GREEN PROVEN` — 5 of 7 packages still report FAIL,
for reasons documented below and traced, with evidence, to pre-existing test-file
defects and one architectural limitation this plan does not have the authority to fix.
That is the honest result. A method that "mostly worked" is not one that worked, and
this file exists so nobody downstream mistakes "191 assertions flipped from red to
green" for "the suite is fully green."

## The exact command

```bash
bash migration/test/redgreen.sh --db mcdb_test_finalrg --install migration/pgsql
```

(`mcdb_test_finalrg` substituted for the plan's literal `mcdb_phase2_rg` — `bootstrap.sh`'s
own T-02-01 name-allowlist gate, `^mcdb_(test|tmpl|harness)[a-z0-9_]*$`, rejects
`mcdb_phase2_rg`; this is the same substitution plan 02-12 already made and documented for
the identical reason. See "Deviations" below.)

## Phase 1 — RED (no translation installed)

Exit code: **1** (non-zero, as required — `redgreen.sh`'s own guard would have aborted
loudly with `RED PHASE DID NOT FAIL` had this been 0). Full log:
`migration/test/regress/results/redgreen-red.log`.

Representative errors — every routine genuinely does not exist yet:

```
died: 42883: procedure tt.osag_notify_event_notify(p_event_id => integer) does not exist
died: 42883: procedure tt.ticket_interface_change_worker(integer, integer, integer) does not exist
```

Per-package table:

| package | pgTAP (pass/total) | regress (pass/total) | result |
|---|---|---|---|
| `_canary.canary` | 2/2 | 1/1 | PASS |
| `auth.osag_auth` | 0/10 | 0/0 | FAIL |
| `mss.osag_dbprop` | 0/10 | 0/1 | FAIL |
| `tt.event_interface` | 0/20 | 0/1 | FAIL |
| `tt.osag_notify` | 0/23 | 0/1 | FAIL |
| `tt.ticket_interface` | **6**/129 | 0/1 | FAIL |
| `tt.util` | 0/10 | 0/1 | FAIL |
| **TOTAL** | **8/204** | 1/6 | 1 pass, 6 fail |

`_canary.canary` is the harness's own self-test (plan 02-01) — it is supposed to be
green with nothing installed; it exercises the harness, not a translation. Every real
package is correctly, overwhelmingly RED. **Except** `tt.ticket_interface`'s 6 assertions
— see "The vacuous-pass investigation" below; this is item 3 of this plan's mandate and
it does not indicate the RED gate is unsound.

## Phase 2 — GREEN (full `migration/pgsql` installed)

Exit code: **1** (non-zero — GREEN did **not** fully pass). Full log:
`migration/test/regress/results/redgreen-green.log`.

Per-package table:

| package | pgTAP (pass/total) | regress (pass/total) | result |
|---|---|---|---|
| `_canary.canary` | 2/2 | 1/1 | PASS |
| `auth.osag_auth` | 9/10 | 0/0 | FAIL |
| `mss.osag_dbprop` | 10/10 | 1/1 | **PASS** |
| `tt.event_interface` | 20/20 | 0/1 | FAIL |
| `tt.osag_notify` | 23/23 | 0/1 | FAIL |
| `tt.ticket_interface` | 125/129 | 0/1 | FAIL |
| `tt.util` | 10/10 | 0/1 | FAIL |
| **TOTAL** | **199/204** | 2/6 | 2 pass, 5 fail |

## The delta

- **pgTAP: 8/204 → 199/204 — 191 assertions flipped from failing to passing** when the
  real translations replaced nothing.
- **regress: 1/6 → 2/6 — 1 file flipped** (`mss.osag_dbprop`'s error-path golden).
- **5 regress files remain red on GREEN, but only on formatting, never on substance** —
  every `ERROR:`/`NOTICE:` line's TEXT matches the golden exactly (message, SQLSTATE);
  only `CONTEXT:` line numbers/phrasing (or, in one case, trailing whitespace) differ.
  See "Regress formatting diffs" below — this is a locked-in, already-understood category
  from plans 02-09 through 02-12, not new information, and this plan does not chase it
  further (D-P7-adjacent: it would require editing a golden file under
  `migration/test/regress/`, which is off-limits to this plan's executor — see
  `PHASE2-FINDINGS.md`'s policy decision).
- **4 pgTAP assertions remain red in `tt.ticket_interface`, all pre-existing test-fixture
  defects, none a translation defect** — root-caused individually below.
- **1 pgTAP assertion remains red in `auth.osag_auth`** — a PL/pgSQL savepoint-semantics
  fact about the `plog` stub, not a translation defect, deferred to Phase 3's XCUT-02.

None of the 5 remaining FAIL rows is a translation bug. All 5 are traced to a specific,
evidenced, non-translation root cause below and in `PHASE2-FINDINGS.md`.

## Why GREEN did not reach "RED->GREEN PROVEN" — every residual red, root-caused

### `tt.ticket_interface`: 4 pgTAP assertions (tests 3, 10, 15, 20 of `selectinto.sql`)

All four are **test-fixture defects already triaged in
`migration/pgsql/tt/ticket_interface.FINDINGS.md`** (its "Task 3 suite results" section,
Categories B/C/F), independently re-verified live by this plan:

| Test | Ticket | Root cause | Category |
|---|---|---|---|
| 3 | 907012 | fixture omits `last_status_change_date` (unreachable in real data — `newticket_new` always sets it) | B |
| 10 | 907018 | fixture's own comment says the value belongs in `company_id`; the `VALUES` list puts it in `status_id` instead | C |
| 15 | 907025 | same as test 3 — fixture omits `last_status_change_date` | B |
| 20 | 907030 | fixture's initial `status_id=4` is not in the tracked-transition set `{2,11,12,60,61,101}`; every sibling fixture uses `2` — apparent typo | F |

A-008 (`TEST-AMENDMENTS.md`) already fixed 8 of the original 10 Category-B instances (all
in `lifecycle.sql`); these 2 remaining instances are in `selectinto.sql`, not yet
amended. Fixing any of the four requires editing a file under `migration/test/pgtap/` —
outside this plan's authority (critical operating constraint 1). Documented here with
full evidence for the orchestrator to adjudicate, per this plan's own escalation path.

### `auth.osag_auth`: 1 pgTAP assertion (S-AUTH-007)

Already triaged in `migration/pgsql/auth/osag_auth.FINDINGS.md` and
`migration/pgsql/tt/osag_notify.FINDINGS.md` (identical root cause, both plans found it
independently): PL/pgSQL's implicit-savepoint-on-EXCEPTION semantics roll back **all**
writes performed inside a `CALL` that pgTAP's `throws_like`/`throws_ok` catches —
including a `plog` `INSERT` performed by the called procedure's own exception handler
before its `RAISE`. This is unconditional PostgreSQL transaction behavior, not a defect
in `delete_login`'s translation. It stops being observable the moment `plog` becomes a
real, non-transactional UDP shipper (Phase 3's XCUT-02, `osag_plog.FINDINGS.md`'s stated
replacement contract) — a `sendto()` is not undone by any savepoint rollback. Confirmed:
this is a Phase-2-pilot-only artifact of the plog STUB specifically, not a permanent
translation limitation.

### 5 regress files: formatting-only diffs, substance identical

See "Regress formatting diffs" below for the full breakdown and the policy decision
(`PHASE2-FINDINGS.md`).

## The vacuous-pass investigation (this plan's mandated Task, item 3)

The RED baseline shows `tt.ticket_interface` at 6/129 with **no translation installed at
all**. Six assertions pass against code that does not exist — identified by name, from
the actual pgTAP output (`pg_prove -v` against a template clone with only the plog stub
installed):

| # | File | Assertion |
|---|---|---|
| 1 | `changes.sql` test 15 | "the 2-arg `change_label` overload wrote NO audit event" |
| 2 | `changes.sql` test 25 | "`change_service_host` still wrote the new (nonexistent, but caller-supplied) service_id/host_id" |
| 3 | `changes.sql` test 41 | "`summary_relevant_events_count` was reset to 0 because the PUBLIC summary changed" |
| 4 | `changes.sql` test 48 | "`rate_ticket` left ticket 906015's status untouched (still 2, open) after a BAD engineer rating" |
| 5 | `lifecycle.sql` test 19 | "`expire_status` left `label_id` untouched (NULL)" |
| 6 | `lifecycle.sql` test 38 | "`deleteTicket` does NOT cascade to `stop.company`" |

**Every one of these is a negative assertion — "X did NOT happen."** With no translation
installed, the preceding `CALL` to the nonexistent procedure dies before it can do
anything, so of course the thing being checked for absence is absent. In isolation, a
"did not happen" assertion is unfalsifiable against a missing implementation — it would
pass just as happily whether the translation is perfectly correct OR does not exist at
all.

**Justified, not condemned — with one important caveat.** Every one of these 6 is
directly adjacent to sibling assertions, in the SAME test block, checking the POSITIVE
fact that the call succeeded — and every one of those siblings correctly fails RED:

| Vacuous assertion | Sibling(s) that correctly catch RED |
|---|---|
| #1 (test 15) | tests 12–14 (`change_label` 2-arg: succeeds / wrote label_id / dispatch proof) — all `not ok` in RED |
| #2 (test 25) | tests 23–24 (`change_service_host` propagation / success) — `not ok` |
| #3 (test 41) | test 40 (`change_summary` succeeds) — `not ok` |
| #4 (test 48) | test 47 (`rate_ticket` pulls sequence value) — `not ok` |
| #5 (test 19) | tests 17–18 (`expire_status` succeeds / forced status) — `not ok` |
| #6 (test 38) | tests 33–37 (`deleteTicket` succeeds / cascades) — `not ok` |

So the OVERALL file, and the overall package, is still correctly, overwhelmingly RED —
these 6 do not let a package "pass" against a missing translation; `run-tests.sh`'s own
pass/fail line requires `PGTAP_PASS == PGTAP_TOTAL` per package, and 6/129 is nowhere
near that bar. The caveat: **if any one of these 6 assertions were ever separated from
its positive sibling** (moved to its own file, or its sibling deleted in a later edit),
it would silently become a permanently-vacuous check — testing nothing, forever. This is
recorded as a real methodology lesson for Phase 4 in `migration/spec/METHOD-REVIEW.md`:
a negative ("did not change") assertion is only meaningful paired with a positive
("the call succeeded") assertion in the same test; the checklist/spec template should
say so explicitly.

## The mutation check — three deliberate wrong-translation changes, each caught

Per this plan's mandate: pick three translated routines from different packages/pitfall
classes, make one deliberate wrong change of exactly the kind this pilot exists to
catch, confirm the suite catches it, revert. All three below were run against
`mcdb_tmpl` clones, confirmed caught, and reverted (`git diff --stat` empty on every
touched translation file afterward — verified after each mutation, not just at the end).

### Mutation 1 — remove `STRICT` from a `SELECT INTO` (Pitfall 1)

**Target:** `migration/pgsql/mss/osag_dbprop.sql`, `get_string_by_host`'s
`SELECT id INTO STRICT v_key_id FROM mss.key WHERE name = v_property_name;` → `INTO`
(STRICT removed).

**Caught:** yes. `run-tests.sh --package mss.osag_dbprop`: **10/10 → 7/10** pgTAP
(tests 8, 9, 10 — S-DBPROP-006, S-DBPROP-009 ×2 — all report `no exception thrown`,
since a zero-match `SELECT INTO` without `STRICT` just leaves `v_key_id` `NULL` instead
of raising `NO_DATA_FOUND`), regress **1/1 → 0/1** (the same three error-path assertions
now error differently — `relation "mss.v_host_key_value" does not exist`, an unrelated,
pre-existing gap this exact mutation happens to expose because the routine now reaches
further into its own call chain instead of raising immediately). Exit code: 1 (was 0).
Reverted; re-verified 10/10 / 1/1 PASS.

### Mutation 1b — the plan's own literal example site (reported honestly, NOT counted as one of the 3)

The plan's Task 2 verify block scripts a STRICT-removal mutation against **the first**
`INTO STRICT` occurrence in `migration/pgsql/mss/osag_dbprop.sql` — which is
`get_number_by_host`'s `SELECT mss.osag_dbprop_get_string_by_host(...) INTO STRICT
l_string;`. Run exactly as scripted (substituting the compliant db name, see
"Deviations"): **the suite still reports 10/10 / 1/1 PASS — this specific mutation was
NOT caught.**

This is not a suite defect — it is a property of the chosen site. That `SELECT` has no
`FROM` clause; it evaluates one scalar function call, which is structurally guaranteed
to return exactly one row every time (identical to `SELECT 1;`), so `STRICT` can
**never** observably differ from its absence at this specific site (documented
independently in `osag_dbprop.FINDINGS.md`: "structurally can never trip"). A blind
first-occurrence sweep for this class of mutation can land on a vacuous target purely by
accident of file ordering. Mutation 1 above (the SAME package, a real table-query
`SELECT INTO`) demonstrates the suite catches the defect class perfectly well when
applied to a site where `STRICT` actually matters — this is a lesson about *where* to
apply the checklist's mutation-testing recommendation, not evidence the suite is weak.
Recorded verbatim in `METHOD-REVIEW.md`'s "What the checklist missed" section.

### Mutation 2 — remove an empty-string normalisation (Pitfall 2)

**Target:** `migration/pgsql/tt/ticket_interface.sql`,
`change_customer_reference`'s `IF (NULLIF(p_customer_reference, '') IS NOT NULL) THEN` →
`IF (p_customer_reference IS NOT NULL) THEN` (the `NULLIF` boundary normalisation
removed).

**Caught:** yes. `run-tests.sh --package tt.ticket_interface --filter
'tt__ticket_interface__changes.sql'`: **70/70 → 69/70** — test 10 (S-TICKET-018: "an
empty-string `p_customer_reference` ALSO produces the `<empty>` audit text") fails,
because without `NULLIF`, an empty string is no longer collapsed to `NULL` before the
`IS NOT NULL` check, so the audit text becomes `'customer reference changed to '`
(trailing blank) instead of `'customer reference changed to <empty>'` — exactly the
divergence this assertion exists to catch (its own description names this precisely:
"a translation that used a literal `IS NOT NULL` check... would instead produce a
trailing-blank text here"). Reverted; re-verified 70/70 PASS.

### Mutation 3 — swallow an exception the spec says re-raises (Pitfall 5)

**Target:** `migration/pgsql/tt/event_interface.sql`, `demote_event`'s
`EXCEPTION WHEN NO_DATA_FOUND THEN RAISE EXCEPTION 'no data found' USING ERRCODE =
'P0002';` → `WHEN NO_DATA_FOUND THEN NULL;` (swallowed, no re-raise).

**Caught:** yes, on both harness halves independently. pgTAP:
**20/20 → 19/20** (test 8, S-EVENT-043's "propagates NO_DATA_FOUND unhandled for a
nonexistent `p_event_id`" — now silently no-ops instead of raising). regress:
`tt__event_interface__errors.sql`'s golden diff **shrinks** (the `demote_event` error
line, previously already red on CONTEXT formatting only, now shows the assertion never
raised at all — the `ERROR: no data found` / `CONTEXT:` pair for `demote_event`
disappears from the actual output entirely, while `promote_event`'s untouched sibling
line is unaffected). Exit code: 1 (was already 1 due to the pre-existing CONTEXT-format
diff — but the actual DIFF content changed materially, confirmed by direct comparison of
the two diffs). Reverted; re-verified 20/20 pgTAP PASS.

**All three mutations were independently caught, by assertions in the specific
dimension each targets.** No mutation was silently absorbed by the suite. Mutation 1b
is the one honest exception, and it is explained, not hidden.

## Regress formatting diffs (5 files, substance-identical, byte-different)

| File | Diff | Category |
|---|---|---|
| `tt__event_interface__errors.out` | `CONTEXT:` line number/phrasing (`line 1 at SQL statement` → `line 19 at RAISE`) | CONTEXT-line, pre-existing |
| `tt__osag_notify__errors.out` | `CONTEXT:`/`DETAIL:` (signature grew 2 params; `DETAIL:` includes live, non-deterministic sequence/timestamp values the golden's own placeholder text anticipated but never resolved) | CONTEXT-line + non-deterministic DETAIL, pre-existing |
| `tt__ticket_interface__errors.out` | `CONTEXT:` line number/phrasing (×2) | CONTEXT-line, pre-existing |
| `tt__util__txn.out` | **Trailing whitespace only** — golden's header row `   id   | status_id` has no trailing space; actual output has one (` status_id `) | New in this plan (first time this file has ever executed to completion — every prior plan's RED baseline for it was "procedure does not exist") |

Every one of these was checked for SUBSTANCE match — every `ERROR:`/`NOTICE:`/data row is
byte-identical to its golden. The `tt__util__txn.out` trailing-space diff is genuinely
new information (this file could not previously execute at all, since it depends on
`tt.ticket_interface_change_status`, which only exists as of plan 02-12): a single
trailing space after `psql`'s `status_id` column header, cause not further diagnosed (not
a translation-content difference — the query and its result are identical either way).
The POLICY decision for all of these (regenerate goldens vs. filter the comparison) is
made once, for the whole category, in `migration/PHASE2-FINDINGS.md` — not repeated
per-file here.

## Deviations from the plan's own literal verify commands

Every verify command in this plan's own Tasks 1–2 names a database (`mcdb_phase2`,
`mcdb_phase2_rg`, `mcdb_phase2_neg`, `mcdb_mut`) that does not match `bootstrap.sh`'s
T-02-01 safe-name allowlist (`^mcdb_(test|tmpl|harness)[a-z0-9_]*$`). This is the
IDENTICAL drift plan 02-12 already found and documented ("CLAUDE.md's own text...
describes a broader pattern than what bootstrap.sh actually implements"). Every command
in this document was run against a compliant substitute name
(`mcdb_test_final*`/`mcdb_test_mut`) — Rule 3, auto-fix blocking issue; the SQL/assertion
content is unchanged, only the database-name argument. `bootstrap.sh`'s allowlist itself
is a hard, non-overridable safety gate (T-02-01) and is correctly NOT weakened to
accommodate the plan's own literal text.

## Verdict

RED is proven: the whole pilot, run together for the first time, fails hard without any
translation, exactly as `redgreen.sh`'s own built-in guard requires. GREEN is **not**
fully proven: 5 of 7 packages remain red, every one traced to a specific, independently
verified, non-translation root cause (4 pre-existing pgTAP fixture defects requiring an
amendment this plan's executor is not authorized to make; 1 PL/pgSQL savepoint fact
about the Phase-2-only plog stub; 5 regress files differing only in formatting). The
mutation check demonstrates the suite is not theatre — three deliberate defects of
exactly the kinds this pilot exists to catch were each independently caught — and it
also demonstrates, honestly, that a blind first-occurrence mutation sweep can pick a
vacuous target. Both facts matter more than a single pass/fail bit; see
`migration/spec/METHOD-REVIEW.md` for what this means for Phase 4.
