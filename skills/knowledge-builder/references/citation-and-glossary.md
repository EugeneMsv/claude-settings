# Citation & Glossary Conventions

Two non-negotiables: **every block is sourced with real links**, and **the doc ends with a glossary** (after References, as the final section). Acronyms are still expanded inline on first use, so the trailing glossary is a reference appendix, not a prerequisite.

## Footnote sourcing — the only mode

Every sourced claim, in every section (prose, tables, checklists, Q&A lists) uses the same pattern: a numbered in-text marker `[[N]](#anchor-id)` pointing into **one collapsed sources block per section** (or per subsection when a section covers several distinct topics), placed at the end of that section/subsection. There is no separate inline `Sources:` line variant — this is the only citation rendering used.

**Why not GitHub-style `<a id>` jump-links relied on for auto-scroll:** many renderers (notably JetBrains/IntelliJ's Markdown preview) will not auto-expand a collapsed `<details>` block when a link jumps to an anchor inside it, and don't reliably resolve raw `<a id="...">` anchors outside of real headings. The anchor links are included anyway for GitHub/VS Code compatibility, but **do not rely on the collapsed block auto-expanding** — the sources are meant to be manually opened by clicking "▸ Sources", not auto-scrolled-to. Keep the collapsed block regardless (it declutters the page); just don't promise the click will visibly jump in every viewer.

Pattern — one collapsed sources block per section (or per subsection when a section is long, e.g. one block per grouped subheading):

```markdown
## N. Section Title

Some claim here.[[1]](#sN-1) Another claim, still in the same flow.[[2]](#sN-2)[[3]](#sN-3)

- A checklist item with its own claim [[1]](#sN-1)
- Another checklist item [[2]](#sN-2)[[3]](#sN-3)

<details>
<summary>📎 Sources — Section N</summary>

1. <a id="sN-1"></a>[Page Name](https://your-site.atlassian.net/wiki/spaces/SPACE/pages/12345) (May 2026) 🟢
2. <a id="sN-2"></a>[repo] `path/to/file.java:42` 🟢
3. <a id="sN-3"></a>🎙️ meeting transcript (2026-07-02) 🟡 — flagged open, not yet answered

</details>
```

Rules:
- Each source is numbered and **on its own line** inside the collapsed block — never comma/dot-separated on one line.
- In-text markers use the doubled-bracket link form `[[N]](#anchor-id)`, not raw `[^N]` footnote syntax (plain `[^N]` doesn't render as a clickable jump in most non-GitHub markdown viewers, and this doc's numbered-list form doubles as the visible reference list, so real bracket links are used instead).
- Anchor IDs must be **unique across the whole document** — prefix with a short section tag (e.g. `s1-`, `s4a-`, `s6b-`) to avoid collisions between sections/subsections that reuse `1, 2, 3...`.
- If one section has several thematically distinct claim groups (e.g. §4 Scope of Work split into Auth / Billing / Reporting subsections), give **each subsection its own collapsed sources block** rather than one giant block for the whole section — keeps the numbering local and short.
- A source cited multiple times within the same block reuses the same number (don't duplicate).
- No unsourced assertions. A claim with no backing is folklore → mark 🔴 and say "unsourced" in the collapsed block entry.
- Annotate *how* a source corroborates when it isn't obvious (short trailing note after the emoji, as in the transcript example above).

Format for each numbered entry inside the collapsed block:
- **Confluence:** `<a id="sN-k"></a>[<Page Name>](https://<your-site>.atlassian.net/wiki/spaces/<SPACE>/pages/<id>) (<date>) <🟢|🟡|🔴>`
  - Link text = the page **name**, never the raw `[SPACE 12345]` id form.
  - Date = the page's last-modified date, e.g. `(May 2024)`.
- **Repo:** `<a id="sN-k"></a>[repo] \`path/to/file:line\` <🟢|🟡|🔴>` (no URL; it is local config-as-code, normally 🟢).
- **Jira:** `<a id="sN-k"></a>[<KEY> — title](https://<your-site>.atlassian.net/browse/<KEY>) (<date>) <emoji>`.
- **Meeting transcript:** `<a id="sN-k"></a>🎙️ <short description> (<date>) <emoji>`.

## Feature Guide pages are always 🟢
Confluence pages that are the canonical Feature Guide (FG) for a project/initiative are treated as 🟢 strong by convention, even when cited only once and not independently corroborated. An FG is the authoritative requirements document reviewed and owned by Product — it does not need a second source to earn 🟢. This overrides the general "single source → 🟡" rule specifically for FG pages; still flag an FG page 🟡 if it visibly contradicts the repo or another equally authoritative source (see `trust-model.md` ground truth rule).

## Consolidated References list (end of doc)
A single deduped list of **every** source used across the doc, so a reader can audit provenance in one place.

Format (one row per unique source):
```markdown
## References
| # | Source | Type | Date | Trust |
|---|---|---|---|---|
| 1 | [Billing Service Overview](https://your-site.atlassian.net/wiki/spaces/SPACE/pages/278269712) | Confluence | May 2024 | 🟡 |
| 2 | [repo] `servlets/BillingServlet.java` | Repo | n/a | 🟢 |
| 3 | [PROJ-123 — …](https://your-site.atlassian.net/browse/PROJ-123) | Jira | 2026-03 | 🟢 |
```
- Dedupe by URL/path. If a source appeared at multiple trust levels, list the **highest** it earned and note the caveat in Contradictions.

## Glossary (at the END of the doc)
The glossary is the **last section**, placed after the References list. It is a reference appendix — do not put it near the top. A simple table:
```markdown
## Glossary
| Term | Expansion / meaning |
|---|---|
| ABBR | Full expansion of the term. |
| TERM | *(inferred)* 🔴 |
```
- Mark inferred/unconfirmed expansions with `*(inferred)*` and a 🔴.
- Because the glossary lives at the end, inline expansion on **first use** as **Full Name (ABBR)** is mandatory — the body must be readable without scrolling to the appendix.
- HTML output additionally turns glossary terms into `abbr.gloss` hover tooltips (see `template-html.md`).
