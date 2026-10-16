"""
Unit tests for migration/test/lib/pkgname.py (the harness's package-identity gate, D-P9).

Run via:
  python3 -m unittest discover -s migration/test/tests -v

Pinned against the REAL migration/mapping/name-map.csv: package identities keep
working exactly as before, kind=trigger rows (which have an EMPTY oracle_package)
now contribute (pg_schema, trigger_name_lower) identities so trigger test files
such as tt__ticket_update_trg__spec.sql validate, and nothing else package-less
(standalone procedures, trigger_function rows) does.
"""
from __future__ import annotations

import csv
import sys
import tempfile
import unittest
from pathlib import Path

TEST_DIR = Path(__file__).resolve().parents[1]  # migration/test/
REPO_ROOT = TEST_DIR.parents[1]
LIB_DIR = TEST_DIR / "lib"
NAME_MAP_CSV = REPO_ROOT / "migration" / "mapping" / "name-map.csv"

sys.path.insert(0, str(LIB_DIR))

import pkgname  # noqa: E402


class TestLoadNameMapReal(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pairs = pkgname.load_name_map(NAME_MAP_CSV)

    def test_package_identity_still_present(self):
        self.assertIn(("tt", "util"), self.pairs)
        self.assertIn(("ticketevolution", "calculator"), self.pairs)

    def test_trigger_identity_present(self):
        self.assertIn(("tt", "ticket_update_trg"), self.pairs)
        self.assertIn(("tt", "todo_item_update_trg"), self.pairs)

    def test_trigger_function_row_contributes_nothing(self):
        # The trigger_function row's pg_object_name is <trigger>_fn; the identity is
        # the trigger, never its implementation half.
        self.assertNotIn(("tt", "ticket_update_trg_fn"), self.pairs)

    def test_standalone_procedure_rows_still_excluded(self):
        with NAME_MAP_CSV.open(newline="", encoding="utf-8") as f:
            standalone = [
                r for r in csv.DictReader(f)
                if r["kind"] == "procedure" and not (r.get("oracle_package") or "").strip()
            ]
        self.assertTrue(standalone, "expected at least one standalone-procedure row in name-map.csv")
        for r in standalone:
            self.assertNotIn((r["pg_schema"].lower(), r["oracle_object"].lower()), self.pairs)


class TestValidateReal(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pairs = pkgname.load_name_map(NAME_MAP_CSV)

    def test_trigger_test_filenames_validate(self):
        errors = pkgname.validate(
            [Path("tt__ticket_update_trg__spec.sql"), Path("tt__todo_item_update_trg__spec.sql")],
            self.pairs,
        )
        self.assertEqual(errors, [])

    def test_package_test_filename_still_validates(self):
        self.assertEqual(pkgname.validate([Path("tt__util__spec.sql")], self.pairs), [])

    def test_trigger_function_filename_rejected(self):
        errors = pkgname.validate([Path("tt__ticket_update_trg_fn__spec.sql")], self.pairs)
        self.assertEqual(len(errors), 1)
        self.assertIn("not a real pair", errors[0])

    def test_unknown_trigger_rejected(self):
        errors = pkgname.validate([Path("tt__no_such_trg__spec.sql")], self.pairs)
        self.assertEqual(len(errors), 1)

    def test_canary_still_exempt(self):
        self.assertEqual(pkgname.validate([Path("_canary__canary__smoke.sql")], self.pairs), [])


class TestLoadNameMapSynthetic(unittest.TestCase):
    """Row-shape rules driven by a synthetic CSV so each rule is provoked alone."""

    def _csv(self, rows):
        tmp = tempfile.NamedTemporaryFile("w", suffix=".csv", delete=False, newline="", encoding="utf-8")
        self.addCleanup(lambda: Path(tmp.name).unlink(missing_ok=True))
        w = csv.DictWriter(tmp, fieldnames=["oracle_schema", "oracle_package", "oracle_object", "kind", "pg_schema", "pg_object_name"])
        w.writeheader()
        for r in rows:
            w.writerow(r)
        tmp.close()
        return Path(tmp.name)

    def test_trigger_row_with_empty_package_yields_object_identity(self):
        p = self._csv([
            {"oracle_schema": "ZZ", "oracle_package": "", "oracle_object": "T_FOO", "kind": "trigger", "pg_schema": "zz", "pg_object_name": "t_foo"},
            {"oracle_schema": "ZZ", "oracle_package": "", "oracle_object": "T_FOO", "kind": "trigger_function", "pg_schema": "zz", "pg_object_name": "t_foo_fn"},
            {"oracle_schema": "ZZ", "oracle_package": "", "oracle_object": "DO_IT", "kind": "procedure", "pg_schema": "zz", "pg_object_name": "do_it"},
            {"oracle_schema": "ZZ", "oracle_package": "PKG", "oracle_object": "r1", "kind": "package_routine", "pg_schema": "zz", "pg_object_name": "pkg_r1"},
        ])
        self.assertEqual(pkgname.load_name_map(p), {("zz", "t_foo"), ("zz", "pkg")})

    def test_trigger_row_with_package_uses_package_identity(self):
        # Defensive: if a trigger row ever carried a package, the package wins
        # (the `continue` after the package branch), no second identity is added.
        p = self._csv([
            {"oracle_schema": "ZZ", "oracle_package": "PKG", "oracle_object": "T_FOO", "kind": "trigger", "pg_schema": "zz", "pg_object_name": "t_foo"},
        ])
        self.assertEqual(pkgname.load_name_map(p), {("zz", "pkg")})


if __name__ == "__main__":
    unittest.main()
