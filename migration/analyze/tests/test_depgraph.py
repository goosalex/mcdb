"""
Unit tests for migration/analyze/depgraph.py (the dependency graph generator, INV-02).

Written FIRST per the plan's TDD requirement: these must fail (ModuleNotFoundError)
before depgraph.py exists, then pass once it is implemented.

Edge-resolution and flagging behaviors (1-9) are pinned against the real
inventory.json + name-map.csv. Wave/cycle behaviors that need a shape the real
corpus doesn't happen to contain (a simple 3-node chain, a 2-node mutual-recursion
pair) are driven with small synthetic node/edge lists passed directly to
compute_sccs()/assign_waves() -- per the plan's own wording ("on a synthetic graph
A->B->C..."). The reconciliation test (15) tampers an in-memory copy of the real
result, never the checked-in artifact.
"""
from __future__ import annotations

import contextlib
import io
import json
import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
ANALYZE_DIR = REPO_ROOT / "migration" / "analyze"
MAPPING_DIR = REPO_ROOT / "migration" / "mapping"
INVENTORY_PATH = ANALYZE_DIR / "inventory.json"
NAME_MAP_PATH = MAPPING_DIR / "name-map.csv"

sys.path.insert(0, str(ANALYZE_DIR))
sys.path.insert(0, str(MAPPING_DIR))

import depgraph  # noqa: E402


def load_real():
    inventory = json.loads(INVENTORY_PATH.read_text())
    name_map_rows = depgraph.load_name_map(NAME_MAP_PATH)
    return inventory, name_map_rows


def find_node(nodes, node_id):
    for n in nodes:
        if n["id"] == node_id:
            return n
    return None


def find_edge(edges, frm, to):
    for e in edges:
        if e["from"] == frm and e["to"] == to:
            return e
    return None


class TestEdgeResolutionBothShapes(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.inventory, cls.name_map_rows = load_real()
        cls.result = depgraph.build_graph(cls.inventory, cls.name_map_rows)

    def test_01_qualified_three_part_edge(self):
        edge = find_edge(self.result["edges"], "AUTH.OSAG_AUTH", "TT.OSAG_NOTIFY")
        self.assertIsNotNone(edge)
        self.assertEqual(edge["via"], "qualified")

    def test_02_synonym_two_part_edge_plog_has_many_inbound(self):
        inbound = [e for e in self.result["edges"] if e["to"] == "OSAG.OSAG_PLOG"]
        self.assertGreater(len(inbound), 10, "plog is the most-called package; if this is low, synonym resolution is broken")
        self.assertTrue(any(e["via"] == "synonym" for e in inbound))

    def test_03_same_schema_bare_reference(self):
        edge = find_edge(self.result["edges"], "TT.EVENT_INTERFACE", "TT.TICKET_INTERFACE")
        self.assertIsNotNone(edge)
        self.assertIn(edge["via"], ("qualified", "same_schema"))
        # at least one edge anywhere resolves via same_schema
        self.assertTrue(any(e["via"] == "same_schema" for e in self.result["edges"]))

    def test_04_dbms_utl_family_produces_no_edge(self):
        node = find_node(self.result["nodes"], "AUTH.OSAG_AUTH")
        self.assertIsNotNone(node)
        for ref in node["unresolved_refs"]:
            self.assertFalse(ref["text"].upper().startswith("DBMS_"))
            self.assertFalse(ref["text"].upper().startswith("UTL_"))
        for e in self.result["edges"]:
            self.assertFalse(e["to"].startswith("DBMS_"))
            self.assertFalse(e["to"].startswith("UTL_"))

    def test_05_unresolved_ref_never_silently_dropped(self):
        node = find_node(self.result["nodes"], "AUTH.OSAG_AUTH")
        texts = {r["text"] for r in node["unresolved_refs"]}
        self.assertIn("auth.profile", texts)
        for r in node["unresolved_refs"]:
            self.assertIn("line", r)

    def test_06_trigger_bodies_produce_edges(self):
        trigger_edges = [e for e in self.result["edges"] if e["from"] in {n["id"] for n in self.result["nodes"] if n["kind"] == "trigger"}]
        # not every trigger calls a package, but the mechanism must work for at
        # least one that does -- confirm at least one trigger node has an outbound edge
        self.assertGreater(len(trigger_edges), 0)

    def test_07_self_reference_produces_no_self_loop(self):
        for e in self.result["edges"]:
            self.assertNotEqual(e["from"], e["to"])
        # AUTH.OSAG_AUTH calls AUTH.OSAG_AUTH.grant_user_role internally (verified
        # in calls_out_raw) -- must not produce a self-loop edge.
        self.assertIsNone(find_edge(self.result["edges"], "AUTH.OSAG_AUTH", "AUTH.OSAG_AUTH"))


class TestFlagging(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.inventory, cls.name_map_rows = load_real()
        cls.result = depgraph.build_graph(cls.inventory, cls.name_map_rows)

    def test_08_dynamic_sql_objects_carry_incomplete_flag(self):
        known_dynamic_sql = [
            "SYS.OSAG_TABLE_REDEFINITION",
            "REPORT.OSAG_CHANNEL",
            "TT.EVENT_INTERFACE",
            "MCDB_CHECKS.CONSISTENCY",
        ]
        for node_id in known_dynamic_sql:
            node = find_node(self.result["nodes"], node_id)
            self.assertIsNotNone(node, node_id)
            self.assertEqual(node["static_resolution"], "incomplete", node_id)
            self.assertTrue(node["reasons"])

    def test_09_unresolved_ref_node_also_marked_incomplete(self):
        node = find_node(self.result["nodes"], "AUTH.OSAG_AUTH")
        self.assertTrue(node["unresolved_refs"])
        self.assertEqual(node["static_resolution"], "incomplete")
        reason_texts = [r["detail"] for r in node["reasons"] if r["kind"] == "unresolved_reference"]
        self.assertTrue(any("auth.profile" in t for t in reason_texts))


class TestWavesAndCyclesSynthetic(unittest.TestCase):
    def test_10_synthetic_chain_leaves_first(self):
        nodes = ["A", "B", "C"]
        edges = [("A", "B"), ("B", "C")]
        sccs = depgraph.compute_sccs(nodes, edges)
        assignment = depgraph.assign_waves(nodes, edges, sccs)
        self.assertEqual(assignment["wave"]["C"], 1)
        self.assertEqual(assignment["wave"]["B"], 2)
        self.assertEqual(assignment["wave"]["A"], 3)

    def test_13_synthetic_mutual_recursion_one_cycle_group_shared_wave(self):
        nodes = ["A", "B"]
        edges = [("A", "B"), ("B", "A")]
        sccs = depgraph.compute_sccs(nodes, edges)
        cycle_sccs = [c for c in sccs if len(c) > 1]
        self.assertEqual(len(cycle_sccs), 1)
        self.assertEqual(sorted(cycle_sccs[0]), ["A", "B"])
        assignment = depgraph.assign_waves(nodes, edges, sccs)
        self.assertEqual(assignment["wave"]["A"], assignment["wave"]["B"])
        self.assertIsNotNone(assignment["cycle_group"]["A"])
        self.assertEqual(assignment["cycle_group"]["A"], assignment["cycle_group"]["B"])
        self.assertEqual(len(assignment["cycle_groups"]), 1)


class TestWavesAndCyclesReal(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.inventory, cls.name_map_rows = load_real()
        cls.result = depgraph.build_graph(cls.inventory, cls.name_map_rows)

    def test_11_every_node_in_exactly_one_wave(self):
        all_ids = {n["id"] for n in self.result["nodes"]}
        seen = []
        for wave in self.result["waves"]:
            seen.extend(wave)
        self.assertEqual(len(seen), len(set(seen)), "a node appears in more than one wave")
        self.assertEqual(set(seen), all_ids)

    def test_12_edge_wave_ordering_holds_outside_cycle_groups(self):
        wave_of = {n["id"]: n["wave"] for n in self.result["nodes"]}
        cycle_of = {n["id"]: n["cycle_group"] for n in self.result["nodes"]}
        for e in self.result["edges"]:
            frm, to = e["from"], e["to"]
            if cycle_of[frm] is not None and cycle_of[frm] == cycle_of[to]:
                continue
            self.assertLess(wave_of[to], wave_of[frm], f"{frm} -> {to} violates wave ordering")

    def test_14_known_cycles_gate(self):
        cycle_groups = self.result["cycle_groups"]
        self.assertGreaterEqual(len(cycle_groups), 1, "the real corpus has genuine mutual-recursion cycles")
        known_ids = {c["id"] for c in cycle_groups}
        ok, messages = depgraph.check_known_cycles(cycle_groups, [{"id": i, "members": []} for i in known_ids])
        self.assertTrue(ok, messages)

        ok2, messages2 = depgraph.check_known_cycles(cycle_groups, [])
        self.assertFalse(ok2)
        self.assertTrue(messages2)


class TestReconciliation(unittest.TestCase):
    def test_15_node_count_matches_inventory_then_fails_when_removed(self):
        inventory, name_map_rows = load_real()
        result = depgraph.build_graph(inventory, name_map_rows)
        known_cycles = json.loads((ANALYZE_DIR / "known_cycles.json").read_text())

        ok, messages = depgraph.check(result, inventory, known_cycles)
        self.assertTrue(ok, messages)

        tampered = json.loads(json.dumps(result))
        tampered["nodes"].pop()
        for wave in tampered["waves"]:
            removed_ids = {n["id"] for n in result["nodes"]} - {n["id"] for n in tampered["nodes"]}
            wave[:] = [nid for nid in wave if nid not in removed_ids]
        ok2, messages2 = depgraph.check(tampered, inventory, known_cycles)
        self.assertFalse(ok2)
        self.assertTrue(messages2)


class TestCheckCLI(unittest.TestCase):
    def test_16_check_exits_zero_against_real_artifacts(self):
        with contextlib.redirect_stdout(io.StringIO()):
            rc = depgraph.main(["--check"])
        self.assertEqual(rc, 0)


if __name__ == "__main__":
    unittest.main()
