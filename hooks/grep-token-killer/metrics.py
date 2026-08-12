"""Token-count estimation and savings math for grep-token-killer.

Single responsibility: pure functions, no I/O. Tokens use the chars/4 heuristic,
applied identically to before and after so the ratio stays meaningful even
though the absolute counts are approximate.
"""
from __future__ import annotations

from dataclasses import dataclass

_CHARS_PER_TOKEN = 4


def estimate_tokens(text):
    if not text:
        return 0
    return len(text) // _CHARS_PER_TOKEN


@dataclass(frozen=True)
class Savings:
    removed: int
    pct: float


def token_savings(before_tokens, after_tokens):
    """Tokens removed and percent saved; pct is 0.0 when before is non-positive."""
    removed = before_tokens - after_tokens
    pct = (removed / before_tokens * 100.0) if before_tokens > 0 else 0.0
    return Savings(removed=removed, pct=round(pct, 1))
