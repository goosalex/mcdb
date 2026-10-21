-- migration/test/pgtap/tt__ticket_interface__changes.sql
--
-- pgTAP verification of migration/spec/tt.ticket_interface.md's change_* family
-- (minus change_status/change_status_event_id_out/expire_status, covered by
-- tt__ticket_interface__lifecycle.sql), the corpus's one genuine overload pair
-- (change_label), rate_ticket, classify_request, the add_*/remove_* pairs
-- (docs_page, related_ticket, related_file), and the todo-list routines.
--
-- RED by construction. Every assertion's description begins with the spec
-- clause ID it verifies (HARN-05, trace_lint.py). Source of expected values is
-- migration/spec/tt.ticket_interface.md ONLY (the_one_rule, plan 02-08).
--
-- This suite is the pilot's designated home for Pitfall 2 (PITFALLS.md):
-- ''-vs-NULL paired assertions for change_customer_reference/
-- change_partner_reference (S-TICKET-018/S-TICKET-022), the only two routines
-- the spec's Checklist dimension 1 found with a genuine audit-text-only
-- divergence -- every OTHER IS NULL/IS NOT NULL/|| site in this package was
-- reviewed by the spec and found to have no ''-collapsing relevance
-- (Checklist section 1's closing paragraph), so this suite does not invent
-- extra paired assertions where the spec found none to invent.

BEGIN;
SET CONSTRAINTS ALL DEFERRED;
SELECT plan(83);

-------------------------------------------------------------------------------
-- Fixtures (906xxx id range, disjoint from lifecycle.sql's 905xxx and the
-- osag_notify/event_interface pilot ranges). Reused reference data: labels
-- 1-4, todo_item_status 1-4, service_type 6, service_level 1, operating_system
-- 2 -- all pre-existing masterdata rows in mcdb_tmpl.
-------------------------------------------------------------------------------

INSERT INTO stop.company (id, name, short) VALUES (906001, 'Pilot Changes Co', 'pltich1');
INSERT INTO stop.company (id, name, short) VALUES (906023, 'Pilot Changes Co Two', 'pltich2');
INSERT INTO stop.contact (id, lastname, firstname, short, company_id) VALUES (906002, 'Requester', 'Pilot', 'pltcrq1', 906001);
INSERT INTO stop.contact (id, lastname, firstname, short, company_id) VALUES (906003, 'NewOwner', 'Pilot', 'pltcow1', 906001);
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author)
    VALUES (906004, 'pilot-ti-host-old', 2, 906001, 'pilot');
INSERT INTO mss.host (id, name, operating_system_id, service_company_id, author)
    VALUES (906005, 'pilot-ti-host-new', 2, 906001, 'pilot');
INSERT INTO mss.service (id, service_type_id, company_id, service_level_id, name)
    VALUES (906006, 6, 906001, 1, 'pilot-svc-old-ti');
INSERT INTO mss.service (id, service_type_id, company_id, service_level_id, name)
    VALUES (906007, 6, 906001, 1, 'pilot-svc-new-ti');

-- The general-purpose ticket most single-attribute change_* routines mutate.
-- Deliberately unassigned (worker_id NULL) so change_worker's local
-- NO_DATA_FOUND default path is exercised on the OLD-worker lookup.
INSERT INTO tt.ticket (id, type_id, status_id, company_id, contact_id, host_id, mss_service_id)
    VALUES (906010, 1, 2, 906001, 906002, 906004, 906006);

-- Two tickets dedicated to proving the change_label overload pair dispatches
-- distinctly (S-TICKET-019 vs S-TICKET-020).
INSERT INTO tt.ticket (id, type_id, status_id, company_id) VALUES (906011, 1, 2, 906001);
INSERT INTO tt.ticket (id, type_id, status_id, company_id) VALUES (906012, 1, 2, 906001);

-- change_company / change_owner / change_type / change_service_component.
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id, mss_service_id)
    VALUES (906013, 1, 2, 906001, 906004, 906006);
INSERT INTO tt.ticket (id, type_id, status_id, company_id) VALUES (906014, 1, 2, 906001);

-- rate_ticket.
INSERT INTO tt.ticket (id, type_id, status_id, company_id) VALUES (906015, 1, 2, 906001);
INSERT INTO tt.event (id, type_id, ticket_id) VALUES (906016, 905006, 906015);

-- add_docs_page / remove_docs_page.
INSERT INTO tt.ticket (id, type_id, status_id, company_id) VALUES (906017, 1, 2, 906001);

-- add_related_ticket / remove_related_ticket.
INSERT INTO tt.ticket (id, type_id, status_id, company_id) VALUES (906018, 1, 2, 906001);
INSERT INTO tt.ticket (id, type_id, status_id, company_id) VALUES (906019, 1, 2, 906001);

-- add_related_file / remove_related_file: file 906021 released to company
-- 906023, but ticket 906020 belongs to company 906001 -- a deliberate
-- cross-company mismatch for S-TICKET-044's authorization-guard NO_DATA_FOUND.
INSERT INTO tt.ticket (id, type_id, status_id, company_id) VALUES (906020, 1, 2, 906001);
INSERT INTO mc.mc_file (id, uploader_id, display_name, description, filename, mime_type, mc_file_type_id)
    VALUES (906021, 906002, 'pilot-file.txt', 'pilot file', 'pilot-file.txt', 'text/plain', 900299999);
INSERT INTO mc.mc_file_release (id, company_id, mc_file_id) VALUES (906022, 906023, 906021);
-- A second, same-company file/relation for remove_related_file's own fixture.
-- TEST-AMENDMENTS.md A-014: the fixture always described this file as "same-company"
-- but never released it to the ticket's company 906001; since the Q11 (d) correction
-- (S-TICKET-060) remove_related_file requires that release, so the row is added.
INSERT INTO mc.mc_file (id, uploader_id, display_name, description, filename, mime_type, mc_file_type_id)
    VALUES (906028, 906002, 'pilot-file2.txt', 'pilot file 2', 'pilot-file2.txt', 'text/plain', 900299999);
INSERT INTO mc.mc_file_release (id, company_id, mc_file_id) VALUES (906031, 906001, 906028);
INSERT INTO tt.ticket2mc_file (ticket_id, mc_file_id) VALUES (906020, 906028);

-- classify_request / clear_todo_list / add_todo_item / update_todo_item_status.
INSERT INTO tt.ticket (id, type_id, status_id, company_id) VALUES (906024, 1, 2, 906001);
INSERT INTO tt.ticket (id, type_id, status_id, company_id, host_id) VALUES (906025, 1, 2, 906001, 906004);
INSERT INTO tt.todo_item (id, ticket_id, seq_no, details, todo_item_status_id, is_public)
    VALUES (906029, 906025, 1, 'pilot pre-existing todo', 1, 1);
INSERT INTO tt.ticket (id, type_id, status_id, company_id) VALUES (906026, 1, 2, 906001);
INSERT INTO tt.ticket (id, type_id, status_id, company_id) VALUES (906027, 1, 2, 906001);
INSERT INTO tt.todo_item (id, ticket_id, seq_no, details, todo_item_status_id, is_public)
    VALUES (906030, 906027, 1, 'pilot updatable todo', 1, 1);

-------------------------------------------------------------------------------
-- change_worker (S-TICKET-013, S-TICKET-014)
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL tt.ticket_interface_change_worker(906010, 906099999, 906002)$$,
    'S-TICKET-013: change_worker succeeds even for a nonexistent p_worker_id -- its local NO_DATA_FOUND handler defaults the new-worker label to the synthetic ''MCC'' rather than raising'
);

SELECT lives_ok(
    $$CALL tt.ticket_interface_change_worker(906010, 906003, 906002)$$,
    'S-TICKET-014: change_worker succeeds for ticket 906010 despite its OLD worker_id being NULL (unassigned) -- the local NO_DATA_FOUND handler on the old-worker lookup defaults to the synthetic ''MCC'' label, not an error'
);

SELECT throws_ok(
    $$CALL tt.ticket_interface_change_worker(906099998, 906003, 906002)$$,
    'P0002',
    NULL,
    'S-TICKET-014: change_worker propagates NO_DATA_FOUND unhandled for a nonexistent p_ticket_id at site #23 (company_id lookup, AFTER both local handler blocks have already closed)'
);

-------------------------------------------------------------------------------
-- change_subject (S-TICKET-017)
-------------------------------------------------------------------------------

SELECT throws_ok(
    $$CALL tt.ticket_interface_change_subject(906099997, 'new subject', 906002)$$,
    'P0002',
    NULL,
    'S-TICKET-017: change_subject propagates NO_DATA_FOUND unhandled for a nonexistent p_ticket_id (site #29, company_id lookup)'
);

SELECT lives_ok(
    $$CALL tt.ticket_interface_change_subject(906010, 'a brand new subject', 906002)$$,
    'S-TICKET-017: change_subject succeeds for a valid ticket, resolving both company_id (site #29) and the old subject (site #30) without error'
);

SELECT is(
    (SELECT subject FROM tt.ticket WHERE id = 906010),
    'a brand new subject',
    'S-TICKET-017: change_subject wrote the new subject onto the ticket row'
);

-------------------------------------------------------------------------------
-- change_customer_reference (S-TICKET-018) -- Pitfall 2, paired '' vs NULL
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL tt.ticket_interface_change_customer_reference(906010, NULL, 906002)$$,
    'S-TICKET-018: change_customer_reference succeeds for a NULL p_customer_reference, taking Oracle''s ELSE branch and recording an audit event mentioning "<empty>"'
);

SELECT ok(
    (SELECT count(*) FROM tt.event WHERE ticket_id = 906010
        AND (details_public LIKE '%customer reference changed to <empty>%' OR details_private LIKE '%customer reference changed to <empty>%')) >= 1,
    'S-TICKET-018: change_customer_reference(NULL) produced an audit event with the literal text "customer reference changed to <empty>" (Oracle''s own ''''=NULL-aware ELSE branch)'
);

SELECT lives_ok(
    $$CALL tt.ticket_interface_change_customer_reference(906010, '', 906002)$$,
    'S-TICKET-018: change_customer_reference succeeds for an empty string p_customer_reference -- Oracle collapses ''''=NULL for this parameter, so this must behave identically to the NULL case above'
);

SELECT ok(
    (SELECT count(*) FROM tt.event WHERE ticket_id = 906010
        AND (details_public LIKE '%customer reference changed to <empty>%' OR details_private LIKE '%customer reference changed to <empty>%')) >= 2,
    'S-TICKET-018: change_customer_reference(empty string) ALSO produced the "<empty>" audit text -- a translation that used a literal IS NOT NULL check (not NULLIF-normalized) would instead produce a trailing-blank text here, diverging from the NULL case; this is exactly the Pitfall-2 gap this pair of assertions exists to catch'
);

SELECT is(
    (SELECT customer_reference FROM tt.ticket WHERE id = 906010),
    '',
    'S-TICKET-018: change_customer_reference writes p_customer_reference to the column VERBATIM (unlike the audit text) -- the empty string call above must leave the stored value as '''', not NULL'
);

-------------------------------------------------------------------------------
-- change_label -- BOTH overloads, dispatched and asserted distinctly
-- (S-TICKET-019 2-arg, S-TICKET-020 3/4-arg)
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL tt.ticket_interface_change_label(906099996, 2)$$,
    'S-TICKET-019: the 2-arg change_label(p_ticket_id, p_label_id) overload is a bare UPDATE with no SELECT/EXCEPTION -- a nonexistent p_ticket_id matches zero rows and is silently NOT an error, in either engine'
);

SELECT lives_ok(
    $$CALL tt.ticket_interface_change_label(906011, 2)$$,
    'S-TICKET-019: the 2-arg change_label overload succeeds for a valid ticket, updating label_id with no audit event and no SELECT of any kind'
);

SELECT is(
    (SELECT label_id FROM tt.ticket WHERE id = 906011),
    2::bigint,
    'S-TICKET-019: the 2-arg change_label overload wrote label_id=2 directly onto ticket 906011'
);

SELECT ok(
    (SELECT count(*) FROM tt.event WHERE ticket_id = 906011) = 0,
    'S-TICKET-019: the 2-arg change_label overload wrote NO audit event -- proving it, not the 3/4-arg overload, was the one PostgreSQL dispatched for a 2-argument call'
);

SELECT throws_ok(
    $$CALL tt.ticket_interface_change_label(906099995, 2, 906002)$$,
    'P0002',
    NULL,
    'S-TICKET-020: the 3/4-arg change_label(p_ticket_id, p_label_id, p_contact_id, ...) overload propagates NO_DATA_FOUND unhandled for a nonexistent p_ticket_id (site #31) -- a DIFFERENT strictness profile than the 2-arg overload''s silent no-op above, proving PostgreSQL dispatched the OTHER signature for a 3-argument call'
);

SELECT lives_ok(
    $$CALL tt.ticket_interface_change_label(906012, 3, 906002)$$,
    'S-TICKET-020: the 3/4-arg change_label overload succeeds for a valid ticket, resolving the old label name (site #32) and the new label name (site #33), then delegating to the 2-arg overload to perform the actual UPDATE'
);

SELECT is(
    (SELECT label_id FROM tt.ticket WHERE id = 906012),
    3::bigint,
    'S-TICKET-020: the 3/4-arg change_label overload''s delegated UPDATE (via the 2-arg overload) wrote label_id=3 onto ticket 906012'
);

SELECT ok(
    (SELECT count(*) FROM tt.event WHERE ticket_id = 906012) >= 1,
    'S-TICKET-020: the 3/4-arg change_label overload wrote its OWN private "attribute change" audit event directly -- proving PostgreSQL resolved the RIGHT overload (the one with a contact_id/audit side effect) for this 3-argument call, distinct from the 2-arg overload''s silent no-audit behavior tested above'
);

-------------------------------------------------------------------------------
-- change_partner_reference (S-TICKET-022) -- Pitfall 2, paired '' vs NULL,
-- structurally identical to change_customer_reference (S-TICKET-018)
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL tt.ticket_interface_change_partner_reference(906010, NULL, 906002)$$,
    'S-TICKET-022: change_partner_reference succeeds for a NULL p_partner_reference, taking Oracle''s ELSE branch and recording an audit event mentioning "<empty>"'
);

SELECT lives_ok(
    $$CALL tt.ticket_interface_change_partner_reference(906010, '', 906002)$$,
    'S-TICKET-022: change_partner_reference succeeds for an empty string p_partner_reference -- Oracle collapses ''''=NULL for this parameter too, so this must produce the SAME "<empty>" audit outcome as the NULL case above (the second half of this package''s two Pitfall-2 pairs)'
);

SELECT is(
    (SELECT partner_reference FROM tt.ticket WHERE id = 906010),
    '',
    'S-TICKET-022: change_partner_reference writes p_partner_reference to the column verbatim -- the empty string call above must leave the stored value as an empty string, not NULL'
);

-------------------------------------------------------------------------------
-- change_service_host (S-TICKET-015, S-TICKET-016)
-------------------------------------------------------------------------------

SELECT throws_ok(
    $$CALL tt.ticket_interface_change_service_host(906099994, 906007, 906005, 906002)$$,
    'P0002',
    NULL,
    'S-TICKET-015: change_service_host propagates NO_DATA_FOUND unhandled for a nonexistent p_ticket_id (site #24, the one UN-guarded lookup in this routine)'
);

SELECT lives_ok(
    $$CALL tt.ticket_interface_change_service_host(906010, 906099993, 906099992, 906002)$$,
    'S-TICKET-016: change_service_host succeeds even when BOTH p_service_id and p_host_id are nonexistent -- each of the four label lookups (sites #25-#28) is individually guarded by its own local NO_DATA_FOUND handler, defaulting to NULL/''<empty>'''
);

SELECT ok(
    (SELECT mss_service_id FROM tt.ticket WHERE id = 906010) IS NOT NULL
        AND (SELECT host_id FROM tt.ticket WHERE id = 906010) IS NOT NULL,
    'S-TICKET-016: change_service_host still wrote the new (nonexistent, but caller-supplied) service_id/host_id onto the ticket -- the local handlers only guard the LABEL lookups, not the final UPDATE'
);

-- A-029 (S-TICKET-016 amended): the new-service label defaults to NULL on a miss and Oracle's
-- || concatenates NULL as '' -- the audit text ends in ' to <empty>' (old host, old service
-- label, new host '<empty>', no new service label). Observed live (differential scenario
-- tt__ticket_interface__change_owner_company, steps 07/08), where a literal port wrote NULL.
SELECT is(
    (SELECT details_public::text FROM tt.event
      WHERE ticket_id = 906010 AND type_id = 100003 AND details_public LIKE 'service changed from%'),
    'service changed from pilot-ti-host-old (Security Gateway [906006]) to <empty>',
    'S-TICKET-016: the audit text of change_service_host with a nonexistent service and host is Oracle''s concatenation with the NULL service label as empty string, not NULL'
);

-------------------------------------------------------------------------------
-- change_owner (S-TICKET-023) -- three mutually exclusive branches
-------------------------------------------------------------------------------

SELECT throws_ok(
    $$CALL tt.ticket_interface_change_owner(906010, 906099991, 906002)$$,
    'P0002',
    NULL,
    'S-TICKET-023: change_owner propagates NO_DATA_FOUND unhandled for a nonexistent p_owner_id (site #34, stop.contact lookup) when Zitadel names are not both supplied'
);

SELECT lives_ok(
    $$CALL tt.ticket_interface_change_owner(906010, NULL, 906002, NULL, NULL, NULL, 'Zitadel', 'Person')$$,
    'S-TICKET-023: change_owner succeeds when BOTH Zitadel first/last names are supplied -- this branch performs NO database lookup at all, so no SELECT INTO hazard is even reachable here'
);

SELECT lives_ok(
    $$CALL tt.ticket_interface_change_owner(906013, NULL, 906002)$$,
    'S-TICKET-023: change_owner succeeds in the ELSE branch (p_owner_id NULL, no Zitadel names) by resolving the company id from the ticket itself (site #36) rather than from a contact'
);

-------------------------------------------------------------------------------
-- change_company (S-TICKET-024)
-------------------------------------------------------------------------------

SELECT throws_ok(
    $$CALL tt.ticket_interface_change_company(906099990, 906023, 906002)$$,
    'P0002',
    NULL,
    'S-TICKET-024: change_company propagates NO_DATA_FOUND unhandled for a nonexistent p_ticket_id (site #37, the routine''s own old company/host lookup)');

SELECT lives_ok(
    $$CALL tt.ticket_interface_change_company(906013, 906099989, 906002)$$,
    'S-TICKET-024: change_company succeeds even for a nonexistent p_company_id -- site #40 is the ONE locally-handled lookup among the four, defaulting the new company''s short name to ''<empty>'' rather than raising'
);

SELECT is(
    (SELECT ROW(company_id, contact_id, mss_service_id, host_id) FROM tt.ticket WHERE id = 906013),
    -- A-007: mss_service_id/host_id are bigint in ddl/migrated (company_id/contact_id are
    -- numeric); an all-numeric ROW() makes is() raise "cannot compare dissimilar column
    -- types", aborting the transaction and every later assertion in this file.
    ROW(906099989::numeric, NULL::numeric, NULL::bigint, NULL::bigint)::record,
    'S-TICKET-024: change_company wrote the new company_id AND reset contact_id/mss_service_id/host_id to NULL -- a company change invalidates all of them, per the routine''s own logic'
);

-------------------------------------------------------------------------------
-- change_emergency (S-TICKET-025) -- the was_emergency ratchet
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL tt.ticket_interface_change_emergency(906014, 1, 906002)$$,
    'S-TICKET-025: change_emergency succeeds setting emergency=1 on ticket 906014, updating was_emergency via GREATEST(1, was_emergency)'
);

SELECT lives_ok(
    $$CALL tt.ticket_interface_change_emergency(906014, 0, 906002)$$,
    'S-TICKET-025: change_emergency succeeds setting emergency back to 0'
);

SELECT is(
    (SELECT ROW(emergency, was_emergency) FROM tt.ticket WHERE id = 906014),
    ROW(0::smallint, 1::smallint)::record,
    'S-TICKET-025: was_emergency stays 1 (the ratchet, GREATEST(p_emergency, was_emergency)) even after emergency itself was reset to 0 -- by design, this value can never go back down once set'
);

-------------------------------------------------------------------------------
-- change_always_visible (S-TICKET-026)
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL tt.ticket_interface_change_always_visible(906014, 1, 906002)$$,
    'S-TICKET-026: change_always_visible succeeds -- the simplest routine in the change_* family alongside change_label''s 2-arg overload, no SELECT INTO and no EXCEPTION block'
);

SELECT is(
    (SELECT always_visible FROM tt.ticket WHERE id = 906014),
    1::smallint,
    'S-TICKET-026: change_always_visible wrote always_visible=1 onto the ticket'
);

-------------------------------------------------------------------------------
-- change_notification (S-TICKET-027) -- correctly handled already, no divergence
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL tt.ticket_interface_change_notification(906014, NULL, NULL, 906002)$$,
    'S-TICKET-027: change_notification succeeds when BOTH text parameters are NULL -- the prefix is only concatenated inside an IS NOT NULL guard, so the local variable stays NULL (not NULL||''x''), correctly avoiding the empty string vs NULL divergence Pitfall 2 warns about'
);

-- A-028 (S-TICKET-027 amended): in Oracle a VARCHAR2 argument of '' IS NULL, so the
-- IS NOT NULL guard is FALSE for '' and -- with a non-NULL private text -- the event is
-- HIDDEN by add_status_change_event (public_event = 0, details_public NULL). Observed live
-- (differential scenario tt__ticket_interface__change_attributes, step 17).
SELECT lives_ok(
    $$CALL tt.ticket_interface_change_notification(906014, '', 'a101 private text', 906002)$$,
    'S-TICKET-027: change_notification succeeds when p_change_text_public is an empty string and the private text is set -- Oracle treats the VARCHAR2 argument '''' as NULL, so the guard is FALSE and the public text stays NULL (amended: the original description claimed the prefix IS applied)'
);

SELECT is(
    (SELECT public_event FROM tt.event WHERE ticket_id = 906014
      AND details_private = 'Notification settings changed' || chr(10) || 'a101 private text'),
    0::smallint,
    'S-TICKET-027: the event written for an empty-string public text and a non-NULL private text is HIDDEN (public_event = 0), as Oracle''s ''''-is-NULL semantics make add_status_change_event do'
);

SELECT is(
    (SELECT details_public::text FROM tt.event WHERE ticket_id = 906014
      AND details_private = 'Notification settings changed' || chr(10) || 'a101 private text'),
    NULL::text,
    'S-TICKET-027: details_public of that event is NULL -- the prefix was NOT prepended to the empty string'
);

-------------------------------------------------------------------------------
-- change_summary (S-TICKET-028, S-TICKET-029)
-------------------------------------------------------------------------------

SELECT throws_ok(
    $$CALL tt.ticket_interface_change_summary(906099988, 'priv', 'pub', 906002)$$,
    'P0002',
    NULL,
    'S-TICKET-028: change_summary propagates NO_DATA_FOUND unhandled for a nonexistent p_ticket_id (site #41, the routine''s own old-summary lookup)');

SELECT lives_ok(
    $$CALL tt.ticket_interface_change_summary(906014, 'new private summary', 'new public summary', 906002)$$,
    'S-TICKET-029: change_summary succeeds updating both summaries, resetting summary_relevant_events_count only on the PUBLIC path (a deliberate asymmetry, not an omission)'
);

SELECT is(
    (SELECT summary_relevant_events_count FROM tt.ticket WHERE id = 906014),
    0::bigint,
    'S-TICKET-029: summary_relevant_events_count was reset to 0 because the PUBLIC summary changed'
);

-- A-028 (S-TICKET-029 amended): a VARCHAR2 argument of '' IS NULL in Oracle. The first
-- call below therefore clears both summaries (the '<empty>' path); the second is a complete
-- no-op (both old and new NULL). Observed live (differential scenario
-- tt__ticket_interface__change_attributes, step 22), where a literal port wrote two
-- 'changed to:\n' events and stored '' instead.
SELECT lives_ok(
    $$CALL tt.ticket_interface_change_summary(906014, '', '', 906002)$$,
    'S-TICKET-029: change_summary succeeds with empty-string summaries -- Oracle sees NULL/NULL against the stored texts, i.e. a change to <empty> on both paths'
);

SELECT is(
    (SELECT summary_private::text FROM tt.ticket WHERE id = 906014),
    NULL::text,
    'S-TICKET-029: an empty-string p_summary_private is stored as NULL (Oracle cannot store an empty VARCHAR2), not as the empty string'
);

SELECT is(
    (SELECT summary_public::text FROM tt.ticket WHERE id = 906014),
    NULL::text,
    'S-TICKET-029: an empty-string p_summary_public is stored as NULL, not as the empty string'
);

SELECT is(
    (SELECT count(*) FROM tt.event WHERE ticket_id = 906014
      AND details_private = 'private summary changed to:' || chr(10) || '<empty>'),
    1::bigint,
    'S-TICKET-029: the private-summary audit text for an empty-string input is the NVL fallback <empty>, exactly as for NULL'
);

SELECT lives_ok(
    $$CALL tt.ticket_interface_change_summary(906014, '', '', 906002)$$,
    'S-TICKET-029: change_summary with empty strings against NULL summaries succeeds as a no-op (both NULL -> the NOT (old IS NULL AND new IS NULL) guard is FALSE in Oracle)'
);

SELECT is(
    (SELECT count(*) FROM tt.event WHERE ticket_id = 906014
      AND details_private LIKE 'private summary changed to:%'),
    2::bigint,
    'S-TICKET-029: exactly two private-summary audit events exist (new private summary, <empty>) -- the second empty-string call wrote none'
);

SELECT is(
    (SELECT count(*) FROM tt.event WHERE ticket_id = 906014
      AND details_public LIKE 'public summary changed to:%'),
    2::bigint,
    'S-TICKET-029: exactly two public-summary audit events exist (new public summary, <empty>) -- the second empty-string call wrote none'
);

-------------------------------------------------------------------------------
-- change_type (S-TICKET-030, S-TICKET-031)
-------------------------------------------------------------------------------

SELECT throws_ok(
    $test3$
    DO $do3$
    DECLARE v_event_id numeric;
    BEGIN
        CALL tt.ticket_interface_change_type(v_event_id, 906099987, 2, 906002);
    END
    $do3$;
    $test3$,
    'P0002',
    NULL,
    'S-TICKET-030: change_type propagates NO_DATA_FOUND unhandled for a nonexistent p_ticket_id (site #42, company id lookup)');

SELECT lives_ok(
    $test4$
    DO $do4$
    DECLARE v_event_id numeric;
    BEGIN
        CALL tt.ticket_interface_change_type(v_event_id, 906014, 2, 906002);
        IF v_event_id IS NULL THEN
            RAISE EXCEPTION 'change_type left OUT p_event_id NULL for a valid ticket';
        END IF;
    END
    $do4$;
    $test4$,
    'S-TICKET-031: change_type resolves its OUT p_event_id via event_sequence.CurrVal immediately after its own INSERT -- a non-NULL result proves the NextVal-then-CurrVal pairing held within this one routine'
);

SELECT is(
    (SELECT type_id FROM tt.ticket WHERE id = 906014),
    2::numeric,
    'S-TICKET-030: change_type wrote the new type_id (2, "change") onto ticket 906014'
);

-------------------------------------------------------------------------------
-- change_service_component (S-TICKET-031, S-TICKET-032)
-------------------------------------------------------------------------------

SELECT throws_ok(
    $test5$
    DO $do5$
    DECLARE v_event_id numeric;
    BEGIN
        CALL tt.ticket_interface_change_service_component(v_event_id, 906099986, 1, 906002);
    END
    $do5$;
    $test5$,
    'P0002',
    NULL,
    'S-TICKET-032: change_service_component propagates NO_DATA_FOUND unhandled for a nonexistent p_ticket_id (site #46, the one UN-guarded lookup in this routine)');

SELECT lives_ok(
    $test6$
    DO $do6$
    DECLARE v_event_id numeric;
    BEGIN
        CALL tt.ticket_interface_change_service_component(v_event_id, 906013, 906099985, 906002);
    END
    $do6$;
    $test6$,
    'S-TICKET-032: change_service_component succeeds even for a nonexistent p_service_component_id -- the old/new component name+code lookups (sites #47-#50) are each locally guarded, defaulting to ''''/''<empty>'''
);

-------------------------------------------------------------------------------
-- rate_ticket (S-TICKET-039, S-TICKET-043 business rule)
-------------------------------------------------------------------------------

SELECT lives_ok(
    $test7$
    DO $do7$
    DECLARE v_rating_id numeric;
    BEGIN
        CALL tt.ticket_interface_rate_ticket(v_rating_id, 906015, 906016, 906002, 1, 2);
        IF v_rating_id IS NULL THEN
            RAISE EXCEPTION 'rate_ticket left OUT p_rating_id NULL';
        END IF;
    END
    $do7$;
    $test7$,
    'S-TICKET-039: rate_ticket pulls a non-NULL p_rating_id from ticketrating_seq.NextVal (site #58) and sets engineer_ticket_rating_id -- an ENGINEER rating (p_by_engineer=1) never triggers a status change regardless of value'
);

SELECT is(
    (SELECT status_id FROM tt.ticket WHERE id = 906015),
    2::numeric,
    'S-TICKET-043: rate_ticket left ticket 906015''s status untouched (still 2, open) after a BAD engineer rating -- only a bad CUSTOMER rating (p_by_engineer=0 AND value<3) forces the ticket to hot'
);

-------------------------------------------------------------------------------
-- add_docs_page / remove_docs_page (S-TICKET-040, S-TICKET-041)
-------------------------------------------------------------------------------

SELECT lives_ok(
    $test8$
    DO $do8$
    DECLARE v_page_id numeric;
    BEGIN
        CALL tt.ticket_interface_add_docs_page(v_page_id, 906017, 700010, 1, 'Pilot Docs Page', 0, 906002);
    END
    $do8$;
    $test8$,
    'S-TICKET-040: add_docs_page succeeds, pulling p_ticket_docs_page_id from ticketdocspage_seq.NextVal (site #59) -- its whole-body WHEN OTHERS would swallow a failure here rather than raise, but this call is expected to succeed outright'
);

SELECT lives_ok(
    $$CALL tt.ticket_interface_remove_docs_page(906099984, 'irrelevant title', 906002)$$,
    'S-TICKET-041: remove_docs_page succeeds (silently) for a nonexistent p_ticket_docs_page_id -- its WHEN NO_DATA_FOUND THEN NULL arm (site #60) means the DELETE and history event simply never run, not an error'
);

-------------------------------------------------------------------------------
-- add_related_ticket / remove_related_ticket (S-TICKET-042, S-TICKET-043)
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL tt.ticket_interface_add_related_ticket(906018, 906018, 906002)$$,
    'S-TICKET-042: add_related_ticket succeeds (logs and RETURNs, not an exception) when p_ticket_id equals p_related_ticket_id -- the v_counter != 2 check catches this as a normal early exit'
);

SELECT lives_ok(
    $$CALL tt.ticket_interface_add_related_ticket(906018, 906019, 906002)$$,
    'S-TICKET-042: add_related_ticket succeeds linking two distinct, existing tickets'
);

SELECT ok(
    (SELECT count(*) FROM tt.ticket2related_ticket WHERE ticket_id = 906018 AND related_ticket_id = 906019) >= 1,
    'S-TICKET-042: add_related_ticket inserted the ticket2related_ticket relation row for the two distinct tickets'
);

SELECT lives_ok(
    $$CALL tt.ticket_interface_remove_related_ticket(906099983, 906099982, 906002)$$,
    'S-TICKET-043: remove_related_ticket succeeds (silent no-op, not an exception) when the relation does not exist at all (v_counter=0, a COUNT aggregate, no STRICT concern)'
);

-------------------------------------------------------------------------------
-- add_related_file / remove_related_file (S-TICKET-044, S-TICKET-045)
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL tt.ticket_interface_add_related_file(906020, 906021, 906002)$$,
    'S-TICKET-044: add_related_file succeeds (swallowed, not propagated) for a cross-company file/ticket pairing -- the routine''s OWN inline comment states this NO_DATA_FOUND is a DELIBERATE same-company authorization guard, not incidental'
);

SELECT ok(
    (SELECT count(*) FROM osag.plog_stub_log WHERE message LIKE '%does not exits or they belong to different companies%') >= 1,
    'S-TICKET-044: add_related_file logged the specific "does not exits or they belong to different companies" message for the cross-company mismatch above'
);

SELECT lives_ok(
    $$CALL tt.ticket_interface_remove_related_file(906020, 906028, 906002)$$,
    'S-TICKET-045: remove_related_file succeeds removing an EXISTING same-company relation (906020/906028) -- file 906028 is released to the ticket''s company 906001, which the corrected same-company guard (S-TICKET-060) requires'
);

SELECT ok(
    (SELECT count(*) FROM tt.ticket2mc_file WHERE ticket_id = 906020 AND mc_file_id = 906028) = 0,
    'S-TICKET-045: remove_related_file deleted the ticket2mc_file relation row'
);

-------------------------------------------------------------------------------
-- classify_request (S-TICKET-047, S-TICKET-050)
-------------------------------------------------------------------------------

SELECT lives_ok(
    $$CALL tt.ticket_interface_classify_request(906024, NULL, 906002)$$,
    'S-TICKET-050: classify_request succeeds (no error raised) for a NULL p_classification -- it silently defaults to 2 (standard) rather than rejecting the input, contradicting the doc comment''s implication that only 1/2/3 are valid'
);

SELECT is(
    (SELECT classification FROM tt.ticket_request_classification WHERE ticket_id = 906024),
    2::smallint,
    'S-TICKET-050: classify_request(NULL) upserted a classification row with value 2 (standard), the silent default for any value outside {1,2,3}'
);

-------------------------------------------------------------------------------
-- clear_todo_list (S-TICKET-048) -- path-dependent SELECT INTO
-------------------------------------------------------------------------------

SELECT throws_ok(
    $$CALL tt.ticket_interface_clear_todo_list(906099981, 906002)$$,
    'P0002',
    NULL,
    'S-TICKET-048: clear_todo_list propagates NO_DATA_FOUND unhandled for a nonexistent p_ticket_id when p_add_history_event=1 (the default) -- site #68''s tt.ticket lookup runs unconditionally on this path');

SELECT lives_ok(
    $$CALL tt.ticket_interface_clear_todo_list(906099980, 906002, 0)$$,
    'S-TICKET-048: clear_todo_list succeeds EVEN FOR a nonexistent p_ticket_id when p_add_history_event=0 -- site #68''s SELECT INTO never executes in that mode, a real path-dependent behavior the spec names explicitly'
);

SELECT lives_ok(
    $$CALL tt.ticket_interface_clear_todo_list(906025, 906002)$$,
    'S-TICKET-048: clear_todo_list succeeds for the real ticket 906025, deleting its pre-existing todo item unconditionally'
);

SELECT is(
    (SELECT count(*) FROM tt.todo_item WHERE ticket_id = 906025),
    0::bigint,
    'S-TICKET-048: clear_todo_list removed ALL todo_item rows for ticket 906025 (it had one pre-existing row, fixture id 906029)'
);

-------------------------------------------------------------------------------
-- add_todo_item (S-TICKET-049)
-------------------------------------------------------------------------------

SELECT lives_ok(
    $test9$
    DO $do9$
    DECLARE v_todo_item_id numeric;
    BEGIN
        CALL tt.ticket_interface_add_todo_item(v_todo_item_id, 906026, 1, 'pilot public todo step', 1, 906002, 1);
        IF v_todo_item_id IS NULL THEN
            RAISE EXCEPTION 'add_todo_item left OUT p_todo_item_id NULL';
        END IF;
    END
    $do9$;
    $test9$,
    'S-TICKET-049: add_todo_item pulls a non-NULL p_todo_item_id from todoitem_seq.NextVal (site #69) and, for a PUBLIC item, increments steps_total -- it deliberately writes NO history event of its own, per its own doc comment'
);

SELECT is(
    (SELECT steps_total FROM tt.ticket WHERE id = 906026),
    1::bigint,
    'S-TICKET-049: add_todo_item incremented steps_total to 1 for the new PUBLIC todo item'
);

-------------------------------------------------------------------------------
-- update_todo_item_status (S-TICKET-050, S-TICKET-054)
-------------------------------------------------------------------------------

SELECT throws_ok(
    $$CALL tt.ticket_interface_update_todo_item_status(906027, 999, 2, 906002)$$,
    'P0002',
    NULL,
    'S-TICKET-050: update_todo_item_status propagates NO_DATA_FOUND unhandled for a nonexistent (ticket_id, seq_no) pair (site #70, the LEFT JOIN to todo_item_status still requires a matching tt.todo_item row)'
);

SELECT lives_ok(
    $$CALL tt.ticket_interface_update_todo_item_status(906027, 1, 2, 906002)$$,
    'S-TICKET-054: update_todo_item_status succeeds updating the real (906027, seq_no=1) todo item to status 2 (DONE)'
);

SELECT is(
    (SELECT todo_item_status_id FROM tt.todo_item WHERE ticket_id = 906027 AND seq_no = 1),
    2::bigint,
    'S-TICKET-054: update_todo_item_status wrote todo_item_status_id=2 onto the real todo item'
);

-------------------------------------------------------------------------------
-- replace_id_placeholders (S-TICKET-037) -- pure string substitution FUNCTION
-------------------------------------------------------------------------------

SELECT lives_ok(
    $test10$
    DO $do10$
    DECLARE v_result text;
    BEGIN
        SELECT tt.ticket_interface_replace_id_placeholders('Ticket ##ticket_id## has event ##event_id##', 906010, 905011) INTO v_result;
        IF v_result <> 'Ticket 906010 has event 905011' THEN
            RAISE EXCEPTION 'replace_id_placeholders did not substitute both placeholders correctly, got: %', v_result;
        END IF;
    END
    $do10$;
    $test10$,
    'S-TICKET-037: replace_id_placeholders substitutes both ##ticket_id## and ##event_id## placeholders with the caller-supplied numeric ids -- pure string substitution, no SELECT, no call to any other routine, no EXCEPTION block'
);

-- TEST-AMENDMENTS.md A-024: NULL-id semantics (S-TICKET-037 amended 2026-10-21 from the
-- live Oracle run). Oracle's REPLACE with a NULL replacement string removes the placeholder
-- and keeps the rest of the text; a text without placeholders is returned verbatim.
SELECT is(
    tt.ticket_interface_replace_id_placeholders('e=##event_id## t=##ticket_id##', 954080, NULL),
    'e= t=954080',
    'S-TICKET-037: a NULL p_event_id removes the ##event_id## placeholder and leaves the rest of the text intact (Oracle REPLACE with a NULL replacement deletes the occurrences)'
);

SELECT is(
    tt.ticket_interface_replace_id_placeholders('e=##event_id## t=##ticket_id##', NULL, 42),
    'e=42 t=',
    'S-TICKET-037: a NULL p_ticket_id removes the ##ticket_id## placeholder and leaves the ##event_id## substitution intact'
);

SELECT is(
    tt.ticket_interface_replace_id_placeholders('nothing to replace', NULL, NULL),
    'nothing to replace',
    'S-TICKET-037: a text without placeholders is returned verbatim even when both ids are NULL (never collapsed to NULL)'
);

SELECT * FROM finish();
ROLLBACK;
