# Macros, Mermaid, and Version Safety

Detailed reference for the failure modes that make Confluence page editing risky.
Consult this when a page contains app macros (Mermaid, Drawio, etc.), when diagrams
stop rendering, or when a bad edit must be recovered.

## 1. How app macros are stored in ADF

A rendered Mermaid diagram is NOT a fenced code block. It is a pair of native ADF nodes:

```json
{
  "type": "extension",
  "attrs": {
    "extensionType": "com.atlassian.ecosystem",
    "extensionKey": "<app-uuid>/.../static/mermaid-diagram",
    "parameters": { "guestParams": { "index": 1 }, ... },
    "localId": "d4bb3b78bac7"
  }
}
```

immediately followed by an `expand` node that holds the diagram SOURCE in a `codeBlock`:

```json
{
  "type": "expand",
  "attrs": { "title": "Diagram", "localId": "4432011b5776" },
  "marks": [ { "type": "breakout", "attrs": { "mode": "wide", "width": 760 } } ],
  "content": [
    {
      "type": "codeBlock",
      "attrs": { "language": "mermaid", "localId": "4aa24a17369d" },
      "content": [ { "type": "text", "text": "%%{init...}%%\nclassDiagram\n..." } ]
    }
  ]
}
```

The macro renders the diagram from the text inside that `codeBlock`. To change a
diagram, edit ONLY that text. Leave the `extension` node, every `localId`, the
`guestParams.index`, and the `breakout` mark exactly as they are.

## 2. The markdown-flatten hazard (root failure)

`getConfluencePage` / `updateConfluencePage` accept `contentFormat` of `adf`,
`markdown`, or `html`. Reading a macro page as `markdown` returns the diagram as a
plain ```` ```mermaid ```` fence and DROPS the `extension`/`expand` macro wrapper.
Writing that markdown back replaces the rendered macro with an inert code block —
the diagram silently stops rendering.

Rule: **if a page contains ANY app macro, never round-trip it through markdown.**
Read and write it as `adf`.

How to detect macros before editing: read the page as `adf` and look for
`extension`/`bodiedExtension` nodes, or read as `html` and look for
`<ac:structured-macro>` / Forge extension markers.

## 3. Editing ADF safely

1. Read page as `adf`, save the response to a local file (e.g. `.claude/confluence-page-editor/body.json`).
2. `python3 scripts/adf_tool.py outline body.json` — get a numbered node list.
3. `python3 scripts/adf_tool.py show body.json <index>` — inspect the target node
   and the macro `expand`/`codeBlock` that follows it.
4. Edit the JSON. Two ways:
   - **Programmatic (preferred for big bodies):** write a short Python script that
     loads the JSON, asserts the target node's `type` and identifying text, edits
     only the intended field, and dumps to a new file. Asserting before writing
     catches index drift. (This mirrors how the original fix was done.)
   - **By hand:** only for tiny, unambiguous changes.
5. `python3 scripts/adf_tool.py validate body.json` — re-parse, re-outline, and
   lint every Mermaid block. Exit code 1 = do not push.
6. Push with `updateConfluencePage`, `contentFormat=adf`, passing the edited body.
   Include a `versionMessage` describing the change.

Never paste a 50KB ADF payload into the update tool unseen. Build it in a file,
validate, then push.

## 4. Mermaid syntax hazards

These render fine in many editors but break the Confluence Mermaid macro:

- **classDiagram member return types must be a single identifier.** A return type
  with a space or hyphen breaks the whole diagram. The lint in `adf_tool.py` flags
  these.
  - Bad: `+record(decision) no-op`, `+decisions() empty stream`
  - Good: `+record(decision)`, `+decisions() Stream`
- **Static members** use a trailing `$`: `+INSTANCE NoOpTracer$`.
- **Node label newlines** in flowcharts use the literal escape `\n` inside the
  quoted label (`GATE{"line1\nline2"}`), which survives JSON encoding as `\\n`.
- **`init` directive** (`%%{init: {...}}%%`) must be the first line of the source.
- Keep diagram edits minimal — changing only the lines that must change reduces
  the chance of introducing a parse error elsewhere.

## 5. Version recovery when a macro page is damaged

The Atlassian MCP tools can only READ the current version — there is no
"read version N" or "restore" tool. If a markdown round-trip already flattened the
macros:

1. Ask the user to restore via the Confluence UI:
   **••• menu → Page history → version N (the last good one) → Restore this version.**
   The restored version becomes the new current version, with the original macros intact.
2. Read the restored page as `adf`.
3. Re-apply the intended edits by editing the macro `codeBlock` text in place
   (section 3), so rendering is preserved.

Alternative when the user will not use the UI: reconstruct the macro nodes directly
in ADF. This requires the app's `extensionKey` / `extensionType` (the Forge app
UUID). Get it from any surviving macro on the same page, or ask the user which
Mermaid app the space uses. This is more fragile than a UI restore.

## 6. Creating a new page

- Prefer `contentFormat=markdown` for brand-new pages with NO app macros — it is
  the simplest authoring path.
- If the new page needs rendered Mermaid, it must use the space's Mermaid macro.
  Author it as `adf` with the `extension`+`expand` pair (copy the structure from an
  existing page in the same space to get the right `extensionKey`), or create a
  plain page first and add diagrams in the UI.
- Always set `spaceId`, `title`, and (for child pages) `parentId`. Save the returned
  `pageId` for follow-up edits.
