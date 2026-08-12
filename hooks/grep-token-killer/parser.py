"""Split eligible grep stdout into structured records, with a confidence gate.

Single responsibility: turn raw stdout into `(path, lineno, content)` records and
decide whether the output really is grep grammar. The gate is the second,
data-driven half of the defense-in-depth: even when the detector judged the
command safe, if too few lines parse as `path[:lineno]:content` (e.g. a count got
prepended by a pipe the detector did not recognize) parsing aborts and the hook
passes the original output through.

Conformance rule: the path field's first character must be non-space and
non-colon, and the path itself contains no colon. This rejects count-prefixed
lines (`   3 /a/B.java:12:x`) whose path field would start with whitespace.
Non-conforming lines (e.g. `Binary file X matches`) are preserved verbatim.
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Optional, Tuple

# Fraction of lines that must parse as grep grammar to trust the whole block.
CONFIDENCE_THRESHOLD = 0.5

_RE_PATH_LINENO = re.compile(r"^([^:\s][^:]*):(\d+):(.*)$")
_RE_PATH_CONTENT = re.compile(r"^([^:\s][^:]*):(.*)$")


@dataclass(frozen=True)
class Record:
    raw: str
    path: Optional[str] = None
    lineno: Optional[str] = None
    content: Optional[str] = None
    # Set by the group_by_file transform so the renderer can hoist a repeated
    # filename into a one-off header. group_head: this record opens a group and
    # its path is rendered once as a `path:` header line. grouped: this record
    # sits inside a group and renders its body (lineno:content) without the path.
    group_head: bool = False
    grouped: bool = False

    @property
    def conforming(self):
        return self.path is not None


@dataclass(frozen=True)
class ParseResult:
    records: Tuple[Record, ...]
    confident: bool
    reason: str
    confidence: float


def _split_lines(stdout):
    if stdout == "":
        return []
    lines = stdout.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    return lines


def _parse_path_only(lines):
    records = tuple(Record(raw=line, path=line) for line in lines)
    blank = any(line == "" for line in lines)
    if blank:
        return ParseResult(records, False, "blank_path_line", 0.0)
    return ParseResult(records, True, "", 1.0)


def parse(stdout, ctx):
    lines = _split_lines(stdout)
    if not lines:
        return ParseResult((), False, "empty_stdout", 0.0)

    if ctx.get("path_only"):
        return _parse_path_only(lines)

    has_n = bool(ctx.get("has_n"))
    pattern = _RE_PATH_LINENO if has_n else _RE_PATH_CONTENT
    records = []
    conforming = 0
    for line in lines:
        match = pattern.match(line)
        if match is None:
            records.append(Record(raw=line))
            continue
        conforming += 1
        if has_n:
            records.append(Record(raw=line, path=match.group(1),
                                  lineno=match.group(2), content=match.group(3)))
        else:
            records.append(Record(raw=line, path=match.group(1),
                                  content=match.group(2)))

    ratio = conforming / len(lines)
    if ratio < CONFIDENCE_THRESHOLD:
        return ParseResult(tuple(records), False, f"low_confidence:{ratio:.2f}", ratio)
    return ParseResult(tuple(records), True, "", ratio)
