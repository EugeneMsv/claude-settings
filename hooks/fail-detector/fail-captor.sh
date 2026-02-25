#!/bin/bash
set -euo pipefail

# PostToolUseFailure hook - receives failures with 'error' field
json=$(cat)
error_msg=$(echo "$json" | jq -r '.error // empty')

# Skip if no error (shouldn't happen in PostToolUseFailure, but defensive)
[ -z "$error_msg" ] && exit 0

log_dir="$HOME/.claude/fail-detector"
mkdir -p "$log_dir"
log_file="$log_dir/detection.jsonl"

tool_name=$(echo "$json" | jq -r '.tool_name')
command=$(echo "$json" | jq -r '.tool_input.command // .tool_input // empty')
is_interrupt=$(echo "$json" | jq -r '.is_interrupt // false')
timestamp=$(date '+%Y-%m-%d %H:%M:%S')

jq -cn \
  --arg ts "$timestamp" \
  --arg tool "$tool_name" \
  --arg cmd "$command" \
  --arg err "$error_msg" \
  --argjson interrupted "$is_interrupt" \
  '{timestamp:$ts, tool:$tool, command:$cmd, error:$err, interrupted:$interrupted}' \
  >> "$log_file"

echo "{\"systemMessage\": \"[fail-detector] Failure recorded to $log_file\"}"
