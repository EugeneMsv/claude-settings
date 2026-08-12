import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import logger  # noqa: E402


class TestAppend(unittest.TestCase):
    def setUp(self):
        self._dir = tempfile.TemporaryDirectory()
        self.addCleanup(self._dir.cleanup)
        self.path = Path(self._dir.name) / "nested" / "log.jsonl"

    def test_creates_parent_and_writes_one_line(self):
        logger.append({"a": 1}, self.path)
        lines = self.path.read_text().splitlines()
        self.assertEqual(len(lines), 1)
        self.assertEqual(json.loads(lines[0]), {"a": 1})

    def test_appends_multiple_records(self):
        logger.append({"n": 1}, self.path)
        logger.append({"n": 2}, self.path)
        lines = self.path.read_text().splitlines()
        self.assertEqual([json.loads(line)["n"] for line in lines], [1, 2])

    def test_unserializable_record_is_swallowed(self):
        logger.append({"bad": object()}, self.path)  # must not raise
        self.assertFalse(self.path.exists() and self.path.read_text())


if __name__ == "__main__":
    unittest.main()
