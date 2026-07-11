"""
Unit tests for migration/mapping/name_map.py (the name-mapping SSOT generator, INV-03).

Written FIRST per the plan's TDD requirement: these must fail (ModuleNotFoundError)
before name_map.py exists, then pass once it is implemented.

Behaviors 1-8 and 15 are pinned against the real `migration/analyze/inventory.json`
(itself derived from real ddl/src). Behaviors 9-13 (the collision gate) are driven
against synthetic in-memory row fixtures -- constructed directly as name_map's own
row-dict shape -- so every collision class can be provoked deterministically without
mutating the real inventory/artifact, per the plan's instruction.
"""
from __future__ import annotations

import contextlib
import csv
import io
import json
import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
MAPPING_DIR = REPO_ROOT / "migration" / "mapping"
ANALYZE_DIR = REPO_ROOT / "migration" / "analyze"
INVENTORY_PATH = ANALYZE_DIR / "inventory.json"

sys.path.insert(0, str(MAPPING_DIR))
sys.path.insert(0, str(ANALYZE_DIR))

import name_map  # noqa: E402


def load_real_inventory():
    return json.loads(INVENTORY_PATH.read_text())


def find_object(objects, schema, name, kind=None):
    for o in objects:
        if o["schema"].upper() == schema.upper() and o["name"].upper() == name.upper():
            if kind is None or o["kind"] == kind:
                return o
    return None


def rows_by_kind(rows, kind):
    return [r for r in rows if r["kind"] == kind]


class TestNameDerivation(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.inventory = load_real_inventory()
        cls.rows, cls.no_public_routines = name_map.build_rows(cls.inventory)

    def test_01_package_routine_flattening(self):
        # TICKETEVOLUTION.CALCULATOR.materialize_tickev -> ticketevolution.calculator_materialize_tickev
        row = next(
            r
            for r in self.rows
            if r["kind"] == "package_routine"
            and r["oracle_schema"] == "TICKETEVOLUTION"
            and r["oracle_package"] == "CALCULATOR"
            and r["oracle_object"].lower() == "materialize_tickev"
        )
        self.assertEqual(row["pg_schema"], "ticketevolution")
        self.assertEqual(row["pg_object_name"], "calculator_materialize_tickev")

    def test_02_standalone_procedure_no_package_prefix(self):
        # SYS.decomAuthHost -> sys.decomauthhost, no package prefix
        row = next(r for r in self.rows if r["kind"] == "procedure" and r["oracle_schema"] == "SYS")
        self.assertEqual(row["oracle_object"].upper(), "DECOMAUTHHOST")
        self.assertEqual(row["pg_schema"], "sys")
        self.assertEqual(row["pg_object_name"], "decomauthhost")
        self.assertEqual(row["oracle_package"], "")

    def test_03_trigger_produces_trigger_and_trigger_function_rows(self):
        trig_rows = [
            r
            for r in self.rows
            if r["oracle_schema"] == "APPID"
            and r["oracle_object"].upper() == "T_INTERFACE_PS_LINK_CLASS_SYNC"
        ]
        kinds = sorted(r["kind"] for r in trig_rows)
        self.assertEqual(kinds, ["trigger", "trigger_function"])
        trig = next(r for r in trig_rows if r["kind"] == "trigger")
        fn = next(r for r in trig_rows if r["kind"] == "trigger_function")
        self.assertEqual(trig["pg_object_name"], "t_interface_ps_link_class_sync")
        self.assertEqual(fn["pg_object_name"], "t_interface_ps_link_class_sync_fn")
        self.assertEqual(trig["pg_schema"], "appid")
        self.assertEqual(fn["pg_schema"], "appid")

    def test_04_type_no_prefix(self):
        row = next(
            r
            for r in self.rows
            if r["kind"] == "type"
            and r["oracle_schema"] == "MCDB_MONITOR"
            and r["oracle_object"].upper() == "CONSISTENCY_CHECK_RESULT_TYPE"
        )
        self.assertEqual(row["pg_schema"], "mcdb_monitor")
        self.assertEqual(row["pg_object_name"], "consistency_check_result_type")

    def test_05_synonym_carried_and_empty_when_absent(self):
        # OSAG.OSAG_PLOG's rows carry its declared public synonym "plog"
        plog_rows = [r for r in self.rows if r["oracle_schema"] == "OSAG" and r["oracle_package"] == "OSAG_PLOG"]
        self.assertTrue(plog_rows)
        self.assertTrue(all(r["oracle_synonym"] == "plog" for r in plog_rows))

        # MSS.OSAG_IP's rows carry its declared public synonym "OSAG_IP"
        ip_rows = [r for r in self.rows if r["oracle_schema"] == "MSS" and r["oracle_package"] == "OSAG_IP"]
        self.assertTrue(ip_rows)
        self.assertTrue(all(r["oracle_synonym"] == "OSAG_IP" for r in ip_rows))

        # A package with no public synonym (e.g. TICKETEVOLUTION.CALCULATOR) yields
        # an empty string, never a missing column/key.
        calc_rows = [r for r in self.rows if r["oracle_schema"] == "TICKETEVOLUTION" and r["oracle_package"] == "CALCULATOR"]
        self.assertTrue(calc_rows)
        for r in calc_rows:
            self.assertIn("oracle_synonym", r)
            self.assertEqual(r["oracle_synonym"], "")


class TestCoverage(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.inventory = load_real_inventory()
        cls.rows, cls.no_public_routines = name_map.build_rows(cls.inventory)

    def test_06_every_public_routine_has_exactly_one_row_bidirectional(self):
        total_public_routines = sum(
            len(o["routines"]) for o in self.inventory["objects"] if o["kind"] == "package"
        )
        pkg_routine_rows = rows_by_kind(self.rows, "package_routine")
        self.assertEqual(len(pkg_routine_rows), total_public_routines)

        # every row traces back to a real routine in the inventory
        routine_keys = set()
        for o in self.inventory["objects"]:
            if o["kind"] != "package":
                continue
            for r in o["routines"]:
                routine_keys.add((o["schema"], o["package"], r["name"].upper(), r["signature"]))
        for row in pkg_routine_rows:
            key = (row["oracle_schema"], row["oracle_package"], row["oracle_object"].upper(), row["oracle_signature"])
            self.assertIn(key, routine_keys)

    def test_07_private_routines_produce_no_row(self):
        # GUMA2.OSAG_GUMA has a real private routine 'dump_to_hw_history' (verified
        # on disk before writing this test) that must never surface as a row.
        pkg_rows = [
            r for r in self.rows if r["kind"] == "package_routine" and r["oracle_package"] == "OSAG_GUMA"
        ]
        names = {r["oracle_object"].lower() for r in pkg_rows}
        self.assertNotIn("dump_to_hw_history", names)

        pkg = find_object(self.inventory["objects"], "GUMA2", "OSAG_GUMA", kind="package")
        self.assertTrue(any(pr["name"].lower() == "dump_to_hw_history" for pr in pkg["private_routines"]))

    def test_08_all_53_triggers_produce_53_plus_53_rows(self):
        self.assertEqual(len(rows_by_kind(self.rows, "trigger")), 53)
        self.assertEqual(len(rows_by_kind(self.rows, "trigger_function")), 53)


def make_row(oracle_schema, oracle_package, oracle_object, oracle_signature, pg_schema, pg_object_name,
             kind="package_routine", source_path="synthetic.sql", source_line=1):
    return {
        "oracle_schema": oracle_schema,
        "oracle_package": oracle_package,
        "oracle_object": oracle_object,
        "oracle_signature": oracle_signature,
        "oracle_synonym": "",
        "kind": kind,
        "pg_schema": pg_schema,
        "pg_object_name": pg_object_name,
        "pg_kind": "procedure",
        "is_overload": False,
        "overridden": False,
        "source_path": source_path,
        "source_line": source_line,
    }


class TestCollisionGate(unittest.TestCase):
    def test_09_same_package_distinct_signatures_is_legitimate_overload(self):
        rows = [
            make_row("TT", "TICKET_INTERFACE", "change_label", "CHANGE_LABEL(NUMBER,NUMBER)", "tt", "ticket_interface_change_label"),
            make_row("TT", "TICKET_INTERFACE", "change_label", "CHANGE_LABEL(NUMBER,NUMBER,NUMBER,NUMBER)", "tt", "ticket_interface_change_label"),
        ]
        ok, messages = name_map.apply_collision_gate(rows, [])
        self.assertTrue(ok, messages)
        self.assertTrue(all(r["is_overload"] for r in rows))

        # Assert the real TT.TICKET_INTERFACE change_label pair is classified exactly this way.
        inventory = load_real_inventory()
        real_rows, _ = name_map.build_rows(inventory)
        ok2, messages2 = name_map.apply_collision_gate(real_rows, [])
        self.assertTrue(ok2, messages2)
        change_label_rows = [
            r for r in real_rows if r["oracle_package"] == "TICKET_INTERFACE" and r["oracle_object"].lower() == "change_label"
        ]
        self.assertEqual(len(change_label_rows), 2)
        self.assertTrue(all(r["is_overload"] for r in change_label_rows))

    def test_10_cross_package_prefix_ambiguity_hard_fails_with_sources(self):
        # MC.MONITORING.state_foo vs MC.MONITORING_STATE.foo both flatten to
        # mc.monitoring_state_foo -- different packages, hard fail even though
        # the argument lists could differ.
        rows = [
            make_row("MC", "MONITORING", "state_foo", "STATE_FOO()", "mc", "monitoring_state_foo",
                     source_path="ddl/src/pkgb/mc_monitoring.sql", source_line=42),
            make_row("MC", "MONITORING_STATE", "foo", "FOO(NUMBER)", "mc", "monitoring_state_foo",
                     source_path="ddl/src/pkgb/mc_monitoring_state.sql", source_line=7),
        ]
        ok, messages = name_map.apply_collision_gate(rows, [])
        self.assertFalse(ok)
        joined = "\n".join(messages)
        self.assertIn("ddl/src/pkgb/mc_monitoring.sql:42", joined)
        self.assertIn("ddl/src/pkgb/mc_monitoring_state.sql:7", joined)

    def test_11_identical_signature_same_schema_hard_fails(self):
        rows = [
            make_row("MC", "PKG_A", "foo", "FOO(NUMBER)", "mc", "pkg_a_foo",
                     source_path="a.sql", source_line=1),
            make_row("MC", "PKG_B", "a_foo", "A_FOO(NUMBER)", "mc", "pkg_a_foo",
                     source_path="b.sql", source_line=2),
        ]
        ok, messages = name_map.apply_collision_gate(rows, [])
        self.assertFalse(ok)
        self.assertTrue(any("pkg_a_foo" in m for m in messages))

    def test_12_hard_collision_with_matching_override_resolves(self):
        rows = [
            make_row("MC", "MONITORING", "state_foo", "STATE_FOO()", "mc", "monitoring_state_foo",
                     source_path="a.sql", source_line=1),
            make_row("MC", "MONITORING_STATE", "foo", "FOO()", "mc", "monitoring_state_foo",
                     source_path="b.sql", source_line=2),
        ]
        overrides = [
            {
                "oracle_schema": "MC",
                "oracle_package": "MONITORING_STATE",
                "oracle_object": "foo",
                "oracle_signature": "FOO()",
                "pg_object_name": "monitoring_state_foo_v2",
                "reason": "resolve MONITORING/MONITORING_STATE prefix collision",
            }
        ]
        ok, messages = name_map.apply_collision_gate(rows, overrides)
        self.assertTrue(ok, messages)
        overridden_row = next(r for r in rows if r["oracle_package"] == "MONITORING_STATE")
        self.assertEqual(overridden_row["pg_object_name"], "monitoring_state_foo_v2")
        self.assertTrue(overridden_row["overridden"])

    def test_13_stale_override_fails(self):
        rows = [
            make_row("MC", "MONITORING", "bar", "BAR()", "mc", "monitoring_bar"),
        ]
        overrides = [
            {
                "oracle_schema": "MC",
                "oracle_package": "MONITORING_STATE",
                "oracle_object": "foo",
                "oracle_signature": "FOO()",
                "pg_object_name": "monitoring_state_foo_v2",
                "reason": "no longer a real collision",
            }
        ]
        ok, messages = name_map.apply_collision_gate(rows, overrides)
        self.assertFalse(ok)
        self.assertTrue(any("stale" in m.lower() or "no existing" in m.lower() or "matches no" in m.lower() for m in messages))

    def test_14_check_exits_zero_against_real_inventory(self):
        # main() prints to stdout; swallow it here so this test doesn't
        # interleave with unittest's own stderr summary when the whole suite
        # is run under `... 2>&1 | tail -3` (the plan's own verify command).
        with contextlib.redirect_stdout(io.StringIO()):
            rc = name_map.main(["--check"])
        self.assertEqual(rc, 0)


class TestConsumerContract(unittest.TestCase):
    def test_15_csv_loads_with_no_ragged_rows(self):
        with contextlib.redirect_stdout(io.StringIO()):
            rc = name_map.main([])
        self.assertEqual(rc, 0)
        with open(name_map.DEFAULT_OUTPUT_PATH, newline="") as f:
            reader = csv.DictReader(f)
            self.assertEqual(list(reader.fieldnames), name_map.COLUMNS)
            row_count = 0
            for row in reader:
                row_count += 1
                for col in name_map.COLUMNS:
                    self.assertIn(col, row)
                    self.assertIsNotNone(row[col])
            self.assertGreater(row_count, 0)


if __name__ == "__main__":
    unittest.main()
