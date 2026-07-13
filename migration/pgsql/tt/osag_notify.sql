-- migration/pgsql/tt/osag_notify.sql
--
-- Translation of TT.OSAG_NOTIFY (spec: migration/spec/tt.osag_notify.md; Oracle body:
-- ddl/src/pkgb/tt_osag_notify.sql, 1844 lines). The 6 public names are copied verbatim
-- from migration/mapping/name-map.csv's 6 OSAG_NOTIFY rows; the 13 private routines have
-- no name-map rows (that SSOT covers public routines only) and follow the double-
-- underscore private-routine convention the spec's "Private routines -- naming
-- convention" section declares (tt.osag_notify__<name>, REVOKE ALL ... FROM PUBLIC) --
-- the same convention 02-09 already used for tt.util__despam_ticket.
--
-- Oracle's usage-audit call (XCUT-06): all 6 plog.AuditUsage(...) call sites DELETED,
-- not ported (Oracle body lines 335, 784, 861, 901, 953, 984). See osag_notify.FINDINGS.md.
--
-- THIS IS THE PILOT'S SELECT INTO PACKAGE: 30 sites, each carrying the verdict the spec's
-- `### SELECT INTO strictness` table assigned it, and each annotated with its clause ID
-- (-- S-NOTIFY-0NN, site #N) so verdict and code sit together. NO blanket answer was
-- applied in either direction: 29 sites are STRICT (their zero-row case is reachable and
-- Oracle raises NO_DATA_FOUND there); site #11 is deliberately NOT strict (a COUNT(*)
-- aggregate always returns exactly one row -- STRICT there would be noise, and the spec
-- calls it "the package's one legitimate no-STRICT concern site").
--
-- Handler fidelity: every one of the 11 Oracle WHEN OTHERS handlers SWALLOWS (logs, or
-- does nothing) -- there is not one RAISE anywhere in the 1844-line body. Reproduced
-- exactly. The consequence, spelled out in S-NOTIFY-001: event_notify NEVER raises to its
-- caller, and send_test_notification / add_notification_event ALWAYS do (they have no
-- handler at all). Both extremes are deliberate Oracle contracts, not accidents.
--
-- The pilot's one TOO_MANY_ROWS handler lives in __get_isp_link_id_for_host_id (site #22,
-- S-NOTIFY-031). It gets INTO STRICT plus all three explicit arms -- without STRICT,
-- PL/pgSQL silently takes the first row and Oracle's own handler becomes dead code.
--
-- OSAG.OSAG_MSG (send_sms / send_mail) is NOT part of the pilot and has no translation
-- yet (name-map rows osag.osag_msg_send_sms / osag.osag_msg_send_mail exist; the bodies
-- do not). PL/pgSQL does not resolve CALL targets at CREATE time, so this file loads
-- regardless; the dispatch paths that reach those CALLs are documented in
-- osag_notify.FINDINGS.md. The Oracle SMTP-header collection type (OSAG_MSG.smtp_headers_t)
-- is likewise deferred with its owning package -- see FINDINGS.
--
-- tt.ticket_interface_change_notification (called by delete_ticket_notifications,
-- S-NOTIFY-021) is a TT cycle-group sibling landing in plan 02-11/02-12, same wave.
-- Same "loads regardless, only running it needs the sibling" property as 02-09's tt.util.

-- =====================================================================================
-- PRIVATE routines first (PL/pgSQL has no forward declarations; Oracle's package body
-- opens with a forward-declaration block precisely because it defines them last).
-- =====================================================================================

-- ------------------------------------------------------------------------------------
-- __email_signature (S-NOTIFY-037): pure string builder, zero DB access.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION tt.osag_notify__email_signature()
RETURNS varchar
LANGUAGE plpgsql
IMMUTABLE
AS $fn$
BEGIN
    RETURN chr(10) ||
           '-- ' || chr(10) ||
           'Open Systems Mission Control' || chr(10) || chr(10) ||
           'E. support@open.ch' || chr(10) ||
           'T. +800 00 724 000' || chr(10) ||
           '   +41 58 100 11 11' || chr(10) ||
           '   1-800-724-2407 (US toll free) ' || chr(10) ||
           'W. https://control.open.ch';
END;
$fn$;
REVOKE ALL ON FUNCTION tt.osag_notify__email_signature() FROM PUBLIC;

-- ------------------------------------------------------------------------------------
-- __email_footer (S-NOTIFY-037): pure string builder. p_ticket_id is accepted and
-- ignored, exactly as in Oracle (ddl/src/pkgb/tt_osag_notify.sql:1817-1826 -- the
-- parameter is declared but never referenced in the body).
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION tt.osag_notify__email_footer(p_ticket_id numeric)
RETURNS varchar
LANGUAGE plpgsql
IMMUTABLE
AS $fn$
BEGIN
    RETURN 'Notification settings can be changed at: https://control.open.ch' || chr(10) ||
           chr(10) ||
           'Best regards,' || chr(10) ||
           'Mission Control' || chr(10) ||
           tt.osag_notify__email_signature();
END;
$fn$;
REVOKE ALL ON FUNCTION tt.osag_notify__email_footer(numeric) FROM PUBLIC;

-- ------------------------------------------------------------------------------------
-- __format_customer_reference (S-NOTIFY-035): the clearest Pitfall-2 ('' / NULL) hazard
-- in the package. Oracle's `p_customer_reference IS NULL` ALSO catches a caller-supplied
-- '' (Oracle collapses '' to NULL); PostgreSQL's does not, and would emit ' []'.
-- NULLIF(p_customer_reference, '') reproduces Oracle's collapse explicitly at the
-- boundary. tt.ticket.customer_reference has no constraint forbidding '', so this is a
-- live divergence, not a theoretical one.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION tt.osag_notify__format_customer_reference(p_customer_reference varchar)
RETURNS varchar
LANGUAGE plpgsql
IMMUTABLE
AS $fn$
DECLARE
    v_ref varchar := NULLIF(p_customer_reference, '');
BEGIN
    IF v_ref IS NULL THEN
        RETURN '';
    ELSE
        RETURN ' [' || v_ref || ']';
    END IF;
END;
$fn$;
REVOKE ALL ON FUNCTION tt.osag_notify__format_customer_reference(varchar) FROM PUBLIC;

-- ------------------------------------------------------------------------------------
-- __get_notification_type_name (S-NOTIFY-036)
-- SELECT INTO site #30 (ddl/src/pkgb/tt_osag_notify.sql:1810): PK lookup on
-- tt.event_notification_type. Zero rows reachable, TOO_MANY_ROWS structurally impossible.
-- Oracle has NO local handler -- the NO_DATA_FOUND propagates to whichever caller has one
-- (both call sites are inside delete_ticket_notifications' own WHEN OTHERS, S-NOTIFY-021).
-- Verdict: STRICT + handler (indirect) -- i.e. STRICT here, NO handler here.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION tt.osag_notify__get_notification_type_name(p_event_notification_type_id numeric)
RETURNS varchar
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_event_notification_type_name tt.event_notification_type.name%TYPE;
BEGIN
    -- S-NOTIFY-036 (site #30): STRICT, no local handler (Oracle has none).
    SELECT name INTO STRICT v_event_notification_type_name
    FROM tt.event_notification_type
    WHERE id = p_event_notification_type_id;

    RETURN v_event_notification_type_name;
END;
$fn$;
REVOKE ALL ON FUNCTION tt.osag_notify__get_notification_type_name(numeric) FROM PUBLIC;

-- ------------------------------------------------------------------------------------
-- __compose_local_contact_message (S-NOTIFY-037-adjacent): pure string builder, no
-- SELECT INTO. TO_CHAR(SYSTIMESTAMP AT TIME ZONE 'EUROPE/ZURICH', 'TZD') has no direct
-- PostgreSQL equivalent (PostgreSQL exposes the abbreviation via to_char(..., 'TZ') on a
-- timestamptz); used here, same observable shape (CET/CEST).
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION tt.osag_notify__compose_local_contact_message(
    p_ticket_id numeric,
    p_event_type_name varchar,
    p_host_name varchar,
    p_eventdate timestamp)
RETURNS varchar
LANGUAGE plpgsql
AS $fn$
BEGIN
    RETURN 'This is an automatically generated email to inform you that the following event has occurred:' ||
           chr(10) || chr(10) ||
           'Ticket:   ' || p_ticket_id || chr(10) ||
           'Event:    ' || p_event_type_name || chr(10) ||
           'Host:     ' || p_host_name || chr(10) ||
           'Date:     ' || to_char(p_eventdate, 'DD.MM.YYYY HH24:MI') || ' ' ||
           to_char(clock_timestamp() AT TIME ZONE 'Europe/Zurich', 'TZ') || chr(10) || chr(10) ||
           'If you have access to the Open Systems Ticket System, you can view' || chr(10) ||
           'the complete ticket using the following link:' || chr(10) || chr(10) ||
           'https://control.open.ch/mc/ticket/' || p_ticket_id || chr(10) || chr(10) ||
           tt.osag_notify__email_signature();
END;
$fn$;
REVOKE ALL ON FUNCTION tt.osag_notify__compose_local_contact_message(numeric, varchar, varchar, timestamp) FROM PUBLIC;

-- ------------------------------------------------------------------------------------
-- __compose_email_msg (S-NOTIFY-026, S-NOTIFY-027)
-- SELECT INTO sites #14 (line 1150) and #15 (line 1155). Both PK lookups; zero rows
-- reachable at both (bad p_event_type_id; orphaned template id). Oracle has NO exception
-- block in this routine at all -- so the SAME NO_DATA_FOUND is swallowed when reached via
-- event_notify (outer WHEN OTHERS) but propagates fully out of send_test_notification.
-- Verdict for both: STRICT, and NO handler here (the caller's net decides the outcome).
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.osag_notify__compose_email_msg(
    INOUT p_message_subject varchar,
    INOUT p_message varchar,
    p_ticket_id numeric,
    p_ticket_subject varchar,
    p_ticket_type_name varchar,
    p_customer_reference varchar,
    p_host_name varchar,
    p_event_type_id numeric,
    p_event_type_name varchar,
    p_event_subject varchar,
    p_eventdate timestamp,
    p_status_valid_until_date timestamp,
    p_details_public varchar,
    p_details_private varchar,
    p_emergency_flag tt.ticket.emergency%TYPE,
    p_company_id numeric)
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_subject_prefix varchar;
    v_message varchar;
    v_subject_template varchar;
    v_message_template varchar;
    v_email_msg_template_id numeric;
    v_details varchar;
    v_emergency_text varchar := '';
    v_tz varchar := to_char(clock_timestamp() AT TIME ZONE 'Europe/Zurich', 'TZ');
BEGIN
    -- S-NOTIFY-026 (site #14): STRICT, no local handler (Oracle has none).
    SELECT email_message_template_id INTO STRICT v_email_msg_template_id
    FROM tt.event_type et
    WHERE et.id = p_event_type_id;

    -- S-NOTIFY-026 (site #15): STRICT, no local handler (Oracle has none).
    SELECT subject_template, message_template INTO STRICT v_subject_template, v_message_template
    FROM tt.event_type_message etm
    WHERE etm.id = v_email_msg_template_id;

    IF p_emergency_flag = 1 THEN
        v_emergency_text := 'EMERGENCY: ';
    END IF;

    -- S-NOTIFY-027: pure REPLACE() placeholder substitution from here on.
    v_subject_prefix := '[OS-' || p_ticket_id || ']' || tt.osag_notify__format_customer_reference(p_customer_reference);
    v_subject_template := replace(v_subject_template, '$#TICKET_SUBJECT#$', coalesce(p_ticket_subject, ''));
    v_subject_template := replace(v_subject_template, '$#EVENT_TYPE_NAME#$', coalesce(p_event_type_name, ''));
    v_subject_template := replace(v_subject_template, '$#TICKET_TYPE#$', coalesce(p_ticket_type_name, ''));
    v_subject_template := replace(v_subject_template, '$#EMERGENCY#$', v_emergency_text);

    IF (p_host_name IS NOT NULL AND p_host_name != 'unspecified') THEN
        v_subject_template := replace(v_subject_template, '$#HOST_NAME#$', p_host_name);
    ELSE
        v_subject_template := replace(v_subject_template, '$#HOST_NAME#$', '<unspecified service>');
    END IF;

    v_subject_template := replace(v_subject_template, '$#STATUS_VALID_UNTIL#$',
        coalesce(to_char(p_status_valid_until_date, 'DD.MM.YYYY HH24:MI'), '') || ' ' || v_tz);

    p_message_subject := v_subject_prefix || ' ' || v_subject_template;

    v_message_template := replace(v_message_template, '$#EVENT_DATE#$',
        coalesce(to_char(p_eventdate, 'DD.MM.YYYY HH24:MI'), '') || ' ' || v_tz);
    v_message_template := replace(v_message_template, '$#EVENT_TYPE_NAME#$', coalesce(p_event_type_name, ''));
    v_message_template := replace(v_message_template, '$#TICKET_SUBJECT#$', coalesce(p_ticket_subject, ''));
    v_message_template := replace(v_message_template, '$#EMERGENCY#$', v_emergency_text);

    IF (p_host_name IS NOT NULL AND p_host_name != 'unspecified') THEN
        v_message_template := replace(v_message_template, '$#HOST_NAME#$', p_host_name);
    ELSE
        v_message_template := replace(v_message_template, '$#HOST_NAME#$', '<unspecified service>');
    END IF;

    v_message_template := replace(v_message_template, '$#TICKET_ID#$', coalesce(p_ticket_id::text, ''));
    v_message_template := replace(v_message_template, '$#STATUS_VALID_UNTIL#$',
        coalesce(to_char(p_status_valid_until_date, 'DD.MM.YYYY HH24:MI'), '') || ' ' || v_tz);
    v_message_template := replace(v_message_template, '$#COMPANY_ID#$', coalesce(p_company_id::text, ''));

    -- Oracle's SUBSTR(x, 1, INSTR(x, CHR(10)) - 1) returns NULL when x is NULL and '' when
    -- CHR(10) is absent (INSTR -> 0, so SUBSTR(x,1,-1) -> ''). substr(x, 1, strpos(x,
    -- chr(10)) - 1) has the identical shape in PostgreSQL (strpos -> 0, substr with a
    -- negative length -> ''), so this ports 1:1; coalesce guards the NULL case for ||.
    v_message_template := replace(v_message_template, '$#PUBLIC_DETAILS_FIRST_LINE#$',
        coalesce(substr(p_details_public, 1, strpos(coalesce(p_details_public, ''), chr(10)) - 1), ''));

    IF (p_event_type_id = 50008) THEN
        v_message_template := substr(replace(v_message_template, '$#QUESTION#$', coalesce(p_details_public, '')), 1, 29000);
    END IF;

    IF (p_event_type_id = 30012) THEN
        v_details := substr(p_details_public, 1, 2000);
        v_message_template := replace(v_message_template, '$#PUBLIC_DETAILS#$', coalesce(v_details, ''));
    ELSIF (p_event_type_id = 50004) THEN
        v_details := substr(p_details_private, 1, 2000);
        v_message_template := replace(v_message_template, '$#PRIVATE_DETAILS#$', coalesce(v_details, ''));
    END IF;

    -- Oracle: v_message := v_message || v_message_template || ... with v_message still
    -- NULL -- Oracle's NULL||'x' = 'x' seeds it. PL/pgSQL's NULL||'x' = NULL would wipe
    -- the whole body (Pitfall 2), so the accumulator is seeded from '' explicitly.
    v_message := '' || v_message_template || chr(10) || chr(10) || tt.osag_notify__email_footer(p_ticket_id);

    p_message := v_message;
END;
$fn$;
REVOKE ALL ON PROCEDURE tt.osag_notify__compose_email_msg(varchar, varchar, numeric, varchar, varchar, varchar, varchar, numeric, varchar, varchar, timestamp, timestamp, varchar, varchar, smallint, numeric) FROM PUBLIC;

-- ------------------------------------------------------------------------------------
-- __compose_sms_msg (S-NOTIFY-028)
-- SELECT INTO sites #16 (line 1249) and #17 (line 1254): the SMS mirror of #14/#15. Same
-- PK-lookup profile, same "no local handler in Oracle" -- three callers, three different
-- safety nets (event_notify swallows; send_test_notification propagates;
-- notify_local_contacts' own routine-level NO_DATA_FOUND handler catches it).
-- Verdict for both: STRICT, no handler here.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION tt.osag_notify__compose_sms_msg(
    p_ticket_id numeric,
    p_host_name varchar,
    p_event_type_id numeric,
    p_event_type_name varchar,
    p_eventdate timestamp,
    p_status_valid_until_date timestamp,
    p_ticket_subject varchar,
    p_emergency_flag tt.ticket.emergency%TYPE)
RETURNS varchar
LANGUAGE plpgsql
AS $fn$
DECLARE
    s_sms_msg_size CONSTANT numeric := 160;
    v_message_template varchar;
    v_sms_msg_template_id numeric;
    v_max_ticket_subject_size numeric;
    v_ticket_subject tt.ticket.subject%TYPE;
    v_emergency_text varchar := '';
    v_tz varchar := to_char(clock_timestamp() AT TIME ZONE 'Europe/Zurich', 'TZ');
BEGIN
    -- S-NOTIFY-028 (site #16): STRICT, no local handler (Oracle has none).
    SELECT sms_message_template_id INTO STRICT v_sms_msg_template_id
    FROM tt.event_type et
    WHERE et.id = p_event_type_id;

    -- S-NOTIFY-028 (site #17): STRICT, no local handler (Oracle has none).
    SELECT message_template INTO STRICT v_message_template
    FROM tt.event_type_message etm
    WHERE etm.id = v_sms_msg_template_id;

    IF p_emergency_flag = 1 THEN
        v_emergency_text := 'EM: ';
    END IF;

    IF (p_host_name IS NOT NULL AND p_host_name != 'unspecified') THEN
        v_message_template := replace(v_message_template, '$#HOST_NAME#$', p_host_name);
    ELSE
        v_message_template := replace(v_message_template, '$#HOST_NAME#$', '<unspecified service>');
    END IF;

    v_message_template := replace(v_message_template, '$#EVENT_DATE#$',
        coalesce(to_char(p_eventdate, 'DD.MM.YYYY HH24:MI'), '') || ' ' || v_tz);
    v_message_template := replace(v_message_template, '$#EVENT_TYPE_NAME#$', coalesce(p_event_type_name, ''));
    v_message_template := replace(v_message_template, '$#TICKET_ID#$', coalesce(p_ticket_id::text, ''));
    v_message_template := replace(v_message_template, '$#STATUS_VALID_UNTIL#$',
        coalesce(to_char(p_status_valid_until_date, 'DD.MM.YYYY HH24:MI'), '') || ' ' || v_tz);

    v_message_template := v_message_template || ' - Open Systems Mission Control';

    v_max_ticket_subject_size := s_sms_msg_size - length(v_message_template)
        + length('$#TICKET_SUBJECT#$') - length(v_emergency_text);

    IF (length(p_ticket_subject) > v_max_ticket_subject_size) THEN
        -- Oracle's SUBSTR(x, 0, n) behaves as SUBSTR(x, 1, n) (position 0 == 1); PostgreSQL's
        -- substr(x, 0, n) instead consumes one character of length. substr(x, 1, n) is the
        -- faithful port.
        v_ticket_subject := substr(p_ticket_subject, 1, (v_max_ticket_subject_size - 3)::int) || '...';
    ELSE
        v_ticket_subject := p_ticket_subject;
    END IF;

    v_message_template := replace(v_message_template, '$#TICKET_SUBJECT#$', coalesce(v_ticket_subject, ''));
    v_message_template := replace(v_message_template, '$#EMERGENCY#$', v_emergency_text);

    RETURN v_message_template;
END;
$fn$;
REVOKE ALL ON FUNCTION tt.osag_notify__compose_sms_msg(numeric, varchar, numeric, varchar, timestamp, timestamp, varchar, smallint) FROM PUBLIC;

-- ------------------------------------------------------------------------------------
-- __get_isp_link_id_for_host_id (S-NOTIFY-031) -- SELECT INTO site #22 (line 1496).
-- THE PILOT'S ONE AND ONLY TOO_MANY_ROWS HANDLER. Multi-row is structurally reachable
-- twice over: mss.interface's PK is `id` alone (a host can have >1 mgmtaccess interface),
-- and mss.interface2isp_link's PK is (interface_id, isp_link_id) (one interface can map
-- to >1 ISP link). Oracle EXPECTED this -- the handler is not defensive boilerplate.
--
-- Verdict: STRICT + handler, ALL THREE ARMS. STRICT is mandatory here: without it,
-- PL/pgSQL silently takes the first row and the TOO_MANY_ROWS arm becomes unreachable
-- dead code that still LOOKS faithful. All three arms swallow to NULL; none re-raises.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION tt.osag_notify__get_isp_link_id_for_host_id(p_host_id numeric)
RETURNS numeric
LANGUAGE plpgsql
AS $fn$
DECLARE
    s_prefix CONSTANT text := 'tt.osag_notify.get_isp_link_id_for_host_id(): ';
    v_isp_link_id numeric;
BEGIN
    BEGIN
        -- S-NOTIFY-031 (site #22): STRICT + all three handler arms.
        SELECT i2l.isp_link_id INTO STRICT v_isp_link_id
        FROM mss.host h, mss.interface i, mss.interface2isp_link i2l
        WHERE h.id = p_host_id
          AND i.host_id = h.id
          AND i2l.interface_id = i.id
          AND i.mgmtaccess = 1;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN NULL;
        WHEN TOO_MANY_ROWS THEN
            CALL osag.osag_plog_err(s_prefix || 'host[' || p_host_id || '] has too many ISP links');
            RETURN NULL;
        WHEN OTHERS THEN
            CALL osag.osag_plog_err(s_prefix || 'unknown error: ' || SQLERRM);
            RETURN NULL;
    END;

    RETURN v_isp_link_id;
END;
$fn$;
REVOKE ALL ON FUNCTION tt.osag_notify__get_isp_link_id_for_host_id(numeric) FROM PUBLIC;

-- ------------------------------------------------------------------------------------
-- __get_message_for_isp_outage (S-NOTIFY-032, S-NOTIFY-034)
-- FOUR SELECT INTO sites (#23 line 1556, #24 line 1571, #25 line 1583, #26 line 1601),
-- each in its OWN small BEGIN...EXCEPTION block that swallows INDEPENDENTLY, so a failure
-- at one never prevents the other three (or the composition) from running. All four:
-- STRICT + handler.
--
-- S-NOTIFY-034 (Pitfall 2): Oracle's NVL(contact.lastname, '') round-trips back to NULL
-- (Oracle collapses ''), so its later `IF v_acc_mgr_lastname IS NULL` correctly detects
-- "no account manager". orafce's NVL(NULL, '') returns a REAL '' in PostgreSQL, which is
-- NOT NULL -- the check would take the WRONG branch and print an empty name instead of
-- 'n/a'. Fixed at the boundary: the NVL is DROPPED (select the raw column) and the later
-- check tests `IS NULL OR = ''`, covering both the NULL column and a genuinely-'' one.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION tt.osag_notify__get_message_for_isp_outage(
    p_ticket_id numeric,
    p_isp_link_id numeric,
    p_host_id numeric,
    p_event_id numeric,
    p_isp_router_ip varchar,
    p_host_name varchar)
RETURNS varchar
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_message varchar;
    v_contact_list varchar;
    v_acc_mgr_lastname stop.contact.lastname%TYPE;
    v_acc_mgr_firstname stop.contact.firstname%TYPE;
    v_isp_account_number mss.isp_link.account_number%TYPE;
    v_isp_line_number mss.isp_link.line_number%TYPE;
    v_isp_company_id numeric;
    v_isp_company_name stop.company.name%TYPE;
    v_company_name stop.company.name%TYPE;
    v_city_name mss.city.name%TYPE;
    v_country_name mss.country.name%TYPE;
    v_connection_down_date varchar;
    contact_rec RECORD;
BEGIN
    BEGIN
        -- S-NOTIFY-032 (site #23): STRICT + WHEN OTHERS (Oracle sets '' there).
        -- S-NOTIFY-034: NVL(lastname,'') deliberately NOT ported -- see header.
        SELECT c.lastname, c.firstname, il.account_number, il.line_number, il.company_id
          INTO STRICT v_acc_mgr_lastname, v_acc_mgr_firstname, v_isp_account_number,
               v_isp_line_number, v_isp_company_id
        FROM mss.isp_link il
        LEFT JOIN stop.contact c ON il.account_manager_id = c.id
        WHERE il.id = p_isp_link_id;
    EXCEPTION
        WHEN OTHERS THEN
            v_acc_mgr_lastname := '';
    END;

    IF v_isp_company_id IS NOT NULL THEN
        BEGIN
            -- S-NOTIFY-032 (site #24): STRICT + WHEN OTHERS THEN NULL.
            SELECT co.name INTO STRICT v_isp_company_name
            FROM stop.company co
            WHERE co.id = v_isp_company_id;
        EXCEPTION
            WHEN OTHERS THEN
                NULL;
        END;
    END IF;

    BEGIN
        -- S-NOTIFY-032 (site #25): STRICT + WHEN OTHERS THEN NULL.
        SELECT co.name, ci.name, cy.name
          INTO STRICT v_company_name, v_city_name, v_country_name
        FROM mss.host h
        JOIN stop.company co ON h.service_company_id = co.id
        LEFT JOIN mss.address a ON h.address_id = a.id
        LEFT JOIN mss.city ci ON a.city_id = ci.id
        LEFT JOIN mss.country cy ON ci.country_id = cy.id
        WHERE h.id = p_host_id;
    EXCEPTION
        WHEN OTHERS THEN
            NULL;
    END;

    BEGIN
        -- S-NOTIFY-032 (site #26): STRICT + WHEN OTHERS THEN NULL. mc.connection_interrupt_open
        -- is NOT unique on host_id (its PK is id alone) -- the Oracle source's own comment
        -- calls "one open outage" an ASSUMPTION. STRICT means a TOO_MANY_ROWS here is caught
        -- by this same WHEN OTHERS, exactly as Oracle's would be. See the spec's Assumptions.
        SELECT to_char(cio.down_date AT TIME ZONE 'Europe/Zurich', 'DD Mon YYYY, HH24:MI TZH:TZM')
          INTO STRICT v_connection_down_date
        FROM mc.connection_interrupt_open cio
        WHERE cio.host_id = p_host_id;
    EXCEPTION
        WHEN OTHERS THEN
            NULL;
    END;

    v_message := 'Dear ' || coalesce(v_isp_company_name, '') || ' support,' || chr(10) ||
                 chr(10) ||
                 'The following local loop';
    IF (v_isp_company_name IS NOT NULL) THEN
        v_message := v_message || ' operated by ' || v_isp_company_name;
    END IF;

    -- Seeded from a REAL '' literal in Oracle too (line 1617) -- '' || 'x' = 'x' in both
    -- engines, so this accumulator is NOT an S-NOTIFY-020-shaped hazard.
    v_contact_list := '';

    FOR contact_rec IN
        SELECT c.id, c.firstname, c.lastname, c.direct, c.email
        FROM stop.contact c, mss.host h, mss.local_contact lc
        WHERE h.id = p_host_id
          AND lc.address_id = h.address_id
          AND lc.contact_id = c.id
          AND (c.direct IS NOT NULL OR c.email IS NOT NULL)
          AND lc.local_contact_type_id = 1
        ORDER BY lc.priority
    LOOP
        v_contact_list := v_contact_list || chr(10) || '- ' || coalesce(contact_rec.firstname, '')
            || ' ' || coalesce(contact_rec.lastname, '') || ' (';
        IF (contact_rec.direct IS NOT NULL) THEN
            v_contact_list := v_contact_list || 'phone: ' || contact_rec.direct;
        END IF;
        IF (contact_rec.email IS NOT NULL) THEN
            IF (contact_rec.direct IS NOT NULL) THEN
                v_contact_list := v_contact_list || ', ';
            END IF;
            v_contact_list := v_contact_list || 'email: ' || contact_rec.email;
        END IF;
        v_contact_list := v_contact_list || ')';
    END LOOP;

    v_message := v_message ||
                 ' is currently down.' || chr(10) ||
                 'The local loop details are provided below.' || chr(10) ||
                 'Please investigate and resolve the ' ||
                 'problem according to the SLA provided.' || chr(10) ||
                 chr(10);

    -- Oracle's `v_contact_list IS NOT NULL` is TRUE for the '' seed (Oracle: '' IS NULL is
    -- TRUE, so an empty list is NULL and this is FALSE). In PostgreSQL '' IS NOT NULL is
    -- TRUE, which would emit the "Should you need support" header with an EMPTY list --
    -- Pitfall 2 again, so the check is `<> ''` here (equivalent to Oracle's intent).
    IF (v_contact_list IS NOT NULL AND v_contact_list <> '') THEN
        v_message := v_message || 'Should you need support by the affected customer site, please contact:' ||
                     v_contact_list || chr(10) || chr(10);
    END IF;

    v_message := v_message || 'In case of further technical information required, do not hesitate' || chr(10) ||
                 'to contact Open Systems Mission Control by replying to this e-mail.' || chr(10) || chr(10) ||
                 'Best regards,' || chr(10) ||
                 'Mission Control' || chr(10) ||
                 chr(10) ||
                 'ISP Router IP: ' || coalesce(p_isp_router_ip, '') || ' (' || coalesce(p_host_name, '') || ')' || chr(10) ||
                 'Location:      ';
    IF (v_city_name IS NOT NULL) THEN
        v_message := v_message || v_city_name || ', ' || coalesce(v_country_name, '') || chr(10);
    ELSE
        v_message := v_message || 'n/a' || chr(10);
    END IF;

    v_message := v_message ||
                 'Customer:      ' || coalesce(v_company_name, 'n/a') || chr(10) ||
                 'Account no:    ' || coalesce(v_isp_account_number, 'n/a') || chr(10) ||
                 'Line no:       ' || coalesce(v_isp_line_number, 'n/a') || chr(10) ||
                 'Account mgr:   ';
    -- S-NOTIFY-034: `IS NULL OR = ''` -- Oracle's bare IS NULL also caught ''.
    IF (v_acc_mgr_lastname IS NULL OR v_acc_mgr_lastname = '') THEN
        v_message := v_message || 'n/a' || chr(10);
    ELSE
        v_message := v_message || v_acc_mgr_lastname || ' ' || coalesce(v_acc_mgr_firstname, '') || chr(10);
    END IF;

    v_message := v_message ||
                 'Outage start:  ' || coalesce(v_connection_down_date, 'n/a') || chr(10) ||
                 chr(10) ||
                 'This message was automatically generated.' || chr(10) || 'The Internet connectivity ' ||
                 'is measured from Zurich, Switzerland.' || chr(10) ||
                 tt.osag_notify__email_signature();

    RETURN v_message;
END;
$fn$;
REVOKE ALL ON FUNCTION tt.osag_notify__get_message_for_isp_outage(numeric, numeric, numeric, numeric, varchar, varchar) FROM PUBLIC;

-- ------------------------------------------------------------------------------------
-- __get_message_for_connection_up (S-NOTIFY-033, S-NOTIFY-034)
-- Mirrors the first THREE sites of __get_message_for_isp_outage exactly (#27 line 1704,
-- #28 line 1719, #29 line 1731 -- same independently-swallowing per-site blocks, same
-- structural safety). It has NO fourth (connection_interrupt_open) lookup -- a deliberate
-- content difference between the outage and restoration messages, not an omission.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION tt.osag_notify__get_message_for_connection_up(
    p_ticket_id numeric,
    p_isp_link_id numeric,
    p_host_id numeric,
    p_event_id numeric,
    p_isp_router_ip varchar,
    p_host_name varchar)
RETURNS varchar
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_message varchar;
    v_acc_mgr_lastname stop.contact.lastname%TYPE;
    v_acc_mgr_firstname stop.contact.firstname%TYPE;
    v_isp_account_number mss.isp_link.account_number%TYPE;
    v_isp_line_number mss.isp_link.line_number%TYPE;
    v_isp_company_id numeric;
    v_isp_company_name stop.company.name%TYPE;
    v_company_name stop.company.name%TYPE;
    v_city_name mss.city.name%TYPE;
    v_country_name mss.country.name%TYPE;
BEGIN
    BEGIN
        -- S-NOTIFY-033 (site #27): STRICT + WHEN OTHERS (Oracle sets '' there).
        -- S-NOTIFY-034: NVL(lastname,'') deliberately NOT ported -- see the outage twin.
        SELECT c.lastname, c.firstname, il.account_number, il.line_number, il.company_id
          INTO STRICT v_acc_mgr_lastname, v_acc_mgr_firstname, v_isp_account_number,
               v_isp_line_number, v_isp_company_id
        FROM mss.isp_link il
        LEFT JOIN stop.contact c ON il.account_manager_id = c.id
        WHERE il.id = p_isp_link_id;
    EXCEPTION
        WHEN OTHERS THEN
            v_acc_mgr_lastname := '';
    END;

    IF v_isp_company_id IS NOT NULL THEN
        BEGIN
            -- S-NOTIFY-033 (site #28): STRICT + WHEN OTHERS THEN NULL.
            SELECT co.name INTO STRICT v_isp_company_name
            FROM stop.company co
            WHERE co.id = v_isp_company_id;
        EXCEPTION
            WHEN OTHERS THEN
                NULL;
        END;
    END IF;

    BEGIN
        -- S-NOTIFY-033 (site #29): STRICT + WHEN OTHERS THEN NULL.
        SELECT co.name, ci.name, cy.name
          INTO STRICT v_company_name, v_city_name, v_country_name
        FROM mss.host h
        JOIN stop.company co ON h.service_company_id = co.id
        LEFT JOIN mss.address a ON h.address_id = a.id
        LEFT JOIN mss.city ci ON a.city_id = ci.id
        LEFT JOIN mss.country cy ON ci.country_id = cy.id
        WHERE h.id = p_host_id;
    EXCEPTION
        WHEN OTHERS THEN
            NULL;
    END;

    v_message := 'Dear support,' || chr(10) ||
                 chr(10) ||
                 'The following local loop,';
    IF (v_isp_company_name IS NOT NULL) THEN
        v_message := v_message || ' provided by ' || v_isp_company_name || ',';
    END IF;
    v_message := v_message ||
                 ' is up again. Thank you for your efforts.' || chr(10) ||
                 chr(10) ||
                 'Do not hesitate to contact Open Systems Mission Control by ' ||
                 'replying to this e-mail in case you require further information.' || chr(10) ||
                 chr(10) ||
                 'Best regards,' || chr(10) ||
                 'Mission Control' || chr(10) ||
                 chr(10) ||
                 'ISP Router IP: ' || coalesce(p_isp_router_ip, '') || ' (' || coalesce(p_host_name, '') || ')' || chr(10) ||
                 'Location:      ';
    IF (v_city_name IS NOT NULL) THEN
        v_message := v_message || v_city_name || ', ' || coalesce(v_country_name, '') || chr(10);
    ELSE
        v_message := v_message || 'n/a' || chr(10);
    END IF;

    v_message := v_message ||
                 'Customer:      ' || coalesce(v_company_name, 'n/a') || chr(10) ||
                 'Account no:    ' || coalesce(v_isp_account_number, 'n/a') || chr(10) ||
                 'Line no:       ' || coalesce(v_isp_line_number, 'n/a') || chr(10) ||
                 'Account mgr:   ';
    -- S-NOTIFY-034: `IS NULL OR = ''`, same reason as the outage twin.
    IF (v_acc_mgr_lastname IS NULL OR v_acc_mgr_lastname = '') THEN
        v_message := v_message || 'n/a' || chr(10);
    ELSE
        v_message := v_message || v_acc_mgr_lastname || ' ' || coalesce(v_acc_mgr_firstname, '') || chr(10);
    END IF;

    v_message := v_message ||
                 chr(10) ||
                 'This message was automatically generated. The Internet connectivity ' ||
                 'is measured from Zurich, Switzerland.' || chr(10) ||
                 tt.osag_notify__email_signature();

    RETURN v_message;
END;
$fn$;
REVOKE ALL ON FUNCTION tt.osag_notify__get_message_for_connection_up(numeric, numeric, numeric, numeric, varchar, varchar) FROM PUBLIC;

-- ------------------------------------------------------------------------------------
-- __send_notification_by_type (S-NOTIFY-024, S-NOTIFY-025)
-- SELECT INTO sites #12 (line 1050, SMS branch) and #13 (line 1072, email branch): both
-- 1:1 PK-to-PK joins (auth.login.id, stop.contact.id) -- TOO_MANY_ROWS structurally
-- impossible; zero rows reachable for a bad p_login_id. Oracle has NO exception block in
-- this routine at all; all 3 of its call sites are inside event_notify, so an unhandled
-- NO_DATA_FOUND escalates to event_notify's outer WHEN OTHERS.
-- Verdict for both: STRICT, NO local handler.
--
-- The Oracle SMTP-header collection (OSAG_MSG.smtp_headers_t, lines 1043-1044/1083-1093)
-- belongs to OSAG.OSAG_MSG, which the pilot does not translate. The two headers it builds
-- (Auto-Submitted: auto-generated / Precedence: bulk) are passed as a plain text[][] to
-- the future osag.osag_msg_send_mail -- shape flagged in FINDINGS as an OSAG_MSG-owned
-- decision, not one this package may finalize.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.osag_notify__send_notification_by_type(
    p_event_notification_type_id numeric,
    p_ticket_id numeric,
    p_login_id numeric,
    p_event_type_name varchar,
    p_host_name varchar,
    p_eventdate timestamp,
    p_event_details_public varchar,
    p_email_message_subject varchar,
    p_email_message_body varchar,
    p_sms_message varchar,
    p_is_public_event numeric DEFAULT 1)
LANGUAGE plpgsql
AS $fn$
DECLARE
    s_prefix CONSTANT text := 'tt.osag_notify.send_notification_by_type(): ';
    s_reply_to_addr CONSTANT varchar := 'support@open.ch';
    s_from_addr CONSTANT varchar := 'monitoring@open.ch';

    v_contact_id numeric;
    v_target_address varchar;
    v_contact_last_name stop.contact.lastname%TYPE;
    v_contact_first_name stop.contact.firstname%TYPE;
    v_email_message_body varchar;
    v_envelope_from varchar;
    v_smtp_headers text[][] := ARRAY[['Auto-Submitted', 'auto-generated'], ['Precedence', 'bulk']];
BEGIN
    IF p_event_notification_type_id = 1 THEN
        -- S-NOTIFY-024 (site #12): STRICT, no local handler (Oracle has none).
        SELECT c.id, c.mobile, c.lastname, c.firstname
          INTO STRICT v_contact_id, v_target_address, v_contact_last_name, v_contact_first_name
        FROM auth.login l, stop.contact c
        WHERE l.id = p_login_id
          AND c.id = l.contact_id;

        IF (v_target_address IS NOT NULL) THEN
            CALL osag.osag_plog_notice(s_prefix || 'sending SMS to ' || coalesce(v_contact_first_name, '')
                || ' ' || coalesce(v_contact_last_name, '') || ' (login[' || p_login_id || ']), ' || v_target_address);

            CALL osag.osag_msg_send_sms(v_target_address, p_sms_message);

            CALL tt.osag_notify_add_notification_event(p_ticket_id, 20003,
                'sent to ' || coalesce(v_contact_first_name, '') || ' ' || coalesce(v_contact_last_name, '')
                || ', ' || v_target_address || chr(10) || coalesce(p_sms_message, ''),
                NULL, v_contact_id, p_is_public_event);
        ELSE
            CALL osag.osag_plog_notice(s_prefix || 'event notification not sent to auth.login['
                || p_login_id || '], assigned contact has no mobile number specified');
        END IF;
    END IF; -- end of SMS notification

    IF p_event_notification_type_id = 2 THEN
        -- S-NOTIFY-025 (site #13): STRICT, no local handler (Oracle has none).
        SELECT c.id, c.email, c.lastname, c.firstname
          INTO STRICT v_contact_id, v_target_address, v_contact_last_name, v_contact_first_name
        FROM auth.login l, stop.contact c
        WHERE l.id = p_login_id
          AND c.id = l.contact_id;

        IF (v_target_address IS NOT NULL) THEN
            CALL osag.osag_plog_notice(s_prefix || 'sending email to ' || coalesce(v_contact_first_name, '')
                || ' ' || coalesce(v_contact_last_name, '') || ' (login[' || p_login_id || ']), ' || v_target_address);

            IF (v_contact_last_name IS NOT NULL AND v_contact_first_name IS NOT NULL) THEN
                v_email_message_body := 'Dear ' || v_contact_first_name || ' ' || v_contact_last_name
                    || ',' || chr(10) || chr(10) || coalesce(p_email_message_body, '');
            ELSE
                v_email_message_body := 'Dear customer,' || chr(10) || chr(10) || coalesce(p_email_message_body, '');
            END IF;

            -- S-NOTIFY-025: envelope-from differs by public/private -- a routing
            -- distinction, not an error path.
            IF (p_is_public_event = 1) THEN
                v_envelope_from := 'ttbounce+' || p_ticket_id || '@open.ch';
            ELSE
                v_envelope_from := 'ttbounce-private+' || p_ticket_id || '@open.ch';
            END IF;

            CALL osag.osag_msg_send_mail(s_reply_to_addr, s_from_addr, v_envelope_from, v_target_address,
                p_email_message_subject, v_email_message_body, v_smtp_headers);

            CALL tt.osag_notify_add_notification_event(p_ticket_id, 20001,
                'sent to ' || coalesce(v_contact_first_name, '') || ' ' || coalesce(v_contact_last_name, '')
                || ', ' || v_target_address || chr(10) || v_email_message_body,
                NULL, v_contact_id, p_is_public_event);
        ELSE
            CALL osag.osag_plog_notice(s_prefix || 'event notification not sent to auth.login['
                || p_login_id || '], assigned contact has no email address specified');
        END IF;
    END IF; -- end of email notification
END;
$fn$;
REVOKE ALL ON PROCEDURE tt.osag_notify__send_notification_by_type(numeric, numeric, numeric, varchar, varchar, timestamp, varchar, varchar, varchar, varchar, numeric) FROM PUBLIC;

-- ------------------------------------------------------------------------------------
-- __notify_local_contacts (S-NOTIFY-029)
-- SELECT INTO sites #18 (line 1336), #19 (line 1342), #20 (line 1347): three single-row
-- PK lookups, ALL THREE covered by ONE routine-level handler
-- (WHEN NO_DATA_FOUND THEN plog.err(...); RETURN, lines 1378-1381) because all three are
-- lexically inside the routine's own BEGIN...EXCEPTION block. Verdict: STRICT + handler.
--
-- S-NOTIFY-029's subtlety, preserved: p_notified_cust is only assigned AFTER all three
-- SELECTs (Oracle line 1357), so a NO_DATA_FOUND leaves it unassigned/NULL -- and both
-- Oracle's and PL/pgSQL's `IF <null> THEN` treat that as not-TRUE, so the caller's check
-- behaves identically. Reproduced by leaving the INOUT parameter untouched on that path.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.osag_notify__notify_local_contacts(
    p_event_id numeric,
    p_event_type_id numeric,
    p_ticket_id numeric,
    p_host_id numeric,
    p_host_name varchar,
    p_customer_reference varchar,
    p_company_id numeric,
    p_service_id numeric,
    p_eventdate timestamp,
    p_status_valid_until_date timestamp,
    p_ticket_subject varchar,
    INOUT p_notified_cust boolean)
LANGUAGE plpgsql
AS $fn$
DECLARE
    s_prefix CONSTANT text := 'tt.osag_notify.notify_local_contacts(): ';
    s_reply_to_addr CONSTANT varchar := 'support@open.ch';
    s_from_addr CONSTANT varchar := 'monitoring@open.ch';

    v_message_subject varchar;
    v_message varchar;
    v_sms_message varchar;
    v_service_name mss.service_type.name%TYPE;
    v_company_name stop.company.name%TYPE;
    v_event_type_name tt.event_type.name%TYPE;
    v_envelope_from varchar;
    local_contact_rec RECORD;
BEGIN
    -- S-NOTIFY-029 (site #18): STRICT; handled by this routine's own NO_DATA_FOUND arm.
    SELECT st.name INTO STRICT v_service_name
    FROM mss.service_type st, mss.service s
    WHERE s.service_type_id = st.id
      AND s.id = p_service_id;

    -- S-NOTIFY-029 (site #19): STRICT; same routine-level handler.
    SELECT name INTO STRICT v_company_name
    FROM stop.company
    WHERE id = p_company_id;

    -- S-NOTIFY-029 (site #20): STRICT; same routine-level handler.
    SELECT name INTO STRICT v_event_type_name
    FROM tt.event_type
    WHERE id = p_event_type_id;

    v_message_subject := '[OS-' || p_ticket_id || ']'
        || tt.osag_notify__format_customer_reference(p_customer_reference)
        || coalesce(v_event_type_name, '');
    v_message := tt.osag_notify__compose_local_contact_message(p_ticket_id, v_event_type_name, p_host_name, p_eventdate);
    -- S-NOTIFY-028: this call is lexically inside THIS routine's handler, so
    -- compose_sms_msg's own unhandled NO_DATA_FOUND IS caught here (one of the three
    -- different outcomes the same exception has depending on call path).
    v_sms_message := tt.osag_notify__compose_sms_msg(p_ticket_id, p_host_name, p_event_type_id,
        v_event_type_name, p_eventdate, p_status_valid_until_date, p_ticket_subject, 0::smallint);

    p_notified_cust := FALSE;
    FOR local_contact_rec IN
        SELECT c.*, lcn.event_notification_type_id
        FROM stop.contact c, mss.local_contact lc, mss.address a, mss.host h, mss.local_contact_notification lcn
        WHERE h.address_id = a.id
          AND a.id = lc.address_id
          AND lc.contact_id = c.id
          AND lc.local_contact_type_id = 1
          AND lc.id = lcn.local_contact_id
          AND h.id = p_host_id
        ORDER BY lc.priority
    LOOP
        IF (local_contact_rec.event_notification_type_id = 1 AND local_contact_rec.mobile IS NOT NULL) THEN
            CALL osag.osag_plog_notice(s_prefix || 'sending sms to local emergency contact: ' || local_contact_rec.mobile);
            CALL osag.osag_msg_send_sms(local_contact_rec.mobile, v_sms_message);
            CALL tt.osag_notify_add_notification_event(p_ticket_id, 20003,
                'sent to ' || local_contact_rec.mobile || ' (local contact sms notification)' || chr(10)
                || chr(10) || chr(10) || coalesce(v_sms_message, ''), NULL, local_contact_rec.id);
            p_notified_cust := TRUE;
        ELSIF (local_contact_rec.event_notification_type_id = 2 AND local_contact_rec.email IS NOT NULL) THEN
            CALL osag.osag_plog_notice(s_prefix || 'sending email to local emergency contact: ' || local_contact_rec.email);
            v_envelope_from := 'ttbounce+' || p_ticket_id || '@open.ch';
            CALL osag.osag_msg_send_mail(s_reply_to_addr, s_from_addr, v_envelope_from,
                local_contact_rec.email, v_message_subject, v_message);
            CALL tt.osag_notify_add_notification_event(p_ticket_id, 20001,
                'sent to ' || local_contact_rec.email || ' (local contact email notification)' || chr(10)
                || coalesce(v_message_subject, '') || chr(10) || chr(10) || coalesce(v_message, ''),
                NULL, local_contact_rec.id);
            p_notified_cust := TRUE;
        END IF;
    END LOOP;
EXCEPTION
    -- S-NOTIFY-029: routine-level NO_DATA_FOUND arm covering sites #18/#19/#20 (and,
    -- lexically, the compose_sms_msg call). Logs and returns; swallows, never re-raises.
    WHEN NO_DATA_FOUND THEN
        CALL osag.osag_plog_err(s_prefix || 'found no data for event ' || p_event_id);
        RETURN;
END;
$fn$;
REVOKE ALL ON PROCEDURE tt.osag_notify__notify_local_contacts(numeric, numeric, numeric, numeric, varchar, varchar, numeric, numeric, timestamp, timestamp, varchar, boolean) FROM PUBLIC;

-- ------------------------------------------------------------------------------------
-- __notify_isp (S-NOTIFY-030)
-- SELECT INTO site #21 (line 1438): 1:1 PK-to-PK join (mss.isp_link.id, stop.contact.id)
-- -- TOO_MANY_ROWS structurally impossible; zero rows reachable if support_id is NULL or
-- orphaned. Oracle has a LOCAL handler covering BOTH cases it anticipates
-- (WHEN NO_DATA_FOUND / WHEN OTHERS, both swallowing to NULL, lines 1444-1449).
-- Verdict: STRICT + handler (both arms).
--
-- S-NOTIFY-030's confirmed no-delta note: the subsequent `IF (v_isp_notification = 0)`
-- compares a possibly-NULL value against 0 -- NULL = 0 is NULL, and `IF NULL THEN` is
-- FALSE in BOTH engines, so execution correctly falls through rather than short-circuiting.
--
-- mss.osag_ip.num2ip -> mss.osag_ip_num2ip (name-map.csv row 112). MSS.OSAG_IP is not in
-- the pilot's translation set; CALL/function resolution is deferred to run time.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.osag_notify__notify_isp(
    p_event_id numeric,
    p_event_type_id numeric,
    p_ticket_id numeric,
    p_host_id numeric,
    p_host_name varchar,
    p_customer_reference varchar)
LANGUAGE plpgsql
AS $fn$
DECLARE
    s_prefix CONSTANT text := 'tt.osag_notify.notify_isp(): ';
    s_reply_to_addr CONSTANT varchar := 'support@open.ch';
    s_from_addr CONSTANT varchar := 'monitoring@open.ch';

    v_isp_link_id mss.isp_link.id%TYPE;
    v_isp_notification mss.isp_link.isp_notification%TYPE;
    v_isp_support_mail stop.contact.email%TYPE;
    v_isp_contact_id stop.contact.id%TYPE;
    v_isp_router_ip mss.isp_link.router_ip_address1%TYPE;
    v_message_subject varchar;
    v_message varchar;
    v_envelope_from varchar;
BEGIN
    v_isp_link_id := tt.osag_notify__get_isp_link_id_for_host_id(p_host_id);

    IF (v_isp_link_id IS NULL) THEN
        RETURN; -- no isp link found
    END IF;

    BEGIN
        -- S-NOTIFY-030 (site #21): STRICT + both Oracle handler arms.
        SELECT i.isp_notification, i.router_ip_address1, c.email, c.id
          INTO STRICT v_isp_notification, v_isp_router_ip, v_isp_support_mail, v_isp_contact_id
        FROM mss.isp_link i, stop.contact c
        WHERE i.id = v_isp_link_id
          AND i.support_id = c.id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_isp_support_mail := NULL;
        WHEN OTHERS THEN
            CALL osag.osag_plog_err(s_prefix || 'unknown error: ' || SQLERRM);
            v_isp_support_mail := NULL;
    END;

    -- S-NOTIFY-030: NULL = 0 is NULL; IF NULL THEN is FALSE in both engines -- falls through.
    IF (v_isp_notification = 0) THEN
        RETURN; -- isp outage notification disabled for this link
    END IF;

    IF (v_isp_support_mail IS NOT NULL AND v_isp_support_mail != 'unknown@during.import.tld') THEN
        IF p_event_type_id = 10003 THEN -- isp outage
            v_message_subject := '[OS-' || p_ticket_id || ']'
                || tt.osag_notify__format_customer_reference(p_customer_reference)
                || ' ISP outage detected for ' || coalesce(mss.osag_ip_num2ip(v_isp_router_ip), '');
            v_message := tt.osag_notify__get_message_for_isp_outage(p_ticket_id, v_isp_link_id, p_host_id,
                p_event_id, mss.osag_ip_num2ip(v_isp_router_ip), p_host_name);
        END IF;

        IF p_event_type_id = 10100 THEN -- connection up
            v_message_subject := '[OS-' || p_ticket_id || ']'
                || tt.osag_notify__format_customer_reference(p_customer_reference)
                || ' connection up for ' || coalesce(mss.osag_ip_num2ip(v_isp_router_ip), '');
            v_message := tt.osag_notify__get_message_for_connection_up(p_ticket_id, v_isp_link_id, p_host_id,
                p_event_id, mss.osag_ip_num2ip(v_isp_router_ip), p_host_name);
        END IF;
        v_envelope_from := 'ttbounce+' || p_ticket_id || '@open.ch';

        CALL osag.osag_plog_notice(s_prefix || 'sending email to isp support contact: ' || v_isp_support_mail);

        CALL osag.osag_msg_send_mail(s_reply_to_addr, s_from_addr, v_envelope_from, v_isp_support_mail,
            v_message_subject, v_message);

        CALL tt.osag_notify_add_notification_event(p_ticket_id, 20001,
            'sent to ' || v_isp_support_mail || ' (isp email notification)' || chr(10)
            || coalesce(v_message_subject, '') || chr(10) || chr(10) || coalesce(v_message, ''),
            NULL, v_isp_contact_id);
    END IF;
END;
$fn$;
REVOKE ALL ON PROCEDURE tt.osag_notify__notify_isp(numeric, numeric, numeric, numeric, varchar, varchar) FROM PUBLIC;

-- =====================================================================================
-- PUBLIC routines (names verbatim from migration/mapping/name-map.csv)
-- =====================================================================================

-- ------------------------------------------------------------------------------------
-- add_notification_event (S-NOTIFY-022)
-- Pure INSERT into tt.event. ZERO SELECT INTO sites -- the only public routine with none.
-- NO exception block: an INSERT failure (FK violation, NOT NULL violation) propagates
-- FULLY UNHANDLED to the caller. That is a deliberate "let it fail loudly" contract, not
-- an oversight -- do not wrap this.
--
-- event_sequence.NextVal -> nextval('tt.event_sequence') (S-NOTIFY-015's note).
-- Defined before its callers below only because PL/pgSQL resolves nothing at CREATE time;
-- placed here so the private routines above that CALL it read naturally.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.osag_notify_add_notification_event(
    p_ticket_id numeric,
    p_event_type_id numeric,
    p_text varchar,
    p_contact_id numeric,
    p_peer_contact_id numeric DEFAULT NULL,
    p_is_public_event numeric DEFAULT 1)
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_details_public varchar;
    v_details_private varchar;
BEGIN
    IF (p_is_public_event = 1) THEN
        v_details_public := p_text;
        v_details_private := NULL;
    ELSE
        v_details_public := NULL;
        v_details_private := p_text;
    END IF;

    INSERT INTO tt.event
        (id, contact_id, peer_contact_id, type_id, ticket_id, eventdate, details_public, details_private, public_event)
    VALUES (nextval('tt.event_sequence'),
            p_contact_id,
            p_peer_contact_id,
            p_event_type_id,
            p_ticket_id,
            statement_timestamp(),
            v_details_public,
            v_details_private,
            p_is_public_event);
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- is_notify_suppressor_active (S-NOTIFY-023) -- the one FUNCTION among the six.
-- SELECT INTO site #11 (line 987): a COUNT(*) aggregate -- ALWAYS exactly one row, so
-- both NO_DATA_FOUND and TOO_MANY_ROWS are structurally impossible.
-- Verdict: **no STRICT** -- the package's one legitimate no-STRICT-concern site. Adding
-- STRICT here would be the blanket answer this plan exists to avoid.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION tt.osag_notify_is_notify_suppressor_active(p_host_id numeric)
RETURNS boolean
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_entry_exists integer;
BEGIN
    -- S-NOTIFY-023 (site #11): COUNT(*) aggregate -- NO STRICT, deliberately.
    SELECT count(*)
      INTO v_entry_exists
    FROM tt.ticket t
        INNER JOIN tt.service_window s ON (s.ticket_id = t.id)
        INNER JOIN tt.host2service_window h2s ON (h2s.service_window_id = s.id)
        LEFT JOIN tt.maintenance_window m ON (s.id = m.service_window_id)
        LEFT JOIN tt.cust_maintenance_window cm ON (s.id = cm.service_window_id)
    WHERE t.status_id < 101
      AND s.end_date > statement_timestamp()
      AND s.start_date < statement_timestamp()
      AND (m.disable_notification = 1 OR cm.disable_notification = 1)
      AND h2s.host_id = p_host_id;

    IF (v_entry_exists > 0) THEN
        RETURN TRUE;
    END IF;
    RETURN FALSE;
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- send_test_notification (S-NOTIFY-018)
-- SELECT INTO site #10 (line 785): PK lookup on tt.event_type. Zero rows reachable.
-- **This routine has NO EXCEPTION BLOCK ANYWHERE in its 81-line Oracle body** -- the only
-- one of the six public routines with no safety net at all. So this NO_DATA_FOUND (and
-- compose_sms_msg's / compose_email_msg's, sites #15/#17, reached from here) propagates
-- FULLY UNHANDLED to whatever called it.
-- Verdict: STRICT, UNHANDLED -- with NO wrapping handler added. That is the pilot's
-- primary reachable "STRICT, unhandled" target and the whole point of the site.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.osag_notify_send_test_notification(
    p_destination_address varchar,
    p_notification_type_id numeric,
    p_ticket_id numeric,
    p_ticket_subject varchar,
    p_host_name varchar,
    p_event_type_id numeric,
    p_eventdate timestamptz,
    p_contact_last_name varchar DEFAULT NULL,
    p_contact_first_name varchar DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
DECLARE
    s_prefix CONSTANT text := 'tt.osag_notify.send_test_notification(): ';
    s_reply_to_addr CONSTANT varchar := 'support@open.ch';
    s_from_addr CONSTANT varchar := 'monitoring@open.ch';

    v_event_type_name tt.event_type.name%TYPE;
    v_message_subject varchar;
    v_message varchar;
    v_message_prefix varchar;
    v_eventdate timestamp := p_eventdate::timestamp;
BEGIN
    -- S-NOTIFY-018 (site #10): STRICT, UNHANDLED -- no handler exists in Oracle and none
    -- is added here. The raise is this routine's contract.
    SELECT name INTO STRICT v_event_type_name
    FROM tt.event_type et
    WHERE et.id = p_event_type_id;

    v_message_prefix := ' ---------------------------------------------------------------------- ' || chr(10) ||
                        '|                   THIS IS ONLY A TEST NOTIFICATION                   |' || chr(10) ||
                        ' ----------------------------------------------------------------------' || chr(10) || chr(10);

    IF (p_notification_type_id = 1) THEN
        -- SMS
        v_message := tt.osag_notify__compose_sms_msg(p_ticket_id,
                                                     p_host_name,
                                                     p_event_type_id,
                                                     v_event_type_name,
                                                     v_eventdate,
                                                     v_eventdate + interval '1 day',
                                                     p_ticket_subject,
                                                     0::smallint);

        CALL osag.osag_msg_send_sms(p_destination_address, 'TEST - ' || v_message);

        CALL osag.osag_plog_notice(s_prefix || 'test notification (SMS) sent to '
            || coalesce(p_contact_first_name, '') || ' ' || coalesce(p_contact_last_name, '')
            || ' (' || p_destination_address || ')');
        CALL osag.osag_plog_notice(s_prefix || p_destination_address || ' - TEST - ' || v_message);
    ELSIF (p_notification_type_id = 2) THEN
        CALL tt.osag_notify__compose_email_msg(v_message_subject,  -- INOUT (Oracle OUT)
                                               v_message,          -- INOUT (Oracle OUT)
                                               p_ticket_id,
                                               p_ticket_subject,
                                               'test ticket',
                                               NULL,               -- no customer reference
                                               p_host_name,
                                               p_event_type_id,
                                               v_event_type_name,
                                               p_ticket_subject,
                                               v_eventdate,
                                               v_eventdate + interval '1 day',
                                               'This is a test notification.',
                                               'This is a test notification',
                                               0::smallint,        -- no emergency
                                               6);                 -- OSAG company placeholder

        IF (p_contact_last_name IS NOT NULL AND p_contact_first_name IS NOT NULL) THEN
            v_message := 'Dear ' || p_contact_first_name || ' ' || p_contact_last_name || ','
                || chr(10) || chr(10) || v_message;
        ELSE
            v_message := 'Dear customer,' || chr(10) || chr(10) || v_message;
        END IF;

        CALL osag.osag_msg_send_mail(s_reply_to_addr, s_from_addr, NULL, p_destination_address,
            v_message_subject, v_message_prefix || v_message);

        CALL osag.osag_plog_notice(s_prefix || 'test notification (email) sent to '
            || coalesce(p_contact_first_name, '') || ' ' || coalesce(p_contact_last_name, '')
            || ' (' || p_destination_address || ')');
    END IF;
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- delete_ticket_notifications (S-NOTIFY-020, S-NOTIFY-021)
-- No SELECT INTO of its own (the cursor is a FOR loop -- zero rows is an empty loop). Its
-- top-level WHEN OTHERS (Oracle lines 932-935) logs twice and SWALLOWS -- catching, among
-- other things, __get_notification_type_name's fully-unhandled site #30 NO_DATA_FOUND.
--
-- S-NOTIFY-020 (Pitfall 2, this package's best example outside format_customer_reference):
-- v_event_details_public/_private are declared with NO default in Oracle -- both start
-- NULL, and Oracle's `NULL || 'x' = 'x'` seeds the accumulator on the first loop pass.
-- PL/pgSQL's `NULL || 'x' = NULL` would leave BOTH permanently NULL, silently dropping
-- every deletion-description line while the DELETEs still succeed. Same hazard again at
-- the suffix append (`x := x || p_event_details_suffix`) when the suffix is left at its
-- NULL default -- Oracle's `x || NULL = x` leaves the text alone; PL/pgSQL's would WIPE it.
-- Both normalized with coalesce(..., '') at the boundary. The accumulators still start
-- NULL (not '') so that the `IS NOT NULL` gates below keep Oracle's exact meaning: "did
-- this loop actually append anything?".
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.osag_notify_delete_ticket_notifications(
    p_ticket_id numeric,
    p_login_id numeric DEFAULT NULL,
    p_event_details_suffix varchar DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
DECLARE
    s_prefix CONSTANT text := 'tt.osag_notify.delete_ticket_notifications(): ';
    v_event_details_public varchar;   -- starts NULL, exactly as Oracle
    v_event_details_private varchar;  -- starts NULL, exactly as Oracle
    notification_record RECORD;
BEGIN
    FOR notification_record IN
        SELECT en.id, en.login_id, en.event_notification_type_id, c.lastname, c.firstname,
               c.mobile, c.email, l.company_id AS login_company_id, t.company_id AS ticket_company_id
        FROM tt.event_notification en, auth.login l, stop.contact c, tt.ticket t
        WHERE en.ticket_id = p_ticket_id
          AND t.id = p_ticket_id
          AND l.id = en.login_id
          AND (p_login_id IS NULL OR en.login_id = p_login_id)
          AND c.id = l.contact_id
    LOOP
        IF (notification_record.login_company_id = 6 AND notification_record.ticket_company_id != 6) THEN
            -- notifications for OSAG logins in non-OSAG tickets are private
            -- S-NOTIFY-020: coalesce seeds the NULL accumulator (Oracle's NULL||'x' = 'x').
            v_event_details_private := coalesce(v_event_details_private, '') || '  -deleted '
                || coalesce(tt.osag_notify__get_notification_type_name(notification_record.event_notification_type_id), '')
                || ' notification for ' || coalesce(notification_record.firstname, '')
                || ' ' || coalesce(notification_record.lastname, '') || chr(10);
        ELSE
            v_event_details_public := coalesce(v_event_details_public, '') || '  -deleted '
                || coalesce(tt.osag_notify__get_notification_type_name(notification_record.event_notification_type_id), '')
                || ' notification for ' || coalesce(notification_record.firstname, '')
                || ' ' || coalesce(notification_record.lastname, '') || chr(10);
        END IF;
        DELETE FROM tt.event_notification en WHERE en.id = notification_record.id;
    END LOOP;

    -- S-NOTIFY-020: the suffix append. Oracle's `x || NULL = x`; PL/pgSQL's would wipe x.
    IF (v_event_details_public IS NOT NULL) THEN
        v_event_details_public := v_event_details_public || coalesce(p_event_details_suffix, '');
    END IF;
    IF (v_event_details_private IS NOT NULL) THEN
        v_event_details_private := v_event_details_private || coalesce(p_event_details_suffix, '');
    END IF;

    -- S-NOTIFY-021: the history-event write fires only if the accumulator holds text.
    IF (v_event_details_public IS NOT NULL OR v_event_details_private IS NOT NULL) THEN
        CALL tt.ticket_interface_change_notification(p_ticket_id,
                                                     v_event_details_public,
                                                     v_event_details_private,
                                                     NULL);
    END IF;

EXCEPTION
    -- S-NOTIFY-021: top-level WHEN OTHERS -- logs twice, SWALLOWS, never re-raises.
    WHEN OTHERS THEN
        CALL osag.osag_plog_warning(s_prefix || 'deletion of notifications for ticket ' || p_ticket_id || ' failed');
        CALL osag.osag_plog_warning(s_prefix || 'exception: ' || SQLERRM);
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- delete_notifications_for_login (S-NOTIFY-019)
-- Cursor FOR loop (zero matching tickets is a normal empty loop, NOT an exception), then
-- one unconditional bulk DELETE that succeeds on zero rows. NO SELECT INTO, and NO
-- EXCEPTION block of its own -- both faithfully reproduced.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.osag_notify_delete_notifications_for_login(p_login_id numeric)
LANGUAGE plpgsql
AS $fn$
DECLARE
    notification_record RECORD;
BEGIN
    FOR notification_record IN
        SELECT DISTINCT en.ticket_id
        FROM tt.event_notification en
        WHERE en.login_id = p_login_id
          AND en.ticket_id IS NOT NULL
    LOOP
        CALL tt.osag_notify_delete_ticket_notifications(notification_record.ticket_id, p_login_id,
                                                        'because the user was deleted');
    END LOOP;

    DELETE FROM tt.event_notification WHERE login_id = p_login_id;
END;
$fn$;

-- ------------------------------------------------------------------------------------
-- event_notify (S-NOTIFY-001..017) -- the package's flagship entry point.
--
-- S-NOTIFY-001, THE headline finding: the ENTIRE body is wrapped in ONE top-level
-- `WHEN OTHERS THEN plog.warning(...); plog.warning(...)` with NO RAISE. Every one of the
-- ~20 SELECT INTO sites and private-routine calls reachable from here -- whatever it
-- raises, NO_DATA_FOUND or TOO_MANY_ROWS or anything else -- is caught HERE if not caught
-- closer to its source, logged, and SWALLOWED. This procedure NEVER raises to its caller.
-- A translation that (correctly) adds STRICT everywhere but forgets this outer swallow
-- would start raising errors into ticket-update transactions that Oracle never did.
--
-- SELECT INTO sites #1-#9 live in this routine. Sites #1, #2, #4-#8 have NO local handler
-- (they escalate to the outer swallow); site #3 has a local NO_DATA_FOUND arm; site #9 has
-- a local NO_DATA_FOUND arm ONLY -- its TOO_MANY_ROWS (structurally reachable, see
-- S-NOTIFY-009) is deliberately NOT caught locally and escalates to the outer WHEN OTHERS,
-- aborting the rest of the procedure including the notify-count updates. That two-tier
-- structure is reproduced exactly, NOT simplified into one catch-all handler.
--
-- DBMS_UTILITY.GET_TIME (S-NOTIFY-017, perf-monitoring only, no behavioral effect) ->
-- clock_timestamp() deltas.
-- ------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tt.osag_notify_event_notify(
    p_event_id numeric,
    p_ticket_id numeric DEFAULT NULL,
    p_question varchar DEFAULT NULL)
LANGUAGE plpgsql
AS $fn$
DECLARE
    s_prefix CONSTANT text := 'tt.osag_notify.event_notify(): ';
    max_event_notify_count CONSTANT numeric := 5;
    elapsed_time_barrier CONSTANT numeric := 500;  -- centiseconds -> 2s

    v_host_name mss.host.name%TYPE;
    v_host_id numeric;
    v_service_id numeric;
    v_ticket_worker_id numeric;
    v_service_type_id numeric;
    v_company_id numeric;
    v_company_unit_id numeric;
    v_ticket_id numeric;
    v_ticket_type_id numeric;
    v_ticket_type_name tt.ticket_type.name%TYPE;
    v_ticket_subject tt.ticket.subject%TYPE;
    v_emergency_flag tt.ticket.emergency%TYPE;
    v_status_valid_until_date tt.ticket.status_valid_until_date%TYPE;
    v_eventdate timestamp;
    v_details varchar;
    v_details_private varchar;
    v_event_subject varchar;
    v_customer_reference tt.ticket.customer_reference%TYPE;
    v_event_notify_count_cust tt.ticket.event_notify_count%TYPE;
    v_event_notify_count_osag tt.ticket.event_notify_count_osag%TYPE;
    v_event_type_id tt.event_type.id%TYPE;
    v_event_type_group_id tt.event_type_group.id%TYPE;
    v_event_type_name varchar;
    v_peer_contact_name varchar;
    v_event_source_id numeric;
    v_notified_customer boolean;
    v_notified_osag boolean;
    v_local_contact_notified boolean;
    v_notif_event_is_public numeric;
    v_is_public_event numeric;
    v_email_message_subject varchar;
    v_email_message_body varchar;
    v_sms_message varchar;

    v_procedure_start timestamptz;
    v_send_noti_start timestamptz;
    v_elapsed_send_noti_cs numeric;
    v_elapsed_procedure_cs numeric;

    notify_rec RECORD;
BEGIN
    v_procedure_start := clock_timestamp();
    v_elapsed_send_noti_cs := 0;
    v_notified_customer := FALSE;
    v_notified_osag := FALSE;

    v_ticket_id := p_ticket_id;

    IF (v_ticket_id IS NULL) THEN
        -- S-NOTIFY-002 (site #1): STRICT, no local handler -- escalates to the outer
        -- WHEN OTHERS below (tt.event.id is the PK, so TOO_MANY_ROWS is impossible).
        SELECT e.ticket_id INTO STRICT v_ticket_id
        FROM tt.event e
        WHERE e.id = p_event_id;
    END IF;

    -- S-NOTIFY-003 (site #2): STRICT, no local handler. BOTH zero-row AND multi-row are
    -- reachable here -- mss.host2service's PK is (host_id, service_id), NOT unique on
    -- host_id, so a host mapped to >1 service makes this join return >1 row. Both
    -- escalate to the outer WHEN OTHERS.
    SELECT coalesce(e.host_id, t.host_id),
           coalesce(h2s.service_id, t.mss_service_id),
           e.type_id, e.eventdate, e.details_public, e.details_private, e.public_event,
           t.event_notify_count, t.event_notify_count_osag, t.customer_reference, t.subject,
           t.status_valid_until_date, t.emergency,
           et.name, coalesce(h.name, 'unspecified'), et.source
      INTO STRICT v_host_id, v_service_id, v_event_type_id, v_eventdate, v_details, v_details_private,
           v_is_public_event, v_event_notify_count_cust, v_event_notify_count_osag, v_customer_reference,
           v_ticket_subject, v_status_valid_until_date, v_emergency_flag,
           v_event_type_name, v_host_name, v_event_source_id
    FROM tt.event e
    JOIN tt.ticket t ON t.id = e.ticket_id
    JOIN tt.event_type et ON e.type_id = et.id
    LEFT JOIN mss.host h ON h.id = coalesce(e.host_id, t.host_id)
    LEFT JOIN mss.host2service h2s ON h2s.host_id = coalesce(e.host_id, t.host_id)
    WHERE e.id = p_event_id;

    -- S-NOTIFY-004: normal early exit (both counters capped AND the event is automatic).
    IF (v_event_notify_count_cust >= max_event_notify_count
        AND v_event_notify_count_osag >= max_event_notify_count
        AND v_event_source_id = 1) THEN
        CALL osag.osag_plog_debug(s_prefix || 'No more notifications for this ticket for automatic events because max notify count reached: ' || max_event_notify_count);
        RETURN;
    END IF;

    v_event_subject := substr(v_details, 1, 100);
    IF (strpos(coalesce(v_event_subject, ''), chr(10)) > 0) THEN
        v_event_subject := substr(v_event_subject, 1, strpos(v_event_subject, chr(10)) - 1);
    END IF;

    -- S-NOTIFY-005 (site #3): only for event type 50020. STRICT + its own local
    -- `WHEN NO_DATA_FOUND THEN NULL` (Oracle line 387) -- the lookup is simply skipped and
    -- v_event_type_name keeps its unmodified value.
    IF (v_event_type_id = 50020) THEN
        BEGIN
            SELECT c.firstname || ' ' || c.lastname INTO STRICT v_peer_contact_name
            FROM stop.contact c, tt.event e
            WHERE e.id = p_event_id
              AND c.id = e.peer_contact_id;
            v_event_type_name := v_event_type_name || ': ' || v_peer_contact_name;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                NULL;
        END;
    END IF;

    -- S-NOTIFY-006: questions (50008) are never suppressed by an active service window.
    IF (NOT tt.osag_notify_is_notify_suppressor_active(v_host_id) OR v_event_type_id = 50008) THEN

        -- S-NOTIFY-007 (site #4): STRICT, no local handler -> outer WHEN OTHERS.
        SELECT t.company_id, t.type_id, t.worker_id
          INTO STRICT v_company_id, v_ticket_type_id, v_ticket_worker_id
        FROM tt.ticket t
        WHERE t.id = v_ticket_id;

        -- S-NOTIFY-007 (site #5): STRICT, no local handler. Zero rows is reachable
        -- specifically because TT.TICKET.TYPE_ID has no NOT NULL constraint.
        SELECT ty.name INTO STRICT v_ticket_type_name
        FROM tt.ticket_type ty
        WHERE ty.id = v_ticket_type_id;

        IF (v_service_id IS NOT NULL) THEN
            -- S-NOTIFY-007 (site #6): STRICT, no local handler.
            SELECT s.company_unit_id, s.service_type_id
              INTO STRICT v_company_unit_id, v_service_type_id
            FROM mss.service s
            WHERE s.id = v_service_id;

            IF (v_company_unit_id IS NULL) THEN
                -- S-NOTIFY-007 (site #7): STRICT, no local handler.
                SELECT c.default_company_unit_id INTO STRICT v_company_unit_id
                FROM stop.company c, mss.service s
                WHERE s.id = v_service_id
                  AND s.company_id = c.id;
            END IF;
        ELSIF (v_company_id IS NOT NULL) THEN
            -- S-NOTIFY-007 (site #8): STRICT, no local handler.
            SELECT c.default_company_unit_id INTO STRICT v_company_unit_id
            FROM stop.company c
            WHERE v_company_id = c.id;
            v_service_type_id := NULL;
        ELSE
            v_company_unit_id := NULL;
            v_service_type_id := NULL;
        END IF;

        CALL osag.osag_plog_debug(s_prefix || 'event_type_name: ' || coalesce(v_event_type_name, '')
            || ', host.id: ' || coalesce(v_host_id::text, '') || ', company_id: ' || coalesce(v_company_id::text, '')
            || ', service_id: ' || coalesce(v_service_id::text, '') || ', company_unit_id: ' || coalesce(v_company_unit_id::text, '')
            || ', service_type_id: ' || coalesce(v_service_type_id::text, ''));

        v_notif_event_is_public := 1;  -- notification events are public by default

        -- S-NOTIFY-008: isp outage (10003) -> notify_isp, unconditionally within the gate.
        IF (v_event_type_id = 10003) THEN
            CALL tt.osag_notify__notify_isp(p_event_id,
                                            v_event_type_id,
                                            v_ticket_id,
                                            v_host_id,
                                            v_host_name,
                                            v_customer_reference);
        END IF;

        -- S-NOTIFY-009 (site #9): STRICT + a local NO_DATA_FOUND arm ONLY. TOO_MANY_ROWS
        -- IS structurally reachable here (tt.event_type2event_type_group's PK is
        -- (group_id, event_type_id), not unique on event_type_id) and is deliberately NOT
        -- caught locally -- it escalates to the outer WHEN OTHERS and aborts the rest of
        -- this procedure, including the notify-count updates below. Two tiers, exactly as
        -- Oracle: local handlers catch ONLY what the Oracle source says they catch.
        BEGIN
            SELECT etg.event_type_group_id INTO STRICT v_event_type_group_id
            FROM tt.event e, tt.event_type2event_type_group etg
            WHERE e.id = p_event_id
              AND e.type_id = etg.event_type_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_event_type_group_id := NULL;
        END;

        -- S-NOTIFY-010: local-contact notification only for connectivity events (group 1)
        -- with a known host.
        IF (v_event_type_group_id = 1 AND v_host_id IS NOT NULL) THEN
            v_local_contact_notified := FALSE;
            CALL tt.osag_notify__notify_local_contacts(p_event_id,
                                                       v_event_type_id,
                                                       v_ticket_id,
                                                       v_host_id,
                                                       v_host_name,
                                                       v_customer_reference,
                                                       v_company_id,
                                                       v_service_id,
                                                       v_eventdate,
                                                       v_status_valid_until_date,
                                                       v_ticket_subject,
                                                       v_local_contact_notified);
            -- S-NOTIFY-029: NULL (unassigned OUT on the handler path) is not-TRUE in both
            -- engines, so this check needs no extra guard.
            IF v_local_contact_notified THEN
                v_notified_customer := TRUE;
            END IF;
        END IF;

        -- S-NOTIFY-011: composition is UNCONDITIONAL once the gate passes; dispatch below
        -- is what's conditional.
        v_sms_message := tt.osag_notify__compose_sms_msg(v_ticket_id,
                                                         v_host_name,
                                                         v_event_type_id,
                                                         v_event_type_name,
                                                         v_eventdate,
                                                         v_status_valid_until_date,
                                                         v_ticket_subject,
                                                         v_emergency_flag);

        CALL tt.osag_notify__compose_email_msg(v_email_message_subject,  -- INOUT (Oracle OUT)
                                               v_email_message_body,     -- INOUT (Oracle OUT)
                                               v_ticket_id,
                                               v_ticket_subject,
                                               v_ticket_type_name,
                                               v_customer_reference,
                                               v_host_name,
                                               v_event_type_id,
                                               v_event_type_name,
                                               v_event_subject,
                                               v_eventdate,
                                               v_status_valid_until_date,
                                               v_details,
                                               v_details_private,
                                               v_emergency_flag,
                                               v_company_id);

        -- ---- notifications for NON-OSAG users ----
        IF (v_event_notify_count_cust >= max_event_notify_count AND v_event_source_id = 1) THEN
            CALL osag.osag_plog_debug(s_prefix || 'No more customer notifications for this ticket for automatic events because max notify count reached: ' || max_event_notify_count);
        ELSIF (v_details IS NULL OR v_is_public_event = 0) THEN
            NULL;  -- no public info, or a private event: do not notify customers
        ELSIF (v_service_id IS NULL) THEN
            -- S-NOTIFY-012: company-wide, role_id = 1 (mc-cust-monitor), non-OSAG logins.
            FOR notify_rec IN
                SELECT DISTINCT en.login_id, en.event_notification_type_id
                FROM tt.event_notification en, tt.event_type2event_type_group et2etg,
                     auth.login l, auth.permission p
                WHERE (en.event_type_id = v_event_type_id
                       OR (en.event_type_group_id = et2etg.event_type_group_id
                           AND et2etg.event_type_id = v_event_type_id))
                  AND en.login_id = l.id
                  AND l.company_id != 6
                  AND en.company_id = l.company_id
                  AND en.login_id = p.login_id
                  AND p.company_id = en.company_id
                  AND p.company_unit_id IS NULL AND p.service_id IS NULL AND p.user_unit_id IS NULL
                  AND p.role_id = 1
                  AND (en.company_unit_id IS NULL OR en.company_unit_id = v_company_unit_id)
                  AND en.service_id IS NULL AND en.service_type_id IS NULL
                  AND (en.company_id = v_company_id)
                  AND (en.ticket_id IS NULL OR en.ticket_id = v_ticket_id)
                  AND (en.ticket_type_id IS NULL OR en.ticket_type_id = v_ticket_type_id)
            LOOP
                v_notified_customer := TRUE;
                v_send_noti_start := clock_timestamp();
                CALL tt.osag_notify__send_notification_by_type(notify_rec.event_notification_type_id,
                                                               v_ticket_id,
                                                               notify_rec.login_id,
                                                               v_event_type_name,
                                                               v_host_name,
                                                               v_eventdate,
                                                               v_details,
                                                               v_email_message_subject,
                                                               v_email_message_body,
                                                               v_sms_message,
                                                               v_notif_event_is_public);
                v_elapsed_send_noti_cs := v_elapsed_send_noti_cs
                    + extract(epoch FROM (clock_timestamp() - v_send_noti_start)) * 100;
            END LOOP;
        ELSE
            -- S-NOTIFY-013: a specific service is known, so per-service access must be
            -- checked via auth.mv_service_access (role_id = 1) rather than company-wide
            -- permission alone.
            FOR notify_rec IN
                SELECT DISTINCT en.login_id, en.event_notification_type_id
                FROM tt.event_notification en, tt.event_type2event_type_group et2etg,
                     auth.login l, auth.mv_service_access mvsa
                WHERE (en.event_type_id = v_event_type_id
                       OR (en.event_type_group_id = et2etg.event_type_group_id
                           AND et2etg.event_type_id = v_event_type_id))
                  AND en.login_id = l.id
                  AND l.company_id != 6
                  AND en.company_id = l.company_id
                  AND en.login_id = mvsa.login_id
                  AND (mvsa.service_id = v_service_id AND mvsa.role_id = 1)
                  AND (en.company_id = v_company_id)
                  AND (en.service_id IS NULL OR en.service_id = v_service_id)
                  AND (en.company_unit_id IS NULL OR en.company_unit_id = v_company_unit_id)
                  AND (en.service_type_id IS NULL OR en.service_type_id = v_service_type_id)
                  AND (en.ticket_id IS NULL OR en.ticket_id = v_ticket_id)
                  AND (en.ticket_type_id IS NULL OR en.ticket_type_id = v_ticket_type_id)
            LOOP
                v_notified_customer := TRUE;
                v_send_noti_start := clock_timestamp();
                CALL tt.osag_notify__send_notification_by_type(notify_rec.event_notification_type_id,
                                                               v_ticket_id,
                                                               notify_rec.login_id,
                                                               v_event_type_name,
                                                               v_host_name,
                                                               v_eventdate,
                                                               v_details,
                                                               v_email_message_subject,
                                                               v_email_message_body,
                                                               v_sms_message,
                                                               v_notif_event_is_public);
                v_elapsed_send_noti_cs := v_elapsed_send_noti_cs
                    + extract(epoch FROM (clock_timestamp() - v_send_noti_start)) * 100;
            END LOOP;
        END IF;

        -- ---- notifications for OSAG users ----
        IF (v_event_notify_count_osag >= max_event_notify_count AND v_event_source_id = 1) THEN
            CALL osag.osag_plog_debug(s_prefix || 'No more notifications for OSAG employees for this ticket for automatic events because max notify count reached: ' || max_event_notify_count);
        ELSE
            -- S-NOTIFY-014: OSAG-staff notifications on a NON-OSAG company's ticket are
            -- marked PRIVATE -- customers must never see that OSAG staff were separately
            -- notified about their own ticket.
            IF (v_company_id IS NOT NULL AND v_company_id != 6) THEN
                v_notif_event_is_public := 0;
            END IF;

            FOR notify_rec IN
                SELECT DISTINCT en.login_id, en.event_notification_type_id
                FROM tt.event_notification en, tt.event e, tt.event_type2event_type_group et2etg,
                     auth.login l, auth.permission p
                WHERE e.id = p_event_id
                  AND (en.event_type_id = e.type_id
                       OR (en.event_type_group_id = et2etg.event_type_group_id
                           AND et2etg.event_type_id = e.type_id))
                  AND en.login_id = l.id
                  AND l.company_id = 6
                  AND l.id = p.login_id
                  AND p.role_id = 6
                  AND (en.company_id IS NULL OR en.company_id = v_company_id)
                  AND (en.service_id IS NULL OR en.service_id = v_service_id)
                  AND (en.company_unit_id IS NULL OR en.company_unit_id = v_company_unit_id)
                  AND (en.service_type_id IS NULL OR en.service_type_id = v_service_type_id)
                  AND (en.ticket_id IS NULL OR en.ticket_id = v_ticket_id)
                  AND (en.ticket_type_id IS NULL OR en.ticket_type_id = v_ticket_type_id)
                  AND (en.regexp IS NULL OR e.details_public ~ en.regexp)
                  AND (en.only_if_worker = 0 OR l.contact_id = v_ticket_worker_id)
            LOOP
                v_notified_osag := TRUE;
                v_send_noti_start := clock_timestamp();
                CALL tt.osag_notify__send_notification_by_type(notify_rec.event_notification_type_id,
                                                               v_ticket_id,
                                                               notify_rec.login_id,
                                                               v_event_type_name,
                                                               v_host_name,
                                                               v_eventdate,
                                                               v_details,
                                                               v_email_message_subject,
                                                               v_email_message_body,
                                                               v_sms_message,
                                                               v_notif_event_is_public);
                v_elapsed_send_noti_cs := v_elapsed_send_noti_cs
                    + extract(epoch FROM (clock_timestamp() - v_send_noti_start)) * 100;
            END LOOP;
        END IF;
    END IF;

    -- S-NOTIFY-015: customer notify-count bump; at exactly 5, a PUBLIC "no more
    -- notifications" ticket event.
    IF v_notified_customer THEN
        IF (v_event_notify_count_cust IS NULL) THEN
            v_event_notify_count_cust := 1;
        ELSE
            v_event_notify_count_cust := v_event_notify_count_cust + 1;
        END IF;

        UPDATE tt.ticket SET event_notify_count = v_event_notify_count_cust WHERE id = v_ticket_id;

        IF (v_event_notify_count_cust = max_event_notify_count) THEN
            INSERT INTO tt.event (id, type_id, ticket_id, eventdate, details_public)
            VALUES (nextval('tt.event_sequence'),
                    20010, v_ticket_id,
                    statement_timestamp(),
                    'notification limit (' || max_event_notify_count || ') reached' || chr(10) ||
                    'There will be no more notifications for system events added to this ticket.');
        END IF;
    END IF;

    -- S-NOTIFY-016: the identical pattern for OSAG staff, except the limit event is
    -- inserted as a PRIVATE event (explicit public_event = 0).
    IF v_notified_osag THEN
        IF (v_event_notify_count_osag IS NULL) THEN
            v_event_notify_count_osag := 1;
        ELSE
            v_event_notify_count_osag := v_event_notify_count_osag + 1;
        END IF;

        UPDATE tt.ticket SET event_notify_count_osag = v_event_notify_count_osag WHERE id = v_ticket_id;

        IF (v_event_notify_count_osag = max_event_notify_count) THEN
            INSERT INTO tt.event (id, type_id, ticket_id, eventdate, details_private, public_event)
            VALUES (nextval('tt.event_sequence'),
                    20010, v_ticket_id,
                    statement_timestamp(),
                    'notification limit (' || max_event_notify_count || ') reached' || chr(10) ||
                    'There will be no more notifications for OSAG employees for system events added to this ticket.',
                    0);
        END IF;
    END IF;

    -- S-NOTIFY-017: purely observational perf logging, no behavioral/data effect.
    v_elapsed_procedure_cs := extract(epoch FROM (clock_timestamp() - v_procedure_start)) * 100;
    IF ((v_elapsed_procedure_cs - v_elapsed_send_noti_cs) > elapsed_time_barrier) THEN
        CALL osag.osag_plog_warning(s_prefix || 'procedure elapsed time ('
            || round((v_elapsed_procedure_cs - v_elapsed_send_noti_cs) * 10) || 'ms) exceeded the barrier ('
            || (elapsed_time_barrier * 10) || 'ms), the queries in this procedure should be optimized');
    END IF;

EXCEPTION
    -- S-NOTIFY-001: THE outer swallow. Logs twice, never re-raises. Removing this would
    -- start raising into ticket-update transactions that Oracle never did.
    WHEN OTHERS THEN
        CALL osag.osag_plog_warning(s_prefix || 'sending of notification for event ID '
            || coalesce(p_event_id::text, '') || ' and ticket ID ' || coalesce(p_ticket_id::text, '') || ' failed');
        CALL osag.osag_plog_warning(s_prefix || 'exception: ' || SQLERRM);
END;
$fn$;
