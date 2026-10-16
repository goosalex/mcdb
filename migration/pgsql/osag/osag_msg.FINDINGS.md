# OSAG.OSAG_MSG -- FINDINGS

**Source:** `ddl/src/pkg/osag_osag_msg.sql` (spec, 58 lines), `ddl/src/pkgb/osag_osag_msg.sql`
(body, 97 lines). **Spec:** `migration/spec/osag.osag_msg.md`. **Target:**
`migration/pgsql/osag/osag_msg.sql`. **Tests:** `migration/test/pgtap/osag__osag_msg__spec.sql`
(63 assertions, 16/16 clauses cited).

## AuditUsage deletion count

**2 of 2** `plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT)` call sites
deleted outright (`send_mail` body line 22, `send_sms` body line 85). Confirmed by
`grep -c AuditUsage ddl/src/pkgb/osag_osag_msg.sql` -> 2. Per XCUT-06, deleted, not
stubbed; S-MSG-016 asserts no `osag_msg*` routine references it and nothing lands in
`osag.plsql_audit`.

## The design: a durable outbox, delivery by an external shipper

PostgreSQL has no `UTL_SMTP`, and PL/pgSQL must not open sockets. The procedures build
exactly the envelope/header values Oracle built, then `INSERT` one row into
`osag.msg_outbox` (created in the translation file with `CREATE TABLE IF NOT EXISTS`,
the same pattern `osag_plog.sql` uses for its stub table). Columns:

| column | holds | Oracle origin |
|---|---|---|
| `id` | identity | -- |
| `kind` | `'mail'` / `'sms'` (`CHECK`) | which public procedure queued it (Oracle: the `@mx-sms.open.ch` domain, lines 80/87) |
| `envelope_from` | `NOT NULL`, normalised `NVL(p_mail_from, p_reply_to)` | `UTL_SMTP.MAIL(...)`, line 53 |
| `reply_to` | raw `p_reply_to` | `Reply-To:` header, line 43 |
| `from_hdr` | raw `NVL(p_from, p_reply_to)` | `From:` header, line 42 |
| `recipient` | `NOT NULL`, normalised | `RCPT` + `To:`, lines 44/54 |
| `subject` | `NULLIF(p_subject, '')` | `Subject:`, line 45 |
| `body` | `p_body` as given | line 46 |
| `opt_headers` | `text[][]` of `[name, value]`, `NULL` when none; `CHECK`ed to be 2-D with inner length 2 | `smtp_headers_t`, lines 31-38 |
| `created_at`, `sent_at`, `attempts`, `last_error` | shipper bookkeeping | -- |

A partial index on `created_at WHERE sent_at IS NULL` serves the shipper's poll query.

**What the shipper must do** (also in `COMMENT ON TABLE osag.msg_outbox`): poll unsent
rows in `created_at` order; connect to the local MTA (Oracle: `localhost:25`, body
lines 9-11); `HELO` with its own host name (Oracle resolved it from `v$instance`, line
23); `MAIL FROM:<envelope_from>`; `RCPT TO:<recipient>`; `DATA` consisting of each
`opt_headers[i][1]: opt_headers[i][2]` line, then `Date:` generated at send time in
`Dy, dd Mon YYYY HH24:MI:SS TZHTZM` (line 41), `From: from_hdr`, `Reply-To: reply_to`,
`To: recipient`, `Subject: subject`, blank line, `body` with SMTP dot-stuffing (line 49,
DB-316); `QUIT`; then set `sent_at`. On failure increment `attempts`, record
`last_error`, retry later. The shipper itself is out of scope for this repository.

### Private helper `osag.osag_msg__enqueue`

Oracle's `send_sms` calls `send_mail`; the outbox row must still say `'sms'`. The body of
`send_mail` therefore lives in `osag.osag_msg__enqueue(p_kind, ...)` (`REVOKE ALL FROM
PUBLIC`), and both public procedures are thin wrappers: `send_mail` = `__enqueue('mail',
...)`, `send_sms` = `__enqueue('sms', ...)`. The helper owns the normalisation, the
debug/notice lines, the `INSERT`, and the `WHEN OTHERS` log-and-`RAISE`; `send_sms` keeps
its own `WHEN OTHERS` log-and-swallow around the call. The Oracle asymmetry is thus
preserved exactly: `send_mail` never swallows, `send_sms` never raises (S-MSG-008/011).

### Signatures match the already-translated caller

`tt.osag_notify` (`migration/pgsql/tt/osag_notify.sql`) calls
`CALL osag.osag_msg_send_mail(reply_to, from, envelope, recipient, subject, body[, text[][]])`
with both 6 and 7 arguments and `CALL osag.osag_msg_send_sms(number, text)`. The
procedures are declared with `varchar` parameters and `p_opt_headers text[][] DEFAULT
NULL`; `text` -> `varchar` is an implicit cast, so every existing call site resolves.
The `smtp_headers_t` nested-table type is represented by the `text[][]` the caller
already builds (`ARRAY[['Auto-Submitted','auto-generated'],['Precedence','bulk']]`) --
the "OSAG_MSG-owned decision" `osag_notify.FINDINGS.md` deferred is now settled that way.

## Deviations from Oracle

Every site is marked `-- DEVIATION(KIND) S-MSG-NNN` in the translation; the spec states
each as the contract.

| Clause | Kind | Oracle behaviour (cited) | Translated behaviour | Why |
|---|---|---|---|---|
| S-MSG-013 | PLATFORM | `UTL_SMTP` dialogue, `HELO` host from `v$instance`, `Date:` header, dot-stuffing (body lines 9-11, 23, 41, 49, 51-56, 65). | Row in `osag.msg_outbox`; transport is the shipper's. | No sockets from PL/pgSQL; no `UTL_SMTP`. |
| S-MSG-007 | PLATFORM | Notice text `sent mail from '...' to '...' subject: '...'` (line 58). | `queued mail from '...' to '...' subject: '...' (outbox id N)` -- same prefix, same from/to/subject fragment. | The procedure no longer sends; saying so in the log is more honest and gives operators the row id. |
| S-MSG-012 | PLATFORM | `send_sms(NULL, ...)` builds the recipient `'@mx-sms.open.ch'` (`NULL || '@' || domain`, line 87) and hands it to the MTA; the `RCPT` rejection -- if any -- is logged and swallowed. | The stripped number is `NULLIF`'d; a `NULL` recipient violates `NOT NULL` (23502) inside `__enqueue`, which `send_sms` catches, logs (`sending SMS to '' failed: ...`) and swallows. No row. | Same caller-visible outcome (no exception, an ERR line); a shipper must never be handed an address with no local part. |
| S-MSG-008 | (mapping, not a deviation) | `UTL_SMTP.RCPT(NULL)` / `MAIL(NULL)` rejected by the MTA, logged, re-raised. | `NOT NULL` on `recipient` / `envelope_from` raises 23502, logged, re-raised. | The reachable failure modes of an `INSERT` replace those of an SMTP session; the handler shape is identical. |

Not deviations, but worth knowing:

- **Address regex.** Oracle's `'^([^\<])(.*)([^\>]$)'` becomes `'^([^<])(.*)([^>]$)'`.
  Inside a POSIX bracket expression the backslash is literal, so Oracle's class also
  excluded a leading backslash; PostgreSQL's ARE would read `\<` as a constraint escape
  (illegal inside brackets). No real address starts with a backslash.
- **`''`/`NULL`.** `NULLIF(x, '')` at the boundary for `p_reply_to`, `p_from`,
  `p_mail_from`, `p_recipient`, `p_subject` reproduces Oracle's collapsing at every `NVL`
  site (S-MSG-004); `send_sms`'s literal `''` subject lands as `NULL`. `p_body` is stored
  as given.
- **Log-line `NULL` operands.** Oracle's `||` drops `NULL`s; PostgreSQL's would `NULL` the
  whole message, so every nullable operand in a log line is wrapped in `coalesce(x, '')`.
  Error lines carry `SQLSTATE || ': ' || SQLERRM` where Oracle had
  `DBMS_UTILITY.FORMAT_ERROR_BACKTRACE || ': ' || sqlerrm`.
- **Empty header array** (`'{}'::text[]`) is stored as `NULL`, matching Oracle's
  `p_opt_headers.count > 0` guard; a 1-D array is rejected by the `CHECK` (23514) and
  surfaces through the normal log-and-re-raise path.

## Transaction semantics (XCUT-04/05 input)

No `COMMIT`/`ROLLBACK` anywhere (S-MSG-014; asserted by `prosrc` inspection). Both are
`PROCEDURE`s as in Oracle and `name-map.csv`. The queued row rides in the caller's
transaction: if the caller rolls back, the message is un-queued. Under Oracle the SMTP
side effect had already happened when the caller rolled back -- mail sent for a
transaction that never committed. The outbox is strictly better here, but it is a real
behavioural difference worth stating for XCUT-05: **a message is only ever sent for
committed work.**

Consequence for the `plog` stub (S-MSG-011): when `__enqueue` fails inside `send_sms`,
its block is a subtransaction and is rolled back -- including the `send mail to '...'
failed` ERR line it wrote. Only `send_sms`'s own `sending SMS to '...' failed` line
survives. Under Oracle's autonomous `plog` both lines would survive. Known Phase 2 stub
limitation (`osag_plog.FINDINGS.md`), resolved by XCUT-02; the suite asserts only the
surviving line.

## Verification performed

- RED: `run-tests.sh --db mcdb_test_ipmsg --install migration/pgsql --package osag.osag_msg`
  before this file existed: **0/63, exit 1**, first error
  `relation "osag.msg_outbox" does not exist` (test commit `e5b01f3`).
- First GREEN run (translation on disk, uncommitted): 57/63. All six failures were test
  defects -- five bookkeeping literals ("rows queued so far") off by one, and `xmin`
  queried through a temp view -- then 62/63 because the outbox `INSERT` runs inside a
  subtransaction (the `EXCEPTION`-bearing block) so its `xmin` is a subxid. Fixed in two
  test-only commits (`b471f11`, `d982a15`), both recorded as A-010 in
  `migration/spec/TEST-AMENDMENTS.md`; no expected value or SQLSTATE changed.
- GREEN: **63/63 PASS**.
- `grep -nEi "utl_smtp|dbms_|auditusage|commit|rollback"` over this file: matches only in
  comments describing what moved to the shipper or was deleted.
- `bash migration/spec/provenance_lint.sh`: spec commit `a696277` and first test commit
  `e5b01f3` are ancestors of the translation commit; the test-fix commits touch no
  translation file.

## Open questions

- The shipper (SMTP client, retry policy, dead-lettering after N attempts, who runs it)
  is not part of this repository. Until it exists, queued messages are not delivered.
- Length limits of `smtp_header_name_t`/`smtp_header_value_t` (64/256) are not enforced
  on `opt_headers`; nothing in the repo relies on them.
- Whether `UTL_SMTP.MAIL(NULL)` actually failed in production Oracle (the premise of
  S-MSG-008's `NOT NULL` on `envelope_from`) cannot be verified without a live instance.
