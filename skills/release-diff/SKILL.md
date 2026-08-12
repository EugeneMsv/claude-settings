---
name: release-diff
description: This skill should be used when the user asks to "compare branches by ticket", "find commits in one branch but not another by ticket", "diff two release branches by ticket", "what tickets are only on this branch", or wants a ticket-level (not raw commit-level) comparison between two git refs.
---

# Release diff

Compare two git refs (branches or commit hashes) and report which ticketed
commits (e.g. `PROJ-123`) exist on one side but not the other.

Run the bundled script and print its output verbatim — no extra interpretation,
summarization, or reformatting of the results, EXCEPT for these two
linkifications, done by you (the skill), not the script — the script's raw
`--help` output and table text always show plain ticket IDs and short hashes:

- **Ticket IDs** (e.g. `PROJ-123`): replace with a Markdown link
  `[PROJ-123](https://<your-site>.atlassian.net/browse/PROJ-123)`.
- **Commit hashes**: replace the short hash shown in the table with a Markdown
  link to the commit on GitLab: `[abcd1234](https://<your-gitlab-host>/<namespace>/<project>/-/commit/abcd1234)`.
  Derive `<namespace>/<project>` from the repo's `origin` remote (run
  `git -C <repo> remote get-url origin` — e.g. `git@<your-gitlab-host>:group/project.git`
  maps to `group/project`). Do not guess the namespace/project if the remote can't
  be read — ask the user instead.

```bash
python3 ~/.claude/skills/release-diff/scripts/release_diff.py REF_A REF_B --repo /path/to/repo
```

- `REF_A` / `REF_B` — branch names or commit hashes.
- `--repo` — path to the git repository (default: current directory). Always pass the
  repo root explicitly when the current working directory is a subdirectory.

Ticket IDs are extracted with a generic `[A-Z]+-\d+` pattern — no fixed project
prefix is required.

## Scoping to a component via paths.json

To restrict the comparison to a specific component's paths (e.g. a repo's
`path/to/paths.json`, which maps
`stack -> component -> pathKey -> [paths]`), pass all three together:

```bash
python3 ~/.claude/skills/release-diff/scripts/release_diff.py REF_A REF_B \
  --repo /path/to/repo \
  --paths-json path/to/paths.json \
  --stack <STACK> --component <COMPONENT>
```

When given, the script resolves every pathKey present for that component
(`main`, `test`, `ci`, `common`, or whatever subset it defines) into a flat
path list, then scopes every `git log`/`git diff` to those paths via a
trailing pathspec (`-- <paths>`). A commit is kept in full if it touches at
least one file under those paths — this is git's native pathspec
commit-filtering, applied before the patch-id dedup step runs on the
narrowed commit set. Without `--paths-json`, the comparison is unscoped
(same as before).

The script fetches `origin` first, then does its own patch-id-based content
deduplication (so cherry-picks and rebases under different hashes are not
double-counted) and prints two Markdown tables directly to stdout — the
commits found only in `REF_A` and only in `REF_B`, each with ticket, hash,
date, author, and message.

Run `python3 ~/.claude/skills/release-diff/scripts/release_diff.py --help` for the full
method explanation and usage examples.
