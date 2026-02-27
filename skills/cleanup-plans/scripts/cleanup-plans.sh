#!/bin/bash
set -euo pipefail

# Cleanup Plans Script
# Deletes plan files older than specified age from global and project-specific locations

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Paths
readonly PLANS_DIR="${HOME}/.claude/plans"
readonly METADATA_FILE="${HOME}/.claude/plans/.metadata"
readonly PLAN_SYNC_LIB="${HOME}/.claude/hooks/plan-sync-utils.sh"

# Source shared utilities if available
if [[ -f "$PLAN_SYNC_LIB" ]]; then
  source "$PLAN_SYNC_LIB"
fi

# Logging function
log_message() {
  local level="$1"
  local message="$2"

  case "$level" in
    error)
      echo -e "${RED}ERROR: ${message}${NC}" >&2
      ;;
    info)
      echo -e "${GREEN}${message}${NC}"
      ;;
    warn)
      echo -e "${YELLOW}WARNING: ${message}${NC}" >&2
      ;;
    *)
      echo "$message"
      ;;
  esac
}

# Parse age parameter (e.g., "2w", "30d", "1m")
parse_age() {
  local age_param="$1"

  # Extract number and unit
  local number="${age_param%[wdm]}"
  local unit="${age_param: -1}"

  # Validate number
  if ! [[ "$number" =~ ^[0-9]+$ ]]; then
    log_message "error" "Invalid age format: '$age_param'. Expected format: Nw, Nd, or Nm (e.g., 2w, 30d, 1m)"
    return 1
  fi

  # Convert to days
  case "$unit" in
    w) echo $((number * 7)) ;;      # weeks to days
    d) echo "$number" ;;             # days
    m) echo $((number * 30)) ;;     # months to days (approximate)
    *)
      log_message "error" "Invalid age unit: '$unit'. Use 'w' (weeks), 'd' (days), or 'm' (months)"
      return 1
      ;;
  esac
}

# Calculate cutoff timestamp (files older than this are deleted)
calculate_cutoff() {
  local days="$1"

  # macOS compatible date command
  if [[ "$(uname)" == "Darwin" ]]; then
    date -v-"${days}d" +%s
  else
    date -d "$days days ago" +%s
  fi
}

# Get file modification time
get_mtime() {
  local file="$1"

  # macOS vs Linux compatible stat command
  if [[ "$(uname)" == "Darwin" ]]; then
    stat -f %m "$file" 2>/dev/null || echo 0
  else
    stat -c %Y "$file" 2>/dev/null || echo 0
  fi
}

# Find plans older than cutoff date
find_old_plans() {
  local cutoff_timestamp="$1"
  local old_plans=()

  # Check if plans directory exists
  if [[ ! -d "$PLANS_DIR" ]]; then
    return 0
  fi

  # Iterate through plan files
  while IFS= read -r -d '' plan_file; do
    local mtime=$(get_mtime "$plan_file")

    if [[ "$mtime" -lt "$cutoff_timestamp" ]]; then
      old_plans+=("$(basename "$plan_file")")
    fi
  done < <(find "$PLANS_DIR" -name "*.md" -type f -print0 2>/dev/null)

  # Print results (handle empty array)
  if [[ ${#old_plans[@]} -gt 0 ]]; then
    printf '%s\n' "${old_plans[@]}"
  fi
}

# Get project path for a plan from metadata
get_project_path() {
  local plan_name="$1"

  if [[ -f "$METADATA_FILE" ]]; then
    grep "^${plan_name}:" "$METADATA_FILE" 2>/dev/null | cut -d: -f2 || echo ""
  else
    echo ""
  fi
}

# Delete plan from global and project-specific locations
delete_plan() {
  local plan_name="$1"

  # Delete from global location
  local global_plan="${PLANS_DIR}/${plan_name}"
  if [[ -f "$global_plan" ]]; then
    rm -f "$global_plan"
    log_message "info" "Deleted global: ${plan_name}"
  fi

  # Delete from project-specific location
  local project_path=$(get_project_path "$plan_name")

  if [[ -n "$project_path" ]]; then
    local project_plan="${project_path}/.claude/plans/${plan_name}"

    if [[ -f "$project_plan" ]]; then
      rm -f "$project_plan"
      log_message "info" "Deleted project: ${project_plan}"
    fi
  fi

  return 0
}

# Remove deleted plans from metadata file
update_metadata() {
  local plan_name="$1"

  if [[ -f "$METADATA_FILE" ]]; then
    # Create temporary file without deleted plan entry
    grep -v "^${plan_name}:" "$METADATA_FILE" > "${METADATA_FILE}.tmp" 2>/dev/null || touch "${METADATA_FILE}.tmp"
    mv "${METADATA_FILE}.tmp" "$METADATA_FILE"
    log_message "info" "Updated metadata: removed ${plan_name}"
  fi
}

# Clean hook log entries older than cutoff timestamp
cleanup_hook_log() {
  local cutoff_timestamp="$1"
  local hook_log="${HOME}/.claude/logs/hook.log"

  # Check if log file exists
  if [[ ! -f "$hook_log" ]]; then
    log_message "debug" "Hook log not found: $hook_log"
    return 0
  fi

  log_message "info" "Cleaning hook log entries older than cutoff..."

  # Create temporary file for filtered log
  local temp_log="${hook_log}.tmp.$$"
  local original_size=$(wc -l < "$hook_log" | tr -d ' ')
  local kept_lines=0

  # Process log line by line
  while IFS= read -r line; do
    # Extract timestamp from log line format: [YYYY-MM-DD HH:MM:SS]
    if [[ "$line" =~ ^\[([0-9]{4})-([0-9]{2})-([0-9]{2})\ ([0-9]{2}):([0-9]{2}):([0-9]{2})\] ]]; then
      local year="${BASH_REMATCH[1]}"
      local month="${BASH_REMATCH[2]}"
      local day="${BASH_REMATCH[3]}"
      local hour="${BASH_REMATCH[4]}"
      local min="${BASH_REMATCH[5]}"
      local sec="${BASH_REMATCH[6]}"

      # Convert to timestamp (macOS compatible)
      if [[ "$(uname)" == "Darwin" ]]; then
        local log_timestamp=$(date -j -f "%Y-%m-%d %H:%M:%S" "${year}-${month}-${day} ${hour}:${min}:${sec}" +%s 2>/dev/null || echo 0)
      else
        local log_timestamp=$(date -d "${year}-${month}-${day} ${hour}:${min}:${sec}" +%s 2>/dev/null || echo 0)
      fi

      # Keep line if newer than cutoff
      if [[ "$log_timestamp" -ge "$cutoff_timestamp" ]]; then
        echo "$line" >> "$temp_log"
        ((kept_lines++))
      fi
    else
      # Keep lines without timestamps (edge case: continuation lines)
      echo "$line" >> "$temp_log"
      ((kept_lines++))
    fi
  done < "$hook_log"

  # Replace original log with filtered log
  mv "$temp_log" "$hook_log"

  local removed_lines=$((original_size - kept_lines))
  log_message "info" "Hook log cleaned: removed ${removed_lines} lines, kept ${kept_lines} lines"
}

# Show usage information
show_usage() {
  cat <<EOF
Usage: cleanup-plans.sh [age]

Delete plan files older than specified age from global and project-specific locations.

Age parameter format:
  Nw  - N weeks (e.g., 2w = 14 days)
  Nd  - N days (e.g., 30d = 30 days)
  Nm  - N months (e.g., 1m = 30 days)

Default: 2w (14 days)

Examples:
  cleanup-plans.sh      # Delete plans older than 2 weeks (default)
  cleanup-plans.sh 3w   # Delete plans older than 3 weeks
  cleanup-plans.sh 30d  # Delete plans older than 30 days
  cleanup-plans.sh 1m   # Delete plans older than 1 month
EOF
}

# Main execution
main() {
  local age_param="${1:-2w}"

  # Show usage if help requested
  if [[ "$age_param" == "-h" ]] || [[ "$age_param" == "--help" ]]; then
    show_usage
    exit 0
  fi

  echo "Cleanup Plans - Deleting plans older than ${age_param}"
  echo "=================================================="
  echo ""

  # Parse and validate age
  local days
  if ! days=$(parse_age "$age_param"); then
    echo ""
    show_usage
    exit 1
  fi

  # Calculate cutoff timestamp
  local cutoff
  if ! cutoff=$(calculate_cutoff "$days"); then
    log_message "error" "Failed to calculate cutoff date"
    exit 1
  fi

  # Find old plans
  local old_plans
  old_plans=$(find_old_plans "$cutoff")

  # Check if any old plans found
  if [[ -z "$old_plans" ]]; then
    log_message "info" "No plans older than ${age_param} found."
    exit 0
  fi

  # Count plans
  local count=$(echo "$old_plans" | wc -l | tr -d ' ')

  echo "Found ${count} plans older than ${age_param}:"
  echo "$old_plans"
  echo ""

  # Delete each plan
  local total_deleted=0
  while IFS= read -r plan_name; do
    if [[ -n "$plan_name" ]]; then
      delete_plan "$plan_name"
      update_metadata "$plan_name"
      ((total_deleted++))
    fi
  done <<< "$old_plans"

  echo ""
  log_message "info" "✓ Deleted ${total_deleted} plans older than ${age_param}"

  # Clean hook log entries
  echo ""
  cleanup_hook_log "$cutoff"

  # Final summary
  echo ""
  log_message "info" "Cleanup complete!"
}

# Run main function
main "$@"