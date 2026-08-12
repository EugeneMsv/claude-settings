#!/usr/bin/env bats
# Given a working tree in various git states, git-status.sh should print the
# correct TSV: branch, insertions, deletions, unstaged count, ahead, behind, commits.

load 'test_helper'

setup() {
    REPO="$(mktemp -d)"
    git -C "$REPO" init -q -b main
    git -C "$REPO" config user.email "test@example.com"
    git -C "$REPO" config user.name "Test"
}

teardown() {
    rm -rf "$REPO"
}

@test "non-git directory prints empty branch and zeroed fields" {
    local dir
    dir="$(mktemp -d)"

    run "$SL_DIR/git-status.sh" "$dir"

    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '\t0\t0\t0\t0\t0\t0')" ]
    rm -rf "$dir"
}

@test "no cwd argument prints empty branch and zeroed fields" {
    run "$SL_DIR/git-status.sh"

    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '\t0\t0\t0\t0\t0\t0')" ]
}

@test "clean repo on main prints branch with zeroed diff counters" {
    echo "hello" > "$REPO/a.txt"
    git -C "$REPO" add a.txt
    git -C "$REPO" commit -q -m "init"

    run "$SL_DIR/git-status.sh" "$REPO"

    [ "$status" -eq 0 ]
    [ "$output" = "$(printf 'main\t0\t0\t0\t0\t0\t0')" ]
}

@test "unstaged edits report insertions, deletions, and unstaged file count" {
    printf 'line1\nline2\nline3\n' > "$REPO/a.txt"
    git -C "$REPO" add a.txt
    git -C "$REPO" commit -q -m "init"
    # Replacing lines 2-3 with one line: git reports this as 1 insertion, 2 deletions.
    printf 'line1\nchanged\n' > "$REPO/a.txt"

    run "$SL_DIR/git-status.sh" "$REPO"

    [ "$status" -eq 0 ]
    IFS=$'\t' read -r branch ins del unstaged ahead behind commits <<< "$output"
    [ "$branch" = "main" ]
    [ "$ins" = "1" ]
    [ "$del" = "2" ]
    [ "$unstaged" = "1" ]
    [ "$ahead" = "0" ]
    [ "$behind" = "0" ]
}

@test "feature branch name is reported as branch" {
    git -C "$REPO" commit -q --allow-empty -m "init"
    git -C "$REPO" checkout -q -b feature/my-thing

    run "$SL_DIR/git-status.sh" "$REPO"

    [ "$status" -eq 0 ]
    branch="${output%%$'\t'*}"
    [ "$branch" = "feature/my-thing" ]
}

@test "commits ahead of origin/main are counted" {
    REMOTE="$(mktemp -d)"
    git -C "$REMOTE" init -q --bare -b main
    git -C "$REPO" commit -q --allow-empty -m "init"
    git -C "$REPO" remote add origin "$REMOTE"
    git -C "$REPO" push -q origin main
    git -C "$REPO" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
    # The script counts commits on the CURRENT branch since it diverged from the local
    # branch named after origin/HEAD (e.g. local "main") — so exercise it from a feature
    # branch, the representative case, rather than committing directly to main itself.
    git -C "$REPO" checkout -q -b feature/x
    git -C "$REPO" commit -q --allow-empty -m "second"
    git -C "$REPO" commit -q --allow-empty -m "third"

    run "$SL_DIR/git-status.sh" "$REPO"

    [ "$status" -eq 0 ]
    commits="${output##*$'\t'}"
    [ "$commits" = "2" ]
    rm -rf "$REMOTE"
}

@test "ahead and behind upstream are counted independently" {
    REMOTE="$(mktemp -d)"
    git -C "$REMOTE" init -q --bare -b main
    git -C "$REPO" commit -q --allow-empty -m "init"
    git -C "$REPO" remote add origin "$REMOTE"
    git -C "$REPO" push -q -u origin main

    CLONE="$(mktemp -d)"
    git clone -q "$REMOTE" "$CLONE"
    git -C "$CLONE" config user.email "test@example.com"
    git -C "$CLONE" config user.name "Test"
    git -C "$CLONE" commit -q --allow-empty -m "from clone"
    git -C "$CLONE" push -q origin main

    git -C "$REPO" commit -q --allow-empty -m "local only"
    git -C "$REPO" fetch -q origin

    run "$SL_DIR/git-status.sh" "$REPO"

    [ "$status" -eq 0 ]
    IFS=$'\t' read -r branch ins del unstaged ahead behind commits <<< "$output"
    [ "$ahead" = "1" ]
    [ "$behind" = "1" ]
    rm -rf "$REMOTE" "$CLONE"
}
