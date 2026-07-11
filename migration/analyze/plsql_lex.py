"""
plsql_lex.py — comment/string-stripping lexer and top-level object header
scanner for Oracle PL/SQL source under ddl/src.

Library only (no CLI). Python 3.12 stdlib only (re, dataclasses, pathlib,
bisect, typing) — see PROJECT.md decision D-B.

Every downstream matcher in this migration pipeline must run against
`StrippedSource.clean`, never `.raw` — `raw` is retained only for the small
set of callers that genuinely need original text (the EXECUTE IMMEDIATE
-wrapped TYPE case, and the `--changeset` directive extraction, both of
which are themselves comments/strings that `clean` has already blanked).
"""
from __future__ import annotations

import re
from bisect import bisect_right
from dataclasses import dataclass, field
from typing import List, Optional


# ---------------------------------------------------------------------------
# Changeset directives
# ---------------------------------------------------------------------------

@dataclass
class Changeset:
    author: str
    id: str
    line: int


_CHANGESET_RE = re.compile(r"^--changeset\s+([^:\s]+):(\S+)", re.IGNORECASE | re.MULTILINE)


# ---------------------------------------------------------------------------
# strip_noise
# ---------------------------------------------------------------------------

@dataclass
class StrippedSource:
    raw: str
    clean: str
    changesets: List[Changeset] = field(default_factory=list)
    _line_starts: List[int] = field(default_factory=list, repr=False)

    def line_of(self, offset: int) -> int:
        """Map a 0-based character offset (in either `raw` or `clean` — they
        share identical newline positions by construction) to a 1-based
        source line number."""
        idx = bisect_right(self._line_starts, offset) - 1
        return idx + 1


def _compute_line_starts(text: str) -> List[int]:
    starts = [0]
    for i, ch in enumerate(text):
        if ch == "\n":
            starts.append(i + 1)
    return starts


def strip_noise(text: str) -> StrippedSource:
    """Length-preserving blanker: walks `text` once as a character-state
    machine over {CODE, LINE_COMMENT, BLOCK_COMMENT, STRING, QUOTED_IDENT}.

    Every character inside a `--` line comment, a `/* ... */` block comment,
    or a single-quoted string literal is replaced with a space — EXCEPT
    newlines, which are always preserved verbatim so that byte offsets and
    line numbers in `clean` map 1:1 back to `raw`. Doubled single-quotes
    inside string literals (Oracle's escape for a literal quote) do not
    terminate the string early. Double-quoted identifiers are skipped over
    without blanking (their content is meaningful, not noise).

    This is NOT implemented via regex removal — nested quote/comment
    interleavings in this source (e.g. a `'` inside a doc comment, or `--`
    inside a string literal) would defeat a regex-based approach.
    """
    n = len(text)
    out = list(text)
    i = 0
    while i < n:
        c = text[i]

        if c == "-" and i + 1 < n and text[i + 1] == "-":
            # line comment: blank through end of line, keep the newline itself
            while i < n and text[i] != "\n":
                out[i] = " "
                i += 1
            continue

        if c == "/" and i + 1 < n and text[i + 1] == "*":
            out[i] = " "
            out[i + 1] = " "
            i += 2
            while i < n and not (text[i] == "*" and i + 1 < n and text[i + 1] == "/"):
                if text[i] != "\n":
                    out[i] = " "
                i += 1
            if i < n:
                out[i] = " "
                if i + 1 < n:
                    out[i + 1] = " "
                    i += 2
                else:
                    i += 1
            continue

        if c == "'":
            out[i] = " "
            i += 1
            while i < n:
                if text[i] == "'":
                    if i + 1 < n and text[i + 1] == "'":
                        # doubled quote: escaped literal quote, stays in the string
                        out[i] = " "
                        out[i + 1] = " "
                        i += 2
                        continue
                    out[i] = " "
                    i += 1
                    break
                if text[i] != "\n":
                    out[i] = " "
                i += 1
            continue

        if c == '"':
            # quoted identifier: content is meaningful (an actual identifier),
            # so it is left untouched — just walk past it without blanking.
            i += 1
            while i < n and text[i] != '"':
                i += 1
            if i < n:
                i += 1
            continue

        i += 1

    clean = "".join(out)
    changesets = [
        Changeset(author=m.group(1), id=m.group(2), line=text.count("\n", 0, m.start()) + 1)
        for m in _CHANGESET_RE.finditer(text)
    ]
    stripped = StrippedSource(raw=text, clean=clean, changesets=changesets)
    stripped._line_starts = _compute_line_starts(text)
    return stripped


# ---------------------------------------------------------------------------
# scan_objects
# ---------------------------------------------------------------------------

@dataclass
class ObjectHeader:
    kind: str  # package_spec | package_body | procedure | function | trigger | type
    schema: Optional[str]
    name: str
    start_line: int
    end_line: int
    source_path: str
    wrapped_in_dynamic_sql: bool = False


_IDENT = r"[A-Za-z0-9_$#]+"
# A handful of trigger headers quote both schema and name (e.g.
# CREATE OR REPLACE TRIGGER "MSS"."T_SERVICE_ASERTO" ... ON "MSS"."SERVICE").
# strip_noise deliberately does not blank double-quoted identifiers (their
# content is meaningful), so the quotes are still present in `clean` and the
# header regex must tolerate them without capturing the quote characters.
_QIDENT = rf'"?({_IDENT})"?'

_OBJECT_RE = re.compile(
    r"CREATE\s+(?:OR\s+REPLACE\s+)?"
    r"(PACKAGE\s+BODY|PACKAGE|PROCEDURE|FUNCTION|TRIGGER|TYPE)\s+"
    rf"(?:{_QIDENT}\.)?{_QIDENT}",
    re.IGNORECASE,
)

_KIND_MAP = {
    "package body": "package_body",
    "package": "package_spec",
    "procedure": "procedure",
    "function": "function",
    "trigger": "trigger",
    "type": "type",
}

# The type case needs a second, explicit pass over `raw`: both files under
# ddl/src/types/ build their type via a string argument to EXECUTE IMMEDIATE
# inside an anonymous block (to swallow ORA-02303), so the
# `CREATE OR REPLACE TYPE` text lives inside a string literal that
# strip_noise has already blanked in `clean`.
_WRAPPED_TYPE_RE = re.compile(
    r"EXECUTE\s+IMMEDIATE\s*'CREATE\s+OR\s+REPLACE\s+TYPE\s+"
    rf"(?:({_IDENT})\.)?({_IDENT})",
    re.IGNORECASE | re.DOTALL,
)


def normalize(name: Optional[str]) -> Optional[str]:
    """Upper-case a schema/object name for identity comparison, preserving
    None."""
    return name.upper() if name is not None else None


def scan_objects(stripped: StrippedSource, path: str) -> List[ObjectHeader]:
    found = []

    for m in _OBJECT_RE.finditer(stripped.clean):
        raw_kind = re.sub(r"\s+", " ", m.group(1).strip().lower())
        kind = _KIND_MAP[raw_kind]
        found.append(
            {
                "kind": kind,
                "schema": m.group(2),
                "name": m.group(3),
                "start_line": stripped.line_of(m.start()),
                "wrapped_in_dynamic_sql": False,
            }
        )

    for m in _WRAPPED_TYPE_RE.finditer(stripped.raw):
        found.append(
            {
                "kind": "type",
                "schema": m.group(1),
                "name": m.group(2),
                "start_line": stripped.line_of(m.start()),
                "wrapped_in_dynamic_sql": True,
            }
        )

    found.sort(key=lambda h: h["start_line"])

    total_lines = stripped.raw.count("\n") + 1
    headers: List[ObjectHeader] = []
    for idx, entry in enumerate(found):
        if idx + 1 < len(found):
            end_line = found[idx + 1]["start_line"] - 1
        else:
            end_line = total_lines
        headers.append(
            ObjectHeader(
                kind=entry["kind"],
                schema=entry["schema"],
                name=entry["name"],
                start_line=entry["start_line"],
                end_line=end_line,
                source_path=str(path),
                wrapped_in_dynamic_sql=entry["wrapped_in_dynamic_sql"],
            )
        )
    return headers


# ---------------------------------------------------------------------------
# scan_synonyms
# ---------------------------------------------------------------------------

@dataclass
class Synonym:
    synonym: str
    target_schema: Optional[str]
    target_package: str
    line: int
    malformed: bool = False

    @property
    def normalized_target(self) -> str:
        if self.target_schema:
            return f"{self.target_schema.upper()}.{self.target_package.upper()}"
        return self.target_package.upper()


_SYNONYM_RE = re.compile(
    r"CREATE\s+(?:OR\s+REPLACE\s+)?PUBLIC\s+SYNONYM\s+"
    rf"({_IDENT})\s+FOR\s+"
    rf"(?:({_IDENT})\.)?({_IDENT})",
    re.IGNORECASE,
)


def scan_synonyms(stripped: StrippedSource) -> List[Synonym]:
    out = []
    for m in _SYNONYM_RE.finditer(stripped.clean):
        target_schema = m.group(2)
        out.append(
            Synonym(
                synonym=m.group(1),
                target_schema=target_schema,
                target_package=m.group(3),
                line=stripped.line_of(m.start()),
                malformed=(target_schema is None),
            )
        )
    return out
