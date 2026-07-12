# Dynamic-SQL manual trace

This document is a reusable FORM for tracing genuine `EXECUTE IMMEDIATE`/`DBMS_SQL` sites
by hand, derived only from `ddl/src/**` (and, where the runtime value comes from
configuration data rather than code, the checked-in `masterdata/**` snapshot — which is
real exported Oracle reference data, not ora2pg output and not a PL/pgSQL translation, so
reading it does not violate the one rule below). Phase 4 has ~12 more sites like this one;
copy this file's section structure per site rather than inventing a new shape each time.

**The rule this document exists to honor:** every fact below is derived from Oracle
source and Oracle reference data. Nothing here is derived from `pg_migration/output/`
(ora2pg's untrusted guess) or from any PL/pgSQL translation (none exists yet for this
package, by construction).

---

## Site: `ddl/src/pkgb/tt_event_interface.sql:971`

### The exact source

```
960	                    IF (v_proc_str IS NULL) THEN
961	                        v_proc_str := event_action_rec.procedure_name;
962	                    END IF;
963	
964	                    plog.debug(c_prefix || 'event action : ' || v_proc_str);
965	
966	                    -- execute the procedure
967	                    -- N.B: the only procedure left configured in tt.event_action today is: tt.escalation_interface.escalate_os()
968	                    IF (v_proc_str IS NOT NULL) THEN
969	                        BEGIN
970	                            stmt_str :=  'call ' || v_proc_str || '(:eventid)';
971	                            plog.debug(c_prefix || 'executing : ' || stmt_str);
972	                            EXECUTE IMMEDIATE stmt_str USING p_event_id;
973	                        EXCEPTION
974	                            WHEN OTHERS THEN
975	                                plog.err(c_prefix||'unexpected error during procedure execution: '||sqlerrm);
976	                        END;
977	                    ELSE
978	                            plog.notice(c_prefix || 'no procedure executed for host: ' || v_host_id || ' on event of type: '||v_event_type_id);
979	                    END IF;
```

Reading the checked-in file directly: the `EXECUTE IMMEDIATE` statement is
`ddl/src/pkgb/tt_event_interface.sql:971` (this excerpt is reproduced with the file's real
line numbers in the left column, so `971` = `EXECUTE IMMEDIATE stmt_str USING
p_event_id;`, matching the plan's citation and `depgraph.json`'s `static_resolution_reasons`).

### What builds the statement string — follow every variable to its origin

`stmt_str := 'call ' || v_proc_str || '(:eventid)'` (`:970`). Two literal fragments
(`'call '`, `'(:eventid)'`) surround exactly one variable, `v_proc_str`. Tracing
`v_proc_str` backward:

1. **`v_proc_str` is declared** at `ddl/src/pkgb/tt_event_interface.sql:899`
   (`v_proc_str VARCHAR2(4000);`) — no default, starts NULL on every call.
2. **First assignment**, `:955`:
   ```
   950	                    IF (event_action_rec.procedure_key_id IS NOT NULL AND v_host_id IS NOT NULL) THEN
   ...
   955	                        v_proc_str := mss.OSAG_DBPROP.get_string_by_host_key_id(v_host_id, event_action_rec.procedure_key_id);
   956	                    END IF;
   ```
   Only runs if the current `event_action` row has a non-null `procedure_key_id` AND the
   event has a `v_host_id`. The value comes from `MSS.OSAG_DBPROP.get_string_by_host_key_id`
   — a **host-scoped runtime configuration lookup** (`ddl/src/pkg/mss_osag_dbprop.sql:23`),
   not a literal anywhere in this package's source.
3. **Fallback assignment**, `:960-961`: if `v_proc_str` is still NULL after the DBPROP
   lookup (either `procedure_key_id` was NULL, `v_host_id` was NULL, or the DBPROP lookup
   itself returned NULL), `v_proc_str := event_action_rec.procedure_name` — the
   `procedure_name` column of the CURRENT ROW of the `event_action_cur` cursor
   (`ddl/src/pkgb/tt_event_interface.sql:902-906`), which is itself a plain **table
   column value**, not a literal.
4. **If both are NULL**, the whole `IF (v_proc_str IS NOT NULL)` block at `:968` is
   skipped entirely — no dynamic SQL runs at all (`:977-978` logs "no procedure executed"
   instead). This path is common: 4 of the 8 `event_action` rows in the current master
   data (`masterdata/TT/event_action.csv`, ids `1001-1004`) have both `PROCEDURE_NAME` and
   `PROCEDURE_KEY_ID` NULL.

**Conclusion: `v_proc_str` is data-controlled, not code-controlled.** It originates from
either a per-host configuration property (`mss.dbprop`, read via `OSAG_DBPROP`) or a plain
table column (`tt.event_action.procedure_name`) — never from a string literal inside
`tt.event_interface`'s own source. **A data-controlled value reaches the statement text
via direct `||` concatenation, with no quoting of any kind.** This is the injection
boundary named in the threat model (T-02-21): whatever `v_proc_str` evaluates to at
runtime is executed verbatim as a `CALL ...` statement.

### The set of statements it can actually produce

The **shape** is fully known from source and is invariant: always `call <v_proc_str>(:eventid)`,
always exactly one bind parameter (`p_event_id`, via `USING`), never any other clause. So
this is not "arbitrary SQL" in the way a naive reading of "EXECUTE IMMEDIATE with a
concatenated string" might suggest — it is always a single-argument procedure call.

The **identifier** (`v_proc_str` itself) is where the real uncertainty lives. Two
independent Oracle reference-data sources bound it, but not completely:

**(a) `masterdata/TT/event_action.csv`** (8 rows — this is exported reference/master data,
not ora2pg output — legitimate to consult):

| id | name | procedure_name | procedure_key_id |
|----|------|------|------|
| 1 | mission control operations escalation | `tt.escalation_interface.escalate_os` | NULL |
| 2 | connection down escalation (dbprop) | NULL | 139 |
| 3 | ISP outage escalation (dbprop) | NULL | 140 |
| 4 | customer id notification action | NULL | 399 |
| 1001-1004 | (four notification-type rows) | NULL | NULL |

Only row `1` has a **literal** `procedure_name`: `tt.escalation_interface.escalate_os` —
this is the "only procedure left configured... today" the source comment at `:967`
refers to, but the comment is *itself* describing data, not code, and is explicitly
time-qualified ("today"). Rows `2`, `3`, `4` resolve via DBPROP instead (see below). Rows
`1001-1004` never reach the dynamic-SQL branch at all (both columns NULL).

**(b) `masterdata/MSS/key.csv`**, the DBPROP key catalog, for keys `139`/`140`/`399`
(referenced by `event_action` rows `2`/`3`/`4` above):

| key id | name | string_default | regexp |
|--------|------|------|------|
| 139 | `tt.event-action.connection-down` | `tt.escalation_interface.escalate_customer` | `^tt\.escalation_interface\.(nop\|escalate_(customer\|os))$` |
| 140 | `tt.event-action.isp-outage` | `tt.escalation_interface.nop` | `^tt\.escalation_interface\.(nop\|escalate_isp_outage_to_os)$` |
| 399 | `tt.event-action.customer-id-notification` | `tt.escalation_interface.nop` | NULL (no constraint recorded) |

Every value seen anywhere in this data — the one literal `procedure_name` and every
DBPROP `string_default` — is one of exactly four `TT.ESCALATION_INTERFACE` routines, and
`migration/mapping/name-map.csv` confirms all four exist with the matching
single-`NUMBER`-argument signature the dynamic call expects:

```
TT,ESCALATION_INTERFACE,escalate_os,ESCALATE_OS(NUMBER),...
TT,ESCALATION_INTERFACE,escalate_customer,ESCALATE_CUSTOMER(NUMBER),...
TT,ESCALATION_INTERFACE,escalate_isp_outage_to_os,ESCALATE_ISP_OUTAGE_TO_OS(NUMBER),...
TT,ESCALATION_INTERFACE,nop,NOP(NUMBER),...
```

**This is strong evidence, not proof.** Three things keep the full statement set from
being cleanly "enumerable" in the STATIC sense:

1. **`event_action` is a live, editable table**, not a constant. `masterdata/` is a
   snapshot of what ships in a fresh container, not a guarantee of what a production
   database will always contain. An operator can `INSERT`/`UPDATE` a row with any
   `procedure_name` string at any time, with nothing in this package's source (or, as far
   as `ddl/src/**` shows, at the schema level — no `CHECK` constraint, no FK to a routine
   catalog) preventing it.
2. **Key `399`'s `regexp` is NULL.** Keys `139`/`140` at least *document* an intended
   constraint (whether or not it is actually enforced anywhere is itself unresolved — see
   below), but key `399` documents no constraint on its DBPROP value at all. Its
   `string_default` happens to be `tt.escalation_interface.nop` today, but nothing in the
   source or the key catalog bounds what a host-specific override could be set to.
3. **No `SET`-style procedure with regexp validation is visible in this package's
   dependency**: `ddl/src/pkg/mss_osag_dbprop.sql` (the only `OSAG_DBPROP` source this
   trace is permitted to read) declares only three `GET_*` functions — no `SET`/write
   path, hence no visible enforcement point for the `key.regexp` column at all. Whether
   the regexp is enforced elsewhere (application layer, an admin tool, a trigger not
   under `ddl/src/pkgb`) cannot be determined from this package's source.

### What it calls — and the depgraph gap this closes

`migration/analyze/depgraph.json`'s edge list for `TT.EVENT_INTERFACE` does **not**
include an edge to `TT.ESCALATION_INTERFACE` — confirmed by inspection: the node's
`static_resolution` is `"incomplete"` with `reasons: [{"construct": "EXECUTE IMMEDIATE",
"line": 971}]`, and its `unresolved_refs` array is empty (the lexer never even attempted
to resolve a callee here, because the callee is not textually present as a call — it is
assembled at runtime). This trace closes that gap **for the identifiers this data
currently contains**: the callee is `TT.ESCALATION_INTERFACE.{escalate_os,
escalate_customer, escalate_isp_outage_to_os, nop}`, all four confirmed as real routines
in `name-map.csv` with the matching one-`NUMBER`-argument signature. `TT.EVENT_INTERFACE`
therefore has a **real, undeclared runtime dependency on `TT.ESCALATION_INTERFACE`** that
the depgraph's wave ordering does not capture — `TT.ESCALATION_INTERFACE` is not a member
of the `TT.EVENT_INTERFACE|TT.OSAG_NOTIFY|TT.TICKET_INTERFACE|TT.UTIL` cycle group in
`migration/analyze/known_cycles.json`, and this trace does not add it there (that is a
`depgraph.py`/`known_cycles.json` maintenance decision, out of scope for this plan) — it
is flagged here so Phase 4's translation-order planning sees it. Interestingly,
`TT.ESCALATION_INTERFACE` already has a *visible* (non-dynamic) edge calling **into**
`TT.EVENT_INTERFACE` (per `depgraph.json`'s in-edges for `TT.EVENT_INTERFACE`: `{"from":
"TT.ESCALATION_INTERFACE", "to": "TT.EVENT_INTERFACE", "call_sites": [68, 131]}`) —
meaning the dynamic-SQL edge this trace adds makes `TT.EVENT_INTERFACE` ↔
`TT.ESCALATION_INTERFACE` a **second, previously invisible mutual-recursion pair**, on top
of the already-accepted 4-member cycle group. This is a genuinely new finding this trace
surfaces, not previously in `known_cycles.json` — it should be raised to whoever owns
that file before Phase 4 batches translation order.

### What you cannot determine from source alone, and what would settle it

- **Whether `key.regexp` (keys 139/140) is enforced anywhere at write time.** Not
  determinable from `ddl/src/pkg/mss_osag_dbprop.sql` (read-only API) or from any file
  this trace is permitted to read. An Oracle 19c container with the real DBPROP write
  path available (deferred to v2 as ORA-01 per `.planning/REQUIREMENTS.md`) would settle
  this by attempting to set a DBPROP value for key 139/140/399 that violates the regexp
  and observing whether Oracle rejects it.
- **Whether any production host currently has a DBPROP override for keys 139/140/399
  that differs from the snapshot's `string_default`.** `masterdata/` is a fresh-container
  snapshot, not a production dump; a live Oracle instance (or a production data export)
  is the only thing that would settle what per-host overrides, if any, actually exist
  today.
- **Whether `event_action.procedure_name`/`.procedure_key_id` will ever hold a value
  outside the four `TT.ESCALATION_INTERFACE` routines seen in the current snapshot.**
  Nothing in `ddl/src/**` constrains this column beyond its `VARCHAR2` type (confirmed:
  `ddl/migrated/tables/tables.pg.sql:2195-2206` shows no `CHECK`, no FK on
  `event_action.procedure_name`). This can only be settled by a policy decision made
  during Phase 4 translation (see Recommendation), not by more reading.

## Recommendation

**`EXECUTE format()`** — genuinely dynamic, but with the identifier's plausible range and
required quoting fully specified here.

This is chosen over `STATIC` specifically **because** `event_action` is a live, editable
table and key `399`'s value is not constrained by any visible mechanism: hard-coding a
`CASE`/`IF` dispatch over today's four known targets would look done, pass every test
written against today's `masterdata/` snapshot, and then silently stop matching the day an
operator adds a fifth `event_action` row or changes key `399`'s DBPROP value — exactly the
kind of "looks done but isn't" failure this project's own `PITFALLS.md` warns about. A
`STATIC` translation is the *wrong* kind of confidence here: it would trade a genuine
runtime lookup for a translation-time guess frozen at whatever the snapshot happened to
contain.

The translation must, in order:

1. **Rewrite the Oracle 3-part name to the PostgreSQL flattened name before executing
   anything.** `v_proc_str` values are always shaped `<schema>.<package>.<routine>`
   (Oracle's package-qualified call syntax — e.g. `tt.escalation_interface.escalate_os`).
   Oracle dispatches that 3-part name directly; PostgreSQL, under this project's
   `package_in_name` convention, has no 3-part object at all — the equivalent object is
   the 2-part `tt.escalation_interface_escalate_os` (`migration/README.md`'s naming
   table). **This rewrite is new work the Oracle source never had to do** — nothing in
   `ddl/src/pkgb/tt_event_interface.sql` performs it, because Oracle never needed it.
   Split `v_proc_str` on `.`: the first component is the PostgreSQL schema (unchanged,
   lowercased), and the remaining components join with `_` to form the PostgreSQL object
   name (`escalation_interface` + `_` + `escalate_os`).
2. **Validate the resolved 2-part name against an explicit allowlist before executing
   it**, rather than trusting `%I` quoting alone to make arbitrary data safe to execute.
   `%I` prevents SQL-syntax injection (a value like `x(); DROP TABLE t; --` cannot break
   out of the identifier position), but it does **not** prevent a compromised or
   misconfigured config value from causing `tt.event_interface` to call an *unintended
   but syntactically valid* function. Given the finding above (nothing in `ddl/src/**`
   constrains `event_action.procedure_name` or DBPROP key 399's value), the safer
   PostgreSQL-native translation is: look the resolved `(schema, object)` pair up against
   the known `TT.ESCALATION_INTERFACE.*` routines from `migration/mapping/name-map.csv`
   (a `CASE`/lookup-table dispatch, or a `to_regprocedure(...)` existence check scoped to
   an explicit allowed-schema set) before calling it, and raise a labelled error if the
   resolved name is not on the list — this is strictly safer than either a frozen
   `STATIC` dispatch (which cannot grow) or blind `%I`-quoted execution (which trusts
   config data as code).
3. **Execute with the bind parameter kept as a genuine parameter, not string-concatenated
   in**, mirroring what the Oracle source itself does (`USING p_event_id`, not
   `||p_event_id||`):
   ```sql
   EXECUTE format('CALL %I.%I($1)', v_schema, v_object) USING p_event_id;
   ```
   where `v_schema`/`v_object` are the post-rewrite, post-allowlist-validated identifier
   parts from step 1-2. `%I` here is defense in depth (correct identifier quoting), not
   the primary safety mechanism (the allowlist in step 2 is).
4. **Preserve the exact `WHEN OTHERS` swallow-and-log semantics** of `:973-975` (log via
   `plog.err`, do not re-raise) — this trace does not change that, it only changes what
   happens on the success path.

**Sub-item flagged UNRESOLVED — DO NOT GUESS:** whether the allowlist in step 2 should be
scoped narrowly to `TT.ESCALATION_INTERFACE.*` (matching what has ever been seen in the
data) or more broadly to "any procedure taking exactly one `NUMBER`/`bigint` argument" is
a **translation-time policy decision**, not something the Oracle source settles — Oracle
itself imposes no such constraint (it will happily `EXECUTE IMMEDIATE` any syntactically
valid `CALL`). This decision belongs to whoever implements this site's translation in
Phase 4 (wave assignment: after `TT.ESCALATION_INTERFACE` and `TT.EVENT_INTERFACE` are
both loaded, given the newly-surfaced mutual dependency above), and must be recorded in
that translation's own commit/spec-amendment, not invented here.
