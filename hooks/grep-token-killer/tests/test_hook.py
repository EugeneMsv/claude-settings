import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import hook  # noqa: E402

_FIXTURES = Path(__file__).resolve().parent / "fixtures"


def _payload(command, stdout, tool_name="Bash"):
    return json.dumps({
        "tool_name": tool_name,
        "tool_input": {"command": command},
        "tool_response": {"stdout": stdout, "stderr": "", "interrupted": False},
    })


class _HookCase(unittest.TestCase):
    def setUp(self):
        self._dir = tempfile.TemporaryDirectory()
        self.addCleanup(self._dir.cleanup)
        self.log = Path(self._dir.name) / "audit.jsonl"

    def _records(self):
        if not self.log.exists():
            return []
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def _run(self, command, stdout, env=None, tool_name="Bash"):
        return hook.run(_payload(command, stdout, tool_name), env=env, log_path=self.log)


class TestSilentNoOp(_HookCase):
    def test_non_bash_tool_no_log(self):
        self.assertEqual(self._run("grep -rn X dir", "a\nb\n", tool_name="Read"), {})
        self.assertEqual(self._records(), [])

    def test_non_grep_command_no_log(self):
        self.assertEqual(self._run("ls -la", "a\nb\n"), {})
        self.assertEqual(self._records(), [])

    def test_malformed_json_passthrough(self):
        self.assertEqual(hook.run("{not json", log_path=self.log), {})


class TestIneligibleLogged(_HookCase):
    def test_count_flag_passthrough_logged(self):
        self.assertEqual(self._run("grep -c X dir", "dir/A.java:3\n"), {})
        records = self._records()
        self.assertEqual(len(records), 1)
        self.assertFalse(records[0]["eligible"])
        self.assertEqual(records[0]["passthrough_reason"], "unsafe_flag:-c")

    def test_pipe_uniq_c_passthrough_logged(self):
        self.assertEqual(self._run("grep -rn X dir | uniq -c", "  3 x\n"), {})
        self.assertEqual(self._records()[0]["passthrough_reason"], "pipe_breaks_grammar:uniq")


class TestEligibleActive(_HookCase):
    def test_rn_fixture_rewritten(self):
        stdout = (_FIXTURES / "rn_sample.txt").read_text()
        response = self._run("grep -rn class dir --include=*.java", stdout)
        updated = response["hookSpecificOutput"]["updatedToolOutput"]
        self.assertTrue(updated["stdout"].startswith("# base: "))
        self.assertLess(len(updated["stdout"]), len(stdout))
        self.assertIn("systemMessage", response)
        self.assertIn("%", response["systemMessage"])
        record = self._records()[0]
        self.assertTrue(record["eligible"])
        self.assertIsNone(record["passthrough_reason"])
        self.assertGreater(record["tokens_removed"], 0)

    def test_cd_prefix_compound_rewritten(self):
        stdout = (_FIXTURES / "rn_sample.txt").read_text()
        response = self._run("cd dir && grep -rn class dir --include=*.java", stdout)
        updated = response["hookSpecificOutput"]["updatedToolOutput"]
        self.assertTrue(updated["stdout"].startswith("# base: "))
        self.assertLess(len(updated["stdout"]), len(stdout))
        record = self._records()[0]
        self.assertTrue(record["eligible"])
        self.assertIsNone(record["passthrough_reason"])
        self.assertGreater(record["tokens_removed"], 0)

    def test_filter_grep_tail_rewritten(self):
        stdout = (_FIXTURES / "rn_sample.txt").read_text()
        response = self._run("grep -rn class dir --include=*.java | grep class", stdout)
        updated = response["hookSpecificOutput"]["updatedToolOutput"]
        self.assertTrue(updated["stdout"].startswith("# base: "))
        record = self._records()[0]
        self.assertTrue(record["eligible"])
        self.assertIsNone(record["passthrough_reason"])

    def test_shadow_mode_logs_but_no_rewrite(self):
        stdout = (_FIXTURES / "rn_sample.txt").read_text()
        response = self._run("grep -rn class dir", stdout, env={"GTK_MODE": "shadow"})
        self.assertNotIn("hookSpecificOutput", response)
        self.assertIn("would save", response["systemMessage"])
        record = self._records()[0]
        self.assertEqual(record["mode"], "shadow")
        self.assertIsNone(record["passthrough_reason"])
        self.assertGreater(record["tokens_removed"], 0)


class TestParseAndThresholdGates(_HookCase):
    def test_low_confidence_passthrough(self):
        stdout = (_FIXTURES / "uniq_c_malformed.txt").read_text()
        self.assertEqual(self._run("grep -rn X dir", stdout), {})
        self.assertTrue(self._records()[0]["passthrough_reason"].startswith("low_confidence"))

    def test_below_min_lines_passthrough(self):
        self.assertEqual(self._run("grep -rn X dir", "d/A.java:1:a\nd/B.java:2:b\n"), {})
        self.assertEqual(self._records()[0]["passthrough_reason"], "below_min_lines")

    def test_savings_below_min_passthrough(self):
        stdout = (_FIXTURES / "rn_sample.txt").read_text()
        self.assertEqual(self._run("grep -rn class dir", stdout, env={"GTK_MIN_SAVING_PCT": "99"}), {})
        self.assertEqual(self._records()[0]["passthrough_reason"], "savings_below_min")


if __name__ == "__main__":
    unittest.main()
