#!/usr/bin/env bash
# Shared bats helpers for statusline script tests.

SL_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

# Points $HOME at an isolated temp dir so scripts never read/write real
# ~/.claude.json, ~/.claude/settings.json, or the macOS keychain.
setup_fake_home() {
    ORIG_HOME="$HOME"
    FAKE_HOME="$(mktemp -d)"
    mkdir -p "$FAKE_HOME/.claude"
    export HOME="$FAKE_HOME"
}

teardown_fake_home() {
    [[ -n "$FAKE_HOME" ]] && rm -rf "$FAKE_HOME"
    export HOME="$ORIG_HOME"
}

# Prepends a temp bin dir to PATH so tests can stub external binaries
# (claude, docker, security, curl) with write_stub below.
setup_fake_bin() {
    FAKE_BIN="$(mktemp -d)"
    export PATH="$FAKE_BIN:$PATH"
}

teardown_fake_bin() {
    [[ -n "$FAKE_BIN" ]] && rm -rf "$FAKE_BIN"
}

# write_stub <name> <shell body> — creates an executable $FAKE_BIN/<name>.
write_stub() {
    local name="$1" body="$2"
    cat > "$FAKE_BIN/$name" <<STUB
#!/bin/bash
$body
STUB
    chmod +x "$FAKE_BIN/$name"
}
