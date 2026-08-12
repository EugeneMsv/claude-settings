#!/bin/bash
# Claude Code statusline — three lines:
#   Line 1: pwd  branch  +lines  -lines  !unstaged  ↑ahead  ↓behind  commits=N
#   Line 2: model  ctx: N% / 200k  in:Nk out:Nk  5h N%  7d N%  vX.Y.Z
#   Line 3: memory  added-dirs  mcp  docker
#
# Data gathering is split into per-concern scripts alongside this one
# (git-status.sh, usage-status.sh, docker-status.sh, memory-status.sh, mcp-status.sh,
# cache-prune.sh) — this file only formats their TSV output.

SL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ANSI colors
GREEN='\033[32m'
RED='\033[31m'
YELLOW='\033[33m'
CYAN='\033[36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# Format a duration in seconds as the largest single unit (e.g. 9m, 3h, 2d).
fmt_duration() {
    local s=${1:-0}
    if   [[ "$s" -ge 86400 ]]; then printf "%dd" $(( s / 86400 ))
    elif [[ "$s" -ge 3600  ]]; then printf "%dh" $(( s / 3600 ))
    elif [[ "$s" -ge 60    ]]; then printf "%dm" $(( s / 60 ))
    else                            printf "%ds" "$s"
    fi
}

# Read Claude Code session JSON from stdin
input=$(cat)

# Parse Claude session fields
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
model=$(printf '%s' "$input" | jq -r '.model.display_name // empty' 2>/dev/null)
ctx_pct=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // 0' 2>/dev/null)
ctx_size=$(printf '%s' "$input" | jq -r '.context_window.context_window_size // 0' 2>/dev/null)
# Override for 1M context models (Claude Code defaults to 200k for custom models)
if [[ "$model" == *"1M"* || "$model" == *"1m"* || "$model" == *"context-1m"* ]]; then
  orig_ctx_size=$ctx_size
  ctx_size=1000000
  # Recalculate percentage against real context window
  if [[ "${orig_ctx_size:-0}" -gt 0 && "${ctx_pct:-0}" -gt 0 ]]; then
    ctx_pct=$(( ctx_pct * orig_ctx_size / ctx_size ))
  fi
fi
total_in=$(printf '%s' "$input" | jq -r '.context_window.total_input_tokens // 0' 2>/dev/null)
total_out=$(printf '%s' "$input" | jq -r '.context_window.total_output_tokens // 0' 2>/dev/null)
session_name=$(printf '%s' "$input" | jq -r '.session_name // empty' 2>/dev/null)
effort=$(printf '%s' "$input" | jq -r '.effort.level // empty' 2>/dev/null)
version=$(printf '%s' "$input" | jq -r '.version // empty' 2>/dev/null)
session_id=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
added_dirs_raw=$(printf '%s' "$input" | jq -r '(.workspace.added_dirs // []) | .[]' 2>/dev/null)

# Per-session cache dir so concurrent sessions (esp. in different repos) never clobber each other
cache_base="${HOME}/.claude/statusline/cache/${session_id:-default}"
mkdir -p "$cache_base"

# Fall back to $PWD if cwd not in JSON
[[ -z "$cwd" ]] && cwd="$PWD"
short_cwd="${cwd/#$HOME/\~}"

IFS=$'\t' read -r mcp_count mcp_connected mcp_failed < <("${SL_DIR}/mcp-status.sh" "$cwd" "$cache_base")

# Uses cut, not `IFS=$'\t' read` — branch is empty for non-git dirs, and a
# lone-tab IFS treats a leading empty field as squeezable IFS-whitespace,
# shifting every later field left by one (see usage-status parse above).
git_output=$("${SL_DIR}/git-status.sh" "$cwd")
branch=$(cut -f1 <<< "$git_output")
ins=$(cut -f2 <<< "$git_output")
del=$(cut -f3 <<< "$git_output")
unstaged=$(cut -f4 <<< "$git_output")
ahead=$(cut -f5 <<< "$git_output")
behind=$(cut -f6 <<< "$git_output")
commits=$(cut -f7 <<< "$git_output")

# ── LINE 1: workspace / git ──────────────────────────────────────────────────

SEP1=" ${DIM}|${RESET} "
first1=true
sep1() { $first1 && first1=false || printf "%b" "$SEP1"; }

sep1; printf "${BOLD}%s${RESET}" "$short_cwd"

if [[ -n "$branch" ]]; then
  sep1; printf "${CYAN}${BOLD}%s${RESET}" "$branch"

  if [[ "${ins:-0}" -gt 0 || "${del:-0}" -gt 0 ]]; then
    sep1; printf "edits"
    [[ "${ins:-0}" -gt 0 ]] && printf " ${GREEN}+%s${RESET}" "$ins"
    [[ "${ins:-0}" -gt 0 && "${del:-0}" -gt 0 ]] && printf " "
    [[ "${del:-0}" -gt 0 ]] && printf "${RED}-%s${RESET}" "$del"
  fi

  [[ "${unstaged:-0}" -gt 0 ]] && { sep1; printf "${YELLOW}!%s${RESET}" "$unstaged"; }

  if [[ "${ahead:-0}" -gt 0 || "${behind:-0}" -gt 0 ]]; then
    sep1; printf "commits: "
    [[ "${ahead:-0}" -gt 0 ]] && printf "${GREEN}↑%s${RESET}" "$ahead"
    [[ "${ahead:-0}" -gt 0 && "${behind:-0}" -gt 0 ]] && printf " "
    [[ "${behind:-0}" -gt 0 ]] && printf "${RED}↓%s${RESET}" "$behind"
  fi

  [[ "${commits:-0}" -gt 0 ]] && { sep1; printf "${DIM}commits=%s${RESET}" "$commits"; }
fi

printf '\n'

# ── LINE 2: Claude session ───────────────────────────────────────────────────

SEP=" ${DIM}|${RESET} "
first=true
sep() { $first && first=false || printf "%b" "$SEP"; }

# Model + effort level + transcript link
if [[ -n "$model" ]]; then
  sep
  printf "${BOLD}%s${RESET}" "$model"
  [[ -n "$effort" ]] && printf " ${DIM}[%s]${RESET}" "$effort"
  if [[ -n "$session_id" ]]; then
    cwd_enc=$(printf '%s' "$cwd" | sed 's#[/.]#-#g')
    transcript="${HOME}/.claude/projects/${cwd_enc}/${session_id}.jsonl"
    if [[ -f "$transcript" ]]; then
      printf " ${DIM}\e]8;;file://%s\alog\e]8;;\a${RESET}" "$transcript"
    fi
  fi
fi

# Context: N% / 200k — color thresholds: green <60, yellow <85, red ≥85
if [[ "${ctx_pct:-0}" -gt 0 || "${ctx_size:-0}" -gt 0 ]]; then
  if [[ "$ctx_size" -ge 1000000 ]]; then
    ctx_size_label="$(( ctx_size / 1000000 ))m"
  else
    ctx_size_label="$(( ctx_size / 1000 ))k"
  fi
  if [[ "$ctx_pct" -ge 85 ]]; then
    ctx_color="$RED"
  elif [[ "$ctx_pct" -ge 60 ]]; then
    ctx_color="$YELLOW"
  else
    ctx_color="$GREEN"
  fi
  sep; printf "${ctx_color}ctx %s%% / %s${RESET}" "$ctx_pct" "$ctx_size_label"
fi

# Session cumulative I/O tokens
if [[ "${total_in:-0}" -gt 0 || "${total_out:-0}" -gt 0 ]]; then
  in_k=$(( total_in / 1000 ))
  out_k=$(( total_out / 1000 ))
  sep; printf "${DIM}in:%sk out:%sk${RESET}" "$in_k" "$out_k"
fi

# Rate limits (5h / 7d) from Claude.ai OAuth
# Uses cut, not `IFS=$'\t' read`, because a lone-tab IFS treats it as
# IFS-whitespace and squeezes/strips leading empty fields (e.g. "\t\t0"
# misparses as five_pct=0 instead of fetched_at=0).
usage_output=$("${SL_DIR}/usage-status.sh")
five_pct=$(cut -f1 <<< "$usage_output")
seven_pct=$(cut -f2 <<< "$usage_output")
usage_fetched_at=$(cut -f3 <<< "$usage_output")
limit_color() {
    local pct=$1
    if   [[ "$pct" -ge 85 ]]; then printf "%s" "$RED"
    elif [[ "$pct" -ge 60 ]]; then printf "%s" "$YELLOW"
    elif [[ "$pct" -ge 20 ]]; then printf "%s" "$GREEN"
    else                           printf "%s" "$CYAN"
    fi
}
if [[ -n "$five_pct" || -n "$seven_pct" ]]; then
    sep
    [[ -n "$five_pct" ]]  && printf "${DIM}5h${RESET} $(limit_color "$five_pct")%s%%${RESET}" "$five_pct"
    [[ -n "$five_pct" && -n "$seven_pct" ]] && printf "  "
    [[ -n "$seven_pct" ]] && printf "${DIM}7d${RESET} $(limit_color "$seven_pct")%s%%${RESET}" "$seven_pct"
    if [[ "${usage_fetched_at:-0}" -gt 0 ]]; then
        age_secs=$(( $(date +%s) - usage_fetched_at ))
        if [[ "$age_secs" -ge 3600 ]]; then
            age_label="$(( age_secs / 3600 ))h ago"
        else
            age_label="$(( age_secs / 60 ))m ago"
        fi
        printf "  ${DIM}%s${RESET}" "$age_label"
    fi
fi

# Version
if [[ -n "$version" ]]; then
  sep; printf "${DIM}v%s${RESET}" "$version"
fi

printf '\n'

# Docker Compose — rendered at the end of line 3; only when a compose project under this repo has running containers
IFS=$'\t' read -r d_name d_status d_verdict d_uptime_fmt < <("${SL_DIR}/docker-status.sh" "$cwd" "$cache_base")
docker_render=""
if [[ -n "$d_name" ]]; then
  [[ "$d_verdict" == "red" ]] && d_color="$RED" || d_color="$GREEN"
  printf -v docker_render "🐳 ${DIM}%s %s${RESET} ${d_color}%s${RESET}" "$d_name" "$d_uptime_fmt" "$d_status"
fi

# Prune stale cache once per day (guarded internally against concurrent sessions)
"${SL_DIR}/cache-prune.sh" "${HOME}/.claude/statusline/cache" &

# ── LINE 3: auto-memory + added dirs + MCP + Docker (per-project, cached ~2 min) ──
IFS=$'\t' read -r mem_enabled mem_count mem_lines mem_newest mem_link < <("${SL_DIR}/memory-status.sh" "$cwd" "$cache_base")

if [[ "$mem_enabled" == "true" ]]; then
  printf "🧠 ${GREEN}on${RESET}"
else
  printf "🧠 ${DIM}off${RESET}"
fi

if [[ "${mem_count:-0}" -gt 0 ]]; then
  if [[ -n "$mem_link" ]]; then
    # OSC 8 hyperlink: Cmd/Ctrl+click the text to open MEMORY.md (iTerm2/Kitty/WezTerm)
    printf " ${DIM}· \e]8;;file://%s\a%s files %s lines\e]8;;\a${RESET}" "$mem_link" "$mem_count" "$mem_lines"
  else
    printf " ${DIM}· %s files %s lines${RESET}" "$mem_count" "$mem_lines"
  fi
else
  printf " ${DIM}· no entries${RESET}"
fi

if [[ -n "$mem_newest" && "${mem_newest:-0}" -gt 0 ]]; then
  m_age=$(( $(date +%s) - mem_newest ))
  if   [[ "$m_age" -ge 86400 ]]; then m_label="$(( m_age / 86400 ))d ago"
  elif [[ "$m_age" -ge 3600  ]]; then m_label="$(( m_age / 3600 ))h ago"
  elif [[ "$m_age" -ge 60    ]]; then m_label="$(( m_age / 60 ))m ago"
  else                                m_label="just now"
  fi
  printf " ${DIM}· %s${RESET}" "$m_label"
fi

# Added dirs from /add-dir — show count only
if [[ -n "$added_dirs_raw" ]]; then
  added_count=$(printf '%s\n' "$added_dirs_raw" | grep -c .)
  [[ "${added_count:-0}" -gt 0 ]] && printf " ${DIM}|${RESET} 📁 %s" "$added_count"
fi

# MCP server count
if [[ "${mcp_count:-0}" -gt 0 ]]; then
  if [[ "$mcp_connected" -lt "$mcp_count" ]]; then
    printf " ${DIM}|${RESET} 🔌 ${RED}%s/%s${RESET}" "$mcp_connected" "$mcp_count"
    [[ -n "$mcp_failed" ]] && printf " ${DIM}⚠ %s${RESET}" "$mcp_failed"
  else
    printf " ${DIM}|${RESET} 🔌 ${GREEN}%s${RESET}" "$mcp_count"
  fi
fi

# Docker after memory, same line
[[ -n "$docker_render" ]] && printf " ${DIM}|${RESET} %s" "$docker_render"

printf '\n'
