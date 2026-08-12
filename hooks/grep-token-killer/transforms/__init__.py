"""Compaction transforms, applied in registry order.

Each transform lives in its own module and implements the contract:

    NAME: str
        Label reported in CompactResult.transforms when the transform fires.
    apply(records, cfg) -> (records, header_lines, fired)
        records      : tuple of parser.Record (duck-typed: .conforming, .path,
                       .lineno, .content, .raw). Return the transformed tuple.
        header_lines : list[str] prepended above the body (e.g. the `# base:`
                       line). Empty when the transform adds no header.
        fired        : bool — True when the transform changed anything.

Order matters: prefix_strip runs first so downstream steps see the shortened
path; group_by_file then marks repeated-filename runs; truncate runs last so a
truncation marker's `path:lineno` hint still reflects the (preserved) path even
when grouping elides it from the rendered body. To add a transform, drop a new
module here and append it to REGISTRY at the right position.
"""
from . import group_by_file, prefix_strip, truncate

REGISTRY = (prefix_strip, group_by_file, truncate)
