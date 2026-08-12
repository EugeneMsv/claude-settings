import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import config  # noqa: E402
import parser  # noqa: E402
from transforms import group_by_file  # noqa: E402


def _cfg():
    return config.Config()


def _rec(path, lineno, content):
    return parser.Record(raw=f"{path}:{lineno}:{content}", path=path,
                         lineno=lineno, content=content)


class TestGroupByFileMarking(unittest.TestCase):
    def test_apply_twoConsecutiveSamePath_marksHeadAndGrouped(self):
        # Given two hits from the same file back-to-back
        records = (_rec("a.py", "1", "x"), _rec("a.py", "2", "y"))
        # When the transform runs
        out, headers, fired = group_by_file.apply(records, _cfg())
        # Then the first opens the group and the second is grouped
        self.assertTrue(fired)
        self.assertEqual(headers, [])
        self.assertTrue(out[0].group_head)
        self.assertFalse(out[0].grouped)
        self.assertTrue(out[1].grouped)
        self.assertFalse(out[1].group_head)

    def test_apply_singleRecord_leftUntouched(self):
        # Given a single hit (run length 1)
        records = (_rec("a.py", "1", "x"),)
        # When the transform runs
        out, _, fired = group_by_file.apply(records, _cfg())
        # Then nothing is marked and the transform did not fire
        self.assertFalse(fired)
        self.assertFalse(out[0].group_head)
        self.assertFalse(out[0].grouped)

    def test_apply_differentPathsBackToBack_notGrouped(self):
        # Given two hits from different files
        records = (_rec("a.py", "1", "x"), _rec("b.py", "2", "y"))
        # When the transform runs
        out, _, fired = group_by_file.apply(records, _cfg())
        # Then each is its own length-1 run, nothing grouped
        self.assertFalse(fired)
        self.assertFalse(any(r.group_head or r.grouped for r in out))

    def test_apply_nonConformingBetweenSamePath_breaksRun(self):
        # Given same-path hits split by a non-conforming line
        records = (
            _rec("a.py", "1", "x"),
            parser.Record(raw="Binary file a.py matches"),
            _rec("a.py", "2", "y"),
        )
        # When the transform runs
        out, _, fired = group_by_file.apply(records, _cfg())
        # Then the run is broken into two length-1 runs -> no grouping
        self.assertFalse(fired)
        self.assertFalse(any(r.group_head or r.grouped for r in out))

    def test_apply_pathOnlyRecords_neverGrouped(self):
        # Given consecutive path-only records with the same path (content is None)
        records = (
            parser.Record(raw="a.py", path="a.py"),
            parser.Record(raw="a.py", path="a.py"),
        )
        # When the transform runs
        out, _, fired = group_by_file.apply(records, _cfg())
        # Then path-only records are never grouped
        self.assertFalse(fired)
        self.assertFalse(any(r.group_head or r.grouped for r in out))

    def test_apply_splitRuns_onlyConsecutiveGrouped(self):
        # Given a,a,b,a -> the trailing single 'a' must NOT join the first run
        records = (
            _rec("a.py", "1", "x"),
            _rec("a.py", "2", "y"),
            _rec("b.py", "9", "z"),
            _rec("a.py", "3", "w"),
        )
        # When the transform runs
        out, _, fired = group_by_file.apply(records, _cfg())
        # Then only the first consecutive a-run is grouped
        self.assertTrue(fired)
        self.assertTrue(out[0].group_head)
        self.assertTrue(out[1].grouped)
        self.assertFalse(out[2].group_head or out[2].grouped)  # lone b
        self.assertFalse(out[3].group_head or out[3].grouped)  # lone trailing a

    def test_apply_preservesPathLinenoContent(self):
        # Given a grouped run
        records = (_rec("a.py", "1", "x"), _rec("a.py", "2", "y"))
        # When the transform runs
        out, _, _ = group_by_file.apply(records, _cfg())
        # Then every record keeps its path/lineno/content (lossless marking)
        self.assertEqual((out[0].path, out[0].lineno, out[0].content), ("a.py", "1", "x"))
        self.assertEqual((out[1].path, out[1].lineno, out[1].content), ("a.py", "2", "y"))


if __name__ == "__main__":
    unittest.main()
