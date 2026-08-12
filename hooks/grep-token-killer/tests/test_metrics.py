import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import metrics  # noqa: E402


class TestEstimateTokens(unittest.TestCase):
    def test_estimate_tokens_parametrized(self):
        cases = [("", 0), ("abcd", 1), ("a" * 100, 25), ("abc", 0)]
        for text, expected in cases:
            with self.subTest(length=len(text)):
                self.assertEqual(metrics.estimate_tokens(text), expected)


class TestTokenSavings(unittest.TestCase):
    def test_positive_savings(self):
        savings = metrics.token_savings(100, 60)
        self.assertEqual(savings.removed, 40)
        self.assertEqual(savings.pct, 40.0)

    def test_zero_before_no_div_by_zero(self):
        savings = metrics.token_savings(0, 0)
        self.assertEqual(savings.removed, 0)
        self.assertEqual(savings.pct, 0.0)

    def test_negative_when_after_larger(self):
        savings = metrics.token_savings(50, 80)
        self.assertEqual(savings.removed, -30)
        self.assertLess(savings.pct, 0)

    def test_pct_rounded_one_decimal(self):
        savings = metrics.token_savings(525, 334)
        self.assertEqual(savings.removed, 191)
        self.assertEqual(savings.pct, 36.4)


if __name__ == "__main__":
    unittest.main()
