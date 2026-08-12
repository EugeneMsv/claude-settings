#!/usr/bin/env bats
# Given `docker compose ls`/`ps` output, docker-status.sh should only surface a project
# that (a) belongs to this repo via ConfigFiles and (b) has running containers.

load 'test_helper'

setup() {
    setup_fake_bin
    CACHE="$(mktemp -d)"
    REPO="$(mktemp -d)"
    git -C "$REPO" init -q -b main
    # docker-status.sh matches ConfigFiles against `git rev-parse --show-toplevel`, which
    # resolves symlinks (e.g. macOS /var -> /private/var) — use the same resolved path here
    # so fixture ConfigFiles values actually match what the script computes.
    REPO_RESOLVED="$(git -C "$REPO" rev-parse --show-toplevel)"
}

teardown() {
    teardown_fake_bin
    rm -rf "$CACHE" "$REPO"
}

# write_docker_stub <compose_ls_json> <compose_ps_json>
write_docker_stub() {
    local ls_json="$1" ps_json="$2"
    write_stub docker "
if [[ \"\$1 \$2\" == 'compose ls' ]]; then
  cat <<'LSEOF'
$ls_json
LSEOF
elif [[ \"\$1 \$2\" == 'compose -p' ]]; then
  :
fi
if [[ \"\$*\" == *'ps --all'* ]]; then
  cat <<'PSEOF'
$ps_json
PSEOF
fi
"
}

@test "no docker binary available prints all-empty TSV" {
    # No stub written — PATH has no docker at all in a minimal env.
    run env PATH="/usr/bin:/bin" "$SL_DIR/docker-status.sh" "$REPO" "$CACHE"

    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '\t\t\t')" ]
}

@test "no compose projects at all prints all-empty TSV" {
    write_docker_stub '[]' '[]'

    run "$SL_DIR/docker-status.sh" "$REPO" "$CACHE"

    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '\t\t\t')" ]
}

@test "project exists but belongs to a different repo is not surfaced" {
    OTHER_REPO="$(mktemp -d)"
    ls_json=$(jq -n --arg cfg "${OTHER_REPO}/docker-compose.yml" \
        '[{Name:"other-proj", Status:"running(1)", ConfigFiles:$cfg}]')
    write_docker_stub "$ls_json" '[]'

    run "$SL_DIR/docker-status.sh" "$REPO" "$CACHE"

    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '\t\t\t')" ]
    rm -rf "$OTHER_REPO"
}

@test "matching project with no running containers is not surfaced" {
    ls_json=$(jq -n --arg cfg "${REPO_RESOLVED}/docker-compose.yml" \
        '[{Name:"myproj", Status:"exited(1)", ConfigFiles:$cfg}]')
    write_docker_stub "$ls_json" '[]'

    run "$SL_DIR/docker-status.sh" "$REPO" "$CACHE"

    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '\t\t\t')" ]
}

@test "matching project with running healthy containers reports healthy status" {
    ls_json=$(jq -n --arg cfg "${REPO_RESOLVED}/docker-compose.yml" \
        '[{Name:"myproj", Status:"running(2)", ConfigFiles:$cfg}]')
    # Real `docker compose ps` CreatedAt includes a trailing tz name after the numeric
    # offset (e.g. "-0400 EDT") — the script strips that trailing field before parsing.
    ps_json=$(jq -n --arg created "$(date -v-1H '+%Y-%m-%d %H:%M:%S %z') EDT" \
        '[{State:"running", Health:"healthy", ExitCode:0, CreatedAt:$created}]')
    write_docker_stub "$ls_json" "$ps_json"

    run "$SL_DIR/docker-status.sh" "$REPO" "$CACHE"

    [ "$status" -eq 0 ]
    IFS=$'\t' read -r name status_str verdict uptime <<< "$output"
    [ "$name" = "myproj" ]
    [[ "$status_str" == *"healthy"* ]]
    [ "$verdict" = "green" ]
    [ "$uptime" = "1h" ]
}

@test "matching project with an unhealthy container reports red verdict" {
    ls_json=$(jq -n --arg cfg "${REPO_RESOLVED}/docker-compose.yml" \
        '[{Name:"myproj", Status:"running(2)", ConfigFiles:$cfg}]')
    ps_json=$(jq -n --arg created "$(date -v-5M '+%Y-%m-%d %H:%M:%S %z') EDT" \
        '[{State:"running", Health:"unhealthy", ExitCode:0, CreatedAt:$created}]')
    write_docker_stub "$ls_json" "$ps_json"

    run "$SL_DIR/docker-status.sh" "$REPO" "$CACHE"

    [ "$status" -eq 0 ]
    IFS=$'\t' read -r name status_str verdict uptime <<< "$output"
    [ "$verdict" = "red" ]
}

@test "result is cached — second call does not re-invoke docker" {
    ls_json=$(jq -n --arg cfg "${REPO_RESOLVED}/docker-compose.yml" \
        '[{Name:"myproj", Status:"running(1)", ConfigFiles:$cfg}]')
    ps_json=$(jq -n --arg created "$(date -v-1H '+%Y-%m-%d %H:%M:%S %z') EDT" \
        '[{State:"running", Health:"healthy", ExitCode:0, CreatedAt:$created}]')
    write_docker_stub "$ls_json" "$ps_json"

    run "$SL_DIR/docker-status.sh" "$REPO" "$CACHE"
    name="${output%%$'\t'*}"
    [ "$name" = "myproj" ]

    # A stub that would error/differ if actually invoked again.
    write_stub docker 'exit 1'

    run "$SL_DIR/docker-status.sh" "$REPO" "$CACHE"
    name="${output%%$'\t'*}"
    [ "$name" = "myproj" ]
}
