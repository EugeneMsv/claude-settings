#!/bin/bash
# subagentStatusLine — one custom row per visible subagent in the agent panel.
# Fields shown: label/description, model, effort, context window size, token count, elapsed time.
#
# Claude Code pipes one JSON object per refresh tick on stdin:
#   { ...base hook fields, "columns": N, "tasks": [ {id,type,status,description,
#     label,startTime,model,effort,contextWindowSize,tokenCount,tokenSamples,cwd}, ... ] }
#
# Verified empirically (11 live refresh ticks of a running deep-researcher agent,
# 2026-08-05, Claude Code v2.1.220): the payload never includes `name` or
# `subagent_type` despite both being tracked internally (visible in the session
# transcript's Agent tool-call input) — docs list `name` as a task field but it
# is absent here. `type` is a generic bucket ("local_agent"/"remote_agent"), not
# agent identity, so it's dropped. `label` and `description` are often identical;
# render whichever is present, once.
#
# Output: one JSON line per task to override: {"id":"<task id>","content":"<row body>"}
# Omitting a task's id keeps the default "name · description · token count" rendering.

DIM='\033[2m'
CYAN='\033[36m'
YELLOW='\033[33m'
GREEN='\033[32m'
RESET='\033[0m'

fmt_duration() {
    local s=${1:-0}
    if   [[ "$s" -ge 86400 ]]; then printf "%dd %dh" $(( s / 86400 )) $(( (s % 86400) / 3600 ))
    elif [[ "$s" -ge 3600  ]]; then printf "%dh %dm" $(( s / 3600 )) $(( (s % 3600) / 60 ))
    else                            printf "%dm %ds" $(( s / 60 )) $(( s % 60 ))
    fi
}

fmt_size() {
    local n=${1:-0}
    if   [[ "$n" -ge 1000000 ]]; then printf "%sm" $(( n / 1000000 ))
    elif [[ "$n" -ge 1000    ]]; then printf "%sk" $(( n / 1000 ))
    else                              printf "%s" "$n"
    fi
}

input=$(cat)
now_epoch=$(date +%s)

# One compact JSON object per task on its own line — avoids the tab-IFS
# squeezing bug where consecutive empty TSV fields shift every later field left.
task_lines=$(printf '%s' "$input" | jq -c '(.tasks // [])[]')

[[ -z "$task_lines" ]] && exit 0

DESC_MAX=40

while IFS= read -r task; do
  [[ -z "$task" ]] && continue

  id=$(jq -r '.id // empty' <<< "$task")
  [[ -z "$id" ]] && continue

  label=$(jq -r '.label // empty' <<< "$task")
  description=$(jq -r '.description // empty' <<< "$task")
  model=$(jq -r '.model // empty' <<< "$task")
  effort=$(jq -r '.effort // empty' <<< "$task")
  ctx_size=$(jq -r '.contextWindowSize // 0' <<< "$task")
  tok_count=$(jq -r '.tokenCount // 0' <<< "$task")
  start_time=$(jq -r '.startTime // 0' <<< "$task")

  # startTime may be unix epoch seconds or milliseconds — 13+ digits means ms.
  start_s="$start_time"
  [[ "${#start_time}" -ge 13 ]] && start_s=$(( start_time / 1000 ))
  elapsed=""
  [[ "${start_s:-0}" -gt 0 ]] && elapsed=$(fmt_duration $(( now_epoch - start_s )))

  # label and description are often identical — show whichever is present, once.
  ident="$description"
  [[ -z "$ident" ]] && ident="$label"

  content=""
  sep() { [[ -n "$content" ]] && content+=" $(printf "${DIM}|${RESET}") "; }

  if [[ -n "$ident" ]]; then
    ident_short="$ident"
    [[ "${#ident_short}" -gt "$DESC_MAX" ]] && ident_short="${ident_short:0:$DESC_MAX}…"
    sep; content+="$(printf "${GREEN}%s${RESET}" "$ident_short")"
  fi
  if [[ -n "$model" ]]; then
    sep; content+="${model}"
    [[ -n "$effort" ]] && content+=" $(printf "${DIM}[${effort}]${RESET}")"
  fi
  if [[ "${ctx_size:-0}" -gt 0 || "${tok_count:-0}" -gt 0 ]]; then
    sep
    content+="$(printf "${CYAN}ctx $(fmt_size "$tok_count")/$(fmt_size "$ctx_size")${RESET}")"
  fi
  [[ -n "$elapsed" ]] && { sep; content+="$(printf "${YELLOW}${elapsed}${RESET}")"; }

  jq -nc --arg id "$id" --arg content "$content" '{id: $id, content: $content}'
done <<< "$task_lines"
