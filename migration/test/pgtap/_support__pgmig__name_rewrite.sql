-- migration/test/pgtap/_support__pgmig__name_rewrite.sql
--
-- pgTAP coverage for migration/pgsql/_support/10_pgmig_name_rewrite.sql -- the
-- in-database twin of migration/mapping/rewrite_names.py. "_support" is a reserved
-- harness schema (pkgname.py / trace_lint.py), not an Oracle package: these objects have
-- no Oracle original and therefore no spec; assertions are labelled PGMIG-NN instead of
-- spec clause ids. The expected values mirror migration/mapping/tests/test_rewrite_names.py
-- so the two implementations cannot drift apart unnoticed.

BEGIN;
SELECT plan(10);

SELECT is(pgmig.rewrite_oracle_names('tt.ticket_interface.change_status(p_ticket_id, 102, NULL, ''x'');'),
          'tt.ticket_interface_change_status(p_ticket_id, 102, NULL, ''x'');',
          'PGMIG-01: three-part routine reference is rewritten');
SELECT is(pgmig.rewrite_oracle_names('TT . Ticket_Interface .CHANGE_STATUS(1)'),
          'tt.ticket_interface_change_status(1)',
          'PGMIG-02: case and whitespace around the dots are tolerated');
SELECT is(pgmig.rewrite_oracle_names('"TT"."TICKET_INTERFACE"."CHANGE_STATUS"(1)'),
          'tt.ticket_interface_change_status(1)',
          'PGMIG-03: quoted identifiers collapse to the unquoted lower-case name');
SELECT is(pgmig.rewrite_oracle_names('^tt\.escalation_interface\.escalate_os$'),
          '^tt\.escalation_interface_escalate_os$',
          'PGMIG-04: a regex stored in data keeps its escaped first separator');
SELECT is(pgmig.rewrite_oracle_names('SELECT t.id FROM tt.ticket t WHERE tt.ticket.id = 1'),
          'SELECT t.id FROM tt.ticket t WHERE tt.ticket.id = 1',
          'PGMIG-05: schema.table.column is never mistaken for a routine');
SELECT is(pgmig.rewrite_oracle_names('v_proc := ''tt.escalation_interface.'' || v_name;'),
          'v_proc := ''tt.escalation_interface_'' || v_name;',
          'PGMIG-06: dynamically fabricated prefix before a closing quote is rewritten');
SELECT is(pgmig.rewrite_oracle_names('^tt\.escalation_interface\.(nop|escalate_(customer|os))$'),
          '^tt\.escalation_interface_(nop|escalate_(customer|os))$',
          'PGMIG-07: dynamic prefix before a regex group (mss.key.regexp shape)');
SELECT is(pgmig.rewrite_oracle_names('plog.debug(''x''); OSAG_IP.num2ip(v);'),
          'osag.osag_plog_debug(''x''); mss.osag_ip_num2ip(v);',
          'PGMIG-08: public-synonym references become schema-qualified');
SELECT is(pgmig.rewrite_oracle_names(NULL), NULL, 'PGMIG-09: NULL in, NULL out');

-- the masterdata rows the migration actually has to rewrite
SELECT is((SELECT count(*)::int FROM pgmig.apply_data_name_rewrites() WHERE rows_changed > 0), 3,
          'PGMIG-10: apply_data_name_rewrites touches event_action.procedure_name, mss.key.string_default and mss.key.regexp on the template masterdata');

SELECT * FROM finish();
ROLLBACK;
