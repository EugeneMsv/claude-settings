# Git Workflow
Always MUST:
- Use Bash for Git operations and verification
- Start every task: checkout main, pull latest, create a feature branch BEFORE any file edits. Never edit on main/master.
- Run project code formatting/linting before each `git add` command
- Run ALL tests (full suite, not just feature-specific) before `git add` — NEVER commit before tests pass
- One commit per task
- Only commit files relevant/changed to current task
- Use format: Task N: <description>
- Never combine multiple tasks in one commit
- NEVER chain git operations — run each command independently and verify result before proceeding (includes `add && commit`, `commit && push`, `stash && pull && pop && push`)
- To revert a committed file on a pushed branch: `git checkout HEAD~1 -- <file>`, then new commit (never amend pushed commits)
- Git worktrees MUST NEVER be created in `.claude` - they MUST ALWAYS be created one folder above the current directory
  When creating worktrees for code review, use pattern: `../{repository-name}-{purpose}-{git-ref-or-branch-name}`
  Example: `git worktree add ../my-repo-review-story-PROJ-16360 origin/story/PROJ-16360`


## Post-Push MR Workflow
After pushing a branch:
1. Find MR: `glab mr list --source-branch <branch>`
2. Assign: `glab mr update <id> --assignee <username>`
3. Update title if needed: `glab mr update <id> --title "PROJ-XXXXX: <description>"`

## Local Infrastructure
Start the stack autonomously using project CLAUDE.md steps. Non-destructive start/build/run only; stop and ask when a required choice is ambiguous (port, profile, missing config) or a step is destructive (data wipe, port-kill, container prune).

## Glab MR Review workflow
When user asks to review MR comments:
1. Check current branch: `git branch --show-current` and ask user if this is the branch or not
2. Find MR: `glab mr list --source-branch <branch-name>`
3. Read comments: `glab mr view <mr-number> --comments`
4. Provide comments to user and ask which ones we need to address
5. Address comments one at a time:
  - Make code changes
  - Run tests
  - Commit with reference to reviewer: "Addresses review comment from <reviewer>"
