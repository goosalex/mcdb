#!/usr/bin/env python3
"""
depgraph.py -- the dependency graph generator (INV-02).

Python 3.12, stdlib only (argparse, csv, json, sys, collections).

Input:  migration/analyze/inventory.json (nodes + calls_out_raw -- the raw,
        unresolved call references)
        migration/mapping/name-map.csv   (supplies the synonym table used to
        resolve two-part bare calls -- see Task 1)
Output: migration/analyze/depgraph.json  (THE dependency graph + wave list)
        migration/analyze/depgraph.dot   (human-review rendering)

Reads migration/analyze/known_cycles.json (human-authored input, not
generated) to gate newly-appearing cycles.

Two modes:
  python3 depgraph.py            -> writes depgraph.json + depgraph.dot
  python3 depgraph.py --check    -> validates, exits non-zero on any gate
                                     failure, writes nothing.

Resolution precedence per calls_out_raw entry (see 01-02-PLAN.md "Naming
Rules"/"Collision Semantics"/action paragraph for Task 2):
  1. three-part reference (SCHEMA.PACKAGE.OBJECT) against the package index
  2. two-part reference (SYNONYM.OBJECT) against the public-synonym index
  3. two-part reference (PKG.OBJECT) against a package of the same name in
     the caller's own schema
  4. DBMS_*/UTL_* family -- external Oracle builtin, no edge, no complaint
  5. otherwise: unresolved -- recorded on the node, never dropped
Self-loops (a node resolving to itself) are dropped, not recorded as edges.
"""
from __future__ import annotations

import argparse
import csv
import json
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional, Tuple

GENERATOR_VERSION = "1.0.0"

ANALYZE_DIR = Path(__file__).resolve().parent
REPO_ROOT = ANALYZE_DIR.parents[1]
MAPPING_DIR = REPO_ROOT / "migration" / "mapping"

DEFAULT_INVENTORY_PATH = ANALYZE_DIR / "inventory.json"
DEFAULT_NAME_MAP_PATH = MAPPING_DIR / "name-map.csv"
DEFAULT_OUTPUT_JSON_PATH = ANALYZE_DIR / "depgraph.json"
DEFAULT_OUTPUT_DOT_PATH = ANALYZE_DIR / "depgraph.dot"
DEFAULT_KNOWN_CYCLES_PATH = ANALYZE_DIR / "known_cycles.json"

EXTERNAL_PREFIXES = ("DBMS_", "UTL_")
CALLABLE_KINDS = ("package", "procedure", "trigger")


# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------

def load_inventory(path: Path = DEFAULT_INVENTORY_PATH) -> Dict:
    return json.loads(path.read_text())


def load_name_map(path: Path = DEFAULT_NAME_MAP_PATH) -> List[Dict]:
    with open(path, newline="") as f:
        return [dict(row) for row in csv.DictReader(f)]


def load_known_cycles(path: Path = DEFAULT_KNOWN_CYCLES_PATH) -> List[Dict]:
    if not path.exists():
        return []
    return json.loads(path.read_text())


# ---------------------------------------------------------------------------
# Resolution tables
# ---------------------------------------------------------------------------

def build_package_index(objects: List[Dict]) -> set:
    return {o["id"] for o in objects if o["kind"] == "package"}


def build_synonym_index(name_map_rows: List[Dict]) -> Dict[str, str]:
    """SYNONYM (upper) -> 'SCHEMA.PACKAGE', derived from name-map.csv's
    oracle_synonym column -- which already carries the one malformed
    unqualified synonym (`plog`/`OSAG_NIDS`-shape) resolved heuristically by
    Task 1's build_synonym_index. Not re-derived from raw inventory.synonyms
    here: name-map.csv is the single source of truth for this attribution,
    per the SSOT rule -- a second synonym-resolution implementation reading
    raw inventory data would be exactly the "second mapping" the plan
    forbids.
    """
    index: Dict[str, str] = {}
    for row in name_map_rows:
        syn = row.get("oracle_synonym", "")
        if not syn:
            continue
        key = f"{row['oracle_schema'].upper()}.{row['oracle_package'].upper()}"
        index[syn.upper()] = key
    return index


def resolve_call(caller_schema: str, text: str, shape: str, package_index: set, synonym_index: Dict[str, str]) -> Tuple[str, Optional[str], Optional[str]]:
    """Resolve one calls_out_raw entry. Returns (action, target, via) where
    action is one of "resolved" | "external" | "unresolved"."""
    parts = text.split(".")
    first = parts[0].upper()

    if first.startswith(EXTERNAL_PREFIXES):
        return ("external", None, None)

    if shape == "qualified" and len(parts) == 3:
        key = f"{parts[0].upper()}.{parts[1].upper()}"
        if key in package_index:
            return ("resolved", key, "qualified")
        return ("unresolved", None, None)

    if shape == "bare" and len(parts) == 2:
        if first in synonym_index:
            return ("resolved", synonym_index[first], "synonym")
        same_schema_key = f"{caller_schema.upper()}.{first}"
        if same_schema_key in package_index:
            return ("resolved", same_schema_key, "same_schema")
        return ("unresolved", None, None)

    return ("unresolved", None, None)


# ---------------------------------------------------------------------------
# Strongly connected components (Tarjan) + wave assignment
# ---------------------------------------------------------------------------

def compute_sccs(nodes: List[str], edges: List[Tuple[str, str]]) -> List[List[str]]:
    """Tarjan's algorithm. Returns a list of SCCs (each a list of node ids);
    a singleton SCC is a node with no cycle."""
    adj: Dict[str, List[str]] = defaultdict(list)
    for frm, to in edges:
        adj[frm].append(to)

    index_counter = [0]
    index_of: Dict[str, int] = {}
    lowlink: Dict[str, int] = {}
    on_stack: Dict[str, bool] = {}
    stack: List[str] = []
    result: List[List[str]] = []

    def strongconnect(v: str) -> None:
        index_of[v] = index_counter[0]
        lowlink[v] = index_counter[0]
        index_counter[0] += 1
        stack.append(v)
        on_stack[v] = True

        for w in adj.get(v, []):
            if w not in index_of:
                strongconnect(w)
                lowlink[v] = min(lowlink[v], lowlink[w])
            elif on_stack.get(w):
                lowlink[v] = min(lowlink[v], index_of[w])

        if lowlink[v] == index_of[v]:
            comp = []
            while True:
                w = stack.pop()
                on_stack[w] = False
                comp.append(w)
                if w == v:
                    break
            result.append(comp)

    sys.setrecursionlimit(max(sys.getrecursionlimit(), len(nodes) + 1000))
    for node in nodes:
        if node not in index_of:
            strongconnect(node)

    return result


def _cycle_group_id(members: List[str]) -> str:
    return "|".join(sorted(members))


def assign_waves(nodes: List[str], edges: List[Tuple[str, str]], sccs: List[List[str]]) -> Dict:
    """Condense each SCC of size > 1 into one node, assign waves over the
    resulting (guaranteed acyclic) condensation, then expand back so every
    original node gets a wave number and (if applicable) a cycle_group id.

    wave(leaf) = 1; wave(caller) = 1 + max(wave(callee) for callee in its
    outbound edges) -- leaves (calling nothing in-scope) come first, callers
    last, so that when a wave is translated everything it calls already
    exists.
    """
    comp_of: Dict[str, str] = {}
    comp_members: Dict[str, List[str]] = {}
    cycle_groups: List[Dict] = []

    for comp in sccs:
        if len(comp) > 1:
            cid = _cycle_group_id(comp)
        else:
            cid = comp[0]  # singleton components use the node's own id as their comp id
        comp_members[cid] = comp
        for member in comp:
            comp_of[member] = cid

    condensed_out: Dict[str, set] = defaultdict(set)
    for frm, to in edges:
        cfrm, cto = comp_of[frm], comp_of[to]
        if cfrm != cto:
            condensed_out[cfrm].add(cto)

    memo: Dict[str, int] = {}

    def compute_wave(cid: str) -> int:
        if cid in memo:
            return memo[cid]
        children = condensed_out.get(cid, set())
        if not children:
            memo[cid] = 1
        else:
            memo[cid] = 1 + max(compute_wave(c) for c in children)
        return memo[cid]

    for cid in comp_members:
        compute_wave(cid)

    node_wave: Dict[str, int] = {}
    node_cycle_group: Dict[str, Optional[str]] = {}
    for cid, members in comp_members.items():
        w = memo[cid]
        is_cycle = len(members) > 1
        for m in members:
            node_wave[m] = w
            node_cycle_group[m] = cid if is_cycle else None

    for cid, members in comp_members.items():
        if len(members) > 1:
            cycle_groups.append(
                {
                    "id": cid,
                    "members": sorted(members),
                    "wave": memo[cid],
                    "note": "all members translate as one batch -- none can precede the others",
                }
            )

    cycle_groups.sort(key=lambda c: c["id"])

    return {"wave": node_wave, "cycle_group": node_cycle_group, "cycle_groups": cycle_groups}


# ---------------------------------------------------------------------------
# Graph assembly
# ---------------------------------------------------------------------------

def build_graph(inventory: Dict, name_map_rows: List[Dict]) -> Dict:
    objects = inventory["objects"]
    package_index = build_package_index(objects)
    synonym_index = build_synonym_index(name_map_rows)

    unresolved_by_node: Dict[str, List[Dict]] = defaultdict(list)
    edge_info: Dict[Tuple[str, str], Dict] = {}

    for o in objects:
        if o["kind"] not in CALLABLE_KINDS:
            continue
        caller = o["id"]
        for c in o.get("calls_out_raw", []):
            action, target, via = resolve_call(o["schema"], c["text"], c["shape"], package_index, synonym_index)
            if action == "external":
                continue
            if action == "unresolved":
                unresolved_by_node[caller].append({"text": c["text"], "line": c["line"]})
                continue
            # action == "resolved"
            if target == caller:
                continue  # self-reference: no self-loop edge
            key = (caller, target)
            if key not in edge_info:
                edge_info[key] = {"via": via, "call_sites": []}
            edge_info[key]["call_sites"].append(c["line"])

    nodes_meta = []
    for o in objects:
        node_id = o["id"]
        reasons = []
        for r in o.get("static_resolution_reasons", []):
            reasons.append({"kind": "dynamic_sql", "detail": r["construct"], "line": r["line"]})
        unresolved = sorted(unresolved_by_node.get(node_id, []), key=lambda r: r["line"])
        for u in unresolved:
            reasons.append({"kind": "unresolved_reference", "detail": u["text"], "line": u["line"]})

        base_incomplete = o.get("static_resolution") == "incomplete"
        static_resolution = "incomplete" if (base_incomplete or unresolved) else "complete"

        nodes_meta.append(
            {
                "id": node_id,
                "kind": o["kind"],
                "schema": o["schema"],
                "package": o.get("package"),
                "static_resolution": static_resolution,
                "reasons": reasons,
                "unresolved_refs": unresolved,
            }
        )

    node_ids = [n["id"] for n in nodes_meta]
    edges_list = list(edge_info.keys())
    sccs = compute_sccs(node_ids, edges_list)
    assignment = assign_waves(node_ids, edges_list, sccs)

    for n in nodes_meta:
        n["wave"] = assignment["wave"][n["id"]]
        n["cycle_group"] = assignment["cycle_group"][n["id"]]

    nodes_meta.sort(key=lambda n: n["id"])

    edges_out = []
    for (frm, to), info in edge_info.items():
        edges_out.append(
            {
                "from": frm,
                "to": to,
                "call_sites": sorted(set(info["call_sites"])),
                "via": info["via"],
            }
        )
    edges_out.sort(key=lambda e: (e["from"], e["to"]))

    waves_by_number: Dict[int, List[str]] = defaultdict(list)
    for n in nodes_meta:
        waves_by_number[n["wave"]].append(n["id"])
    max_wave = max(waves_by_number) if waves_by_number else 0
    waves_out = [sorted(waves_by_number.get(w, [])) for w in range(1, max_wave + 1)]

    unresolved_count = sum(len(n["unresolved_refs"]) for n in nodes_meta)
    incomplete_count = sum(1 for n in nodes_meta if n["static_resolution"] == "incomplete")

    result = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "generator_version": GENERATOR_VERSION,
        "nodes": nodes_meta,
        "edges": edges_out,
        "waves": waves_out,
        "cycle_groups": assignment["cycle_groups"],
        "stats": {
            "node_count": len(nodes_meta),
            "edge_count": len(edges_out),
            "unresolved_count": unresolved_count,
            "incomplete_count": incomplete_count,
        },
    }
    return result


# ---------------------------------------------------------------------------
# DOT rendering
# ---------------------------------------------------------------------------

def render_dot(result: Dict) -> str:
    lines = ["digraph depgraph {", "  rankdir=BT;"]
    for n in result["nodes"]:
        node_id = n["id"]
        safe_id = node_id.replace(".", "_").replace("-", "_").replace("|", "_")
        label = node_id.replace('"', '\\"')
        if n["static_resolution"] == "incomplete":
            style = 'style=filled,fillcolor="#ffcccc",color="#cc0000"'
        else:
            style = 'style=filled,fillcolor="#eeeeee"'
        lines.append(f'  "{safe_id}" [label="{label}\\nwave={n["wave"]}",{style}];')
    for e in result["edges"]:
        f_id = e["from"].replace(".", "_").replace("-", "_").replace("|", "_")
        t_id = e["to"].replace(".", "_").replace("-", "_").replace("|", "_")
        lines.append(f'  "{f_id}" -> "{t_id}" [label="{e["via"]}"];')
    lines.append("}")
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# --check gates
# ---------------------------------------------------------------------------

def check_known_cycles(cycle_groups: List[Dict], known_cycles: List[Dict]) -> Tuple[bool, List[str]]:
    known_ids = {c["id"] for c in known_cycles}
    messages = []
    for cg in cycle_groups:
        if cg["id"] not in known_ids:
            messages.append(
                f"NEW CYCLE not in known_cycles.json: {cg['id']} (members: {cg['members']}) -- "
                "confirm it is a genuine mutual reference (not a resolver bug), then add it to "
                "migration/analyze/known_cycles.json to accept it"
            )
    return (len(messages) == 0, messages)


def check(result: Dict, inventory: Dict, known_cycles: List[Dict]) -> Tuple[bool, List[str]]:
    messages: List[str] = []

    expected_node_count = len(inventory["objects"])
    actual_node_count = len(result["nodes"])
    if actual_node_count != expected_node_count:
        messages.append(f"node count mismatch: expected {expected_node_count} (from inventory), got {actual_node_count}")

    # every node in exactly one wave; union of waves == node set
    all_ids = {n["id"] for n in result["nodes"]}
    seen: List[str] = []
    for wave in result["waves"]:
        seen.extend(wave)
    if len(seen) != len(set(seen)):
        messages.append("a node appears in more than one wave")
    if set(seen) != all_ids:
        missing = all_ids - set(seen)
        extra = set(seen) - all_ids
        if missing:
            messages.append(f"nodes missing from waves[]: {sorted(missing)}")
        if extra:
            messages.append(f"waves[] contains node ids not present in nodes[]: {sorted(extra)}")

    # edge wave ordering, excluding same cycle group
    wave_of = {n["id"]: n["wave"] for n in result["nodes"]}
    cycle_of = {n["id"]: n["cycle_group"] for n in result["nodes"]}
    for e in result["edges"]:
        frm, to = e["from"], e["to"]
        if frm not in wave_of or to not in wave_of:
            continue
        if cycle_of.get(frm) is not None and cycle_of.get(frm) == cycle_of.get(to):
            continue
        if not (wave_of[to] < wave_of[frm]):
            messages.append(f"wave ordering violated: {frm} (wave {wave_of[frm]}) -> {to} (wave {wave_of[to]})")

    # every inventory object flagged incomplete must be flagged incomplete in the graph
    node_by_id = {n["id"]: n for n in result["nodes"]}
    for o in inventory["objects"]:
        if o.get("static_resolution") == "incomplete":
            node = node_by_id.get(o["id"])
            if node is None:
                continue
            if node["static_resolution"] != "incomplete":
                messages.append(f"{o['id']} is flagged incomplete in inventory.json but not in the graph")

    # every node with unresolved refs must be marked incomplete
    for n in result["nodes"]:
        if n["unresolved_refs"] and n["static_resolution"] != "incomplete":
            messages.append(f"{n['id']} has unresolved_refs but static_resolution != incomplete")

    ok_cycles, cycle_messages = check_known_cycles(result["cycle_groups"], known_cycles)
    messages.extend(cycle_messages)

    return (len(messages) == 0, messages)


# ---------------------------------------------------------------------------
# Reporting (printed on every run, per the plan -- this is the manual-
# verification backlog Phase 2 and Phase 4 inherit)
# ---------------------------------------------------------------------------

def print_report(result: Dict) -> None:
    print(f"nodes={result['stats']['node_count']} edges={result['stats']['edge_count']} "
          f"unresolved={result['stats']['unresolved_count']} incomplete={result['stats']['incomplete_count']}")
    print("Wave table:")
    for i, wave in enumerate(result["waves"], start=1):
        print(f"  wave {i}: {len(wave)} node(s) -- {', '.join(wave[:8])}{' ...' if len(wave) > 8 else ''}")
    if result["cycle_groups"]:
        print("Cycle groups (translate each as one batch):")
        for cg in result["cycle_groups"]:
            print(f"  {cg['id']} (wave {cg['wave']}): {cg['members']}")
    incomplete_nodes = [n for n in result["nodes"] if n["static_resolution"] == "incomplete"]
    if incomplete_nodes:
        print(f"Statically incomplete nodes ({len(incomplete_nodes)}) -- manual tracing required:")
        for n in incomplete_nodes:
            reasons = "; ".join(f"{r['kind']}:{r['detail']}@{r['line']}" for r in n["reasons"])
            print(f"  {n['id']}: {reasons}")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="validate instead of writing depgraph.json/.dot")
    parser.add_argument("--inventory-path", type=Path, default=DEFAULT_INVENTORY_PATH)
    parser.add_argument("--name-map-path", type=Path, default=DEFAULT_NAME_MAP_PATH)
    parser.add_argument("--known-cycles-path", type=Path, default=DEFAULT_KNOWN_CYCLES_PATH)
    parser.add_argument("--output-json-path", type=Path, default=DEFAULT_OUTPUT_JSON_PATH)
    parser.add_argument("--output-dot-path", type=Path, default=DEFAULT_OUTPUT_DOT_PATH)
    args = parser.parse_args(argv)

    inventory = load_inventory(args.inventory_path)
    name_map_rows = load_name_map(args.name_map_path)
    known_cycles = load_known_cycles(args.known_cycles_path)

    result = build_graph(inventory, name_map_rows)
    print_report(result)

    ok, messages = check(result, inventory, known_cycles)

    if args.check:
        if ok:
            print("--check: OK")
            return 0
        print("--check: FAILED", file=sys.stderr)
        for m in messages:
            print(f"  - {m}", file=sys.stderr)
        return 1

    if not ok:
        print("depgraph: gate FAILED (writing nothing)", file=sys.stderr)
        for m in messages:
            print(f"  - {m}", file=sys.stderr)
        return 1

    args.output_json_path.write_text(json.dumps(result, indent=2, sort_keys=False) + "\n")
    args.output_dot_path.write_text(render_dot(result))
    print(f"wrote {args.output_json_path}")
    print(f"wrote {args.output_dot_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
