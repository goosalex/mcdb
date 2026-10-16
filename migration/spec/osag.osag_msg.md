---
oracle_schema: OSAG
oracle_package: OSAG_MSG
pg_schema: osag
pg_prefix: osag_msg
clause_prefix: MSG
oracle_spec: ddl/src/pkg/osag_osag_msg.sql
oracle_body: ddl/src/pkgb/osag_osag_msg.sql
public_routines: 2
---

# OSAG.OSAG_MSG — PostgreSQL spec

Generalised outbound messaging. Per the package header (`ddl/src/pkg/osag_osag_msg.sql:6-18`)
both routines send e-mail: `send_mail` builds an RFC 822 message and hands it to the local
MTA over `UTL_SMTP` (`localhost:25`, `ddl/src/pkgb/osag_osag_msg.sql:9-11`), and `send_sms`
is a thin wrapper that addresses the mail to `<number>@mx-sms.open.ch`, where an SMS gateway
takes over. The package has no state and no SQL of its own beyond one `SELECT` of the
instance host name for the SMTP `HELO`. Its only in-repo caller is `TT.OSAG_NOTIFY`
(`ddl/src/pkgb/tt_osag_notify.sql`).

**Platform decision this spec is written against (locked before translation, see
"Assumptions / Unresolved"):** PostgreSQL must not open TCP connections from PL/pgSQL, and
there is no `UTL_SMTP`. The translated routines therefore **enqueue** the fully-prepared
message into a durable outbox table `osag.msg_outbox`; an external shipper process performs
the SMTP transaction. Every clause below that describes what Oracle *put on the wire*
becomes a clause about what the outbox row *contains*; every clause about the SMTP
transaction itself (HELO, Date header, dot-stuffing, connection lifecycle) becomes a
documented responsibility of the shipper (S-MSG-013).

## Routines

### send_mail

- **Oracle signature:** `SEND_MAIL(p_reply_to VARCHAR2, p_from VARCHAR2, p_mail_from VARCHAR2, p_recipient VARCHAR2, p_subject VARCHAR2, p_body VARCHAR2, p_opt_headers smtp_headers_t := NULL)` (`PROCEDURE`)
- **PostgreSQL name:** `osag.osag_msg_send_mail` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/osag_osag_msg.sql:40-41`
- **Defined:** `ddl/src/pkgb/osag_osag_msg.sql:5-71`
- Normalises the addresses, logs a debug line, assembles headers + body, sends over SMTP,
  logs a notice. On any error logs an error line and **re-raises**. `p_opt_headers` is a
  nested table of `(h_name VARCHAR2(64), h_value VARCHAR(256))` records
  (`ddl/src/pkg/osag_osag_msg.sql:21-24`); its PostgreSQL shape is `text[][]` of
  `[name, value]` pairs, which is what the already-translated caller
  `tt.osag_notify` passes.

### send_sms

- **Oracle signature:** `SEND_SMS(p_sms_no VARCHAR2, p_body VARCHAR2)` (`PROCEDURE`)
- **PostgreSQL name:** `osag.osag_msg_send_sms` (from `name-map.csv`)
- **Declared:** `ddl/src/pkg/osag_osag_msg.sql:51`
- **Defined:** `ddl/src/pkgb/osag_osag_msg.sql:75-95`
- Strips spaces from the number and delegates to `send_mail` with fixed reply-to
  `support@open.ch`, recipient `<number>@mx-sms.open.ch`, empty subject and the SMS text as
  body; logs a notice on success. On any error logs an error line and **swallows** it —
  `send_sms` never raises to its caller.

### Private helper (translation-only, no `name-map.csv` row)

The outbox row must record whether it was queued as mail or as SMS (S-MSG-015) while
`send_sms` must keep delegating through `send_mail`'s body (same normalisation, same
logging, same re-raise, S-MSG-009/011). The translation therefore places `send_mail`'s
body in a private procedure `osag.osag_msg__enqueue(p_kind, p_reply_to, p_from,
p_mail_from, p_recipient, p_subject, p_body, p_opt_headers)` (`REVOKE ALL ... FROM PUBLIC`,
per the `__` convention from `migration/spec/tt.osag_notify.md`); the public `send_mail`
is `__enqueue('mail', ...)` and `send_sms` calls `__enqueue('sms', ...)`. This is a
packaging decision only — no clause below depends on the helper's existence.

## Clauses

### S-MSG-001

- **routines:** send_mail
- **claim:** `p_reply_to`, `p_recipient` and `p_mail_from` are each normalised with
  `REGEXP_REPLACE(x, '^([^\<])(.*)([^\>]$)', '<\1\2\3>')`: a value of at least two
  characters whose first character is not `<` and whose last character is not `>` is
  wrapped in angle brackets (`'a@x.ch'` → `'<a@x.ch>'`); a value already starting with `<`
  or already ending with `>` is left unchanged (`'<a@x.ch>'`, `'Name <a@x.ch>'`); a `NULL`
  stays `NULL`. `p_from` is **not** normalised anywhere (it is used raw at line 42).
- **source:** `ddl/src/pkgb/osag_osag_msg.sql:24-26, 42`

### S-MSG-002

- **routines:** send_mail
- **claim:** The envelope sender (SMTP `MAIL FROM`) is
  `NVL(normalised p_mail_from, normalised p_reply_to)` — the normalised `p_mail_from` when
  one was given, otherwise the normalised `p_reply_to`. The outbox column `envelope_from`
  holds exactly this value, e.g. `send_mail('a@x.ch', ..., p_mail_from => 'c@x.ch')` →
  `'<c@x.ch>'`; `send_mail('a@x.ch', ..., p_mail_from => NULL)` → `'<a@x.ch>'`.
- **source:** `ddl/src/pkgb/osag_osag_msg.sql:53`

### S-MSG-003

- **routines:** send_mail
- **claim:** The message headers are, in this order after any optional headers: `Date:`
  (generated at send time), `From: NVL(p_from, p_reply_to)` using the **raw** values,
  `Reply-To: p_reply_to` raw, `To:` the **normalised** recipient, `Subject: p_subject`, a
  blank line, then `p_body`. The outbox columns therefore hold `from_hdr =
  coalesce(p_from, p_reply_to)` (raw, e.g. `'b@x.ch'`, not `'<b@x.ch>'`), `reply_to =
  p_reply_to` (raw), `recipient` = normalised (`'<d@x.ch>'`), `subject = p_subject`,
  `body = p_body` — each byte-for-byte what Oracle would have written into the
  corresponding header. The `Date:` header is not stored (S-MSG-013).
- **source:** `ddl/src/pkgb/osag_osag_msg.sql:40-46`

### S-MSG-004

- **routines:** send_mail, send_sms
- **claim:** Oracle treats `''` as `NULL` at every `NVL` site: `p_from = ''` → `From:`
  falls back to `p_reply_to`; `p_mail_from = ''` → envelope falls back to the normalised
  `p_reply_to`; `p_subject = ''` (which is exactly what `send_sms` passes at line 87) is a
  `NULL` subject. The translation must collapse `''` to `NULL` at the boundary for
  `p_from`, `p_mail_from`, `p_subject`, `p_reply_to` and `p_recipient` so that the stored
  row is identical whether the caller passed `''` or `NULL` — an SMS row has
  `subject IS NULL`, never `subject = ''`.
- **source:** `ddl/src/pkgb/osag_osag_msg.sql:42, 53, 87`

### S-MSG-005

- **routines:** send_mail
- **claim:** When `p_opt_headers` is `NULL` or has zero elements no optional header line is
  produced; otherwise every element `(h_name, h_value)` is emitted, in order, as
  `h_name || ': ' || h_value || CRLF` *before* the fixed headers. The outbox column
  `opt_headers` holds the caller's `text[][]` verbatim when at least one pair was given
  (e.g. `ARRAY[['Auto-Submitted','auto-generated'],['Precedence','bulk']]`) and `NULL`
  when the caller passed `NULL`, omitted the argument (declared default `NULL`), or passed
  an empty array. A value that is not a two-dimensional array of `[name, value]` pairs is
  rejected by the table's `CHECK` constraint (SQLSTATE `23514`).
- **source:** `ddl/src/pkg/osag_osag_msg.sql:21-24, 41`, `ddl/src/pkgb/osag_osag_msg.sql:31-38`

### S-MSG-006

- **routines:** send_mail
- **claim:** Before any send attempt a `plog.debug` line is written:
  `OSAG.OSAG_MSG.send_mail(): from: '<envelope>', recipient: '<normalised recipient>', subject: '<p_subject>'`
  (level 7 in the `osag.plog_stub_log` stub), where `<envelope>` is the S-MSG-002 value.
- **source:** `ddl/src/pkgb/osag_osag_msg.sql:28`

### S-MSG-007

- **routines:** send_mail
- **claim:** After the message has been handed off, a `plog.notice` (level 5) line is
  written whose text contains `mail from '<envelope>' to '<normalised recipient>' subject: '<p_subject>'`
  with the same prefix `OSAG.OSAG_MSG.send_mail(): `. Oracle's wording is `sent mail from ...`;
  because the translation hands off to an outbox rather than to the MTA, the wording becomes
  `queued mail from ... subject: '...' (outbox id N)` — the from/to/subject fragment is
  identical and is what tests assert on.
- **source:** `ddl/src/pkgb/osag_osag_msg.sql:58`

### S-MSG-008

- **routines:** send_mail
- **claim:** On any error the `WHEN OTHERS` handler writes a `plog.err` (level 3) line
  `OSAG.OSAG_MSG.send_mail(): send mail to '<normalised recipient>' failed: <error text>`
  and then **re-raises** the original exception unchanged (`RAISE;`) — `send_mail` never
  swallows. The `DBMS_OUTPUT.PUT_LINE` at line 62 and the connection-close at lines 64-69
  are transport side effects with no PostgreSQL counterpart. In the outbox model the
  reachable failures are constraint violations on the row: a `NULL`/`''` recipient
  (Oracle: `UTL_SMTP.RCPT(NULL)` is rejected by the MTA) or a `NULL` envelope sender
  (both `p_mail_from` and `p_reply_to` `NULL`/`''`) violate `NOT NULL` and raise
  SQLSTATE `23502` to the caller, with no row inserted.
- **source:** `ddl/src/pkgb/osag_osag_msg.sql:60-70`

### S-MSG-009

- **routines:** send_sms
- **claim:** `send_sms(p_sms_no, p_body)` removes every space from `p_sms_no`
  (`REPLACE(p_sms_no, ' ', '')`) and calls `send_mail` with `p_reply_to = 'support@open.ch'`,
  `p_from = NULL`, `p_mail_from = NULL`, `p_recipient = <stripped number> || '@mx-sms.open.ch'`,
  `p_subject = ''`, `p_body = p_body`, and no optional headers. By S-MSG-001/002/003/004
  the resulting outbox row has `envelope_from = '<support@open.ch>'`,
  `reply_to = 'support@open.ch'`, `from_hdr = 'support@open.ch'`,
  `recipient = '<+41791234567@mx-sms.open.ch>'` for input `'+41 79 123 45 67'`,
  `subject IS NULL`, `body = p_body`, `opt_headers IS NULL`.
- **source:** `ddl/src/pkgb/osag_osag_msg.sql:79-80, 86-87`

### S-MSG-010

- **routines:** send_sms
- **claim:** After a successful delegation `send_sms` writes a `plog.notice` (level 5) line
  `OSAG.OSAG_MSG.send_sms(): sent SMS to '<stripped number>' subject: '<p_body>'`
  (sic — the Oracle text labels the body "subject"; reproduced verbatim).
- **source:** `ddl/src/pkgb/osag_osag_msg.sql:89`

### S-MSG-011

- **routines:** send_sms
- **claim:** `send_sms` **never raises**: its `WHEN OTHERS` handler writes a `plog.err`
  (level 3) line `OSAG.OSAG_MSG.send_sms(): sending SMS to '<stripped number>' failed: <error text>`
  and ends without `RAISE`. Any failure inside the delegated `send_mail` (which itself logs
  and re-raises, S-MSG-008) is therefore absorbed here; the caller observes a normal return
  and no outbox row. (The stub `plog` writes in the caller's transaction, so when the
  failing `send_mail` sub-block is rolled back its own S-MSG-008 error line is lost; only
  the `send_sms` error line survives — a documented stub limitation, see
  `migration/pgsql/osag/osag_plog.FINDINGS.md`.)
- **source:** `ddl/src/pkgb/osag_osag_msg.sql:91-94`

### S-MSG-012

- **routines:** send_sms
- **claim (CORRECTED — DEVIATION(PLATFORM)):** A `NULL`, empty, or all-spaces `p_sms_no`
  is a failure, handled by the S-MSG-011 path: no outbox row is created, no exception
  reaches the caller, and the error line reads `sending SMS to '' failed: ...` (Oracle's
  `NULL` concatenation renders the number as the empty string). In Oracle the recipient
  becomes the literal `'@mx-sms.open.ch'` (line 87), the message is handed to the MTA, and
  the failure — if any — is the MTA's `RCPT` rejection, which Oracle would also log and
  swallow. The translation rejects the row at queue time instead (the stripped number is
  collapsed to `NULL`, making the recipient `NULL`, which violates `NOT NULL`), because a
  shipper must never be handed a message with no local part.
- **source:** `ddl/src/pkgb/osag_osag_msg.sql:86-87, 91-94`

### S-MSG-013

- **routines:** send_mail, send_sms
- **claim (DEVIATION(PLATFORM)):** The SMTP transport moves out of the database into an
  external shipper that drains `osag.msg_outbox`. The following Oracle behaviours are
  therefore the shipper's, not the procedures': resolving the `HELO` host name from
  `v$instance` (line 23, the package's only `SELECT INTO`), connecting to `localhost:25`
  (lines 9-11, 51), generating the `Date:` header at send time in
  `'Dy, dd Mon YYYY HH24:MI:SS TZHTZM'` format (line 41), dot-stuffing lines that begin
  with `.` (line 49, DB-316), `HELO`/`MAIL`/`RCPT`/`DATA`/`QUIT` sequencing (52-56) and
  closing the connection on error (65). A freshly queued row has `sent_at IS NULL`,
  `attempts = 0`, `last_error IS NULL` and `created_at` set; the shipper owns those three
  mutable columns. The procedures never read the table.
- **source:** `ddl/src/pkgb/osag_osag_msg.sql:9-11, 23, 41, 49, 51-56, 65`

### S-MSG-014

- **routines:** send_mail, send_sms
- **claim:** Neither routine commits or rolls back (no `COMMIT`/`ROLLBACK`/autonomous
  pragma anywhere in the body); the queued row is part of the caller's transaction and is
  visible to the caller immediately and discarded if the caller rolls back. Both are
  Oracle `PROCEDURE`s and translate to PostgreSQL `PROCEDURE`s invoked with `CALL`.
- **source:** `ddl/src/pkg/osag_osag_msg.sql:40-41, 51`, `ddl/src/pkgb/osag_osag_msg.sql:5-6, 75`

### S-MSG-015

- **routines:** send_mail, send_sms
- **claim:** Each queued row records its origin: `kind = 'mail'` for a row queued through
  `send_mail`, `kind = 'sms'` for a row queued through `send_sms` (which Oracle expresses
  only through the `@mx-sms.open.ch` recipient domain, line 80/87). `kind` accepts no other
  value (`CHECK`, SQLSTATE `23514`).
- **source:** `ddl/src/pkgb/osag_osag_msg.sql:5, 75, 80, 87`

### S-MSG-016

- **routines:** send_mail, send_sms
- **claim:** The `plog.AuditUsage($$PLSQL_UNIT_OWNER, $$PLSQL_UNIT_TYPE, $$PLSQL_UNIT)`
  call at the top of each routine (2 sites) is deleted, not ported (XCUT-06: the feature is
  write-only and `osag.osag_plog_auditusage` deliberately does not exist). Neither routine
  may write to `osag.plsql_audit` or call a non-existent audit procedure.
- **source:** `ddl/src/pkgb/osag_osag_msg.sql:22, 85`

## Checklist

### 1. Empty-string / NULL handling

Every parameter of both routines is `VARCHAR2` (plus the collection `p_opt_headers`). Sites
where `''` vs `NULL` matters, all in `ddl/src/pkgb/osag_osag_msg.sql`:

- `NVL(p_from, p_reply_to)` (line 42) and `NVL(l_rfc822_mail_from, l_rfc822_reply_to)`
  (lines 28, 53, 58): `''` is reachable from any caller; Oracle collapses it to `NULL` and
  takes the fallback, a naive PostgreSQL `coalesce('' , x)` would return `''`. Decision:
  `NULLIF(x, '')` at the boundary for `p_from`, `p_mail_from`, `p_reply_to` (S-MSG-004).
- `p_subject` (lines 28, 45, 58): `send_sms` passes the literal `''` (line 87). Oracle
  stores/sends a `NULL` subject; decision: `NULLIF(p_subject, '')` so the row has
  `subject IS NULL` (S-MSG-004).
- `p_recipient` (lines 25, 44, 54): `''` → `NULL` recipient → `RCPT` fails in Oracle;
  decision: `NULLIF` then `NOT NULL` column → `23502` (S-MSG-008).
- `p_opt_headers IS NOT NULL AND .count > 0` (line 31): a collection, no `''` question;
  `NULL`/empty both mean "no extra headers" (S-MSG-005).
- `REPLACE(p_sms_no, ' ', '')` then `l_sms_no || '@' || S_SMS_DOMAIN` (lines 86-87):
  `NULL`/`''`/`'   '` all give `'@mx-sms.open.ch'` in Oracle (`NULL || '@...'` is
  `'@...'`); decision: `NULLIF(replace(...), '')` so the recipient becomes `NULL` and the
  row is rejected (S-MSG-012). The error text at line 94 concatenates `l_sms_no`, which
  Oracle renders as `''` when `NULL`; the translation uses `coalesce(l_sms_no, '')`.
- `||` concatenations in log lines (28, 58, 63, 89, 94): Oracle drops `NULL` operands;
  PostgreSQL would `NULL` the whole message. Decision: `coalesce(x, '')` around every
  nullable operand in log text so no log line is lost.
- `p_body` (line 46): never compared, only concatenated into the message; stored as-is
  (`''` and `NULL` are both "empty body"; the column is nullable and no normalisation is
  applied — left as-is, with the note that Oracle could not distinguish them either).

### 2. SELECT INTO strictness

Exactly one `SELECT ... INTO` site, matching the inventory count: line 23,
`select host_name into S_SMTP_HELO from v$instance`. On a single-instance database it
returns exactly one row; zero rows is impossible and more than one (RAC) would raise
`TOO_MANY_ROWS` into the `WHEN OTHERS` handler at line 60 (logged and re-raised). It is
not translated at all: the `HELO` host name is a transport concern that moves to the
shipper (S-MSG-013), so there is no `STRICT`/handler decision to make. No other SQL exists
in the package (verified over the full 97-line body).

### 3. Exception codes

No `RAISE_APPLICATION_ERROR`, no named exception, no `PRAGMA EXCEPTION_INIT` anywhere
(inventory `raise_application_error: []`). Two `WHEN OTHERS` handlers: `send_mail`'s
(lines 60-70) logs and re-raises with a bare `RAISE` — whatever SQLSTATE the underlying
failure carried propagates unchanged, so nothing needs mapping; `send_sms`'s (lines 91-94)
logs and swallows. In the outbox model the concrete underlying failures are PostgreSQL
constraint violations (`23502` not-null on recipient/envelope, `23514` check on
`kind`/`opt_headers` shape); these are PostgreSQL-native codes, not Oracle `-20NNN`
mappings, and nothing is left PROVISIONAL for XCUT-01.

### 4. Package state

None. The body (`ddl/src/pkgb/osag_osag_msg.sql`) opens with `PROCEDURE send_mail` at
line 5 directly after `IS` (line 3) and a separator comment (4); every constant
(`S_PREFIX`, `S_SMTP_PORT`, `S_SMTP_HOST`, `CRLF`, `S_EMAIL_REPLY_TO`, `S_SMS_DOMAIN`) is
routine-local (lines 8-12, 77-80); `S_SMTP_HELO` (line 20) is a routine-local variable
despite its constant-style name. The file ends at `END OSAG_MSG;` (line 96) with no
trailing initialization block. Matches the inventory's `package_state: []`,
`has_init_block: false`. The spec's `SUBTYPE`/`TYPE` declarations (lines 21-24) are types,
not state; their PostgreSQL shape is the `text[][]` the caller already uses.

### 5. FUNCTION vs PROCEDURE

No `COMMIT`, `ROLLBACK` or `PRAGMA AUTONOMOUS_TRANSACTION` in the package (full body read;
inventory `has_commit: false`, `has_rollback: false`, `autonomous_transaction: false`).
Both routines are Oracle `PROCEDURE`s (`ddl/src/pkg/osag_osag_msg.sql:40, 51`) and
`name-map.csv` carries `pg_kind=procedure` for both; the translation creates PostgreSQL
`PROCEDURE`s and the known caller (`tt.osag_notify`, already translated) invokes them with
`CALL`. There is no transaction-control hazard; the translated procedures deliberately
contain no `COMMIT` so they remain callable from inside a function or an outer
transaction (S-MSG-014).

## Assumptions / Unresolved

- **The outbox design itself is a platform decision, not an Oracle-derived fact.** No
  Oracle source line describes a queue; the shape of `osag.msg_outbox` (one row per
  message: `kind`, `envelope_from`, `reply_to`, `from_hdr`, `recipient`, `subject`, `body`,
  `opt_headers`, `created_at`, `sent_at`, `attempts`, `last_error`) is derived from what
  Oracle put into the SMTP envelope and headers (S-MSG-002/003/005) plus the minimum a
  retrying shipper needs. The shipper (SMTP client, `Date:` generation, dot-stuffing,
  retry policy, what happens to `attempts`/`last_error`) is out of scope for this
  migration and is not specified or tested here beyond the columns existing.
- Oracle's address regex uses `[^\<]`/`[^\>]` inside bracket expressions. Whether Oracle
  treats the backslash there as a literal character (POSIX) or as an escape is Oracle
  documentation knowledge; the only practical difference is for an address beginning with
  a backslash, which no real address does. The translation uses `[^<]`/`[^>]`.
- `UTL_SMTP.RCPT(NULL)` / `UTL_SMTP.MAIL(NULL)` are assumed to fail in Oracle (the MTA
  rejects an empty path, which `send_mail` would then log and re-raise). This cannot be
  verified without a live instance; S-MSG-008 maps it to a `NOT NULL` violation, which
  preserves the observable outcome (an exception from `send_mail`, swallowed by
  `send_sms`).
- `h_name`/`h_value` length limits (64/256, `ddl/src/pkg/osag_osag_msg.sql:21-22`) are not
  enforced on the `text[][]` column; nothing in the repo relies on the limit and the known
  caller passes two short fixed headers.
- The `plog` stub rides in the caller's transaction, so the S-MSG-008 error line written
  inside a failing `send_mail` sub-block is rolled back together with it when `send_sms`
  swallows the error (S-MSG-011). Under Oracle's autonomous-transaction `plog`, both lines
  would survive. This is a known limitation of the Phase 2 stub, not of this package, and
  is resolved by XCUT-02.
- Everything else was settled statically: every `NVL`/`||`/`IS NOT NULL` site, the single
  `SELECT INTO`, both `WHEN OTHERS` handlers, the declare sections and the absence of
  transaction control were reviewed against the full text of
  `ddl/src/pkg/osag_osag_msg.sql` and `ddl/src/pkgb/osag_osag_msg.sql`.
