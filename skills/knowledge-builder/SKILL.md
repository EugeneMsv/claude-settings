---
name: knowledge-builder
model: sonnet
effort: xhigh
description: Build a trustworthy, source-cited knowledge document on any topic by mining Atlassian (Confluence/Jira) cross-checked against a code repo (default the current repo), date- and trust-scoring every claim, and rendering it as scannable Markdown or a rich themed HTML page with readable Mermaid diagrams. Use when the user asks to "build knowledge on <topic>", "research and document <X> from Confluence + the repo", "deep-dive into <X>", "create an AI-generated knowledge doc", or "write a sourced knowledge page about <X>".
allowed-tools: Agent, Read, Glob, Grep, Write, Edit, Bash(mkdir:*), Bash(ls:*), Bash(git:*), Bash(grep:*), Bash(python3:*), mcp__atlassian__getAccessibleAtlassianResources, mcp__atlassian__searchConfluenceUsingCql, mcp__atlassian__getConfluencePage, mcp__atlassian__getConfluencePageDescendants, mcp__atlassian__getConfluencePageFooterComments, mcp__atlassian__getConfluencePageInlineComments, mcp__atlassian__getConfluenceSpaces, mcp__atlassian__getPagesInConfluenceSpace, mcp__atlassian__search, mcp__atlassian__fetch, mcp__atlassian__searchJiraIssuesUsingJql, mcp__atlassian__getJiraIssue
---

# Knowledge Builder

Codifies a repeatable method for turning scattered Atlassian pages + repo code into a **single, source-cited, trust-scored knowledge document**. The repo is **ground truth**; Confluence is **narrative** to be verified against it. Every claim carries a dated, named link and a trust level. Output is **scannable** (bullets, tables, colored diagrams), not walls of prose.

## When to use
- "build knowledge on <topic>" / "write a sourced knowledge page about <X>"
- "research and document <X> from Confluence + the repo"
- "deep-dive into <X>" (when a general, source-cited doc is wanted — not only a cloud/topology view)
- "create an AI-generated knowledge doc"

## Inputs (confirm before starting)
- **Topic(s)** — required. The subject(s) to research.
- **Format** — required: `md` or `html`. Drives which template + rules apply (Markdown is version-control-friendly; HTML is the rich themed reading view).
- **Output path** — **ASK every run.** No default. Confirm the exact file path before writing.
- **Sources scope** — default Confluence space **<SPACE>** + the **<repo-name>** monorepo. The user may override the space key and/or the repo root per run.

If format or output path is missing, ask. If the topic has two plausible scopes, ask.

## Method

### 1. Discover (Rovo first, CQL fallback)
- **Confluence — Rovo is the primary path.** Run TWO parallel `mcp__atlassian__search` calls per topic: one as a short natural-language phrase ("how does <component> resolve <behavior>"), one as raw keywords ("<component> <behavior> <input>"). Merge results. See `references/search-strategy.md` for the query patterns.
- **Repo — discover in parallel.** Launch `deep-researcher` subagents (the default discovery agent) to investigate the monorepo for the topic (configs, source, BUILD files, IaC) — broad map first, then dig into the actual source until the mechanism is understood. Repo findings are ground truth. `deep-researcher` is read-only toward the repo (it writes only to its own memory dir) and does not spawn further agents, so scope each brief with what to research, where to look, and how deep to go. It returns a claims table with 🟢/🟡/🔴 tiers using the same trust model as this skill. Fall back to `Explore` only for a quick, shallow file/symbol locate.
- **CQL (`searchConfluenceUsingCql`) is a fallback** — use only when Rovo + repo find nothing, or when exact field filtering is needed (space, date range, assignee).
- Run repo discovery and Confluence discovery concurrently (multiple tool calls / parallel `deep-researcher` subagents).

### 2. Cross-check & resolve conflicts
- Pull **multiple** pages per sub-topic. Select by relevance **and by date** — do not blindly take the first hit.
- **Repo wins** on any conflict over live values/config (it is config-as-code).
- **Doc-vs-doc** conflict → the **most recently updated** page wins; if still unresolved, **highlight it explicitly** in the Contradictions table rather than picking silently.
- For every Confluence claim, **confirm whether code backs it**. Code-backed → stronger. Not in code → still usable but scored lower and flagged.
- Detail in `references/search-strategy.md` and `references/trust-model.md`.

### 3. Trust-score every block (3 tiers)
Apply the model in `references/trust-model.md`:
- 🟢 **Strong** — ≥2 corroborating pages, OR current-year/fresh, OR confirmed in code.
- 🟡 **Partial** — minor contradictions vs other pages/repo, or stale (~2+ years since last update).
- 🔴 **Weak** — single unconfirmed source, not found in code, and/or multiple contradictions (especially vs code).

### 4. Source every paragraph
- Every sourced claim uses **footnote-style citation**: a numbered in-text marker `[[N]](#anchor-id)` pointing into one collapsed `<details>` sources block (one source per numbered line) at the end of the section/subsection. This is the only rendering mode — see `references/citation-and-glossary.md` for the exact pattern, anchor-naming rule, and format per source type (Confluence/repo/Jira/transcript).
- Named, clickable Confluence links **with explicit dates**; `[repo] path:line` for code. Trust emoji per source.
- No unsourced assertions. Folklore is flagged 🔴.
- Expand every acronym on first use: **Full Name (ABBR)**.
- Feature Guide (FG) pages are always 🟢, even single-sourced — they are the canonical, Product-owned requirements doc (see `references/citation-and-glossary.md`).

### 5. Render (format-aware)
- **`md`** → follow `references/template-md.md`.
- **`html`** → follow `references/template-html.md` (full rich theme).
- Both follow the same section order and the readability rules in `references/presentation-and-diagrams.md`:
  - **Bullets and tables over paragraphs.** No wall-of-text.
  - **Comparisons go in tables.** Pros/cons & status use 🟢/🔴/🟡.
  - **Diagrams are a primary deliverable and must be readable** — vertical layout for many nodes, node cap (~25, else split), mandatory color with a legend, readable font, meaningful labels.

### 6. Close out
- **Contradictions & Open Items** table.
- **Consolidated References list** — every source used, deduped, with page name + date + trust + link (see `references/citation-and-glossary.md`).
- One-paragraph **Method note** (how facts were gathered + conflict resolution).

### 7. Verify before declaring done
- Confirm the output path with the user, write the file, then run the diagram verifier:
  ```bash
  python3 ~/.claude/skills/knowledge-builder/scripts/verify_mermaid.py <output-file> --strict
  ```
- Fix any errors. Address readability warnings (uncolored / horizontal-sprawl / too-many-nodes / tiny-font) before finishing.

## Hard requirements (all must hold)
1. **Verification banner is the very first thing** in the doc, defaulting to AI-generated / NOT human-verified, and **easily switchable** to human-verified (see `references/trust-model.md`).
2. **Glossary is the LAST section** (after References/Method note), as a table; acronyms are still expanded inline on first use so the body reads without the appendix.
3. **TOC** with working anchor links follows the intro (and lists the trailing Glossary).
4. **Every sourced claim uses footnote-marker + collapsed sources block** (see `references/citation-and-glossary.md`) with real, named, dated links. No unsourced claims; folklore → 🔴.
5. **Repo wins** for any live-config conflict; doc-vs-doc → newest wins or is flagged.
6. **Rovo leads; CQL is fallback.** Run dual parallel Rovo calls (phrase + keywords); use CQL only when Rovo + repo find nothing or exact field filtering is required.
7. **Atlassian access is read-only** (this skill never creates/edits/transitions Atlassian content).
8. **Scannable structure:** bullets + tables over prose; comparisons as tables; pros/cons as 🟢/🔴.
9. **Readable, colored diagrams** that pass `verify_mermaid.py --strict`.
10. **Output path is confirmed with the user** before writing; no silent default.

## Reference files
- `references/search-strategy.md` — Rovo dual-call patterns, CQL fallback, cross-checking, contradiction resolution.
- `references/trust-model.md` — the 3 trust tiers, repo-as-ground-truth, code-backing, switchable banner forms.
- `references/citation-and-glossary.md` — per-paragraph `Sources:` format, References list, glossary conventions.
- `references/presentation-and-diagrams.md` — scannability rules + diagram readability spec + color palette.
- `references/template-md.md` — Markdown output skeleton.
- `references/template-html.md` — rich HTML output skeleton.
- `scripts/verify_mermaid.py` — Mermaid validator + readability linter.
