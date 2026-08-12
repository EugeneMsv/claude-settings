---
paths:
  - "**/*.html"
---
# HTML Knowledge Docs

General doc rules in `rules/docs.md` also apply here (glossary, acronym expansion, TOC). HTML-specific:

- Mermaid v11 sets `width="100%"` on the rendered SVG, so CSS `max-width:none` alone still shrinks text. After `mermaid.run()`, strip the svg `width`/`height` attributes and set `svg.style.width` to its `viewBox` width — natural size + horizontal scroll on the container.
- Add a scroll hint under wide diagrams that overflow horizontally.
- Acronym glossary can be made interactive via hover tooltips (`abbr` + a floating tip), tagging prose only and skipping rendered SVG, `code`, and the glossary table itself.
