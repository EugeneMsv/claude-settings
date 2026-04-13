#!/bin/bash
# Claude Code statusline — two lines:
#   Line 1: pwd  branch  +lines  -lines  !unstaged  ↑ahead  ↓behind  commits=N
#   Line 2: model  context: N% / 200k  in:Nk out:Nk  edits +Nl -Nl  5h [bar] N%  7d [bar] N%  [session_name  vX.Y.Z]

# ANSI colors
GREEN='\033[32m'
RED='\033[31m'
YELLOW='\033[33m'
CYAN='\033[36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

mkdir -p /tmp/claude


# Resolve Claude.ai OAuth token from macOS Keychain or credentials file
get_oauth_token() {
    if command -v security >/dev/null 2>&1; then
        local blob token
        blob=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
        if [[ -n "$blob" ]]; then
            token=$(echo "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
            [[ -n "$token" && "$token" != "null" ]] && echo "$token" && return 0
        fi
    fi
    local creds_file="${HOME}/.claude/.credentials.json"
    if [[ -f "$creds_file" ]]; then
        local token
        token=$(jq -r '.claudeAiOauth.accessToken // empty' "$creds_file" 2>/dev/null)
        [[ -n "$token" && "$token" != "null" ]] && echo "$token" && return 0
    fi
    echo ""
}

# Fetch rate limit data from Anthropic API (cached 1h)
get_usage_data() {
    local api_cache="/tmp/claude/statusline-usage-cache.json"
    local api_cache_max=300

    if [[ -f "$api_cache" ]]; then
        local cached
        cached=$(cat "$api_cache" 2>/dev/null)
        if [[ -n "$cached" ]] && ! echo "$cached" | jq -e '.error' >/dev/null 2>&1; then
            local fetched_at now age
            fetched_at=$(echo "$cached" | jq -r '.fetched_at // 0' 2>/dev/null)
            now=$(date +%s)
            age=$(( now - fetched_at ))
            if [[ "$age" -lt "$api_cache_max" ]]; then
                echo "$cached"
                return 0
            fi
        fi
    fi

    local token
    token=$(get_oauth_token)
    if [[ -n "$token" && "$token" != "null" ]]; then
        local response
        response=$(curl -s --max-time 8 \
            -H "Accept: application/json" \
            -H "Authorization: Bearer $token" \
            -H "anthropic-beta: oauth-2025-04-20" \
            "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
        if [[ -n "$response" ]] && echo "$response" | jq . >/dev/null 2>&1; then
            if ! echo "$response" | jq -e '.error' >/dev/null 2>&1; then
                echo "$response" | jq --argjson ts "$(date +%s)" '. + {fetched_at: $ts}' > "$api_cache"
                cat "$api_cache"
                return 0
            fi
        fi
    fi

    # API call failed — return nothing, caller will skip display
    return 1
}

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

SEP1=" ${DIM}|${RESET} "
first1=true
sep1() { $first1 && first1=false || printf "%b" "$SEP1"; }

sep1; printf "${BOLD}%s${RESET}" "$short_cwd"

if git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
  branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)
  sep1; printf "${CYAN}${BOLD}%s${RESET}" "$branch"

  # Line insertions/deletions from working tree vs HEAD
  stats=$(git -C "$cwd" diff HEAD --shortstat 2>/dev/null)
  ins=$(printf '%s' "$stats" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+')
  del=$(printf '%s' "$stats" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+')
  if [[ ( -n "$ins" && "$ins" -gt 0 ) || ( -n "$del" && "$del" -gt 0 ) ]]; then
    sep1
    [[ -n "$ins" && "$ins" -gt 0 ]] && printf "${GREEN}+%s${RESET}" "$ins"
    [[ -n "$ins" && "$ins" -gt 0 && -n "$del" && "$del" -gt 0 ]] && printf " "
    [[ -n "$del" && "$del" -gt 0 ]] && printf "${RED}-%s${RESET}" "$del"
  fi

  # Unstaged file count
  u=$(git -C "$cwd" diff --name-only 2>/dev/null | wc -l | tr -d ' ')
  [[ "${u:-0}" -gt 0 ]] && { sep1; printf "${YELLOW}!%s${RESET}" "$u"; }

  # Ahead / behind upstream
  a=$(git -C "$cwd" rev-list --count "HEAD@{upstream}..HEAD" 2>/dev/null)
  r=$(git -C "$cwd" rev-list --count "HEAD..HEAD@{upstream}" 2>/dev/null)
  if [[ "${a:-0}" -gt 0 || "${r:-0}" -gt 0 ]]; then
    sep1
    [[ "${a:-0}" -gt 0 ]] && printf "${GREEN}↑%s${RESET}" "$a"
    [[ "${a:-0}" -gt 0 && "${r:-0}" -gt 0 ]] && printf " "
    [[ "${r:-0}" -gt 0 ]] && printf "${RED}↓%s${RESET}" "$r"
  fi

  # Commits on branch vs base
  base=$(git -C "$cwd" rev-parse --abbrev-ref origin/HEAD 2>/dev/null | sed 's|origin/||')
  c=$(git -C "$cwd" rev-list --count "${base:-main}..HEAD" 2>/dev/null)
  [[ "${c:-0}" -gt 0 ]] && { sep1; printf "${DIM}commits=%s${RESET}" "$c"; }
fi

printf '\n'

# ── LINE 2: Claude session ───────────────────────────────────────────────────

SEP=" ${DIM}|${RESET} "
first=true
sep() { $first && first=false || printf "%b" "$SEP"; }

# Model
if [[ -n "$model" ]]; then
  sep; printf "${BOLD}%s${RESET}" "$model"
fi

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
  sep; printf "${ctx_color}ctx %s%% / %sk${RESET}" "$ctx_pct" "$ctx_size_k"
fi

# Session cumulative I/O tokens
if [[ "${total_in:-0}" -gt 0 || "${total_out:-0}" -gt 0 ]]; then
  in_k=$(( total_in / 1000 ))
  out_k=$(( total_out / 1000 ))
  sep; printf "${DIM}in:%sk out:%sk${RESET}" "$in_k" "$out_k"
fi

# Code edits this session
if [[ "${lines_added:-0}" -gt 0 || "${lines_removed:-0}" -gt 0 ]]; then
  sep; printf "edits"
  [[ "${lines_added:-0}" -gt 0 ]]   && printf " ${GREEN}+%s${RESET}" "$lines_added"
  [[ "${lines_removed:-0}" -gt 0 ]] && printf " ${RED}-%s${RESET}" "$lines_removed"
fi

# Rate limits (5h / 7d) from Claude.ai OAuth
usage_data=$(get_usage_data)
if [[ -n "$usage_data" ]]; then
    five_pct=$(echo "$usage_data"   | jq -r '.five_hour.utilization // empty' 2>/dev/null | awk '{printf "%.0f", $1}')
    seven_pct=$(echo "$usage_data"  | jq -r '.seven_day.utilization // empty' 2>/dev/null | awk '{printf "%.0f", $1}')
    fetched_at=$(echo "$usage_data" | jq -r '.fetched_at // 0' 2>/dev/null)
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
        if [[ "${fetched_at:-0}" -gt 0 ]]; then
            age_secs=$(( $(date +%s) - fetched_at ))
            if [[ "$age_secs" -ge 3600 ]]; then
                age_label="$(( age_secs / 3600 ))h ago"
            else
                age_label="$(( age_secs / 60 ))m ago"
            fi
            printf "  ${DIM}%s${RESET}" "$age_label"
        fi
    fi
fi

# Version
if [[ -n "$version" ]]; then
  sep; printf "${DIM}v%s${RESET}" "$version"
fi

printf '\n'
