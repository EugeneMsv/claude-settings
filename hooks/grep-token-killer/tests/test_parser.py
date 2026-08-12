import os
import sys
import unittest
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import parser  # noqa: E402

_FIXTURES = Path(__file__).resolve().parent / "fixtures"


class TestParsePathLineno(unittest.TestCase):
    def test_path_lineno_content(self):
        stdout = (
            "/a/B.java:12:foo\n"
            "/a/C.java:30:bar\n"
            "/a/D.java:5:baz\n"
        )
        result = parser.parse(stdout, {"has_n": True})
        self.assertTrue(result.confident)
        self.assertEqual(len(result.records), 3)
        first = result.records[0]
        self.assertEqual(first.path, "/a/B.java")
        self.assertEqual(first.lineno, "12")
        self.assertEqual(first.content, "foo")

    def test_content_with_colons_preserved(self):
        stdout = "/a/B.java:12:if (x): y\n"
        result = parser.parse(stdout, {"has_n": True})
        record = result.records[0]
        self.assertEqual(record.path, "/a/B.java")
        self.assertEqual(record.lineno, "12")
        self.assertEqual(record.content, "if (x): y")

    def test_space_in_path_conforms(self):
        stdout = "/My Dir/File.java:1:code\n"
        result = parser.parse(stdout, {"has_n": True})
        self.assertTrue(result.confident)
        self.assertEqual(result.records[0].path, "/My Dir/File.java")


class TestParsePathContent(unittest.TestCase):
    def test_path_content_without_lineno(self):
        stdout = "/a/B.java:foo bar\n/a/C.java:baz\n"
        result = parser.parse(stdout, {"has_n": False})
        self.assertTrue(result.confident)
        self.assertEqual(result.records[0].path, "/a/B.java")
        self.assertEqual(result.records[0].content, "foo bar")
        self.assertIsNone(result.records[0].lineno)


class TestParsePathOnly(unittest.TestCase):
    def test_path_only_lines(self):
        stdout = "/a/B.java\n/a/C.java\n"
        result = parser.parse(stdout, {"path_only": True})
        self.assertTrue(result.confident)
        self.assertEqual([r.path for r in result.records], ["/a/B.java", "/a/C.java"])


class TestConfidenceGate(unittest.TestCase):
    def test_binary_line_tolerated(self):
        stdout = (
            "/a/B.java:12:foo\n"
            "/a/C.java:30:bar\n"
            "Binary file /a/D.class matches\n"
        )
        result = parser.parse(stdout, {"has_n": True})
        self.assertTrue(result.confident)
        self.assertFalse(result.records[2].conforming)
        self.assertEqual(result.records[2].raw, "Binary file /a/D.class matches")

    def test_uniq_c_malformed_aborts(self):
        stdout = (_FIXTURES / "uniq_c_malformed.txt").read_text()
        result = parser.parse(stdout, {"has_n": True})
        self.assertFalse(result.confident)
        self.assertTrue(result.reason.startswith("low_confidence"))

    def test_empty_stdout_not_confident(self):
        result = parser.parse("", {"has_n": True})
        self.assertFalse(result.confident)
        self.assertEqual(result.reason, "empty_stdout")


if __name__ == "__main__":
    unittest.main()
