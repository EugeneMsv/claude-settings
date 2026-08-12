
# confluence-page-editor scripts

Read/write Confluence pages via the REST API directly, bypassing the
Atlassian MCP's size-capped tool results and its lack of optimistic-locking
support. See `../SKILL.md` for the full workflow these scripts fit into —
this README covers setup and the scripts themselves in more depth.

## Setup

All scripts read Atlassian credentials from a `.env` file in this same
directory (`scripts/.env`), which is **not tracked in git** (see
`~/.claude/.gitignore`'s `**/.env` rule — applies repo-wide, including inside
`skills/`).

Create it once:

```bash
cat > ~/.claude/skills/confluence-page-editor/scripts/.env << 'EOF'
ATLASSIAN_EMAIL="you@yourcompany.com"
ATLASSIAN_TOKEN="your-personal-access-token"
EOF
chmod 600 ~/.claude/skills/confluence-page-editor/scripts/.env
```

Generate a token at **id.atlassian.com → Security → API tokens** (or your
org's equivalent Atlassian Cloud account settings page).

Both scripts source `.env` automatically — but only if `ATLASSIAN_TOKEN`
isn't *already* exported in your shell. An `export ATLASSIAN_TOKEN=...` in
your environment always takes precedence over the file, so you can override
per-invocation without touching `.env`.

## Why these scripts exist instead of the Atlassian MCP tools

| | MCP (`getConfluencePage`/`updateConfluencePage`) | These scripts |
|---|---|---|
| Read size limit | Tool-result envelope caps out around ~90-140KB; larger pages get dumped to a `tool-results/*.txt` file you then have to re-extract | None — streams via curl |
| Write size limit | Silently truncates or errors above ~50KB | None — streams via curl |
| Version number on read | Not exposed | Returned directly (`version.number`) |
| Concurrent-edit protection | None — you can't tell if the page changed since you read it | Optimistic locking via explicit `-v`: a stale version number gets rejected by the API instead of silently overwriting someone else's edit |

Because of the last two rows, **prefer these scripts over the MCP tools for
every read and write in this skill's workflow** (see `SKILL.md` steps 2 and
8). Only fall back to the MCP tools if the environment genuinely can't run
shell scripts / curl — and if you do, you lose the version-number safety net,
so be extra careful about re-checking the page hasn't changed before writing.

## `confluence-get.sh` — read a page

```bash
confluence-get.sh -p <pageId> -o <out-body.json>
```

Fetches the page via `GET /wiki/api/v2/pages/{id}?body-format=atlas_doc_format`,
writes the ADF body (a bare `{"type":"doc",...}` object — the same shape
`adf_tool.py` expects) to `<out-body.json>`, and prints:

```
title: <page title>
version: <current version number>
version.createdAt: <ISO timestamp of that version>
top-level nodes: <count>
wrote: <out-body.json>

NEXT VERSION TO PUSH: <version + 1>
```

**Remember the `NEXT VERSION TO PUSH` value** — that's what you pass to
`confluence-push.sh -v` later. It's the version your edit is built against;
if the live page moves past it before you push, the push will be rejected
(see "Optimistic locking" below) instead of silently clobbering whatever
changed.

Naming convention for `-o`: name the output file after the current session
(`body_<session-name-or-id>.json`) so parallel/resumed sessions don't
overwrite each other's working copy. Don't delete it when you're done — leave
it for the next turn or session to diff against or resume from.

## `confluence-push.sh` — create or update a page

```bash
# Update (recommended: explicit version)
confluence-push.sh -a update -p <pageId> -v <version> -t "<title>" \
  -f <body.json> -m "<version message>"

# Create
confluence-push.sh -a create -s <spaceId> -P <parentId> -t "<title>" \
  -f <body.json>
```

| Flag | Meaning |
|---|---|
| `-a, --action` | `create` or `update` (required) |
| `-f, --file` | path to the ADF body JSON file (required) |
| `-t, --title` | page title (required) |
| `-p, --page-id` | page ID — required for `update` |
| `-s, --space-id` | space ID — required for `create` |
| `-P, --parent-id` | parent page ID — required for `create` |
| `-v, --version` | version number for `update` (see below — omit at your own risk) |
| `-m, --message` | version message (optional) |
| `-u, --base-url` | Confluence base URL (default: `CONFLUENCE_BASE_URL` from `.env`) |

### Optimistic locking — always pass `-v`

Confluence's v2 API enforces `version.number` as an optimistic lock: the PUT
body's `version.number` must be exactly `current + 1` or the API rejects the
write with a 409-style error. There is no `If-Match`/`ETag` HTTP-header
alternative — it's purely this counter field.

- **With explicit `-v <n>`** (recommended): you pass the version your edit
  was built against, plus one — i.e. the `NEXT VERSION TO PUSH` value
  `confluence-get.sh` printed when you read the page. If someone else updated
  the page in between, the live version has moved past `n - 1`, your `n` is
  now wrong, and the push is **rejected** — exactly the protection you want.
- **Without `-v`** (omitted): the script auto-fetches "current" version *at
  push time* and blindly submits `current + 1`. This always succeeds
  version-wise, even if someone edited the page after you read it — because
  it never compares against the version you actually built your edit
  against. Your push silently overwrites their edit. Don't rely on this mode
  for anything beyond a quick one-shot page with no concurrent-edit risk.

**On rejection**, do not just retry with a bumped counter — that repeats the
same silent-overwrite risk, just one push later. Instead: re-fetch the live
page with `confluence-get.sh`, diff it against your last-known body (or at
least read what changed), and re-apply your intended edit against the new
content before pushing again.

## `adf_tool.py` — inspect, edit, validate

Operates on a local ADF body JSON file — never calls Atlassian directly
except for `fetch`, which extracts `body` from an already-saved MCP
tool-result dump (the fallback path's cleanup step, not a network call).

```bash
adf_tool.py fetch      <tool_result.txt> <out_body.json>
adf_tool.py outline    <body.json>
adf_tool.py show       <body.json> <index>
adf_tool.py next-index <body.json> [insert-at-position]
adf_tool.py validate   <body.json>
adf_tool.py fidelity   <body.json> <content_index> <md_file> <start_line> <end_line>
```

- **`outline`** — numbered list of top-level nodes, so you can target edits
  by index (also labels `extension`/`expand`/`table`/etc. node types).
- **`show`** — dump one node's full JSON.
- **`next-index`** — the next free Mermaid `guestParams.index` (every Mermaid
  diagram's extension node needs a page-wide-unique index, or multiple
  diagrams will silently render the same content — see `SKILL.md` step 6).
  Pass a second arg to also see which existing diagrams would need bumping if
  you insert new ones earlier in the document.
- **`validate`** — re-parses the ADF, lints every Mermaid block for syntax
  that breaks the macro (e.g. `classDiagram` return types with spaces), and
  checks `guestParams.index` uniqueness. Run before every push. Exit 1 = don't
  push.
- **`fidelity`** — for markdown insertions specifically (see `md_to_adf.py`
  below): diffs the plain text of a built ADF node against a markdown line
  range in the source file, using the same inline-markup parser on both
  sides, to catch accidental summarization/paraphrasing/truncation. Also
  confirms any Mermaid blocks are byte-identical to their source fence. Run
  after every `md_to_adf.py` insertion, before pushing. Exit 1 = mismatch,
  don't push.

## `md_to_adf.py` — insert verbatim markdown as new ADF content

A library, not a CLI — import `convert()` from a short driver script when you
need to insert new content from a markdown file/section into an existing
page (as opposed to editing an existing macro's `codeBlock` text in place,
which you do directly on the loaded JSON).

```python
import sys
sys.path.insert(0, "path/to/scripts")
from md_to_adf import convert, count_mermaid_blocks

with open("source.md", encoding="utf-8") as f:
    lines = f.readlines()

section = lines[29:249]  # exact line-range slice, never re-typed/summarized
n_mermaid = count_mermaid_blocks(section)
nodes = convert(section, mermaid_guest_indices=list(range(next_free_index, next_free_index + n_mermaid)))

# splice `nodes` into body['content'] wherever it belongs, e.g.:
body["content"][target_index]["content"] = nodes
```

Supports: ATX headings, paragraphs (soft-wrapped lines joined by a single
space — matches how markdown itself renders soft line breaks), bullet lists
(with indented continuation lines folded in), pipe tables (header row +
`|---|---|` separator + body rows), inline `` `code` ``/`**bold**`/`*italic*`
(correctly nested, and a literal `*`/`` ` `` inside a code span like
`` `granular_*` `` is never mistaken for markup), and fenced ` ```mermaid `
blocks (emitted as real extension+expand macro pairs, not inert code).

**Not handled**: ordered lists, nested/multi-level bullet lists, links,
images, block quotes, setext headings, multi-line table cells. Extend
`convert()`'s loop if you need these.

Always pass an **exact line-range slice of the source file's raw lines** —
never a re-typed or paraphrased copy — and run `adf_tool.py fidelity`
afterward to prove it.

## Tests

```bash
python3 scripts/tests/run_tests.py
```

Regression suite covering `md_to_adf.py` (inline mark parsing, table/bullet
list/mermaid conversion, no-content-dropped fidelity), `adf_tool.py` (CLI
subcommands run as real subprocesses: `outline`, `validate` — including the
duplicate-`guestParams.index` failure case, `next-index`, `fidelity` —
including both a passing and a deliberately-tampered case), and the
argument-validation error paths of both shell scripts (missing page id,
missing credentials, missing base URL) plus a guard that neither script has
any org-specific hardcoded default. No network calls — safe to run anytime.
Live network behavior (auth, actual GET/PUT against a real page) is only
verified manually, per the Troubleshooting section below.

Run this after modifying any script in this directory, before relying on it
for a real edit.

## Troubleshooting

- **"ATLASSIAN_EMAIL/ATLASSIAN_TOKEN not set"** — `.env` is missing, empty,
  or you haven't generated a token yet. See Setup above.
- **Push rejected with a version error** — someone else edited the page (or
  you're reusing a stale version number from an earlier turn). Re-fetch with
  `confluence-get.sh`, review what changed, reapply your edit, push again.
- **"file is not an ADF doc"** from `adf_tool.py`** — you passed it a raw MCP
  tool-result envelope instead of the extracted `body`. Run `adf_tool.py
  fetch` first (or use `confluence-get.sh`, which writes the extracted body
  directly).
- **Diagrams all show the same content after a push** — two or more Mermaid
  extension nodes share a `guestParams.index`. Run `adf_tool.py validate` (it
  flags this) and `adf_tool.py next-index` to get correct values.
- **Inserted section reads different from the source markdown** — run
  `adf_tool.py fidelity` against the exact line range you meant to insert;
  it will show the first character where built vs. source diverge.
