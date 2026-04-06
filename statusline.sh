#!/bin/bash
# Claude Code statusline — two lines:
#   Line 1: pwd  branch  +lines  -lines  !unstaged  ↑ahead  ↓behind  commits=N
#   Line 2: model  context: N% / 200k  in:Nk out:Nk  edits +Nl -Nl  [session_name  vX.Y.Z]

# ANSI colors
GREEN='\033[32m'
RED='\033[31m'
YELLOW='\033[33m'
CYAN='\033[36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# Read Claude Code session JSON from stdin
input=$(cat)

# Parse Claude session fields
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
model=$(printf '%s' "$input" | jq -r '.model.display_name // empty' 2>/dev/null)
ctx_pct=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // 0' 2>/dev/null)
ctx_size=$(printf '%s' "$input" | jq -r '.context_window.context_window_size // 0' 2>/dev/null)
total_in=$(printf '%s' "$input" | jq -r '.context_window.total_input_tokens // 0' 2>/dev/null)
total_out=$(printf '%s' "$input" | jq -r '.context_window.total_output_tokens // 0' 2>/dev/null)
lines_added=$(printf '%s' "$input" | jq -r '.cost.total_lines_added // 0' 2>/dev/null)
lines_removed=$(printf '%s' "$input" | jq -r '.cost.total_lines_removed // 0' 2>/dev/null)
session_name=$(printf '%s' "$input" | jq -r '.session_name // empty' 2>/dev/null)
version=$(printf '%s' "$input" | jq -r '.version // empty' 2>/dev/null)

# Fall back to $PWD if cwd not in JSON
[[ -z "$cwd" ]] && cwd="$PWD"
short_cwd="${cwd/#$HOME/\~}"

# ── LINE 1: workspace / git ──────────────────────────────────────────────────

printf "${BOLD}%s${RESET}" "$short_cwd"

if git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
  branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)
  printf "  ${CYAN}${BOLD}%s${RESET}" "$branch"

  # Line insertions/deletions from working tree vs HEAD
  stats=$(git -C "$cwd" diff HEAD --shortstat 2>/dev/null)
  ins=$(printf '%s' "$stats" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+')
  del=$(printf '%s' "$stats" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+')
  [[ -n "$ins" && "$ins" -gt 0 ]] && printf "  ${GREEN}+%s${RESET}" "$ins"
  [[ -n "$del" && "$del" -gt 0 ]] && printf "  ${RED}-%s${RESET}" "$del"

  # Unstaged file count
  u=$(git -C "$cwd" diff --name-only 2>/dev/null | wc -l | tr -d ' ')
  [[ "${u:-0}" -gt 0 ]] && printf "  ${YELLOW}!%s${RESET}" "$u"

  # Ahead / behind upstream
  a=$(git -C "$cwd" rev-list --count "HEAD@{upstream}..HEAD" 2>/dev/null)
  [[ "${a:-0}" -gt 0 ]] && printf "  ${GREEN}↑%s${RESET}" "$a"
  r=$(git -C "$cwd" rev-list --count "HEAD..HEAD@{upstream}" 2>/dev/null)
  [[ "${r:-0}" -gt 0 ]] && printf "  ${RED}↓%s${RESET}" "$r"

  # Commits on branch vs base
  base=$(git -C "$cwd" rev-parse --abbrev-ref origin/HEAD 2>/dev/null | sed 's|origin/||')
  c=$(git -C "$cwd" rev-list --count "${base:-main}..HEAD" 2>/dev/null)
  [[ "${c:-0}" -gt 0 ]] && printf "  ${DIM}commits=%s${RESET}" "$c"
fi

printf '\n'

# ── LINE 2: Claude session ───────────────────────────────────────────────────

[[ -n "$model" ]] && printf "${BOLD}%s${RESET}" "$model"

# Context: N% / 200k — color thresholds: green <60, yellow <85, red ≥85
if [[ "${ctx_pct:-0}" -gt 0 || "${ctx_size:-0}" -gt 0 ]]; then
  ctx_size_k=$(( ctx_size / 1000 ))
  if [[ "$ctx_pct" -ge 85 ]]; then
    ctx_color="$RED"
  elif [[ "$ctx_pct" -ge 60 ]]; then
    ctx_color="$YELLOW"
  else
    ctx_color="$GREEN"
  fi
  printf "  ${ctx_color}ctx %s%% / %sk${RESET}" "$ctx_pct" "$ctx_size_k"
fi

# Session cumulative I/O tokens
if [[ "${total_in:-0}" -gt 0 || "${total_out:-0}" -gt 0 ]]; then
  in_k=$(( total_in / 1000 ))
  out_k=$(( total_out / 1000 ))
  printf "  ${DIM}in:%sk out:%sk${RESET}" "$in_k" "$out_k"
fi

# Code edits this session
if [[ "${lines_added:-0}" -gt 0 || "${lines_removed:-0}" -gt 0 ]]; then
  printf "  edits"
  [[ "${lines_added:-0}" -gt 0 ]]   && printf " ${GREEN}+%s${RESET}" "$lines_added"
  [[ "${lines_removed:-0}" -gt 0 ]] && printf " ${RED}-%s${RESET}" "$lines_removed"
fi

# Version — appended inline (no right-alignment; tput has no TTY here)
[[ -n "$version" ]] && printf "  ${DIM}v%s${RESET}" "$version"

printf '\n'
