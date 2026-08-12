#!/usr/bin/env bats
# Given `claude mcp list` output and a project's disabledMcpServers list in ~/.claude.json,
# mcp-status.sh should count only non-disabled servers and correctly flag which are connected.

load 'test_helper'

setup() {
    setup_fake_home
    setup_fake_bin
    CACHE="$(mktemp -d)"
    PROJECT_CWD="/Users/tester/project"
}

teardown() {
    teardown_fake_bin
    teardown_fake_home
    rm -rf "$CACHE"
}

# write_claude_json <disabled_json_array>
write_claude_json() {
    jq -n --arg cwd "$PROJECT_CWD" --argjson disabled "$1" \
        '{projects: {($cwd): {disabledMcpServers: $disabled}}}' > "$HOME/.claude.json"
}

@test "all servers connected and none disabled" {
    write_stub claude 'cat <<EOF
alpha: some-url - ✔ Connected
beta: some-url - ✔ Connected
EOF'
    write_claude_json '[]'

    run "$SL_DIR/mcp-status.sh" "$PROJECT_CWD" "$CACHE"

    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '2\t2\t')" ]
}

@test "disabled servers are excluded from count even when reported connected" {
    write_stub claude 'cat <<EOF
alpha: some-url - ✔ Connected
beta: some-url - ✔ Connected
gamma: some-url - ✔ Connected
EOF'
    write_claude_json '["beta","gamma"]'

    run "$SL_DIR/mcp-status.sh" "$PROJECT_CWD" "$CACHE"

    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '1\t1\t')" ]
}

@test "non-disabled failed server is counted and named in failed list" {
    write_stub claude 'cat <<EOF
alpha: some-url - ✔ Connected
beta: some-url - ✗ Failed
EOF'
    write_claude_json '[]'

    run "$SL_DIR/mcp-status.sh" "$PROJECT_CWD" "$CACHE"

    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '2\t1\tbeta')" ]
}

@test "disabled failed server does not appear in failed list" {
    write_stub claude 'cat <<EOF
alpha: some-url - ✔ Connected
beta: some-url - ✗ Failed
EOF'
    write_claude_json '["beta"]'

    run "$SL_DIR/mcp-status.sh" "$PROJECT_CWD" "$CACHE"

    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '1\t1\t')" ]
}

@test "result is cached — second call does not re-invoke claude" {
    write_stub claude 'cat <<EOF
alpha: some-url - ✔ Connected
EOF'
    write_claude_json '[]'

    run "$SL_DIR/mcp-status.sh" "$PROJECT_CWD" "$CACHE"
    [ "$output" = "$(printf '1\t1\t')" ]

    # Replace the stub with one that would produce a different result if invoked again.
    write_stub claude 'cat <<EOF
alpha: some-url - ✗ Failed
EOF'

    run "$SL_DIR/mcp-status.sh" "$PROJECT_CWD" "$CACHE"
    [ "$output" = "$(printf '1\t1\t')" ]
}

@test "missing cwd or cache_base fails fast with zeroed output" {
    run "$SL_DIR/mcp-status.sh" "" "$CACHE"
    [ "$status" -eq 1 ]

    run "$SL_DIR/mcp-status.sh" "$PROJECT_CWD" ""
    [ "$status" -eq 1 ]
}

@test "a momentarily unparseable ~/.claude.json is retried instead of treated as nothing disabled" {
    # ~/.claude.json is rewritten by Claude Code itself during a session, so a read can land
    # mid-write. Simulate that: the first two jq calls against it see truncated/invalid JSON,
    # the third sees the real file — the script must retry rather than cache a false "enabled".
    write_stub claude 'cat <<EOF
alpha: some-url - ✔ Connected
beta: some-url - ✔ Connected
EOF'
    write_claude_json '["beta"]'

    attempt_counter="$CACHE/jq-attempts"
    echo 0 > "$attempt_counter"
    real_jq=$(command -v jq)
    write_stub jq "
n=\$(cat '$attempt_counter')
n=\$((n+1))
echo \"\$n\" > '$attempt_counter'
if [[ \"\$*\" == *'.claude.json'* && \$n -lt 3 ]]; then
  exit 1
fi
exec '$real_jq' \"\$@\"
"

    run "$SL_DIR/mcp-status.sh" "$PROJECT_CWD" "$CACHE"

    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '1\t1\t')" ]
}

@test "a persistently unparseable ~/.claude.json (all retries fail) does not poison the cache" {
    # If every retry fails, the script must NOT write a guessed result to disk — otherwise
    # a bad snapshot would freeze for cache_max seconds. It should fall back to zero counts
    # (no prior cache exists yet) and leave no cache file behind, so the next render retries fresh.
    write_stub claude 'cat <<EOF
alpha: some-url - ✔ Connected
EOF'
    write_claude_json '[]'
    real_jq=$(command -v jq)
    write_stub jq "if [[ \"\$*\" == *'.claude.json'* ]]; then exit 1; fi; exec '$real_jq' \"\$@\""

    run "$SL_DIR/mcp-status.sh" "$PROJECT_CWD" "$CACHE"

    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '0\t0\t')" ]
    [ ! -f "$CACHE/mcp-status.json" ]
}
