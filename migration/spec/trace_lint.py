#!/usr/bin/env python3
"""
trace_lint.py -- the HARN-05 gate: every test must be traceable to an
Oracle-derived spec clause, not to the translation. Companion to
spec_lint.py (SPEC-02/SPEC-03) and provenance_lint.sh (git-ancestry gate).

Python 3.12, stdlib only (argparse, re, pathlib), matching Phase 1's D-B.

Two invocation shapes:
  python3 trace_lint.py               -> lint every file under
                                          migration/test/pgtap/*.sql and
                                          migration/test/regress/sql/*.sql
  python3 trace_lint.py PATH [PATH…]  -> lint exactly the given file(s),
                                          classified as pgTAP-style unless a
                                          path component is literally
                                          "regress" (matches this repo's
                                          migration/test/regress/sql/ layout)

Runs clean (0 test files found, exit 0) on a tree with no migration/test/
directory yet -- plans 02-04..02-12 populate it as they go.

What is checked:
  - pgTAP files (migration/test/pgtap/*.sql): every assertion call
    (ok/is/isnt/matches/cmp_ok/throws_ok/lives_ok/pass/fail/...) whose last
    argument is a string literal must have that literal begin with
    'S-<PREFIX>-NNN: '. The cited clause ID must resolve against the spec for
    that file's package (derived from the filename convention
    <schema>__<pkg>__*.sql -- migration/spec/<schema>.<pkg>.md).
  - Expected-output files (migration/test/regress/sql/*.sql): the file must
    carry a '-- verifies: S-XXX-001, S-XXX-014' header naming at least one
    clause, and every ID listed must resolve against that package's spec.
  - A test file for a package with no spec at all fails outright.
  - The _canary package (plan 02-01's harness self-test, not a translation)
    is exempt by exact name, not by a loose pattern.

Also prints a coverage REPORT (not a gate) -- which clauses of each spec have
at least one citing test. Phase 2 does not require full coverage (that is
VER-02, Phase 4's job); the report exists so nobody mistakes the pilot's
partial coverage for completeness.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

SPEC_DIR = Path(__file__).resolve().parent
REPO_ROOT = SPEC_DIR.parents[1]
PGTAP_DIR = REPO_ROOT / "migration" / "test" / "pgtap"
REGRESS_SQL_DIR = REPO_ROOT / "migration" / "test" / "regress" / "sql"

CANARY_NAME = "_canary"
SUPPORT_SCHEMA = "_support"  # migration/pgsql/_support/: no Oracle original, no spec, exempt like the canary

CLAUSE_ID_RE = re.compile(r"S-[A-Z0-9]+-\d{3}")
LEADING_CLAUSE_ID_RE = re.compile(r"^(S-[A-Z0-9]+-\d{3}):\s")
SPEC_CLAUSE_HEADING_RE = re.compile(r"^###\s+(S-[A-Z0-9]+-\d{3})\s*$", re.MULTILINE)
VERIFIES_HEADER_RE = re.compile(r"--\s*verifies:\s*(.+)", re.IGNORECASE)

ASSERTION_NAMES = [
    "ok",
    "is",
    "isnt",
    "matches",
    "doesnt_match",
    "cmp_ok",
    "throws_ok",
    "throws_like",
    "lives_ok",
    "pass",
    "fail",
    "is_empty",
    "isnt_empty",
    "results_eq",
    "results_ne",
    "set_eq",
    "bag_eq",
    "set_has",
    "bag_has",
]
_ASSERTION_CALL_RE = re.compile(r"\b(" + "|".join(ASSERTION_NAMES) + r")\s*\(")


# ---------------------------------------------------------------------------
# Quote-aware scanning (single-quoted '' escaping + $tag$ dollar-quoting, plus
# `--` line comments) -- needed so a comma or paren inside a SQL string
# literal OR inside a `--` comment is never mistaken for a top-level
# call-argument separator. Found live in plan 02-13: A-007's amendment
# (TEST-AMENDMENTS.md) added a `--` comment spanning two lines inside
# tt__ticket_interface__changes.sql's S-TICKET-024 `is()` call, and that
# comment's own prose contains a literal comma ("...dissimilar column
# types", aborting...") -- which, before this fix, the scanner treated as a
# real top-level argument separator, since it had no notion of `--` comments
# at all. This is a linter robustness gap (this file lives under
# migration/spec/, not migration/test/pgtap/ or regress/, so fixing it here
# does not touch any test assertion's content or meaning), not a test defect
# -- a `--` comment is ordinary, encouraged SQL documentation, and no
# assertion's cited clause or expected value changes as a result of this fix.
# ---------------------------------------------------------------------------

def _skip_string_literal(text: str, i: int) -> int:
    """If text[i] opens a string literal ('...' or $tag$...$tag$), return the
    index just past its close. Otherwise return i unchanged."""
    n = len(text)
    if text[i] == "'":
        i += 1
        while i < n:
            if text[i] == "'" and i + 1 < n and text[i + 1] == "'":
                i += 2
                continue
            if text[i] == "'":
                return i + 1
            i += 1
        return n
    if text[i] == "$":
        m = re.match(r"\$([A-Za-z0-9_]*)\$", text[i:])
        if m:
            tag = m.group(0)
            end_idx = text.find(tag, i + len(tag))
            return (end_idx + len(tag)) if end_idx != -1 else n
    return i


def _skip_line_comment(text: str, i: int) -> int:
    """If text[i:i+2] opens a '--' SQL line comment, return the index of the
    next newline (or end of text). Otherwise return i unchanged."""
    if text[i : i + 2] == "--":
        nl = text.find("\n", i)
        return nl if nl != -1 else len(text)
    return i


def _find_call_close_paren(text: str, open_idx: int) -> int:
    depth = 0
    i = open_idx
    n = len(text)
    while i < n:
        c = text[i]
        if c in ("'", "$"):
            new_i = _skip_string_literal(text, i)
            if new_i != i:
                i = new_i
                continue
        if c == "-":
            new_i = _skip_line_comment(text, i)
            if new_i != i:
                i = new_i
                continue
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def _scan_top_level_args(text: str) -> List[Tuple[int, int]]:
    """Top-level (depth-0, quote-aware, comment-aware) comma-separated
    argument spans within `text`, which is the already-extracted inside of a
    balanced call's parens."""
    spans: List[Tuple[int, int]] = []
    depth = 0
    i = 0
    n = len(text)
    start = 0
    while i < n:
        c = text[i]
        if c in ("'", "$"):
            new_i = _skip_string_literal(text, i)
            if new_i != i:
                i = new_i
                continue
        if c == "-":
            new_i = _skip_line_comment(text, i)
            if new_i != i:
                i = new_i
                continue
        if c == "(":
            depth += 1
            i += 1
            continue
        if c == ")":
            depth -= 1
            i += 1
            continue
        if c == "," and depth == 0:
            spans.append((start, i))
            start = i + 1
            i += 1
            continue
        i += 1
    spans.append((start, n))
    return spans


def _extract_string_literal(arg: str) -> Optional[str]:
    arg = arg.strip()
    if len(arg) >= 2 and arg[0] == "'" and arg[-1] == "'":
        return arg[1:-1].replace("''", "'")
    m = re.match(r"^\$([A-Za-z0-9_]*)\$", arg)
    if m:
        tag = m.group(0)
        if arg.endswith(tag) and len(arg) >= 2 * len(tag):
            return arg[len(tag) : -len(tag)]
    return None


def _mask_for_call_search(text: str) -> str:
    """Same-length copy of `text` with `--` line comments and string-literal
    interiors blanked to spaces (newlines preserved), so ASSERTION_CALL_RE
    only matches a real call in code -- never prose like "...makes is()
    raise..." inside a `--` comment, or an assertion name that happens to
    appear inside a quoted string. Positions are unchanged, so offsets found
    against this masked copy remain valid indices into the original `text`."""
    n = len(text)
    out = list(text)
    i = 0
    while i < n:
        c = text[i]
        if c == "-" and text[i : i + 2] == "--":
            end = _skip_line_comment(text, i)
            for k in range(i, end):
                out[k] = " "
            i = end
            continue
        if c in ("'", "$"):
            new_i = _skip_string_literal(text, i)
            if new_i != i:
                for k in range(i, new_i):
                    if out[k] != "\n":
                        out[k] = " "
                i = new_i
                continue
        i += 1
    return "".join(out)


def find_assertions(text: str) -> List[Dict]:
    out = []
    masked = _mask_for_call_search(text)
    for m in _ASSERTION_CALL_RE.finditer(masked):
        open_idx = m.end() - 1
        close_idx = _find_call_close_paren(text, open_idx)
        if close_idx == -1:
            continue
        args_text = text[open_idx + 1 : close_idx]
        spans = _scan_top_level_args(args_text)
        if not spans:
            continue
        last_start, last_end = spans[-1]
        last_arg = args_text[last_start:last_end]
        line = text.count("\n", 0, m.start()) + 1
        out.append({"func": m.group(1), "line": line, "last_arg": last_arg})
    return out


# ---------------------------------------------------------------------------
# Filename -> package resolution
# ---------------------------------------------------------------------------

def package_key_from_filename(path: Path) -> Optional[Tuple[str, str]]:
    """<schema>__<pkg>__<suffix>.sql -> (schema_lower, pkg_lower). None if the
    filename doesn't match the convention at all."""
    parts = path.stem.split("__")
    if len(parts) < 2 or not parts[0] or not parts[1]:
        return None
    return parts[0].lower(), parts[1].lower()


def is_canary(schema: str, pkg: str) -> bool:
    return schema == CANARY_NAME or pkg == CANARY_NAME or schema == SUPPORT_SCHEMA


def load_spec_clauses(spec_path: Path) -> Set[str]:
    text = spec_path.read_text()
    return set(SPEC_CLAUSE_HEADING_RE.findall(text))


# ---------------------------------------------------------------------------
# Per-file lint
# ---------------------------------------------------------------------------

def lint_pgtap_file(path: Path) -> Tuple[List[str], Dict[str, Set[str]]]:
    violations: List[str] = []
    coverage: Dict[str, Set[str]] = {}

    key = package_key_from_filename(path)
    if key is None:
        return [
            f"{path}: filename does not match the <schema>__<pkg>__*.sql convention"
        ], coverage
    schema, pkg = key
    if is_canary(schema, pkg):
        return [], coverage

    spec_path = SPEC_DIR / f"{schema}.{pkg}.md"
    if not spec_path.exists():
        return [
            f"{path}: no spec found for package {schema}.{pkg} (expected {spec_path}) -- "
            f"a test file for a package with no spec at all cannot be traced to anything"
        ], coverage

    clause_ids = load_spec_clauses(spec_path)
    text = path.read_text()
    cited: Set[str] = set()

    for a in find_assertions(text):
        desc = _extract_string_literal(a["last_arg"])
        if desc is None:
            violations.append(
                f"{path}:{a['line']}: {a['func']}() has no string-literal description "
                f"as its last argument -- cannot trace to a spec clause"
            )
            continue
        m = LEADING_CLAUSE_ID_RE.match(desc)
        if not m:
            snippet = desc[:60]
            violations.append(
                f"{path}:{a['line']}: {a['func']}() description carries no leading clause ID "
                f"(expected 'S-<PREFIX>-NNN: ...'): {snippet!r}"
            )
            continue
        cid = m.group(1)
        if cid not in clause_ids:
            violations.append(
                f"{path}:{a['line']}: cites clause {cid} which does not exist in {spec_path}"
            )
        else:
            cited.add(cid)

    coverage[f"{schema}.{pkg}"] = cited
    return violations, coverage


def lint_regress_file(path: Path) -> Tuple[List[str], Dict[str, Set[str]]]:
    violations: List[str] = []
    coverage: Dict[str, Set[str]] = {}

    key = package_key_from_filename(path)
    if key is None:
        return [
            f"{path}: filename does not match the <schema>__<pkg>__*.sql convention"
        ], coverage
    schema, pkg = key
    if is_canary(schema, pkg):
        return [], coverage

    spec_path = SPEC_DIR / f"{schema}.{pkg}.md"
    if not spec_path.exists():
        return [
            f"{path}: no spec found for package {schema}.{pkg} (expected {spec_path}) -- "
            f"a test file for a package with no spec at all cannot be traced to anything"
        ], coverage

    clause_ids = load_spec_clauses(spec_path)
    text = path.read_text()

    header_match = None
    for line in text.split("\n")[:20]:
        m = VERIFIES_HEADER_RE.search(line)
        if m:
            header_match = m
            break

    if header_match is None:
        return [
            f"{path}: no '-- verifies: S-XXX-NNN[, S-XXX-MMM...]' header found in the first "
            f"20 lines -- an expected-output test must name at least one clause it verifies"
        ], coverage

    cited_ids = CLAUSE_ID_RE.findall(header_match.group(1))
    if not cited_ids:
        return [
            f"{path}: '-- verifies:' header found but names no clause IDs: {header_match.group(0)!r}"
        ], coverage

    cited: Set[str] = set()
    for cid in cited_ids:
        if cid not in clause_ids:
            violations.append(
                f"{path}: '-- verifies:' header cites clause {cid} which does not exist in {spec_path}"
            )
        else:
            cited.add(cid)

    coverage[f"{schema}.{pkg}"] = cited
    return violations, coverage


def classify(path: Path) -> str:
    parts = [p.lower() for p in path.parts]
    return "regress" if "regress" in parts else "pgtap"


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def merge_coverage(into: Dict[str, Set[str]], src: Dict[str, Set[str]]) -> None:
    for key, ids in src.items():
        into.setdefault(key, set()).update(ids)


def print_coverage_report(coverage: Dict[str, Set[str]]) -> None:
    spec_files = sorted(
        p for p in SPEC_DIR.glob("*.md")
        if p.name not in {"TEMPLATE.md", "CHECKLIST.md", "README.md", "TEST-AMENDMENTS.md", "DYNAMIC-SQL-TRACE.md", "METHOD-REVIEW.md"}
    )
    if not spec_files:
        return
    print("\nClause coverage report (informational -- not a gate; VER-02/full coverage is Phase 4):")
    for spec_path in spec_files:
        key = spec_path.stem  # "<schema>.<pkg>"
        all_clauses = load_spec_clauses(spec_path)
        cited = coverage.get(key, set())
        covered = len(all_clauses & cited)
        total = len(all_clauses)
        print(f"  {key}: {covered}/{total} clauses cited by at least one test")


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("paths", nargs="*", type=Path, help="test files to lint (default: migration/test/{pgtap,regress/sql}/*.sql)")
    args = parser.parse_args(argv)

    if args.paths:
        targets = args.paths
    else:
        targets = []
        if PGTAP_DIR.exists():
            targets.extend(sorted(PGTAP_DIR.glob("*.sql")))
        if REGRESS_SQL_DIR.exists():
            targets.extend(sorted(REGRESS_SQL_DIR.glob("*.sql")))

    if not targets:
        print(
            f"trace_lint: 0 test files found under {PGTAP_DIR} or {REGRESS_SQL_DIR} -- nothing to check"
        )
        return 0

    total_violations = 0
    coverage: Dict[str, Set[str]] = {}
    for p in targets:
        kind = classify(p)
        violations, file_coverage = (
            lint_regress_file(p) if kind == "regress" else lint_pgtap_file(p)
        )
        merge_coverage(coverage, file_coverage)
        if violations:
            total_violations += len(violations)
            print(f"FAIL {p}:")
            for v in violations:
                print(f"  - {v}")
        else:
            print(f"OK   {p}")

    print_coverage_report(coverage)

    if total_violations:
        print(f"\ntrace_lint: {total_violations} violation(s) across {len(targets)} file(s)")
        return 1

    print(f"\ntrace_lint: {len(targets)} test file(s) OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
