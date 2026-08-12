#!/usr/bin/env python3
import json
import sys

json.load(sys.stdin)  # consume required stdin

context = (
    "**[HARD GATE]** For every Bash command that requires a permission approval, "
    "you MUST write exactly two numbered sentences immediately before the command block:\n"
    "1. Plain: what it does in plain terms (no jargon)\n"
    "2. Technical: what the command does in concise, straight language — name each flag and path by what it controls; never repeat the raw command\n"
    "You MUST NOT submit the command for approval without both sentences present."
)

print(json.dumps({
    "hookSpecificOutput": {"hookEventName": "UserPromptSubmit"},
    "additionalContext": context,
    "systemMessage": "[User prompt hook] Two-sentence gate applied.",
}))
