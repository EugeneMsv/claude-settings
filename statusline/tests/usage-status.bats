#!/usr/bin/env bats
# Given an OAuth token source and a rate-limit API response, usage-status.sh should print
# five_hour/seven_day utilization percentages and the fetch timestamp — or blank fields
# when no token is available or the API call fails.

load 'test_helper'

setup() {
    setup_fake_home
    setup_fake_bin
    USAGE_CACHE="$(mktemp -d)/statusline-usage-cache.json"
    export SL_USAGE_CACHE="$USAGE_CACHE"
    unset ANTHROPIC_BASE_URL
}

teardown() {
    teardown_fake_bin
    teardown_fake_home
    unset SL_USAGE_CACHE
    unset ANTHROPIC_BASE_URL
}

@test "no keychain and no credentials file prints blank fields" {
    # `security` absent from PATH, no ~/.claude/.credentials.json written.
    write_stub security 'exit 1'

    run "$SL_DIR/usage-status.sh"

    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '\t\t0')" ]
}

@test "credentials file token with successful API response reports percentages" {
    jq -n '{claudeAiOauth: {accessToken: "tok-123"}}' > "$HOME/.claude/.credentials.json"
    write_stub security 'exit 1'
    write_stub curl 'echo "{\"five_hour\":{\"utilization\":42.4},\"seven_day\":{\"utilization\":10.6}}"'

    run "$SL_DIR/usage-status.sh"

    [ "$status" -eq 0 ]
    IFS=$'\t' read -r five seven fetched <<< "$output"
    [ "$five" = "42" ]
    [ "$seven" = "11" ]
    [ "$fetched" != "0" ]
}

@test "API error response prints blank fields" {
    jq -n '{claudeAiOauth: {accessToken: "tok-123"}}' > "$HOME/.claude/.credentials.json"
    write_stub security 'exit 1'
    write_stub curl 'echo "{\"error\":{\"message\":\"boom\"}}"'

    run "$SL_DIR/usage-status.sh"

    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '\t\t0')" ]
}

@test "result is cached — second call does not re-invoke curl" {
    jq -n '{claudeAiOauth: {accessToken: "tok-123"}}' > "$HOME/.claude/.credentials.json"
    write_stub security 'exit 1'
    write_stub curl 'echo "{\"five_hour\":{\"utilization\":5},\"seven_day\":{\"utilization\":6}}"'

    run "$SL_DIR/usage-status.sh"
    five="$(printf '%s' "$output" | cut -f1)"
    [ "$five" = "5" ]

    write_stub curl 'echo "{\"five_hour\":{\"utilization\":99},\"seven_day\":{\"utilization\":99}}"'

    run "$SL_DIR/usage-status.sh"
    five="$(printf '%s' "$output" | cut -f1)"
    [ "$five" = "5" ]
}

@test "ANTHROPIC_BASE_URL pointing at a custom proxy prints blank fields without calling curl" {
    jq -n '{claudeAiOauth: {accessToken: "tok-123"}}' > "$HOME/.claude/.credentials.json"
    write_stub security 'exit 1'
    write_stub curl 'echo "should not be invoked" >&2; exit 1'
    export ANTHROPIC_BASE_URL="https://llm-proxy.example.com"

    run "$SL_DIR/usage-status.sh"

    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '\t\t0')" ]
}

@test "ANTHROPIC_BASE_URL pointing at api.anthropic.com still calls curl" {
    jq -n '{claudeAiOauth: {accessToken: "tok-123"}}' > "$HOME/.claude/.credentials.json"
    write_stub security 'exit 1'
    write_stub curl 'echo "{\"five_hour\":{\"utilization\":42},\"seven_day\":{\"utilization\":10}}"'
    export ANTHROPIC_BASE_URL="https://api.anthropic.com"

    run "$SL_DIR/usage-status.sh"

    [ "$status" -eq 0 ]
    five="$(printf '%s' "$output" | cut -f1)"
    [ "$five" = "42" ]
}
