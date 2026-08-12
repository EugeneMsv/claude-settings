"""Append one JSONL audit record per grep seen.

Single responsibility: durable, append-only I/O. Creates the parent directory on
demand and writes exactly one compact JSON line per call. Never raises into the
caller; a logging failure must not break the tool, so errors are swallowed.
"""
from __future__ import annotations

import json
import os
from pathlib import Path

DEFAULT_LOG_PATH = Path.home() / ".claude" / "feedback-loop" / "grep-token-killer.jsonl"


def append(record, log_path=None):
    """Append `record` as one JSON line; best-effort, swallows I/O errors."""
    path = Path(log_path) if log_path is not None else DEFAULT_LOG_PATH
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        line = json.dumps(record, ensure_ascii=False)
        with open(path, "a", encoding="utf-8") as handle:
            handle.write(line + "\n")
    except (OSError, TypeError, ValueError):
        pass
