#!/usr/bin/env python3
"""Compare two git refs for ticketed commits (e.g. PROJ-123) that
exist on one side but not the other.

Usage:
    release_diff.py REF_A REF_B [--repo PATH]
                     [--paths-json FILE --stack STACK --component COMPONENT]

Example:
    release_diff.py origin/release-1.0 origin/release-2.0
    release_diff.py origin/release-1.0 origin/release-2.0 \\
        --paths-json path/to/paths.json \\
        --stack STACK --component COMPONENT

Method (in order):
1. Fetch origin so refs are current.
2. If --paths-json/--stack/--component are given, resolve the component's
   path list (same stack -> component -> pathKey -> [paths] convention as
   GitLabHelper.flattenPathsByKeys in the Jenkins library, using every
   pathKey present for that component) and scope every git log/diff below
   to those paths via a trailing pathspec. A commit is kept in full (not
   split into hunks) if it touches at least one file under those paths --
   this is git's native pathspec commit-filtering behavior, not a
   line-level filter.
3. Collect ALL commits reachable from REF_A but not REF_B, and vice versa,
   restricted to the resolved paths (or unfiltered if no paths given) --
   this is the true symmetric difference within scope.
4. Compute a content patch-id (diff against first parent) for every such
   commit in ONE streamed `git log -p | git patch-id` pass per side (not one
   subprocess per commit -- that does not scale to branches with thousands
   of unrelated divergent commits), using the same path scope as step 3 so
   the patch-id set lines up with the filtered commit list. Commits present
   on both sides with the SAME patch-id are content-identical cherry-picks/
   rebases under a different hash -- and their commit message can
   legitimately differ (a cherry-picked merge commit can drop the ticket
   reference the original merge's body carried). These pairs are excluded
   entirely: the change is not actually unique to either side.
5. Extract a ticket ID (e.g. ABC-123) from each remaining commit's full
   message (subject + body, not just the subject -- GitLab often parks
   "Closes TICKET-123" in the body of a merge commit) using a generic
   [A-Z]+-\\d+ pattern -- no fixed project prefix required. If no ticket
   number is found but the message references another commit's hash (e.g.
   "cherry-pick-<hash>", "revert-<hash>"), resolve that hash's own message
   one hop to recover the ticket.
6. Within each side, group remaining commits by resolved ticket. If a group
   has both a "Merge branch ..." wrapper commit and a direct commit, keep
   only the direct commit(s) -- the merge is just a wrapper artifact.
7. Print two tables: only-in-A, only-in-B.
"""
import argparse
import json
import re
import subprocess
import sys

FIELD_SEP = "\x1f"
RECORD_SEP = "\x1e"
TICKET_RE = re.compile(r"[A-Z]+-\d+")


def run(args, repo, input_text=None):
    return subprocess.run(
        args, cwd=repo, capture_output=True, text=True, input=input_text
    )


def fetch_origin(repo):
    print("Fetching origin...", file=sys.stderr)
    result = run(["git", "fetch", "origin", "--prune"], repo)
    if result.returncode != 0:
        print(f"warning: git fetch failed: {result.stderr.strip()}", file=sys.stderr)


def load_component_paths(paths_json, stack, component):
    """Resolve stack -> component -> pathKey -> [paths] into a flat pathspec
    list, mirroring GitLabHelper.flattenPathsByKeys. Every pathKey present
    for the component is used (main/test/ci/common or whatever subset that
    component defines)."""
    with open(paths_json) as f:
        data = json.load(f)
    if stack not in data:
        print(f"error: stack '{stack}' not found in {paths_json}", file=sys.stderr)
        sys.exit(1)
    if component not in data[stack]:
        print(f"error: component '{component}' not found under stack '{stack}' in {paths_json}", file=sys.stderr)
        sys.exit(1)
    component_paths = data[stack][component]
    flattened = []
    for key in component_paths:
        flattened.extend(component_paths[key])
    return flattened


def list_commits(ref_a, ref_b, repo, paths=None):
    """Commits reachable from ref_a but not ref_b, optionally restricted to
    commits that touch at least one of `paths`."""
    fmt = f"%H{FIELD_SEP}%P{FIELD_SEP}%ad{FIELD_SEP}%an{FIELD_SEP}%s{FIELD_SEP}%B{RECORD_SEP}"
    cmd = ["git", "log", ref_a, "--not", ref_b, f"--pretty=format:{fmt}", "--date=iso-strict"]
    if paths:
        cmd.append("--")
        cmd.extend(paths)
    result = run(cmd, repo)
    if result.returncode != 0:
        print(f"error: git log failed: {result.stderr.strip()}", file=sys.stderr)
        sys.exit(1)
    commits = []
    for record in result.stdout.split(RECORD_SEP):
        record = record.strip("\n")
        if not record:
            continue
        h, parents, date, author, subject, body = record.split(FIELD_SEP, 5)
        commits.append(
            {
                "hash": h,
                "parents": parents.split(),
                "date": date,
                "author": author,
                "subject": subject,
                "message": body,
            }
        )
    return commits


def batch_patch_ids(primary_ref, other_ref, repo, total, label, paths=None):
    """Patch-id for every commit reachable from primary_ref but not
    other_ref (optionally restricted to `paths`, matching list_commits),
    computed in a single streamed pass instead of one subprocess per commit.
    --diff-merges=first-parent makes merge commits diff against their first
    parent only, so a clean merge's patch-id lines up with the equivalent
    direct/cherry-picked commit on the other branch when the change is
    truly identical.

    Reads git patch-id's output line-by-line (rather than waiting for it to
    finish) so progress can be reported every 10% of `total` commits -- this
    step is the long pole for large ranges (~3ms/commit measured), and it
    otherwise produces no output until the whole pipe drains."""
    cmd = [
        "git", "log", primary_ref, "--not", other_ref,
        "--diff-merges=first-parent", "-p", "--pretty=format:%H",
    ]
    if paths:
        cmd.append("--")
        cmd.extend(paths)
    log_proc = subprocess.Popen(cmd, cwd=repo, stdout=subprocess.PIPE)
    patchid_proc = subprocess.Popen(
        ["git", "patch-id", "--stable"], cwd=repo, stdin=log_proc.stdout,
        stdout=subprocess.PIPE, text=True,
    )
    log_proc.stdout.close()

    mapping = {}
    processed = 0
    next_threshold = 10
    for line in patchid_proc.stdout:
        parts = line.split()
        if len(parts) == 2:
            patch_id, commit_hash = parts
            mapping[commit_hash] = patch_id
        processed += 1
        if total > 0:
            pct = processed * 100 // total
            if pct >= next_threshold:
                print(
                    f"  {label}: {processed}/{total} processed ({pct}%), {total - processed} left",
                    file=sys.stderr,
                )
                while next_threshold <= pct:
                    next_threshold += 10

    patchid_proc.wait()
    log_proc.wait()
    return mapping


def resolve_ticket(message, repo, depth=0):
    m = TICKET_RE.search(message)
    if m:
        return m.group(0).upper()
    if depth >= 1:
        return None
    hash_re = re.compile(r"\b[0-9a-f]{7,40}\b")
    for candidate in hash_re.findall(message):
        result = run(["git", "log", "-1", "--format=%B", candidate], repo)
        if result.returncode == 0 and result.stdout.strip():
            resolved = resolve_ticket(result.stdout.strip(), repo, depth + 1)
            if resolved:
                return resolved
    return None


def is_merge_wrapper(subject):
    return subject.strip().lower().startswith("merge branch")


def build_side(commits, patch_ids, repo):
    """Attach patch_id + ticket to each commit."""
    for c in commits:
        c["patch_id"] = patch_ids.get(c["hash"])
        c["ticket"] = resolve_ticket(c["message"], repo)
    return commits


def dedup_cross_branch_by_patch_id(commits_a, commits_b):
    """Drop commits whose patch-id appears on both sides (content-identical
    cherry-pick/rebase under a different hash, even if the message differs)."""
    patch_ids_a = {c["patch_id"] for c in commits_a if c["patch_id"]}
    patch_ids_b = {c["patch_id"] for c in commits_b if c["patch_id"]}
    shared = patch_ids_a & patch_ids_b
    removed_a = [c for c in commits_a if c["patch_id"] in shared]
    removed_b = [c for c in commits_b if c["patch_id"] in shared]
    kept_a = [c for c in commits_a if c["patch_id"] not in shared]
    kept_b = [c for c in commits_b if c["patch_id"] not in shared]
    return kept_a, kept_b, removed_a, removed_b


def collapse_same_side_duplicates(commits):
    """Group same-side commits by resolved ticket; if a group has both a
    merge-wrapper subject and a direct-commit subject, keep only the direct
    commit(s) -- the merge is just a wrapper artifact for the same change."""
    by_ticket = {}
    untracked = []
    for c in commits:
        if c["ticket"]:
            by_ticket.setdefault(c["ticket"], []).append(c)
        else:
            untracked.append(c)
    collapsed = []
    for group in by_ticket.values():
        direct = [c for c in group if not is_merge_wrapper(c["subject"])]
        collapsed.extend(direct if direct else group)
    collapsed.extend(untracked)
    return collapsed


def filter_ticketed(commits):
    return [c for c in commits if c["ticket"]]


def print_table(title, commits):
    print(f"\n### {title} ({len(commits)} commits)\n")
    if not commits:
        print("_none_")
        return
    print("| Ticket | Hash | Date | Author | Message |")
    print("|---|---|---|---|---|")
    for c in sorted(commits, key=lambda x: x["date"], reverse=True):
        short = c["hash"][:8]
        print(f"| {c['ticket']} | `{short}` | {c['date']} | {c['author']} | {c['subject']} |")


EPILOG = """\
Examples:
  release_diff.py origin/release-1.0 origin/release-2.0
  release_diff.py origin/branch-a origin/branch-b --repo ~/dev/repo/myrepo
  release_diff.py abc1234 def5678
  release_diff.py origin/release-1.0 origin/release-2.0 \\
      --paths-json path/to/paths.json \\
      --stack STACK --component COMPONENT

Output:
  Two Markdown tables -- commits with a resolvable ticket (e.g. ABC-123)
  reachable from one ref but not the other, after removing content-identical
  cherry-picks and collapsing merge-commit wrappers down to their direct
  commit. When --paths-json/--stack/--component are given, the comparison is
  scoped to commits touching that component's paths only.
"""


def main():
    parser = argparse.ArgumentParser(
        description=__doc__,
        epilog=EPILOG,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("ref_a", help="First ref (branch name or commit hash)")
    parser.add_argument("ref_b", help="Second ref (branch name or commit hash)")
    parser.add_argument("--repo", default=".", help="Path to git repo (default: cwd)")
    parser.add_argument("--paths-json", help="Path to a paths.json file mapping stack -> component -> pathKey -> [paths]")
    parser.add_argument("--stack", help="Stack key to look up in --paths-json, e.g. Frontend")
    parser.add_argument("--component", help="Component key to look up under --stack, e.g. auth-service")
    args = parser.parse_args()

    paths_opts = [args.paths_json, args.stack, args.component]
    if any(paths_opts) and not all(paths_opts):
        parser.error("--paths-json, --stack, and --component must be given together")

    paths = None
    scope_label = ""
    if args.paths_json:
        paths = load_component_paths(args.paths_json, args.stack, args.component)
        print(f"Resolved paths for {args.stack}/{args.component}: {paths}", file=sys.stderr)
        scope_label = f" ({args.stack}/{args.component})"

    fetch_origin(args.repo)

    print(f"Collecting commits only in {args.ref_a}...", file=sys.stderr)
    only_a_raw = list_commits(args.ref_a, args.ref_b, args.repo, paths)
    print(f"Collecting commits only in {args.ref_b}...", file=sys.stderr)
    only_b_raw = list_commits(args.ref_b, args.ref_a, args.repo, paths)

    print(f"Computing patch-ids for {len(only_a_raw)} + {len(only_b_raw)} commits...", file=sys.stderr)
    patch_ids_a = batch_patch_ids(args.ref_a, args.ref_b, args.repo, len(only_a_raw), args.ref_a, paths)
    patch_ids_b = batch_patch_ids(args.ref_b, args.ref_a, args.repo, len(only_b_raw), args.ref_b, paths)
    build_side(only_a_raw, patch_ids_a, args.repo)
    build_side(only_b_raw, patch_ids_b, args.repo)

    kept_a, kept_b, removed_a, removed_b = dedup_cross_branch_by_patch_id(only_a_raw, only_b_raw)

    collapsed_a = collapse_same_side_duplicates(kept_a)
    collapsed_b = collapse_same_side_duplicates(kept_b)

    ticketed_a = filter_ticketed(collapsed_a)
    ticketed_b = filter_ticketed(collapsed_b)

    print(f"\n## Commit diff{scope_label}: {args.ref_a} vs {args.ref_b}")

    if removed_a or removed_b:
        print(
            f"\n_Excluded {len(removed_a)} commit(s) from {args.ref_a} and "
            f"{len(removed_b)} from {args.ref_b}: content-identical "
            f"(same patch-id) on both branches under different hashes._"
        )

    print_table(f"Only in {args.ref_a}", ticketed_a)
    print_table(f"Only in {args.ref_b}", ticketed_b)


if __name__ == "__main__":
    main()
