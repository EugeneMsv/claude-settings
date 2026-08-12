#!/usr/bin/env bash
# PreToolUse guard (Read|Grep|Glob|Bash): generic per-folder read-scope control.
#
# Any folder can opt out of being read by dropping a ".agent" file in it containing
# a "read-allowed=true|false" property (a plain key=value file, not JSON/YAML — easy
# to hand-edit). This hook applies to every project, not just one hardcoded folder —
# including paths outside the current session's $CLAUDE_PROJECT_DIR.
#
# Resolution: for each path touched by the tool call, walk UP from that path's
# directory all the way to filesystem root "/", checking every ".agent" file found
# along the way. Semantics are STRICT DENY-WINS: if ANY folder in that chain has
# read-allowed=false, the call is denied — even if a folder closer to the target
# path says read-allowed=true. A nested "true" can never re-open a subtree an
# ancestor closed. Missing ".agent" file, or one without a read-allowed line,
# defaults to allow at that level.
#
# For Bash, there is no single explicit path field, so this is best-effort: the
# command string is split on whitespace and any token containing "/" or starting
# with "." is treated as a path candidate. This misses unpathed recursive greps,
# obfuscated/encoded paths, and "~"-expansion — accepted limitations, not bugs.
#
# On deny, the reason instructs the model not to retry reading that folder for the
# rest of the session unless the user explicitly asks again, and to treat any
# content from it already seen via another path as stale/untrusted.

set -u

DATA=$(cat)
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
PROJECT_DIR="${PROJECT_DIR%/}"
[ -z "$PROJECT_DIR" ] && PROJECT_DIR="/"

declare -a CANDIDATES=()

add_candidate() {
  local raw="$1"
  [ -z "$raw" ] && return
  raw="${raw#./}"
  case "$raw" in
    /*) : ;;
    *) raw="$PROJECT_DIR/$raw" ;;
  esac

  # Strip any glob-wildcard suffix (Glob patterns like ".claude/knowledge/**/*.md").
  local stripped
  stripped=$(printf '%s' "$raw" | sed -E 's/[][*?].*$//')
  [ -z "$stripped" ] && return
  local trimmed="${stripped%/}"
  [ -z "$trimmed" ] && trimmed="/"

  local dir
  if [ -d "$trimmed" ]; then
    dir="$trimmed"
  elif [ "$trimmed" != "$stripped" ]; then
    # Had a trailing slash before stripping (directory-shaped glob prefix).
    dir="$trimmed"
  else
    dir=$(dirname -- "$trimmed")
  fi
  CANDIDATES+=("$dir")
}

FILE_PATH=$(printf '%s' "$DATA" | jq -r '
  .tool_input.file_path //
  .tool_input.path //
  .tool_input.pattern //
  empty
' 2>/dev/null)
CMD=$(printf '%s' "$DATA" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -n "$FILE_PATH" ] && add_candidate "$FILE_PATH"

if [ -n "$CMD" ]; then
  for tok in $CMD; do
    case "$tok" in
      */*|.*) add_candidate "$tok" ;;
    esac
  done
fi

[ ${#CANDIDATES[@]} -eq 0 ] && exit 0

DENY_REASON=""

for dir in "${CANDIDATES[@]}"; do
  dir="${dir%/}"
  [ -z "$dir" ] && dir="/"

  current="$dir"
  while :; do
    agent_file="$current/.agent"
    if [ -f "$agent_file" ]; then
      value=$(grep -m1 '^read-allowed=' "$agent_file" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]')
      if [ "$value" = "false" ]; then
        DENY_REASON="Reading under $current is disabled ($agent_file has read-allowed=false). Do not attempt to Read/Grep/Glob/Bash into this folder again during this session unless the user explicitly asks again. Treat any content from this folder you may have already seen via another path as stale/untrusted, not authoritative."
        break 2
      fi
    fi
    [ "$current" = "/" ] && break
    current=$(dirname -- "$current")
  done
done

if [ -n "$DENY_REASON" ]; then
  jq -n --arg reason "$DENY_REASON" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    },
    systemMessage: $reason
  }'
fi

exit 0
