# agent-scope-control

A Claude Code **PreToolUse** hook (`Read|Grep|Glob|Bash`) that lets any folder, in
any project, opt out of being read by the model — without hardcoding folder paths
into the hook itself.

## Table of Contents

- [How it works](#how-it-works)
- [`.agent` file format](#agent-file-format)
- [Registration](#registration)
- [Manual verification](#manual-verification)
- [Limitations](#limitations)

Drop a `.agent` file into a folder containing:

```
read-allowed=false
```

and every `Read`, `Grep`, `Glob`, or `Bash` call that touches that folder (or
anything under it) is denied. Set `read-allowed=true` (or delete the `.agent`
file) to re-allow.

## How it works

1. **Collect path candidates** from the tool call:
   - `Read`/`Grep`/`Glob`: `tool_input.file_path` / `.path` / `.pattern`. Any glob
     wildcard suffix (`*`, `?`, `[`) is stripped to get a concrete directory.
   - `Bash`: `tool_input.command` is split on whitespace; any token containing `/`
     or starting with `.` is treated as a path candidate. This is best-effort —
     unpathed `grep -r`, obfuscated/encoded paths, and `~`-expansion are not
     detected (same accepted limitation as the hook this replaced).
2. **Walk up** from each candidate's directory to `$CLAUDE_PROJECT_DIR`
   (inclusive), checking for a `.agent` file at every level.
3. **Strict deny-wins:** if *any* `.agent` file in that chain has
   `read-allowed=false`, the call is denied — even if a folder closer to the
   target path says `read-allowed=true`. A nested `true` can never re-open a
   subtree an ancestor closed. Missing `.agent` file, or one without a
   `read-allowed` line, defaults to allow at that level.
4. On deny, the `permissionDecisionReason` fed back to the model:
   - names the specific denying folder and its `.agent` file,
   - instructs the model not to retry reading that folder again this session
     unless the user explicitly asks again,
   - tells it to treat any content from that folder already seen via another
     path as stale/untrusted, not authoritative.

Missing/malformed input, or no path candidates found at all (e.g. `git status`),
exits `0` silently — same fail-open behavior as any well-behaved PreToolUse gate.

## `.agent` file format

Plain `key=value` lines (not JSON/YAML), one property per line:

```
read-allowed=false
```

Only `read-allowed` is read today. The format is deliberately extensible — future
properties can be added to the same file without changing existing folders.

## Registration

In `~/.claude/settings.json` under `hooks`:

```json
"PreToolUse": [
  {
    "matcher": "Read|Grep|Glob|Bash",
    "hooks": [
      {
        "type": "command",
        "command": "~/.claude/hooks/agent-scope-control/hook.sh",
        "statusMessage": "Checking agent scope control"
      }
    ]
  }
]
```

Registered **globally** (not per-project) so the same `.agent`-file convention
works in every repo, not just one. Claude Code snapshots hooks at startup, so a
session restart is required after editing settings.

## Manual verification

No automated test harness covers `.claude/hooks/*.sh` (no Bazel target owns it,
`shellcheck` isn't installed). Verify by hand against a temp fixture tree:

```bash
mkdir -p /tmp/agent-scope-test/parent/child
printf 'read-allowed=false\n' > /tmp/agent-scope-test/parent/.agent
printf 'read-allowed=true\n'  > /tmp/agent-scope-test/parent/child/.agent
echo "secret" > /tmp/agent-scope-test/parent/child/file.md

# Strict deny-wins: parent=false, child=true -> still DENY
echo '{"tool_input":{"file_path":"/tmp/agent-scope-test/parent/child/file.md"}}' \
  | CLAUDE_PROJECT_DIR="/tmp/agent-scope-test" ~/.claude/hooks/agent-scope-control/hook.sh

# Unrelated path -> allowed (no output)
echo '{"tool_input":{"file_path":"/tmp/agent-scope-test/other.md"}}' \
  | CLAUDE_PROJECT_DIR="/tmp/agent-scope-test" ~/.claude/hooks/agent-scope-control/hook.sh

# Bash tokenized detection -> DENY
echo '{"tool_input":{"command":"cat parent/child/file.md"}}' \
  | CLAUDE_PROJECT_DIR="/tmp/agent-scope-test" ~/.claude/hooks/agent-scope-control/hook.sh

rm -r /tmp/agent-scope-test
```

## Limitations

This is a best-effort text-matching gate, not an OS-level permission lockdown —
same scope the prior relative-path fix already accepted.

- **Bash path detection is incomplete.** Only whitespace-separated tokens
  containing `/` or starting with `.` are checked. Misses: unpathed recursive
  commands (`grep -r secret .`), paths built via variable/command substitution
  (`cat "$DIR/file.md"`), `~`-expansion (`cat ~/knowledge/foo.md`),
  obfuscated/encoded paths, and pipelines where the denied folder never appears
  as a literal token (e.g. `ls .claude | while read f; do cat "$f"; done`).
- **No symlink resolution.** A symlink candidate is checked against its own
  ancestor chain, not the resolved target's — a symlink into a denied folder can
  bypass the gate.
- **Glob wildcard stripping is heuristic.** Cuts at the first `*`, `?`, or `[`;
  unusual syntax (brace expansion, a non-glob `*`/`[` in a path segment) can
  resolve to the wrong directory.
- **Only covers Read/Grep/Glob/Bash.** Edit/Write/NotebookEdit aren't gated here
  (see `block-generated-files.sh` for that scope), so a denied folder can still
  be written, just not read back through these four tools. Other MCP tools
  (e.g. a filesystem MCP server) aren't covered at all.
- **Fail-open by default.** A missing `.agent` file, or one without a
  `read-allowed` line, defaults to allow. There's no way to default-deny a
  subtree without an explicit `.agent` file.
- **The session no-retry instruction is advisory, not enforced.** It's a prompt
  to the model in the deny reason, not a hard block — if ignored, the hook just
  denies again on the next attempt.
- **No cap on candidate count.** A Bash command with many `/`-containing tokens
  triggers one ancestor walk per token; not an issue at normal command lengths,
  but there's no explicit limit.
