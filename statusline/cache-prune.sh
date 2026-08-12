#!/bin/bash
# cache-prune.sh — prune stale statusline cache once per day.
# A lock file guards against concurrent sessions racing the prune.
#
# Usage: cache-prune.sh <cache_root>

cache_root="$1"
[[ -z "$cache_root" ]] && cache_root="${HOME}/.claude/statusline/cache"

marker="${cache_root}/.last-prune"
lock="${cache_root}/.prune-lock"

age=$(( $(date +%s) - $(stat -f %m "$marker" 2>/dev/null || echo 0) ))
[[ "$age" -lt 86400 ]] && exit 0

now=$(date +%s)
lock_ts=$(cat "$lock" 2>/dev/null | grep -oE '^[0-9]+')
lock_age=$(( now - ${lock_ts:-0} ))

# Acquire: no lock file, or lock is >5 min old (crashed/hung session)
if [[ -f "$lock" && "$lock_age" -le 300 ]]; then
    exit 0
fi

printf '%s locked_at=%s\n' "$now" "$(date -r "$now" '+%Y-%m-%dT%H:%M:%S' 2>/dev/null)" > "$lock"

# Delete flat cache files not touched in ≥1 day (mtime +0 = older than 24h)
find "$cache_root" -maxdepth 1 -type f \
    -not -name ".last-prune" -not -name ".prune-lock" \
    -mtime +0 -delete 2>/dev/null

# Delete per-session subdirs where no file was touched in ≥1 day
find "$cache_root" -mindepth 1 -maxdepth 1 -type d | while read -r sdir; do
    newest=$(find "$sdir" -type f -mtime -1 2>/dev/null | head -1)
    [[ -z "$newest" ]] && rm -rf "$sdir" 2>/dev/null
done

touch "$marker" 2>/dev/null
rm -f "$lock" 2>/dev/null
