#!/usr/bin/env python3
"""
test_spec_lint.py -- pins spec_lint.py's behavior (SPEC-02, SPEC-03, T-02-05,
T-02-06 neighbor, T-02-07). Run via:

  python3 -m unittest discover -s migration/spec/tests -v

Two layers of proof:
  1. The three checked-in fixtures under migration/spec/fixtures/ -- good
     passes, both bad ones fail with the expected violation.
  2. Synthetic specs built against the REAL migration/mapping/name-map.csv and
     migration/analyze/inventory.json (MSS.OSAG_DBPROP, a real pilot package)
     to prove the SSOT-binding checks (wrong pg_schema/pg_prefix, dropped
     routine coverage) actually reject bad input against real data, not just
     the throwaway fixtures.
"""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

SPEC_DIR = Path(__file__).resolve().parent.parent
REPO_ROOT = SPEC_DIR.parents[1]
sys.path.insert(0, str(SPEC_DIR))

import spec_lint  # noqa: E402

FIXTURES_DIR = SPEC_DIR / "fixtures"

REAL_INVENTORY_PATH = REPO_ROOT / "migration" / "analyze" / "inventory.json"
REAL_NAME_MAP_PATH = REPO_ROOT / "migration" / "mapping" / "name-map.csv"
CHECKLIST_PATH = SPEC_DIR / "CHECKLIST.md"


def _lint(path: Path):
    dims = spec_lint.load_checklist_dimensions(CHECKLIST_PATH)
    inventory = spec_lint.load_inventory(REAL_INVENTORY_PATH)
    name_map_rows = spec_lint.load_name_map(REAL_NAME_MAP_PATH)
    return spec_lint.lint_file(path, dims, inventory, name_map_rows)


class TestFixtures(unittest.TestCase):
    def test_good_fixture_passes(self):
        violations = _lint(FIXTURES_DIR / "good.example.md")
        self.assertEqual(violations, [], f"expected no violations, got: {violations}")

    def test_bad_missing_assumptions_fails(self):
        violations = _lint(FIXTURES_DIR / "bad_missing_assumptions.example.md")
        self.assertTrue(violations, "expected at least one violation")
        self.assertTrue(
            any("Assumptions / Unresolved" in v for v in violations),
            f"expected an Assumptions/Unresolved violation, got: {violations}",
        )

    def test_bad_missing_citation_fails(self):
        violations = _lint(FIXTURES_DIR / "bad_missing_citation.example.md")
        self.assertTrue(violations, "expected at least one violation")
        self.assertTrue(
            any("9999" in v and "lines" in v for v in violations),
            f"expected a citation-past-EOF violation, got: {violations}",
        )


REAL_SPEC_GOOD = """---
oracle_schema: MSS
oracle_package: OSAG_DBPROP
pg_schema: mss
pg_prefix: osag_dbprop
clause_prefix: DBPROP
oracle_spec: ddl/src/pkg/mss_osag_dbprop.sql
oracle_body: ddl/src/pkgb/mss_osag_dbprop.sql
public_routines: 3
---

# MSS.OSAG_DBPROP -- PostgreSQL spec (unit-test probe, real SSOT data)

## Routines

### get_number_by_host

- **Oracle signature:** `GET_NUMBER_BY_HOST(NUMBER, VARCHAR2) RETURN NUMBER`
- **PostgreSQL name:** `mss.osag_dbprop_get_number_by_host`
- **Declared:** `ddl/src/pkg/mss_osag_dbprop.sql:23`
- **Defined:** `ddl/src/pkgb/mss_osag_dbprop.sql:11`

### get_string_by_host

- **Oracle signature:** `GET_STRING_BY_HOST(NUMBER, VARCHAR2) RETURN VARCHAR2`
- **PostgreSQL name:** `mss.osag_dbprop_get_string_by_host`
- **Declared:** `ddl/src/pkg/mss_osag_dbprop.sql:24`
- **Defined:** `ddl/src/pkgb/mss_osag_dbprop.sql:67`

### get_string_by_host_key_id

- **Oracle signature:** `GET_STRING_BY_HOST_KEY_ID(NUMBER, NUMBER) RETURN VARCHAR2`
- **PostgreSQL name:** `mss.osag_dbprop_get_string_by_host_key_id`
- **Declared:** `ddl/src/pkg/mss_osag_dbprop.sql:25`
- **Defined:** `ddl/src/pkgb/mss_osag_dbprop.sql:31`

## Clauses

### S-DBPROP-001

- **routines:** get_number_by_host
- **claim:** Test probe clause.
- **source:** `ddl/src/pkgb/mss_osag_dbprop.sql:11`

### S-DBPROP-002

- **routines:** get_string_by_host
- **claim:** Test probe clause.
- **source:** `ddl/src/pkgb/mss_osag_dbprop.sql:67`

### S-DBPROP-003

- **routines:** get_string_by_host_key_id
- **claim:** Test probe clause.
- **source:** `ddl/src/pkgb/mss_osag_dbprop.sql:31`

## Checklist

### 1. Empty-string / NULL handling
Test probe -- not a real answer.

### 2. SELECT INTO strictness
Test probe -- not a real answer.

### 3. Exception codes
Test probe -- not a real answer.

### 4. Package state
Test probe -- not a real answer.

### 5. FUNCTION vs PROCEDURE
Test probe -- not a real answer.

## Assumptions / Unresolved
Test probe -- not a real answer.
"""


class TestRealSSOTBinding(unittest.TestCase):
    """Proves the SSOT-binding checks reject bad input against the REAL
    name-map.csv / inventory.json, not just the throwaway fixtures -- this is
    what makes T-02-06's neighbor claim ('a spec cannot invent a PostgreSQL
    name') and T-02-07 (routine coverage) actually mechanical."""

    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmpdir.cleanup)

    def _write(self, name: str, content: str) -> Path:
        p = Path(self.tmpdir.name) / name
        p.write_text(content)
        return p

    def test_well_formed_real_spec_passes(self):
        p = self._write("mss.osag_dbprop.md", REAL_SPEC_GOOD)
        violations = _lint(p)
        self.assertEqual(violations, [], f"expected no violations, got: {violations}")

    def test_wrong_pg_schema_rejected(self):
        bad = REAL_SPEC_GOOD.replace("pg_schema: mss", "pg_schema: totallywrong")
        p = self._write("mss.osag_dbprop.md", bad)
        violations = _lint(p)
        self.assertTrue(
            any("pg_schema" in v and "invent" in v for v in violations),
            f"expected a pg_schema mismatch violation, got: {violations}",
        )

    def test_wrong_pg_prefix_rejected(self):
        bad = REAL_SPEC_GOOD.replace("pg_prefix: osag_dbprop", "pg_prefix: made_up_prefix")
        p = self._write("mss.osag_dbprop.md", bad)
        violations = _lint(p)
        self.assertTrue(
            any("pg_prefix" in v and "invent" in v for v in violations),
            f"expected a pg_prefix mismatch violation, got: {violations}",
        )

    def test_dropped_routine_rejected(self):
        # Drop the get_string_by_host_key_id clause entirely -- 2 of 3 public
        # routines covered, the 3rd silently missing.
        bad_lines = []
        skip = False
        for line in REAL_SPEC_GOOD.split("\n"):
            if line.strip() == "### S-DBPROP-003":
                skip = True
                continue
            if skip and line.strip() == "## Checklist":
                skip = False
            if not skip:
                bad_lines.append(line)
        bad = "\n".join(bad_lines)
        p = self._write("mss.osag_dbprop.md", bad)
        violations = _lint(p)
        self.assertTrue(
            any("GET_STRING_BY_HOST_KEY_ID" in v and "not covered" in v for v in violations),
            f"expected a dropped-routine violation, got: {violations}",
        )

    def test_unknown_package_rejected(self):
        bad = REAL_SPEC_GOOD.replace("oracle_package: OSAG_DBPROP", "oracle_package: DOES_NOT_EXIST")
        p = self._write("mss.does_not_exist.md", bad)
        violations = _lint(p)
        self.assertTrue(
            any("no rows found in name-map.csv" in v for v in violations),
            f"expected a not-found-in-name-map violation, got: {violations}",
        )


class TestMandatorySectionsAndChecklist(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmpdir.cleanup)

    def _write(self, name: str, content: str) -> Path:
        p = Path(self.tmpdir.name) / name
        p.write_text(content)
        return p

    def test_missing_checklist_dimension_rejected(self):
        bad = REAL_SPEC_GOOD.replace(
            "### 5. FUNCTION vs PROCEDURE\nTest probe -- not a real answer.\n\n",
            "",
        )
        p = self._write("mss.osag_dbprop.md", bad)
        violations = _lint(p)
        self.assertTrue(
            any("dimension 5" in v for v in violations),
            f"expected a missing-dimension-5 violation, got: {violations}",
        )

    def test_bare_na_checklist_answer_rejected(self):
        bad = REAL_SPEC_GOOD.replace(
            "### 3. Exception codes\nTest probe -- not a real answer.",
            "### 3. Exception codes\nN/A",
        )
        p = self._write("mss.osag_dbprop.md", bad)
        violations = _lint(p)
        self.assertTrue(
            any("dimension 3" in v and "bare" in v for v in violations),
            f"expected a bare-N/A dimension-3 violation, got: {violations}",
        )

    def test_duplicate_clause_id_rejected(self):
        bad = REAL_SPEC_GOOD.replace("### S-DBPROP-002", "### S-DBPROP-001")
        p = self._write("mss.osag_dbprop.md", bad)
        violations = _lint(p)
        self.assertTrue(
            any("duplicate clause ID S-DBPROP-001" in v for v in violations),
            f"expected a duplicate-clause-ID violation, got: {violations}",
        )


if __name__ == "__main__":
    unittest.main()
