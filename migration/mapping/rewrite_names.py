#!/usr/bin/env python3
"""
rewrite_names.py -- rewrite Oracle `SCHEMA.PACKAGE.OBJECT` references in an existing
code base to the definitive PostgreSQL `schema.package_object` names (CLI-01).

Python 3.12, stdlib only (argparse, csv, re, json, difflib, pathlib) -- matching
Phase 1's D-B. The ONLY source of names is migration/mapping/name-map.csv (INV-03);
this tool never invents a name and never re-derives one from ddl/src.

What it rewrites (in this order of precedence, longest match first):

  R1  three-part routine reference      TT.TICKET_INTERFACE.change_status
                                      -> tt.ticket_interface_change_status
      (quoted variants "TT"."TICKET_INTERFACE"."CHANGE_STATUS" collapse to the
      unquoted lower-case PostgreSQL name; whitespace around the dots is tolerated;
      a backslash-escaped dot `\\.` -- as found inside regular expressions stored in
      data such as mss.key.regexp -- is tolerated as a separator too)
  R2  dynamic prefix                    'tt.escalation_interface.' || v_name
                                      -> 'tt.escalation_interface_' || v_name
      (a three-part name that is cut after the package dot inside a string literal,
      before a quote, a `(` or end of line -- the shape dynamically fabricated SQL
      takes; the suffix is concatenated at run time, so only the prefix can be
      rewritten; every R2 hit is also listed in the report so a human can confirm
      the run-time suffix is a routine of that package)
  R3  public-synonym reference          plog.debug(...)  /  OSAG_IP.num2ip(...)
                                      -> osag.osag_plog_debug / mss.osag_ip_num2ip
      (synonym names come from name-map.csv's oracle_synonym column -- PostgreSQL
      has no public synonyms, so these must become schema-qualified)
  R4  bare same-schema reference        event_interface.addevent_new(...)
                                      -> tt.event_interface_addevent_new
      (PL/SQL inside schema TT may omit the schema; the package name alone is
      unambiguous for every package in the corpus except OSAG_IMPLICATION, which
      exists in AUTH and GUMA2 -- for that one pass --default-schema, otherwise the
      reference is reported, not rewritten)
  R5  anonymous-block call wrappers     BEGIN tt.util.check_ticket_status; END;
      (opt-in, --rewrite-blocks)      -> CALL tt.util_check_ticket_status();
      (client code typically wraps a PL/SQL procedure call in BEGIN ... END; a
      PostgreSQL PROCEDURE is invoked with CALL; only pg_kind=procedure entries are
      rewritten, and only the simple one-statement block shape)

What it REPORTS but deliberately does not rewrite:

  P1  package-only references          GRANT EXECUTE ON tt.ticket_interface TO x
      (PostgreSQL has no package object to grant on; the report lists every
      PostgreSQL routine the package expands to, so the grant can be fanned out)
  P2  unknown member of a known package osag_msg.smtp_headers_t, pkg.CONSTANT
      (package types, constants and variables have no name-map row: they need a
      hand decision -- see migration/mapping/sqlstate-map.md for the *_STATE
      exception constants)

Usage:
  rewrite_names.py [--write | --dry-run] [--report FILE] [--default-schema S]
                   [--no-bare] [--rewrite-blocks] [--ext .sql,.pl,...] PATH...
  rewrite_names.py --emit-csv FILE      the definitive 3-part -> 2-part mapping
  rewrite_names.py --emit-sed FILE      GNU sed -E script (R1/R3 only, see notes)
  rewrite_names.py --emit-sql FILE      pgmig.oracle_name_map loader + rewrite fn

Dry-run (the default) prints a unified diff per file and a summary; --write edits
files in place. Exit code 0 when nothing unresolvable was found, 2 when the report
contains P1/P2/ambiguous-R4 items (so CI can gate on "every reference is settled").
"""
from __future__ import annotations

import argparse
import csv
import difflib
import json
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

MAPPING_DIR = Path(__file__).resolve().parent
DEFAULT_NAME_MAP_PATH = MAPPING_DIR / "name-map.csv"

DEFAULT_EXTS = (".sql", ".pls", ".pks", ".pkb", ".prc", ".fnc", ".trg",
                ".pl", ".pm", ".t", ".java", ".kt", ".groovy", ".scala",
                ".py", ".sh", ".xml", ".properties", ".yaml", ".yml", ".txt", ".csv")

IDENT = r'[A-Za-z_][A-Za-z0-9_]*'  # $/# never occur in a routine name in this corpus
# a dot separator, tolerating whitespace and a regex-escaping backslash (`\.`)
DOT = r'\s*\\?\.\s*'
# identifier boundaries: not preceded/followed by an identifier char or a quote.
# `$`/`#` are legal in Oracle identifiers but no routine name here uses them; they are
# excluded from IDENT and from the boundary classes, so a name at the end of a stored
# regular expression (`...escalate_os$`) still matches.
LB = r'(?<![A-Za-z0-9_"])'
RB = r'(?![A-Za-z0-9_"])'


class NameMap:
    """Lookup tables built from name-map.csv. All keys are lower-cased."""

    def __init__(self, rows: List[Dict[str, str]]):
        self.routines: Dict[Tuple[str, str, str], Dict[str, str]] = {}
        self.by_package: Dict[Tuple[str, str], List[Dict[str, str]]] = defaultdict(list)
        self.synonyms: Dict[str, Tuple[str, str]] = {}
        self.package_schemas: Dict[str, Set[str]] = defaultdict(set)
        for r in rows:
            if r["kind"] != "package_routine" or not r["oracle_package"]:
                continue
            s, p, o = (r["oracle_schema"].lower(), r["oracle_package"].lower(), r["oracle_object"].lower())
            self.routines[(s, p, o)] = r
            self.by_package[(s, p)].append(r)
            self.package_schemas[p].add(s)
            syn = (r.get("oracle_synonym") or "").strip().lower()
            if syn:
                self.synonyms[syn] = (s, p)

    def pg_name(self, s: str, p: str, o: str) -> Optional[str]:
        r = self.routines.get((s, p, o))
        return f'{r["pg_schema"]}.{r["pg_object_name"]}' if r else None

    def pg_kind(self, s: str, p: str, o: str) -> Optional[str]:
        r = self.routines.get((s, p, o))
        return r["pg_kind"] if r else None

    def pg_prefix(self, s: str, p: str) -> Optional[str]:
        rows = self.by_package.get((s, p))
        if not rows:
            return None
        # pg_object_name = <package>_<object>; the prefix is everything up to the
        # object part. Derive it from one row rather than re-deriving the rule.
        r = rows[0]
        obj = r["oracle_object"].lower()
        name = r["pg_object_name"]
        assert name.endswith(obj), (name, obj)
        return f'{r["pg_schema"]}.{name[: len(name) - len(obj)]}'

    def resolve_bare(self, p: str, default_schema: Optional[str]) -> Tuple[Optional[str], bool]:
        """(schema, ambiguous) for a bare package name."""
        schemas = self.package_schemas.get(p)
        if not schemas:
            return None, False
        if len(schemas) == 1:
            return next(iter(schemas)), False
        if default_schema and default_schema.lower() in schemas:
            return default_schema.lower(), False
        return None, True


def load_name_map(path: Path = DEFAULT_NAME_MAP_PATH) -> NameMap:
    with path.open(newline="", encoding="utf-8") as f:
        return NameMap(list(csv.DictReader(f)))


# ---------------------------------------------------------------------------
# Rewriting
# ---------------------------------------------------------------------------

RE_R1 = re.compile(
    LB + r'"?(?P<s>' + IDENT + r')"?(?P<d1>' + DOT + r')"?(?P<p>' + IDENT + r')"?' + DOT + r'"?(?P<o>' + IDENT + r')"?' + RB)
# R2: three-part prefix cut after the package dot, inside a string: followed by a
# quote, a `(` (regex alternation in data), `||`, or end of line.
RE_R2 = re.compile(
    LB + r'"?(?P<s>' + IDENT + r')"?(?P<d1>' + DOT + r')"?(?P<p>' + IDENT + r')"?' + r'\s*\\?\.(?=\s*(?:[\'"(]|\|\||$))',
    re.MULTILINE)
RE_R3R4 = re.compile(
    r'(?<![A-Za-z0-9_".])(?<!\.\s)"?(?P<p>' + IDENT + r')"?' + DOT + r'"?(?P<o>' + IDENT + r')"?' + RB)
RE_P1 = re.compile(LB + r'"?(?P<s>' + IDENT + r')"?' + DOT + r'"?(?P<p>' + IDENT + r')"?' + RB + r'(?!' + DOT + r')')


def _sep(d1: str) -> str:
    """Keep a backslash-escaped separator escaped (regex stored in data); otherwise
    normalise to a plain dot."""
    return r"\." if "\\" in d1 else "."
RE_BLOCK = re.compile(
    r'\bBEGIN\s+(?P<name>' + IDENT + r'(?:\.' + IDENT + r')?\.' + IDENT + r')\s*(?:\((?P<args>[^;]*?)\))?\s*;\s*END\s*;',
    re.IGNORECASE | re.DOTALL)


class Rewriter:
    def __init__(self, nm: NameMap, default_schema: Optional[str] = None,
                 bare: bool = True, blocks: bool = False):
        self.nm = nm
        self.default_schema = default_schema
        self.bare = bare
        self.blocks = blocks
        self.counts: Dict[str, int] = defaultdict(int)
        self.report: Dict[str, List[Dict]] = defaultdict(list)
        self._file = "<string>"

    # -- helpers -----------------------------------------------------------
    def _line_of(self, text: str, pos: int) -> int:
        return text.count("\n", 0, pos) + 1

    def _note(self, kind: str, text: str, m: re.Match, **extra) -> None:
        self.report[kind].append({"file": self._file, "line": self._line_of(text, m.start()),
                                  "text": m.group(0).strip(), **extra})

    # -- rules -------------------------------------------------------------
    def _r1(self, text: str) -> str:
        def sub(m: re.Match) -> str:
            s, p, o = (m.group("s").lower(), m.group("p").lower(), m.group("o").lower())
            pg = self.nm.pg_name(s, p, o)
            if pg:
                self.counts["R1"] += 1
                return pg.replace(".", _sep(m.group("d1")), 1)
            if (s, p) in self.nm.by_package:
                self._note("P2_unknown_member", text, m, package=f"{s}.{p}")
            return m.group(0)
        return RE_R1.sub(sub, text)

    def _r2(self, text: str) -> str:
        def sub(m: re.Match) -> str:
            s, p = m.group("s").lower(), m.group("p").lower()
            prefix = self.nm.pg_prefix(s, p)
            if not prefix:
                return m.group(0)
            self.counts["R2"] += 1
            self._note("R2_dynamic_prefix", text, m, rewritten_to=prefix,
                       members=[r["pg_object_name"] for r in self.nm.by_package[(s, p)]])
            return prefix.replace(".", _sep(m.group("d1")), 1)
        return RE_R2.sub(sub, text)

    def _r3r4(self, text: str) -> str:
        def sub(m: re.Match) -> str:
            p, o = m.group("p").lower(), m.group("o").lower()
            if p in self.nm.synonyms:
                s, real_p = self.nm.synonyms[p]
                pg = self.nm.pg_name(s, real_p, o)
                if pg:
                    self.counts["R3"] += 1
                    return pg
                self._note("P2_unknown_member", text, m, package=f"{s}.{real_p}", via="synonym")
                return m.group(0)
            if not self.bare:
                return m.group(0)
            s, ambiguous = self.nm.resolve_bare(p, self.default_schema)
            if ambiguous:
                if any((sch, p, o) in self.nm.routines for sch in self.nm.package_schemas[p]):
                    self._note("R4_ambiguous", text, m,
                               candidates=sorted(self.nm.package_schemas[p]))
                return m.group(0)
            if s is None:
                return m.group(0)
            pg = self.nm.pg_name(s, p, o)
            if pg:
                self.counts["R4"] += 1
                return pg
            self._note("P2_unknown_member", text, m, package=f"{s}.{p}", via="bare")
            return m.group(0)
        return RE_R3R4.sub(sub, text)

    def _p1(self, text: str) -> None:
        for m in RE_P1.finditer(text):
            s, p = m.group("s").lower(), m.group("p").lower()
            rows = self.nm.by_package.get((s, p))
            if rows:
                self._note("P1_package_only", text, m, package=f"{s}.{p}",
                           expands_to=sorted({f'{r["pg_schema"]}.{r["pg_object_name"]}' for r in rows}))

    def _r5(self, text: str) -> str:
        def sub(m: re.Match) -> str:
            name = m.group("name")
            # name is already rewritten to schema.pkg_obj at this point
            parts = name.lower().split(".")
            if len(parts) != 2:
                return m.group(0)
            row = next((r for r in self.nm.routines.values()
                        if r["pg_schema"] == parts[0] and r["pg_object_name"] == parts[1]), None)
            if not row or row["pg_kind"] != "procedure":
                return m.group(0)
            self.counts["R5"] += 1
            args = (m.group("args") or "").strip()
            return f"CALL {parts[0]}.{parts[1]}({args});"
        return RE_BLOCK.sub(sub, text)

    # -- entry point -------------------------------------------------------
    def rewrite(self, text: str, filename: str = "<string>") -> str:
        self._file = filename
        self._p1(text)              # report before anything is rewritten
        out = self._r1(text)
        out = self._r2(out)
        out = self._r3r4(out)
        if self.blocks:
            out = self._r5(out)
        return out

    @property
    def has_unresolved(self) -> bool:
        return any(self.report.get(k) for k in ("P1_package_only", "P2_unknown_member", "R4_ambiguous"))


# ---------------------------------------------------------------------------
# Emitters: the deliverable "regexp list" in three consumable shapes
# ---------------------------------------------------------------------------

def mapping_rows(nm: NameMap) -> List[Dict[str, str]]:
    rows = []
    seen = set()
    for (s, p, o), r in sorted(nm.routines.items()):
        pg = f'{r["pg_schema"]}.{r["pg_object_name"]}'
        key = (s, p, o)
        if key in seen:
            continue
        seen.add(key)
        rows.append({"kind": "routine", "oracle_name": f"{s}.{p}.{o}", "pg_name": pg,
                     "pg_kind": r["pg_kind"], "note": ""})
        syn = (r.get("oracle_synonym") or "").strip().lower()
        if syn:
            rows.append({"kind": "synonym", "oracle_name": f"{syn}.{o}", "pg_name": pg,
                         "pg_kind": r["pg_kind"],
                         "note": f"public synonym {syn} for {s}.{p}; PostgreSQL has no synonyms"})
    for (s, p), prs in sorted(nm.by_package.items()):
        rows.append({"kind": "dynamic_prefix", "oracle_name": f"{s}.{p}.", "pg_name": nm.pg_prefix(s, p),
                     "pg_kind": "", "note": "prefix of a dynamically built name; verify the run-time suffix"})
    return rows


def emit_csv(nm: NameMap, path: Path) -> None:
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["kind", "oracle_name", "pg_name", "pg_kind", "note"])
        w.writeheader()
        w.writerows(mapping_rows(nm))


def emit_sed(nm: NameMap, path: Path) -> None:
    lines = [
        "# GENERATED by migration/mapping/rewrite_names.py --emit-sed -- do not edit.",
        "# Apply with: sed -E -i -f client-rename.sed FILE...   (GNU sed; the I flag = case-insensitive)",
        "# Covers R1 (three-part), R3 (synonym) and R2 (dynamic prefix) rewrites. It does NOT",
        "# cover bare same-schema references (R4) nor BEGIN..END; -> CALL (R5): use the Python",
        "# tool for those. Longest patterns first so prefixes never shadow full names.",
    ]
    rows = mapping_rows(nm)
    rows.sort(key=lambda r: -len(r["oracle_name"]))
    for r in rows:
        if r["kind"] == "dynamic_prefix":
            # sed has no lookahead: capture the terminator and put it back
            sch, rest = r["oracle_name"][:-1].split(".", 1)
            pat = r"\b" + sch + r"(\\?\.)" + rest.replace(".", r"\\?\.") + r"\\?\.(['\"(]|\|\||$)"
            lines.append(f"s/{pat}/{r['pg_name'].replace('.', chr(92) + '1', 1)}\\2/Ig")
        elif r["kind"] == "synonym":
            pat = r"\b" + r["oracle_name"].replace(".", r"\s*\\?\.\s*") + r"\b"
            lines.append(f"s/{pat}/{r['pg_name']}/Ig")
        else:
            sch, rest = r["oracle_name"].split(".", 1)
            pat = r"\b" + sch + r"\s*(\\?\.)\s*" + rest.replace(".", r"\s*\\?\.\s*") + r"\b"
            lines.append(f"s/{pat}/{r['pg_name'].replace('.', chr(92) + '1', 1)}/Ig")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def emit_sql(nm: NameMap, path: Path) -> None:
    """A loader for pgmig.oracle_name_map (schema/table/function are created by
    migration/pgsql/_support/10_pgmig_name_rewrite.sql). Data rows only."""
    out = [
        "-- GENERATED by migration/mapping/rewrite_names.py --emit-sql -- do not edit.",
        "-- Requires migration/pgsql/_support/10_pgmig_name_rewrite.sql (creates pgmig.oracle_name_map).",
        "BEGIN;",
        "DELETE FROM pgmig.oracle_name_map;",
    ]
    for r in mapping_rows(nm):
        if r["kind"] == "dynamic_prefix":
            continue
        out.append("INSERT INTO pgmig.oracle_name_map (oracle_name, pg_name, kind, pg_kind) VALUES "
                   f"('{r['oracle_name']}', '{r['pg_name']}', '{r['kind']}', '{r['pg_kind']}');")
    for (s, p), _ in sorted(nm.by_package.items()):
        out.append("INSERT INTO pgmig.oracle_name_map (oracle_name, pg_name, kind, pg_kind) VALUES "
                   f"('{s}.{p}.', '{nm.pg_prefix(s, p)}', 'dynamic_prefix', '');")
    out.append("COMMIT;")
    path.write_text("\n".join(out) + "\n", encoding="utf-8")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def iter_files(paths: List[Path], exts: Tuple[str, ...]):
    for p in paths:
        if p.is_dir():
            for f in sorted(p.rglob("*")):
                if f.is_file() and f.suffix.lower() in exts and ".git" not in f.parts:
                    yield f
        elif p.is_file():
            yield p


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paths", nargs="*", type=Path)
    ap.add_argument("--name-map", type=Path, default=DEFAULT_NAME_MAP_PATH)
    ap.add_argument("--write", action="store_true", help="edit files in place (default: dry-run diff)")
    ap.add_argument("--dry-run", action="store_true", help="print unified diffs, change nothing (default)")
    ap.add_argument("--report", type=Path, help="write the JSON report (P1/P2/R2/R4 items) to FILE")
    ap.add_argument("--default-schema", help="schema to assume for an ambiguous bare package name")
    ap.add_argument("--no-bare", action="store_true", help="disable R4 (bare package.object) rewriting")
    ap.add_argument("--rewrite-blocks", action="store_true", help="enable R5 (BEGIN proc; END; -> CALL proc();)")
    ap.add_argument("--ext", default=",".join(DEFAULT_EXTS), help="comma-separated file extensions to scan")
    ap.add_argument("--emit-csv", type=Path)
    ap.add_argument("--emit-sed", type=Path)
    ap.add_argument("--emit-sql", type=Path)
    args = ap.parse_args(argv)

    nm = load_name_map(args.name_map)
    if args.emit_csv:
        emit_csv(nm, args.emit_csv); print(f"wrote {args.emit_csv}")
    if args.emit_sed:
        emit_sed(nm, args.emit_sed); print(f"wrote {args.emit_sed}")
    if args.emit_sql:
        emit_sql(nm, args.emit_sql); print(f"wrote {args.emit_sql}")
    if not args.paths:
        return 0

    rw = Rewriter(nm, default_schema=args.default_schema, bare=not args.no_bare, blocks=args.rewrite_blocks)
    exts = tuple(e if e.startswith(".") else "." + e for e in args.ext.split(","))
    changed = 0
    for f in iter_files(args.paths, exts):
        try:
            text = f.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            text = f.read_text(encoding="latin-1")
        new = rw.rewrite(text, str(f))
        if new != text:
            changed += 1
            if args.write:
                f.write_text(new, encoding="utf-8")
                print(f"rewrote {f}")
            else:
                sys.stdout.writelines(difflib.unified_diff(
                    text.splitlines(keepends=True), new.splitlines(keepends=True),
                    fromfile=str(f), tofile=str(f) + " (rewritten)"))
    print(f"\nfiles changed: {changed}; rewrites: " +
          ", ".join(f"{k}={v}" for k, v in sorted(rw.counts.items())) if rw.counts else f"\nfiles changed: {changed}")
    for kind, items in sorted(rw.report.items()):
        print(f"{kind}: {len(items)}")
        for it in items[:20]:
            print(f"  {it['file']}:{it['line']}: {it['text']}")
        if len(items) > 20:
            print(f"  ... {len(items) - 20} more (see --report)")
    if args.report:
        args.report.write_text(json.dumps({"counts": rw.counts, "report": rw.report}, indent=2) + "\n")
        print(f"wrote {args.report}")
    return 2 if rw.has_unresolved else 0


if __name__ == "__main__":
    sys.exit(main())
