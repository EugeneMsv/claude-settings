# Statusline

## Problem

Claude Code's `statusLine.command` gets one JSON blob on stdin per render and must
print plain text (with ANSI escapes) back to stdout in well under a second — it
runs on every prompt. Cramming git status, MCP health, Docker state, auto-memory
stats, and Anthropic rate limits into one monolithic script made it slow to reason
about and impossible to unit test: every code path touched real git repos, the
real `~/.claude.json`, the real Docker daemon, and the real network.

It also hid a real correctness bug: `claude mcp list` health-checks *every*
server configured in `.mcp.json`, including ones a project has explicitly
disabled via `disabledMcpServers` in `~/.claude.json`. A disabled server still
reports "✔ Connected" — so the statusline was overcounting connected MCP
servers for projects that disable some of them.

## Solution

Split the monolith into one script per concern. Each script:

- takes plain positional args (no reliance on global shell state)
- reads/writes its own cache file under `<cache_base>/`
- prints a single-line TSV to stdout, nothing else
- has no dependency on the others

`statusline.sh` is now a thin orchestrator: it parses the session JSON once,
calls each script, and only handles ANSI coloring/formatting of their output.

| Script | Resolves |
|---|---|
| `git-status.sh` | branch, insertions/deletions, unstaged count, ahead/behind, commits |
| `mcp-status.sh` | MCP server count/connected/failed, **filtered by this project's `disabledMcpServers`** |
| `docker-status.sh` | the Docker Compose project (if any) running under this repo |
| `memory-status.sh` | auto-memory entry count/lines/newest-edit for this project |
| `usage-status.sh` | Anthropic 5h/7d rate-limit utilization via OAuth (skipped when `ANTHROPIC_BASE_URL` points at a non-Anthropic endpoint) |
| `cache-prune.sh` | deletes cache files untouched for ≥1 day, once/day, lock-guarded |

### Why `mcp-status.sh` retries the `~/.claude.json` read

`~/.claude.json` is rewritten frequently by Claude Code itself (session
bookkeeping) — often several times a minute. If `mcp-status.sh` reads it at
the exact moment of a write, `jq` can see a truncated file and fail to parse.
Silently treating that as "nothing is disabled" would overcount connected
servers and — worse — cache that wrong answer for two minutes (`cache_max`).

So the script retries the read up to 8 times with a short backoff. If every
attempt still fails, it does **not** write a new cache entry — it falls back
to the previous cache file if one exists, or zeroed counts otherwise, and
lets the next render try again fresh. A bad read never freezes the status
line for the full cache TTL.

## Example: input

Claude Code pipes one JSON object per render on stdin:

```json
{
  "cwd": "/Users/you/dev/myrepo",
  "model": { "display_name": "Sonnet" },
  "session_id": "6faec320-cee4-472a-94bd-0534a3671f08",
  "version": "2.1.0",
  "effort": { "level": "medium" },
  "context_window": {
    "used_percentage": 12,
    "context_window_size": 200000,
    "total_input_tokens": 5000,
    "total_output_tokens": 1000
  },
  "workspace": { "added_dirs": [] }
}
```

## Example: output

```
~/dev/myrepo | main | edits +12 -3 | !2 | ↑1 | commits=3
Sonnet [medium] log | ctx 12% / 200k | in:5k out:1k | 5h 22%  7d 8% | v2.1.0
🧠 on · 4 files 61 lines · 17d ago | 📁 1 | 🔌 3 | 🐳 myproj 2h healthy(2)
```

- **Line 1**: cwd, git branch, working-tree diff stats, ahead/behind upstream, commits vs base.
- **Line 2**: model + effort + transcript link, context window usage, session token I/O,
  5h/7d Anthropic rate-limit utilization, Claude Code version.
- **Line 3**: auto-memory stats, `/add-dir` count, MCP server health
  (`🔌 N` all connected, or `🔌 connected/total ⚠ names` when some are down —
  disabled servers are excluded from both numbers), Docker Compose status for
  a project under this repo.

## Testing

Tests use [bats-core](https://github.com/bats-core/bats-core)
(`brew install bats-core`). Each script gets its own `.bats` file under
`tests/`, plus a shared `tests/test_helper.bash` with two isolation helpers:

- `setup_fake_home` / `teardown_fake_home` — points `$HOME` at a throwaway temp
  dir so tests never read/write your real `~/.claude.json`,
  `~/.claude/settings.json`, or `~/.claude/.credentials.json`.
- `setup_fake_bin` / `teardown_fake_bin` + `write_stub <name> <body>` —
  prepends a temp dir to `$PATH` so tests can stub `claude`, `docker`,
  `security`, and `jq` itself without touching the real binaries or network.

Run the whole suite:

```bash
cd ~/.claude/statusline/tests
bats .
```

Run one file, or one test by name:

```bash
bats git-status.bats
bats mcp-status.bats -f "disabled servers are excluded"
```

39 tests as of this writing, covering the happy path, cache-hit behavior
(a second call must not re-invoke `claude`/`docker`/`curl`), and the edge
cases that actually broke in practice — e.g. `mcp-status.bats` has a
dedicated test that stubs `jq` to fail twice then succeed, proving the
`~/.claude.json` race is handled, and another proving a *persistent* failure
falls back safely instead of caching a guess.
