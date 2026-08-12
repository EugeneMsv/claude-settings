import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import detector  # noqa: E402


class TestDetectorEligible(unittest.TestCase):
    def test_eligible_commands(self):
        cases = [
            "grep -rn TODO src",
            "grep -rln TODO src",
            "grep -rn TODO src | head -10",
            "grep -rn TODO src | sort",
            "grep -rn TODO src | tee out.txt",
            "grep --color=never -rn TODO src",
            "grep -rn TODO src --include=*.java",
            "grep -rn TODO src | grep foo",
            "grep -rn TODO src | sort | head",
            "grep -rn TODO src | grep foo | tail",
        ]
        for command in cases:
            with self.subTest(command=command):
                decision = detector.decide(command)
                self.assertTrue(decision.eligible, decision.reason)
                self.assertEqual(decision.reason, "")

    def test_ctx_flags_recorded(self):
        recursive_numbered = detector.decide("grep -rn TODO src")
        self.assertTrue(recursive_numbered.ctx["recursive"])
        self.assertTrue(recursive_numbered.ctx["has_n"])
        self.assertFalse(recursive_numbered.ctx["path_only"])

        path_only = detector.decide("grep -rln TODO src")
        self.assertTrue(path_only.ctx["path_only"])

        piped = detector.decide("grep -rn TODO src | head -10")
        self.assertTrue(piped.ctx["pipeline"])
        self.assertEqual(piped.ctx["last_stage"], "head")


class TestDetectorPipelinePassthrough(unittest.TestCase):
    def test_pipeline_reasons(self):
        cases = [
            ("grep -rn TODO src | uniq -c", "pipe_breaks_grammar:uniq"),
            ("grep -rn TODO src | wc -l", "pipe_breaks_grammar:wc"),
            ("grep -rn TODO src | awk '{print $1}'", "pipe_breaks_grammar:awk"),
            ("grep -rn TODO src | grep -c foo", "pipe_breaks_grammar:grep"),
            ("grep -rn TODO src | grep -l foo", "pipe_breaks_grammar:grep"),
            ("grep -rn TODO src | sed s/a/b/ | head", "pipe_breaks_grammar:sed"),
            ("grep -rn TODO src | less", "unknown_pipe_stage:less"),
            ("grep -rn TODO src && echo done", "compound_operator"),
            ("grep -rn TODO src ; echo done", "compound_operator"),
            ("grep -rn TODO src > out.txt", "redirected_to_file"),
            ("grep -rn TODO src >> out.txt", "redirected_to_file"),
        ]
        for command, expected_reason in cases:
            with self.subTest(command=command):
                decision = detector.decide(command)
                self.assertFalse(decision.eligible)
                self.assertEqual(decision.reason, expected_reason)


class TestDetectorUnsafeFlags(unittest.TestCase):
    def test_unsafe_flag_reasons(self):
        cases = [
            ("grep -c TODO src", "unsafe_flag:-c"),
            ("grep -ro TODO src", "unsafe_flag:-o"),
            ("grep -rn -A2 TODO src", "unsafe_flag:-A"),
            ("grep -rh TODO src", "unsafe_flag:-h"),
            ("grep --color=auto -rn TODO src", "unsafe_flag:--color"),
            ("grep --count TODO src", "unsafe_flag:--count"),
            ("grep --only-matching TODO src", "unsafe_flag:--only-matching"),
        ]
        for command, expected_reason in cases:
            with self.subTest(command=command):
                decision = detector.decide(command)
                self.assertFalse(decision.eligible)
                self.assertEqual(decision.reason, expected_reason)


class TestDetectorDefensive(unittest.TestCase):
    def test_unterminated_quote_is_unparseable(self):
        decision = detector.decide('grep "unterminated TODO src')
        self.assertFalse(decision.eligible)
        self.assertEqual(decision.reason, "unparseable_command")

    def test_non_grep_first_stage(self):
        decision = detector.decide("ls | grep TODO")
        self.assertFalse(decision.eligible)
        self.assertEqual(decision.reason, "not_grep_first_stage")


class TestDetectorCompoundChains(unittest.TestCase):
    def test_silent_prefix_then_grep_is_eligible(self):
        cases = [
            "cd dir && grep -rn TODO src",
            "cd a && cd b && grep -rn X .",
            "export FOO=1 && grep -rn X .",
            "cd dir && grep -rn TODO src | head",
        ]
        for command in cases:
            with self.subTest(command=command):
                decision = detector.decide(command)
                self.assertTrue(decision.eligible, decision.reason)
                self.assertEqual(decision.reason, "")

    def test_ctx_computed_from_grep_segment(self):
        decision = detector.decide("cd dir && grep -rn TODO src")
        self.assertTrue(decision.ctx["recursive"])
        self.assertTrue(decision.ctx["has_n"])

        piped = detector.decide("cd dir && grep -rn TODO src | head")
        self.assertEqual(piped.ctx["last_stage"], "head")

    def test_grep_segment_flags_and_pipe_still_gated(self):
        cases = [
            ("cd dir && grep X . > out.txt", "redirected_to_file"),
            ("cd dir && grep -rn X . | uniq -c", "pipe_breaks_grammar:uniq"),
        ]
        for command, expected_reason in cases:
            with self.subTest(command=command):
                decision = detector.decide(command)
                self.assertFalse(decision.eligible)
                self.assertEqual(decision.reason, expected_reason)

    def test_non_silent_or_misplaced_grep_rejected(self):
        cases = [
            "grep -rn X . && echo done",
            "echo hi && grep -rn X .",
            "grep -rn X . || echo none",
            "cd dir && sed -n 1p f ; grep X .",
        ]
        for command in cases:
            with self.subTest(command=command):
                decision = detector.decide(command)
                self.assertFalse(decision.eligible)
                self.assertEqual(decision.reason, "compound_operator")


if __name__ == "__main__":
    unittest.main()
