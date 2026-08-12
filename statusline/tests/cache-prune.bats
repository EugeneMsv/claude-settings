#!/usr/bin/env bats
# Given a cache root with stale/fresh files and session subdirs, cache-prune.sh should
# only delete what's ≥1 day untouched, run at most once per day, and respect the lock.

load 'test_helper'

setup() {
    CACHE_ROOT="$(mktemp -d)"
}

teardown() {
    rm -rf "$CACHE_ROOT"
}

@test "no marker file — prune runs and creates the marker" {
    touch "$CACHE_ROOT/some-file.txt"

    run "$SL_DIR/cache-prune.sh" "$CACHE_ROOT"

    [ "$status" -eq 0 ]
    [ -f "$CACHE_ROOT/.last-prune" ]
}

@test "recent marker skips pruning entirely" {
    touch "$CACHE_ROOT/.last-prune"
    touch -t "$(date -v-30M '+%Y%m%d%H%M.%S')" "$CACHE_ROOT/.last-prune" 2>/dev/null || touch "$CACHE_ROOT/.last-prune"
    stale_file="$CACHE_ROOT/stale.txt"
    touch "$stale_file"
    touch -t "$(date -v-2d '+%Y%m%d%H%M.%S')" "$stale_file"

    run "$SL_DIR/cache-prune.sh" "$CACHE_ROOT"

    [ "$status" -eq 0 ]
    [ -f "$stale_file" ]
}

@test "stale flat file is deleted, fresh flat file survives" {
    touch -t "$(date -v-2d '+%Y%m%d%H%M.%S')" "$CACHE_ROOT/.last-prune" 2>/dev/null
    [ -f "$CACHE_ROOT/.last-prune" ] || { touch "$CACHE_ROOT/.last-prune"; touch -t "$(date -v-2d '+%Y%m%d%H%M.%S')" "$CACHE_ROOT/.last-prune"; }

    stale_file="$CACHE_ROOT/old.json"
    touch "$stale_file"
    touch -t "$(date -v-2d '+%Y%m%d%H%M.%S')" "$stale_file"

    fresh_file="$CACHE_ROOT/new.json"
    touch "$fresh_file"

    run "$SL_DIR/cache-prune.sh" "$CACHE_ROOT"

    [ "$status" -eq 0 ]
    [ ! -f "$stale_file" ]
    [ -f "$fresh_file" ]
}

@test "session subdir with only stale files is removed entirely" {
    touch "$CACHE_ROOT/.last-prune"
    touch -t "$(date -v-2d '+%Y%m%d%H%M.%S')" "$CACHE_ROOT/.last-prune"

    stale_session="$CACHE_ROOT/old-session-id"
    mkdir -p "$stale_session"
    touch "$stale_session/mcp-status.json"
    touch -t "$(date -v-2d '+%Y%m%d%H%M.%S')" "$stale_session/mcp-status.json"

    fresh_session="$CACHE_ROOT/new-session-id"
    mkdir -p "$fresh_session"
    touch "$fresh_session/mcp-status.json"

    run "$SL_DIR/cache-prune.sh" "$CACHE_ROOT"

    [ "$status" -eq 0 ]
    [ ! -d "$stale_session" ]
    [ -d "$fresh_session" ]
}

@test "fresh lock file blocks a concurrent prune" {
    touch "$CACHE_ROOT/.last-prune"
    touch -t "$(date -v-2d '+%Y%m%d%H%M.%S')" "$CACHE_ROOT/.last-prune"
    printf '%s locked_at=now\n' "$(date +%s)" > "$CACHE_ROOT/.prune-lock"

    stale_file="$CACHE_ROOT/old.json"
    touch "$stale_file"
    touch -t "$(date -v-2d '+%Y%m%d%H%M.%S')" "$stale_file"

    run "$SL_DIR/cache-prune.sh" "$CACHE_ROOT"

    [ "$status" -eq 0 ]
    [ -f "$stale_file" ]
}

@test "stale lock file (crashed session) is taken over and prune proceeds" {
    touch "$CACHE_ROOT/.last-prune"
    touch -t "$(date -v-2d '+%Y%m%d%H%M.%S')" "$CACHE_ROOT/.last-prune"
    old_ts=$(( $(date +%s) - 400 ))
    printf '%s locked_at=old\n' "$old_ts" > "$CACHE_ROOT/.prune-lock"

    stale_file="$CACHE_ROOT/old.json"
    touch "$stale_file"
    touch -t "$(date -v-2d '+%Y%m%d%H%M.%S')" "$stale_file"

    run "$SL_DIR/cache-prune.sh" "$CACHE_ROOT"

    [ "$status" -eq 0 ]
    [ ! -f "$stale_file" ]
    [ ! -f "$CACHE_ROOT/.prune-lock" ]
}
