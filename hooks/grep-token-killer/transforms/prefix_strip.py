"""prefix_strip transform: hoist the longest common path prefix into a header.

A *global* transform: it inspects every conforming record's path, finds the
longest common prefix trimmed back to the last '/', emits one `# base: <prefix>`
header line, and strips that prefix from each path. Lossless — no record dropped,
a shared prefix is merely relocated from every line into one header.

Contract: see transforms/__init__.py.
"""
from __future__ import annotations

import os
from dataclasses import replace

NAME = "prefix_strip"


def _common_base(paths):
    if not paths:
        return ""
    raw = os.path.commonprefix(paths)
    cut = raw.rfind("/")
    return raw[: cut + 1] if cut >= 0 else ""


def _strip(record, base):
    if record.path is not None and record.path.startswith(base):
        return replace(record, path=record.path[len(base):])
    return record


def apply(records, cfg):
    paths = [r.path for r in records if r.conforming and r.path is not None]
    base = _common_base(paths)
    if not base:
        return records, [], False
    stripped = tuple(_strip(record, base) for record in records)
    return stripped, [f"# base: {base}"], True
