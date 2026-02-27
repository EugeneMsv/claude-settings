# Plan-Sync Hooks Troubleshooting Guide

## Overview

The plan-sync hooks automatically copy plan files from `~/.claude/plans/` to project directories when working in plan mode.

### Hook Architecture

```
~/.claude/hooks/plan-sync/
├── copy-plan-on-change.sh   # Triggered on Write/Edit tools
├── copy-plan-on-exit.sh     # Triggered on ExitPlanMode tool
├── plan-sync-utils.sh       # Shared utility functions
└── TROUBLESHOOTING.md       # This file
```

### How It Works

1. **Plan Creation/Editing**: `copy-plan-on-change.sh` syncs plan to project `.claude/plans/` directory
2. **Plan Exit**: `copy-plan-on-exit.sh` performs final sync when exiting plan mode
3. **Metadata Tracking**: `~/.claude/plans/.metadata` maps plan names to project paths
4. **Git Root Detection**: Hooks normalize paths to repository root (not subdirectories)

### Expected Behavior

- Plans sync to **git repository root** (e.g., `/path/to/repo/.claude/plans/`)
- Plans created in subdirectories sync to root, not subdirectory
- Cross-session isolation: Plan associated with Project A won't sync to Project B
- Metadata persists associations across Claude restarts

---

## Common Issues & Solutions

### Issue 1: Plans Copied to Wrong Subdirectory

**Symptom**: Plan file appears in subdirectory instead of repository root
```
❌ /path/to/repo/some/subdirectory/.claude/plans/plan.md
✅ /path/to/repo/.claude/plans/plan.md
```

**Root Cause**: Using `$cwd` instead of `$cwd_normalized` for sync destination

**Solution**: Verify hook uses normalized path
```bash
# In copy-plan-on-exit.sh:55 and similar locations
EFFECTIVE_CWD="$cwd_normalized"  # ✅ Correct
EFFECTIVE_CWD="$cwd"             # ❌ Wrong
```

**Check**: Look for "Normalized CWD" in logs
```bash
tail -f ~/.claude/logs/hook.log | grep "Normalized CWD"
```

**Files Affected**:
- `copy-plan-on-exit.sh:55`
- `copy-plan-on-change.sh` (uses `CWD_NORMALIZED` throughout)

---

### Issue 2: Undefined METADATA_FILE Variable

**Symptom**: Hook fails silently when starting Claude from invalid directory

**Root Cause**: `METADATA_FILE` variable used before initialization

**Solution**: Ensure metadata initialization happens early
```bash
# Should appear near line 40-44 in both hooks
METADATA_FILE="${HOME}/.claude/plans/.metadata"
init_metadata_file "$METADATA_FILE"
```

**Check**: Look for initialization before first usage
```bash
grep -n "METADATA_FILE" ~/.claude/hooks/plan-sync/copy-plan-on-change.sh
# First occurrence should be initialization, not usage
```

**Files Affected**: `copy-plan-on-change.sh:43-44`

---

### Issue 3: Slow Hook Execution

**Symptom**: Noticeable delay after Write/Edit operations in plan mode

**Root Cause**: `migrate_metadata_if_needed()` running on every hook invocation

**Solution**: Remove migration calls if not using old JSON format
```bash
# Remove these lines from both hooks:
migrate_metadata_if_needed  # ❌ Remove if not needed
```

**Check**: Search for migration function calls
```bash
grep "migrate_metadata" ~/.claude/hooks/plan-sync/*.sh
# Should return no results after fix
```

**Files Affected**: Both `copy-plan-on-change.sh` and `copy-plan-on-exit.sh`

---

### Issue 4: Cross-Session Plan Conflicts

**Symptom**: Plan from Project A appears in Project B

**Expected Behavior**: Hooks should skip syncing to mismatched projects

**Check Logs**: Look for skip message
```bash
tail -f ~/.claude/logs/hook.log | grep "Plan skipped"
# Expected: "Plan skipped: plan.md belongs to /project-A, not /project-B"
```

**Check Metadata**: Verify associations are correct
```bash
cat ~/.claude/plans/.metadata
# Format: plan-name.md:/absolute/path/to/project
```

**If Broken**: Plan may be incorrectly registered to wrong project
```bash
# Fix: Edit ~/.claude/plans/.metadata manually
# Update: plan-name.md:/wrong/path → plan-name.md:/correct/path
```

---

## Debugging Procedures

### Enable Debug Logging

By default, hooks only log important events (info level and above). To see all debug messages:

**Temporary (current session):**
```bash
export CLAUDE_HOOK_LOG_LEVEL=debug
claude  # Run Claude with debug logging enabled
```

**Permanent (add to ~/.zshrc or ~/.bashrc):**
```bash
export CLAUDE_HOOK_LOG_LEVEL=debug  # Always enable debug logging
```

**Log Levels:**
- `debug` - All messages including hook triggers and file checks
- `info` - Important events only (plan synced, registered, skipped) - **DEFAULT**
- `warn` - Warnings and errors
- `error` - Errors only

**Check Current Level:**
```bash
echo $CLAUDE_HOOK_LOG_LEVEL  # Empty = info (default)
```

**Example Debug Output:**
```
[2026-02-19 16:36:13] [debug] [copy-plan-on-change] Hook triggered
[2026-02-19 16:36:13] [debug] [copy-plan-on-change] Not a plan file: /path/to/file.tsx
```

**Example Info Output (default):**
```
[2026-02-19 16:36:13] [info] [copy-plan-on-change] Processing plan: FILE_PATH=...
[2026-02-19 16:36:13] [info] Plan registered: test.md -> /path/to/project
[2026-02-19 16:36:13] [info] Plan synced: test.md -> /path/to/project/.claude/plans/
```

### Step 1: Check Hook Logs

```bash
# Follow hook execution in real-time
tail -f ~/.claude/logs/hook.log

# Filter for specific hook
tail -f ~/.claude/logs/hook.log | grep "\[copy-plan-on-change\]"
tail -f ~/.claude/logs/hook.log | grep "\[copy-plan-on-exit\]"

# Look for errors
grep -i "error\|warn" ~/.claude/logs/hook.log | tail -20
```

### Step 2: Verify Metadata Associations

```bash
# View all plan-to-project mappings
cat ~/.claude/plans/.metadata

# Format: plan-name.md:/absolute/path/to/project
# Example:
# cached-jumping-mitten.md:/Users/user/Sources/my-org/my-project
# dreamy-gliding-peacock.md:/Users/user/Sources/my-org/feature-flag
```

### Step 3: Test Hook Manually

```bash
# Simulate hook input for copy-plan-on-change.sh
echo '{"file_path":"'$HOME'/.claude/plans/test.md","cwd":"'$(pwd)'"}' | \
  ~/.claude/hooks/plan-sync/copy-plan-on-change.sh

# Check logs for output
tail -10 ~/.claude/logs/hook.log
```

### Step 4: Add Debug Logging

Temporarily add debug statements to hooks:

```bash
# Add these lines after variable assignments
log_message "debug" "CWD=$CWD, CWD_NORMALIZED=$CWD_NORMALIZED"
log_message "debug" "EFFECTIVE_CWD=$EFFECTIVE_CWD"
log_message "debug" "TARGET_DIR=$TARGET_DIR"
log_message "debug" "METADATA_FILE=$METADATA_FILE"
```

Then reproduce the issue and check logs.

### Step 5: Verify Git Root Detection

```bash
# From any subdirectory in a git repo
cd /path/to/repo/some/deep/subdirectory
git rev-parse --show-toplevel
# Should output: /path/to/repo

# This is what hooks use via get_project_root()
```

---

## Key Variables Reference

| Variable | Purpose | Example |
|----------|---------|---------|
| `CWD` | Original working directory from hook input | `/path/to/repo/subdir` |
| `CWD_NORMALIZED` | Git root (normalized to absolute path) | `/path/to/repo` |
| `EFFECTIVE_CWD` | Final path used for sync destination | `/path/to/repo` |
| `METADATA_FILE` | Path to plan-to-project associations | `~/.claude/plans/.metadata` |
| `PLAN_FILENAME` | Just the plan filename (no path) | `cached-jumping-mitten.md` |
| `ASSOCIATED_PROJECT` | Project path from metadata | `/path/to/repo` |
| `TARGET_DIR` | Full destination directory path | `/path/to/repo/.claude/plans` |

---

## Expected Log Patterns

### Successful Sync

```
[2026-02-19 15:43:27] [info] [copy-plan-on-change] Processing plan: FILE_PATH=/Users/.../.claude/plans/test.md, CWD=/path/to/repo
[2026-02-19 15:43:27] [debug] [copy-plan-on-change] Plan: test.md, Normalized CWD: /path/to/repo
[2026-02-19 15:43:27] [info] Plan registered: test.md -> /path/to/repo
[2026-02-19 15:43:27] [info] Plan synced: test.md -> /path/to/repo/.claude/plans/
```

### Cross-Session Skip (Expected Behavior)

```
[2026-02-19 15:44:18] [info] [copy-plan-on-exit] Processing plan: cached-jumping-mitten.md
[2026-02-19 15:44:18] [debug] [copy-plan-on-exit] Plan already associated: cached-jumping-mitten.md -> /path/to/project-A
[2026-02-19 15:44:18] [info] [copy-plan-on-exit] Plan skipped: cached-jumping-mitten.md belongs to /path/to/project-A, not /path/to/project-B
```

### Warning Patterns

```
[2026-02-19 15:43:27] [warn] [copy-plan-on-change] Invalid CWD (/Users/.claude), checking metadata
[2026-02-19 15:43:27] [warn] [copy-plan-on-change] New plan with invalid CWD. Start Claude from project directory.
```

### Global Plan Skip

```
[2026-02-19 15:43:27] [info] [copy-plan-on-change] Global plan (in ~/.claude), skipping metadata/sync
```

---

## Recent Fixes (Feb 2026)

### Fix 1: Wrong Directory Syncing
- **Date**: 2026-02-19
- **Issue**: Plans synced to subdirectories instead of git root
- **Root Cause**: `EFFECTIVE_CWD` assigned from `$cwd` instead of `$cwd_normalized`
- **Fix**: Changed `EFFECTIVE_CWD="$cwd"` → `EFFECTIVE_CWD="$cwd_normalized"`
- **File**: `copy-plan-on-exit.sh:55`
- **Impact**: Plans from subdirectories (e.g., `my-project/packages/pages/my-feature`) now correctly sync to repo root (`my-project/`)

### Fix 2: Undefined Variable
- **Date**: 2026-02-19
- **Issue**: `METADATA_FILE` variable used before initialization, causing silent failures
- **Root Cause**: Variable initialized at line 73, but used at line 58 (when CWD is invalid)
- **Fix**: Moved initialization to line 43 (before first use at line 62)
- **File**: `copy-plan-on-change.sh:43-44`
- **Impact**: Hooks now handle invalid CWD scenarios correctly

### Fix 3: Migration Overhead
- **Date**: 2026-02-19
- **Issue**: `migrate_metadata_if_needed()` running on every hook call, causing delays
- **Root Cause**: Function checked for old JSON format file on every invocation
- **Fix**: Removed `migrate_metadata_if_needed()` calls from both hooks
- **Files**: Both `copy-plan-on-change.sh` and `copy-plan-on-exit.sh`
- **Impact**: Hooks execute faster, only use line-based metadata format
- **Note**: If you need to migrate from old JSON format, run migration manually once

---

## Verification Tests

### Test 1: Subdirectory Sync

```bash
# Start Claude from subdirectory
cd /path/to/repo/some/deep/subdirectory
claude

# Create/edit plan in plan mode, then exit

# Verify plan synced to repo root
ls -la /path/to/repo/.claude/plans/

# Should NOT exist in subdirectory
ls -la /path/to/repo/some/deep/subdirectory/.claude/plans/
# Expected: No such file or directory
```

### Test 2: Multi-Session Isolation

```bash
# Terminal 1: Project A
cd /path/to/project-A
claude
# Create plan "test-plan-A"

# Terminal 2: Project B
cd /path/to/project-B
claude
# Create plan "test-plan-B"

# Verify metadata associations
cat ~/.claude/plans/.metadata
# Should show:
# test-plan-A.md:/path/to/project-A
# test-plan-B.md:/path/to/project-B

# Verify no cross-contamination
ls /path/to/project-A/.claude/plans/  # Should only contain test-plan-A.md
ls /path/to/project-B/.claude/plans/  # Should only contain test-plan-B.md
```

### Test 3: Metadata Associations

```bash
# Check all current associations
cat ~/.claude/plans/.metadata

# Expected format:
# plan-filename.md:/absolute/path/to/project

# Verify each plan is in correct project directory
for line in $(cat ~/.claude/plans/.metadata); do
  plan=$(echo $line | cut -d: -f1)
  project=$(echo $line | cut -d: -f2)
  echo "Checking: $plan -> $project"
  ls -la "$project/.claude/plans/$plan" 2>/dev/null && echo "✓ Found" || echo "✗ Missing"
done
```

---

## Quick Reference Commands

```bash
# Watch hook activity live
tail -f ~/.claude/logs/hook.log

# Check last 50 hook events
tail -50 ~/.claude/logs/hook.log | grep -E "\[info\]|\[warn\]|\[error\]"

# View metadata associations
cat ~/.claude/plans/.metadata

# Find all synced plans
find ~ -path "*/.claude/plans/*.md" -type f 2>/dev/null

# Test hook manually
echo '{"file_path":"'$HOME'/.claude/plans/test.md","cwd":"'$(pwd)'"}' | \
  ~/.claude/hooks/plan-sync/copy-plan-on-change.sh

# Check git root from current directory
git rev-parse --show-toplevel 2>/dev/null || echo "Not in git repo"
```

---

## Future Enhancements

Potential improvements if needed:
- **Hook Testing Script**: Automated tests for all scenarios
- **Health Check Utility**: Verify all metadata associations are valid
- **Log Parser**: Extract and analyze hook execution patterns
- **Installation Guide**: Document hook setup for new systems
- **Migration Script**: One-time conversion from JSON to line-based format