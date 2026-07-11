"""
Unit tests for migration/analyze/plsql_lex.py.

Written FIRST per the plan's TDD requirement: these must fail (ModuleNotFoundError)
before plsql_lex.py exists, then pass once it is implemented.

Tests are pinned against real files under ddl/src — this is deliberate: the lexer's
whole purpose is to survive this repo's actual doc-comment and dynamic-SQL shapes,
not a synthetic fixture.
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

# migration/analyze/tests/test_plsql_lex.py -> parents[3] is the repo root.
REPO_ROOT = Path(__file__).resolve().parents[3]
ANALYZE_DIR = REPO_ROOT / "migration" / "analyze"
DDL_SRC = REPO_ROOT / "ddl" / "src"

sys.path.insert(0, str(ANALYZE_DIR))

import plsql_lex  # noqa: E402


def read(*parts) -> str:
    return (DDL_SRC.joinpath(*parts)).read_text()


class TestStripNoise(unittest.TestCase):
    def test_01_line_comment_blanked_preserving_length(self):
        src = "SELECT 1; -- this is a trailing comment\nSELECT 2;\n"
        stripped = plsql_lex.strip_noise(src)
        # Same total length, same line count.
        self.assertEqual(len(stripped.clean), len(src))
        self.assertEqual(stripped.clean.count("\n"), src.count("\n"))
        # The comment text is gone from clean.
        self.assertNotIn("trailing comment", stripped.clean)
        # Code before the comment survives.
        self.assertIn("SELECT 1;", stripped.clean)
        self.assertIn("SELECT 2;", stripped.clean)

    def test_02_block_comment_spans_lines_newlines_preserved(self):
        src = "BEGIN\n/* line one\nline two\nline three */\nNULL;\nEND;\n"
        stripped = plsql_lex.strip_noise(src)
        self.assertEqual(stripped.clean.count("\n"), src.count("\n"))
        self.assertNotIn("line one", stripped.clean)
        self.assertNotIn("line two", stripped.clean)
        self.assertNotIn("line three", stripped.clean)
        self.assertIn("BEGIN", stripped.clean)
        self.assertIn("NULL;", stripped.clean)
        self.assertIn("END;", stripped.clean)

    def test_03_string_literal_blanked_doubled_quote_survives(self):
        src = "v := 'it''s a test with -- not a comment and /* not a comment */';\n"
        stripped = plsql_lex.strip_noise(src)
        self.assertEqual(len(stripped.clean), len(src))
        self.assertNotIn("not a comment", stripped.clean)
        self.assertNotIn("it''s a test", stripped.clean)
        # code around the string literal survives
        self.assertIn("v :=", stripped.clean)
        self.assertTrue(stripped.clean.rstrip().endswith(";"))

    def test_04_marker_in_comment_absent_marker_in_code_survives(self):
        src = (
            "-- RAISE_APPLICATION_ERROR is mentioned here only in prose\n"
            "BEGIN\n"
            "  RAISE_APPLICATION_ERROR(-20001, 'boom');\n"
            "END;\n"
        )
        stripped = plsql_lex.strip_noise(src)
        comment_line = stripped.clean.splitlines()[0]
        code_line = stripped.clean.splitlines()[2]
        self.assertNotIn("RAISE_APPLICATION_ERROR", comment_line)
        self.assertIn("RAISE_APPLICATION_ERROR", code_line)

    def test_05_regression_comment_stripped_count_below_naive_count(self):
        # Ground-truth check (verified on disk before writing this test):
        # ddl/src/pkgb/auth_osag_auth_passport.sql has 29 raw occurrences of
        # RAISE_APPLICATION_ERROR, two of which (lines 670, 1564) are commented
        # out with a leading '--'. The comment-stripped count must therefore be
        # strictly less than the naive raw count.
        # NOTE (deviation from plan): the plan named ddl/src/pkgb/tt_ticket_interface.sql
        # for this regression fixture, but that file contains zero occurrences of
        # RAISE_APPLICATION_ERROR at all (verified via grep) — the naive count there
        # is 0, so "stripped < naive" can never hold. auth_osag_auth_passport.sql is
        # used instead because it actually exhibits the comment-inflation property
        # the test is designed to catch. See SUMMARY.md Deviations section.
        raw = read("pkgb", "auth_osag_auth_passport.sql")
        naive_count = len(re.findall(r"RAISE_APPLICATION_ERROR", raw, re.IGNORECASE))
        stripped = plsql_lex.strip_noise(raw)
        stripped_count = len(re.findall(r"RAISE_APPLICATION_ERROR", stripped.clean, re.IGNORECASE))
        self.assertLess(stripped_count, naive_count)
        self.assertGreater(stripped_count, 0)

    def test_06_line_of_maps_offset_to_source_line(self):
        src = "AAAA\nBBBB\nCCCC\nDDDD\n"
        stripped = plsql_lex.strip_noise(src)
        offset_of_c = src.index("CCCC")
        self.assertEqual(stripped.line_of(offset_of_c), 3)
        offset_of_a = src.index("AAAA")
        self.assertEqual(stripped.line_of(offset_of_a), 1)
        offset_of_d = src.index("DDDD")
        self.assertEqual(stripped.line_of(offset_of_d), 4)


class TestScanObjects(unittest.TestCase):
    def test_07_package_spec_single_header(self):
        raw = read("pkg", "mss_osag_ip.sql")
        stripped = plsql_lex.strip_noise(raw)
        headers = plsql_lex.scan_objects(stripped, "ddl/src/pkg/mss_osag_ip.sql")
        self.assertEqual(len(headers), 1)
        h = headers[0]
        self.assertEqual(h.kind, "package_spec")
        self.assertEqual(h.schema.upper(), "MSS")
        self.assertEqual(h.name.upper(), "OSAG_IP")

    def test_08_appid_triggers_two_headers(self):
        raw = read("triggers", "APPID.sql")
        stripped = plsql_lex.strip_noise(raw)
        headers = plsql_lex.scan_objects(stripped, "ddl/src/triggers/APPID.sql")
        self.assertEqual(len(headers), 2)
        names = {h.name for h in headers}
        self.assertEqual(names, {"t_interface_ps_link_class_sync", "t_path_override_member_link_sync"})
        for h in headers:
            self.assertEqual(h.kind, "trigger")
            self.assertEqual(h.schema.upper(), "APPID")

    def test_09_auth_triggers_eighteen_headers(self):
        raw = read("triggers", "AUTH.sql")
        stripped = plsql_lex.strip_noise(raw)
        headers = plsql_lex.scan_objects(stripped, "ddl/src/triggers/AUTH.sql")
        self.assertEqual(len(headers), 18)
        self.assertTrue(all(h.kind == "trigger" for h in headers))

    def test_10_dynamic_sql_wrapped_type_detected(self):
        raw = read("types", "mcdb_monitor_consistency_check_result_type.sql")
        stripped = plsql_lex.strip_noise(raw)
        headers = plsql_lex.scan_objects(
            stripped, "ddl/src/types/mcdb_monitor_consistency_check_result_type.sql"
        )
        self.assertEqual(len(headers), 1)
        h = headers[0]
        self.assertEqual(h.kind, "type")
        self.assertEqual(h.schema.upper(), "MCDB_MONITOR")
        self.assertEqual(h.name.upper(), "CONSISTENCY_CHECK_RESULT_TYPE")
        self.assertTrue(h.wrapped_in_dynamic_sql)

    def test_11_standalone_procedure_header(self):
        raw = read("proc", "sys_decom_authhost.sql")
        stripped = plsql_lex.strip_noise(raw)
        headers = plsql_lex.scan_objects(stripped, "ddl/src/proc/sys_decom_authhost.sql")
        self.assertEqual(len(headers), 1)
        h = headers[0]
        self.assertEqual(h.kind, "procedure")
        self.assertEqual(h.schema, "sys")
        self.assertEqual(h.name, "decomAuthHost")

    def test_12_case_preserved_but_normalize_upper_cases(self):
        raw = read("proc", "sys_decom_authhost.sql")
        stripped = plsql_lex.strip_noise(raw)
        headers = plsql_lex.scan_objects(stripped, "ddl/src/proc/sys_decom_authhost.sql")
        h = headers[0]
        # as-written case preserved
        self.assertEqual(h.name, "decomAuthHost")
        self.assertEqual(h.schema, "sys")
        # normalize() upper-cases for identity comparison
        self.assertEqual(plsql_lex.normalize(h.name), "DECOMAUTHHOST")
        self.assertEqual(plsql_lex.normalize(h.schema), "SYS")


class TestScanSynonyms(unittest.TestCase):
    def test_13_mss_osag_ip_synonym(self):
        raw = read("pkg", "mss_osag_ip.sql")
        stripped = plsql_lex.strip_noise(raw)
        synonyms = plsql_lex.scan_synonyms(stripped)
        self.assertEqual(len(synonyms), 1)
        s = synonyms[0]
        self.assertEqual(s.synonym.upper(), "OSAG_IP")
        self.assertEqual(s.target_schema.upper(), "MSS")
        self.assertEqual(s.target_package.upper(), "OSAG_IP")

    def test_14_plog_synonym_differs_from_package_name(self):
        raw = read("pkg", "osag_osag_plog.sql")
        stripped = plsql_lex.strip_noise(raw)
        synonyms = plsql_lex.scan_synonyms(stripped)
        self.assertEqual(len(synonyms), 1)
        s = synonyms[0]
        self.assertEqual(s.synonym.lower(), "plog")
        self.assertEqual(s.target_schema.upper(), "OSAG")
        self.assertEqual(s.target_package.upper(), "OSAG_PLOG")
        # Exactly why synonym-shaped calls can't be resolved by string similarity:
        self.assertNotEqual(s.synonym.upper(), s.target_package.upper())

    def test_15_nids_malformed_unqualified_synonym_target(self):
        # NOTE: the malformed synonym lives in the package SPEC
        # (ddl/src/pkg/nids_osag_nids.sql), not the body — verified via grep
        # before writing this test.
        raw = read("pkg", "nids_osag_nids.sql")
        stripped = plsql_lex.strip_noise(raw)
        synonyms = plsql_lex.scan_synonyms(stripped)
        malformed = [s for s in synonyms if s.malformed]
        self.assertEqual(len(malformed), 1)
        s = malformed[0]
        self.assertIsNone(s.target_schema)
        self.assertEqual(s.target_package.upper(), "OSAG_NIDS")


class TestCorpusWideStructuralInvariants(unittest.TestCase):
    """Supplementary to the 15 named behaviors — pins the acceptance-criteria
    structural counts as automated (not just manually verified) gates."""

    def _all_source_files(self):
        for sub in ("pkg", "pkgb", "proc", "triggers", "types"):
            yield from sorted((DDL_SRC / sub).glob("*.sql"))

    def test_16_line_count_preserved_across_corpus(self):
        for path in self._all_source_files():
            raw = path.read_text()
            stripped = plsql_lex.strip_noise(raw)
            self.assertEqual(
                stripped.clean.count("\n"),
                raw.count("\n"),
                f"line count diverged for {path}",
            )

    def test_17_trigger_objects_total_53(self):
        total = 0
        for path in sorted((DDL_SRC / "triggers").glob("*.sql")):
            raw = path.read_text()
            stripped = plsql_lex.strip_noise(raw)
            headers = plsql_lex.scan_objects(stripped, str(path))
            total += len(headers)
        self.assertEqual(total, 53)

    def test_18_types_both_wrapped_in_dynamic_sql(self):
        total = 0
        for path in sorted((DDL_SRC / "types").glob("*.sql")):
            raw = path.read_text()
            stripped = plsql_lex.strip_noise(raw)
            headers = plsql_lex.scan_objects(stripped, str(path))
            self.assertEqual(len(headers), 1)
            self.assertTrue(headers[0].wrapped_in_dynamic_sql)
            total += len(headers)
        self.assertEqual(total, 2)

    def test_19_plsql_lex_imports_stdlib_only(self):
        lex_path = ANALYZE_DIR / "plsql_lex.py"
        text = lex_path.read_text()
        import_lines = [
            ln.strip()
            for ln in text.splitlines()
            if ln.strip().startswith("import ") or ln.strip().startswith("from ")
        ]
        stdlib_modules = {"re", "dataclasses", "pathlib", "enum", "bisect", "typing", "__future__"}
        for line in import_lines:
            m = re.match(r"(?:from|import)\s+([A-Za-z0-9_.]+)", line)
            self.assertIsNotNone(m, f"unparsable import line: {line}")
            top_module = m.group(1).split(".")[0]
            self.assertIn(top_module, stdlib_modules, f"non-stdlib import found: {line}")


if __name__ == "__main__":
    unittest.main()
