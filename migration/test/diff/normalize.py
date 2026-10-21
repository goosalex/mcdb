#!/usr/bin/env python3
"""migration/test/diff/normalize.py -- make an Oracle (SQL*Plus CSV) and a PostgreSQL
(psql --csv) probe capture comparable, so that `diff` only shows behavioural differences.

Python 3.12, stdlib only.

Input: the raw stdout(+stderr) of one scenario run on one side, as produced by the
scripts compose.py builds. The stream is a sequence of sections, each introduced by a
marker line the composer emitted before every probe statement:

    ## probe <N> [<label>]
    <CSV header>
    <CSV rows...>

Anything that is not a well-formed CSV record of the section (ORA-xxxxx lines, "ERROR at
line", psql's "psql:file:line: ERROR:" lines, SP2- messages, ...) is kept as a `! <line>`
noise line, so an unexpected failure on either side shows up in the diff instead of being
silently dropped. Lines before the first marker form the `## preamble` section (connection
errors, setup/call failures).

Normalisation rules (each one has a unit test in tests/test_normalize.py):

  R1  headers: lower-cased, surrounding whitespace stripped (Oracle prints column names
      upper-case, psql lower-case).
  R2  every field: trailing spaces removed (Oracle CHAR padding) and CR stripped.
  R3  NULL and the empty string both become the empty field. Oracle has no empty string
      (it IS NULL); psql --csv writes NULL as nothing and '' as "". After normalisation
      the two are indistinguishable -- deliberately, document it in a scenario's probe if
      the distinction matters and encode it as CASE WHEN x IS NULL THEN 'null' ... instead.
  R4  numbers: canonical decimal rendering. "12.0" -> "12", "-0" -> "0", ".5" -> "0.5",
      "1.7294E+19" -> "17294000000000000000", "256.0000000000000000" -> "256".
  R5  booleans: a column whose non-empty values are all in {t, f, true, false} is rewritten
      to 1/0 (psql renders boolean as t/f; Oracle has no SQL boolean and scenarios render
      flags as NUMBER(1)). Columns containing any other value are left alone, so a
      genuine single-letter string column is safe.
  R6  error codes: a column named `code` (or `*_code`) is mapped to a canonical token
      through the table below, derived from migration/mapping/sqlstate-map.md. Oracle
      SQLCODE forms accepted: -1403, 1403, ORA-01403, ORA-1403. Codes not in the table stay
      as they are, so an unmapped code is visible in the diff rather than hidden.
  R7  error messages: a column named `msg` (or `*_msg`) is blanked unless the scenario's
      meta.env says COMPARE_MSG=yes. Message texts legitimately differ between the two
      engines ("ORA-01403: no data found" vs "no data found"); the code is the contract.
  R8  zero-row probes: the header line is emitted only when at least one data row
      follows. SQL*Plus with FEEDBACK OFF prints nothing at all for an empty result,
      psql --csv prints the header alone; both normalise to just the marker line.
  R9  embedded newlines inside a field are rendered as the two characters \\n so every
      normalised row is one line and the diff stays readable.
  R10 rows within a probe section are sorted by their normalised fields. The template
      database collates en_US.utf8 while Oracle sorts BINARY, so an ORDER BY over text
      can legitimately order the same rows differently; row ORDER is therefore not part
      of what the harness compares. A scenario that needs to assert order must expose it
      as data (a numbered step label, a row_number column).
  R11 lines starting with `--` are dropped. SQL*Plus (ECHO OFF) and psql (-q) never echo
      SQL comments, so such lines only occur as annotations in hand-written or synthetic
      capture files (tests/fixtures/), where they label the file's provenance.

Usage:
  normalize.py --dialect ora|pg [--meta meta.env] [--compare-msg] RAW_FILE   > normalised
  normalize.py --self-check                                                   (prints the code table)
"""
from __future__ import annotations

import argparse
import csv
import io
import re
import sys
from decimal import Decimal, InvalidOperation
from pathlib import Path

MARKER_RE = re.compile(r"^## probe (\d+)(?: (.*))?$")

# Lines that can never be CSV data; used only to decide that a would-be header is noise.
NOISE_RE = re.compile(
    r"^(ORA-\d+|ERROR( at line \d+)?:?|SP2-\d+|PLS-\d+|psql:|PL/SQL procedure|"
    r"Session altered|Table (created|dropped|truncated)|Rollback complete|Commit complete|"
    r"Constraint set|Disconnected from|Connected to|Warning:|NOTICE:|WARNING:|DO$|BEGIN$|"
    r"ROLLBACK$|COMMIT$|SET$|CREATE TABLE$|SET CONSTRAINTS$)"
)

# ---------------------------------------------------------------------------
# R6 -- the error-code equivalence table.
#
# Source: migration/mapping/sqlstate-map.md (XCUT-01). The canonical token is the
# PostgreSQL SQLSTATE where sqlstate-map.md names one. Oracle's VALUE_ERROR
# (ORA-06502) corresponds to several PostgreSQL class-22 codes depending on whether
# the engine or the translation raises it (sqlstate-map.md rule 1); Oracle itself
# does not distinguish those cases, so both sides collapse onto the token
# VALUE_ERROR. ORA-01722 (invalid number) is the SQL-level twin of ORA-06502's
# "character to number conversion error" and joins the same class.
#
# Custom application errors (RAISE_APPLICATION_ERROR(-20NNN)) follow rule 3 of
# sqlstate-map.md: 'OS' + last three digits.
# ---------------------------------------------------------------------------
ORA_TO_CANON: dict[int, str] = {
    1403: "P0002",        # NO_DATA_FOUND (ORA-01403)
    100: "P0002",         # NO_DATA_FOUND as SQLCODE returns it in a handler (+100, ANSI)
    1422: "P0003",        # TOO_MANY_ROWS
    1: "23505",           # DUP_VAL_ON_INDEX
    1400: "23502",        # cannot insert NULL
    1407: "23502",        # cannot update to NULL
    2291: "23503",        # integrity constraint violated - parent key not found
    2292: "23503",        # integrity constraint violated - child record found
    6502: "VALUE_ERROR",  # PL/SQL numeric or value error
    1722: "VALUE_ERROR",  # invalid number
    1476: "22012",        # divisor is equal to zero
    6510: "P0001",        # unhandled user-defined exception  <-> RAISE EXCEPTION default
    942: "42P01",         # table or view does not exist
    904: "42703",         # invalid identifier
    1017: "28P01",        # invalid username/password
}
PG_TO_CANON: dict[str, str] = {
    "22023": "VALUE_ERROR",  # invalid_parameter_value (deliberate VALUE_ERROR raise)
    "22P02": "VALUE_ERROR",  # invalid_text_representation (engine)
    "22003": "VALUE_ERROR",  # numeric_value_out_of_range (engine)
    "22001": "VALUE_ERROR",  # string_data_right_truncation (engine)
}

ORA_CODE_RE = re.compile(r"^\s*(?:ORA-)?(-?)0*(\d+)\s*$", re.IGNORECASE)
NUMBER_RE = re.compile(r"^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$")


def read_meta(path: Path | None) -> dict[str, str]:
    """meta.env: KEY=VALUE per line, `#` comments, optional single/double quotes."""
    meta: dict[str, str] = {}
    if path is None or not path.exists():
        return meta
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
            value = value[1:-1]
        meta[key.strip().upper()] = value
    return meta


def canon_code(value: str, dialect: str) -> str:
    """R6. Map one error-code field to its canonical token; unknown codes pass through."""
    v = value.strip()
    if not v:
        return v
    if dialect == "ora":
        m = ORA_CODE_RE.match(v)
        if not m:
            return v
        num = int(m.group(2))
        if 20000 <= num <= 20999:
            return "OS" + f"{num % 1000:03d}"
        return ORA_TO_CANON.get(num, v)
    # pg: SQLSTATE is five characters, upper-case
    if re.fullmatch(r"[0-9A-Za-z]{5}", v):
        v = v.upper()
        return PG_TO_CANON.get(v, v)
    return v


def canon_number(value: str) -> str:
    """R4. Canonical decimal rendering; non-numbers pass through unchanged."""
    if not NUMBER_RE.match(value):
        return value
    try:
        d = Decimal(value)
    except InvalidOperation:
        return value
    if d == 0:
        return "0"
    text = format(d.normalize(), "f")
    if text.startswith("."):
        text = "0" + text
    elif text.startswith("-."):
        text = "-0" + text[1:]
    return text


def clean_field(value: str) -> str:
    """R2 + R9."""
    value = value.replace("\r", "")
    value = value.replace("\n", "\\n")
    return value.rstrip(" ")


def is_code_column(name: str) -> bool:
    return name == "code" or name.endswith("_code")


def is_msg_column(name: str) -> bool:
    return name == "msg" or name.endswith("_msg")


class Section:
    def __init__(self, title: str):
        self.title = title
        self.header: list[str] | None = None
        self.rows: list[list[str]] = []
        self.noise: list[str] = []

    def add_text(self, text: str) -> None:
        """Parse the raw text of the section as CSV; records whose arity does not match
        the header are noise (ORA-/psql error lines and the like)."""
        if not text.strip():
            return
        reader = csv.reader(io.StringIO(text, newline=""))
        for record in reader:
            if not record or (len(record) == 1 and not record[0].strip()):
                continue
            joined = ",".join(record).strip()
            if self.header is None:
                if NOISE_RE.match(joined) or len(record) == 1 and " " in record[0].strip():
                    self.noise.append(joined)
                    continue
                self.header = [h.strip().lower() for h in record]
                continue
            if len(record) != len(self.header) or NOISE_RE.match(joined):
                self.noise.append(joined)
                continue
            self.rows.append(record)


def split_sections(raw: str) -> list[Section]:
    sections: list[Section] = [Section("## preamble")]
    buffer: list[str] = []

    def flush() -> None:
        sections[-1].add_text("\n".join(buffer) + ("\n" if buffer else ""))
        buffer.clear()

    for line in raw.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
        if line.startswith("--"):  # R11
            continue
        m = MARKER_RE.match(line.strip())
        if m:
            flush()
            label = (m.group(2) or "").strip()
            title = f"## probe {int(m.group(1))}" + (f" {label}" if label else "")
            sections.append(Section(title))
            continue
        buffer.append(line)
    flush()
    return sections


def normalise_section(section: Section, dialect: str, compare_msg: bool) -> list[str]:
    out: list[str] = [section.title]
    if section.header is not None and section.rows:  # R8
        header = section.header
        rows = [[clean_field(f) for f in row] for row in section.rows]
        ncol = len(header)
        # R5 -- boolean columns, decided per column over the whole section
        for c in range(ncol):
            values = {row[c].strip().lower() for row in rows if row[c].strip() != ""}
            if values and values <= {"t", "f", "true", "false"}:
                for row in rows:
                    v = row[c].strip().lower()
                    if v:
                        row[c] = "1" if v in ("t", "true") else "0"
        for row in rows:
            for c, name in enumerate(header):
                if is_code_column(name):
                    row[c] = canon_code(row[c], dialect)
                elif is_msg_column(name):
                    if not compare_msg:
                        row[c] = ""
                else:
                    row[c] = canon_number(row[c])
        rows.sort()  # R10
        writer_buf = io.StringIO()
        writer = csv.writer(writer_buf, lineterminator="\n", quoting=csv.QUOTE_MINIMAL)
        writer.writerow(header)
        for row in rows:
            writer.writerow(row)
        out.extend(writer_buf.getvalue().rstrip("\n").split("\n"))
    for line in section.noise:
        out.append("! " + clean_field(line))
    return out


def normalise(raw: str, dialect: str, compare_msg: bool = False) -> str:
    if dialect not in ("ora", "pg"):
        raise ValueError(f"dialect must be ora or pg, got {dialect!r}")
    lines: list[str] = []
    for i, section in enumerate(split_sections(raw)):
        if i == 0 and section.header is None and not section.rows and not section.noise:
            continue  # empty preamble: nothing happened before the first probe
        lines.extend(normalise_section(section, dialect, compare_msg))
    return "\n".join(lines) + ("\n" if lines else "")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dialect", choices=("ora", "pg"))
    parser.add_argument("--meta", type=Path, help="scenario meta.env (COMPARE_MSG=yes enables R7 message comparison)")
    parser.add_argument("--compare-msg", action="store_true", help="compare error messages regardless of meta.env")
    parser.add_argument("--self-check", action="store_true", help="print the code table and exit")
    parser.add_argument("raw", nargs="?", type=Path)
    args = parser.parse_args(argv)

    if args.self_check:
        for k, v in sorted(ORA_TO_CANON.items()):
            print(f"ORA-{k:05d}\t{v}")
        for k, v in sorted(PG_TO_CANON.items()):
            print(f"{k}\t{v}")
        print("ORA-20NNN\tOSNNN (rule 3)")
        return 0

    if not args.dialect or args.raw is None:
        parser.error("--dialect and RAW_FILE are required")
    meta = read_meta(args.meta)
    compare_msg = args.compare_msg or meta.get("COMPARE_MSG", "no").lower() == "yes"
    raw = args.raw.read_text(encoding="utf-8", errors="replace")
    sys.stdout.write(normalise(raw, args.dialect, compare_msg))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
