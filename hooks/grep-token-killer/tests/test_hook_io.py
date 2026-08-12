import json
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import hook_io  # noqa: E402


def _input(command="grep -rn X dir", stdout="a\n", **response):
    payload = {
        "tool_name": "Bash",
        "tool_input": {"command": command},
        "tool_response": {"stdout": stdout, "stderr": "", "interrupted": False, **response},
    }
    return json.dumps(payload)


class TestParseInput(unittest.TestCase):
    def test_real_schema_shape(self):
        result = hook_io.parse_input(_input(command="grep -rn X dir", stdout="line\n"))
        self.assertEqual(result.tool_name, "Bash")
        self.assertEqual(result.command, "grep -rn X dir")
        self.assertEqual(result.stdout, "line\n")
        self.assertFalse(result.out_of_band)

    def test_missing_tool_response_yields_empty_stdout(self):
        result = hook_io.parse_input(json.dumps({"tool_name": "Bash", "tool_input": {"command": "grep x"}}))
        self.assertEqual(result.stdout, "")
        self.assertEqual(result.tool_response, {})

    def test_non_dict_tool_input_yields_empty_command(self):
        result = hook_io.parse_input(json.dumps({"tool_name": "Bash", "tool_input": "oops"}))
        self.assertEqual(result.command, "")

    def test_out_of_band_when_persisted_path_and_empty_stdout(self):
        result = hook_io.parse_input(_input(stdout="", persistedOutputPath="/tmp/x"))
        self.assertTrue(result.out_of_band)

    def test_not_out_of_band_when_stdout_present(self):
        result = hook_io.parse_input(_input(stdout="data\n", persistedOutputPath="/tmp/x"))
        self.assertFalse(result.out_of_band)

    def test_malformed_json_returns_none(self):
        self.assertIsNone(hook_io.parse_input("{not json"))

    def test_non_object_json_returns_none(self):
        self.assertIsNone(hook_io.parse_input("[1, 2, 3]"))


class TestBuildUpdatedOutput(unittest.TestCase):
    def test_clones_and_replaces_only_stdout(self):
        original = {"stdout": "old", "stderr": "err", "interrupted": False, "isImage": False}
        envelope = hook_io.build_updated_output(original, "new")
        updated = envelope["hookSpecificOutput"]["updatedToolOutput"]
        self.assertEqual(updated["stdout"], "new")
        self.assertEqual(updated["stderr"], "err")
        self.assertFalse(updated["interrupted"])
        self.assertFalse(updated["isImage"])
        self.assertEqual(original["stdout"], "old")  # original untouched

    def test_envelope_shape(self):
        envelope = hook_io.build_updated_output({"stdout": "x", "stderr": "", "interrupted": False}, "y")
        self.assertEqual(envelope["hookSpecificOutput"]["hookEventName"], "PostToolUse")
        self.assertIn("updatedToolOutput", envelope["hookSpecificOutput"])
        self.assertNotIn("systemMessage", envelope)


if __name__ == "__main__":
    unittest.main()
