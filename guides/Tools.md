# Tools usage

## Required for Every Task:
- `mcp__sequentialthinking__sequentialthinking` - Break down tasks into steps 
- `Read` - Read file contents
- `Bash` - Run verification commands and tests

## Guidelines:
- Always prefer built-in tools like `Grep` `Glob` over `Bash`
- Prefer using `Edit` over `Write`
- Use `mcp__sequentialthinking__sequentialthinking` to plan complex tasks
- Use `mcp__context7__resolve-library-id` and `mcp__context7__get-library-docs` before generating/changing any code
- When using git CLI, use `git --no-pager <subcommand>` for clean output (global flag goes BEFORE subcommand, e.g. `git --no-pager log`)
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
- NEVER retry git push after non-fast-forward rejection — run `git pull --rebase` first, then push
- NEVER run `git pull --rebase` with unstaged changes present — stash first, rebase, then stash pop

### gh / glab
- NEVER use `gh` on GitLab repos — use `glab` instead (`glab mr create`, `glab mr list`, etc.)

## Read
- NEVER Read files >256KB without offset+limit params — use Grep to search or read specific portions
