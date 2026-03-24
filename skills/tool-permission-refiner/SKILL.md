---
name: tool-permission-refiner
description: This skill should be used when the user asks to "audit tool permissions", "refine permissions from log", "check what tools need permissions", "analyze tool usage permissions", "permission audit", "run tool-permission-refiner", "what tools are unmatched", "tighten permissions", or wants to derive permission rules from ~/.claude/tool-detector/log.jsonl into settings.json allow/ask/deny lists. Cross-references real tool usage data against all permission layers and applies security-first, principle-of-least-privilege suggestions.
version: 1.0.0
allowed-tools: Read, Grep, Glob, Edit
---

# Tool Permission Refiner

## Purpose

Analyze `~/.claude/tool-detector/log.jsonl` to find what tools and commands are actually used, cross-reference against all permission layers (user / local / project), and propose security-hardened changes to `allow`, `ask`, and `deny` arrays. Security-first: when in doubt, restrict.

## Target Files (in precedence order)

1. `~/.claude/settings.json` — user-level (primary target)
2. `~/.claude/settings.local.json` — local overrides
3. `.claude/settings.json` in CWD — project-level (if exists)

Precedence: `deny > ask > allow`, `project > local > user`. Suggestions go to the lowest (most specific) layer that makes sense.

## Core Workflow

### Phase 1: Parse Log

```bash
jq -r '[.timestamp, .tool, .command] | @tsv' ~/.claude/tool-detector/log.jsonl | sort
```

Group entries by:
- `tool` field (Bash, Read, Edit, Write, Glob, Grep, ToolSearch, LSP, Agent, etc.)
- For Bash: extract the leading sub-command token from `.command` (e.g. `git`, `gradle`, `jq`, `aws`)

Count occurrences per pattern. Every occurrence counts — unlike failure analysis, a single tool use is enough to warrant a permission review.

Build usage inventory: `{ tool, pattern, count, example_commands[] }`.

### Phase 2: Load All Permission Layers

Read each settings file and extract `permissions.allow`, `permissions.ask`, `permissions.deny`:

```bash
jq '.permissions' ~/.claude/settings.json
jq '.permissions' ~/.claude/settings.local.json 2>/dev/null
jq '.permissions' .claude/settings.json 2>/dev/null
```

Build a flat rule map with layer tags. For each log pattern, attempt glob-style match against all rules across all layers. Record: matched rule, layer, bucket (allow/ask/deny).

### Phase 3: Gap & Security Analysis

Classify each log pattern:

| Classification | Severity | Meaning |
|---|---|---|
| `ADD_TO_ALLOW` | 🟢 | Unmatched, safe read-only op — add to `allow` for convenience |
| `UNMATCHED` | 🟡 | Used but no rule — currently falls to `defaultMode`; needs explicit placement |
| `MOVE_TO_ASK` | 🟠 | Currently in `allow` but command can modify state, exec scripts, or call network |
| `MOVE_TO_DENY` | 🔴 | Touches credentials, secrets, keys, or is irreversibly destructive |
| `ALREADY_COVERED` | ⚪ | Matched by existing rule — skip (count only in summary) |
| `OVERLY_PERMISSIVE` | ⚠️ | Rule in `allow` that was never seen in log and has dangerous potential |

**Security classification rules (apply in this order):**

1. **`MOVE_TO_DENY`**: Bash commands touching `~/.aws`, `~/.ssh`, `*.key`, `*.pem`, `*.env`, secrets dirs; package publishing (`npm publish`, `pip upload`); force-push, hard-reset, `rm -rf`; privilege escalation (`sudo`, `su`).
2. **`MOVE_TO_ASK`**: Bash commands that install packages (`brew install`, `pip install`, `npm install`); deploy artifacts; exec into remote systems; write files outside `.claude/`; make network calls (`curl`, `wget`); run migrations; scale or apply to clusters.
3. **`ADD_TO_ALLOW`**: `Read`, `Glob`, `Grep` on non-sensitive paths; read-only `Bash` ops (git log, git status, git diff, git show, ls, jq, head, tail); `LSP`; `mcp__*` tools (read-only MCP calls).
4. **`UNMATCHED`** (no clear category): flag for user decision with a recommendation.
5. **`OVERLY_PERMISSIVE`**: scan `allow[]` for rules that: (a) have no matching log entry in recent history AND (b) match patterns known to be dangerous (file write, exec, network, package management).

### Phase 4: Present and Apply

Present suggestions grouped by severity: `MOVE_TO_DENY` first, then `MOVE_TO_ASK`, then `UNMATCHED`, then `ADD_TO_ALLOW`, then `OVERLY_PERMISSIVE`.

**Output format:**

```
=== TOOL PERMISSION REFINER REPORT ===

Scanned: N log entries | N unique patterns | N already covered (⚪)

--- SUGGESTIONS ---

1. 🔴 MOVE_TO_DENY  [user ~/.claude/settings.json]
   Pattern:   "Bash(some-command *)"
   Seen:      3 times — e.g. "some-command ~/.aws/credentials"
   Rationale: Accesses credential files; irreversible risk
   Action:    Remove from allow[] → add to deny[]

2. 🟠 MOVE_TO_ASK  [user ~/.claude/settings.json]
   Pattern:   "Bash(npm run *)"
   Seen:      5 times — e.g. "npm run build", "npm run deploy"
   Rationale: Can execute arbitrary scripts including deploy hooks
   Action:    Remove from allow[] → add to ask[]

3. 🟡 UNMATCHED — recommend ask  [user ~/.claude/settings.json]
   Pattern:   "Bash(python3 *)"
   Seen:      8 times — e.g. "python3 script.py", "python3 -c ..."
   Rationale: No rule; falls to defaultMode; can execute arbitrary code
   Action:    Add to ask[]

4. 🟢 ADD_TO_ALLOW  [user ~/.claude/settings.json]
   Pattern:   "Bash(git --no-pager *)"
   Seen:      12 times — e.g. "git --no-pager log", "git --no-pager diff"
   Rationale: Read-only git operation; currently unmatched; safe to auto-allow
   Action:    Add to allow[]

5. ⚠️ OVERLY_PERMISSIVE  [user ~/.claude/settings.json]
   Pattern:   "Bash(sed *)"  (in allow[])
   Seen:      0 times in log
   Rationale: Never used; `sed` with -i can silently overwrite files (already denied via sed -i*, but base pattern is broad)
   Action:    Consider narrowing or moving to ask[]

--- ALREADY COVERED: N patterns ⚪ ---
Bash(git log *), Bash(git * status), Read(**/*.md), Glob, Grep, LSP ...

Apply which suggestions? Enter numbers (e.g. 1,3,4), "all", or "none"
```

After user selects:
1. Apply all approved changes to the correct settings file using `Edit` tool
2. All changes to the same file in a single atomic `Edit` call
3. Maintain JSON validity — preserve formatting style of the existing file
4. Confirm applied changes with a brief summary

## Validation Checklist

Before presenting suggestions:
- ✓ Pattern backed by actual log entry (or explicitly flagged as zero-occurrence for OVERLY_PERMISSIVE)
- ✓ Proposed rule does not duplicate an existing rule verbatim or semantically
- ✓ `deny` takes precedence — never suggest adding to `allow` a pattern already in `deny`
- ✓ Security-first: when classification is ambiguous, prefer the more restrictive bucket
- ✓ Show both old and new state for MOVE_TO_* suggestions
- ✓ Each suggestion includes the target layer (user/local/project)
- ✓ Applied JSON remains valid — run `jq . <file>` mentally before editing
