-- migration/test/regress/sql/tt__event_interface__errors.sql
-- verifies: S-EVENT-043, S-EVENT-044
--
-- Expected-output harness half: pins the EXACT psql error text (including SQLSTATE via
-- the plain error message) for two of TT.EVENT_INTERFACE's deliberately-unhandled
-- propagation paths -- demote_event and promote_event share the identical shape (a
-- 1:1 tt.event x tt.ticket PK join, zero EXCEPTION blocks anywhere in either routine).
-- RED right now because neither tt.event_interface_demote_event nor
-- tt.event_interface_promote_event exists yet -- run with ON_ERROR_STOP=0 (the
-- harness's expected-output convention), so both statements run and each error is
-- captured independently.
--
-- Per the golden-file convention established in 02-04 (see
-- .planning/phases/02-spec-method-test-harness-pilot/02-04-SUMMARY.md, "Decisions
-- Made"): the expected/*.out golden below is authored from the SPEC's expected
-- SUBSTANCE (PL/pgSQL's own default STRICT error text), not from today's actual output
-- ("function ... does not exist"). Today's mismatch against that golden IS the RED
-- proof itself; reconciling only the CONTEXT line's internal function/line-number
-- formatting (never the substance) is deferred to whichever plan lands the real
-- translation.

-- S-EVENT-043: demote_event has zero EXCEPTION blocks anywhere in its body -- a
-- nonexistent p_event_id propagates NO_DATA_FOUND unhandled, which PL/pgSQL's own
-- STRICT default renders as the literal text "no data found". The preceding
-- `UPDATE tt.event SET demoted = 1 WHERE id = p_event_id` is unconditional and
-- zero-row-tolerant (no row-count check), so it is the SUBSEQUENT SELECT INTO that
-- actually surfaces the bad-id case.
CALL tt.event_interface_demote_event(900699999, NULL);

-- S-EVENT-044: promote_event is the exact mirror of demote_event -- same PK-join
-- shape, same total absence of an EXCEPTION block, same unhandled NO_DATA_FOUND.
CALL tt.event_interface_promote_event(900699999, NULL);
