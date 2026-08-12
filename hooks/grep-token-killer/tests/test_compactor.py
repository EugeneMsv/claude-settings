import os
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import compactor  # noqa: E402
import config  # noqa: E402
import parser  # noqa: E402

_FIXTURES = Path(__file__).resolve().parent / "fixtures"


def _cfg(line_max_output_chars=500):
    return config.Config(line_max_output_chars=line_max_output_chars)


# A group-by-file header is an unindented `path:` line — path chars then a single
# trailing colon, nothing after. Distinct from indented body lines (`  12:code`)
# and inline hits (`file:12:code`), so it never miscounts an actual match.
_GROUP_HEADER = re.compile(r"^[^:\s][^:]*:$")


def _body_lines(text):
    """Match lines only: excludes the `# base:` header and group `path:` headers."""
    return [
        ln for ln in text.split("\n")
        if ln and not ln.startswith("# base:") and not _GROUP_HEADER.match(ln)
    ]


class TestPrefixStrip(unittest.TestCase):
    def test_header_added_and_paths_stripped(self):
        records = (
            parser.Record(raw="/a/b/X.java:1:foo", path="/a/b/X.java", lineno="1", content="foo"),
            parser.Record(raw="/a/b/Y.java:2:bar", path="/a/b/Y.java", lineno="2", content="bar"),
        )
        result = compactor.compact(records, _cfg())
        self.assertIn("prefix_strip", result.transforms)
        self.assertTrue(result.text.startswith("# base: /a/b/\n"))
        self.assertIn("X.java:1:foo", result.text)
        self.assertNotIn("/a/b/X.java", result.text)

    def test_line_count_preserved(self):
        records = tuple(
            parser.Record(raw=f"/a/b/F{i}.java:{i}:x", path=f"/a/b/F{i}.java",
                          lineno=str(i), content="x")
            for i in range(5)
        )
        result = compactor.compact(records, _cfg())
        self.assertEqual(len(_body_lines(result.text)), len(records))


class TestTruncation(unittest.TestCase):
    def test_long_content_truncated_with_marker(self):
        long_content = "x" * 100
        records = (parser.Record(raw=f"/a/B.java:1:{long_content}",
                                 path="/a/B.java", lineno="1", content=long_content),)
        result = compactor.compact(records, _cfg(line_max_output_chars=20))
        self.assertIn("truncate", result.transforms)
        self.assertIn("…[+", result.text)
        self.assertIn("see B.java:1 for full line", result.text)
        self.assertLess(len(result.text), len(long_content))

    def test_short_content_not_truncated(self):
        records = (parser.Record(raw="/a/B.java:1:short", path="/a/B.java",
                                 lineno="1", content="short"),)
        result = compactor.compact(records, _cfg(line_max_output_chars=500))
        self.assertNotIn("truncate", result.transforms)

    def test_tiny_overflow_not_truncated(self):
        # 11-char content over a 10 limit: the marker would make it longer.
        records = (parser.Record(raw="/a/B.java:1:abcdefghijk", path="/a/B.java",
                                 lineno="1", content="abcdefghijk"),)
        result = compactor.compact(records, _cfg(line_max_output_chars=10))
        self.assertNotIn("truncate", result.transforms)


class TestPathOnlyAndRaw(unittest.TestCase):
    def test_path_only_never_truncated(self):
        long_path = "/a/" + "d/" * 200 + "File.java"
        records = (parser.Record(raw=long_path, path=long_path),)
        result = compactor.compact(records, _cfg(line_max_output_chars=20))
        self.assertNotIn("truncate", result.transforms)

    def test_non_conforming_line_preserved(self):
        records = (
            parser.Record(raw="/a/b/X.java:1:foo", path="/a/b/X.java", lineno="1", content="foo"),
            parser.Record(raw="Binary file /a/b/Y.class matches"),
        )
        result = compactor.compact(records, _cfg())
        self.assertIn("Binary file /a/b/Y.class matches", result.text)
        self.assertEqual(len(_body_lines(result.text)), 2)


class TestGroupByFileRendering(unittest.TestCase):
    def test_groupedRun_rendersHeaderAndIndentedBody(self):
        # Given two consecutive hits from the same file (no shared prefix to strip)
        records = (
            parser.Record(raw="a.py:1:x", path="a.py", lineno="1", content="x"),
            parser.Record(raw="a.py:2:y", path="a.py", lineno="2", content="y"),
        )
        result = compactor.compact(records, _cfg())
        # Then the path is a one-off header and bodies are indented, path elided
        self.assertIn("group_by_file", result.transforms)
        self.assertIn("a.py:\n  1:x\n  2:y", result.text)

    def test_singleHitFile_rendersInlineNoRegression(self):
        # Given one hit per file (all length-1 runs)
        records = (
            parser.Record(raw="a.py:1:x", path="a.py", lineno="1", content="x"),
            parser.Record(raw="b.py:9:z", path="b.py", lineno="9", content="z"),
        )
        result = compactor.compact(records, _cfg())
        # Then output stays the classic inline path:lineno:content form
        self.assertNotIn("group_by_file", result.transforms)
        self.assertIn("a.py:1:x", result.text)
        self.assertIn("b.py:9:z", result.text)

    def test_groupThenTruncate_composeWithCorrectHint(self):
        # Given a long line inside a grouped run
        long_content = "x" * 100
        records = (
            parser.Record(raw="a.py:1:short", path="a.py", lineno="1", content="short"),
            parser.Record(raw=f"a.py:2:{long_content}", path="a.py",
                          lineno="2", content=long_content),
        )
        result = compactor.compact(records, _cfg(line_max_output_chars=20))
        # Then both transforms fire and the truncation hint still points at path:lineno
        self.assertIn("group_by_file", result.transforms)
        self.assertIn("truncate", result.transforms)
        self.assertIn("see a.py:2 for full line", result.text)
        self.assertIn("a.py:\n", result.text)  # group header still emitted


class TestSampleFixtures(unittest.TestCase):
    def test_rln_fixture_compacts(self):
        stdout = (_FIXTURES / "rln_sample.txt").read_text()
        parsed = parser.parse(stdout, {"path_only": True})
        self.assertTrue(parsed.confident)
        result = compactor.compact(parsed.records, _cfg())
        self.assertTrue(result.text.startswith("# base: "))
        self.assertLess(len(result.text), len(stdout))
        self.assertEqual(len(_body_lines(result.text)), len(stdout.rstrip("\n").split("\n")))

    def test_rn_fixture_compacts(self):
        stdout = (_FIXTURES / "rn_sample.txt").read_text()
        parsed = parser.parse(stdout, {"has_n": True})
        self.assertTrue(parsed.confident)
        result = compactor.compact(parsed.records, _cfg())
        self.assertIn("prefix_strip", result.transforms)
        self.assertLess(len(result.text), len(stdout))
        self.assertEqual(len(_body_lines(result.text)), len(stdout.rstrip("\n").split("\n")))


if __name__ == "__main__":
    unittest.main()
