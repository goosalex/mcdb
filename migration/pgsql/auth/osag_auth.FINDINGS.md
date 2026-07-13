# AUTH.OSAG_AUTH -- FINDINGS

**Source:** `ddl/src/pkg/auth_osag_auth.sql` (spec, 32 lines), `ddl/src/pkgb/auth_osag_auth.sql`
(body, 156 lines). **Spec:** `migration/spec/auth.osag_auth.md`. **Target:**
`migration/pgsql/auth/osag_auth.sql`.

## AuditUsage deletion count

**3 of 3** `plog.AuditUsage(...)` call sites deleted outright (`delete_login` line 20,
`grant_role` line 93, `grant_user_role` line 116 of the Oracle body). Confirmed by
`grep -c AuditUsage ddl/src/pkgb/auth_osag_auth.sql` -> 3. Per XCUT-06, the feature is
unused (write-only) and is deleted, not stubbed.

## "no data found" message-parity shim (all 3 unhandled NO_DATA_FOUND sites)

Both of this package's genuinely-unguarded `SELECT ... INTO` sites (`delete_login`'s
`v_contact_id` lookup, S-AUTH-001; `grant_user_role`'s `v_company_id` lookup,
S-AUTH-009) have **no local Oracle handler** -- the spec is explicit about this, and the
translation preserves that structurally (the exception still propagates all the way to
each routine's own outermost `WHEN OTHERS`, logged exactly once there, per S-AUTH-007/
011). PostgreSQL's own default `STRICT` zero-row message is "query returned no rows",
not "no data found" -- but Oracle's REAL `SQLERRM` for an unhandled `NO_DATA_FOUND` is
literally `ORA-01403: no data found`, and both this plan's pgTAP suite
(`auth__osag_auth__spec.sql`, S-AUTH-001/009) and TT.UTIL's suite pin the exact substring
`%no data found%` via `throws_like`.

Translation choice: each such site keeps its `SELECT ... INTO STRICT` with **no
Oracle-side behavioral handler**, but adds a minimal, purely cosmetic
`WHEN NO_DATA_FOUND THEN RAISE EXCEPTION 'no data found' USING ERRCODE = 'P0002';`
immediately after it -- this does not swallow, log, or redirect control flow; it only
corrects the observable message text to match Oracle's real runtime string before the
SAME exception continues propagating to the routine's own outer handler exactly as
before. This is a provisional decision (message text only, not SQLSTATE assignment)
pending Phase 3's XCUT-01 authoritative Oracle-code-to-SQLSTATE/message mapping table --
flagged here so XCUT-01 does not have to rediscover it independently. Applied
identically in `migration/pgsql/tt/util.FINDINGS.md` for `update_status_valid_until`'s
own unhandled NO_DATA_FOUND site.

## S-AUTH-010: ROWNUM=1-then-aggregate preserved AS-WRITTEN, not "fixed"

`grant_user_role`'s Oracle source has `SELECT COUNT(*) ... WHERE ... AND ROWNUM = 1` and
`SELECT NVL(MIN(p.id), 0) ... WHERE ... AND ROWNUM = 1` -- both filter the underlying row
set down to at most one row BEFORE aggregating, which is a defensive/existence-check
idiom (Oracle's `ROWNUM=1` short-circuits after the first matching row), not a true
`COUNT`/`MIN` over every match. Translated as `SELECT count(*)/coalesce(min(...),0) INTO
STRICT ... FROM (SELECT ... LIMIT 1) sub` -- reproducing the exact "limit to 1, then
aggregate" shape rather than a blanket `COUNT(*)`/`MIN(...)` over the full match set
(Pitfall 1's warning against silently "fixing" AS-WRITTEN Oracle behavior applies here:
in practice at most one automatic profile/permission row can exist per login by the
schema's own design, so this never observably differs from a true aggregate -- but the
AS-WRITTEN shape is preserved rather than assumed equivalent).

## S-AUTH-011: unique-violation swallow preserved as real business logic

`grant_user_role`'s outer handler checks `SQLSTATE != '23505'` (PostgreSQL's
`unique_violation`, the direct equivalent of Oracle's `SQLCODE = -00001`/`ORA-00001`) --
translated verbatim as a `SQLSTATE`-based discriminator, not a blanket catch-and-swallow.
Verified live: granting the same `(login, user_role)` pair twice succeeds silently on
the second call (pgTAP S-AUTH-011, both assertions pass).

## Sequences

`auth.seq_profile.nextVal` / `auth.seq_user_permission.nextVal` /
`auth.seq_user_company_scope.nextval` -> `nextval('auth.seq_profile')` /
`nextval('auth.seq_user_permission')` / `nextval('auth.seq_user_company_scope')` --
mechanical (Pitfall 11), no identity-column modernization attempted.

## Package state

None (matches the spec's `package_state: []`, confirmed by reading the full 156-line body).

## Known-red assertions in `auth__osag_auth__spec.sql` (verified, not translation bugs)

Ran live against `mcdb_test_p09` (template clone, `osag_plog.sql` +
`mss/osag_dbprop.sql` + this file installed): **4/10 pgTAP assertions pass**
(S-AUTH-001, S-AUTH-009's NO_DATA_FOUND propagation, and both S-AUTH-011 grant/re-grant
assertions). The other 6 fail for two independent, already-understood, non-translation
reasons:

1. **S-AUTH-005/004 (4 assertions: the successful-delete path and its 3 follow-up row
   counts).** `delete_login` calls `tt.osag_notify_delete_notifications_for_login`
   (S-AUTH-002) unconditionally, before any of its own deletes. That routine is
   `TT.OSAG_NOTIFY`'s (plan 02-10, same wave, not yet landed) -- the `CALL` fails with
   "procedure ... does not exist", exactly as the pgtap file's own header comment
   anticipates ("this suite stays partially RED even after auth.osag_auth_delete_login
   lands", until 02-10 lands OSAG_NOTIFY). Not a defect in this package's translation.
2. **S-AUTH-007 (1 assertion: plog-survival check after a `throws_like`-wrapped
   `CALL`).** Verified empirically (two independent minimal reproductions against a
   scratch database) that PL/pgSQL's implicit savepoint-on-EXCEPTION semantics roll back
   **all** writes performed during a `CALL` that pgTAP's `throws_like` catches --
   including a plog `INSERT` performed by the called procedure's OWN exception handler
   before its `RAISE`. This is unconditional PostgreSQL transaction-savepoint behavior,
   not something any PL/pgSQL translation of `delete_login` can avoid while still
   re-raising (which S-AUTH-007 itself requires). It is the SAME root cause
   `osag_plog.FINDINGS.md` already documents ("pilot tests assert on plog output
   WITHOUT forcing a rollback") -- this specific pgTAP assertion inherently forces one
   via `throws_like`'s internal exception catch, which the earlier plan that wrote this
   test file did not anticipate. Flagged here as a genuine pre-existing test-authoring
   gap for Phase 3 (once `plog` becomes the real non-transactional UDP shipper, a
   datagram send is not undone by any savepoint rollback, and this exact assertion shape
   would start passing on its own). No fix attempted -- not a translation defect, and
   this plan does not touch any file under `migration/test/`.
3. **S-AUTH-008 (1 assertion: `grant_role`'s invalid-role-id error).** This
   `throws_ok(sql, '22023', '<long clause description text>')` call hits a pgTAP
   dispatch quirk, verified with an isolated minimal reproduction against a scratch
   pgTAP database: `throws_ok(TEXT, TEXT, TEXT)` treats its 2nd argument as an `errcode`
   ONLY IF `octet_length($2) = 5`, and in that branch its 3rd argument is passed through
   as the EXPECTED ERROR MESSAGE TEXT (`errmsg`), not as a human-readable test
   description -- there is no 3-argument pgTAP overload that means
   `(sql, errcode, description)`. Since `'22023'` is exactly 5 bytes, this test's own
   3rd argument (clearly intended as a human description, per its content and the
   `4-argument` sibling calls elsewhere in the same file that use a real `description`
   positionally) is silently reinterpreted as the exact expected `SQLERRM`. The
   translation DOES raise `SQLSTATE 22023` (confirmed: `caught: 22023: ...` in the pgTAP
   diagnostic output, i.e. the SQLSTATE matches) -- only the message-text comparison
   (an accidental side effect of the 5-byte errcode dispatch, not the test author's
   intent) fails. Not a translation defect; not fixed by rewording the raised message to
   literally embed a spec-clause description in production error text, which would be
   the wrong direction to resolve a test-tooling footgun. No test file touched.

## Verification performed

- Loaded cleanly into a `bootstrap.sh --template mcdb_tmpl` clone with `osag_plog.sql`
  and `mss/osag_dbprop.sql` already installed.
- `run-tests.sh --package auth.osag_auth`: pgTAP 4/10 (all 6 failures independently
  explained above, none a translation defect); no expected-output suite exists for this
  package.
- `grep -nEi "dbms_|utl_|auditusage"` over this file: zero matches.
