-- migration/pgsql/osag/osag_msg.sql
--
-- Translation of OSAG.OSAG_MSG (spec: migration/spec/osag.osag_msg.md; Oracle body:
-- ddl/src/pkgb/osag_osag_msg.sql, 97 lines). The 2 public names are copied verbatim from
-- migration/mapping/name-map.csv's 2 OSAG_MSG rows (both pg_kind=procedure); the one
-- private helper follows the double-underscore convention (osag.osag_msg__enqueue,
-- REVOKE ALL FROM PUBLIC).
--
-- PLATFORM DECISION (locked before the spec was written, S-MSG-013): PostgreSQL has no
-- UTL_SMTP and must not open sockets from PL/pgSQL. The procedures therefore ENQUEUE a
-- fully-prepared message into the durable outbox table osag.msg_outbox (created below);
-- an external shipper process drains it and performs the SMTP transaction. Everything
-- Oracle did on the wire that is a transport concern -- HELO host from v$instance (body
-- line 23), localhost:25 (9-11, 51), the Date: header (41), dot-stuffing (49),
-- HELO/MAIL/RCPT/DATA/QUIT (52-56), closing the connection on error (65) -- moves to the
-- shipper and is documented in osag_msg.FINDINGS.md and in the COMMENT ON TABLE.
--
-- Oracle's usage-audit call (XCUT-06): both plog.AuditUsage sites DELETED, not ported
-- (body lines 22, 85). See osag_msg.FINDINGS.md.
--
-- NO COMMIT / ROLLBACK anywhere (S-MSG-014): the queued row rides in the caller's
-- transaction, exactly as Oracle's UTL_SMTP side effect would NOT have -- see FINDINGS
-- for the one semantic consequence (a rolled-back caller un-queues the message, which is
-- arguably better than Oracle's "mail sent, transaction rolled back").
--
-- Deviations are marked at the site with `-- DEVIATION(...)` and listed in FINDINGS.

-- ------------------------------------------------------------------------------------
-- The outbox. One row per message; the procedures only INSERT, the shipper owns
-- sent_at / attempts / last_error.
-- ------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS osag.msg_outbox (
    id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    kind          text        NOT NULL CHECK (kind IN ('mail', 'sms')),
    envelope_from text        NOT NULL,                 -- SMTP MAIL FROM (normalised, S-MSG-002)
    reply_to      text,                                  -- Reply-To: header, raw p_reply_to (S-MSG-003)
    from_hdr      text,                                  -- From: header, raw NVL(p_from, p_reply_to) (S-MSG-003)
    recipient     text        NOT NULL,                 -- SMTP RCPT TO and To: header (normalised, S-MSG-001)
    subject       text,                                  -- Subject: header; NULL when '' (S-MSG-004)
    body          text,
    opt_headers   text[][]    CHECK (opt_headers IS NULL
                                     OR (array_ndims(opt_headers) = 2 AND array_length(opt_headers, 2) = 2)),
    created_at    timestamptz NOT NULL DEFAULT clock_timestamp(),
    sent_at       timestamptz,
    attempts      int         NOT NULL DEFAULT 0,
    last_error    text
);

CREATE INDEX IF NOT EXISTS msg_outbox_unsent_idx ON osag.msg_outbox (created_at) WHERE sent_at IS NULL;

COMMENT ON TABLE osag.msg_outbox IS
    'Outbound mail/SMS queue written by osag.osag_msg_send_mail / osag.osag_msg_send_sms '
    '(translation of OSAG.OSAG_MSG, which used UTL_SMTP directly). An EXTERNAL SHIPPER '
    'process must: SELECT rows WHERE sent_at IS NULL ordered by created_at; connect to the '
    'local MTA (Oracle: localhost:25) and HELO with its own host name; MAIL FROM:'
    '<envelope_from>; RCPT TO:<recipient>; DATA with, in order: each opt_headers[i][1]: '
    'opt_headers[i][2] line, then "Date: <now, RFC 5322 Dy, dd Mon YYYY HH24:MI:SS TZHTZM>", '
    '"From: <from_hdr>", "Reply-To: <reply_to>", "To: <recipient>", "Subject: <subject>", a '
    'blank line, then body with SMTP dot-stuffing (a line starting with "." gets a second '
    '"."; Oracle DB-316); QUIT; then UPDATE sent_at = now(). On failure UPDATE attempts = '
    'attempts + 1, last_error = <text> and retry later. The procedures never read this '
    'table and never COMMIT. See migration/pgsql/osag/osag_msg.FINDINGS.md.';

COMMENT ON COLUMN osag.msg_outbox.kind IS '''mail'' for send_mail, ''sms'' for send_sms (S-MSG-015).';
COMMENT ON COLUMN osag.msg_outbox.opt_headers IS
    'Optional extra headers as a 2-D text array of [name, value] pairs (Oracle smtp_headers_t); NULL when none.';

-- ------------------------------------------------------------------------------------
-- PRIVATE __enqueue: the body of Oracle's send_mail (body lines 5-71), parameterised by
-- the outbox kind so send_sms can keep delegating through it (S-MSG-009) while the row
-- records 'sms' (S-MSG-015). Normalisation (24-26), debug line (28), header handling
-- (31-38), the row (40-46 + 53-54), notice (58), and the WHEN OTHERS log-and-RE-RAISE
-- (60-70) are all here. Both public procedures are thin wrappers.
--
-- S-MSG-004: Oracle collapses '' to NULL at every NVL site; NULLIF at the boundary
-- reproduces that for every text argument that takes part in a fallback or a NOT NULL
-- column. p_body is stored as given (nothing in Oracle compared it).
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE osag.osag_msg__enqueue(
    p_kind        text,
    p_reply_to    varchar,
    p_from        varchar,
    p_mail_from   varchar,
    p_recipient   varchar,
    p_subject     varchar,
    p_body        varchar,
    p_opt_headers text[][])
LANGUAGE plpgsql
AS $fn$
DECLARE
    s_prefix           CONSTANT text := 'OSAG.OSAG_MSG.send_mail(): ';
    l_reply_to         varchar := NULLIF(p_reply_to, '');
    l_from             varchar := NULLIF(p_from, '');
    l_mail_from        varchar := NULLIF(p_mail_from, '');
    l_recipient        varchar := NULLIF(p_recipient, '');
    l_subject          varchar := NULLIF(p_subject, '');
    l_rfc822_reply_to  text;
    l_rfc822_mail_from text;
    l_rfc822_recipient text;
    l_envelope_from    text;
    l_headers          text[][];
    l_id               bigint;
BEGIN
    -- S-MSG-001 (body lines 24-26): wrap a bare address in <...>; leave a value that
    -- already starts with '<' or ends with '>' alone; NULL stays NULL. Oracle's pattern
    -- is '^([^\<])(.*)([^\>]$)' -- the backslashes are literal-escapes inside Oracle's
    -- bracket expressions; PostgreSQL ARE needs the bare '[^<]' / '[^>]' form.
    l_rfc822_reply_to  := regexp_replace(l_reply_to,  '^([^<])(.*)([^>]$)', '<\1\2\3>');
    l_rfc822_recipient := regexp_replace(l_recipient, '^([^<])(.*)([^>]$)', '<\1\2\3>');
    l_rfc822_mail_from := regexp_replace(l_mail_from, '^([^<])(.*)([^>]$)', '<\1\2\3>');

    -- S-MSG-002 (body line 53): envelope sender = NVL(normalised mail_from, normalised reply_to)
    l_envelope_from := coalesce(l_rfc822_mail_from, l_rfc822_reply_to);

    -- S-MSG-006 (body line 28). coalesce(): Oracle's || drops NULL operands, PostgreSQL's
    -- would NULL the whole message and the log line would be lost.
    CALL osag.osag_plog_debug(s_prefix || 'from: ''' || coalesce(l_envelope_from, '')
        || ''', recipient: ''' || coalesce(l_rfc822_recipient, '')
        || ''', subject: ''' || coalesce(l_subject, '') || '''');

    -- S-MSG-005 (body line 31): NULL or .count = 0 -> no optional headers -> store NULL.
    -- A non-empty array is stored verbatim; the table CHECK enforces the [name, value]
    -- pair shape (23514), which the handler below logs and re-raises like any failure.
    IF p_opt_headers IS NULL OR cardinality(p_opt_headers) = 0 THEN
        l_headers := NULL;
    ELSE
        l_headers := p_opt_headers;
    END IF;

    -- S-MSG-003 (body lines 40-46), S-MSG-013: the row IS the message. Date: header,
    -- dot-stuffing and the SMTP dialogue (lines 41, 49, 51-56) are the shipper's.
    -- DEVIATION(PLATFORM) S-MSG-013: no UTL_SMTP; INSERT into the outbox instead.
    -- A NULL recipient / envelope sender violates NOT NULL here (23502), where Oracle's
    -- MTA would have rejected the RCPT/MAIL command (S-MSG-008) -- same outcome: an
    -- exception out of send_mail, no message.
    INSERT INTO osag.msg_outbox (kind, envelope_from, reply_to, from_hdr, recipient, subject, body, opt_headers)
    VALUES (p_kind,
            l_envelope_from,
            l_reply_to,                               -- Reply-To: p_reply_to (raw)
            coalesce(l_from, l_reply_to),             -- From: NVL(p_from, p_reply_to) (raw)
            l_rfc822_recipient,                       -- To: / RCPT (normalised)
            l_subject,
            p_body,
            l_headers)
    RETURNING id INTO l_id;

    -- S-MSG-007 (body line 58). Oracle: 'sent mail from ... to ... subject: ...'; the
    -- hand-off here is to the outbox, so 'queued', plus the row id for operators.
    -- DEVIATION(PLATFORM) S-MSG-007: wording 'sent' -> 'queued ... (outbox id N)'.
    CALL osag.osag_plog_notice(s_prefix || 'queued mail from ''' || coalesce(l_envelope_from, '')
        || ''' to ''' || coalesce(l_rfc822_recipient, '')
        || ''' subject: ''' || coalesce(l_subject, '') || ''' (outbox id ' || l_id || ')');

EXCEPTION
    WHEN OTHERS THEN
        -- S-MSG-008 (body lines 60-70): log, then RE-RAISE unchanged. dbms_output
        -- (line 62) and UTL_SMTP.CLOSE_CONNECTION (64-69) have no counterpart here.
        CALL osag.osag_plog_err(s_prefix || 'send mail to ''' || coalesce(l_rfc822_recipient, '')
            || ''' failed: ' || SQLSTATE || ': ' || SQLERRM);
        RAISE;
END;
$fn$;

REVOKE ALL ON PROCEDURE osag.osag_msg__enqueue(text, varchar, varchar, varchar, varchar, varchar, varchar, text[][]) FROM PUBLIC;

-- ------------------------------------------------------------------------------------
-- send_mail (S-MSG-001..008, S-MSG-014/015): public wrapper, kind = 'mail'.
-- p_opt_headers defaults to NULL exactly as Oracle's `smtp_headers_t := NULL`
-- (ddl/src/pkg/osag_osag_msg.sql:41); tt.osag_notify calls it with both 6 and 7
-- arguments. No handler of its own: __enqueue already logged and re-raised (S-MSG-008).
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE osag.osag_msg_send_mail(
    p_reply_to    varchar,
    p_from        varchar,
    p_mail_from   varchar,
    p_recipient   varchar,
    p_subject     varchar,
    p_body        varchar,
    p_opt_headers text[][] DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
BEGIN
    CALL osag.osag_msg__enqueue('mail', p_reply_to, p_from, p_mail_from, p_recipient, p_subject, p_body, p_opt_headers);
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- send_sms (S-MSG-009..012, S-MSG-014/015): strip spaces, delegate with the fixed
-- reply-to / SMS-gateway recipient / '' subject (body lines 79-87), notice (89), and
-- the WHEN OTHERS that logs and SWALLOWS (91-94) -- send_sms never raises.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE osag.osag_msg_send_sms(p_sms_no varchar, p_body varchar)
LANGUAGE plpgsql
AS $fn$
DECLARE
    s_prefix         CONSTANT text    := 'OSAG.OSAG_MSG.send_sms(): ';
    s_email_reply_to CONSTANT varchar := 'support@open.ch';
    s_sms_domain     CONSTANT varchar := 'mx-sms.open.ch';
    l_sms_no         varchar;
BEGIN
    -- body line 86, plus:
    -- DEVIATION(PLATFORM) S-MSG-012: a NULL / '' / all-spaces number is collapsed to NULL
    -- so the recipient below becomes NULL and __enqueue rejects it (23502) -> caught and
    -- logged right here, nothing queued. Oracle built the literal '@mx-sms.open.ch'
    -- (NULL || '@' || domain) and let the MTA reject it at RCPT time -- same observable
    -- outcome for the caller (no exception, an ERR log line), but a shipper must never
    -- be handed an address with no local part.
    l_sms_no := NULLIF(replace(p_sms_no, ' ', ''), '');

    -- body line 87: send_mail(S_EMAIL_REPLY_TO, NULL, NULL, l_sms_no||'@'||S_SMS_DOMAIN, '', p_body)
    CALL osag.osag_msg__enqueue('sms', s_email_reply_to, NULL, NULL,
                                l_sms_no || '@' || s_sms_domain, '', p_body, NULL);

    -- S-MSG-010 (body line 89) -- Oracle labels the body "subject"; reproduced verbatim.
    CALL osag.osag_plog_notice(s_prefix || 'sent SMS to ''' || coalesce(l_sms_no, '')
        || ''' subject: ''' || coalesce(p_body, '') || '''');

EXCEPTION
    WHEN OTHERS THEN
        -- S-MSG-011 (body lines 91-94): log and swallow. No RAISE.
        CALL osag.osag_plog_err(s_prefix || 'sending SMS to ''' || coalesce(l_sms_no, '')
            || ''' failed: ' || SQLSTATE || ': ' || SQLERRM);
END;
$fn$;
