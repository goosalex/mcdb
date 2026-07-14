# TEST-AMENDMENTS.md

The anti-circularity contract (`migration/spec/provenance_lint.sh`) forbids a **translation**
commit from touching a test file. Tests are written from the Oracle-derived spec *before* the
translation exists; a translation that could edit its own tests would make this phase theatre.

This file is the audit trail for the sanctioned escape hatch. Every amendment to an already-committed
test file is recorded here, with evidence, so a reviewer can check that nothing was quietly weakened
to manufacture a green run.

**The bar:** an amendment must not change *what* is asserted. It may only correct a defect that
prevents the test from asserting what it already intended. A change that makes a failing test pass by
asserting *less* is not an amendment — it is a translation bug being covered up, and it is forbidden.

---

## A-001 — `tt__osag_notify__selectinto.sql`: 7 × `throws_ok` 3-arg overload misuse

| | |
|---|---|
| **Date** | 2026-07-13 |
| **Amended by** | orchestrator (not a translation plan — this commit touches NO translation file) |
| **File** | `migration/test/pgtap/tt__osag_notify__selectinto.sql` |
| **Assertions affected** | 7 |
| **Surfaced by** | plan 02-10, which correctly REFUSED to fix it (a translation plan may not touch tests) and documented it in `migration/pgsql/tt/osag_notify.FINDINGS.md` |
| **User approved** | Yes — explicitly, before the edit was made |

### The defect

pgTAP's `throws_ok` has two 3-argument overloads and they are ambiguous by design:

```
throws_ok ( sql, errcode, errmsg )       -- arg3 = expected ERROR MESSAGE
throws_ok ( sql, errmsg, description )   -- arg3 = human label
```

When arg2 is a 5-character SQLSTATE, pgTAP resolves to the **first** form — so arg3 is treated as the
*expected error message*, not as a label. All 7 calls passed a long human sentence as arg3, so each
asserted "expect SQLSTATE X **whose message is literally this sentence**". No error can ever have that
message, so the assertions could never pass regardless of how correct the translation was.

### Independently reproduced (not taken on trust)

```sql
SELECT throws_ok($$ SELECT 1/0 $$, '22012', 'this is meant to be a human description');
-- not ok 1 - threw 22012: this is meant to be a human description
--       caught: 22012: division by zero
--       wanted: 22012: this is meant to be a human description
```

The SQLSTATE matched. The test still failed — on the description text.

### The amendment

Insert `NULL` as the message argument, promoting each call to the unambiguous 4-argument form
`throws_ok(sql, errcode, errmsg, description)`, where a NULL `errmsg` means "do not check the message":

```diff
 SELECT throws_ok(
     $$CALL tt.osag_notify_send_test_notification(...)$$,
     'P0002',
+    NULL,
     'S-NOTIFY-018: send_test_notification (SMS branch) propagates NO_DATA_FOUND unhandled ...'
 );
```

Affected: 6 × `'P0002'` (S-NOTIFY-018 ×2, 024, 025, 026, 028) and 1 × `'23502'` (S-NOTIFY-022).

### Why this is not a weakening

The asserted condition is **unchanged**: each test still requires that exact SQLSTATE to be raised.
Only the sentence's role changes — from "expected message" (never satisfiable) to "test label" (its
evident intent, matching every other test file in the suite).

**Proven still falsifiable** — the corrected form fails on a wrong SQLSTATE:

```sql
SELECT throws_ok($$ SELECT 1/0 $$, '23505', NULL, 'wrong code must fail');
-- not ok 2 - wrong code must fail
--       caught: 22012: division by zero
```

A test that cannot fail is worthless; this one can, and does.

### Effect

`tt.osag_notify`: **15/24 → 22/24** pgTAP assertions passing. No translation file was modified in the
amending commit. `provenance_lint.sh` passes.

---

## A-002 — the same `throws_ok` defect in 5 more test files (23 assertions)

| | |
|---|---|
| **Date** | 2026-07-13 |
| **Amended by** | orchestrator (touches NO translation file) |
| **Assertions affected** | 23 |
| **User approved** | Yes — same defect class as A-001, approved remedy applied to all identical instances |

### Why this exists

A-001 fixed 7 instances in one file. A sweep then found the **identical** pgTAP misuse in 5 more files —
every spec/test agent independently made the same mistake:

| File | Instances |
|---|---|
| `auth__osag_auth__spec.sql` | 1 |
| `tt__event_interface__spec.sql` | 4 |
| `tt__ticket_interface__changes.sql` | 5 |
| `tt__ticket_interface__lifecycle.sql` | 8 |
| `tt__ticket_interface__selectinto.sql` | 5 |

These were fixed **before** plans 02-11 and 02-12 run. Left in place, they would have made 23 assertions
unpassable no matter how correct those translations were — sending both agents to hunt phantom bugs in
correct code, and very likely provoking exactly the kind of "fix" that corrupts a translation to satisfy a
broken test.

### The amendment

Mechanically identical to A-001: insert `NULL` as the message argument, promoting each 3-arg call to the
unambiguous 4-arg `throws_ok(sql, errcode, errmsg, description)`. The asserted SQLSTATE is unchanged in
every case; only the sentence's role changes from "expected message" to "label". Still falsifiable — a
wrong SQLSTATE still fails (proven under A-001).

### Effect

`auth.osag_auth`: **8/10 → 9/10**. The `tt.event_interface` and `tt.ticket_interface` assertions remain red
only because their translations do not exist yet (plans 02-11 and 02-12) — which is correct, and is what
the RED baseline confirms: with no translation installed, those packages still report **0** passes.

### Standing warning for 02-13

The RED baseline (`run-tests.sh` with no `--install`) shows `tt.ticket_interface` at **6/129** — six
assertions pass with **no translation loaded at all**. A test that passes when the code under test does not
exist is not testing that code. These six are prime candidates for the mutation check to expose, and must
be examined before the phase can claim a clean red→green.
