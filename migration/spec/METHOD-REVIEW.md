# METHOD-REVIEW.md — is the spec-first method fit to run 44 more times?

This is the more important of this plan's two documents. `PHASE2-FINDINGS.md` tells
Phase 3 what it inherits; this tells Phase 4 whether the *process* that produced it is
worth repeating unchanged. Phase 4 applies this method to 44 more packages on the
strength of what is written here — an unqualified "yes" is worth nothing if the real
answer is "yes, with these specific changes." The number that matters most in this
document (the amendment rate) is reported as measured, not flattered.

## Did the method work? Yes — with a measured, non-trivial defect rate on both sides

Tests were written from Oracle-derived specs, by agents who had never seen the
translation (`provenance_lint.sh` proves this by git ancestry, not by trust — every one
of the 6 translated packages passes it). Those tests then went green against
translations written later, without the translator ever being allowed to edit them to
make them pass. **The mechanism works: 191 of 204 pgTAP assertions (94%) flipped from
failing-against-nothing to passing-against-a-real-translation, in one scripted run, with
zero test-content edits made during translation.** See `REDGREEN-EVIDENCE.md` for the
full run.

But "the mechanism works" is not the same claim as "the pilot is fully green," and it
would be dishonest to conflate them. It is not. 5 of 7 packages still report FAIL in
`run-all.sh`'s own per-package table, for reasons fully traced in
`REDGREEN-EVIDENCE.md`/`PHASE2-FINDINGS.md`:

- **4 pgTAP assertions** (`tt.ticket_interface`) — pre-existing test-fixture defects,
  not translation defects, that this plan's executor lacks the authority to amend.
- **1 pgTAP assertion** (`auth.osag_auth`, S-AUTH-007) — a genuine PL/pgSQL
  savepoint-semantics fact about the Phase-2-only `plog` stub, resolved automatically the
  moment Phase 3's XCUT-02 replaces it with a real UDP shipper.
- **5 regress goldens** — formatting-only diffs (CONTEXT-line numbers/phrasing, one
  trailing space), substance identical, requiring a golden regeneration this plan's
  executor is likewise not authorized to perform unilaterally.

**None of the 9 residual assertions is a translation bug.** Every one is traced to a
specific, independently reproduced, non-translation root cause. That is itself a
meaningful result — it means the spec-first pipeline (spec → test → translation) is
producing CORRECT translations, and the residual redness is entirely in the
test-authoring and harness-maintenance layer, not the thing the method exists to verify.
Phase 4 should read that as encouraging about the CORE claim and sobering about the
SURROUNDING tooling discipline required to keep 44 more packages this clean.

## The spec error rate — the single most useful number this phase produces

**8 amendments** were needed against already-committed test files across the pilot
(`migration/spec/TEST-AMENDMENTS.md`, A-001 through A-008), touching **114 individual
pgTAP assertions** (many via cascade from one root-cause line — see below), across **76
public routines** in 6 packages.

**Raw rate: 8 amendments / 76 routines ≈ 10.5 per hundred routines.**
**Assertion-impact rate: 114 assertions / 76 routines ≈ 1.5 assertions affected per
routine** (this second number is inflated by two single-line defects that each cascaded
into dozens of skipped assertions via a PostgreSQL transaction-abort — see below; it
measures blast radius, not defect count, and should not be read as "1.5 real bugs per
routine").

**These 8 amendments collapse into 4 distinct recurring defect CLASSES, not 8
independent mistakes:**

| Class | Amendments | Assertions affected | Root cause |
|---|---|---|---|
| pgTAP `throws_ok(sql, sqlstate, description)` 3-arg overload footgun | A-001, A-002, A-006 — **3 separate sweeps** | 49 (7+23+19) | pgTAP's own ambiguous 3-arg dispatch (`octet_length($2)=5` reinterprets arg3 as expected message, not label) — every spec/test-authoring agent independently made this mistake |
| `is()`/`ROW()` anonymous-record type mismatch (`smallint`/`numeric`, `bigint`/`numeric`) | A-003, A-007 | 2 direct + 52 cascade (12+40) | pgTAP's `is(anyelement, anyelement)` requires exact type equality; expected literals were cast to a default type instead of the live column's actual type, and one unhandled `ERROR` aborts every later assertion in the same transaction |
| Fixture missing a column every real row always has | A-004, A-008 | 10 (2+8) | a hand-written `INSERT` in a test fixture omitted a column the application-code path (`newticket_new`, etc.) always sets — constructing a state the real system can never reach |
| TAP `plan(N)` off-by-one | A-005 | 0 (cosmetic, masked by real failures until they cleared) | miscounted assertions when the file was first authored |

**The single most important fact in this table: the SAME defect class (`throws_ok`
misuse) survived THREE independent sweeps and still had 19 live instances when plan
02-12 landed.** A-002's own text states the lesson plainly: "a text-pattern sweep for
this defect class is not reliable; the only sound detector is running the suite and
looking for the `threw <SQLSTATE>: <long sentence>` output shape." This is not a
one-off — it is direct evidence that **grep-based amendment sweeps under-count their own
defect class**, and Phase 4 must not assume a single cleanup pass closes a known-bad
pattern.

**Multiply by 44.** The pilot covered 6 of 48 packages (76 of an estimated ~216
corpus-wide public routines — extrapolated from the ~177 corpus-wide `AuditUsage`
estimate divided by this pilot's own ~0.82 sites/routine density, `PHASE2-FINDINGS.md`
XCUT-06). At the pilot's raw 10.5-per-hundred-routines amendment rate, the remaining
~140 routines should be expected to need **roughly 15 more amendments** — and, given the
throws_ok lesson above, Phase 4 should NOT assume "we already know about `throws_ok`"
prevents new instances; it should assume the same class recurs unless the pattern is
mechanically prevented (see "Recommended template changes" below), not just documented.
**Budget for 15-20 amendments across the remaining corpus, not zero.** Reporting this
number as "we already fixed it" would be the exact flattery this document exists to
avoid — three sweeps in and it STILL was not fully fixed.

## What the checklist caught — per dimension, honestly distinguishing "found nothing" from "nothing to find"

`CHECKLIST.md`'s 5 dimensions, applied to every one of the 6 pilot specs:

| Dimension | Found real defects? | Evidence |
|---|---|---|
| **1. SELECT INTO strictness** | **Yes — proven by direct mutation.** `REDGREEN-EVIDENCE.md` Mutation 1: removing `STRICT` from a real table-query site (`mss.osag_dbprop.get_string_by_host`'s `mss.key` lookup) flips 3 pgTAP assertions and 1 regress file from pass to fail. Also surfaced a real methodology risk: the plan's OWN literal example mutation site (the FIRST textual `INTO STRICT` in the same file) turned out to be a scalar function-call `SELECT` — structurally incapable of ever exhibiting the STRICT/non-STRICT distinction — and the mutation there was correctly NOT caught. A blind "mutate the first occurrence" sweep can pick a vacuous target by accident of file ordering; this dimension's checklist entries should flag which sites are structurally inert (`osag_dbprop.FINDINGS.md` already does this for its own package) so Phase 4's own mutation testing doesn't repeat the miss. |
| **2. Empty-string/NULL handling (Pitfall 2)** | **Yes — proven by direct mutation and by translation-time discovery.** `REDGREEN-EVIDENCE.md` Mutation 2: removing one `NULLIF` boundary normalisation flips a real assertion (S-TICKET-018). Also: `tt.ticket_interface.FINDINGS.md` records a normalisation the SPEC did not flag but translation-time inspection found (`newticket_new`'s call into `replace_id_placeholders` needed `NULLIF` wrapping the spec's own clause for that FUNCTION's body didn't call out, since the spec traces the callee, not every caller). |
| **3. Exception codes** | **Yes.** 14 message-parity shim sites across 5 packages (`PHASE2-FINDINGS.md` XCUT-01), a real SQLSTATE discriminator (`auth.osag_auth`'s `unique_violation` check), and `REDGREEN-EVIDENCE.md` Mutation 3 (swallowing a re-raise) proves the dimension is exercised, not decorative. |
| **4. Package state** | **Found nothing — because there was nothing to find, not because the dimension is broken.** All 6 pilot packages independently report `package_state: []`, each confirmed by reading the FULL package body, not assumed. The corpus DOES contain real state packages (`AUTH.OSAG_AUTH_STATE`, `MC.MONITORING_STATE` — `migration/README.md`'s own collision-semantics section names them), and none of them was in this pilot's scope. **This dimension is unexercised, not proven, and Phase 4's first package with real package-level state is where it gets its first real test.** |
| **5. FUNCTION-vs-PROCEDURE** | **Yes — a substantive, positive result, not a null finding.** `pg_kind` held for all 76 pilot routines with zero discrepancies; 3 candidate FUNCTIONs were traced full-body and confirmed to have zero COMMIT-hazard call chains; `tt.util.close_old_dev_tickets` is a confirmed, tested COMMIT-bearing PROCEDURE. This is the pilot's single largest structural finding (`PHASE2-FINDINGS.md` XCUT-04) and it is a real, evidenced "the provisional label held," not an absence of counterexamples. |

**Two of five dimensions (1, 5) were validated by direct, deliberate mutation — the
other three (2, 3, 4) rest on translation-time evidence and spec citations, not an
equivalent adversarial check.** Phase 4 should extend the mutation-check discipline
(`REDGREEN-EVIDENCE.md`'s Task 2 pattern) to dimensions 2 and 3 routinely, not just as
this closing plan's one-off exercise — and should treat dimension 4 as genuinely
untested pending a package that actually has state.

## What the checklist MISSED

1. **pgTAP API footguns are not a translation-correctness dimension at all, and the
   checklist has no slot for them** — yet they cost this phase 3 separate amendment
   sweeps and 49 assertions. `throws_ok`'s 3-arg ambiguity and `is()`'s exact-type-match
   requirement for anonymous records are PGTAP TOOLING facts, orthogonal to Oracle
   fidelity, that every spec/test-authoring agent re-discovered independently because
   nothing forced the correct pattern. **This is a template change, and it must land
   before Phase 4, not be documented as a known issue and hoped away** (see below).
2. **The vacuous-pass risk for "did NOT happen" assertions** (this plan's own
   investigation, `REDGREEN-EVIDENCE.md`): a negative assertion is only meaningful when
   paired with a positive "the call succeeded" assertion in the same test block. All 6
   instances found in the pilot's RED baseline WERE correctly paired, so this did not
   cause a real gap here — but nothing in `CHECKLIST.md` or `TEMPLATE.md` currently
   requires the pairing, so it is one refactor away from silently becoming one.
3. **The TEST-AMENDMENTS.md ledger lived at the wrong path for this entire phase**
   (`migration/test/TEST-AMENDMENTS.md` instead of the documented
   `migration/spec/TEST-AMENDMENTS.md`) — `provenance_lint.sh`'s escape hatch would have
   silently rejected a properly-recorded amendment landing in the same commit as its
   translation, had that shape ever actually occurred. It never did (every amendment was
   test-file-only), so this was a latent gap, not a live failure — but it went unnoticed
   for 8 amendments across 2 weeks of phase work because nothing checked the documented
   contract against the file's real location. Fixed this plan (`git mv`); Phase 4 should
   add a cheap existence assertion to `provenance_lint.sh` itself so a similar drift
   cannot hide again.
4. **`build-template.sh` is not rebuilt automatically when `schema-fixes/` changes** —
   flagged as a standing operational risk by the orchestrator's own pre-flight brief for
   this plan ("cost 5 assertions during 02-12's own verification"). `run-all.sh` now
   prints a loud warning when skipping the rebuild, but does not force it. Phase 4, which
   will touch `schema-fixes/` far more than Phase 2 did (42 more packages, each capable
   of surfacing its own ora2pg gap), should make this a hard, automatic check
   (content-hash the directory; rebuild if it changed since the template was last built),
   not a printed warning a busy translator can scroll past.

## Cost — what a package cost, and what 44 more will cost

Empirical, from every plan's own recorded `duration` (`.planning/phases/02-*/*-SUMMARY.md`
frontmatter), summed:

| Phase | Plans | Time | What it bought |
|---|---|---|---|
| One-time infra | 02-01, 02-02, 02-03 | 21+20+30 = **71 min** | harness, linters, test schema — paid once, not per package |
| Spec + tests (RED) | 02-04..02-08 | 120+120+45+150+95 = **530 min** | specs+tests for 6 packages (dbprop/auth/util bundled in one plan; ticket_interface needed 2 plans for its 38 routines/77 sites) |
| Translation (GREEN) | 02-09..02-12 | 180+50+190+210 = **630 min** | translating the same 6 packages |
| **Total package-specific work** | 9 plans | **1160 min ≈ 19.3h** | 76 public routines, 6 packages |

**≈ 15.3 minutes per public routine** (spec + test + translation combined, excluding the
one-time 71-minute infra cost and excluding this closing plan's own integration
overhead). Cost scales with package complexity, not a flat per-package rate — the
smallest 3 packages (dbprop/auth/util, bundled) cost ~100 min/package; the largest
(`tt.ticket_interface`, 38 routines/77 sites) cost 455 min across its 3 dedicated plans.

**Extrapolated to the remaining corpus** (~140 routines, 42 packages, per
`PHASE2-FINDINGS.md`'s XCUT-06 density estimate): **~140 × 15.3 min ≈ 36 hours** of raw
spec+test+translate work, **plus periodic closing/integration overhead** like this
plan (Phase 4's own wave-closing checkpoints will need something like `run-all.sh` +
`REDGREEN-EVIDENCE.md` re-verification at each wave boundary — budget several hours per
wave, not zero). This is a rough, single-pilot-data-point estimate, not a committed
schedule — package complexity variance (`tt.ticket_interface` cost 4.5× the smallest
bundle) means Phase 4's actual total could differ meaningfully in either direction, and
this estimate does not include Phase 3's own dedicated 2 plans (exception map, plog UDP
shipper, DBMS_* table, transaction audit), which gate Phase 4 and are not part of this
per-routine figure at all.

**A cost factor the plan-count table does not show:** several plans (`02-06`, `02-12`,
this one) explicitly record being resumed after a session interruption. Real elapsed
calendar time exceeds the summed task-duration figures above; Phase 4's own schedule
should pad for this, not assume continuous, uninterrupted execution across 42 more
packages.

## Recommended template changes for Phase 4

Concrete, not aspirational — every one below is a specific artifact change, not a
"be more careful" exhortation:

1. **Ban the pgTAP `throws_ok(sql, sqlstate, description)` 3-arg form outright.**
   Require either `throws_like(sql, '%pattern%', description)` or the unambiguous 4-arg
   `throws_ok(sql, sqlstate, NULL, description)`. This should be a **mechanical lint
   rule**, not a style note in a README — `trace_lint.py` already parses every assertion
   call in every test file; add a check that flags any `throws_ok` call with exactly 3
   arguments where argument 2 is a 5-character string literal (the exact ambiguity
   condition). A defect class that survived 3 human sweeps needs a machine gate, not a
   fourth sweep.
2. **Require exact-type casts on `is()`/`ROW()::record` comparisons, matching the LIVE
   column type, not a default.** Same lesson (A-003, A-007) — recommend a spec-template
   checklist note under dimension 1 (SELECT INTO strictness) or a new short checklist
   item: "when a test compares a column value via `is()`, does the expected literal's
   cast match `\d <table>`'s actual type?"
3. **Require every "did NOT happen" assertion to be adjacent to, or explicitly reference,
   a "the call succeeded" assertion in the same test.** A one-line addition to
   `CHECKLIST.md` or `TEMPLATE.md`'s test-authoring guidance closes this before it ever
   causes a real gap (it did not here, by luck of pairing, not by rule).
4. **Add a path-existence self-check to `provenance_lint.sh`** for
   `migration/spec/TEST-AMENDMENTS.md` — if amendment-shaped commits exist in git history
   (a commit whose message matches `test(amend`) but the ledger file is missing at its
   documented path, fail loudly instead of silently treating "no ledger" as "no
   amendments permitted."
5. **Make template staleness a hard gate, not a warning.** `run-all.sh` (this plan) prints
   a warning when `mcdb_tmpl` exists but `schema-fixes/` may have changed since; Phase 4
   should upgrade this to a content-hash check that forces a rebuild automatically,
   removing the human-attention dependency entirely.
6. **Flag structurally-inert `SELECT INTO STRICT` sites explicitly in the spec** (a
   FROM-less scalar-expression `SELECT`, or a query against a column with a
   `UNIQUE`/`PRIMARY KEY` constraint that makes `TOO_MANY_ROWS` provably impossible) —
   this pilot's own `osag_dbprop.FINDINGS.md` already does this informally; making it a
   required spec-template field would have saved this plan's own mutation-check dead end
   (Mutation 1b) and would help Phase 4's own future mutation testing pick real targets
   on the first try.

**If the answer were "none needed," that would itself be a claim requiring evidence this
phase does not have** — every one of the 6 changes above is backed by a specific,
reproduced defect this pilot actually hit, not a hypothetical. Recommend all 6 land
before Phase 4's first translation plan, not be absorbed informally as Phase 4 goes.

## Bottom line

The spec-first method's CORE claim held: every residual red assertion in this pilot
traces to test-authoring or harness-maintenance defects, never to a translation bug, and
the mutation check confirms the suite would have caught it if there had been one. That
is real, hard-won evidence, not an assumption. But "the translations are correct" is a
narrower claim than "the pilot is green," and this document does not conflate them: 5 of
7 packages are not green today, 8 amendments (3 of them repeat sweeps of the SAME defect
class) were needed to get this far, and at this pilot's own measured rate Phase 4 should
budget for 15-20 more amendments across the remaining corpus — not zero, and not "we
already fixed that." Ship the 6 template changes above first.
