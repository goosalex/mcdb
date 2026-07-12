#!/usr/bin/env python3
"""migration/test/lib/pkgname.py

Package-identity resolution for the dual test harness (D-P9).

Test files are named `<pg_schema>__<oracle_package_lower>__<topic>.sql`.
This module is the single enforcement point for the rule that nobody may
invent a package name outside `migration/mapping/name-map.csv` — the Phase 1
SSOT. Python 3.12 stdlib only, matching Phase 1's D-B.

CLI:
    pkgname.py --list [PATH ...]

    With no PATH arguments, discovers `*.sql` under the harness's default
    directories (`pgtap/`, `regress/sql/`) relative to this script's
    `migration/test/` parent. Prints one `<package>\\t<file>` line per valid
    file to stdout, sorted. Any file whose `(pg_schema, oracle_package)` pair
    is not present in name-map.csv (and is not the reserved `_canary` schema)
    is a validation ERROR: printed to stderr, and the process exits non-zero
    printing nothing further to stdout for that file.
"""

from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

# The one schema value reserved for harness self-tests (Task 2/3's canary).
# No real Oracle schema in this corpus starts with an underscore, so this is
# unambiguous. Files under this schema are exempt from the name-map check —
# they exist to prove the harness itself, not to describe a translated
# object.
RESERVED_CANARY_SCHEMA = "_canary"

THIS_FILE = Path(__file__).resolve()
TEST_DIR = THIS_FILE.parents[1]  # migration/test/
REPO_ROOT = THIS_FILE.parents[3]  # repo root
NAME_MAP_CSV = REPO_ROOT / "migration" / "mapping" / "name-map.csv"

DEFAULT_DIRS = [TEST_DIR / "pgtap", TEST_DIR / "regress" / "sql"]


class PkgNameError(Exception):
    pass


def load_name_map(csv_path: Path = NAME_MAP_CSV) -> set[tuple[str, str]]:
    """Load the set of valid (pg_schema, oracle_package_lower) pairs.

    oracle_package may be empty (standalone procedures have no package) —
    those rows are not package identities and are excluded here; the harness
    only names files after packages.
    """
    if not csv_path.exists():
        raise PkgNameError(f"name-map.csv not found at {csv_path}")
    pairs: set[tuple[str, str]] = set()
    with csv_path.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            pkg = (row.get("oracle_package") or "").strip().lower()
            schema = (row.get("pg_schema") or "").strip().lower()
            if pkg and schema:
                pairs.add((schema, pkg))
    return pairs


def parse(filename: str) -> tuple[str, str, str]:
    """Parse `<pg_schema>__<oracle_package_lower>__<topic>.sql` -> (pg_schema, oracle_package_lower, topic).

    `filename` may be a bare filename or a path; only the basename is used.
    Raises PkgNameError if the filename does not match the convention.
    """
    base = Path(filename).name
    if not base.endswith(".sql"):
        raise PkgNameError(f"{filename}: does not end in .sql")
    stem = base[: -len(".sql")]
    parts = stem.split("__", 2)
    if len(parts) != 3 or not all(parts):
        raise PkgNameError(
            f"{filename}: does not match <pg_schema>__<oracle_package_lower>__<topic>.sql"
        )
    pg_schema, oracle_package_lower, topic = parts
    return pg_schema, oracle_package_lower, topic


def validate(paths: list[Path], name_map: set[tuple[str, str]] | None = None) -> list[str]:
    """Return a list of human-readable error strings, one per invalid file.

    Empty list means every path is valid: either its (pg_schema,
    oracle_package) pair is a real pair in name-map.csv, or its schema is the
    reserved `_canary` self-test schema.
    """
    if name_map is None:
        name_map = load_name_map()
    errors: list[str] = []
    for path in paths:
        try:
            pg_schema, oracle_package_lower, _topic = parse(str(path))
        except PkgNameError as exc:
            errors.append(str(exc))
            continue
        if pg_schema == RESERVED_CANARY_SCHEMA:
            continue
        if (pg_schema, oracle_package_lower) not in name_map:
            errors.append(
                f"{path}: (pg_schema={pg_schema!r}, oracle_package={oracle_package_lower!r}) "
                "is not a real pair in migration/mapping/name-map.csv"
            )
    return errors


def discover(dirs: list[Path]) -> list[Path]:
    found: list[Path] = []
    for d in dirs:
        if d.exists():
            found.extend(sorted(d.glob("*.sql")))
    return sorted(found)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--list", action="store_true", required=True, help="list (package, file) pairs")
    parser.add_argument("paths", nargs="*", help="explicit .sql files; default: discover under pgtap/ and regress/sql/")
    args = parser.parse_args(argv)

    paths = [Path(p) for p in args.paths] if args.paths else discover(DEFAULT_DIRS)

    try:
        name_map = load_name_map()
    except PkgNameError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    errors = validate(paths, name_map)
    if errors:
        for err in errors:
            print(f"ERROR: {err}", file=sys.stderr)
        return 1

    for path in paths:
        pg_schema, oracle_package_lower, _topic = parse(str(path))
        package = f"{pg_schema}.{oracle_package_lower}"
        print(f"{package}\t{path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
