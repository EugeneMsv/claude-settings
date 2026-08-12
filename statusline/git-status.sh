#!/bin/bash
# git-status.sh — resolve git working-tree status for the statusline's line 1.
#
# Usage: git-status.sh <cwd>
# Output (TSV): <branch> <ins> <del> <unstaged> <ahead> <behind> <commits>
# Empty <branch> means cwd is not inside a git repo — caller should skip line 1 git segments.

cwd="$1"
[[ -z "$cwd" ]] && { printf '\t0\t0\t0\t0\t0\t0\n'; exit 0; }

if ! git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
  printf '\t0\t0\t0\t0\t0\t0\n'
  exit 0
fi

branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)

stats=$(git -C "$cwd" diff HEAD --shortstat 2>/dev/null)
ins=$(printf '%s' "$stats" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+')
del=$(printf '%s' "$stats" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+')

unstaged=$(git -C "$cwd" diff --name-only 2>/dev/null | wc -l | tr -d ' ')

ahead=$(git -C "$cwd" rev-list --count "HEAD@{upstream}..HEAD" 2>/dev/null)
behind=$(git -C "$cwd" rev-list --count "HEAD..HEAD@{upstream}" 2>/dev/null)

base=$(git -C "$cwd" rev-parse --abbrev-ref origin/HEAD 2>/dev/null | sed 's|origin/||')
commits=$(git -C "$cwd" rev-list --count "${base:-main}..HEAD" 2>/dev/null)

printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$branch" "${ins:-0}" "${del:-0}" "${unstaged:-0}" "${ahead:-0}" "${behind:-0}" "${commits:-0}"
