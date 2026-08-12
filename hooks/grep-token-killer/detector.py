"""Decide whether a grep command's stdout is safe to compact.

Single responsibility: classify the *command* (never the output). Two gates:

1. Pipeline shape — the hook sees the final shell stdout, so a trailing stage
   that rewrites grep's grammar (uniq/wc/awk/a second grep/...) makes the output
   un-compactable. Only grammar-preserving trailing stages (head/tail/sort/...)
   keep the `path[:lineno]:content` shape.
2. grep flags — flags that drop paths, emit counts/offsets/ANSI, or restructure
   lines (-c, -o, -h, -A/-B/-C, --color=always, ...) force passthrough.

Anything ambiguous returns eligible=False. The parser (Task 4) independently
re-validates the real lines, so both layers must agree before a rewrite.
"""
from __future__ import annotations

import shlex
from dataclasses import dataclass, field

# Trailing pipe stages that keep grep's line grammar (subset / reordering only).
PRESERVING_LAST = frozenset({"head", "tail", "cat", "tee", "sort"})
# Trailing stages that mangle the grammar (prepend counts, collapse, reshape).
BREAKING_LAST = frozenset({
    "uniq", "wc", "awk", "sed", "cut", "tr", "xargs",
    "column", "nl", "rev", "fmt", "fold", "paste",
})

# Short grep flags that make output un-compactable.
_UNSAFE_SHORT = frozenset("hZcoABCbq")
# Short flags that yield path-only output (compactable by prefix strip, no truncation).
_PATHONLY_SHORT = frozenset("lL")

_UNSAFE_LONG = frozenset({
    "--no-filename", "--null", "--count", "--only-matching",
    "--after-context", "--before-context", "--context",
    "--byte-offset", "--quiet", "--silent",
})
_PATHONLY_LONG = frozenset({"--files-with-matches", "--files-without-match"})
_RECURSIVE_LONG = frozenset({"--recursive", "--dereference-recursive"})

# Compound operators that chain separate commands in one shell line.
_COMPOUND_OPS = frozenset({"&&", "||", ";"})
# Leaders of commands that emit nothing to stdout, so a chain like
# `cd dir && grep ...` leaves stdout as pure grep output (still compactable).
_SILENT_LEADERS = frozenset({"cd", "pushd", "popd", "export", "unset", "set", ":", "true"})


@dataclass(frozen=True)
class Decision:
    eligible: bool
    reason: str
    ctx: dict = field(default_factory=dict)


def _split_stages(tokens):
    """Split a token list on '|' into pipeline stages."""
    stages, current = [], []
    for token in tokens:
        if token == "|":
            stages.append(current)
            current = []
        else:
            current.append(token)
    stages.append(current)
    return stages


def _split_segments(tokens):
    """Split a token list on compound operators into command segments.

    Mirrors `_split_stages` but breaks on `&&`/`||`/`;` instead of `|`. Empty
    segments (e.g. a leading/trailing operator) are dropped.
    """
    segments, current = [], []
    for token in tokens:
        if token in _COMPOUND_OPS:
            if current:
                segments.append(current)
            current = []
        else:
            current.append(token)
    if current:
        segments.append(current)
    return segments


def _is_filter_grep(stage):
    """True when a trailing `grep` only filters stdin lines (grammar-preserving).

    A downstream grep reading stdin just drops non-matching lines, so the surviving
    `path[:lineno]:content` lines keep their shape — UNLESS a flag reshapes output
    (counts, path-only, no-filename, color, ...). Any unsafe/path-only flag disqualifies.
    """
    for token in stage[1:]:
        if token.startswith("--"):
            name = token.split("=", 1)[0]
            if name in _UNSAFE_LONG or name in _PATHONLY_LONG:
                return False
            if name in ("--color", "--colour"):
                value = token.split("=", 1)[1] if "=" in token else "auto"
                if value != "never":
                    return False
        elif token.startswith("-") and token != "-":
            if any(ch in _UNSAFE_SHORT or ch in _PATHONLY_SHORT for ch in token[1:]):
                return False
    return True


def _classify_pipeline(stages):
    """Return a reason if any stage after the source grep breaks grammar, else None.

    Every stage past stage 0 must keep grep's line grammar: a grammar-preserving
    filter (head/tail/cat/tee/sort) or a filter-grep. The first breaking stage wins.
    """
    if len(stages) == 1:
        return None
    for stage in stages[1:]:
        cmd = stage[0] if stage else ""
        if cmd in PRESERVING_LAST:
            continue
        if cmd == "grep" and _is_filter_grep(stage):
            continue
        if cmd in BREAKING_LAST or cmd == "grep":
            return f"pipe_breaks_grammar:{cmd}"
        return f"unknown_pipe_stage:{cmd}"
    return None


def _inspect_flags(grep_tokens, ctx):
    """Scan grep flags; return a passthrough reason on an unsafe flag, else None."""
    for token in grep_tokens[1:]:
        if token.startswith("--"):
            name = token.split("=", 1)[0]
            if name in _UNSAFE_LONG:
                return f"unsafe_flag:{name}"
            if name in ("--color", "--colour"):
                value = token.split("=", 1)[1] if "=" in token else "auto"
                if value != "never":
                    return f"unsafe_flag:{name}"
            if name in _PATHONLY_LONG:
                ctx["path_only"] = True
            if name in _RECURSIVE_LONG:
                ctx["recursive"] = True
            if name == "--line-number":
                ctx["has_n"] = True
        elif token.startswith("-") and token != "-":
            cluster = token[1:]
            unsafe = next((ch for ch in cluster if ch in _UNSAFE_SHORT), None)
            if unsafe is not None:
                return f"unsafe_flag:-{unsafe}"
            if any(ch in _PATHONLY_SHORT for ch in cluster):
                ctx["path_only"] = True
            if "n" in cluster:
                ctx["has_n"] = True
            if "r" in cluster or "R" in cluster:
                ctx["recursive"] = True
    return None


def decide(command):
    try:
        tokens = shlex.split(command)
    except ValueError:
        return Decision(False, "unparseable_command")
    if not tokens:
        return Decision(False, "empty_command")

    segments = _split_segments(tokens)
    if len(segments) > 1:
        grep_segments = [seg for seg in segments if seg[0] == "grep"]
        if len(grep_segments) != 1 or segments[-1][0] != "grep":
            return Decision(False, "compound_operator")
        if any(seg[0] not in _SILENT_LEADERS for seg in segments[:-1]):
            return Decision(False, "compound_operator")
        tokens = segments[-1]

    if (">" in tokens or ">>" in tokens) and "tee" not in tokens:
        return Decision(False, "redirected_to_file")

    stages = _split_stages(tokens)
    first = stages[0]
    if not first or first[0] != "grep":
        return Decision(False, "not_grep_first_stage")

    pipeline_reason = _classify_pipeline(stages)
    if pipeline_reason is not None:
        return Decision(False, pipeline_reason)

    last_cmd = stages[-1][0] if stages[-1] else "grep"
    ctx = {
        "recursive": False,
        "has_n": False,
        "path_only": False,
        "pipeline": len(stages) > 1,
        "last_stage": last_cmd,
    }
    flag_reason = _inspect_flags(first, ctx)
    if flag_reason is not None:
        return Decision(False, flag_reason)

    return Decision(True, "", ctx)
