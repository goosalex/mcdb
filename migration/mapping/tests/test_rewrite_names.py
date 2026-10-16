"""Pins rewrite_names.py behaviour against the REAL name-map.csv (never a fixture map,
so a regression in the SSOT surfaces here too) plus a few synthetic strings."""
from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import rewrite_names as rn  # noqa: E402

REPO_ROOT = HERE.parents[2]


class RewriteNamesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.nm = rn.load_name_map()

    def rw(self, text: str, **kw) -> tuple[str, rn.Rewriter]:
        r = rn.Rewriter(self.nm, **kw)
        return r.rewrite(text), r

    # R1 ---------------------------------------------------------------
    def test_three_part_qualified(self):
        out, r = self.rw("tt.ticket_interface.change_status(p_ticket_id, 102, NULL, 'x');")
        self.assertEqual(out, "tt.ticket_interface_change_status(p_ticket_id, 102, NULL, 'x');")
        self.assertEqual(r.counts["R1"], 1)

    def test_three_part_case_and_whitespace(self):
        out, _ = self.rw("TT . Ticket_Interface .CHANGE_STATUS(1)")
        self.assertEqual(out, "tt.ticket_interface_change_status(1)")

    def test_three_part_quoted(self):
        out, _ = self.rw('"TT"."TICKET_INTERFACE"."CHANGE_STATUS"(1)')
        self.assertEqual(out, "tt.ticket_interface_change_status(1)")

    def test_escaped_dots_inside_regex_data(self):
        out, _ = self.rw(r"^tt\.escalation_interface\.escalate_os$")
        self.assertEqual(out, r"^tt\.escalation_interface_escalate_os$")

    def test_column_reference_untouched(self):
        # schema.table.column must never be mistaken for schema.package.object
        text = "SELECT t.id FROM tt.ticket t WHERE tt.ticket.id = 1 AND p_id tt.ticket.id%TYPE"
        out, r = self.rw(text)
        self.assertEqual(out, text)
        self.assertEqual(dict(r.counts), {})

    def test_overload_same_target(self):
        out, _ = self.rw("tt.ticket_interface.change_label(1,2); tt.ticket_interface.change_label(1,2,3);")
        self.assertEqual(out, "tt.ticket_interface_change_label(1,2); tt.ticket_interface_change_label(1,2,3);")

    # R2 ---------------------------------------------------------------
    def test_dynamic_prefix_before_quote(self):
        out, r = self.rw("v_proc := 'tt.escalation_interface.' || v_name;")
        self.assertEqual(out, "v_proc := 'tt.escalation_interface_' || v_name;")
        self.assertEqual(len(r.report["R2_dynamic_prefix"]), 1)

    def test_dynamic_prefix_in_stored_regexp(self):
        out, _ = self.rw(r"^tt\.escalation_interface\.(nop|escalate_(customer|os))$")
        self.assertEqual(out, r"^tt\.escalation_interface_(nop|escalate_(customer|os))$")

    # R3 ---------------------------------------------------------------
    def test_synonym(self):
        out, r = self.rw("plog.debug('x'); OSAG_IP.num2ip(v); osag_dbprop.get_string_by_host(1,'k');")
        self.assertEqual(out, "osag.osag_plog_debug('x'); mss.osag_ip_num2ip(v); mss.osag_dbprop_get_string_by_host(1,'k');")
        self.assertEqual(r.counts["R3"], 3)

    # R4 ---------------------------------------------------------------
    def test_bare_same_schema(self):
        out, r = self.rw("event_interface.addevent_new(v_event_id, v_ticket_id, 60001, v_host_id, 'a', 'b');")
        self.assertEqual(out, "tt.event_interface_addevent_new(v_event_id, v_ticket_id, 60001, v_host_id, 'a', 'b');")
        self.assertEqual(r.counts["R4"], 1)

    def test_bare_disabled(self):
        text = "event_interface.addevent_new(1)"
        out, _ = self.rw(text, bare=False)
        self.assertEqual(out, text)

    def test_bare_ambiguous_reported_not_rewritten(self):
        text = "osag_implication.get_implied_roles(1)"
        out, r = self.rw(text)
        # OSAG_IMPLICATION exists in AUTH and GUMA2: without --default-schema it stays
        self.assertEqual(out, text)
        self.assertTrue(r.has_unresolved)

    # R5 ---------------------------------------------------------------
    def test_block_to_call(self):
        out, r = self.rw("$dbh->do(q{BEGIN tt.util.check_ticket_status; END;});", blocks=True)
        self.assertEqual(out, "$dbh->do(q{CALL tt.util_check_ticket_status();});")
        out, _ = self.rw("BEGIN tt.ticket_interface.change_status(:1, :2, NULL, :3); END;", blocks=True)
        self.assertEqual(out, "CALL tt.ticket_interface_change_status(:1, :2, NULL, :3);")

    def test_block_not_rewritten_for_function(self):
        text = "BEGIN :r := mss.osag_ip.num2ip(:1); END;"
        out, _ = self.rw(text, blocks=True)
        self.assertEqual(out, "BEGIN :r := mss.osag_ip_num2ip(:1); END;")

    # P1 / P2 reports --------------------------------------------------
    def test_package_only_reference_reported(self):
        out, r = self.rw("GRANT EXECUTE ON tt.ticket_interface TO svc_api_ticketing;")
        self.assertEqual(out, "GRANT EXECUTE ON tt.ticket_interface TO svc_api_ticketing;")
        items = r.report["P1_package_only"]
        self.assertEqual(len(items), 1)
        self.assertIn("tt.ticket_interface_change_status", items[0]["expands_to"])
        self.assertTrue(r.has_unresolved)

    def test_unknown_member_reported(self):
        text = "l_hdrs osag_msg.smtp_headers_t;"
        out, r = self.rw(text)
        self.assertEqual(out, text)
        self.assertEqual(r.report["P2_unknown_member"][0]["package"], "osag.osag_msg")

    # Emitters ---------------------------------------------------------
    def test_emitters_roundtrip(self):
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            rn.emit_csv(self.nm, d / "m.csv")
            rn.emit_sed(self.nm, d / "m.sed")
            rn.emit_sql(self.nm, d / "m.sql")
            csv_text = (d / "m.csv").read_text()
            self.assertIn("tt.ticket_interface.change_status,tt.ticket_interface_change_status,procedure", csv_text)
            self.assertIn("plog.debug,osag.osag_plog_debug", csv_text)
            # the sed script must actually work with GNU sed on a sample
            sample = d / "s.txt"
            sample.write_text("x := TT.Ticket_Interface.change_status(1); plog.err('e'); 'tt.escalation_interface.' || v\n")
            subprocess.run(["sed", "-E", "-i", "-f", str(d / "m.sed"), str(sample)], check=True)
            self.assertEqual(sample.read_text(),
                             "x := tt.ticket_interface_change_status(1); osag.osag_plog_err('e'); 'tt.escalation_interface_' || v\n")
            self.assertIn("INSERT INTO pgmig.oracle_name_map", (d / "m.sql").read_text())

    # Real corpus smoke: every Oracle body rewrites without an unresolved R4 ----
    def test_real_tt_bodies_have_no_ambiguous_bare_refs(self):
        for f in sorted((REPO_ROOT / "ddl/src/pkgb").glob("tt_*.sql")):
            r = rn.Rewriter(self.nm)
            r.rewrite(f.read_text(), str(f))
            self.assertEqual(r.report.get("R4_ambiguous", []), [], f)


if __name__ == "__main__":
    unittest.main()
