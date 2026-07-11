"""
Unit tests for migration/analyze/inventory.py.

Written FIRST per the plan's TDD requirement: these must fail (ModuleNotFoundError)
before inventory.py exists, then pass once it is implemented.

Tests are pinned against real files under ddl/src wherever the plan names a specific
fixture; a couple of behaviors (package_state CONSTANT-vs-mutable distinction, the
--check gate's ability to actually fail) are additionally exercised against small
synthetic snippets / a deliberately mutated in-memory result, because they need a
fixture shape the real corpus doesn't happen to contain (see inline notes).
"""
from __future__ import annotations

import copy
import re
import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
ANALYZE_DIR = REPO_ROOT / "migration" / "analyze"
DDL_SRC = REPO_ROOT / "ddl" / "src"

sys.path.insert(0, str(ANALYZE_DIR))

import plsql_lex  # noqa: E402
import inventory  # noqa: E402


def find_object(objects, schema, name, kind=None):
    for o in objects:
        if o["schema"].upper() == schema.upper() and o["name"].upper() == name.upper():
            if kind is None or o["kind"] == kind:
                return o
    return None


class TestRoutineExtractionFromSpecs(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.result = inventory.build_inventory(DDL_SRC)

    def test_01_mss_osag_ip_seven_public_functions(self):
        pkg = find_object(self.result["objects"], "MSS", "OSAG_IP", kind="package")
        self.assertIsNotNone(pkg)
        self.assertEqual(len(pkg["routines"]), 7)
        self.assertTrue(all(r["kind"] == "FUNCTION" for r in pkg["routines"]))
        self.assertTrue(all(r["deterministic"] is True for r in pkg["routines"]))
        ip2num = next(r for r in pkg["routines"] if r["name"].lower() == "ip2num")
        self.assertEqual(len(ip2num["params"]), 1)
        self.assertEqual(ip2num["params"][0]["name"], "p_string")
        self.assertIn("VARCHAR2", ip2num["params"][0]["type"].upper())
        self.assertIn("NUMBER", ip2num["returns"].upper())

    def test_02_tt_ticket_interface_change_label_overload(self):
        pkg = find_object(self.result["objects"], "TT", "TICKET_INTERFACE", kind="package")
        self.assertIsNotNone(pkg)
        change_labels = [r for r in pkg["routines"] if r["name"].lower() == "change_label"]
        self.assertEqual(len(change_labels), 2)
        signatures = {r["signature"] for r in change_labels}
        self.assertEqual(len(signatures), 2, "overloads must carry distinct signatures")
        param_counts = sorted(len(r["params"]) for r in change_labels)
        self.assertEqual(param_counts, [2, 4])

    def test_03_param_order_name_mode_type_default_preserved(self):
        pkg = find_object(self.result["objects"], "TT", "TICKET_INTERFACE", kind="package")
        newticket_new = next(r for r in pkg["routines"] if r["name"].lower() == "newticket_new")
        params = newticket_new["params"]
        # first two params are OUT NUMBER, declared in this exact order
        self.assertEqual(params[0]["name"], "p_ticket_id")
        self.assertEqual(params[0]["mode"], "OUT")
        self.assertFalse(params[0]["has_default"])
        self.assertEqual(params[1]["name"], "p_event_id")
        self.assertEqual(params[1]["mode"], "OUT")
        # p_details_private has a DEFAULT NULL
        details_private = next(p for p in params if p["name"] == "p_details_private")
        self.assertEqual(details_private["mode"], "IN")
        self.assertTrue(details_private["has_default"])
        # p_ticket_type_id has no default, mode defaults to IN
        ticket_type = next(p for p in params if p["name"] == "p_ticket_type_id")
        self.assertEqual(ticket_type["mode"], "IN")
        self.assertFalse(ticket_type["has_default"])


class TestSemanticMarkers(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.result = inventory.build_inventory(DDL_SRC)

    def test_04_osag_plog_autonomous_transaction(self):
        pkg = find_object(self.result["objects"], "OSAG", "OSAG_PLOG", kind="package")
        self.assertIsNotNone(pkg)
        self.assertTrue(pkg["autonomous_transaction"])
        self.assertGreaterEqual(len(pkg["autonomous_transaction_sites"]), 1)

    def test_05_mcdb_checks_consistency_autonomous_and_dbms_sql(self):
        pkg = find_object(self.result["objects"], "MCDB_CHECKS", "CONSISTENCY", kind="package")
        self.assertIsNotNone(pkg)
        self.assertTrue(pkg["autonomous_transaction"])
        dbms_sql_calls = [c for c in pkg["oracle_pkg_calls"] if c["family"] == "DBMS_SQL"]
        self.assertGreater(len(dbms_sql_calls), 0)

    def test_06_commit_present_and_absent_reported_correctly(self):
        plog = find_object(self.result["objects"], "OSAG", "OSAG_PLOG", kind="package")
        self.assertTrue(plog["has_commit"])
        self.assertGreaterEqual(len(plog["has_commit_sites"]), 1)
        # mss.osag_ip has no transaction control at all
        ip_pkg = find_object(self.result["objects"], "MSS", "OSAG_IP", kind="package")
        self.assertFalse(ip_pkg["has_commit"])
        self.assertFalse(ip_pkg["has_rollback"])

    def test_07_package_state_empty_not_absent_for_constants_only(self):
        # GUMA2.SECONDARY_ISP's body declares only an EXCEPTION and two CONSTANTs
        # at package level, no mutable variable (verified on disk before writing
        # this test) -- package_state must be an empty list, not a missing key.
        pkg = find_object(self.result["objects"], "GUMA2", "SECONDARY_ISP", kind="package")
        self.assertIsNotNone(pkg)
        self.assertIn("package_state", pkg)
        self.assertEqual(pkg["package_state"], [])
        self.assertIsInstance(pkg["has_init_block"], bool)

        # Supplementary: directly exercise the underlying helper to prove it
        # actually distinguishes CONSTANT from mutable declarations (this repo's
        # corpus, per PITFALLS.md Pitfall 5, happens to contain no real mutable
        # package-level variable, so the discriminating case is demonstrated here
        # against a small synthetic declare-section instead of a repo file).
        synthetic = (
            "  E_ABORT EXCEPTION;\n"
            "  C_LIMIT CONSTANT NUMBER := 5;\n"
            "  g_cache_hits NUMBER := 0;\n"
        )
        state = inventory.find_package_state(synthetic)
        names = {s["name"] for s in state}
        self.assertEqual(names, {"g_cache_hits"})

    def test_08_raise_application_error_stripped_below_naive_corpus_wide(self):
        naive_total = 0
        for sub in ("pkg", "pkgb", "proc", "triggers", "types"):
            for f in (DDL_SRC / sub).glob("*.sql"):
                naive_total += len(re.findall(r"RAISE_APPLICATION_ERROR", f.read_text(), re.IGNORECASE))
        stripped_total = 0
        for sub in ("pkg", "pkgb", "proc", "triggers", "types"):
            for f in (DDL_SRC / sub).glob("*.sql"):
                stripped = plsql_lex.strip_noise(f.read_text())
                stripped_total += len(re.findall(r"RAISE_APPLICATION_ERROR", stripped.clean, re.IGNORECASE))
        self.assertLess(stripped_total, naive_total)
        self.assertEqual(naive_total, 49)  # ground truth from PLAN.md, reconfirmed here

    def test_09_type_refs_dictionary_vs_project(self):
        plog = find_object(self.result["objects"], "OSAG", "OSAG_PLOG", kind="package")
        dictionary_refs = [t for t in plog["type_refs"] if t["against"] == "dictionary"]
        self.assertTrue(any("all_source" in t["ref"].lower() for t in dictionary_refs))
        project_refs = [t for t in plog["type_refs"] if t["against"] == "project"]
        self.assertTrue(len(project_refs) >= 0)  # field must exist and be a list either way
        self.assertIsInstance(plog["type_refs"], list)


class TestRawCallReferences(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.result = inventory.build_inventory(DDL_SRC)

    def test_10_qualified_three_part_call_captured(self):
        auth = find_object(self.result["objects"], "AUTH", "OSAG_AUTH", kind="package")
        self.assertIsNotNone(auth)
        qualified = [c for c in auth["calls_out_raw"] if c["shape"] == "qualified"]
        texts = [c["text"].upper() for c in qualified]
        self.assertTrue(
            any("TT.OSAG_NOTIFY.DELETE_NOTIFICATIONS_FOR_LOGIN" in t for t in texts),
            f"expected qualified TT.OSAG_NOTIFY call, got: {texts}",
        )

    def test_11_bare_two_part_call_captured(self):
        auth = find_object(self.result["objects"], "AUTH", "OSAG_AUTH", kind="package")
        bare = [c for c in auth["calls_out_raw"] if c["shape"] == "bare"]
        texts = [c["text"].lower() for c in bare]
        self.assertTrue(
            any(t.startswith("plog.") for t in texts),
            f"expected a bare plog.* call, got: {texts}",
        )

    def test_12_comment_only_reference_excluded(self):
        snippet = (
            "-- FOO.BAR.baz() is the old deprecated call, no longer used\n"
            "BEGIN\n"
            "    FOO.BAR.baz();\n"
            "END;\n"
        )
        stripped = plsql_lex.strip_noise(snippet)
        refs = inventory.extract_calls_out_raw(stripped.clean)
        self.assertEqual(len(refs), 1)
        self.assertEqual(refs[0]["line"], 3)

    def test_13_raw_reference_carries_line_number(self):
        snippet = "BEGIN\n\n    some.pkg.routine();\nEND;\n"
        stripped = plsql_lex.strip_noise(snippet)
        refs = inventory.extract_calls_out_raw(stripped.clean)
        self.assertEqual(len(refs), 1)
        self.assertEqual(refs[0]["line"], 3)
        self.assertEqual(refs[0]["shape"], "qualified")


class TestStaticResolutionFlagging(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.result = inventory.build_inventory(DDL_SRC)

    def test_14_dynamic_sql_objects_flagged_incomplete(self):
        known_incomplete = [
            ("SYS", "OSAG_TABLE_REDEFINITION"),
            ("REPORT", "OSAG_CHANNEL"),
            ("TT", "EVENT_INTERFACE"),
            ("MCDB_CHECKS", "CONSISTENCY"),
        ]
        for schema, name in known_incomplete:
            pkg = find_object(self.result["objects"], schema, name, kind="package")
            self.assertIsNotNone(pkg, f"{schema}.{name} not found in inventory")
            self.assertEqual(pkg["static_resolution"], "incomplete")
            self.assertTrue(len(pkg["static_resolution_reasons"]) > 0)

        clean_pkg = find_object(self.result["objects"], "MSS", "OSAG_IP", kind="package")
        self.assertEqual(clean_pkg["static_resolution"], "complete")
        self.assertEqual(clean_pkg["static_resolution_reasons"], [])


class TestReconciliation(unittest.TestCase):
    def test_15_check_passes_then_fails_when_object_removed(self):
        result = inventory.build_inventory(DDL_SRC)
        expected = inventory.load_expected_counts(ANALYZE_DIR / "expected_counts.json")
        ok, messages = inventory.reconcile(result, expected)
        self.assertTrue(ok, f"reconcile should pass against current tree; messages={messages}")

        mutated = copy.deepcopy(result)
        # Remove one arbitrary package object -- the gate must be able to fail.
        removed = mutated["objects"].pop(
            next(i for i, o in enumerate(mutated["objects"]) if o["kind"] == "package")
        )
        ok2, messages2 = inventory.reconcile(mutated, expected)
        self.assertFalse(ok2, f"reconcile must fail once {removed['id']} is missing")
        self.assertTrue(len(messages2) > 0)


class TestCorpusWideCounts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.result = inventory.build_inventory(DDL_SRC)

    def test_16_top_level_object_counts(self):
        objs = self.result["objects"]
        self.assertEqual(len([o for o in objs if o["kind"] == "package"]), 48)
        self.assertEqual(len([o for o in objs if o["kind"] == "procedure"]), 2)
        self.assertEqual(len([o for o in objs if o["kind"] == "trigger"]), 53)
        self.assertEqual(len([o for o in objs if o["kind"] == "type"]), 2)

    def test_17_excluded_files_names_the_markdown_doc(self):
        self.assertIn("ticketing-interfaces.md", self.result["excluded_files"])

    def test_18_no_key_absent_on_package_objects(self):
        required_keys = {
            "routines",
            "has_commit",
            "has_rollback",
            "autonomous_transaction",
            "package_state",
            "oracle_pkg_calls",
            "calls_out_raw",
            "static_resolution",
        }
        for o in self.result["objects"]:
            if o["kind"] == "package":
                missing = required_keys - set(o.keys())
                self.assertEqual(missing, set(), f"{o['id']} missing keys: {missing}")

    def test_19_both_call_shapes_present_somewhere_in_corpus(self):
        objs = self.result["objects"]
        all_calls = [c for o in objs for c in o.get("calls_out_raw", [])]
        shapes = {c["shape"] for c in all_calls}
        self.assertIn("qualified", shapes)
        self.assertIn("bare", shapes)


if __name__ == "__main__":
    unittest.main()
