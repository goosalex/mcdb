#!/usr/bin/env python3
"""
spec_lint.py -- SPEC-02 / SPEC-03 gate for migration/spec/*.md.

Python 3.12, stdlib only (argparse, csv, json, re, pathlib), matching Phase 1's
D-B (migration/README.md).

Two invocation shapes:
  python3 spec_lint.py               -> lint every migration/spec/*.md except
                                         TEMPLATE.md, CHECKLIST.md, README.md,
                                         TEST-AMENDMENTS.md (and never descends
                                         into fixtures/ or tests/, since a plain
                                         *.md glob at this directory's root
                                         doesn't recurse)
  python3 spec_lint.py PATH [PATH…]  -> lint exactly the given file(s),
                                         regardless of name or location (this is
                                         how the unit suite and this plan's own
                                         verification commands exercise the
                                         fixtures under fixtures/)
  --check                            -> CI-symmetry alias for Phase 1's
                                         generators' --check convention; spec_lint
                                         never writes anything either way, so
                                         behavior is identical -- --check only
                                         changes the final summary line.

Exit 0 if every linted file has zero violations, 1 otherwise. Every violation is
printed with the file, and where possible the line, that caused it.

What each check enforces and why (see migration/spec/README.md for the full
narrative):
  1. Front-matter complete; pg_schema/pg_prefix must match name-map.csv for real
     specs (paths NOT under a fixtures/ directory) -- this is what makes
     Phase 1's SSOT binding (T-02-06 neighbor: a spec cannot invent a name).
  2. All four mandatory sections present (## Routines, ## Clauses, ## Checklist,
     ## Assumptions / Unresolved).
  3. ## Assumptions / Unresolved has non-whitespace, non-bare-N/A content (SPEC-02).
  4. ## Checklist covers all five CHECKLIST.md dimensions, each with non-empty,
     non-bare-N/A content (SPEC-03).
  5. Every clause has a unique S-<clause_prefix>-NNN ID and at least one
     ddl/src/<path>:<line> citation whose file exists and whose line is within
     that file's length (T-02-05: a fabricated citation is caught).
  6. Routine coverage: for real specs, every PUBLIC routine inventory.json lists
     for that package must appear in at least one clause's routines: field
     (T-02-07: a package can't quietly drop routines it found hard).
"""
from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

SPEC_DIR = Path(__file__).resolve().parent
REPO_ROOT = SPEC_DIR.parents[1]
DEFAULT_INVENTORY_PATH = REPO_ROOT / "migration" / "analyze" / "inventory.json"
DEFAULT_NAME_MAP_PATH = REPO_ROOT / "migration" / "mapping" / "name-map.csv"
DEFAULT_CHECKLIST_PATH = SPEC_DIR / "CHECKLIST.md"

# Docs that live in this directory but are NOT package specs. A package spec is named
# <schema>.<package>.md; anything else here is supporting material and must not be linted
# against the spec structure (front-matter, ## Routines, ## Clauses, ...).
EXCLUDED_FILENAMES = {
    "TEMPLATE.md",
    "CHECKLIST.md",
    "README.md",
    "TEST-AMENDMENTS.md",
    "DYNAMIC-SQL-TRACE.md",  # 02-06's manual trace of TT.EVENT_INTERFACE's EXECUTE IMMEDIATE
    "METHOD-REVIEW.md",  # 02-13's phase-closing verdict document -- not a package spec
}

REQUIRED_FRONTMATTER_FIELDS = [
    "oracle_schema",
    "oracle_package",
    "pg_schema",
    "pg_prefix",
    "clause_prefix",
    "oracle_spec",
    "oracle_body",
    "public_routines",
]

MANDATORY_SECTIONS = ["## Routines", "## Clauses", "## Checklist", "## Assumptions / Unresolved"]

CLAUSE_HEADING_RE = re.compile(r"^###\s+(S-[A-Z0-9]+-\d{3})\s*$")
DIMENSION_HEADING_RE = re.compile(r"^###\s+(\d+)\.\s+(.+?)\s*$")
CITATION_RE = re.compile(r"(ddl/src/[\w./\-]+):(\d+)")


# ---------------------------------------------------------------------------
# Front-matter + section parsing
# ---------------------------------------------------------------------------

def parse_frontmatter(text: str) -> Tuple[Dict[str, str], List[str]]:
    """Split a spec file into (frontmatter dict, body lines). Frontmatter is a
    minimal YAML-lite block: '---' delimiters, flat 'key: value' lines only --
    exactly what TEMPLATE.md's eight fields need, nothing more elaborate."""
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return {}, lines
    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end = i
            break
    if end is None:
        return {}, lines
    fm: Dict[str, str] = {}
    for l in lines[1:end]:
        stripped = l.strip()
        if not stripped or stripped.startswith("#") or ":" not in stripped:
            continue
        key, _, val = stripped.partition(":")
        fm[key.strip()] = val.strip()
    return fm, lines[end + 1 :]


def extract_section(body_lines: List[str], heading: str) -> Optional[List[str]]:
    """Lines strictly between a '## <heading>' line and the next '## ' heading
    (or EOF). Returns None if the heading itself is not found at all."""
    start = None
    for i, l in enumerate(body_lines):
        if l.strip() == heading:
            start = i + 1
            break
    if start is None:
        return None
    end = len(body_lines)
    for i in range(start, len(body_lines)):
        if body_lines[i].startswith("## ") and body_lines[i].strip() != heading:
            end = i
            break
    return body_lines[start:end]


def _is_bare_na(content: str) -> bool:
    stripped = content.strip().strip(".").strip().lower()
    return stripped in ("", "n/a", "na")


# ---------------------------------------------------------------------------
# CHECKLIST.md dimension titles (read once, shared across every spec linted)
# ---------------------------------------------------------------------------

def load_checklist_dimensions(checklist_path: Path) -> List[Tuple[str, str]]:
    """Returns [(number, title), ...] in file order, e.g.
    [("1", "Empty-string / NULL handling"), ...]."""
    dims: List[Tuple[str, str]] = []
    if not checklist_path.exists():
        return dims
    for line in checklist_path.read_text().split("\n"):
        m = DIMENSION_HEADING_RE.match(line)
        if m:
            dims.append((m.group(1), m.group(2)))
    return dims


# ---------------------------------------------------------------------------
# SSOT loaders
# ---------------------------------------------------------------------------

def load_inventory(path: Path) -> Dict:
    if not path.exists():
        return {"objects": []}
    return json.loads(path.read_text())


def load_name_map(path: Path) -> List[Dict[str, str]]:
    if not path.exists():
        return []
    with path.open(newline="") as f:
        return list(csv.DictReader(f))


def find_inventory_package(inventory: Dict, oracle_schema: str, oracle_package: str) -> Optional[Dict]:
    target = f"{oracle_schema.upper()}.{oracle_package.upper()}"
    for obj in inventory.get("objects", []):
        if obj.get("kind") == "package" and obj.get("id") == target:
            return obj
    return None


def name_map_rows_for(name_map_rows: List[Dict[str, str]], oracle_schema: str, oracle_package: str) -> List[Dict[str, str]]:
    return [
        r
        for r in name_map_rows
        if r.get("oracle_schema", "").upper() == oracle_schema.upper()
        and r.get("oracle_package", "").upper() == oracle_package.upper()
        and r.get("kind") == "package_routine"
    ]


def is_fixture_path(path: Path) -> bool:
    return "fixtures" in path.parts


# ---------------------------------------------------------------------------
# Clause parsing
# ---------------------------------------------------------------------------

class Clause:
    def __init__(self, clause_id: str, block_lines: List[str]):
        self.id = clause_id
        self.block_lines = block_lines
        self.block_text = "\n".join(block_lines)

    def routines(self) -> List[str]:
        for line in self.block_lines:
            m = re.search(r"routines:\**\s*(.+)$", line, re.IGNORECASE)
            if m:
                raw = m.group(1)
                return [r.strip().strip("`*") for r in raw.split(",") if r.strip()]
        return []

    def has_routines_field(self) -> bool:
        return any(re.search(r"routines:", l, re.IGNORECASE) for l in self.block_lines)

    def has_source_field(self) -> bool:
        return any(re.search(r"source:", l, re.IGNORECASE) for l in self.block_lines)

    def citations(self) -> List[Tuple[str, int]]:
        out = []
        for m in CITATION_RE.finditer(self.block_text):
            out.append((m.group(1), int(m.group(2))))
        return out


def parse_clauses(clauses_section: List[str]) -> List[Clause]:
    clauses: List[Clause] = []
    current_id: Optional[str] = None
    current_lines: List[str] = []
    for line in clauses_section:
        m = CLAUSE_HEADING_RE.match(line)
        if m:
            if current_id is not None:
                clauses.append(Clause(current_id, current_lines))
            current_id = m.group(1)
            current_lines = []
        else:
            if current_id is not None:
                current_lines.append(line)
    if current_id is not None:
        clauses.append(Clause(current_id, current_lines))
    return clauses


# ---------------------------------------------------------------------------
# Per-file lint
# ---------------------------------------------------------------------------

def lint_file(
    path: Path,
    dimensions: List[Tuple[str, str]],
    inventory: Dict,
    name_map_rows: List[Dict[str, str]],
) -> List[str]:
    violations: List[str] = []

    if not path.exists():
        return [f"{path}: file does not exist"]

    text = path.read_text()
    fm, body_lines = parse_frontmatter(text)

    # 1. front-matter completeness
    if not fm:
        violations.append(f"{path}: no front-matter block found (expected '---' delimited YAML-lite at top of file)")
    else:
        for field in REQUIRED_FRONTMATTER_FIELDS:
            if field not in fm or not fm[field]:
                violations.append(f"{path}: front-matter missing required field '{field}'")

    oracle_schema = fm.get("oracle_schema", "")
    oracle_package = fm.get("oracle_package", "")
    pg_schema = fm.get("pg_schema", "")
    pg_prefix = fm.get("pg_prefix", "")
    clause_prefix = fm.get("clause_prefix", "")

    if "public_routines" in fm:
        try:
            declared_public_routines = int(fm["public_routines"])
        except ValueError:
            violations.append(f"{path}: front-matter 'public_routines' is not an integer: {fm['public_routines']!r}")
            declared_public_routines = None
    else:
        declared_public_routines = None

    # 2. mandatory sections present
    for heading in MANDATORY_SECTIONS:
        if not any(l.strip() == heading for l in body_lines):
            violations.append(f"{path}: missing mandatory section '{heading}'")

    # 3. Assumptions / Unresolved has real content (SPEC-02)
    assumptions = extract_section(body_lines, "## Assumptions / Unresolved")
    if assumptions is not None:
        content = "\n".join(assumptions).strip()
        if _is_bare_na(content):
            violations.append(
                f"{path}: '## Assumptions / Unresolved' is empty or a bare 'N/A' -- SPEC-02 requires either "
                f"a real unresolved item or an explicit statement of what was checked to conclude nothing is unresolved"
            )

    # 4. Checklist covers all five dimensions (SPEC-03)
    checklist_section = extract_section(body_lines, "## Checklist")
    if checklist_section is not None and dimensions:
        found_by_num: Dict[str, List[str]] = {}
        current_num: Optional[str] = None
        current_lines: List[str] = []
        for line in checklist_section:
            m = DIMENSION_HEADING_RE.match(line)
            if m:
                if current_num is not None:
                    found_by_num[current_num] = current_lines
                current_num = m.group(1)
                current_lines = []
            else:
                if current_num is not None:
                    current_lines.append(line)
        if current_num is not None:
            found_by_num[current_num] = current_lines

        for num, title in dimensions:
            if num not in found_by_num:
                violations.append(f"{path}: '## Checklist' missing dimension {num}. {title}")
                continue
            content = "\n".join(found_by_num[num]).strip()
            if _is_bare_na(content):
                violations.append(
                    f"{path}: checklist dimension {num}. {title} is empty or a bare 'N/A' -- "
                    f"'N/A' is only acceptable with a stated reason"
                )
    elif checklist_section is None:
        pass  # already reported by mandatory-sections check above

    # 5 + 6. clauses: ID shape, uniqueness, routines field, source citations,
    #        and (for real specs) routine coverage against inventory.json
    clauses_section = extract_section(body_lines, "## Clauses")
    all_clause_routines: Set[str] = set()
    if clauses_section is not None:
        clauses = parse_clauses(clauses_section)
        seen_ids: Set[str] = set()
        for clause in clauses:
            if clause_prefix and not clause.id.startswith(f"S-{clause_prefix}-"):
                violations.append(
                    f"{path}: clause {clause.id} does not match declared clause_prefix "
                    f"'{clause_prefix}' (expected S-{clause_prefix}-NNN)"
                )
            if clause.id in seen_ids:
                violations.append(f"{path}: duplicate clause ID {clause.id}")
            seen_ids.add(clause.id)

            if not clause.has_routines_field():
                violations.append(f"{path}: clause {clause.id} has no 'routines:' field")
            else:
                routines = clause.routines()
                if not routines:
                    violations.append(f"{path}: clause {clause.id} has an empty 'routines:' field")
                for r in routines:
                    all_clause_routines.add(r.upper())

            if not clause.has_source_field():
                violations.append(f"{path}: clause {clause.id} has no 'source:' field")

            citations = clause.citations()
            if not citations:
                violations.append(
                    f"{path}: clause {clause.id} has no ddl/src/<path>:<line> citation -- "
                    f"a clause with no Oracle source citation is not a clause, it is a guess"
                )
            for rel_path_str, line_no in citations:
                cited_path = REPO_ROOT / rel_path_str
                if not cited_path.exists():
                    violations.append(
                        f"{path}: clause {clause.id} cites nonexistent file '{rel_path_str}'"
                    )
                    continue
                n_lines = len(cited_path.read_text().split("\n"))
                if line_no < 1 or line_no > n_lines:
                    violations.append(
                        f"{path}: clause {clause.id} cites {rel_path_str}:{line_no}, "
                        f"but that file only has {n_lines} lines -- fabricated or stale citation"
                    )

    # SSOT cross-checks -- skipped entirely for paths under fixtures/, since
    # fixtures deliberately use throwaway package names that were never meant
    # to exist in migration/mapping/name-map.csv or migration/analyze/inventory.json.
    if not is_fixture_path(path) and oracle_schema and oracle_package:
        matching_rows = name_map_rows_for(name_map_rows, oracle_schema, oracle_package)
        if not matching_rows:
            violations.append(
                f"{path}: no rows found in name-map.csv for {oracle_schema}.{oracle_package} -- "
                f"check spelling, or this package has no public routines to map"
            )
        else:
            for row in matching_rows:
                if row.get("pg_schema", "").lower() != pg_schema.lower():
                    violations.append(
                        f"{path}: front-matter pg_schema '{pg_schema}' does not match name-map.csv's "
                        f"pg_schema '{row.get('pg_schema')}' for {oracle_schema}.{oracle_package}.{row.get('oracle_object')} "
                        f"-- a spec may not invent a PostgreSQL schema"
                    )
                    break
            expected_prefix = f"{pg_prefix.lower()}_"
            for row in matching_rows:
                pg_object_name = row.get("pg_object_name", "").lower()
                if not pg_object_name.startswith(expected_prefix):
                    violations.append(
                        f"{path}: front-matter pg_prefix '{pg_prefix}' does not match name-map.csv's "
                        f"pg_object_name '{row.get('pg_object_name')}' for {oracle_schema}.{oracle_package}.{row.get('oracle_object')} "
                        f"-- a spec may not invent a PostgreSQL name"
                    )

        pkg_obj = find_inventory_package(inventory, oracle_schema, oracle_package)
        if pkg_obj is None:
            violations.append(
                f"{path}: no package {oracle_schema}.{oracle_package} found in inventory.json -- "
                f"check spelling of oracle_schema/oracle_package"
            )
        else:
            inventory_routine_names = {r["name"].upper() for r in pkg_obj.get("routines", [])}
            missing = sorted(inventory_routine_names - all_clause_routines)
            if missing:
                violations.append(
                    f"{path}: {len(missing)} public routine(s) from inventory.json not covered by any clause's "
                    f"'routines:' field: {', '.join(missing)} -- a spec must not silently drop routines"
                )
            if declared_public_routines is not None and declared_public_routines != len(inventory_routine_names):
                violations.append(
                    f"{path}: front-matter public_routines={declared_public_routines} does not match "
                    f"inventory.json's {len(inventory_routine_names)} public routines for {oracle_schema}.{oracle_package}"
                )

    return violations


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def default_targets() -> List[Path]:
    return sorted(p for p in SPEC_DIR.glob("*.md") if p.name not in EXCLUDED_FILENAMES)


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("paths", nargs="*", type=Path, help="spec files to lint (default: migration/spec/*.md)")
    parser.add_argument("--check", action="store_true", help="CI-symmetry alias; behavior is identical (spec_lint never writes files)")
    parser.add_argument("--inventory-path", type=Path, default=DEFAULT_INVENTORY_PATH)
    parser.add_argument("--name-map-path", type=Path, default=DEFAULT_NAME_MAP_PATH)
    parser.add_argument("--checklist-path", type=Path, default=DEFAULT_CHECKLIST_PATH)
    args = parser.parse_args(argv)

    targets = args.paths if args.paths else default_targets()

    if not targets:
        print("spec_lint: 0 specs found under migration/spec/*.md -- nothing to check")
        return 0

    dimensions = load_checklist_dimensions(args.checklist_path)
    inventory = load_inventory(args.inventory_path)
    name_map_rows = load_name_map(args.name_map_path)

    total_violations = 0
    for p in targets:
        violations = lint_file(p, dimensions, inventory, name_map_rows)
        if violations:
            total_violations += len(violations)
            print(f"FAIL {p}:")
            for v in violations:
                print(f"  - {v}")
        else:
            print(f"OK   {p}")

    if total_violations:
        print(f"spec_lint: {total_violations} violation(s) across {len(targets)} file(s)")
        return 1

    suffix = " [--check]" if args.check else ""
    print(f"spec_lint: {len(targets)} spec(s) OK{suffix}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
