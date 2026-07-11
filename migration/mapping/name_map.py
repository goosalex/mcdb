#!/usr/bin/env python3
"""
name_map.py -- the Oracle -> PostgreSQL name-mapping SSOT generator (INV-03).

Python 3.12, stdlib only (csv, json, argparse, collections). This is the ONLY
place in the repo that decides a PostgreSQL object name -- Phase 4's cross-
reference rewriter, Phase 4's test naming, and Phase 5's client regexp kit
all read `name-map.csv` and none of them invent a name.

Input:  migration/analyze/inventory.json (the sole data input; never re-parses
        ddl/src itself -- that is inventory.py's job)
        migration/mapping/overrides.csv  (human-authored collision resolutions)
Output: migration/mapping/name-map.csv

Two modes:
  python3 name_map.py            -> writes migration/mapping/name-map.csv
  python3 name_map.py --check    -> validates (collision gate, coverage),
                                     prints failures, exits non-zero, writes
                                     nothing.

Naming rules (see 01-02-PLAN.md "Naming Rules" table -- restated in
migration/README.md for consumers):
  package routine   SCHEMA.PKG.OBJ  -> schema=schema.lower(), name=pkg_obj (lower)
  standalone proc   SCHEMA.PROC     -> schema=schema.lower(), name=proc (lower), no prefix
  trigger           SCHEMA.TRG      -> schema=schema.lower(), name=trg (lower), no prefix
  trigger function  (synthetic)     -> schema=schema.lower(), name=trg_fn (lower)
  type              SCHEMA.TYP      -> schema=schema.lower(), name=typ (lower), no prefix
"""
from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# plsql_lex lives in migration/analyze -- reuse its normalize() helper for
# schema/name identity comparisons rather than writing a second one.
ANALYZE_DIR = Path(__file__).resolve().parents[1] / "analyze"
sys.path.insert(0, str(ANALYZE_DIR))
import plsql_lex  # noqa: E402

GENERATOR_VERSION = "1.0.0"

MAPPING_DIR = Path(__file__).resolve().parent
DEFAULT_INVENTORY_PATH = ANALYZE_DIR / "inventory.json"
DEFAULT_OVERRIDES_PATH = MAPPING_DIR / "overrides.csv"
DEFAULT_OUTPUT_PATH = MAPPING_DIR / "name-map.csv"

COLUMNS = [
    "oracle_schema",
    "oracle_package",
    "oracle_object",
    "oracle_signature",
    "oracle_synonym",
    "kind",
    "pg_schema",
    "pg_object_name",
    "pg_kind",
    "is_overload",
    "overridden",
    "source_path",
    "source_line",
]

OVERRIDE_COLUMNS = ["oracle_schema", "oracle_package", "oracle_object", "oracle_signature", "pg_object_name", "reason"]


# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------

def load_inventory(path: Path = DEFAULT_INVENTORY_PATH) -> Dict:
    return json.loads(path.read_text())


def load_overrides(path: Path = DEFAULT_OVERRIDES_PATH) -> List[Dict]:
    if not path.exists():
        return []
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        return [dict(row) for row in reader]


# ---------------------------------------------------------------------------
# Synonym resolution (per-package public synonym, for the oracle_synonym column)
# ---------------------------------------------------------------------------

def build_synonym_index(synonyms: List[Dict], package_ids: set) -> Dict[str, str]:
    """Map normalized 'SCHEMA.PACKAGE' -> the public synonym name declared for
    that package (original case, as written in the CREATE PUBLIC SYNONYM
    statement). Packages with no synonym are simply absent from this dict --
    callers must default to "".

    Handles the one malformed unqualified synonym the inventory flagged
    (`CREATE PUBLIC SYNONYM OSAG_NIDS FOR osag_nids` -- no schema on the
    target) by resolving it against the unique package with that name, when
    exactly one such package exists. An ambiguous or unmatched malformed
    synonym is left unresolved here -- Task 2's depgraph is the artifact
    responsible for surfacing an unresolved reference as a graph-level
    concern; Task 1 simply never stamps a synonym it cannot uniquely
    attribute to one package.
    """
    by_name: Dict[str, List[str]] = defaultdict(list)
    for pid in package_ids:
        _, pkg = pid.split(".", 1)
        by_name[plsql_lex.normalize(pkg)].append(pid)

    index: Dict[str, str] = {}
    for s in synonyms:
        target_package = plsql_lex.normalize(s["target_package"])
        if s.get("target_schema"):
            key = f"{plsql_lex.normalize(s['target_schema'])}.{target_package}"
            if key in package_ids:
                index[key] = s["synonym"]
        else:
            candidates = by_name.get(target_package, [])
            if len(candidates) == 1:
                index[candidates[0]] = s["synonym"]
            # ambiguous or no match: leave unresolved (see docstring)
    return index


# ---------------------------------------------------------------------------
# Signature construction for standalone procedures (package routines already
# carry a precomputed `signature` field from inventory.py; this mirrors that
# same formula for the one object kind that doesn't).
# ---------------------------------------------------------------------------

def _norm_param_type(t: str) -> str:
    return re.sub(r"%.*$", "", t).strip().upper()


def build_procedure_signature(name: str, params: List[Dict]) -> str:
    type_list = ",".join(_norm_param_type(p["type"]) for p in params)
    return f"{name.upper()}({type_list})"


# ---------------------------------------------------------------------------
# Row construction
# ---------------------------------------------------------------------------

def _row(oracle_schema, oracle_package, oracle_object, oracle_signature, oracle_synonym,
         kind, pg_schema, pg_object_name, pg_kind, source_path, source_line) -> Dict:
    return {
        "oracle_schema": oracle_schema,
        "oracle_package": oracle_package,
        "oracle_object": oracle_object,
        "oracle_signature": oracle_signature,
        "oracle_synonym": oracle_synonym,
        "kind": kind,
        "pg_schema": pg_schema,
        "pg_object_name": pg_object_name,
        "pg_kind": pg_kind,
        "is_overload": False,
        "overridden": False,
        "source_path": source_path,
        "source_line": source_line,
    }


def build_rows(inventory: Dict) -> Tuple[List[Dict], List[str]]:
    """Build every name-map row from the inventory. Returns (rows,
    packages_without_public_routines) -- the latter is a note, not a CSV
    row: a package with zero public routines is a legitimate structural fact
    (e.g. a *_STATE package exposing only package-level variables), not a
    parser failure, but it deserves to be visible on every --check run."""
    objects = inventory["objects"]
    package_objs = [o for o in objects if o["kind"] == "package"]
    package_ids = {o["id"] for o in package_objs}
    synonym_index = build_synonym_index(inventory.get("synonyms", []), package_ids)

    rows: List[Dict] = []
    packages_without_public_routines: List[str] = []

    for o in package_objs:
        schema = o["schema"]
        pkg = o["package"]
        synonym = synonym_index.get(o["id"], "")
        if not o["routines"]:
            packages_without_public_routines.append(o["id"])
        for r in o["routines"]:
            pg_kind = "function" if r["kind"].upper() == "FUNCTION" else "procedure"
            rows.append(
                _row(
                    oracle_schema=schema,
                    oracle_package=pkg,
                    oracle_object=r["name"],
                    oracle_signature=r["signature"],
                    oracle_synonym=synonym,
                    kind="package_routine",
                    pg_schema=schema.lower(),
                    pg_object_name=f"{pkg.lower()}_{r['name'].lower()}",
                    pg_kind=pg_kind,
                    source_path=o["spec_path"],
                    source_line=r["line"],
                )
            )

    for o in objects:
        if o["kind"] != "procedure":
            continue
        schema = o["schema"]
        name = o["name"]
        sig = build_procedure_signature(name, o.get("params", []))
        rows.append(
            _row(
                oracle_schema=schema,
                oracle_package="",
                oracle_object=name,
                oracle_signature=sig,
                oracle_synonym="",
                kind="procedure",
                pg_schema=schema.lower(),
                pg_object_name=name.lower(),
                pg_kind="procedure",
                source_path=o["body_path"],
                source_line=o["start_line"],
            )
        )

    for o in objects:
        if o["kind"] != "trigger":
            continue
        schema = o["schema"]
        name = o["name"]
        rows.append(
            _row(
                oracle_schema=schema,
                oracle_package="",
                oracle_object=name,
                oracle_signature="",
                oracle_synonym="",
                kind="trigger",
                pg_schema=schema.lower(),
                pg_object_name=name.lower(),
                pg_kind="trigger",
                source_path=o["body_path"],
                source_line=o["start_line"],
            )
        )
        rows.append(
            _row(
                oracle_schema=schema,
                oracle_package="",
                oracle_object=name,
                oracle_signature="",
                oracle_synonym="",
                kind="trigger_function",
                pg_schema=schema.lower(),
                pg_object_name=f"{name.lower()}_fn",
                pg_kind="trigger_function",
                source_path=o["body_path"],
                source_line=o["start_line"],
            )
        )

    for o in objects:
        if o["kind"] != "type":
            continue
        schema = o["schema"]
        name = o["name"]
        rows.append(
            _row(
                oracle_schema=schema,
                oracle_package="",
                oracle_object=name,
                oracle_signature="",
                oracle_synonym="",
                kind="type",
                pg_schema=schema.lower(),
                pg_object_name=name.lower(),
                pg_kind="type",
                source_path=o["body_path"],
                source_line=o["start_line"],
            )
        )

    return rows, packages_without_public_routines


# ---------------------------------------------------------------------------
# Collision gate
# ---------------------------------------------------------------------------

def _group_key(row: Dict) -> Tuple[str, str]:
    return (row["pg_schema"], row["pg_object_name"])


def classify_groups(rows: List[Dict]) -> Tuple[set, Dict[Tuple[str, str], List[int]]]:
    """Group rows by (pg_schema, pg_object_name) and classify every group of
    size > 1 as either a legitimate overload (same Oracle package, distinct
    signatures -- PostgreSQL overloads natively) or a hard collision (any
    other shape of duplicate, per the plan's Collision Semantics table).

    Two rows can only share a flattened pg name while genuinely coming from
    the SAME package if they also share the same routine name (the package
    prefix is a fixed string, so two different routine names can never
    collide once concatenated with the same fixed prefix) -- so "all rows
    share (oracle_schema, oracle_package)" is a sufficient proxy for "same
    package and same routine name" without needing a second check.

    Returns (legitimate_overload_row_indices, hard_collision_groups).
    """
    groups: Dict[Tuple[str, str], List[int]] = defaultdict(list)
    for i, row in enumerate(rows):
        groups[_group_key(row)].append(i)

    overload_idxs: set = set()
    hard_groups: Dict[Tuple[str, str], List[int]] = {}

    for key, idxs in groups.items():
        if len(idxs) < 2:
            continue
        pkgs = {(rows[i]["oracle_schema"], rows[i]["oracle_package"]) for i in idxs}
        same_package = len(pkgs) == 1 and all(rows[i]["oracle_package"] for i in idxs)
        sigs = [rows[i]["oracle_signature"] for i in idxs]
        distinct_sigs = len(set(sigs)) == len(sigs)
        if same_package and distinct_sigs:
            overload_idxs.update(idxs)
        else:
            hard_groups[key] = idxs

    return overload_idxs, hard_groups


def _override_key(schema: str, package: str, obj: str, sig: str) -> Tuple[str, str, str, str]:
    return (schema.upper(), (package or "").upper(), obj.upper(), sig)


def _row_source(row: Dict) -> str:
    pkg = row["oracle_package"] or "(no package)"
    return f"{row['oracle_schema']}.{pkg}.{row['oracle_object']} ({row['source_path']}:{row['source_line']})"


def apply_collision_gate(rows: List[Dict], overrides: List[Dict]) -> Tuple[bool, List[str]]:
    """Classify every duplicate (pg_schema, pg_object_name) group, apply any
    matching override (mutating rows[] in place: pg_object_name, overridden),
    mark legitimate overloads (is_overload), and report every unresolved hard
    collision plus every stale override. Never renames anything the plan
    hasn't sanctioned -- overrides are the ONLY mechanism that changes a name
    away from the mechanical rule.
    """
    messages: List[str] = []

    # Phase 1: classify against the mechanically-derived names to determine
    # which rows are in a genuine hard-collision group (this is what an
    # override is allowed to resolve; anything else would be an override
    # inventing a rename nobody asked for).
    _overload_idxs, hard_groups = classify_groups(rows)

    override_index: Dict[Tuple[str, str, str, str], Dict] = {}
    for ov in overrides:
        override_index[_override_key(ov["oracle_schema"], ov["oracle_package"], ov["oracle_object"], ov["oracle_signature"])] = ov

    used_overrides: set = set()
    for idxs in hard_groups.values():
        for i in idxs:
            row = rows[i]
            key = _override_key(row["oracle_schema"], row["oracle_package"], row["oracle_object"], row["oracle_signature"])
            if key in override_index:
                ov = override_index[key]
                row["pg_object_name"] = ov["pg_object_name"]
                row["overridden"] = True
                used_overrides.add(key)

    # Phase 2: re-classify on the final (post-override) names -- this is the
    # authoritative pass. Anything that still collides here (whether it never
    # had an override, or an override collided with something else) is an
    # unresolved hard failure.
    overload_idxs2, hard_groups2 = classify_groups(rows)
    for i in overload_idxs2:
        rows[i]["is_overload"] = True

    for key, idxs in hard_groups2.items():
        sources = " vs ".join(_row_source(rows[i]) for i in idxs)
        messages.append(f"HARD COLLISION on pg name '{key[0]}.{key[1]}': {sources}")

    for key, ov in override_index.items():
        if key not in used_overrides:
            messages.append(
                f"STALE OVERRIDE: override for {ov['oracle_schema']}.{ov['oracle_package']}.{ov['oracle_object']}"
                f"({ov['oracle_signature']}) matches no existing hard collision -- remove it or the collision it"
                " was meant to resolve has already disappeared"
            )

    return (len(messages) == 0, messages)


# ---------------------------------------------------------------------------
# CSV I/O
# ---------------------------------------------------------------------------

def _csv_ready(row: Dict) -> Dict:
    out = dict(row)
    out["is_overload"] = "true" if row["is_overload"] else "false"
    out["overridden"] = "true" if row["overridden"] else "false"
    for col in COLUMNS:
        if out.get(col) is None:
            out[col] = ""
    return out


def write_csv(rows: List[Dict], path: Path) -> None:
    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=COLUMNS)
        writer.writeheader()
        for row in rows:
            writer.writerow(_csv_ready(row))


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="validate instead of writing name-map.csv")
    parser.add_argument("--inventory-path", type=Path, default=DEFAULT_INVENTORY_PATH)
    parser.add_argument("--overrides-path", type=Path, default=DEFAULT_OVERRIDES_PATH)
    parser.add_argument("--output-path", type=Path, default=DEFAULT_OUTPUT_PATH)
    args = parser.parse_args(argv)

    inventory = load_inventory(args.inventory_path)
    overrides = load_overrides(args.overrides_path)

    rows, packages_without_public_routines = build_rows(inventory)
    ok, messages = apply_collision_gate(rows, overrides)

    if packages_without_public_routines:
        print(f"packages with zero public routines ({len(packages_without_public_routines)}):")
        for pid in packages_without_public_routines:
            print(f"  - {pid}")

    if not ok:
        print("name_map: COLLISION GATE FAILED", file=sys.stderr)
        for m in messages:
            print(f"  - {m}", file=sys.stderr)
        return 1

    if args.check:
        print(f"--check: OK -- {len(rows)} rows, zero unresolved collisions")
        return 0

    args.output_path.parent.mkdir(parents=True, exist_ok=True)
    write_csv(rows, args.output_path)
    print(f"wrote {args.output_path} ({len(rows)} rows)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
