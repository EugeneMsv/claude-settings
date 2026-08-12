import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import config  # noqa: E402

_NO_FILE = Path("/nonexistent/grep-token-killer/config.json")


class TestConfigDefaults(unittest.TestCase):
    def test_defaults_when_empty_env_and_no_file(self):
        # Given no env and a missing config file
        cfg = config.load(env={}, config_path=_NO_FILE)
        # Then all defaults apply
        self.assertEqual(cfg.mode, "active")
        self.assertEqual(cfg.line_max_output_chars, 500)
        self.assertEqual(cfg.min_lines, 3)
        self.assertEqual(cfg.min_saving_pct, 10.0)


class TestConfigEnvOverride(unittest.TestCase):
    def test_env_overrides_each_field(self):
        env = {
            "GTK_MODE": "shadow",
            "GTK_LINE_MAX_OUTPUT_CHARS": "200",
            "GTK_MIN_LINES": "5",
            "GTK_MIN_SAVING_PCT": "25",
        }
        cfg = config.load(env=env, config_path=_NO_FILE)
        self.assertEqual(cfg.mode, "shadow")
        self.assertEqual(cfg.line_max_output_chars, 200)
        self.assertEqual(cfg.min_lines, 5)
        self.assertEqual(cfg.min_saving_pct, 25.0)


class TestConfigInvalidEnv(unittest.TestCase):
    def test_invalid_values_fall_back_to_default(self):
        cases = [
            ("GTK_MODE", "bogus", "mode", "active"),
            ("GTK_LINE_MAX_OUTPUT_CHARS", "abc", "line_max_output_chars", 500),
            ("GTK_MIN_LINES", "-2", "min_lines", 3),
            ("GTK_MIN_SAVING_PCT", "xx", "min_saving_pct", 10.0),
        ]
        for env_key, bad_value, field, expected in cases:
            with self.subTest(env_key=env_key):
                cfg = config.load(env={env_key: bad_value}, config_path=_NO_FILE)
                self.assertEqual(getattr(cfg, field), expected)


class TestConfigFilePrecedence(unittest.TestCase):
    def test_file_used_then_env_wins(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "config.json"
            path.write_text(json.dumps({"mode": "shadow", "line_max_output_chars": 300}))

            from_file = config.load(env={}, config_path=path)
            self.assertEqual(from_file.mode, "shadow")
            self.assertEqual(from_file.line_max_output_chars, 300)

            env_wins = config.load(env={"GTK_MODE": "active"}, config_path=path)
            self.assertEqual(env_wins.mode, "active")
            self.assertEqual(env_wins.line_max_output_chars, 300)

    def test_malformed_file_ignored(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "config.json"
            path.write_text("{not valid json")
            cfg = config.load(env={}, config_path=path)
            self.assertEqual(cfg.mode, "active")


if __name__ == "__main__":
    unittest.main()
