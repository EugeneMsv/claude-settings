"""Drive the registered compaction transforms and render records to text.

Single responsibility: run transforms/REGISTRY in order over the parsed records,
collect any header lines they emit, and render exactly one output line per record
(plus the headers). The transforms themselves (prefix_strip, truncate) each live
in their own module under transforms/; this module owns only orchestration,
rendering, and the invariant that no record is ever dropped or merged.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Tuple

from transforms import REGISTRY


@dataclass(frozen=True)
class CompactResult:
    text: str
    transforms: Tuple[str, ...]


_GROUP_INDENT = "  "


def _body(record):
    """Render a record's body without its path (used inside a file group)."""
    if record.lineno is not None:
        return f"{_GROUP_INDENT}{record.lineno}:{record.content}"
    return f"{_GROUP_INDENT}{record.content}"


def _render_line(record):
    if not record.conforming:
        return record.raw
    if record.content is None:  # path-only
        return record.path
    if record.group_head:  # open a file group: path header once, then its body
        return f"{record.path}:\n{_body(record)}"
    if record.grouped:  # inside a group: body only, path elided
        return _body(record)
    if record.lineno is not None:
        return f"{record.path}:{record.lineno}:{record.content}"
    return f"{record.path}:{record.content}"


def compact(records, cfg):
    headers, fired = [], []
    for transform in REGISTRY:
        records, header_lines, did_fire = transform.apply(records, cfg)
        headers.extend(header_lines)
        if did_fire:
            fired.append(transform.NAME)

    body = "\n".join(_render_line(record) for record in records)
    prefix = ("\n".join(headers) + "\n") if headers else ""
    return CompactResult(f"{prefix}{body}\n", tuple(sorted(fired)))
