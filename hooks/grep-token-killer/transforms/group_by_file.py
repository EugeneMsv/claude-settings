"""group_by_file transform: hoist a repeated filename into a one-off header.

A *global* transform. Recursive multi-file greps emit the same path on every
consecutive line from a file (`a.py:1:x`, `a.py:2:y`, ...). This marks each run
of >= 2 consecutive conforming records sharing the same path: the first record
becomes a `group_head` (renderer prints its path once as a `path:` header) and
the rest become `grouped` (renderer prints only `lineno:content`, indented).
Lossless — every record and its path/lineno/content survive on the record; only
the *rendering* elides the repeated path. The renderer (compactor._render_line)
owns the actual header/indent output.

Grouping is by runs of *consecutive* identical paths — order is never assumed.
A file whose hits are split into two runs simply gets two headers: still smaller,
never wrong. Runs of length 1, non-conforming records, and path-only records
(content is None) are left untouched.

Contract: see transforms/__init__.py.
"""
from __future__ import annotations

from dataclasses import replace

NAME = "group_by_file"


def _groupable(record):
    # A record can join a group only if it has both a path and a content body;
    # path-only records (content is None) render as a bare path and gain nothing.
    return record.conforming and record.content is not None


def _run_length(records, start):
    path = records[start].path
    end = start + 1
    while end < len(records) and _groupable(records[end]) and records[end].path == path:
        end += 1
    return end - start


def apply(records, cfg):
    out = []
    fired = False
    index = 0
    total = len(records)
    while index < total:
        record = records[index]
        if not _groupable(record):
            out.append(record)
            index += 1
            continue
        length = _run_length(records, index)
        if length < 2:
            out.append(record)
            index += 1
            continue
        out.append(replace(record, group_head=True))
        for offset in range(1, length):
            out.append(replace(records[index + offset], grouped=True))
        fired = True
        index += length
    return tuple(out), [], fired
