#!/bin/bash
# memory-status.sh — resolve auto-memory stats for the statusline's line 3.
#
# Aggregates the UNION of the cwd's own project memory dir and the git repo root's
# (auto memory is keyed to the repo root, but cwd is included so nothing is missed).
#
# Usage: memory-status.sh <cwd> <cache_base>
# Output (TSV): <enabled> <count> <lines> <newest_epoch> <link>

cwd="$1"
cache_base="$2"
[[ -z "$cache_base" ]] && cache_base="${HOME}/.claude/statusline/cache"
mkdir -p "$cache_base"

cache="${cache_base}/memory.json"
cache_max=120

enabled=$(jq -r '.autoMemoryEnabled // false' "${HOME}/.claude/settings.json" 2>/dev/null)
amd=$(jq -r '.autoMemoryDirectory // empty' "${HOME}/.claude/settings.json" 2>/dev/null)

# Build the set of memory dirs to aggregate (deduped)
dirs=()
if [[ -n "$amd" ]]; then
    dirs+=("${amd/#\~/$HOME}")
else
    cwd_enc=$(printf '%s' "$cwd" | sed 's#[/.]#-#g')
    dirs+=("${HOME}/.claude/projects/${cwd_enc}/memory")
    # --git-common-dir maps every worktree of a repo to the same shared .git
    common=$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
    if [[ -n "$common" ]]; then
        repo_root=$(dirname "$common")
        root_enc=$(printf '%s' "$repo_root" | sed 's#[/.]#-#g')
        root_dir="${HOME}/.claude/projects/${root_enc}/memory"
        [[ "$root_dir" != "${dirs[0]}" ]] && dirs+=("$root_dir")   # dedupe when cwd == root
    fi
fi

dirs_key=$(printf '%s:' "${dirs[@]}")

# Serve fresh cache only if computed for THIS exact set of dirs
if [[ -f "$cache" ]]; then
    c_fetched=$(jq -r '.fetched_at // 0' "$cache" 2>/dev/null)
    c_dirs=$(jq -r '.dirs // ""' "$cache" 2>/dev/null)
    now=$(date +%s)
    age=$(( now - c_fetched ))
    if [[ "$c_dirs" == "$dirs_key" && "${age:-9999}" -lt "$cache_max" ]]; then
        jq -r '[.enabled, .count, .lines, .newest, .link] | @tsv' "$cache" 2>/dev/null
        exit 0
    fi
fi

count=0 lines=0 newest=0 link_dir="" link=""
for d in "${dirs[@]}"; do
    [[ -d "$d" ]] || continue
    # Sum lines across entry files (MEMORY.md is the index, not a memory)
    for f in "$d"/*.md; do
        [[ -e "$f" ]] || continue
        [[ "${f##*/}" == "MEMORY.md" ]] && continue
        n=$(wc -l < "$f" 2>/dev/null | tr -d ' ')
        lines=$(( lines + ${n:-0} ))
        count=$(( count + 1 ))
    done
    # Newest mtime across all dirs — catches an edited entry even when MEMORY.md is untouched
    nw=$(stat -f %m "$d"/*.md 2>/dev/null | sort -nr | head -1)
    [[ -n "$nw" && "$nw" -gt "$newest" ]] && newest="$nw"
    link_dir="$d"   # last existing dir wins (git root takes precedence over cwd)
done
# Click target: the authoritative MEMORY.md (or its dir) for click-to-open
if [[ -n "$link_dir" ]]; then
    if [[ -f "$link_dir/MEMORY.md" ]]; then link="$link_dir/MEMORY.md"; else link="$link_dir"; fi
fi

jq -n --arg dirs "$dirs_key" --arg en "$enabled" --argjson c "$count" --argjson l "$lines" \
    --argjson nw "${newest:-0}" --arg lk "$link" --argjson ts "$(date +%s)" \
    '{fetched_at:$ts, dirs:$dirs, enabled:$en, count:$c, lines:$l, newest:$nw, link:$lk}' > "$cache" 2>/dev/null
printf '%s\t%s\t%s\t%s\t%s\n' "$enabled" "$count" "$lines" "${newest:-0}" "$link"
