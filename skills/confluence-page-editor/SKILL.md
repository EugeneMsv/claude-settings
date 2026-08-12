---
name: confluence-page-editor
description: Create new Confluence pages and safely modify existing ones via the Atlassian MCP, preserving app macros (especially Mermaid diagrams) and page version history. Use when the user asks to "create a Confluence page", "update a Confluence page", "edit the design doc / wiki page", "fix the Confluence diagrams", "the Mermaid diagram stopped rendering", "my edit broke the page", or wants to change a page that contains rendered diagrams or macros.
allowed-tools: Read, Write, Edit, Bash(python3:*), Bash(mkdir:*), Bash(ls:*), Bash(*/confluence-get.sh:*), Bash(*/confluence-push.sh:*), mcp__atlassian__getAccessibleAtlassianResources, mcp__atlassian__getConfluencePage, mcp__atlassian__updateConfluencePage, mcp__atlassian__createConfluencePage, mcp__atlassian__getConfluenceSpaces, mcp__atlassian__getPagesInConfluenceSpace, mcp__atlassian__search
---

# Confluence Page Editor

Create and modify Confluence pages through the Atlassian MCP without destroying
rendered diagrams or losing version history. The central risk this skill guards
against: editing a page that contains **app macros** (Mermaid diagrams, Drawio,
etc.) through `contentFormat=markdown` silently **flattens those macros into inert
code blocks** and the diagrams stop rendering.

## Core rule

Before any edit, determine whether the page contains app macros.
- **No macros** → markdown editing is fine and simplest.
- **Any macro present** → read and write the page as `adf` ONLY. Never round-trip
  a macro page through markdown.

## Workflow: modifying an existing page

1. **Resolve the page.** Get the `pageId` from the URL or `mcp__atlassian__search`.
   (`cloudId`/`getAccessibleAtlassianResources` are only needed for other MCP
   Atlassian tools you might use alongside this — e.g. `search` — not for the
   read/write path below.)

2. **Fetch the page — prefer `confluence-get.sh` over the MCP tool.** Name the
   output file after the current session's name (the one shown in the session
   header/status, e.g. what you'd pass to `SendMessage`) so parallel or resumed
   sessions don't clobber each other's working copy — if the session has no
   name, fall back to its session id instead:
   ```bash
   ~/.claude/skills/confluence-page-editor/scripts/confluence-get.sh \
     -p <pageId> \
     -o .claude/confluence-page-editor/body_<session-name-or-id>.json
   ```
   This is the default, not a fallback — it goes straight through the REST API
   with no size limit and prints `version` in the same call, both things the
   MCP tool cannot do for you. **Note the printed `NEXT VERSION TO PUSH`
   value** — you'll pass it to `-v` at push time (step 8).

   **Only use `mcp__atlassian__getConfluencePage` (`contentFormat=adf`)** when
   `confluence-get.sh` genuinely isn't usable — e.g. no shell/curl access in
   the current environment, or the `.env` credentials aren't set up yet. If you
   do fall back to it: pages of moderate size (roughly >90KB) will make the MCP
   call itself exceed the tool's token cap, saving the result to a
   `tool-results/*.txt` file instead of returning it inline. Don't read that
   file in chunks — run
   `python3 scripts/adf_tool.py fetch <tool-results-file> <out-body.json>`
   instead, which extracts the `body` object in one step. This fallback path
   also has no version number available, so you lose the optimistic-locking
   guarantee described in step 8 — treat it as strictly worse than
   `confluence-get.sh` and switch back once possible.

   Create the `.claude/confluence-page-editor/` dir if needed. Do NOT delete
   the body file when done — leave it for the next turn/session to diff
   against or resume from; only the user prunes stale ones.

3. **Detect macros.** Scan the fetched body for `extension` / `bodiedExtension`
   nodes (`python3 scripts/adf_tool.py outline <body>.json` surfaces these
   directly in its labels). Mermaid macros appear as an `extension` node (key
   ends `.../static/mermaid-diagram`) immediately followed by an `expand` node
   containing a `codeBlock` that holds the diagram source.

4. **Choose the edit path:**
   - No macros and only prose/table changes → editing as `markdown` is acceptable.
   - Macros present → stay in ADF for the rest of this workflow.

   **If you push more than once in the same session**, re-run
   `confluence-get.sh` before building the next edit and diff it against your
   last-known body, or at minimum compare the printed `version` number. Don't
   build edit N+1 on top of a stale in-memory copy from edit N — another actor
   (or your own earlier push) may have changed the live page since.

5. **Inspect node structure** with the bundled tool:
   ```
   python3 scripts/adf_tool.py outline .claude/confluence-page-editor/body_<name>.json
   python3 scripts/adf_tool.py show    .claude/confluence-page-editor/body_<name>.json <index>
   ```

6. **Edit in place**, OR **insert new verbatim markdown content** — two different
   operations, don't conflate them:

   - **Editing an existing macro diagram**: change ONLY the text inside its
     `codeBlock`. Leave the `extension` node, every `localId`, `guestParams.index`,
     and `breakout` marks untouched. For large bodies, write a short Python script
     that loads the JSON, **asserts the target node's type and identifying text**,
     edits the one field, and dumps to a file — asserting before writing prevents
     index drift from corrupting an unrelated node.

   - **Inserting new content from a markdown file/section verbatim** (e.g. "add
     this doc's section into the page as a collapsed section"): do NOT hand-write
     ADF nodes or summarize the markdown into a paraphrased blurb — both are easy
     ways to silently drop or reword content the user expected verbatim. Use
     `scripts/md_to_adf.py`'s `convert(md_lines, mermaid_guest_indices)`, which
     parses headings, paragraphs (soft-wrapped lines joined per markdown's own
     rules), bullet lists, pipe tables, inline `code`/**bold**/*italic*, and
     ```` ```mermaid ```` fences (emitted as real extension+expand macro pairs,
     not inert code blocks) into the exact ADF node list to splice in. Pass it an
     **exact line-range slice** of the source file's raw lines — never a
     re-typed or summarized copy. See `references/adf-table-shape.md` for the
     table node shape it produces, in case you need to build one by hand instead.

   **CRITICAL when adding new mermaid blocks** (via `md_to_adf.py` or by hand):
   each mermaid `extension` node's `parameters.guestParams.index` MUST be unique
   across the page (0, 1, 2, ... in document order). This is what the Forge app
   uses to look up which diagram's source to render. If every new extension node
   shares the same index (e.g. everything left at `index: 0`), the page still
   "renders" with no visible error, but **every mermaid block displays the same
   diagram** — whichever one owns that index — instead of its own. This is silent
   and easy to miss on a quick glance; only checking each diagram individually
   reveals it. Run `python3 scripts/adf_tool.py next-index body_<name>.json
   [insert-at-position]` to get a free index (and to see which existing
   diagrams' indices need bumping if you're inserting new ones earlier in the
   document than they currently sit) instead of guessing.

7. **Validate before pushing** — never push an unseen payload:
   ```
   python3 scripts/adf_tool.py validate .claude/confluence-page-editor/body_<name>.json
   ```
   This re-parses the ADF, re-prints the outline, lints every Mermaid block for
   syntax that breaks the macro, AND checks that every mermaid extension node's
   `guestParams.index` is unique (catches the "all diagrams show the first
   diagram" bug described above). Exit code 1 means do not push.

   **If step 6 was an insertion from markdown**, also run a fidelity check —
   this is the step that catches silent summarization/truncation, which
   `validate` does not check for:
   ```
   python3 scripts/adf_tool.py fidelity .claude/confluence-page-editor/body_<name>.json \
     <content-index-of-inserted-node> <source.md> <start-line> <end-line>
   ```
   It strips markdown/ADF markup from both sides using the SAME inline parser
   `md_to_adf.py` uses to build the node (so a literal `*`/`` ` `` inside a code
   span like `` `granular_*` `` isn't mistaken for markup on either side), diffs
   the resulting plain text, and separately confirms every mermaid block is
   byte-identical to its source fence. Exit code 1 means the inserted content
   diverged from the source — do not push until resolved.

8. **Push — prefer `confluence-push.sh` over `updateConfluencePage`.**
   ```bash
   ~/.claude/skills/confluence-page-editor/scripts/confluence-push.sh \
     -a update \
     -p <pageId> \
     -t "<title>" \
     -v <version-from-confluence-get.sh + 1> \
     -f .claude/confluence-page-editor/body_<name>.json \
     -m "<version message>"
   ```
   Always pass the explicit `-v` you captured in step 2 (`NEXT VERSION TO
   PUSH`) — don't omit it and let the script auto-fetch at push time, which
   defeats the optimistic-locking check (see `scripts/README.md`). Reads auth
   from `scripts/.env`, streams the file directly via curl — no inline string
   size limit, unlike `updateConfluencePage` which silently truncates or
   errors above ~50KB. Only fall back to `updateConfluencePage` if the script
   genuinely isn't usable in the current environment (same caveat as step 2's
   MCP-read fallback) — and if you do, you have no version number to check
   against, so re-verify nothing else changed before pushing.

9. **Confirm.** Ask the user to reload and verify diagrams render. If a specific
   diagram is wrong, adjust only that macro's `codeBlock` and re-validate.

   **If the inserted content included new headings and the page has a `toc`
   macro**, and those headings ended up nested inside an `expand` node (a
   collapsed section) rather than at the top level of the page body: whether
   the TOC macro surfaces headings from inside a collapsed `expand` is NOT
   confirmed either way — check the rendered TOC after pushing rather than
   assuming either behavior.

## Workflow: creating a new page

- New page with **no diagrams** → `createConfluencePage` with `contentFormat=markdown`.
  Provide `spaceId`, `title`, and `parentId` for a child page. Save the returned `pageId`.
- New page that **needs rendered Mermaid** → the space's Mermaid macro must wrap each
  diagram. Either author as `adf` by copying the `extension`+`expand` structure from
  an existing page in the same space (to get the correct `extensionKey`), or create a
  plain page and add diagrams in the UI. A bare ```` ```mermaid ```` fence does NOT
  render unless the space renders fenced mermaid natively.

## Recovering a damaged page

The MCP tools read only the CURRENT version — there is no restore tool. If a markdown
round-trip already flattened macros into code blocks: ask the user to restore the last
good version via **••• → Page history → Restore this version**, then re-apply the
intended changes in ADF (edit macro `codeBlock` text in place). Full procedure and the
no-UI alternative are in the reference file.

## Mermaid gotchas (quick list)

- classDiagram member return types must be a single identifier — a space or hyphen
  breaks the diagram (`+record(decision) no-op` ✗ → `+record(decision)` ✓). The
  `validate` command flags these.
- Static members: trailing `$` (`+INSTANCE Foo$`).
- Flowchart label line breaks: literal `\n` inside the quoted label.
- `%%{init: ...}%%` must be the first line.

## Additional resources

- **`scripts/README.md`** — start here for the scripts. Setup (`.env`), what
  each script does, the full get → edit → push flow with optimistic locking,
  and troubleshooting.
- **`scripts/tests/run_tests.py`** — no-network regression suite for every
  script in this directory. Run after modifying any of them
  (`python3 scripts/tests/run_tests.py`), before trusting the result on a
  real page.
- **`scripts/confluence-get.sh`** — fetches a page's ADF body + version number
  directly via REST (no MCP token cap, no size limit). The preferred way to
  read a page for this skill's workflow — see step 2 above.
- **`scripts/confluence-push.sh`** — pushes an edited ADF body back via REST,
  with optimistic-locking version checking via `-v`. The preferred way to
  write a page for this skill's workflow — see step 8 above.
- **`scripts/adf_tool.py`** — `fetch` / `outline` / `show` / `next-index` /
  `validate` / `fidelity` an ADF body file. `fetch` is only needed for the
  MCP-fallback read path (step 2); `validate` lints Mermaid blocks and checks
  index uniqueness, run it before every push; `fidelity` checks an inserted
  node against its markdown source, run it after any `md_to_adf.py` insertion.
- **`scripts/md_to_adf.py`** — markdown → ADF node converter for inserting new
  verbatim content (headings, paragraphs, bullet lists, pipe tables, inline
  code/bold/italic, mermaid fences) into an existing page. Import `convert()`
  from a short driver script; see its module docstring for the exact supported
  subset and what's not handled (ordered lists, links, nested lists, etc.).
- **`references/macros-mermaid-versions.md`** — full detail on macro node structure,
  the flatten hazard, ADF editing, Mermaid syntax, and version recovery. Read it when
  a page has macros or a previous edit broke rendering.
- **`references/adf-table-shape.md`** — the exact ADF `table`/`tableRow`/
  `tableHeader`/`tableCell` node shape, reverse-engineered from a live page.
  Reference this if building a table node by hand instead of via
  `md_to_adf.py`'s `table_from_markdown_rows()`.
