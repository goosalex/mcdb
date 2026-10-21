"""
Unit tests for migration/test/diff/normalize.py (rules R1-R11) and compose.py's probe
splitter. Run via:

  python3 -m unittest discover -s migration/test/diff/tests -v

Every rule in normalize.py's docstring has at least one test here; the inputs imitate the
real shapes of SQL*Plus `SET MARKUP CSV ON` output and psql `--csv` output. The code-table
test pins the Oracle -> SQLSTATE rows of migration/mapping/sqlstate-map.md.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

DIFF_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(DIFF_DIR))

import compose  # noqa: E402
import normalize  # noqa: E402

ORA_RAW = """\
## probe 1 results
"STEP","CODE","MSG","N","S","FLAG","PADDED"
"b 2",,,12.0,"x  ",1,"ab   "
"a 1","-1403","ORA-01403: no data found",,,0,"cd"
"c 3",,,.5,"multi
line",1,"ef"
"""

PG_RAW = """\
## probe 1 results
step,code,msg,n,s,flag,padded
a 1,P0002,query returned no rows,,,f,cd
b 2,,,12,x,t,ab
c 3,,,0.5,"multi
line",t,ef
"""


class TestRules(unittest.TestCase):
    def test_r1_r2_r3_r4_r5_r7_r9_r10_make_sides_identical(self):
        ora = normalize.normalise(ORA_RAW, "ora")
        pg = normalize.normalise(PG_RAW, "pg")
        self.assertEqual(ora, pg)
        self.assertIn("step,code,msg,n,s,flag,padded", ora)          # R1 lower-case header
        self.assertIn("a 1,P0002,,,,0,cd", ora)                        # R6 code mapped, R7 msg blanked, R5 0/1
        self.assertIn("b 2,,,12,x,1,ab", ora)                          # R2 padding stripped, R4 12.0 -> 12
        self.assertIn("c 3,,,0.5,multi\\nline,1,ef", ora)              # R4 .5 -> 0.5, R9 newline rendered
        lines = ora.splitlines()
        self.assertEqual(lines[2][:3], "a 1")                           # R10 sorted (Oracle gave b first)

    def test_r4_numbers(self):
        cases = {
            "12.0": "12", "-0": "0", "0.0": "0", ".5": "0.5", "-.5": "-0.5",
            "1.7294E+19": "17294000000000000000", "256.0000000000000000": "256",
            "16909060.5": "16909060.5", "1e3": "1000", "abc": "abc", "1.2.3": "1.2.3", "": "",
        }
        for raw, want in cases.items():
            self.assertEqual(normalize.canon_number(raw), want, raw)

    def test_r5_boolean_column_only_when_every_value_is_boolean(self):
        raw = "## probe 1 x\nflag,letter\nt,t\nf,q\n"
        out = normalize.normalise(raw, "pg")
        self.assertIn("1,t", out)   # column 1 all booleans -> 1/0; column 2 has 'q' -> untouched
        self.assertIn("0,q", out)

    def test_r6_oracle_code_forms(self):
        for form in ("-1403", "1403", "ORA-01403", "ORA-1403", " -1403 "):
            self.assertEqual(normalize.canon_code(form, "ora"), "P0002", form)
        self.assertEqual(normalize.canon_code("-20980", "ora"), "OS980")   # rule 3 of sqlstate-map.md
        self.assertEqual(normalize.canon_code("ORA-20801", "ora"), "OS801")
        self.assertEqual(normalize.canon_code("-6502", "ora"), "VALUE_ERROR")
        self.assertEqual(normalize.canon_code("-99999", "ora"), "-99999")  # unknown: passes through
        self.assertEqual(normalize.canon_code("22P02", "pg"), "VALUE_ERROR")
        self.assertEqual(normalize.canon_code("p0002", "pg"), "P0002")
        self.assertEqual(normalize.canon_code("OS980", "pg"), "OS980")

    def test_r6_table_matches_sqlstate_map(self):
        # The rows of migration/mapping/sqlstate-map.md's predefined-exception table.
        want = {1403: "P0002", 1422: "P0003", 1: "23505", 1400: "23502", 1407: "23502"}
        for ora, pg in want.items():
            self.assertEqual(normalize.ORA_TO_CANON[ora], pg)

    def test_r7_compare_msg(self):
        raw = "## probe 1 x\nstep,code,msg\ns,-1403,ORA-01403: no data found\n"
        self.assertIn("s,P0002,", normalize.normalise(raw, "ora"))
        self.assertIn("s,P0002,ORA-01403: no data found", normalize.normalise(raw, "ora", compare_msg=True))

    def test_r8_zero_rows_both_shapes_normalise_to_marker_only(self):
        ora = normalize.normalise("## probe 1 empty\n", "ora")          # SQL*Plus: nothing at all
        pg = normalize.normalise("## probe 1 empty\na,b\n", "pg")       # psql: header alone
        self.assertEqual(ora, pg)
        self.assertEqual(ora, "## probe 1 empty\n")

    def test_r11_comment_lines_dropped(self):
        raw = "-- synthetic\n## probe 1 x\n-- note\na\n1\n"
        self.assertEqual(normalize.normalise(raw, "ora"), "## probe 1 x\na\n1\n")

    def test_noise_lines_are_kept_visible(self):
        ora = "## probe 1 x\nSELECT * FROM nowhere\n              *\nERROR at line 1:\nORA-00942: table or view does not exist\n"
        out = normalize.normalise(ora, "ora")
        self.assertIn("! ORA-00942: table or view does not exist", out)
        pg = "## probe 1 x\npsql:x.sql:3: ERROR:  relation \"nowhere\" does not exist\n"
        self.assertIn("! psql:x.sql:3: ERROR:  relation \"nowhere\" does not exist", normalize.normalise(pg, "pg"))

    def test_preamble_noise_is_reported(self):
        out = normalize.normalise("SP2-0640: Not connected\n## probe 1 x\n", "ora")
        self.assertTrue(out.startswith("## preamble\n! SP2-0640: Not connected\n"))

    def test_sections_are_split_by_marker_with_label(self):
        raw = "## probe 1 first\na\n1\n## probe 2\nb\n2\n"
        out = normalize.normalise(raw, "pg")
        self.assertEqual(out, "## probe 1 first\na\n1\n## probe 2\nb\n2\n")

    def test_dialect_must_be_known(self):
        with self.assertRaises(ValueError):
            normalize.normalise("", "mysql")


class TestMeta(unittest.TestCase):
    def test_read_meta(self):
        import tempfile
        with tempfile.NamedTemporaryFile("w", suffix=".env", delete=False) as f:
            f.write("# comment\nORA_USER=tt\nCOMMITS = no\nDESCRIPTION=\"a = b\"\n\n")
            path = Path(f.name)
        meta = normalize.read_meta(path)
        self.assertEqual(meta, {"ORA_USER": "tt", "COMMITS": "no", "DESCRIPTION": "a = b"})
        self.assertEqual(normalize.read_meta(Path("/nonexistent/meta.env")), {})


class TestCompose(unittest.TestCase):
    def test_split_probes_labels_and_multiline(self):
        text = (
            "-- probe: first\n"
            "SELECT a\nFROM t\nORDER BY a;\n"
            "\n"
            "-- a plain comment\n"
            "SELECT 1 AS one;\n"
        )
        probes = compose.split_probes(text)
        self.assertEqual(probes, [("first", "SELECT a\nFROM t\nORDER BY a;"), ("", "SELECT 1 AS one;")])

    def test_split_probes_rejects_unterminated_statement(self):
        with self.assertRaises(SystemExit):
            compose.split_probes("SELECT 1\n")

    def test_marker_format_is_shared_by_both_dialects(self):
        self.assertEqual(compose.marker(3, "x y"), "## probe 3 x y")
        self.assertEqual(compose.marker(4, ""), "## probe 4")
        self.assertIsNotNone(normalize.MARKER_RE.match(compose.marker(3, "x y")))

    def test_real_scenarios_compose_for_both_dialects(self):
        scenarios = sorted((DIFF_DIR / "scenarios").iterdir())
        self.assertTrue(scenarios)
        for sdir in scenarios:
            meta = normalize.read_meta(sdir / "meta.env")
            ora = compose.compose_ora(sdir, meta)
            pg = compose.compose_pg(sdir, meta, "UTC")
            n_ora = ora.count("\nPROMPT ## probe ")
            n_pg = pg.count("\n\\echo ## probe ")
            self.assertGreater(n_ora, 0, sdir.name)
            self.assertEqual(n_ora, n_pg, sdir.name)
            if meta.get("COMMITS", "no").lower() == "yes":
                # a committing scenario runs without a transaction block on PostgreSQL and
                # ends with its cleanup + COMMIT on Oracle (README, Limitations 1)
                self.assertNotIn("ROLLBACK;", pg, sdir.name)
                self.assertIn("cleanup (COMMITS=yes)", ora, sdir.name)
            else:
                self.assertIn("ROLLBACK;", ora, sdir.name)
                self.assertIn("ROLLBACK;", pg, sdir.name)
            self.assertIn("EXIT ROLLBACK", ora, sdir.name)


if __name__ == "__main__":
    unittest.main()
