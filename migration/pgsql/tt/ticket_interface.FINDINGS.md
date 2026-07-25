# TT.TICKET_INTERFACE -- FINDINGS

**Source:** `ddl/src/pkg/tt_ticket_interface.sql` (spec, ~650 lines), `ddl/src/pkgb/tt_ticket_interface.sql`
(body, 2,484 lines). **Spec:** `migration/spec/tt.ticket_interface.md`. **Target:**
`migration/pgsql/tt/ticket_interface.sql`.

This is the pilot's largest translation: 38 public routines (37 distinct PostgreSQL
names -- `change_label` is the corpus's only genuine overload pair), 3 private routines,
77 `SELECT ... INTO` sites, 13 `NO_DATA_FOUND` handlers, 0 `TOO_MANY_ROWS` handlers, 10
`WHEN OTHERS` handlers. It is the first real test of the spec-first method at scale, and
the mutual-recursion cycle with `TT.EVENT_INTERFACE`/`TT.OSAG_NOTIFY`/`TT.UTIL`.

## FUNCTION-vs-COMMIT verdict for both FUNCTIONs

This package declares exactly two `FUNCTION`s. Both are created as PostgreSQL
`FUNCTION`s (`prokind='f'`), matching `name-map.csv`'s `pg_kind=function` for both rows.

1. **`get_next_recent_ticket`** (`tt.ticket_interface_get_next_recent_ticket`). Full
   Oracle body traced (`ddl/src/pkgb/tt_ticket_interface.sql:1437-1465`, 29 lines): one
   `SELECT MIN(t.id) INTO ...` aggregate query, zero `INSERT`/`UPDATE`/`DELETE`, zero
   calls to any other routine. It cannot transitively reach a `COMMIT` because it does
   not call anything at all. Call chain: NONE (leaf routine for call-out purposes). Its
   only caller *into* this routine is `TT.EVENT_INTERFACE.newevent_new` (the cycle-group
   partner) -- an inbound edge, irrelevant to this routine's own COMMIT reachability.
2. **`replace_id_placeholders`** (`tt.ticket_interface_replace_id_placeholders`). Full
   Oracle body traced (`ddl/src/pkgb/tt_ticket_interface.sql:1647-1657`, 11 lines): pure
   `REPLACE`/`SUBSTRB` string manipulation, zero database access, zero calls to anything.
   Cannot transitively reach a `COMMIT` for the same reason.

**Verdict: no FUNCTION/PROCEDURE-COMMIT hazard exists for either routine.** This
package's own two current call sites into `TT.UTIL` (which DOES `COMMIT` per
`migration/spec/tt.util.md`) are both from `change_status_event_id_out`
(`tt.util_update_status_valid_until`, twice) -- a `PROCEDURE`, not either `FUNCTION`. No
cross-package collision is reachable through this package's `FUNCTION`s. Confirms
S-TICKET-046's conclusion live. `pg_kind` remains PROVISIONAL for all 38 routines
pending Phase 3's XCUT-04 (`migration/README.md`'s standing warning) -- this FINDINGS
entry only confirms no *within-package* hazard; it does not settle the final shape.

## STRICT verdict distribution across the 77 sites, as translated

Computed directly from `migration/spec/tt.ticket_interface.md`'s own 77-row strictness
table (`## Checklist` > `### SELECT INTO strictness`):

| Verdict | Count |
|---|---|
| `STRICT, unhandled` | 42 |
| `STRICT + handler` | 18 |
| `no STRICT` (aggregate/sequence) | 17 |
| **Total** | **77** |

Every one of the 77 rows carries its `-- S-TICKET-0NN` clause-ID comment in
`migration/pgsql/tt/ticket_interface.sql`, placed directly above the translated site (120
total `S-TICKET-0NN` occurrences in the file -- some clauses cover multiple sites, e.g.
S-TICKET-032 covers 5). Sequence pulls (`nextval`/`currval`) use `SELECT ... INTO STRICT`
even where the spec verdict is `no STRICT` (harmless -- a sequence call always returns
exactly one row; matches `migration/pgsql/tt/event_interface.sql`'s established
convention). `COUNT`/`MIN`/`MAX` aggregates use plain `SELECT INTO` without `STRICT`,
same convention.

`ROWNUM = 1` -> `LIMIT 1` translation (S-TICKET-012, site #20,
`update_ux_timeout_for_ticket`'s service-window-end lookup): applied exactly per the
established mechanic (`migration/spec/tt.event_interface.md`'s S-EVENT-019 precedent) --
confirmed additionally structurally impossible to violate regardless, since
`tt.service_window` carries a genuine `UNIQUE INDEX` on `ticket_id`
(`ticket_id_uk1`, `ddl/migrated/tables/tables.pg.sql:1888`).

## AuditUsage deletion count

**36 of 36** `plog.AuditUsage(...)` call sites deleted outright (confirmed:
`grep -c AuditUsage ddl/src/pkgb/tt_ticket_interface.sql` -> 36; `awk`-cross-checked
against routine boundaries -- one call site per routine for 36 of the 38 public
routines). The 2 routines with NO `AuditUsage` call in Oracle source to begin with:
the 2-arg `change_label` overload and `deleteTicket` (neither has one in
`ddl/src/pkgb/tt_ticket_interface.sql`). The 3 private routines never had one either
(matches every sibling package's private-routine pattern). Per XCUT-06, deleted, not
stubbed -- `grep -c AuditUsage migration/pgsql/tt/ticket_interface.sql` -> 0 (the file's
own header comment is the only textual match, documenting the deletion, not code).

## Empty-string/NULL normalisations applied, parameter by parameter

Three distinct findings, matching the spec's own Checklist dimension 1 exactly (nothing
new discovered beyond what the spec already traced):

1. **`change_customer_reference.p_customer_reference`** (S-TICKET-018) and
   **`change_partner_reference.p_partner_reference`** (S-TICKET-022): boundary
   normalisation applied via `NULLIF(p_x, '') IS NOT NULL` on the audit-TEXT `IF` check
   ONLY. The `UPDATE` that writes the actual column stores `p_customer_reference`/
   `p_partner_reference` **verbatim** (unnormalised), exactly matching Oracle's own
   storage behavior (Oracle stores whatever was passed too -- only the *comparison*
   needed `''`-collapsing, not the write).
2. **`change_notification`'s `p_change_text_public`/`p_change_text_private`**
   (S-TICKET-027): NO normalisation needed or applied -- confirmed correctly handled by
   Oracle's own `IS NOT NULL`-guarded concatenation already (the prefix variable starts
   uninitialised/NULL and is only ever assigned inside the guard, so there is no
   `NULL||'x'`-collapsing-vs-not divergence to translate). PL/pgSQL variables likewise
   default to `NULL` on declaration, so this ports as a direct 1:1 translation.
3. **`add_status_change_event`'s "hide the event" check** (private routine, inherited by
   6 callers): NOT normalised -- Oracle's OWN inline comment flags this check as fragile
   ("if you ever decide to make this procedure public this has to be checked more
   carefully (whitespace-only strings...)"). Ported as-is, fragility included, per the
   spec's own instruction not to "fix" what Oracle's author explicitly left unfixed.

**One additional normalisation NOT flagged by the spec, found during translation** (see
"Places the spec left me guessing" below): `newticket_new`'s own call to
`replace_id_placeholders` needed `NULLIF(..., '')` wrapping that the spec's S-TICKET-037
clause (which only traces `replace_id_placeholders`' own body) did not call out for this
specific call site.

## GENUINE ORACLE BUG found during translation, not flagged anywhere in the spec

**Three call sites pass only 5 positional arguments to `add_status_change_event`'s
6-parameter signature** (`event_id OUT, p_ticket_id, p_public_change_text, p_contact_id,
p_private_change_text DEFAULT NULL, p_zitadel_contact_id DEFAULT NULL`):

| Call site | Oracle line | Args passed | What actually happens |
|---|---|---|---|
| `change_emergency` | `ddl/src/pkgb/tt_ticket_interface.sql:1217` | `(v_event_id, p_ticket_id, change_text, p_contact_id, p_zitadel_contact_id)` | `p_zitadel_contact_id` (this routine's own param) lands in `add_status_change_event`'s `p_private_change_text` slot (implicit Oracle `NUMBER`->`VARCHAR2` conversion) |
| `change_always_visible` | `ddl/src/pkgb/tt_ticket_interface.sql:1248` | same shape | same bug |
| `change_summary`, public-summary branch | `ddl/src/pkgb/tt_ticket_interface.sql:1323` | `(v_event_id, p_ticket_id, 'public summary changed to:'...,  p_contact_id, p_zitadel_contact_id)` | same bug -- the sibling private-summary branch (line 1310) IS the full 6-arg form and has no bug |

In all three cases, `add_status_change_event`'s own `p_zitadel_contact_id` parameter is
left at its `DEFAULT NULL` -- **the real zitadel contact id is never forwarded to the
audit event's `contact_zitadel_id` column at these 3 call sites**, and the
`details_private` column instead receives the stringified zitadel id (or stays `NULL`,
harmlessly, when the caller passed none).

**Ported faithfully, not fixed** -- per this project's translate-don't-fix methodology
(identical precedent to S-TICKET-053's `cust_id` bug and `TT.EVENT_INTERFACE.moveevent`'s
S-EVENT-033). Since PostgreSQL has **no cast at all** (not even assignment) from
`numeric` to `varchar` (confirmed: `SELECT castcontext FROM pg_cast WHERE
castsource='numeric'::regtype AND casttarget='varchar'::regtype` returns zero rows), an
explicit `::varchar` cast was required to make Oracle's *implicit* conversion happen at
all in PostgreSQL -- without it, the `CALL` would fail to resolve at CREATE/first-use
time rather than silently mis-route the value the way Oracle does. This is the specific
place a spec citing "structurally identical" bugs (S-TICKET-053 for `cust_id`) does NOT
by itself surface a *different* structural bug at 3 more call sites -- reading the actual
call-site argument counts against the private routine's signature was necessary, not
inferable from the spec text alone.

## Places the spec left me guessing (highest-value Phase 4 signal)

1. **The 3-call-site `add_status_change_event` positional-argument bug above.** The spec
   traces `add_status_change_event`'s own body thoroughly (S-TICKET-053, the `cust_id`
   bug) but does not cross-check every one of its 7 call sites' argument counts against
   its declared signature. Finding this required grepping every `add_status_change_event(`
   call site and counting arguments by hand -- a mechanical check the spec template could
   plausibly automate for Phase 4 (flag any call whose positional argument count doesn't
   match the callee's declared parameter count, cross-referenced against DEFAULTs).
2. **`replace_id_placeholders`'s `''`-vs-`NULL` boundary at its one call site.** S-TICKET-037
   fully traces the FUNCTION's own body (confirming no `SELECT`, no calls, no COMMIT
   hazard) but does not flag that its caller (`newticket_new`) needs `NULLIF(...)`
   wrapping to preserve Oracle's `SUBSTRB('',1,30000)`-collapses-to-NULL behavior --
   exactly the class of boundary-crossing fact `migration/spec/tt.event_interface.md`'s
   S-EVENT-015 already had to establish for the SAME function called from the OTHER
   package. The pattern (Pitfall 2, `NULLIF` at every FUNCTION-call boundary that
   ultimately feeds an `IS NOT NULL` check) is real and recurring, but the spec template
   traces it callee-side, not caller-side -- Phase 4's spec template should explicitly
   ask "does this FUNCTION's caller gate on the result with `IS NULL`/`IS NOT NULL`?" for
   every FUNCTION call site, not just every FUNCTION body.
3. **The private-routine naming convention's one arguable typo.** The spec's own
   recommended name for `updateTicketTimeStats` is written as
   `tt.ticket_interface__updateticketimestats` (missing a `t` -- Oracle's
   `updateTicketTimeStats` mechanically lowercases to `updatetickettimestats`, matching
   every other mechanical `package_in_name` lowercasing in this corpus, e.g.
   `updateTicketFlow` -> `ticket_interface_updateticketflow` in `name-map.csv` row 209).
   Used the corrected mechanical name (`tt.ticket_interface__updatetickettimestats`) --
   this convention lives outside `migration/mapping/name-map.csv` and remains
   unfinalized per every sibling spec's standing caveat, so this is a low-stakes
   correction, but worth flagging since Phase 4's name-map generator, if it ever absorbs
   private-routine naming, should not propagate this typo forward.
4. **`newticket_new`'s admin-permission check queries `auth.permission`**, which does not
   exist anywhere in `ddl/migrated/`, `ddl/export/`, or `changes/` -- identical situation
   to `TT.EVENT_INTERFACE.newevent_new`'s already-documented precedent
   (`migration/pgsql/tt/event_interface.FINDINGS.md`). Ported verbatim per spec (Rule 4 --
   architectural, not mechanical); no test reaches this branch (it requires
   `p_host_id IS NULL AND p_contact_id IS NOT NULL`, a company-wide-ticket path outside
   plan 02-08's test scope). Not independently re-flagged by this package's own spec
   (S-TICKET-003 mentions the query exists but does not flag the schema gap) -- decided
   here by following the sibling package's already-established disposition rather than
   re-deriving a new one.
5. **`tt.change_request.requester_zitadel_id`/`approver_zitadel_id`** -- referenced by
   `newticket_new`'s change-request-creation branch (`v_create_cr = 1`), these two
   columns exist **nowhere else in the entire repository** outside this one Oracle
   `INSERT` statement -- not in `ddl/export/`, not in `changes/changelog-current.sql`,
   not in `ddl/migrated/`. Unlike `tt.event.contact_zitadel_id`/`tt.ticket.contact_zitadel_id`
   (added by plan 02-11's schema-fix, traceable to a real, if not-yet-applied-to-snapshot,
   Liquibase changeset), there is no changelog entry to point to for these two -- the
   spec's own S-TICKET-005 clause mentions the sequence pull at this site but does not
   flag the column gap. Decided to add them via schema-fix anyway (varchar(128), matching
   `contact_zitadel_id`'s established type) rather than leave `newticket_new`'s CR-branch
   permanently broken at runtime -- see `migration/test/schema-fixes/24_p12_fixes.sql`.
6. **`fw.change` is missing from `ddl/migrated/` entirely** (not a partial-column gap
   like the two above -- the WHOLE TABLE), despite existing in the Oracle export
   (`ddl/generated/schema.oracle.sql:1579`, `CREATE TABLE FW.CHANGE (...)`). Referenced
   by `deleteTicket`'s next-to-last `DELETE` statement. A genuine ora2pg conversion gap
   (the table was silently dropped somewhere in the ora2pg pipeline, unlike the
   `contact_zitadel_id`/`requester_zitadel_id` cases which are Liquibase-changelog
   timing gaps). Added via schema-fix, matching the Oracle export's column list exactly.
   Not flagged by S-TICKET-052 (which enumerates the 31-statement cascade faithfully but,
   like every other clause in this spec, does not independently cross-check every
   referenced table's existence against `ddl/migrated/`).

## Deviations from the plan's own literal verify commands

`migration/test/bootstrap.sh`'s actual safe-name gate is
`^mcdb_(test|tmpl|harness)[a-z0-9_]*$` -- it does **not** accept `mcdb_p12` (the literal
database name this plan's own verify blocks specify). Every verify command in this
plan's Tasks 1-3 was run against `mcdb_test_p12`/`mcdb_test_p12_all`/`mcdb_test_p12_rg`
instead (Rule 3 -- auto-fix blocking issue; the substitution is purely a database-name
argument, the SQL/assertions themselves are unchanged). CLAUDE.md's own text ("Database
names must match the `mcdb_test_*`/`mcdb_p12*` safe-name pattern that bootstrap.sh
enforces") describes a broader pattern than what `bootstrap.sh` actually implements --
this is a documentation/implementation drift outside this plan's file-modification scope
to fix (bootstrap.sh lives under `migration/test/`, off-limits per the anti-circularity
wall).
