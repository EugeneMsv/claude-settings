---
paths:
  - "**/*.md"
  - "**/*.html"
---
# Documentation / Knowledge Docs

- When a paragraph enumerates 2+ distinct items/options/structures (e.g. "several contract structures: A is..., B is..., C is..."), convert it to a bulleted list with each item bolded — not a single run-on paragraph.
- Maintain a Glossary listing ALL acronyms. When it exceeds ~20 entries, group by category with subheadings.
- Also expand each acronym on first use in prose (e.g., "EPG (Electronic Program Guide)").
- Mark inferred/unverified expansions explicitly.
- Always generate a Table of Contents with anchored section links near the top.
- These rules also apply to HTML knowledge docs; for HTML-specific rendering (diagram sizing, visible Contents block, interactive tooltips) see `rules/html.md`.
- When the user reviews content in chat and then asks to save/add it to a file (especially a HUMAN-VERIFIED doc), write it byte-for-byte identical to what was displayed and approved — no paraphrasing, reformatting, or silent edits during the save step. The user's review covers exactly what they read; introducing any difference means the saved content was never actually verified. Only diverge if the user explicitly asks for a change at save time.
- Don't patch confusing content with a trailing note/caveat — fix the description directly at the point of confusion. Legacy/deprecated content must be fully isolated in its own section so the main read path never surfaces it.
