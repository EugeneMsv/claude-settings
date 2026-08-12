#!/bin/bash
# usage-status.sh — resolve Anthropic 5h/7d rate-limit utilization for the statusline.
#
# Usage: usage-status.sh
# Output (TSV): <five_pct> <seven_pct> <fetched_at_epoch>
# Empty fields mean the OAuth token or API call was unavailable — caller should skip the segment.
#
# The 5h/7d figures come from Claude.ai's OAuth-based subscription usage endpoint.
# They're meaningless (and the API call is wasted work) when Claude Code is
# configured against a non-Anthropic endpoint (e.g. an internal LiteLLM proxy)
# via ANTHROPIC_BASE_URL — that traffic isn't metered by Claude.ai at all.

# True when ANTHROPIC_BASE_URL points somewhere other than api.anthropic.com
using_custom_endpoint() {
    local base_url="${ANTHROPIC_BASE_URL:-}"
    [[ -n "$base_url" && "$base_url" != *"api.anthropic.com"* ]]
}

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

# Fetch rate limit data from Anthropic API (cached 5 min)
get_usage_data() {
    local api_cache="${SL_USAGE_CACHE:-/tmp/claude/statusline-usage-cache.json}"
    local api_cache_max=300
    mkdir -p "$(dirname "$api_cache")"

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

if using_custom_endpoint; then
    printf '\t\t0\n'
    exit 0
fi

usage_data=$(get_usage_data)
if [[ -z "$usage_data" ]]; then
    printf '\t\t0\n'
    exit 0
fi

five_pct=$(echo "$usage_data"   | jq -r '.five_hour.utilization // empty' 2>/dev/null | awk '{printf "%.0f", $1}')
seven_pct=$(echo "$usage_data"  | jq -r '.seven_day.utilization // empty' 2>/dev/null | awk '{printf "%.0f", $1}')
fetched_at=$(echo "$usage_data" | jq -r '.fetched_at // 0' 2>/dev/null)

printf '%s\t%s\t%s\n' "$five_pct" "$seven_pct" "${fetched_at:-0}"
