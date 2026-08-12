#!/bin/bash
# docker-status.sh — resolve the Docker Compose project (if any) running under this repo.
#
# Usage: docker-status.sh <cwd> <cache_base>
# Output (TSV): <name> <status> <color> <uptime_fmt>
#   color = "red" when any container is unhealthy or exited non-zero, else "green"
#   status has "running" swapped for "healthy" when every running container is healthy
# Empty <name> means no compose project under this repo has running containers — caller skips.

cwd="$1"
cache_base="$2"
[[ -z "$cache_base" ]] && cache_base="${HOME}/.claude/statusline/cache"
mkdir -p "$cache_base"

# Format a duration in seconds as the largest single unit (e.g. 9m, 3h, 2d).
fmt_duration() {
    local s=${1:-0}
    if   [[ "$s" -ge 86400 ]]; then printf "%dd" $(( s / 86400 ))
    elif [[ "$s" -ge 3600  ]]; then printf "%dh" $(( s / 3600 ))
    elif [[ "$s" -ge 60    ]]; then printf "%dm" $(( s / 60 ))
    else                            printf "%ds" "$s"
    fi
}

# Fetch docker-compose project list (cached 15s; raw `docker compose ls` output)
get_docker_projects() {
    local cache="${cache_base}/docker-compose.json"
    local cache_max=15

    # Serve fresh cache — keeps the daemon out of the hot render path
    if [[ -f "$cache" ]]; then
        local fetched_at now age
        fetched_at=$(jq -r '.fetched_at // 0' "$cache" 2>/dev/null)
        now=$(date +%s)
        age=$(( now - fetched_at ))
        if [[ "${age:-9999}" -lt "$cache_max" ]]; then
            jq -c '.projects // []' "$cache" 2>/dev/null
            return 0
        fi
    fi

    command -v docker >/dev/null 2>&1 || { echo "[]"; return 1; }

    # Hard timeout so a hung/dead daemon never blocks the prompt
    local timeout_cmd=""
    if command -v timeout  >/dev/null 2>&1; then timeout_cmd="timeout 2"
    elif command -v gtimeout >/dev/null 2>&1; then timeout_cmd="gtimeout 2"
    fi

    local projects
    projects=$($timeout_cmd docker compose ls --all --format json 2>/dev/null)
    # On any failure cache an empty list so we don't re-hit the daemon each render
    if [[ -z "$projects" ]] || ! echo "$projects" | jq -e 'type=="array"' >/dev/null 2>&1; then
        projects="[]"
    fi
    jq -n --argjson p "$projects" --argjson ts "$(date +%s)" \
        '{fetched_at:$ts, projects:$p}' > "$cache" 2>/dev/null
    echo "$projects"
}

# Per-container summary for a compose project (cached 15s).
# Echoes TSV: <color> <all_running_healthy> <longest_uptime_secs>
get_docker_meta() {
    local proj="$1"
    local safe; safe=$(printf '%s' "$proj" | tr -c 'A-Za-z0-9._-' '_')
    local cache="${cache_base}/docker-ps-${safe}.json"
    local cache_max=15

    local containers=""
    if [[ -f "$cache" ]]; then
        local fetched_at now age
        fetched_at=$(jq -r '.fetched_at // 0' "$cache" 2>/dev/null)
        now=$(date +%s)
        age=$(( now - fetched_at ))
        if [[ "${age:-9999}" -lt "$cache_max" ]]; then
            containers=$(jq -c '.containers // []' "$cache" 2>/dev/null)
        fi
    fi

    if [[ -z "$containers" ]]; then
        command -v docker >/dev/null 2>&1 || { printf 'green\tno\t0\n'; return; }
        local timeout_cmd=""
        if command -v timeout  >/dev/null 2>&1; then timeout_cmd="timeout 2"
        elif command -v gtimeout >/dev/null 2>&1; then timeout_cmd="gtimeout 2"
        fi
        # `ps --format json` emits NDJSON on some versions, a single array on others — normalize to an array
        local raw
        raw=$($timeout_cmd docker compose -p "$proj" ps --all --format json 2>/dev/null)
        containers=$(printf '%s' "$raw" | jq -s -c 'if length==1 and (.[0]|type=="array") then .[0] else . end' 2>/dev/null)
        [[ -z "$containers" ]] && containers="[]"
        jq -n --argjson c "$containers" --argjson ts "$(date +%s)" \
            '{fetched_at:$ts, containers:$c}' > "$cache" 2>/dev/null
    fi

    local color="green" all_healthy="no"
    printf '%s' "$containers" | jq -e 'any(.[]; (.Health=="unhealthy") or ((.ExitCode // 0) != 0))' >/dev/null 2>&1 && color="red"
    printf '%s' "$containers" | jq -e 'map(select(.State=="running")) as $r | ($r|length>0) and ($r|all(.Health=="healthy"))' >/dev/null 2>&1 && all_healthy="yes"

    # Longest uptime = now - earliest CreatedAt among running containers
    local now earliest ts clean epoch
    now=$(date +%s)
    earliest=$now
    while IFS= read -r ts; do
        [[ -z "$ts" ]] && continue
        clean="${ts% *}"   # drop trailing tz name (e.g. " EDT"); numeric offset stays for %z
        epoch=$(date -j -f "%Y-%m-%d %H:%M:%S %z" "$clean" +%s 2>/dev/null)
        [[ -n "$epoch" && "$epoch" -lt "$earliest" ]] && earliest="$epoch"
    done < <(printf '%s' "$containers" | jq -r '.[] | select(.State=="running") | .CreatedAt // empty')

    local uptime=0
    [[ "$earliest" -lt "$now" ]] && uptime=$(( now - earliest ))
    printf '%s\t%s\t%s\n' "$color" "$all_healthy" "$uptime"
}

docker_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
[[ -z "$docker_root" ]] && docker_root="$cwd"

docker_projects=$(get_docker_projects)
[[ -z "$docker_projects" || "$docker_projects" == "[]" ]] && { printf '\t\t\t\n'; exit 0; }

docker_match=$(printf '%s' "$docker_projects" | jq -r --arg root "${docker_root}/" '
  map(select((.ConfigFiles // "") | split(",") | map(gsub("^ +";"")) | any(startswith($root))))
  | ((map(select(.Status | contains("running"))) | first) // first // empty)
  | select(. != null)
  | [.Name, .Status] | @tsv' 2>/dev/null)

if [[ -z "$docker_match" ]] || ! printf '%s' "${docker_match#*	}" | grep -q "running"; then
  printf '\t\t\t\n'
  exit 0
fi

d_name="${docker_match%%	*}"
d_status="${docker_match#*	}"
IFS=$'\t' read -r d_verdict d_allhealthy d_uptime < <(get_docker_meta "$d_name")

[[ "$d_allhealthy" == "yes" ]] && d_status="${d_status//running/healthy}"

printf '%s\t%s\t%s\t%s\n' "$d_name" "$d_status" "$d_verdict" "$(fmt_duration "$d_uptime")"
