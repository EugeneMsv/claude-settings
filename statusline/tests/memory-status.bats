#!/usr/bin/env bats
# Given a project's auto-memory directory with .md entry files, memory-status.sh should
# report enabled/count/lines/newest/link — treating MEMORY.md as an index, not a memory entry.

load 'test_helper'

setup() {
    setup_fake_home
    CACHE="$(mktemp -d)"
    PROJECT_DIR="$(mktemp -d)"
    CWD_ENC=$(printf '%s' "$PROJECT_DIR" | sed 's#[/.]#-#g')
    MEM_DIR="$HOME/.claude/projects/${CWD_ENC}/memory"
    mkdir -p "$MEM_DIR"
}

teardown() {
    teardown_fake_home
    rm -rf "$CACHE" "$PROJECT_DIR"
}

write_settings() {
    local enabled="$1"
    jq -n --argjson en "$enabled" '{autoMemoryEnabled: $en}' > "$HOME/.claude/settings.json"
}

@test "memory disabled reports enabled=false" {
    write_settings false

    run "$SL_DIR/memory-status.sh" "$PROJECT_DIR" "$CACHE"

    [ "$status" -eq 0 ]
    enabled="${output%%$'\t'*}"
    [ "$enabled" = "false" ]
}

@test "no entry files reports zero count and zero lines" {
    write_settings true

    run "$SL_DIR/memory-status.sh" "$PROJECT_DIR" "$CACHE"

    [ "$status" -eq 0 ]
    IFS=$'\t' read -r enabled count lines newest link <<< "$output"
    [ "$enabled" = "true" ]
    [ "$count" = "0" ]
    [ "$lines" = "0" ]
}

@test "MEMORY.md index file is excluded from count and line sum" {
    write_settings true
    printf 'a\nb\nc\n' > "$MEM_DIR/MEMORY.md"

    run "$SL_DIR/memory-status.sh" "$PROJECT_DIR" "$CACHE"

    [ "$status" -eq 0 ]
    IFS=$'\t' read -r enabled count lines newest link <<< "$output"
    [ "$count" = "0" ]
    [ "$lines" = "0" ]
}

@test "entry files are counted and their lines summed" {
    write_settings true
    printf 'title\n' > "$MEM_DIR/MEMORY.md"
    printf 'line1\nline2\n' > "$MEM_DIR/feedback_one.md"
    printf 'line1\nline2\nline3\n' > "$MEM_DIR/project_two.md"

    run "$SL_DIR/memory-status.sh" "$PROJECT_DIR" "$CACHE"

    [ "$status" -eq 0 ]
    IFS=$'\t' read -r enabled count lines newest link <<< "$output"
    [ "$count" = "2" ]
    [ "$lines" = "5" ]
    [ "$link" = "$MEM_DIR/MEMORY.md" ]
}

@test "link falls back to memory dir when MEMORY.md is absent" {
    write_settings true
    printf 'line1\n' > "$MEM_DIR/feedback_one.md"

    run "$SL_DIR/memory-status.sh" "$PROJECT_DIR" "$CACHE"

    [ "$status" -eq 0 ]
    link="${output##*$'\t'}"
    [ "$link" = "$MEM_DIR" ]
}

@test "explicit autoMemoryDirectory overrides the derived per-project path" {
    OVERRIDE_DIR="$(mktemp -d)"
    printf 'line1\nline2\n' > "$OVERRIDE_DIR/custom.md"
    jq -n --arg dir "$OVERRIDE_DIR" '{autoMemoryEnabled: true, autoMemoryDirectory: $dir}' > "$HOME/.claude/settings.json"

    run "$SL_DIR/memory-status.sh" "$PROJECT_DIR" "$CACHE"

    [ "$status" -eq 0 ]
    IFS=$'\t' read -r enabled count lines newest link <<< "$output"
    [ "$count" = "1" ]
    [ "$lines" = "2" ]
    rm -rf "$OVERRIDE_DIR"
}

@test "result is cached — second call with a new file does not pick it up" {
    write_settings true
    printf 'line1\n' > "$MEM_DIR/feedback_one.md"

    run "$SL_DIR/memory-status.sh" "$PROJECT_DIR" "$CACHE"
    count="$(printf '%s' "$output" | cut -f2)"
    [ "$count" = "1" ]

    printf 'line1\n' > "$MEM_DIR/feedback_two.md"

    run "$SL_DIR/memory-status.sh" "$PROJECT_DIR" "$CACHE"
    count="$(printf '%s' "$output" | cut -f2)"
    [ "$count" = "1" ]
}
