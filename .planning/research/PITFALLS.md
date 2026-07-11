# Pitfalls Research

**Domain:** Oracle 19c PL/SQL → PostgreSQL 17 PL/pgSQL code migration (spec-first, static-analysis-only, no live Oracle)
**Researched:** 2026-07-10
**Confidence:** MEDIUM (cross-checked against PostgreSQL official docs, AWS/Cybertec/Dalibo/EDB migration literature, ora2pg/orafce project docs, and grounded against this repo's actual `ddl/src/pkgb` source — no live-Oracle empirical verification possible per project constraints)

## Critical Pitfalls

### Pitfall 1: Implicit `SELECT INTO` no longer raises `NO_DATA_FOUND`

**What goes wrong:**
In Oracle, every `SELECT ... INTO` that returns zero rows raises `NO_DATA_FOUND`, and every one that returns more than one row raises `TOO_MANY_ROWS`. In PL/pgSQL, a plain `SELECT INTO` (without `STRICT`) silently assigns the first row or sets the target to NULL on zero rows — no exception is ever raised, and the multi-row case is silently truncated to one row. This repo's package bodies rely on `NO_DATA_FOUND` as normal control flow in at least 22 places (e.g. `auth_osag_auth.sql`: `WHEN NO_DATA_FOUND THEN NULL; -- there is no profile for this login -> nothing to do`), including inside row-level triggers (`ddl/src/triggers/APPID.sql`: `SELECT ... INTO v_link_class_id ... EXCEPTION WHEN NO_DATA_FOUND THEN :NEW.LINK_CLASS_ID := NULL;`).

**Why it happens:**
`STRICT` is not the default in PL/pgSQL (Oracle's strict behavior *is* the default in PL/SQL), and ora2pg's mechanical pattern-matching does not reliably decide, statement by statement, whether the original code depended on the exception path. A blanket "add STRICT everywhere" pass is also wrong — some Oracle `SELECT INTO`s never expected to hit zero/multiple rows and adding STRICT there just introduces a new failure mode that wasn't in the original contract.

**How to avoid:**
For every `SELECT INTO` migrated, the derived spec must explicitly record: (a) is zero-rows a possible/expected case, and if so what the Oracle exception handler did; (b) is multiple-rows possible, and what Oracle did. Translate to `SELECT ... INTO STRICT ...` plus explicit `EXCEPTION WHEN NO_DATA_FOUND` / `WHEN TOO_MANY_ROWS` blocks whenever the Oracle source had a handler (or relied on propagating NO_DATA_FOUND to a caller). Where Oracle code had no exception handler around a SELECT INTO that could plausibly return zero rows, that is itself a latent Oracle bug/assumption — the spec must capture and preserve it (STRICT will simply raise an unhandled exception, matching Oracle's unhandled NO_DATA_FOUND propagation).

**Warning signs:**
- grep for `SELECT.*INTO` without a following `STRICT` keyword in translated code.
- Any translated block with `EXCEPTION WHEN NO_DATA_FOUND` where the corresponding SELECT lost `STRICT` during translation (dead handler, never reached).
- Test failures on empty-result-set inputs that pass on non-empty inputs (asymmetric coverage is the tell).

**Phase to address:** Spec derivation phase (record STRICT/exception intent per SELECT INTO) and package/trigger translation phase (enforce STRICT + handler pairing); should be a mechanical lint/check run at translation-verification time, not caught ad hoc.

---

### Pitfall 2: Empty string treated as NULL in Oracle, but not in PostgreSQL

**What goes wrong:**
Oracle collapses `''` and `NULL` into the same value for storage, `NOT NULL` constraint checks, comparisons, and concatenation. PostgreSQL treats `''` as a distinct zero-length string: it satisfies `NOT NULL` constraints, `col = ''` never matches a NULL column, and `NULL || 'x'` yields `NULL` (not `'x'`, unlike Oracle where `NULL || 'x'` yields `'x'`). `mcdb_checks_consistency.sql` has `p_check_group IN VARCHAR2 DEFAULT ''` — under Oracle semantics a caller passing nothing or explicit `''` are identical; under PostgreSQL they are not, and any downstream `IF p_check_group IS NULL THEN` check on the ported code will silently stop matching callers that pass `''`.

**Why it happens:**
This is a fundamental engine-level semantic difference, not a syntax issue — ora2pg cannot fix it by pattern substitution, and it is invisible in code review unless you specifically trace every `IS NULL`, `!=`, `||`, and default-value comparison against string-typed parameters and columns.

**How to avoid:**
During spec derivation, flag every VARCHAR2/CLOB parameter, column, and local variable that participates in an `IS NULL`/`IS NOT NULL` check, an equality/inequality comparison, or string concatenation. Decide per-case: normalize `''` to `NULL` on write (via trigger or explicit `NULLIF(x, '')` at the translation boundary) if Oracle-identical semantics matter for that data, or add `CHECK (col <> '')` where Oracle's implicit "empty means absent" `NOT NULL` behavior must be preserved. Never leave this to orafce's `NVL()` alone — `NVL('', x)` in Oracle returns `x`, but `NVL('', x)` in PostgreSQL (even with orafce's `NVL`) returns `''` because PostgreSQL's `''` is not NULL, so `NVL` never even sees a NULL to replace.

**Warning signs:**
- Table/column diffs where an Oracle `NOT NULL` column has no PostgreSQL `CHECK` equivalent after migration.
- Test suites that only insert `NULL` and never insert `''` for string columns (the gap won't be caught).
- Downstream client code checking `col = ''` or `col IS NULL` inconsistently.

**Phase to address:** Spec derivation phase (catalog affected columns/params) and DDL/data-migration phase (constraints + normalization); must be verified with tests that explicitly assert both `''` and `NULL` inputs behave identically where Oracle made them identical.

---

### Pitfall 3: `WHEN OTHERS` / `RAISE_APPLICATION_ERROR` do not map 1:1 to PostgreSQL's exception model

**What goes wrong:**
This codebase uses `WHEN OTHERS THEN plog.err(...); RAISE;` extensively (27 occurrences) and `RAISE_APPLICATION_ERROR(-20NNN, msg)` for custom application errors (9 occurrences, e.g. `mc_osag_isp_monitoring.sql`, `mss_osag_ip_test.sql`). Oracle's `WHEN OTHERS` catches every error by a single wildcard; PostgreSQL requires `WHEN OTHERS` too, but SQLCODE/SQLERRM numeric error codes are structurally different (Oracle uses negative integers like `-20001`; PostgreSQL uses five-character SQLSTATE strings). Naive translation of `RAISE_APPLICATION_ERROR(-20001, 'msg')` to `RAISE EXCEPTION 'msg'` loses the distinguishing error code entirely, breaking any caller (including client Perl/Java code) that branches on the Oracle error number.

**Why it happens:**
ora2pg mechanically substitutes `RAISE_APPLICATION_ERROR` calls but has no way to know whether calling code elsewhere depends on the specific `-20NNN` code to distinguish error types — that dependency often lives in client code outside this repo entirely.

**How to avoid:**
Standardize a mapping convention up front: use `RAISE EXCEPTION 'msg' USING ERRCODE = '<custom 5-char SQLSTATE in the P0001-P9999 or application-reserved range>'`, and maintain a table mapping each Oracle `-20NNN` code used in this codebase to a chosen PostgreSQL custom SQLSTATE, published alongside the client rename regexps so client code can be updated consistently. For `WHEN OTHERS THEN <log>; RAISE;`, translate to `EXCEPTION WHEN OTHERS THEN <log>; RAISE;` (PL/pgSQL supports bare `RAISE;` to re-raise). `plog.err` must still survive the rollback that the re-raise causes — and it does so for free, because `plog` emits a UDP datagram rather than writing to the database (Pitfall 4). No autonomous-transaction emulation is involved.

**Warning signs:**
- Client code (Perl/Java) with `if (errorCode == -20001)`-style branches that silently stop matching after migration.
- Any translated `RAISE EXCEPTION` without an explicit `ERRCODE`.
- Loss of distinction between "expected business error" and "unexpected system error" once everything becomes a generic PostgreSQL exception.

**Phase to address:** Spec derivation phase (catalog all `RAISE_APPLICATION_ERROR` codes and their consumers) and package translation phase (apply consistent ERRCODE mapping); the Oracle-code-number → SQLSTATE mapping table should ship as part of the client regexp/rename deliverable.

---

### Pitfall 4: Autonomous transactions silently become ordinary (rollback-vulnerable) calls

> **CORRECTED — project decision supersedes the original finding for `plog`.**
> The original research recommended emulating `PRAGMA AUTONOMOUS_TRANSACTION` via `dblink`/`pg_background` so `plog` writes survive rollback. **This is rejected.** `plog` does not get an autonomous-transaction emulation in PostgreSQL. It is re-implemented as a non-transactional UDP log shipper (see below). Do not plan, benchmark, or build `dblink`/`pg_background` machinery for logging.

**What goes wrong (the part that still applies):**
Three package bodies use `PRAGMA AUTONOMOUS_TRANSACTION` so their writes survive a later rollback in the caller. PostgreSQL has no equivalent, and ora2pg drops the pragma silently. The three sites split into two very different categories, and only the second is still a problem:

1. **Log shipping — SOLVED BY DESIGN, not by emulation.** `osag_osag_plog.sql` (`Log`, called by `Emerg`/`Alert`/`Crit`/`Err`/`Warning`/`Notice`/`Info`/`Debug`) uses an autonomous transaction purely to `ENQUEUE` onto the Oracle AQ queue `MCDB_MONITOR.plog_messages` and `COMMIT` it. In PostgreSQL the AQ queue and the autonomous transaction both disappear: `plog` emits a **fire-and-forget UDP datagram** to the telemetry sink instead. A UDP send is not part of any transaction, so rollback-survival is inherent rather than emulated — the datagram has already left the backend process by the time the caller rolls back. This is strictly *better* than the Oracle behavior (no queue table to drain, no commit cost on the error path) and removes the highest-risk item from the original research.
2. **Table writes — STILL A REAL PROBLEM.** Two autonomous-transaction sites are genuine database writes that UDP does *not* address: `mcdb_checks_consistency.insert_result` (persists consistency-check results that must survive a failing check) and `tt_util.close_old_dev_tickets`. A third, `plog.AuditUsage` (174 call sites), is *inside* the plog package but is not logging at all — it `UPDATE`s `osag.plsql_audit.last_used` and commits, with `WHEN OTHERS THEN rollback`. These three need an explicit decision, and it is not "UDP".

**Why it happens:**
ora2pg drops the pragma or emits a no-op comment; the semantic loss is invisible unless someone checks that the write survives a failure.

**How to avoid:**
- **For `plog.*` logging (levels 0–7):** implement as a UDP emitter — no queue, no autonomous transaction, no `dblink`, no `pg_background`. The rollback-survival test still has value, but it now asserts *the datagram was sent* (observed at the collector), not *a log row exists*.
- **For the three real table-writing autonomous transactions:** decide each explicitly in the cross-cutting phase. Options, cheapest first: (a) re-emit as a UDP telemetry event and drop the table write entirely — plausible for `AuditUsage`, which is usage telemetry that already tolerates loss (it swallows its own errors); (b) accept transactional semantics (write folds into the caller's transaction and is lost on rollback) where losing the row on rollback is actually correct; (c) only if a write genuinely must survive an unrelated rollback, reach for `dblink`. Do not apply (c) reflexively — it was the original research's blanket answer and it is overkill for at least `AuditUsage`.

**Warning signs:**
- A `dblink`/`pg_background` dependency appearing anywhere in the logging path — that means the UDP decision was quietly reverted.
- `PRAGMA AUTONOMOUS_TRANSACTION` in a *table-writing* Oracle routine with no corresponding explicit decision recorded in the transaction-semantics audit.
- Test suites that only test the happy path (no test ever forces a rollback after a log/audit call).

**Phase to address:** Phase 3 (Cross-cutting Semantics). `plog` is still load-bearing and still goes first — nearly every package's `WHEN OTHERS` handler calls it — but the work is now "build the UDP emitter and the syslog-shaped payload", not "emulate autonomous transactions". The three table-writing autonomous sites are a separate, much smaller decision list in the same phase.

---

### Pitfall 5: Package-level state has no PL/pgSQL equivalent — `package_in_name` flattening can silently drop session state or package initialization

**What goes wrong:**
Oracle packages provide two things this migration's `package_in_name` convention (flattening to prefixed standalone functions in the same schema) does **not** automatically preserve: (1) package-body-level variables that persist for the life of a session (package "global" state), and (2) a package initialization block (unnamed `BEGIN...END` at the end of the package body) that runs once per session on first reference. A quick scan of this repo's `ddl/src/pkgb` shows package-body-level declarations are mostly `CONSTANT`s (safe — these become plain PL/pgSQL constants/no-op), but the absence of *mutable* globals in the sampled packages must not be assumed to hold for all 48 packages — it must be verified per package during spec derivation, because if even one package relies on a mutable package variable (e.g., a cache, a "have I already logged this session" flag, a sequence-like counter), naive flattening to stateless functions will change behavior silently (each call re-initializes what Oracle would have kept warm for the session).

**Why it happens:**
`package_in_name` (chosen naming convention here) intentionally discards the package as a scoping/state construct and keeps only the naming convention; ora2pg's own package-to-schema mode has the same blind spot in the opposite direction (it makes packages into schemas, which does capture some notion of grouping but still has no session-persistent variables in PostgreSQL either way — PostgreSQL functions have no concept of "package-session" state).

**How to avoid:**
As part of spec derivation for each of the 48 packages, explicitly grep and record: (a) any package-body-level variable declaration that is *not* `CONSTANT`, (b) any unnamed initialization block. Where mutable state exists, decide the replacement per case: session-scoped custom GUC (`current_setting`/`set_config` with `is_local => false` for session lifetime), a session-scoped temp table, or (if the "state" is really just a memoization/cache) explicit re-derivation each call (safe default, but note the performance/behavior delta). Do not let this get lost simply because `package_in_name` was already prototyped and "looks done" — the prototype (`pg_migration/output/package_in_name/`) is raw ora2pg output and per project context is known to contain errors; it has not been verified against package-global-state semantics.

**Warning signs:**
- Any Oracle package with a body-level variable that is assigned (not just declared/initialized once as a constant) inside more than one procedure.
- Any package body with a trailing unnamed `BEGIN...END` initialization block.
- Behavioral spec that says "cached" or "computed once per session" anywhere.

**Phase to address:** Spec derivation phase, per-package, as an explicit checklist item before translation begins on that package — this is exactly the kind of thing static analysis can and must catch systematically (grep-able), so it should be a repeatable check applied to all 48 packages, not discovered ad hoc during translation.

---

### Pitfall 6: Choosing FUNCTION vs PROCEDURE wrong breaks `COMMIT`-dependent Oracle procedures

**What goes wrong:**
PostgreSQL functions can never issue `COMMIT`/`ROLLBACK` — they always run inside the caller's transaction, and any error rolls back everything the function did. PostgreSQL procedures (PG 11+), invoked only via `CALL` (never inside a query or another function body), *can* issue `COMMIT`/`ROLLBACK`, but only at the top level of a `CALL`/`DO` or through an uninterrupted `CALL → CALL` chain — and after a `COMMIT` inside a procedure, execution continues in a **new** transaction, so anything the caller assumed would still be visible/locked from before the commit (temp tables not created `ON COMMIT PRESERVE ROWS`, advisory locks, cursors without `WITH HOLD`) silently breaks. Any Oracle procedure in this codebase's ~49 package bodies that issues an explicit `COMMIT` (independent of the 3 known `PRAGMA AUTONOMOUS_TRANSACTION` cases) must become a PostgreSQL **procedure**, not a function — and every caller of it must also become callable via `CALL`, which can cascade the FUNCTION→PROCEDURE decision up a whole call chain.

**Why it happens:**
Oracle does not distinguish functions and procedures for transaction-control purposes as strictly as PostgreSQL does; ora2pg's default output tends toward creating PostgreSQL functions (since Oracle functions that return a value map naturally to functions), and a package's mix of "procedure that commits" and "function that returns a value" doesn't cleanly separate — some Oracle functions in this codebase may also commit internally, which has **no direct PostgreSQL translation** for functions at all (would need to become a procedure with an OUT parameter, changing every call site).

**How to avoid:**
During spec derivation, grep every package body for explicit `COMMIT`/`ROLLBACK` statements (separate from the 3 autonomous-transaction ones already found) and record, per callable, whether it commits. Any Oracle FUNCTION that commits must be redesigned as a PostgreSQL PROCEDURE with an OUT parameter (breaking its usability inside SQL expressions — flag this for the client regexp/rename deliverable since call sites change shape, not just name). Trace the full call graph for anything that commits, since the "uninterrupted CALL chain" rule means an intervening plain function call in the chain silently disables the ability to commit deeper in the stack.

**Warning signs:**
- Any Oracle FUNCTION (not procedure) containing `COMMIT`.
- A call chain where a PostgreSQL procedure that commits is invoked from inside a function body rather than via top-level/chained `CALL` (this is a hard PostgreSQL error, not a silent bug — but better caught in spec/design than at translation-verification time).
- Client (Perl/Java) code calling something as a scalar-returning function that must become a procedure — this changes the calling convention entirely.

**Phase to address:** Spec derivation phase (grep + call-graph analysis for COMMIT/ROLLBACK) must happen before translation starts, because it determines each object's PL/pgSQL *kind* (FUNCTION vs PROCEDURE) — getting this wrong mid-translation means redoing call sites across multiple packages.

---

### Pitfall 7: `ora2pg`'s raw output contains systematic mistranslation classes, not just typos — never trust it as a starting point without re-deriving from Oracle source

**What goes wrong:**
This repo's own `.planning/codebase/CONCERNS.md` audit already found concrete instances: `GET DIAGNOSTICS v_return = ROW_COUNT > 0;` (invalid PostgreSQL syntax) at two locations, unrewritten `DBMS_UTILITY.format_error_backtrace()` / `DBMS_UTILITY.GET_TIME()` / `DBMS_RANDOM.varchar()` (malformed) / `DBMS_CRYPTO` / `UTL_SMTP` / `UTL_I18N.STRING_TO_RAW()` calls left completely untranslated (references to Oracle packages that don't exist in PostgreSQL at all), and known-missing views with Oracle system-generated "ghost columns" (`sys_nc00008$`) carried over verbatim. Beyond these confirmed examples, the general classes of ora2pg failure are: (1) dynamic SQL (`EXECUTE IMMEDIATE`, `DBMS_SQL.PARSE` — 13 occurrences of `DBMS_SQL` in this codebase) cannot be resolved by static pattern-matching at all, since the actual SQL text is only known at runtime; (2) nested/local PL/SQL functions declared inside another function's body have no PL/pgSQL equivalent and must be hoisted to standalone functions, changing naming and scoping; (3) nothing in ora2pg's output should be assumed correct merely because it "compiles" — mechanical regex substitution (e.g., blind `SYSDATE` → `clock_timestamp()`, `NVL` → `COALESCE`) can silently change semantics (see Pitfall 2 for why `NVL`/`COALESCE` substitution is not equivalent for string-typed arguments).

**Why it happens:**
ora2pg is a pattern-matching/regex tool, not a semantic compiler — it has no model of Oracle PL/SQL execution semantics, so it can only handle transformations expressible as local textual substitution. This project's own decision to do spec-first translation from Oracle source (not "fix up ora2pg output") is the direct, correct response to this — but the raw `pg_migration/output/` prototype exists in the repo and there is a real risk that translators, under time pressure, start "fixing" the ora2pg output line-by-line instead of independently deriving a spec from `ddl/src/pkgb` and writing fresh, spec-verified PL/pgSQL.

**How to avoid:**
Use ora2pg output only as a checklist of "things to look for" (e.g., it already surfaces every `DBMS_*`/`UTL_*` call site, which is useful), never as the base to edit into working code. Every translated function/procedure must be traceable to a derived spec from the Oracle source, and every DBMS_*/UTL_* call site flagged by the CONCERNS.md audit needs an explicit, deliberate PostgreSQL replacement decision (see Pitfall 9) recorded in the spec, not a leftover Oracle-package reference "to fix later."

**Warning signs:**
- Any `DBMS_`, `UTL_`, or other Oracle-package-qualified identifier surviving into a file intended as final PostgreSQL code.
- Translated code that closely mirrors ora2pg's line-by-line structure rather than the Oracle source's actual control flow (a sign of "patching ora2pg" rather than "translating from spec").
- `GET DIAGNOSTICS` used with a boolean/comparison RHS instead of the correct `GET DIAGNOSTICS var = ROW_COUNT;` followed by a separate comparison.

**Phase to address:** This is a process guardrail that applies across every package-translation phase — the roadmap should explicitly require "derived from `ddl/src/pkgb` spec" as an acceptance criterion for each translated object, and a scripted check for leftover `DBMS_`/`UTL_`/Oracle-only syntax should run as an automated gate before a package is marked complete.

---

### Pitfall 8: Trusting `orafce` for full Oracle compatibility instead of a narrow compatibility shim

**What goes wrong:**
`orafce` implements a useful subset of Oracle built-ins (NVL, `dbms_output`, `plvdate`, partial `utl_*`, etc.) but is explicitly *not* a full compatibility layer: it implements only a subset of `dbms_sql` (this codebase has 13 `DBMS_SQL` call sites — must verify each against orafce's actual subset, not assume coverage), its `VARCHAR2`/`NVARCHAR2` types do not enforce Oracle's 4000-byte declared-size limit (so a translated column relying on Oracle silently truncating/erroring at 4000 bytes will behave differently), `length()` semantics differ for byte vs. character semantics depending on encoding, and past orafce version upgrades have changed function volatility (STABLE vs IMMUTABLE) in ways that broke existing functional indexes — meaning orafce is not even a stable, version-pinned dependency to lean on long-term. Additionally, Oracle idioms like BULK COLLECT/FORALL-style bulk operations (not found in this codebase's package bodies via a targeted grep, which is good news, but still worth a final confirmation pass) have no benefit in PostgreSQL's single-process execution model, and orafce's own emulation of Oracle collection patterns carries real CPU/memory overhead if leaned on for large datasets.

**Why it happens:**
The project's own constraint explicitly allows orafce "to reduce translation friction," which is reasonable, but "allowed" can be misread as "sufficient" — teams under deadline pressure tend to reach for orafce compatibility functions as a way to avoid rewriting logic, even where a native PostgreSQL idiom would be more correct and more maintainable.

**How to avoid:**
Treat orafce as a bridge for genuinely mechanical Oracle-isms (e.g., `NVL` where NULL semantics are actually equivalent — see Pitfall 2 for when they aren't) — not as a substitute for actually understanding what a DBMS_SQL/UTL_* call was doing. Pin the exact orafce version used and re-verify function volatility assumptions if it's ever upgraded. For each of this codebase's DBMS_SQL, DBMS_UTILITY, DBMS_CRYPTO, DBMS_AQ, DBMS_REDEFINITION, DBMS_RANDOM, and DBMS_OUTPUT call sites (13, 13, 7, 11, 9, 1, 12 occurrences respectively — see Pitfall 9), make an explicit per-package decision: orafce shim, `pgcrypto`/native PostgreSQL equivalent, or architectural replacement, and record which.

**Warning signs:**
- A translated function that "works" only because orafce happens to paper over a semantic gap that wasn't actually verified against a spec.
- Functional indexes on orafce-provided functions (fragile against orafce version bumps).
- Any reliance on `VARCHAR2(4000)`-style length enforcement without an explicit `CHECK (length(col) <= 4000)`.

**Phase to address:** Package translation phase, as a running checklist per package — should be reviewed again at the final integration/container-assembly phase when orafce's actual installed version is pinned for the deliverable.

---

### Pitfall 9: `DBMS_*`/`UTL_*` package calls need a deliberate per-family replacement strategy, not ad hoc fixes

**What goes wrong:**
This codebase has confirmed usage of `DBMS_UTILITY` (13), `DBMS_SQL` (13), `DBMS_OUTPUT` (12), `DBMS_AQ` (11 — AQ queues are explicitly out of scope for this milestone per PROJECT.md, but any *non-queue* package that merely logs/inspects via DBMS_AQ-adjacent calls must not be swept into "deferred" by mistake), `DBMS_REDEFINITION` (9), `DBMS_CRYPTO` (7), and `DBMS_RANDOM` (1), plus (from CONCERNS.md) `UTL_SMTP` and `UTL_I18N.STRING_TO_RAW`. Each family needs a different replacement class: `DBMS_UTILITY.GET_TIME()` → `extract(epoch from clock_timestamp())`; `DBMS_UTILITY.format_error_backtrace()` → no direct equivalent, needs `GET STACKED DIAGNOSTICS`-based custom error context capture; `DBMS_CRYPTO` → `pgcrypto` extension; `DBMS_RANDOM` → native `random()`/`gen_random_uuid()`; `UTL_SMTP` → no in-database equivalent at all (email must move to the application layer or a `plpython3u`/external-call shim); `DBMS_SQL` (dynamic SQL) → PL/pgSQL's `EXECUTE`/`format()`, but requires re-deriving the actual dynamic SQL logic since DBMS_SQL's parse/bind/execute cursor model doesn't map mechanically; `DBMS_REDEFINITION` (online table redefinition) → has no PostgreSQL equivalent at all and any package using it for an Oracle-specific operational task (not application logic) may be out of scope for this migration entirely and needs a scoping decision, not a translation attempt.

**Why it happens:**
These are exactly the classes of Oracle-vendor-package calls that a pattern-matching tool like ora2pg cannot translate (no PostgreSQL syntax exists to substitute in), so they're left as dead references pointing at nonexistent objects — this is confirmed, not hypothetical, per the CONCERNS.md audit of the raw ora2pg output.

**How to avoid:**
Build a single reference table (per DBMS_*/UTL_* family found) mapping Oracle call → PostgreSQL replacement strategy, reviewed once, applied consistently across all packages that use it (rather than re-deciding the DBMS_UTILITY.GET_TIME() replacement 8 separate times inconsistently, for instance). For `DBMS_REDEFINITION` specifically, first determine whether any of the 9 occurrences are actually invoked as part of application-visible behavior (in which case they need a real design) versus purely operational/maintenance scripting (in which case they may belong in the same "deferred, architectural replacement" bucket as jobs/queues/mviews already carved out of scope in PROJECT.md).

**Warning signs:**
- The same DBMS_* family translated two different ways in two different packages without a documented reason.
- Any DBMS_REDEFINITION or UTL_SMTP call site not yet triaged into "in scope, needs design" vs. "out of scope, defer."

**Phase to address:** Should be resolved as a cross-cutting reference/design pass early — ideally right after spec derivation begins and before package-by-package translation, since several packages likely share the same DBMS_* dependency and re-deciding per-package wastes effort and risks inconsistency.

---

### Pitfall 10: `%TYPE`/`%ROWTYPE` references break silently when the referenced object is renamed (`package_in_name`) or restructured

**What goes wrong:**
This codebase has heavy reliance on `%TYPE` (664+ occurrences) and `%ROWTYPE` (35 occurrences) — e.g. `osag_osag_plog.sql`: `lnumb all_source.line%TYPE;`, `callr t_msg_record.SENDER_PROC%TYPE;`. PL/pgSQL supports `%TYPE`/`%ROWTYPE` natively, so this is mechanically translatable in the common case — but two migration-specific risks exist: (1) `%TYPE` references against **Oracle data dictionary views** (`all_source.line%TYPE` has no PostgreSQL equivalent view with that shape at all — this specific one needs a hand replacement, not a mechanical rename); (2) `%TYPE` references against columns of tables/types that get renamed or restructured as part of this same migration (via `package_in_name` or DDL changes) will point at a name that no longer exists, and PostgreSQL will only catch this at function-creation time (a hard failure, not silent) *if* the referenced table already exists in the target schema at translation time — but if translation order isn't carefully sequenced (DDL before code, dependency-ordered), you can get transient false negatives during incremental builds that mask a real dangling reference until the final full-container build.

**Why it happens:**
`%TYPE`/`%ROWTYPE` create a hidden, non-textual dependency on the referenced object's *current* shape — a purely textual/regexp-based rename pass (like the client-facing regexp deliverable this project produces) will not have any concept of "this `%TYPE` reference must be updated" unless the object name itself is part of the type reference (e.g., `some_view%ROWTYPE` where `some_view` is being renamed).

**How to avoid:**
During spec derivation, catalog every `%TYPE`/`%ROWTYPE` reference in `ddl/src/pkg`/`ddl/src/pkgb` against Oracle data-dictionary objects (`all_source`, `user_tables`, etc. — these need explicit hand-replacement, there is no PostgreSQL equivalent) separately from references against this schema's own tables/types (these are mechanically portable as long as the DDL migration and object renames are applied *before* the code that references them, and the container build order enforces that dependency). Add a final-build validation step that creates every function/procedure from scratch against the fully-migrated DDL, specifically to surface any dangling `%TYPE`/`%ROWTYPE` reference — this class of error is exactly what "runnable container built from scratch" (already a stated deliverable) is good at catching, so make sure that build step runs `%TYPE`-bearing objects last relative to their dependencies, not first.

**Warning signs:**
- Any `%TYPE`/`%ROWTYPE` reference to an `all_*`/`user_*`/`dba_*` Oracle dictionary view.
- Function-creation errors during full-container rebuild citing "relation does not exist" for a `%TYPE` target — a sign the DDL/object-rename ordering wasn't respected.

**Phase to address:** Spec derivation (catalog dictionary-view %TYPE references specifically) and final container-assembly/build-order phase (dependency-ordered rebuild as the systematic catch-all).

---

### Pitfall 11: Sequences/triggers interplay — Oracle's `.nextval`/`.currval` session semantics vs. PostgreSQL sequence functions

**What goes wrong:**
This codebase uses Oracle sequence syntax extensively (e.g. `auth.seq_profile.nextVal`, `auth.SEQ_USER_COMPANY_UNIT_SCOPE.nextval`). PostgreSQL sequences exist and are semantically very close (both are unlogged, gap-tolerant, session-independent-of-transaction-rollback counters), so this is one of the *lower*-risk translation areas — but two things still need explicit attention: (1) Oracle's `sequence.CURRVAL` requires that `NEXTVAL` was already called *in the same session*; PostgreSQL's `currval('sequence')` requires `nextval()` was called in the same **session** too, but PostgreSQL raises an explicit error (`currval of sequence "x" is not yet defined in this session`) rather than Oracle's ORA-08002, and pooled-connection environments (common in migrated web apps) can violate the "same session" assumption in ways that were previously masked by Oracle connection-pool configuration; (2) any Oracle trigger relying on `:NEW.id` being populated by a `BEFORE INSERT` trigger reading `sequence.NEXTVAL` (a common Oracle pre-12c pattern, before `GENERATED AS IDENTITY` / default-value sequences existed) needs to be either kept as-is (a `BEFORE INSERT` trigger calling `nextval()`, which works identically in PostgreSQL) or consciously upgraded to a PostgreSQL `GENERATED BY DEFAULT AS IDENTITY` column default — these are behaviorally almost identical but not code-identical, and if some tables use the old trigger pattern and others get "modernized" to identity columns inconsistently, cross-table code that assumes a uniform ID-generation mechanism (e.g., generic audit/logging code that reads back a just-inserted ID) can break.

**Why it happens:**
Sequences are one of the few areas where Oracle and PostgreSQL are nearly identical, which paradoxically makes them a candidate for "let's modernize this while we're at it" scope creep — introducing subtle behavioral drift versus a purely mechanical, low-risk translation.

**How to avoid:**
Default to a purely mechanical translation of Oracle sequences and any pre-existing `BEFORE INSERT ... :NEW.id := sequence.NEXTVAL` trigger pattern (keep the trigger, just translate the syntax) rather than "modernizing" to identity columns as part of this migration — identity-column modernization, if wanted, should be a deliberate, separately-scoped follow-up, not incidental to behavior-preserving translation. Verify that no code relies on Oracle's specific `ORA-08002` error text/number for `CURRVAL`-before-`NEXTVAL` (WHEN OTHERS handlers that inspect `SQLERRM` text specifically for this would break, though none were observed in the targeted greps above — this should still be explicitly re-checked as a residual risk since only two sequence-adjacent files were sampled).

**Warning signs:**
- Trigger translation PRs that also convert a table to `GENERATED AS IDENTITY` "since we're already touching it" — flag as scope creep unless explicitly decided.
- Any `WHEN OTHERS` handler whose logic branches on the literal text of `SQLERRM`.

**Phase to address:** Trigger/procedure translation phase — treat as low-risk but explicitly forbid unplanned identity-column modernization within this milestone's scope.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|-----------------|------------------|
| Patch ora2pg's raw output line-by-line instead of deriving spec from Oracle source | Faster first pass, reuses existing 15k+ line artifact | Inherits ora2pg's silent semantic errors (Pitfalls 2, 7); untraceable to Oracle intent | Never — contradicts the project's own spec-first methodology |
| Blanket-add `STRICT` to every `SELECT INTO` without checking Oracle's original exception handling | Fast, mechanical | Introduces new unhandled-exception failures where Oracle never expected zero/multi-row results | Only after per-statement spec review confirms it's safe (Pitfall 1) |
| Defer package-global-state audit ("we didn't find any in the sample, probably fine") | Saves upfront analysis time | One missed mutable global variable silently changes behavior across all calls to that package | Never — must be checked per package, not sampled |
| Use orafce shims wherever "it compiles" | Avoids rewriting Oracle-specific logic | Hidden semantic gaps (length limits, volatility, NULL/'' handling) surface later as data corruption or index breakage | Acceptable for genuinely mechanical 1:1 cases (e.g., `SYSDATE`-adjacent date functions) only after verifying semantics match |
| Translate every Oracle FUNCTION as a PostgreSQL FUNCTION by default | Matches ora2pg default output, less restructuring | Silently breaks any function that internally COMMITs (Pitfall 6) — hard PostgreSQL error only surfaces at CALL-time, possibly late | Only after grep-confirming no COMMIT/ROLLBACK inside |
| Skip the "log survives rollback" test for `plog` (now: datagram reaches the collector after the caller rolls back) | Ships faster | Failure-path diagnostics vanish in production exactly when needed most | Never |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|--------------|------------------|-------------------|
| `plog` logging package | Port the Oracle shape (AQ enqueue inside an autonomous transaction) by emulating autonomous transactions with `dblink`/`pg_background` | Re-implement as a non-transactional **UDP log shipper** — no queue, no autonomous transaction, no `dblink`. Rollback-survival is inherent to UDP. Verify by asserting the datagram reached the collector (Pitfall 4) |
| `aserto.*` authorization calls in triggers (30+ call sites per CONCERNS.md) | Translate trigger body mechanically without adding error handling; a failed aserto call currently has undocumented failure behavior and cascades to the triggering DML | Decide explicitly whether aserto failures should abort the triggering transaction (current implicit behavior) or be caught/logged — do not leave this ambiguous; write a test for the chosen behavior |
| DBMS_SQL dynamic SQL (13 sites) | Attempt to mechanically substitute `DBMS_SQL.PARSE`/`EXECUTE` calls 1:1 with PL/pgSQL `EXECUTE` | Re-derive the actual dynamic SQL being constructed at runtime from the Oracle logic (static analysis can't fully resolve this — flag as a "needs manual trace" item, matching the project's own acknowledgment that no live Oracle exists to observe actual runtime SQL) |
| UTL_SMTP email sending | Try to find/force a PostgreSQL in-database SMTP equivalent | Move email-sending to the application layer or an explicit external-call shim (`plpython3u`/HTTP callout); keep the database function signature stable so callers don't need to change, but the implementation must not live purely in SQL |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|-----------------|
| Leaning on orafce's Oracle-collection emulation (bulk-collect-style patterns) instead of native SQL set operations | Functions that loop row-by-row instead of using set-based SQL | Rewrite as native PostgreSQL set-based SQL where the Oracle pattern was only there because PL/SQL required explicit iteration | Noticeable once row counts move from hundreds to tens of thousands per call |
| ~~`dblink`-based autonomous-transaction emulation for high-frequency logging~~ — **obsolete, decision reversed** | — | `plog` ships via UDP: no connection setup, no commit, no queue drain. The per-call-overhead trap this row described cannot occur. Residual risk moves to the UDP sink itself (datagram loss under load is accepted by design; the collector, not the database, is the backpressure point) | n/a |
| Sequential CLOB data migration (already flagged in CONCERNS.md, not code-translation but adjacent) | Multi-hour bulk transfers for CLOB-heavy historical tables | Parallelize by ID/date range, use `COPY` | Multi-GB CLOB tables |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Losing the distinction between "expected business exception" and "unexpected system error" when collapsing Oracle's `-20NNN` codes into generic PostgreSQL exceptions (Pitfall 3) | Client code or ops tooling that alerts differently on business vs. system errors stops distinguishing them, masking real failures as routine ones (or vice versa) | Maintain an explicit Oracle-code → SQLSTATE mapping table, published with the client rename regexps |
| Trigger error-handling changes for `aserto.*` authorization sync calls done inconsistently across triggers | Authorization state could silently drift out of sync with the data it's meant to protect, differently per trigger, if some triggers absorb errors and others propagate | Decide and apply one consistent policy across all aserto-calling triggers, and test it explicitly (already flagged as untested in CONCERNS.md) |
| Hardcoded SSH jump-host placeholder pattern (`C_OSAG_AUTHSYNC_SSH_CALL`, already flagged in CONCERNS.md) carried through translation unexamined | Runtime string-replace failures could silently direct SSH calls to the wrong host | Move to configuration table with validated replacement, as part of translating this specific package, not treated as pure syntax porting |

## "Looks Done But Isn't" Checklist

- [ ] **STRICT/exception handling on every `SELECT INTO`:** Often "translated" by mechanically adding `STRICT` everywhere or nowhere — verify each one against the Oracle source's actual exception-handling intent (Pitfall 1).
- [ ] **Package-global mutable state:** Often assumed absent because a quick sample didn't find any — verify per-package, not by sampling (Pitfall 5).
- [ ] **FUNCTION vs PROCEDURE choice:** Often defaulted to FUNCTION (matching ora2pg's typical output) — verify no internal `COMMIT`/`ROLLBACK` exists before accepting (Pitfall 6).
- [ ] **`plog` rollback survival:** Verify with a test that deliberately rolls back the caller and asserts the UDP datagram still reached the collector. Also assert no `dblink`/`pg_background`/queue-table dependency crept into the logging path (Pitfall 4).
- [ ] **DBMS_*/UTL_* replacement completeness:** Often left as untranslated dead references that only fail at first invocation — verify zero Oracle-package-qualified identifiers remain in final code (Pitfall 7, Pitfall 9).
- [ ] **`%TYPE`/`%ROWTYPE` against Oracle dictionary views:** Often missed because the code "compiles" against the wrong or stale reference during incremental builds — verify via full from-scratch container rebuild (Pitfall 10).
- [ ] **Empty-string vs NULL parity:** Often untested because test suites only exercise NULL, never `''` — verify explicit `''`-input test cases exist for every string parameter that had Oracle NULL-equivalence semantics (Pitfall 2).

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|-----------------|------------------|
| Missing STRICT/exception handling discovered post-translation | LOW | Re-derive the specific SELECT INTO's spec from Oracle source, add STRICT + handler, add a regression test for the zero/multi-row case |
| Package-global mutable state discovered late (behavior drift found in testing) | MEDIUM | Identify the state's actual purpose, redesign as session GUC/temp table/explicit param, re-verify all callers of the affected package |
| Wrong FUNCTION/PROCEDURE choice discovered after several dependent objects already built on top | HIGH | Requires cascading rewrite of the call chain and all call sites (including client code) — this is why Pitfall 6 needs upfront spec analysis, not late discovery |
| `plog` log messages not reaching the telemetry sink (UDP emitter misconfigured, sink down, datagrams dropped) | LOW-MEDIUM | Fix the emitter/sink config; already-lost datagrams are unrecoverable, but UDP loss is an accepted property of the design, not a correctness bug in the translation. Verify the emitter with a collector-side assertion before any package ships |
| Table-writing autonomous transaction (`insert_result`, `close_old_dev_tickets`, `AuditUsage`) folded into the caller's transaction and lost on rollback | MEDIUM | Recover per the decision recorded in the Phase 3 transaction-semantics audit: re-emit as UDP telemetry, accept the transactional semantics, or (last resort) `dblink`. Not applicable to `plog`'s log levels |
| Oracle `-20NNN` error code semantics lost, client code silently stops branching correctly | MEDIUM | Reconstruct the mapping table from Oracle source, patch client code via the regexp deliverable, add tests asserting SQLSTATE values match the documented mapping |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|-------------------|----------------|
| NO_DATA_FOUND / SELECT INTO STRICT (1) | Spec derivation + package translation | pgTAP test per SELECT INTO exercising zero-row and multi-row cases where Oracle had a handler |
| Empty string vs NULL (2) | Spec derivation + DDL/data migration | Test suite includes explicit `''` inputs alongside `NULL` inputs for every affected string parameter/column |
| WHEN OTHERS / RAISE_APPLICATION_ERROR mapping (3) | Spec derivation + package translation | Test asserts specific SQLSTATE/ERRCODE returned matches the documented Oracle-code mapping table |
| Autonomous transactions (4) — **split** | Phase 3, cross-cutting (before the first package batch) | **Logging:** `plog` emits UDP; test asserts the datagram reaches the collector after the caller rolls back (inherent, not emulated). **Table writes** (`insert_result`, `close_old_dev_tickets`, `AuditUsage`): each has an explicit recorded decision in the transaction-semantics audit; test the chosen behavior |
| Package-global state / `package_in_name` flattening (5) | Spec derivation, per package | Explicit per-package checklist item; grep-based automated check for non-CONSTANT package-body-level variables |
| FUNCTION vs PROCEDURE / COMMIT semantics (6) | Spec derivation (call-graph analysis) | Automated grep for COMMIT/ROLLBACK inside translated FUNCTIONs (should be zero); CALL-chain integration test for procedures that commit |
| ora2pg mistranslation classes (7) | Cross-cutting guardrail, every translation phase | Automated check for leftover DBMS_*/UTL_*/Oracle-only syntax before marking any object complete |
| Over-trusting orafce (8) | Package translation, reviewed again at container-assembly | Explicit per-DBMS_*-family decision log; orafce version pinned and documented |
| DBMS_*/UTL_* replacement strategy (9) | Cross-cutting reference pass, early (after spec derivation begins) | Single reference table applied consistently; DBMS_REDEFINITION/UTL_SMTP explicitly triaged in/out of scope |
| %TYPE/%ROWTYPE dangling references (10) | Spec derivation (catalog dictionary-view refs) + final container-assembly build order | Full from-scratch container rebuild as the systematic catch-all test |
| Sequences/triggers interplay (11) | Trigger/procedure translation phase | Explicit prohibition on unplanned identity-column modernization; regression test on trigger-based ID generation |
| Process: spec derivation without runtime Oracle baseline | Whole-project methodology | Every derived spec explicitly lists open questions/assumptions where static analysis alone couldn't resolve behavior (esp. dynamic SQL); revisit if/when an Oracle 19c container becomes available |
| Process: name-refactoring misses (`package_in_name` regexps) | Client-regexp deliverable phase | Regexp list tested against actual call sites including schema-qualified calls, dynamic SQL string literals referencing old names, and changed call *shapes* (e.g., function→procedure conversions per Pitfall 6) — not just renamed identifiers |
| Process: tests that verify the translation's own assumptions, not Oracle semantics | Test-writing phase (pgTAP + plain SQL) | Tests must be written from the Oracle-derived spec independently of the translated code (spec-first, not code-first) — a reviewer should be able to write the same test from the Oracle source alone, without reading the PL/pgSQL implementation |

## Additional Process Pitfalls (Spec-First Without a Live Oracle Baseline)

### Deriving specs from source without a runtime baseline creates blind spots that static analysis cannot close

**What goes wrong:** Static analysis of `ddl/src/pkg`/`ddl/src/pkgb` can recover declared signatures, structural control flow, and explicit exception handlers — but it cannot observe what actually happens at runtime for dynamic SQL (`DBMS_SQL`, `EXECUTE IMMEDIATE`), implicit type coercions Oracle silently performs (e.g., `NUMBER` ↔ `VARCHAR2` coercion in comparisons, or date-format-string-dependent `TO_DATE`/`TO_CHAR` behavior), or edge cases in data-dependent branches that were never exercised in the code the humans wrote comments about. Because this project has explicitly deferred a live-Oracle empirical baseline, some specs will necessarily be "best effort from reading the code," and there is a real risk that gaps get silently smoothed over rather than flagged.

**Prevention:** Require every derived spec to have an explicit "Assumptions / Unresolved from static analysis" subsection — especially for anything touching dynamic SQL, implicit conversions, or NLS/locale-dependent date-and-number formatting. This creates a concrete backlog for the "Oracle 19c container possible later" fallback mentioned in PROJECT.md, rather than losing track of which specs are solid vs. best-guess.

**Phase to address:** Spec derivation phase, as a structural requirement of the spec template itself, not an afterthought.

---

### Name-refactoring regexps miss non-mechanical renames

**What goes wrong:** The `package_in_name` convention (e.g., `CALCULATOR.materialize_tickev` → `calculator_materialize_tickev`) is regexp-friendly for simple qualified-call renames, but misses: dynamic SQL string literals that reference the old package/procedure name as text (invisible to a call-site regexp since it's inside a string), any FUNCTION→PROCEDURE conversion changing the calling *shape* (Pitfall 6 — a regexp can rename the identifier but can't restructure `x := pkg.func(a,b)` into `CALL pkg_func(a,b,x)`), and schema-qualified vs. unqualified references that resolve differently depending on client-side search_path assumptions that changed during migration.

**Prevention:** Test the regexp deliverable against a corpus of real client call sites (not just a hand-picked few), explicitly including dynamic-SQL-constructed calls and any function-to-procedure conversions flagged during translation — ship those as a separate "manual review required" list rather than silently including them in the same regexp file as safe mechanical renames.

**Phase to address:** Client-regexp deliverable phase, at the end, but the list of "non-mechanical" renames should be tracked incrementally throughout package translation (each time Pitfall 6 forces a function→procedure conversion, log it into this list immediately).

---

### Tests that verify the translation's own assumptions, not Oracle semantics

**What goes wrong:** Because there's no live Oracle to run the same test against and diff results, it's easy — even with good intentions — to write a PostgreSQL test that says "call the PL/pgSQL function, assert it returns what the PL/pgSQL function already does" (circular verification), rather than a test derived independently from the Oracle source's documented/inferred behavior. This risk is structural to the project's own stated methodology (spec-first, no live Oracle) and is exactly the kind of mistake that "looks like progress" (green tests) while providing zero actual assurance of Oracle-equivalence.

**Prevention:** Enforce, as a review gate, that every pgTAP/plain-SQL test's expected value is justified by a citation back to the Oracle-derived spec (or the Oracle source directly), not derived by "running the new code and recording what it outputs." A useful heuristic: a reviewer should be able to write the same test's expected output from the Oracle source and the spec alone, without ever looking at the PL/pgSQL implementation.

**Phase to address:** Test-writing phase — should be an explicit item in whatever review/verification step follows each package's translation, not assumed to be automatically satisfied by "tests exist and pass."

## Sources

- [PostgreSQL 18 Docs: 41.13 Porting from Oracle PL/SQL](https://www.postgresql.org/docs/current/plpgsql-porting.html) — HIGH (official docs)
- [PostgreSQL Docs: 41.8 Transaction Management (procedures)](https://www.postgresql.org/docs/current/plpgsql-transactions.html) — HIGH (official docs)
- [How to Handle No Data Found with Scalar function in Oracle to PostgreSQL Migration](https://databaserookies.wordpress.com/2021/05/08/scalar-functions-and-no-data-found-in-oracle-to-postgresql-migration/) — MEDIUM
- [AWS: Challenges When Migrating from Oracle to PostgreSQL](https://aws.amazon.com/blogs/database/challenges-when-migrating-from-oracle-to-postgresql-and-how-to-overcome-them/) — MEDIUM
- [AWS: Handle empty strings when migrating from Oracle to PostgreSQL](https://aws.amazon.com/blogs/database/handle-empty-strings-when-migrating-from-oracle-to-postgresql/) — MEDIUM
- [AWS: Migrating Oracle Autonomous Transactions to PostgreSQL](https://aws.amazon.com/blogs/database/migrating-oracle-autonomous-transactions-to-postgresql/) — MEDIUM
- [EDB: How NULL and empty strings are treated in PostgreSQL vs Oracle](https://www.enterprisedb.com/postgres-tutorials/how-null-and-empty-strings-are-treated-postgresql-vs-oracle) — MEDIUM
- [Dalibo: Autonomous transaction support in PostgreSQL](https://blog.dalibo.com/2016/08/19/Autonoumous_transactions_support_in_PostgreSQL.html) — MEDIUM
- [Dalibo: Pragma autonomous_transaction in PostgreSQL](https://blog.dalibo.com/2016/09/08/Pragma_Autonoumous_transactions.html) — MEDIUM
- [Dalibo: PL/SQL to PL/pgSQL porting guide](https://dalibo.github.io/from-oracle-to-postgresql/pl-sql-to-pl-pgsql-porting/) — MEDIUM
- [ora2pg: Features](https://ora2pg.darold.net/docs/features) — MEDIUM (project docs)
- [ora2pg GitHub issue #22: Convert standard SQL files](https://github.com/darold/ora2pg/issues/22) — LOW (community discussion)
- [orafce GitHub README](https://github.com/orafce/orafce) — HIGH (project docs)
- [Franck Pachot: PostgreSQL transaction management in procedures](https://franckpachot.medium.com/postgresql-transaction-management-in-procedures-9b57cb909067) — MEDIUM
- [dbi-services: PostgreSQL 11 Procedures and transaction control](https://www.dbi-services.com/blog/postgresql-11-procedures-and-transaction-control/) — MEDIUM
- Repo-grounded findings: `ddl/src/pkgb/*.sql` (grep for `PRAGMA AUTONOMOUS_TRANSACTION`, `WHEN OTHERS`, `RAISE_APPLICATION_ERROR`, `NO_DATA_FOUND`, `DBMS_*`, `%TYPE`/`%ROWTYPE`), `ddl/src/triggers/*.sql`, `.planning/codebase/CONCERNS.md` — HIGH (direct source inspection, this repo)

---
*Pitfalls research for: Oracle 19c → PostgreSQL 17 PL/SQL migration*
*Researched: 2026-07-10*
