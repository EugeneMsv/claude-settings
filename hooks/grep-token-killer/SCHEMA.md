# PostToolUse hook schema — empirical findings

Resolved authoritatively from the compiled `claude` binary v2.1.176
(`/opt/homebrew/bin/claude`) by extracting the embedded zod schemas with
`strings`/`grep -aoE`. This supersedes the official docs, which incorrectly
name the result key `tool_output`.

## Input (stdin JSON) — PostToolUse

```jsonc
{
  "session_id": "...",
  "transcript_path": "...",
  "cwd": "...",
  "permission_mode": "default",
  "hook_event_name": "PostToolUse",
  "tool_name": "Bash",
  "tool_input":   { "command": "grep -rn X dir", ... },   // k.unknown()
  "tool_response":{ "stdout": "...", "stderr": "...",      // k.unknown() -> Bash output object
                    "interrupted": false, ... },
  "tool_use_id": "...",
  "duration_ms": 123
}
```

- **Result key is `tool_response`** (an object), NOT `tool_output`.
- The command lives at `tool_input.command`.
- stdout lives at **`tool_response.stdout`** (string).
- For a piped command, `tool_response.stdout` is the **final shell stdout of the
  whole pipeline** (Bash executes the entire command string), e.g. for
  `grep ... | head -10` it is head's output, not grep's.

## Bash tool output schema (what `updatedToolOutput` is validated against)

```
stdout: string (required)
stderr: string (required)
interrupted: boolean (required)
returnCodeInterpretation: string (optional)
isImage: boolean (optional)
persistedOutputPath: string (optional)
rawOutputPath: string (optional)
backgroundTaskId: string (optional)
```

The hook engine runs `H.outputSchema.safeParse(updatedToolOutput)`; on failure it
**discards** the rewrite and logs `PostToolUse hook returned updatedToolOutput that
does not match Bash's output shape`. Therefore the safe construction is to
**shallow-copy the original `tool_response` and replace only `stdout`** — every
required field is preserved by construction.

## Output (stdout JSON, exit 0)

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "updatedToolOutput": { "...clone of tool_response with stdout replaced..." }
  }
}
```

- `updatedToolOutput` — `k.unknown().optional()`, "Replaces the tool output before
  it is sent to the model". Works for all tools.
- `updatedMCPToolOutput` — MCP tools only; not used here.
- `additionalContext` — `k.string().optional()`; not used (silent operation).
- Emit nothing (or `{}`) to pass the original output through untouched.
- `systemMessage` — top-level `k.string().optional()`; shown to the user (not the
  model). Emitted alongside `updatedToolOutput` to report the saved percentage.

## Large-output caveat

When stdout is large Claude Code may persist it out-of-band and set
`persistedOutputPath`/`rawOutputPath`. If `tool_response.stdout` looks truncated
or empty while such a path is present, **passthrough** — we cannot safely compact
a body we do not fully hold.

## Mid-session reload caveat

Claude Code snapshots hooks at startup. Editing `~/.claude/settings.json`
mid-session does NOT activate the hook until a session restart or `/hooks`
re-approval. In-session verification therefore pipes fixture JSON straight into
`hook.py` (identical code path); true live smoke requires a restart.
