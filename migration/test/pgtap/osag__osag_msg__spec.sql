-- migration/test/pgtap/osag__osag_msg__spec.sql
--
-- pgTAP verification for migration/spec/osag.osag_msg.md. RED by construction: neither
-- osag.osag_msg_send_mail / osag.osag_msg_send_sms nor the osag.msg_outbox table exists
-- when this file is first committed (the translation lands in a later commit;
-- provenance_lint.sh enforces the order). Every assertion's description starts with the
-- spec clause ID it verifies (HARN-05, trace_lint.py).
--
-- The spec is written against the locked platform decision that PostgreSQL enqueues a
-- fully-prepared message into osag.msg_outbox and an external shipper does SMTP. So
-- "what Oracle put on the wire" is asserted here as "what the newest outbox row holds".
--
-- throws_ok is always used in its 4-argument form (sql, sqlstate, NULL, description):
-- the 3-argument (sql, sqlstate, description) form treats the description as the
-- expected error MESSAGE and can never pass (see migration/spec/TEST-AMENDMENTS.md A-001).

BEGIN;

SELECT plan(63);

-- Baseline: this file only reasons about rows IT creates. Any pre-existing outbox rows
-- (there should be none in a fresh clone, but be robust) are excluded via this id mark.
CREATE TEMP TABLE t_mark AS SELECT coalesce(max(id), 0) AS id0 FROM osag.msg_outbox;

-- Helper view over "rows created by this file", newest first.
CREATE TEMP VIEW v_mine AS
    SELECT o.* FROM osag.msg_outbox o, t_mark m WHERE o.id > m.id0 ORDER BY o.id DESC;

-- ---------------------------------------------------------------------------------
-- S-MSG-013: the outbox exists and carries the shipper's bookkeeping columns
-- ---------------------------------------------------------------------------------
SELECT has_table('osag', 'msg_outbox',
    'S-MSG-013: osag.msg_outbox exists');
SELECT has_column('osag', 'msg_outbox', 'sent_at',
    'S-MSG-013: osag.msg_outbox.sent_at exists (shipper-owned)');
SELECT has_column('osag', 'msg_outbox', 'attempts',
    'S-MSG-013: osag.msg_outbox.attempts exists (shipper-owned)');
SELECT has_column('osag', 'msg_outbox', 'last_error',
    'S-MSG-013: osag.msg_outbox.last_error exists (shipper-owned)');

-- ---------------------------------------------------------------------------------
-- send_mail, all six addresses/texts given, no optional headers
-- ---------------------------------------------------------------------------------
SELECT lives_ok(
    $$CALL osag.osag_msg_send_mail('a@x.ch', 'b@x.ch', 'c@x.ch', 'd@x.ch', 'subj', 'body')$$,
    'S-MSG-014: send_mail with every argument given returns normally (no COMMIT needed, no error)');
SELECT is((SELECT count(*)::int FROM v_mine), 1,
    'S-MSG-014: exactly one outbox row was queued, visible inside the caller''s own transaction');
SELECT is((SELECT kind FROM v_mine LIMIT 1), 'mail',
    'S-MSG-015: a row queued through send_mail has kind = ''mail''');
SELECT is((SELECT envelope_from FROM v_mine LIMIT 1), '<c@x.ch>',
    'S-MSG-002: envelope_from is the normalised p_mail_from when one was given');
SELECT is((SELECT reply_to FROM v_mine LIMIT 1), 'a@x.ch',
    'S-MSG-003: reply_to holds the RAW p_reply_to (Reply-To header is not normalised)');
SELECT is((SELECT from_hdr FROM v_mine LIMIT 1), 'b@x.ch',
    'S-MSG-003: from_hdr holds the RAW p_from (From header is not normalised)');
SELECT is((SELECT recipient FROM v_mine LIMIT 1), '<d@x.ch>',
    'S-MSG-001: recipient is wrapped in angle brackets when given bare');
SELECT is((SELECT subject FROM v_mine LIMIT 1), 'subj',
    'S-MSG-003: subject holds p_subject verbatim');
SELECT is((SELECT body FROM v_mine LIMIT 1), 'body',
    'S-MSG-003: body holds p_body verbatim');
SELECT ok((SELECT opt_headers IS NULL FROM v_mine LIMIT 1),
    'S-MSG-005: opt_headers is NULL when the argument was omitted (declared default NULL)');
SELECT ok((SELECT sent_at IS NULL FROM v_mine LIMIT 1),
    'S-MSG-013: a freshly queued row has sent_at IS NULL');
SELECT is((SELECT attempts FROM v_mine LIMIT 1), 0,
    'S-MSG-013: a freshly queued row has attempts = 0');
SELECT ok((SELECT last_error IS NULL FROM v_mine LIMIT 1),
    'S-MSG-013: a freshly queued row has last_error IS NULL');
SELECT ok((SELECT created_at IS NOT NULL FROM v_mine LIMIT 1),
    'S-MSG-013: a freshly queued row has created_at set');

-- S-MSG-006 / S-MSG-007: the two plog lines around the hand-off
SELECT ok(EXISTS (
        SELECT 1 FROM osag.plog_stub_log
         WHERE loglevel = 7
           AND message = 'OSAG.OSAG_MSG.send_mail(): from: ''<c@x.ch>'', recipient: ''<d@x.ch>'', subject: ''subj'''),
    'S-MSG-006: send_mail logs the from/recipient/subject DEBUG line with the envelope sender and normalised recipient');
SELECT ok(EXISTS (
        SELECT 1 FROM osag.plog_stub_log
         WHERE loglevel = 5
           AND message LIKE 'OSAG.OSAG_MSG.send_mail(): %mail from ''<c@x.ch>'' to ''<d@x.ch>'' subject: ''subj''%'),
    'S-MSG-007: send_mail logs the NOTICE line naming envelope sender, normalised recipient and subject after hand-off');

-- ---------------------------------------------------------------------------------
-- S-MSG-001: already-bracketed / display-name addresses are left alone
-- ---------------------------------------------------------------------------------
SELECT lives_ok(
    $$CALL osag.osag_msg_send_mail('<a@x.ch>', NULL, 'Sender <c@x.ch>', 'Name <d@x.ch>', 's', 'b')$$,
    'S-MSG-001: send_mail accepts already-formatted addresses');
SELECT is((SELECT envelope_from FROM v_mine LIMIT 1), 'Sender <c@x.ch>',
    'S-MSG-001: a value ending in ''>'' is not wrapped again (envelope)');
SELECT is((SELECT recipient FROM v_mine LIMIT 1), 'Name <d@x.ch>',
    'S-MSG-001: a value ending in ''>'' is not wrapped again (recipient)');
SELECT is((SELECT reply_to FROM v_mine LIMIT 1), '<a@x.ch>',
    'S-MSG-001: a value starting with ''<'' is stored as given');

-- ---------------------------------------------------------------------------------
-- S-MSG-002 / S-MSG-004: '' collapses to NULL and triggers the NVL fallbacks
-- ---------------------------------------------------------------------------------
SELECT lives_ok(
    $$CALL osag.osag_msg_send_mail('a@x.ch', '', '', 'd@x.ch', '', 'b')$$,
    'S-MSG-004: send_mail accepts empty strings where Oracle accepted NULL');
SELECT is((SELECT envelope_from FROM v_mine LIMIT 1), '<a@x.ch>',
    'S-MSG-002: envelope_from falls back to the normalised p_reply_to when p_mail_from is ''''');
SELECT is((SELECT from_hdr FROM v_mine LIMIT 1), 'a@x.ch',
    'S-MSG-004: from_hdr falls back to the raw p_reply_to when p_from is ''''');
SELECT ok((SELECT subject IS NULL FROM v_mine LIMIT 1),
    'S-MSG-004: an empty-string subject is stored as NULL, never as ''''');
SELECT lives_ok(
    $$CALL osag.osag_msg_send_mail('a@x.ch', NULL, NULL, 'd@x.ch', NULL, 'b')$$,
    'S-MSG-003: send_mail accepts NULL p_from / p_mail_from / p_subject');
SELECT is((SELECT from_hdr FROM v_mine LIMIT 1), 'a@x.ch',
    'S-MSG-003: from_hdr is NVL(p_from, p_reply_to) -- the raw reply-to when p_from is NULL');

-- ---------------------------------------------------------------------------------
-- S-MSG-005: optional headers
-- ---------------------------------------------------------------------------------
SELECT lives_ok(
    $$CALL osag.osag_msg_send_mail('a@x.ch', 'monitoring@open.ch', 'ttbounce+1@open.ch', 'd@x.ch', 's', 'b',
          ARRAY[['Auto-Submitted', 'auto-generated'], ['Precedence', 'bulk']])$$,
    'S-MSG-005: send_mail accepts a text[][] of [name, value] header pairs (the tt.osag_notify call shape)');
SELECT is((SELECT opt_headers FROM v_mine LIMIT 1),
    ARRAY[['Auto-Submitted', 'auto-generated'], ['Precedence', 'bulk']]::text[],
    'S-MSG-005: opt_headers holds the caller''s pairs verbatim and in order');
SELECT lives_ok(
    $$CALL osag.osag_msg_send_mail('a@x.ch', NULL, NULL, 'd@x.ch', 's', 'b', '{}'::text[])$$,
    'S-MSG-005: send_mail accepts an empty header array');
SELECT ok((SELECT opt_headers IS NULL FROM v_mine LIMIT 1),
    'S-MSG-005: an empty header array is stored as NULL (Oracle: .count = 0 means no header lines)');
SELECT throws_ok(
    $$CALL osag.osag_msg_send_mail('a@x.ch', NULL, NULL, 'd@x.ch', 's', 'b', ARRAY['Precedence', 'bulk'])$$,
    '23514', NULL,
    'S-MSG-005: a header array that is not [name, value] pairs is rejected by the CHECK constraint');

-- ---------------------------------------------------------------------------------
-- S-MSG-008: send_mail re-raises; nothing is queued on failure
-- ---------------------------------------------------------------------------------
SELECT is((SELECT count(*)::int FROM v_mine), 5,
    'S-MSG-008: baseline before the failure cases -- five rows queued so far');
SELECT throws_ok(
    $$CALL osag.osag_msg_send_mail('a@x.ch', NULL, NULL, NULL, 's', 'b')$$,
    '23502', NULL,
    'S-MSG-008: a NULL recipient raises not_null_violation to the caller (Oracle: RCPT rejected, logged, re-raised)');
SELECT throws_ok(
    $$CALL osag.osag_msg_send_mail('a@x.ch', NULL, NULL, '', 's', 'b')$$,
    '23502', NULL,
    'S-MSG-008: an empty-string recipient raises the same not_null_violation (''''/NULL collapsing)');
SELECT throws_ok(
    $$CALL osag.osag_msg_send_mail(NULL, 'b@x.ch', NULL, 'd@x.ch', 's', 'b')$$,
    '23502', NULL,
    'S-MSG-008: no envelope sender at all (p_mail_from and p_reply_to both NULL) raises not_null_violation');
SELECT is((SELECT count(*)::int FROM v_mine), 5,
    'S-MSG-008: none of the failed send_mail calls queued a row');

-- ---------------------------------------------------------------------------------
-- S-MSG-009 / S-MSG-010 / S-MSG-015: send_sms happy path
-- ---------------------------------------------------------------------------------
SELECT lives_ok(
    $$CALL osag.osag_msg_send_sms('+41 79 123 45 67', 'hello')$$,
    'S-MSG-009: send_sms returns normally');
SELECT is((SELECT kind FROM v_mine LIMIT 1), 'sms',
    'S-MSG-015: a row queued through send_sms has kind = ''sms''');
SELECT is((SELECT recipient FROM v_mine LIMIT 1), '<+41791234567@mx-sms.open.ch>',
    'S-MSG-009: recipient is the space-stripped number at mx-sms.open.ch, normalised');
SELECT is((SELECT reply_to FROM v_mine LIMIT 1), 'support@open.ch',
    'S-MSG-009: reply_to is the fixed support@open.ch');
SELECT is((SELECT from_hdr FROM v_mine LIMIT 1), 'support@open.ch',
    'S-MSG-009: from_hdr falls back to support@open.ch (p_from is NULL)');
SELECT is((SELECT envelope_from FROM v_mine LIMIT 1), '<support@open.ch>',
    'S-MSG-009: envelope_from falls back to the normalised support@open.ch (p_mail_from is NULL)');
SELECT ok((SELECT subject IS NULL FROM v_mine LIMIT 1),
    'S-MSG-009: subject is NULL (Oracle passes the literal '''')');
SELECT is((SELECT body FROM v_mine LIMIT 1), 'hello',
    'S-MSG-009: body is the SMS text');
SELECT ok((SELECT opt_headers IS NULL FROM v_mine LIMIT 1),
    'S-MSG-009: no optional headers for an SMS');
SELECT ok(EXISTS (
        SELECT 1 FROM osag.plog_stub_log
         WHERE loglevel = 5
           AND message = 'OSAG.OSAG_MSG.send_sms(): sent SMS to ''+41791234567'' subject: ''hello'''),
    'S-MSG-010: send_sms logs its NOTICE line with the stripped number and the body labelled "subject"');

-- ---------------------------------------------------------------------------------
-- S-MSG-011 / S-MSG-012: send_sms swallows; NULL / blank number is a logged failure
-- ---------------------------------------------------------------------------------
SELECT is((SELECT count(*)::int FROM v_mine), 6,
    'S-MSG-011: baseline before the swallow cases -- six rows queued so far');
SELECT lives_ok(
    $$CALL osag.osag_msg_send_sms(NULL, 'x')$$,
    'S-MSG-011: send_sms(NULL, ...) does NOT raise -- the failure is swallowed');
SELECT is((SELECT count(*)::int FROM v_mine), 6,
    'S-MSG-012: send_sms(NULL, ...) queued nothing');
SELECT ok(EXISTS (
        SELECT 1 FROM osag.plog_stub_log
         WHERE loglevel = 3
           AND message LIKE 'OSAG.OSAG_MSG.send_sms(): sending SMS to '''' failed: %'),
    'S-MSG-012: the swallowed failure is logged as ERR with the number rendered as '''' (Oracle NULL concatenation)');
SELECT lives_ok(
    $$CALL osag.osag_msg_send_sms('   ', 'x')$$,
    'S-MSG-012: an all-spaces number does not raise either');
SELECT is((SELECT count(*)::int FROM v_mine), 6,
    'S-MSG-012: an all-spaces number queued nothing');

-- ---------------------------------------------------------------------------------
-- S-MSG-015: kind is constrained
-- ---------------------------------------------------------------------------------
SELECT throws_ok(
    $$INSERT INTO osag.msg_outbox (kind, envelope_from, recipient, body) VALUES ('fax', '<a@x.ch>', '<d@x.ch>', 'b')$$,
    '23514', NULL,
    'S-MSG-015: kind accepts only ''mail'' and ''sms''');

-- ---------------------------------------------------------------------------------
-- S-MSG-016: no usage-audit, S-MSG-014: PROCEDUREs without transaction control
-- ---------------------------------------------------------------------------------
SELECT ok(NOT EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'osag' AND p.proname LIKE 'osag_msg%' AND p.prosrc ~* 'auditusage'),
    'S-MSG-016: no osag_msg routine references AuditUsage (both Oracle sites deleted)');
SELECT is((SELECT count(*)::int FROM osag.plsql_audit WHERE upper(coalesce(object_name, '')) LIKE '%OSAG_MSG%'), 0,
    'S-MSG-016: nothing was written to osag.plsql_audit by the calls above');
SELECT is((SELECT prokind::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'osag' AND p.proname = 'osag_msg_send_mail'), 'p',
    'S-MSG-014: osag.osag_msg_send_mail is a PROCEDURE');
SELECT is((SELECT prokind::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'osag' AND p.proname = 'osag_msg_send_sms'), 'p',
    'S-MSG-014: osag.osag_msg_send_sms is a PROCEDURE');
SELECT ok(NOT EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'osag' AND p.proname LIKE 'osag_msg%' AND p.prosrc ~* '\m(commit|rollback)\M'),
    'S-MSG-014: no osag_msg routine contains COMMIT or ROLLBACK');
SELECT is((SELECT count(*)::int FROM v_mine WHERE xmin = txid_current()::text::xid), 6,
    'S-MSG-014: every queued row was written by THIS (uncommitted) transaction -- rows ride in the caller''s transaction, no autonomous commit');

SELECT * FROM finish();
ROLLBACK;
