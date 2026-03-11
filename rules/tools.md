# Tools usage

## Required for Every Task:
- `mcp__sequentialthinking__sequentialthinking` - Break down tasks into steps 
- `Read` - Read file contents
- `Bash` - Run verification commands and tests

## Guidelines:
- Always prefer built-in tools like `Grep` `Glob` over `Bash`
- Always prefer `LSP` over `Grep`, `Glob`, `Search`
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
- Stash unstaged changes before `git pull --rebase`, pop after
- Stash unstaged changes before `git checkout <branch>`, pop after
- Push with `git push origin $(git branch --show-current)` — avoids macOS case-mismatch on branch names

### gh / glab
- NEVER use `gh` on GitLab repos — use `glab` instead (`glab mr create`, `glab mr list`, etc.)
- Use `--opened`, `--closed`, `--merged`, or `--all` for `glab mr list` filtering (no `--state` flag)
- Include `--fill` with `glab mr create` in non-interactive mode
- NEVER use `glab ci view` non-interactively — requires TTY; use `glab ci get <id>` instead
- Use single quotes for `glab api` URL arguments — double quotes cause Python escape errors on special chars (`\!`, etc.)

### File Operations
- Use `Glob` tool for file search — not `find` in Bash

### General
- Use `python3` — `python` command not available on macOS

## Edit
- Re-read file before retrying when Edit fails with "File has been unexpectedly modified"

## Glob
- NEVER glob with path at /Users or home root — always specify a project subdirectory; times out after 20s

## Read
- Use Grep for targeted search before attempting Read on unknown-size files; use offset+limit only when file is >256KB or >25k tokens — never Read entire log/output dump files
