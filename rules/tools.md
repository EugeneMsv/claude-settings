# Tools usage

## Required for Every Task:
- `mcp__sequentialthinking__sequentialthinking` - Break down tasks into steps (use when 2+ files or 3+ steps; skip for single-edit/command/question)
- `Read` - Read file contents
- `Bash` - Run verification commands and tests

## Code Exploration Priority (MUST FOLLOW)
For any code navigation, symbol lookup, or codebase understanding task, use tools in this strict order:
1. **`bazel query`** (via Bash) — FIRST for target ownership, reverse-dep impact, and test discovery. Answers "which target owns this file?", "what tests cover this?", "what breaks if I change this?" The build graph is authoritative; the filesystem is not.
2. **`Grep`** — symbol/string content search (definitions, references, string literals)
3. **`Glob`** — file discovery by name/pattern only
4. **`Bash`** — last resort; never use for code search when the above tools suffice

## Debugging discipline
- When you can name a likely root cause, VERIFY that first before trying generic/destructive fixes (cache wipes, restarts). Cheapest diagnostic that discriminates causes wins. Don't pursue a fix path after evidence contradicts it.
- Reproduce the user's exact invocation (same script, same args, no added flags) before declaring a component verified — isolation tests that supply args the real caller omits prove nothing.
- Say "verified in isolation" vs "verified end-to-end" explicitly — never let a component-level pass stand in for a full-path claim.

## Guidelines:
- Always prefer built-in tools like `Grep` `Glob` over `Bash`
- Prefer using `Edit` over `Write`
- Use `mcp__context7__resolve-library-id` and `mcp__context7__get-library-docs` before generating/changing any code
- When using git CLI, use `git --no-pager <subcommand>` — global flag BEFORE subcommand once only; NEVER repeat `--no-pager` after the subcommand
- Prefer a single command over piped alternatives when it accomplishes the goal

## Research & Documentation:
- For unfamiliar tools/config: read official docs first (WebFetch); never guess env vars, config formats, or API structures. Read any user-provided doc URL before proceeding.

## Atlassian (Confluence/Jira):
- Never `WebFetch` a Confluence URL (incl. `/wiki/x/` tiny-links) — it 302s to `id.atlassian.com` login. Use `mcp__atlassian__search` by page title, then `getConfluencePage`. If the MCP tools appear absent, they likely need re-auth: ask the user to run `/mcp` rather than routing the task through a subagent.
- Repo code is the source of truth; Atlassian is secondary — on conflict, trust code and flag the doc stale
- Prefer Rovo (`mcp__atlassian__search`) over CQL/JQL. Rovo is unreliable — run TWO parallel calls for the same search: one as a short natural-language phrase ("<component> feature resolution"), one as raw keywords ("<component> feature lookup"). Merge results — rank intersection (appears in both calls) first, then phrase-only, then keyword-only. Fall back to CQL/JQL only for exact field filtering (project, status, date range, assignee).
- If your workspace has a default team/org scope suffix that improves search relevance, append it to every query call unless the user explicitly says otherwise.
- After merging, call `getConfluencePage` on the top 2–3 results before forming conclusions — excerpts alone don't verify claims. If a page's last-modified date is older than 1 year, flag it as potentially stale and cross-check against the repo before citing.
- If both Rovo calls return fewer than 2 useful hits, retry using known team/system aliases (if your workspace maintains such a list) before falling back to CQL.
- Narrow JQL before retrying a broad query (e.g. `assignee IN (...)` with multiple IDs) — `searchJiraIssuesUsingJql`/`search` can hang 300s+ instead of erroring on slow/broad JQL.
- Cross-check every claim across multiple sources (pages, Jira, repo); never rely on one page
- Cite each Confluence source with a link + reliability estimate (page freshness vs. today, # corroborating sources)
- `searchConfluenceUsingCql` requires `cloudId` (site host, e.g. `<your-site>.atlassian.net`)
- `getConfluencePage` `pageId` = numeric or /wiki/x/ tiny-link id (400 = wrong form, 404 = wrong id)

## MCP
- `mcp__sequentialthinking__sequentialthinking`: `thoughtNumber`/`totalThoughts` must be numbers and `nextThoughtNeeded` a boolean — never strings

## Execution:
- Run independent tools in parallel when possible
- Use sequential execution when tools depend on previous results
- Never use placeholders or guess missing parameters

## Bash

### Git
- On non-fast-forward rejection, run `git pull --rebase` then push once — do not retry bare push
- When `git pull` or `git pull --rebase` fails with "no tracking information", use `git pull --rebase origin $(git branch --show-current)` explicitly
- Before `git worktree add <path> <branch>`, run `git worktree list` to confirm the branch isn't already checked out
- Stash unstaged changes before `git pull --rebase`, pop after
- Stash unstaged changes before `git checkout <branch>`, pop after
- Push with `git push origin $(git branch --show-current)` — avoids macOS case-mismatch on branch names
- Run git add, commit, push as separate commands — chaining with && hides push failures after commits and leaves branch in mixed state
- Before git checkout -b <branch>, run git branch --list <branch>; if it exists, ask the user what to do (may be stale or in-progress work)

### gh
- NEVER use `gh` on GitLab repos — use `glab` instead

### glab
- Use `--opened`, `--closed`, `--merged`, or `--all` for `glab mr list` filtering (no `--state` flag)
- Include `--fill` with `glab mr create` in non-interactive mode
- NEVER use `glab ci view` non-interactively — requires TTY; use `glab ci status` (pipeline status) or `glab ci get <id>` (pipeline details)
- Use single quotes for `glab api` URL arguments — double quotes cause Python escape errors on special chars (`\!`, etc.)
- In `python3 -c` inline scripts, don't use `\!` — Python 3.12+ rejects it as invalid escape; use `!` unescaped in f-strings or write script to a temp file for complex cases
- Assign MR: `glab mr update <id> --assignee <username>`
- Update MR title: `glab mr update <id> --title "..."`
- Get current username: `glab api user | python3 -c "import sys,json; print(json.load(sys.stdin)['username'])"`

### Bazel
- Prefer `bazel query` over `find`/Grep for target ownership, dep traversal, and test discovery
- Never query `//...` without `--keep_going` — monorepo has broken packages that abort the query
- Add `--notool_deps --noimplicit_deps` to any `deps()`/`rdeps()` call to suppress toolchain noise
- `kind(test, rdeps(...))` is the canonical way to find tests for a changed target — don't guess paths

### File Operations
- Use `Glob` for filename search and `Grep` for code content — never `find` or `find | xargs grep` in Bash. `find | xargs grep` fails silently (exit 1, no output) whenever `find` returns 0 files
- NEVER use Bash heredoc (`cat > file << 'EOF'`) to write files — always use the `Write` tool

### Timeout
- Default Bash timeout is 120s — pass an explicit `timeout` (ms, max 600000) for `sleep`, repo-wide `git log -S`, bazel, and gcloud calls
- Never `sleep` ≥110s without raising `timeout` — it always dies before the command returns

### MySQL
- Always check schema first (`SHOW TABLES`, `DESCRIBE <table>`) before writing a query against an unfamiliar table
- Every SELECT (including subselects) MUST have a `LIMIT`, default 20 if the user doesn't specify one — never run an unbounded SELECT
- Unfiltered `SELECT COUNT(*) FROM <table>` (no WHERE) is fine any time — cheap, reads table metadata/index. A `COUNT(*) ... WHERE ...` is a full filtered scan, same cost as the real query — don't run it "to check first," just add `LIMIT` to the real query instead
- Use `--login-path=<name>` (via `mysql_config_editor`) — never pass host/user/password inline; credentials must never appear in a command
- Never use a prod login-path (e.g. `*-prod`/`*-prd`) without first asking and explaining why — dev/qa login-paths are fine to use freely

### Trino
- Use `mcp__trino__execute_query` (MCP tool), never the `trino` CLI
- Always check schema first (`mcp__trino__get_table_schema` / `SHOW TABLES` / `DESCRIBE <table>`) before writing a query against an unfamiliar table
- Every SELECT (including subselects) MUST have a `LIMIT`, default 10 if the user doesn't specify one — never run an unbounded SELECT
- Unlike MySQL, `SELECT COUNT(*)` (filtered or not) is NOT exempt from this — Trino/Hive is a distributed engine, so an unfiltered count still triggers a full distributed scan and can slow the cluster; never run it "to check first"

### General
- Use `python3` — `python` command not available on macOS
- `claude mcp add` requires positional args in order: `claude mcp add <name> <commandOrUrl> [flags]` — flags like --transport must follow both
- NEVER `pip3 install <pkg>` ad hoc — macOS Python is externally-managed and blocks it (with or without `--user`); check for a Homebrew/system alternative or ask the user instead

## Edit
- Re-read the file before retrying when Edit fails with "File content has changed since it was last read" — usually a linter/formatter rewrote it via Bash

## Skill
- If Skill tool call fails with schema/parameter error, call `ToolSearch` with `query: "select:Skill"` first, then retry

## Agent
- subagent_type is case-sensitive; known valid values: `Explore`, `Plan`, `general-purpose`, `developer`, `deployer`, `deep-researcher` — never use lowercase variants
- In an active back-and-forth (user says "let's go step by step", is iterating on a design, or is challenging a claim), do the investigation yourself with Read/Grep/bazel query — do NOT spawn a subagent. Delegation breaks the dialogue and loses the shared context the user is building.
- `deep-researcher` — deep+broad investigation subagent (code/docs/web/APIs/MCPs); read-only toward the world, writes only to its own `~/.claude/agent-memory/deep-researcher/` (so it compounds source maps and dead ends across runs); single-context by design — does not spawn agents. Output is dense freeform intelligence for a calling agent, not a human: claims table with 🟢/🟡/🔴 trust tiers, falsification results, gaps. Give it what/where/how-deep.

### Choosing an investigation agent (Explore vs deep-researcher vs general-purpose)
Axis = breadth × depth × whether it must act. Prefer the read-only pair over `general-purpose` for pure investigation (least privilege).

| Agent | Use when | Depth | Read-only? | Can spawn? |
|-------|----------|-------|-----------|-----------|
| `Explore` | Locate files/symbols/patterns; you want the conclusion, not file dumps | shallow (excerpts) | yes | no |
| `deep-researcher` | Understand *how/why* something works end-to-end; map terrain then dig to mechanism | deep (full source/pages/APIs) | yes, except own memory dir | no |
| `general-purpose` | Multi-step task mixing search + action, or open-ended "find X" where match confidence is low and needs iteration | varies | no | yes (full tools) |

Tie-breakers:
- "Where is X / which files / does pattern Y exist" → **Explore**.
- "How does X work / trace the flow / gather everything about X" → **deep-researcher**.
- Must *edit, run, or chain* actions after searching → **general-purpose** (only one of the three that can write/spawn).
- For a single direct lookup in a known/specific file (e.g. confirming one method's line number), `Read`/grep directly — do not spawn any agent.

## Glob
- NEVER glob with path at /Users, ~, or any path shallower than a project repo root — path must point inside a specific project dir (e.g., ~/dev/prj/org/repo/...); times out after 20s

## Read
- Never full-Read .html, .csv, .xml, or any dumped tool/MCP output (`.claude/**/*.txt`, `tool-results`) — always Grep or offset+limit. Applies to source/.json/generated files too; limit is 25000 tokens / 256KB
- Run Glob or `ls` before Read — directory paths error EISDIR. Highest-risk: `.claude/<skill>/` artifact folders and `tool-results` are directories, not files
- Confirm inferred paths with Glob before Read. Two dominant failure modes: (a) extension guesses (.yaml vs .yml, BUILD vs .bazel, README.md vs README), (b) constructed Java package/class paths — locate the class with Grep, never assemble the path from the package name
- Before reading any MEMORY.md, run Glob first to confirm it exists — NOT optional. Per-project paths under .claude/projects/*/memory/ are not auto-created

## WebFetch
- Don't guess raw file paths in GitLab repos — use glab or Glob to confirm file exists before constructing a raw URL
- On 403 or 404, switch to WebSearch to find the correct accessible URL — don't retry WebFetch on the same guessed URL
- "unable to fetch from <host>" means the domain is blocked outright — switch to WebSearch immediately, never retry the URL
