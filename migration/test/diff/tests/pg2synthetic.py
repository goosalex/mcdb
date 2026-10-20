#!/usr/bin/env python3
"""tests/pg2synthetic.py -- turn a psql --csv capture (<scenario>.pg.raw) into a capture
that LOOKS like SQL*Plus `SET MARKUP CSV ON` output, for the harness's own self-test.

THE RESULT IS SYNTHETIC. It carries no information about Oracle's behaviour -- it is the
PostgreSQL result re-dressed in SQL*Plus clothing (upper-case quoted header, quoted
strings, bare numbers, BINARY row order, no header for empty results). Replaying it
through run-diff.sh --ora-from proves that the capture/normalise/diff pipeline handles the
SQL*Plus shape and reports PASS when the two sides agree and DIFF when they do not
(README.md, "Falsifiability"). It must never be mistaken for Oracle evidence; the files
it produces live under tests/fixtures/synthetic-ora-capture/ and say so in oracle.env.

Usage: pg2synthetic.py IN.pg.raw > OUT.ora.raw
"""
from __future__ import annotations

import csv
import io
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from normalize import MARKER_RE, NUMBER_RE  # noqa: E402


def quote(v: str) -> str:
    if v == "":
        return ""
    if NUMBER_RE.match(v):
        return v
    return '"' + v.replace('"', '""') + '"'


def convert(raw: str) -> str:
    out: list[str] = ["-- SYNTHETIC capture (tests/pg2synthetic.py) -- not produced by Oracle --"]
    sections: list[tuple[str, list[str]]] = []
    for line in raw.splitlines():
        if MARKER_RE.match(line.strip()):
            sections.append((line.strip(), []))
        elif sections:
            sections[-1][1].append(line)
    for title, body in sections:
        out.append(title)
        text = "\n".join(body)
        records = [r for r in csv.reader(io.StringIO(text, newline="")) if r and any(f.strip() for f in r)]
        if len(records) < 2:
            continue  # SQL*Plus prints nothing for an empty result with FEEDBACK OFF
        header, rows = records[0], records[1:]
        out.append(",".join('"' + h.upper() + '"' for h in header))
        rows.sort(key=lambda r: [f.encode("utf-8") for f in r])  # BINARY order
        for r in rows:
            out.append(",".join(quote(f) for f in r))
    return "\n".join(out) + "\n"


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    sys.stdout.write(convert(Path(sys.argv[1]).read_text(encoding="utf-8")))
