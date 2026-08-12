#!/bin/bash
# mcp-status.sh — resolve MCP server status for the statusline.
#
# `claude mcp list` health-checks every server configured in .mcp.json regardless of whether
# it's disabled for the current project (~/.claude.json .projects[cwd].disabledMcpServers) —
# a disabled server still reports "✔ Connected" even though its tools are never loaded into
# the session. This script merges both sources into one cached JSON file and prints the
# already-filtered counts, so the statusline never has to re-derive this logic inline.
#
# Usage: mcp-status.sh <cwd> <cache_base>
# Output (TSV): <count> <connected> <failed_csv>
#   count       = number of non-disabled configured servers
#   connected   = number of those reporting "✔ Connected"
#   failed_csv  = comma-joined names of non-disabled servers NOT connected

cwd="$1"
cache_base="$2"
[[ -z "$cwd" || -z "$cache_base" ]] && { echo -e "0\t0\t"; exit 1; }

mkdir -p "$cache_base"
cache="${cache_base}/mcp-status.json"
cache_max=120

mcp_json=""
if [[ -f "$cache" ]]; then
    age=$(( $(date +%s) - $(stat -f %m "$cache" 2>/dev/null || echo 0) ))
    [[ "${age:-9999}" -lt "$cache_max" ]] && mcp_json=$(cat "$cache")
fi

if [[ -z "$mcp_json" ]]; then
    raw=$(claude mcp list 2>/dev/null)

    # ~/.claude.json is rewritten frequently by Claude Code itself (session bookkeeping),
    # so a read can land mid-write and jq fails to parse. Retry rather than silently
    # treating a transient parse failure as "nothing disabled".
    disabled=""
    disabled_ok=false
    for _attempt in $(seq 1 8); do
        if disabled=$(jq -e -c --arg cwd "$cwd" '.projects[$cwd].disabledMcpServers // []' "${HOME}/.claude.json" 2>/dev/null); then
            disabled_ok=true
            break
        fi
        sleep 0.3
    done

    if [[ "$disabled_ok" != "true" ]]; then
        # Every retry failed to get a clean read — don't cache a guess. Print the previous
        # cache if one exists (better than nothing), otherwise fall back to unfiltered zero
        # counts, and let the NEXT render try fresh instead of freezing a bad result for
        # cache_max seconds.
        if [[ -f "$cache" ]]; then
            mcp_json=$(cat "$cache")
        else
            mcp_json="[]"
        fi
        count=$(printf '%s' "$mcp_json" | jq '[.[] | select(.disabled == false)] | length' 2>/dev/null)
        connected=$(printf '%s' "$mcp_json" | jq '[.[] | select(.disabled == false and .connected == true)] | length' 2>/dev/null)
        failed=$(printf '%s' "$mcp_json" | jq -r '[.[] | select(.disabled == false and .connected == false) | .name] | join(",")' 2>/dev/null)
        printf '%s\t%s\t%s\n' "${count:-0}" "${connected:-0}" "$failed"
        exit 0
    fi

    mcp_json=$(printf '%s' "$raw" | jq -R -s --argjson disabled "$disabled" '
        split("\n")
        | map(select(test("^[a-zA-Z0-9_-]+:")))
        | map(capture("^(?<name>[a-zA-Z0-9_-]+):\\s*(?<raw>.*)$"))
        | map(.name as $n | . + {connected: (.raw | test("✔ Connected")), disabled: ($disabled | index($n) != null)})
    ' 2>/dev/null)
    [[ -z "$mcp_json" ]] && mcp_json="[]"
    echo "$mcp_json" > "$cache"
fi

count=$(printf '%s' "$mcp_json" | jq '[.[] | select(.disabled == false)] | length' 2>/dev/null)
connected=$(printf '%s' "$mcp_json" | jq '[.[] | select(.disabled == false and .connected == true)] | length' 2>/dev/null)
failed=$(printf '%s' "$mcp_json" | jq -r '[.[] | select(.disabled == false and .connected == false) | .name] | join(",")' 2>/dev/null)

printf '%s\t%s\t%s\n' "${count:-0}" "${connected:-0}" "$failed"
