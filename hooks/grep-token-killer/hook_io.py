"""Defensive PostToolUse input/output adapter.

Single responsibility: isolate the wire format in one place. Reads the stdin
JSON shape recorded in SCHEMA.md (`tool_input.command`, `tool_response.stdout`)
and builds the `updatedToolOutput` envelope by cloning `tool_response` and
replacing only `stdout`, so every field Bash's output schema requires survives.
Never raises on missing/odd keys; the caller treats a None parse as passthrough.
"""
from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Optional


@dataclass(frozen=True)
class HookInput:
    tool_name: str
    command: str
    stdout: str
    tool_response: dict
    out_of_band: bool


def _as_dict(value):
    return value if isinstance(value, dict) else {}


def _as_str(value):
    return value if isinstance(value, str) else ""


def parse_input(raw):
    """Parse stdin JSON into a HookInput, or None when it isn't usable."""
    try:
        data = json.loads(raw)
    except (ValueError, TypeError):
        return None
    if not isinstance(data, dict):
        return None

    tool_input = _as_dict(data.get("tool_input"))
    tool_response = _as_dict(data.get("tool_response"))
    stdout = _as_str(tool_response.get("stdout"))
    out_of_band = bool(
        tool_response.get("persistedOutputPath") or tool_response.get("rawOutputPath")
    ) and stdout == ""

    return HookInput(
        tool_name=_as_str(data.get("tool_name")),
        command=_as_str(tool_input.get("command")),
        stdout=stdout,
        tool_response=tool_response,
        out_of_band=out_of_band,
    )


def build_updated_output(tool_response, new_stdout):
    """Clone tool_response, replace only stdout, wrap in the PostToolUse envelope."""
    updated = dict(tool_response)
    updated["stdout"] = new_stdout
    return {
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "updatedToolOutput": updated,
        }
    }
