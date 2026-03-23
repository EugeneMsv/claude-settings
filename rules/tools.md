# Tools usage

## Required for Every Task:
- `mcp__sequentialthinking__sequentialthinking` - Break down tasks into steps 
- `Read` - Read file contents
- `Bash` - Run verification commands and tests

## Code Exploration Priority (MUST FOLLOW)
For any code navigation, symbol lookup, or codebase understanding task, use tools in this strict order:
1. **`LSP`** — FIRST choice for all code exploration: find definitions, references, symbols, hover docs, diagnostics
2. **`Grep`** — fallback when LSP is unavailable or task is text-pattern based (e.g., searching string literals)
3. **`Glob`** — fallback for file discovery by name/pattern only
4. **`Bash`** — last resort; never use for code search when the above tools suffice

Examples where LSP MUST be used instead of Grep/Glob:
- Finding where a class/function/method is defined → `LSP` (go-to-definition)
- Finding all usages of a symbol → `LSP` (find-references)
- Checking what a type/function signature looks like → `LSP` (hover)
- Listing all symbols in a file or project → `LSP` (document/workspace symbols)
- Checking for compile errors → `LSP` (diagnostics)

## Guidelines:
- Always prefer built-in tools like `Grep` `Glob` over `Bash`
- Prefer using `Edit` over `Write`
- Use `mcp__sequentialthinking__sequentialthinking` to plan complex tasks
- Use `mcp__context7__resolve-library-id` and `mcp__context7__get-library-docs` before generating/changing any code
- When using git CLI, use `git --no-pager <subcommand>` — global flag BEFORE subcommand once only; NEVER repeat `--no-pager` after the subcommand
- **Prefer simple commands over pipes**: When a single command accomplishes the goal, use it instead of piped alternatives. Example:
  prefer `git log -n 5 --stat` over `git log --format=%H -n 5 | xargs -I {} git show {} --stat`. Simpler commands are clearer, less
  error-prone, and may avoid unnecessary permission prompts.

## Research & Documentation:
- When configuring unfamiliar tools/services, read official documentation first
- Use `WebFetch` to retrieve official docs when unsure about configuration
- Don't guess at environment variables, config formats, or API structures
- If user provides documentation URL, read it before proceeding
- Prefer official sources over assumptions

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

### File Operations
- Use `Glob` tool for file search — not `find` in Bash
- NEVER use Bash heredoc (`cat > file << 'EOF'`) to write files — always use the `Write` tool

### General
- Use `python3` — `python` command not available on macOS

## Edit
- Re-read file before retrying when Edit fails with "File has been unexpectedly modified"

## Skill
- If Skill tool call fails with schema/parameter error, call `ToolSearch` with `query: "select:Skill"` first, then retry

## Agent
- subagent_type is case-sensitive; known valid values: `Explore`, `Plan`, `general-purpose`, `developer`, `deployer` — never use lowercase variants

## Glob
- NEVER glob with path at /Users, ~, or any path shallower than a project repo root — path must point inside a specific project dir (e.g., ~/dev/prj/org/repo/...); times out after 20s

## Read
- Grep before Read on any file whose size is uncertain; treat all .json files in .claude/ directories, OpenAPI specs, and generated files as potentially large — use offset+limit proactively rather than attempting full Read and failing
- Before reading any MEMORY.md, verify it exists with Glob — per-project paths under .claude/projects/*/memory/ are not auto-created

## WebFetch
- Don't guess raw file paths in GitLab repos — use glab or Glob to confirm file exists before constructing a raw URL
