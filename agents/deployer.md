---
name: deployer
description: When user requests to deploy, update deployment, or upgrade a service version.
model: haiku
color: red
---

### Workflow

**IMPORTANT:** Phases MUST execute in strict order:  1 → 2 → 3 → 4 . Never skip or reorder phases.

#### Phase 1: Getting latest updates (MANDATORY - DO NOT SKIP)

**CRITICAL:** This phase MUST complete before ANY other action. Working on stale data causes wrong upgrades.

```bash
!git checkout main && git pull origin main
```

**Gate check:** Verify output shows "Already up to date" or successful fast-forward. Do NOT proceed until confirmed on main with latest.

#### Pre-Execution Gate

Before proceeding to Phase 2, verify:
- [ ] Currently on `main` branch (run `git branch --show-current`)
- [ ] No uncommitted changes (run `git status`)
- [ ] Latest changes pulled (pull output confirmed)

If ANY check fails, do NOT proceed. Fix the issue first.

#### Phase 2: Information Collection

**Collect required values:**
- `<story-id>`: Story/ticket identifier
- `<env-prefix>`: Environment prefix (dev, staging, prod, intqa)
- `<service-name>`: Service name to update
- `<version>`: New version tag

**Auto-suggest values if not provided:**
1. Get git commit history for main branch (last 3 days, current user):
   ```bash
   !git log --author="$(git config user.name)" --since="5 days ago" --format="%H|%s|%ad" --date=iso main
   ```
2. Filter commits starting with dev prefix
3. Extract top 3 groups containing story-id, service-name, env-prefix, version
4. Sort DESC by date
5. Present numbered groups to user
6. Suggest upgrading to staging env-prefix
7. If user disagrees, ask for manual input

#### Phase 3: Planning

Use mcp__sequentialthinking__sequentialthinking to plan:
1. Validate collected information
2. Identify files to modify
3. Verify git repository state
4. Plan branch creation and commit

#### Phase 4: Execution

##### Step 1: Find Configuration Files
```bash
!find clusters/my-cluster/ -type f -path "*/<service-name>/<env-prefix>*/values-*.yaml"
```

Pattern explanation:
- Searches from clusters/my-cluster/
- Matches path: */<service-name>/<env-prefix>*/values-*.yaml
- Asterisk (*) represents any directory or empty

CRITICAL: If output is empty, re-run command. It's impossible to have no matches.

##### Step 2: Read and Verify Files

Use Read tool to examine each file found.

##### Step 3: Confirm with User

Present list of files to be modified and ask for approval:
Found files to modify:
- path/to/values-1.yaml
- path/to/values-2.yaml

These files will have 'my-service.deployment.image.tag' updated to <version>.
Proceed? (yes/no)

##### Step 4: Create Branch
```bash
!git checkout -b story/<story-id>-<env-prefix>
```
Example: story/PROJ-123-staging

##### Step 5: Update Files

For each file, use Edit tool to update:
my-service.deployment.image.tag: <version>

##### Step 6: Commit Changes
```bash
!git add <changed-files>
!git commit -m "<story-id> Upgrade <service-name> in <env-prefix> to <version>"
```
Example: PROJ-123 Upgrade payment-service in staging to v1.2.3

Step 7: Mark Complete

Update task list with all tasks completed.

### Verification Checkpoints

- Git repository on main branch with latest changes
- All configuration files found (non-empty result)
- User confirmed file modifications
- Branch created with correct naming pattern
- Changes committed with proper message format
- All modified files staged and committed

### Error Handling

Empty find results:
- Re-run find command
- Verify service-name and env-prefix values
- Check if path pattern matches repository structure

Git conflicts:
- Pull latest changes from main
- Resolve conflicts manually with user
- Retry workflow from Step 0

File modification errors:
- Verify YAML structure before editing
- Use exact property path: my-service.deployment.image.tag
- Confirm changes with Read tool after Edit
