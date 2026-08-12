"""truncate transform: cap each line's content at cfg.line_max_output_chars.

A *per-line* transform. Only the content tail of an over-limit line is dropped,
replaced with a marker reporting how many chars were removed and pointing at that
line's own `path:lineno` so the full line is one targeted read away. Path and
line number are never touched; path-only lines are never truncated. A line is
shortened only when the marker actually makes it smaller.

Contract: see transforms/__init__.py.
"""
from __future__ import annotations

from dataclasses import replace

NAME = "truncate"


def _hint(path, lineno):
    loc = f"{path}:{lineno}" if lineno is not None else path
    return f" — see {loc} for full line"


def _truncate(text, limit, hint=""):
    """Return (text, removed_chars); only truncates when it shortens the line."""
    if limit <= 0 or len(text) <= limit:
        return text, 0
    removed = len(text) - limit
    candidate = text[:limit] + f"…[+{removed} chars{hint}]"
    if len(candidate) >= len(text):
        return text, 0
    return candidate, len(text) - len(candidate)


def _truncate_record(record, limit):
    if not record.conforming:
        text, removed = _truncate(record.raw, limit)
        return (replace(record, raw=text) if removed else record), removed
    if record.content is None:  # path-only: never truncate a path
        return record, 0
    content, removed = _truncate(record.content, limit, _hint(record.path, record.lineno))
    return (replace(record, content=content) if removed else record), removed


def apply(records, cfg):
    limit = cfg.line_max_output_chars
    out, fired = [], False
    for record in records:
        new_record, removed = _truncate_record(record, limit)
        if removed:
            fired = True
        out.append(new_record)
    return tuple(out), [], fired
