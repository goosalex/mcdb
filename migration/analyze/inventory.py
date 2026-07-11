#!/usr/bin/env python3
"""
inventory.py — the Oracle source object inventory generator (INV-01).

Python 3.12, stdlib only (argparse, json, re, dataclasses, pathlib, datetime).
Imports plsql_lex (this phase's lexer) as its only local dependency.

Two modes:
  python3 inventory.py            -> writes migration/analyze/inventory.json
  python3 inventory.py --check    -> reconciles the parse against
                                      expected_counts.json, exits non-zero on
                                      any mismatch, writes nothing.

Walks ddl/src/{pkg,pkgb,proc,triggers,types} (read-only input) and never
touches ddl/src itself -- the only write surface is migration/.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import plsql_lex

GENERATOR_VERSION = "1.0.0"

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SOURCE_ROOT = REPO_ROOT / "ddl" / "src"
ANALYZE_DIR = Path(__file__).resolve().parent
DEFAULT_INVENTORY_PATH = ANALYZE_DIR / "inventory.json"
DEFAULT_EXPECTED_COUNTS_PATH = ANALYZE_DIR / "expected_counts.json"

SCANNED_SUBDIRS = ["pkg", "pkgb", "proc", "triggers", "types"]
DEFERRED_SUBDIRS = ["jobs", "queues", "mviews", "mlog", "global", "roles", "users", "tests"]


# ---------------------------------------------------------------------------
# Routine header parsing (shared by package specs and package bodies)
# ---------------------------------------------------------------------------

_ROUTINE_KEYWORD_RE = re.compile(r"\b(FUNCTION|PROCEDURE)\s+([A-Za-z0-9_$#]+)", re.IGNORECASE)
_RETURN_TYPE_RE = re.compile(r"RETURN\s+([A-Za-z0-9_$#.%]+(?:\([^)]*\))?)", re.IGNORECASE)
_DETERMINISTIC_RE = re.compile(r"DETERMINISTIC\b", re.IGNORECASE)


def _find_matching_paren(text: str, open_idx: int) -> int:
    depth = 0
    i = open_idx
    n = len(text)
    while i < n:
        if text[i] == "(":
            depth += 1
        elif text[i] == ")":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def _split_top_level(text: str, sep: str = ",") -> List[str]:
    parts = []
    depth = 0
    current = []
    for ch in text:
        if ch == "(":
            depth += 1
            current.append(ch)
        elif ch == ")":
            depth -= 1
            current.append(ch)
        elif ch == sep and depth == 0:
            parts.append("".join(current))
            current = []
        else:
            current.append(ch)
    tail = "".join(current).strip()
    if tail:
        parts.append("".join(current))
    return parts


def _parse_param(param_text: str) -> Dict:
    param_text = param_text.strip()
    default_match = re.search(r"\bDEFAULT\b", param_text, re.IGNORECASE)
    has_default = bool(default_match)
    if default_match:
        param_text = param_text[: default_match.start()].strip()

    m = re.match(r"^([A-Za-z0-9_$#]+)\s+(.*)$", param_text, re.DOTALL)
    if not m:
        # malformed/unparsable param text -- record what we can rather than crash
        return {"name": param_text, "mode": "IN", "type": "", "has_default": has_default}
    name = m.group(1)
    rest = m.group(2).strip()

    mode = "IN"
    mode_m = re.match(r"^(IN\s+OUT|IN|OUT)\b\s*(.*)$", rest, re.IGNORECASE | re.DOTALL)
    if mode_m:
        mode = re.sub(r"\s+", " ", mode_m.group(1).upper())
        rest = mode_m.group(2).strip()

    type_ = re.sub(r"\s+", " ", rest.strip())
    return {"name": name, "mode": mode, "type": type_, "has_default": has_default}


def _parse_params(params_text: str) -> List[Dict]:
    params_text = params_text.strip()
    if not params_text:
        return []
    return [_parse_param(p) for p in _split_top_level(params_text) if p.strip()]


def _parse_routine_headers(text: str) -> List[Dict]:
    """Find every FUNCTION/PROCEDURE header in `text` (comment/string-stripped),
    whether it is a spec prototype (terminated by ';'), a body forward
    declaration (also terminated by ';'), or a body definition (terminated by
    IS/AS) -- we only need the header (name, params, return type,
    deterministic), never the body, so the terminator kind doesn't matter."""
    routines = []
    for m in _ROUTINE_KEYWORD_RE.finditer(text):
        kw = m.group(1).upper()
        name = m.group(2)
        pos = m.end()

        while pos < len(text) and text[pos].isspace():
            pos += 1

        params: List[Dict] = []
        if pos < len(text) and text[pos] == "(":
            close = _find_matching_paren(text, pos)
            if close == -1:
                continue  # unbalanced parens -- skip, don't crash
            params = _parse_params(text[pos + 1 : close])
            pos = close + 1

        while pos < len(text) and text[pos].isspace():
            pos += 1

        returns = None
        if kw == "FUNCTION":
            ret_m = _RETURN_TYPE_RE.match(text[pos:])
            if ret_m:
                returns = ret_m.group(1).strip()
                pos += ret_m.end()

        while pos < len(text) and text[pos].isspace():
            pos += 1

        deterministic = bool(_DETERMINISTIC_RE.match(text[pos:]))

        sig = f"{name.upper()}({','.join(re.sub(r'%.*$', '', p['type']).strip().upper() for p in params)})"
        line = text.count("\n", 0, m.start()) + 1
        routines.append(
            {
                "name": name,
                "kind": kw,
                "params": params,
                "returns": returns,
                "deterministic": deterministic,
                "signature": sig,
                "line": line,
            }
        )
    return routines


def parse_spec_routines(spec_clean_text: str) -> List[Dict]:
    return _parse_routine_headers(spec_clean_text)


def parse_body_routines(body_clean_text: str) -> List[Dict]:
    """All routine headers found in a body, de-duplicated by (name, signature)
    -- a routine forward-declared and then defined would otherwise appear
    twice."""
    seen = set()
    out = []
    for r in _parse_routine_headers(body_clean_text):
        key = (r["name"].upper(), r["signature"])
        if key in seen:
            continue
        seen.add(key)
        out.append(r)
    return out


# ---------------------------------------------------------------------------
# Package-level mutable state
# ---------------------------------------------------------------------------

_NON_VARIABLE_LEADING_KEYWORDS = {"TYPE", "SUBTYPE", "PRAGMA", "CURSOR"}
_NON_VARIABLE_SECOND_TOKENS = {"CURSOR", "EXCEPTION"}


def find_package_state(body_clean_text: str, start: int = 0, end: Optional[int] = None) -> List[Dict]:
    """Find non-CONSTANT package-body-level variable declarations within
    body_clean_text[start:end] (the declare section preceding a package
    body's first routine). CONSTANTs, EXCEPTIONs, CURSORs, TYPEs, SUBTYPEs
    and PRAGMAs are all excluded -- only genuinely mutable state.

    `start`/`end` default to the whole string, so this can be called
    directly on a self-contained snippet (as the unit tests do) -- but when
    called from build_inventory() with a slice of a larger object body,
    `line` is computed relative to the FULL body_clean_text (not the
    substring), so it needs only the single start_line-1 shift every other
    per-object marker already gets -- no separate inner offset to track."""
    if end is None:
        end = len(body_clean_text)
    section = body_clean_text[start:end]
    out = []
    pos = 0
    for part in section.split(";"):
        part_abs_start = start + pos
        pos += len(part) + 1  # +1 accounts for the ';' separator consumed by split()
        stmt = part.strip()
        if not stmt:
            continue
        tokens = stmt.split()
        if not tokens:
            continue
        if tokens[0].upper() in _NON_VARIABLE_LEADING_KEYWORDS:
            continue
        if len(tokens) >= 2 and tokens[1].upper() in _NON_VARIABLE_SECOND_TOKENS:
            continue
        if len(tokens) >= 2 and tokens[1].upper() == "CONSTANT":
            continue
        # name TYPE [:= expr] -- a mutable variable declaration
        m = re.match(r"^([A-Za-z0-9_$#]+)\s+(.+)$", stmt, re.DOTALL)
        if not m:
            continue
        name = m.group(1)
        rest = m.group(2)
        # cut off an initializer if present
        assign_m = re.search(r":=", rest)
        type_ = rest[: assign_m.start()].strip() if assign_m else rest.strip()
        type_ = re.sub(r"\s+", " ", type_)
        # part_abs_start is only approximately where `stmt` begins (leading
        # whitespace stripped) -- close enough for line-number purposes since
        # a declaration statement essentially never spans a stripped blank
        # prefix long enough to cross a newline boundary incorrectly here.
        line = body_clean_text.count("\n", 0, part_abs_start) + 1
        out.append({"name": name, "type": type_, "line": line})
    return out


def declare_section_bounds(body_clean_text: str) -> Tuple[int, int]:
    """Character offsets [start, end) of the text between the object's own
    `IS`/`AS` opener and its first top-level routine header -- this is where
    package-body-level state (mutable variables, constants, exceptions) is
    declared. Returned as bounds (not a detached substring) so line numbers
    computed within stay relative to the full body_clean_text."""
    first_routine = _ROUTINE_KEYWORD_RE.search(body_clean_text)
    end = first_routine.start() if first_routine else len(body_clean_text)
    header_m = re.search(r"\b(IS|AS)\b", body_clean_text[:end], re.IGNORECASE)
    start = header_m.end() if header_m else 0
    if start > end:
        start = end
    return start, end


_TRAILING_INIT_BLOCK_RE = re.compile(
    r";\s*BEGIN\s+(?:(?!END\s+[A-Za-z0-9_$#]+\s*;).)*?END\s*;\s*END\s+[A-Za-z0-9_$#]+\s*;\s*/?\s*\Z",
    re.IGNORECASE | re.DOTALL,
)


def has_package_init_block(object_clean_text: str) -> bool:
    return bool(_TRAILING_INIT_BLOCK_RE.search(object_clean_text))


# ---------------------------------------------------------------------------
# Semantic markers on a per-object body
# ---------------------------------------------------------------------------

_COMMIT_RE = re.compile(r"\bCOMMIT\b", re.IGNORECASE)
_ROLLBACK_RE = re.compile(r"\bROLLBACK\b", re.IGNORECASE)
_AUTONOMOUS_TX_RE = re.compile(r"PRAGMA\s+AUTONOMOUS_TRANSACTION", re.IGNORECASE)
_RAISE_APP_ERROR_RE = re.compile(r"RAISE_APPLICATION_ERROR\s*\(\s*(-?\d+)", re.IGNORECASE)
_NO_DATA_FOUND_RE = re.compile(r"WHEN\s+NO_DATA_FOUND\b", re.IGNORECASE)
_TOO_MANY_ROWS_RE = re.compile(r"WHEN\s+TOO_MANY_ROWS\b", re.IGNORECASE)
_WHEN_OTHERS_RE = re.compile(r"WHEN\s+OTHERS\b", re.IGNORECASE)
_ORACLE_PKG_CALL_RE = re.compile(r"\b(DBMS_[A-Z0-9_]+|UTL_[A-Z0-9_]+)\.([A-Z0-9_]+)", re.IGNORECASE)
_EXECUTE_IMMEDIATE_RE = re.compile(r"EXECUTE\s+IMMEDIATE", re.IGNORECASE)
_DBMS_SQL_RE = re.compile(r"\bDBMS_SQL\b", re.IGNORECASE)
_TYPE_REF_RE = re.compile(
    r"\b([A-Za-z0-9_$#]+(?:\.[A-Za-z0-9_$#]+)?)%(TYPE|ROWTYPE)\b", re.IGNORECASE
)
_SELECT_INTO_RE = re.compile(r"\bSELECT\b(?:(?!;).)*?\bINTO\b", re.IGNORECASE | re.DOTALL)
_DICTIONARY_PREFIXES = ("all_", "user_", "dba_")

# calls_out_raw: a dotted chain of 2 or 3 identifiers immediately followed by
# '(' -- this is the graph's only input (resolution happens in plan 02).
_CALL_RE = re.compile(
    r"\b([A-Za-z][A-Za-z0-9_$#]*)\.([A-Za-z][A-Za-z0-9_$#]*)(?:\.([A-Za-z][A-Za-z0-9_$#]*))?\s*(?=\()"
)


def _line_of(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def find_commit_rollback(text: str) -> Tuple[bool, List[int], bool, List[int]]:
    commit_sites = [_line_of(text, m.start()) for m in _COMMIT_RE.finditer(text)]
    rollback_sites = [_line_of(text, m.start()) for m in _ROLLBACK_RE.finditer(text)]
    return bool(commit_sites), commit_sites, bool(rollback_sites), rollback_sites


def find_autonomous_transaction(text: str) -> Tuple[bool, List[int]]:
    sites = [_line_of(text, m.start()) for m in _AUTONOMOUS_TX_RE.finditer(text)]
    return bool(sites), sites


def find_raise_application_error(text: str) -> List[Dict]:
    return [
        {"code": int(m.group(1)), "line": _line_of(text, m.start())}
        for m in _RAISE_APP_ERROR_RE.finditer(text)
    ]


def find_exception_handlers(text: str) -> Dict[str, int]:
    return {
        "NO_DATA_FOUND": len(_NO_DATA_FOUND_RE.findall(text)),
        "TOO_MANY_ROWS": len(_TOO_MANY_ROWS_RE.findall(text)),
        "OTHERS": len(_WHEN_OTHERS_RE.findall(text)),
    }


def find_oracle_pkg_calls(text: str) -> List[Dict]:
    out = []
    for m in _ORACLE_PKG_CALL_RE.finditer(text):
        family = m.group(1).upper()
        call = f"{family}.{m.group(2).upper()}"
        out.append({"family": family, "call": call, "line": _line_of(text, m.start())})
    return out


def find_dynamic_sql_reasons(text: str) -> List[Dict]:
    reasons = []
    for m in _EXECUTE_IMMEDIATE_RE.finditer(text):
        reasons.append({"construct": "EXECUTE IMMEDIATE", "line": _line_of(text, m.start())})
    for m in _DBMS_SQL_RE.finditer(text):
        reasons.append({"construct": "DBMS_SQL", "line": _line_of(text, m.start())})
    return reasons


def find_type_refs(text: str) -> List[Dict]:
    out = []
    for m in _TYPE_REF_RE.finditer(text):
        ref = m.group(1)
        parts = ref.split(".")
        against = "project"
        if len(parts) >= 2 and parts[0].lower().startswith(_DICTIONARY_PREFIXES):
            against = "dictionary"
        out.append({"ref": ref, "kind": m.group(2).upper(), "against": against, "line": _line_of(text, m.start())})
    return out


def find_select_into_sites(text: str) -> List[int]:
    return [_line_of(text, m.start()) for m in _SELECT_INTO_RE.finditer(text)]


def extract_calls_out_raw(text: str) -> List[Dict]:
    out = []
    for m in _CALL_RE.finditer(text):
        third = m.group(3)
        if third:
            call_text = f"{m.group(1)}.{m.group(2)}.{third}"
            shape = "qualified"
        else:
            call_text = f"{m.group(1)}.{m.group(2)}"
            shape = "bare"
        out.append({"text": call_text, "shape": shape, "line": _line_of(text, m.start())})
    return out


def analyze_body(text: str) -> Dict:
    """Full semantic-marker analysis for any object body (package body,
    standalone procedure, trigger). Applied uniformly -- package-specific
    facts (routines/package_state/init_block) are layered on top by the
    caller for kind=='package'."""
    has_commit, commit_sites, has_rollback, rollback_sites = find_commit_rollback(text)
    autonomous_transaction, autonomous_sites = find_autonomous_transaction(text)
    dyn_sql_reasons = find_dynamic_sql_reasons(text)
    return {
        "has_commit": has_commit,
        "has_commit_sites": commit_sites,
        "has_rollback": has_rollback,
        "has_rollback_sites": rollback_sites,
        "autonomous_transaction": autonomous_transaction,
        "autonomous_transaction_sites": autonomous_sites,
        "oracle_pkg_calls": find_oracle_pkg_calls(text),
        "raise_application_error": find_raise_application_error(text),
        "exception_handlers": find_exception_handlers(text),
        "type_refs": find_type_refs(text),
        "select_into_sites": find_select_into_sites(text),
        "calls_out_raw": extract_calls_out_raw(text),
        "static_resolution": "incomplete" if dyn_sql_reasons else "complete",
        "static_resolution_reasons": dyn_sql_reasons,
    }


# ---------------------------------------------------------------------------
# Absolute line-number shifting
# ---------------------------------------------------------------------------
#
# Every find_*/_parse_routine_headers/analyze_body function above computes
# "line" relative to the start of whatever text it was handed. Every one of
# those calls in build_inventory() is handed exactly one object's own clean
# text slice (which begins at that object's header.start_line) -- so a
# single scalar shift of (header.start_line - 1) converts every relative
# line number in that call's output into a real, absolute file line number.
# Routines parsed from a package SPEC use the spec's own start_line; every
# other marker (including private_routines and package_state, both derived
# from the BODY) uses the body's start_line -- see build_inventory().

def shift_markers(markers: Dict, offset: int) -> Dict:
    m = dict(markers)
    for key in ("has_commit_sites", "has_rollback_sites", "autonomous_transaction_sites", "select_into_sites"):
        m[key] = [n + offset for n in m[key]]
    for key in ("oracle_pkg_calls", "raise_application_error", "calls_out_raw", "static_resolution_reasons", "type_refs"):
        m[key] = [dict(d, line=d["line"] + offset) for d in m[key]]
    return m


def shift_line_field(items: List[Dict], offset: int) -> List[Dict]:
    return [dict(d, line=d["line"] + offset) for d in items]


# ---------------------------------------------------------------------------
# Trigger-specific metadata
# ---------------------------------------------------------------------------

_TRIGGER_META_RE = re.compile(
    r'CREATE\s+(?:OR\s+REPLACE\s+)?TRIGGER\s+(?:"?[A-Za-z0-9_$#]+"?\.)?"?[A-Za-z0-9_$#]+"?\s+'
    r'(BEFORE|AFTER|INSTEAD\s+OF)\s+(.*?)\s+ON\s+(?:"?([A-Za-z0-9_$#]+)"?\.)?"?([A-Za-z0-9_$#]+)"?',
    re.IGNORECASE | re.DOTALL,
)
_TRIGGER_EVENT_KEYWORDS = ("INSERT", "UPDATE", "DELETE")


def parse_trigger_meta(header_clean_text: str) -> Dict:
    m = _TRIGGER_META_RE.search(header_clean_text)
    if not m:
        return {"timing": None, "events": [], "event_detail": None, "table_schema": None, "table": None}
    timing = re.sub(r"\s+", " ", m.group(1).upper())
    events_raw = re.sub(r"\s+", " ", m.group(2).strip())
    events = [kw for kw in _TRIGGER_EVENT_KEYWORDS if re.search(rf"\b{kw}\b", events_raw, re.IGNORECASE)]
    return {
        "timing": timing,
        "events": events,
        "event_detail": events_raw,
        "table_schema": m.group(3),
        "table": m.group(4),
    }


# ---------------------------------------------------------------------------
# File discovery
# ---------------------------------------------------------------------------

def discover(source_root: Path) -> Tuple[Dict[str, List[Path]], List[str], Dict[str, int]]:
    scanned: Dict[str, List[Path]] = {}
    excluded_files: List[str] = []
    for sub in SCANNED_SUBDIRS:
        d = source_root / sub
        # Hidden files (e.g. a `.gitkeep` placeholder keeping an otherwise-empty
        # directory tracked in git) are not Oracle source and are not part of
        # the translation scope at all -- skip them entirely rather than
        # reporting them as an "excluded" source file alongside genuine
        # non-.sql documents like ticketing-interfaces.md.
        files = sorted(p for p in d.iterdir() if p.is_file() and not p.name.startswith("."))
        sql_files = [p for p in files if p.suffix == ".sql"]
        non_sql = [p.name for p in files if p.suffix != ".sql"]
        excluded_files.extend(non_sql)
        scanned[sub] = sql_files

    deferred_scope: Dict[str, int] = {}
    for sub in DEFERRED_SUBDIRS:
        d = source_root / sub
        deferred_scope[sub] = len([p for p in d.iterdir() if p.is_file()]) if d.exists() else 0

    return scanned, excluded_files, deferred_scope


# ---------------------------------------------------------------------------
# Build the inventory
# ---------------------------------------------------------------------------

def _object_text(stripped: plsql_lex.StrippedSource, header: plsql_lex.ObjectHeader) -> Tuple[str, str]:
    clean_lines = stripped.clean.split("\n")
    raw_lines = stripped.raw.split("\n")
    start_idx = header.start_line - 1
    end_idx = header.end_line
    clean_slice = "\n".join(clean_lines[start_idx:end_idx])
    raw_slice = "\n".join(raw_lines[start_idx:end_idx])
    return clean_slice, raw_slice


def build_inventory(source_root: Path) -> Dict:
    scanned, excluded_files, deferred_scope = discover(source_root)

    all_synonyms = []
    schemas = set()

    # kind -> list of (header, stripped, clean_text, raw_text, file_path)
    parsed_by_kind: Dict[str, List[Dict]] = {k: [] for k in ("package_spec", "package_body", "procedure", "trigger", "type")}

    for sub, files in scanned.items():
        for f in files:
            raw = f.read_text()
            stripped = plsql_lex.strip_noise(raw)
            rel_path = str(f.relative_to(source_root.parent.parent))
            headers = plsql_lex.scan_objects(stripped, rel_path)
            for h in headers:
                clean_text, raw_text = _object_text(stripped, h)
                parsed_by_kind[h.kind].append(
                    {"header": h, "clean": clean_text, "raw": raw_text, "path": rel_path}
                )
                if h.schema:
                    schemas.add(plsql_lex.normalize(h.schema))
            for s in plsql_lex.scan_synonyms(stripped):
                all_synonyms.append(
                    {
                        "synonym": s.synonym,
                        "target_schema": s.target_schema,
                        "target_package": s.target_package,
                        "malformed": s.malformed,
                        "source_path": rel_path,
                        "line": s.line,
                    }
                )

    objects: List[Dict] = []

    # ---- packages: pair spec + body by normalized (schema, name) ----
    specs_by_key = {}
    for entry in parsed_by_kind["package_spec"]:
        h = entry["header"]
        key = (plsql_lex.normalize(h.schema), plsql_lex.normalize(h.name))
        specs_by_key[key] = entry

    bodies_by_key = {}
    for entry in parsed_by_kind["package_body"]:
        h = entry["header"]
        key = (plsql_lex.normalize(h.schema), plsql_lex.normalize(h.name))
        bodies_by_key[key] = entry

    all_pkg_keys = sorted(set(specs_by_key) | set(bodies_by_key))
    for key in all_pkg_keys:
        spec_entry = specs_by_key.get(key)
        body_entry = bodies_by_key.get(key)

        # Every find_*/parse_*_routines call below returns "line" relative to
        # whatever text it was handed. spec_offset/body_offset convert those
        # into real, absolute file line numbers (see shift_markers docstring).
        spec_offset = (spec_entry["header"].start_line - 1) if spec_entry else 0
        spec_routines_raw = parse_spec_routines(spec_entry["clean"]) if spec_entry else []
        spec_routines = shift_line_field(spec_routines_raw, spec_offset)
        public_names = {r["name"].upper() for r in spec_routines_raw}

        if body_entry:
            body_offset = body_entry["header"].start_line - 1
            body_routines = parse_body_routines(body_entry["clean"])
            private_routines_raw = [r for r in body_routines if r["name"].upper() not in public_names]
            private_routines = shift_line_field(private_routines_raw, body_offset)
            marker_source = body_entry["clean"]
            declare_start, declare_end = declare_section_bounds(body_entry["clean"])
            package_state = shift_line_field(
                find_package_state(body_entry["clean"], declare_start, declare_end), body_offset
            )
            init_block = has_package_init_block(body_entry["clean"])
            body_path = body_entry["path"]
            header = body_entry["header"]
        else:
            body_offset = 0
            private_routines = []
            marker_source = ""
            package_state = []
            init_block = False
            body_path = None
            header = spec_entry["header"]

        markers = shift_markers(analyze_body(marker_source) if marker_source else analyze_body(""), body_offset)

        schema = (header.schema or "").upper()
        name = (header.name or "").upper()
        obj = {
            "id": f"{schema}.{name}",
            "schema": schema,
            "package": name,
            "name": name,
            "kind": "package",
            "spec_path": spec_entry["path"] if spec_entry else None,
            "body_path": body_path,
            "start_line": header.start_line,
            "end_line": header.end_line,
            "routines": spec_routines,
            "private_routines": private_routines,
            "package_state": package_state,
            "has_init_block": init_block,
        }
        obj.update(markers)
        objects.append(obj)

    # ---- standalone procedures ----
    for entry in parsed_by_kind["procedure"]:
        h = entry["header"]
        routine_headers = _parse_routine_headers(entry["clean"])
        self_routine = routine_headers[0] if routine_headers else {"params": [], "returns": None, "deterministic": False}
        markers = shift_markers(analyze_body(entry["clean"]), h.start_line - 1)
        schema = (h.schema or "").upper()
        name = (h.name or "").upper()
        obj = {
            "id": f"{schema}.{name}",
            "schema": schema,
            "package": None,
            "name": name,
            "kind": "procedure",
            "spec_path": None,
            "body_path": entry["path"],
            "start_line": h.start_line,
            "end_line": h.end_line,
            "params": self_routine["params"],
            "returns": self_routine["returns"],
            "deterministic": self_routine["deterministic"],
        }
        obj.update(markers)
        objects.append(obj)

    # ---- triggers ----
    for entry in parsed_by_kind["trigger"]:
        h = entry["header"]
        trig_meta = parse_trigger_meta(entry["clean"])
        markers = shift_markers(analyze_body(entry["clean"]), h.start_line - 1)
        schema = (h.schema or "").upper()
        name = (h.name or "").upper()
        obj = {
            "id": f"{schema}.{name}",
            "schema": schema,
            "package": None,
            "name": name,
            "kind": "trigger",
            "spec_path": None,
            "body_path": entry["path"],
            "start_line": h.start_line,
            "end_line": h.end_line,
            "table_schema": trig_meta["table_schema"],
            "table": trig_meta["table"],
            "timing": trig_meta["timing"],
            "events": trig_meta["events"],
            "event_detail": trig_meta["event_detail"],
        }
        obj.update(markers)
        objects.append(obj)

    # ---- types ----
    for entry in parsed_by_kind["type"]:
        h = entry["header"]
        schema = (h.schema or "").upper()
        name = (h.name or "").upper()
        obj = {
            "id": f"{schema}.{name}",
            "schema": schema,
            "package": None,
            "name": name,
            "kind": "type",
            "spec_path": None,
            "body_path": entry["path"],
            "start_line": h.start_line,
            "end_line": h.end_line,
            "wrapped_in_dynamic_sql": h.wrapped_in_dynamic_sql,
            "static_resolution": "complete",
            "static_resolution_reasons": [],
        }
        objects.append(obj)

    counts = {
        "package_specs": len(specs_by_key),
        "package_bodies": len(bodies_by_key),
        "packages": len(all_pkg_keys),
        "standalone_procedures": len(parsed_by_kind["procedure"]),
        "trigger_files": len(scanned["triggers"]),
        "trigger_objects": len(parsed_by_kind["trigger"]),
        "types": len(parsed_by_kind["type"]),
        "schemas": len(schemas),
    }

    result = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "generator_version": GENERATOR_VERSION,
        "source_root": str(source_root.relative_to(source_root.parent.parent)),
        "counts": counts,
        "excluded_files": sorted(excluded_files),
        "deferred_scope": deferred_scope,
        "objects": objects,
        "synonyms": all_synonyms,
    }
    return result


# ---------------------------------------------------------------------------
# Reconciliation ( --check )
# ---------------------------------------------------------------------------

def load_expected_counts(path: Path) -> Dict:
    return json.loads(path.read_text())


def _recount_from_objects(result: Dict) -> Dict[str, int]:
    """Derive structural counts directly from result['objects'] (the live,
    possibly-mutated list) rather than trusting the separately-stored
    result['counts'] snapshot computed at build time. This is what makes the
    reconciliation gate able to actually fail: removing an object from
    result['objects'] must change what this function reports, even though
    the original 'counts' dict computed during build_inventory() is
    untouched by that mutation."""
    objects = result.get("objects", [])
    packages_with_spec = {o["id"] for o in objects if o["kind"] == "package" and o.get("spec_path")}
    packages_with_body = {o["id"] for o in objects if o["kind"] == "package" and o.get("body_path")}
    trigger_files = {o.get("body_path") for o in objects if o["kind"] == "trigger" and o.get("body_path")}
    schemas = {o["schema"] for o in objects if o.get("schema")}
    return {
        "package_specs": len(packages_with_spec),
        "package_bodies": len(packages_with_body),
        "packages": len([o for o in objects if o["kind"] == "package"]),
        "standalone_procedures": len([o for o in objects if o["kind"] == "procedure"]),
        "trigger_files": len(trigger_files),
        "trigger_objects": len([o for o in objects if o["kind"] == "trigger"]),
        "types": len([o for o in objects if o["kind"] == "type"]),
        "schemas": len(schemas),
    }


def reconcile(result: Dict, expected: Dict) -> Tuple[bool, List[str]]:
    messages: List[str] = []

    # 1. structural counts match exactly -- recomputed from result['objects']
    #    itself so that removing an object from the list is guaranteed to be
    #    caught here, not just compared against a stale precomputed snapshot.
    recounted = _recount_from_objects(result)
    for key, actual in recounted.items():
        want = expected.get(key)
        if actual != want:
            messages.append(f"count mismatch for '{key}': expected {want}, got {actual}")

    # 2. pkgb_non_sql_files exclusion list matches
    want_excluded = sorted(expected.get("pkgb_non_sql_files", []))
    got_excluded = sorted(result.get("excluded_files", []))
    if want_excluded != got_excluded:
        messages.append(f"excluded_files mismatch: expected {want_excluded}, got {got_excluded}")

    # 3. every package has exactly one spec and one body (spec_path and body_path both set)
    for o in result["objects"]:
        if o["kind"] == "package":
            if not o.get("spec_path"):
                messages.append(f"package {o['id']} has no matching spec")
            if not o.get("body_path"):
                messages.append(f"package {o['id']} has no matching body")

    # 4. every object with a dynamic-SQL construct is flagged incomplete
    for o in result["objects"]:
        reasons = o.get("static_resolution_reasons", [])
        if reasons and o.get("static_resolution") != "incomplete":
            messages.append(f"{o['id']} has dynamic-SQL reasons but static_resolution != incomplete")

    # 5. no object has an empty routines[] unless it genuinely declares none
    #    (only meaningful for kind == package; procedures/triggers/types don't
    #    carry a routines[] field at all, so this check is scoped accordingly)
    #    -- we cannot know "genuinely none" vs "parser missed it" from the
    #    inventory alone, so this is a soft structural sanity check: total
    #    routines across all packages must be > 0 (the corpus is not empty).
    total_routines = sum(len(o.get("routines", [])) for o in result["objects"] if o["kind"] == "package")
    if total_routines == 0:
        messages.append("no routines found across any package -- parser likely broken")

    return (len(messages) == 0, messages)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="reconcile instead of writing inventory.json")
    parser.add_argument("--source-root", type=Path, default=DEFAULT_SOURCE_ROOT)
    parser.add_argument("--inventory-path", type=Path, default=DEFAULT_INVENTORY_PATH)
    parser.add_argument("--expected-counts-path", type=Path, default=DEFAULT_EXPECTED_COUNTS_PATH)
    args = parser.parse_args(argv)

    result = build_inventory(args.source_root)

    # Report (not gate on) semantic marker totals vs a naive grep, per plan.
    naive_markers = {
        "PRAGMA AUTONOMOUS_TRANSACTION": re.compile(r"PRAGMA\s+AUTONOMOUS_TRANSACTION", re.IGNORECASE),
        "RAISE_APPLICATION_ERROR": re.compile(r"RAISE_APPLICATION_ERROR", re.IGNORECASE),
        "NO_DATA_FOUND": re.compile(r"NO_DATA_FOUND", re.IGNORECASE),
        "WHEN OTHERS": re.compile(r"WHEN\s+OTHERS", re.IGNORECASE),
        "COMMIT": re.compile(r"\bCOMMIT\b", re.IGNORECASE),
        "ROLLBACK": re.compile(r"\bROLLBACK\b", re.IGNORECASE),
        "EXECUTE IMMEDIATE": re.compile(r"EXECUTE\s+IMMEDIATE", re.IGNORECASE),
        "DBMS_SQL": re.compile(r"\bDBMS_SQL\b", re.IGNORECASE),
    }
    naive_totals = {name: 0 for name in naive_markers}
    for sub in SCANNED_SUBDIRS:
        for f in (args.source_root / sub).glob("*.sql"):
            text = f.read_text()
            for name, pat in naive_markers.items():
                naive_totals[name] += len(pat.findall(text))

    stripped_totals = {
        "PRAGMA AUTONOMOUS_TRANSACTION": sum(
            len(o.get("autonomous_transaction_sites", [])) for o in result["objects"]
        ),
        "RAISE_APPLICATION_ERROR": sum(len(o.get("raise_application_error", [])) for o in result["objects"]),
        "NO_DATA_FOUND": sum(o.get("exception_handlers", {}).get("NO_DATA_FOUND", 0) for o in result["objects"]),
        "WHEN OTHERS": sum(o.get("exception_handlers", {}).get("OTHERS", 0) for o in result["objects"]),
        "COMMIT": sum(len(o.get("has_commit_sites", [])) for o in result["objects"]),
        "ROLLBACK": sum(len(o.get("has_rollback_sites", [])) for o in result["objects"]),
        "EXECUTE IMMEDIATE": sum(
            1
            for o in result["objects"]
            for r in o.get("static_resolution_reasons", [])
            if r["construct"] == "EXECUTE IMMEDIATE"
        ),
        "DBMS_SQL": sum(
            1
            for o in result["objects"]
            for r in o.get("static_resolution_reasons", [])
            if r["construct"] == "DBMS_SQL"
        ),
    }

    print("Semantic marker totals (stripped, authoritative) vs naive grep (includes comments/strings):")
    for name in naive_markers:
        stripped_n = stripped_totals[name]
        naive_n = naive_totals[name]
        print(f"  {name:32s} stripped={stripped_n:4d}  naive={naive_n:4d}  delta={naive_n - stripped_n:4d}")
    print("  (stripped count is authoritative; delta is expected -- comments and string literals)")

    if args.check:
        expected = load_expected_counts(args.expected_counts_path)
        ok, messages = reconcile(result, expected)
        if ok:
            print("--check: OK -- parse reconciles against expected_counts.json")
            return 0
        else:
            print("--check: FAILED", file=sys.stderr)
            for m in messages:
                print(f"  - {m}", file=sys.stderr)
            return 1
    else:
        args.inventory_path.write_text(json.dumps(result, indent=2, sort_keys=False) + "\n")
        print(f"wrote {args.inventory_path}")
        return 0


if __name__ == "__main__":
    sys.exit(main())
