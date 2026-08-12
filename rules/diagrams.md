---
paths:
  - "**/*.md"
  - "**/*.txt"
  - "**/*.adoc"
  - "**/*.html"
---

# ASCII Diagram Guidelines

## Sequence Diagram Pipe Alignment

Every `|` present on any line MUST land on a target column defined by the header pipe row.

### Verification

```bash
sed -n 'START,ENDp' file | awk '{printf "%3d: ", NR+START-1; for(i=1;i<=length($0);i++){if(substr($0,i,1)=="|")printf "%d ",i};print ""}'
```

Check output against header pipe positions. A diagram is not done until all present pipes match.

### Rules

1. Target columns come from the first `|...|` row — e.g. `4 22 42 56 71`.
2. Arrow lines may omit intermediate pipes when text overflows — that is fine.
3. Arrow tip `>|` and leftward `|<---` endpoints must each land on a target column.
4. The last column is the most common misalignment — count spaces carefully.

### Fixing Misalignments

- **Off by +1** (e.g. `55` instead of `56`): remove one char before that `|` — a trailing space or one dash.
- **Off by -1** (e.g. `57` instead of `56`): add one char before that `|`.
- **Cascade**: fixing a `|` shifts all pipes to its right on the same line — compensate if those were already correct.
- **Long arrows**: `|<` + N dashes + `|` where N = (target_col - source_col - 2).

# Mermaid Diagrams

- Diagram-first: convert a table, list, or described flow into a diagram when it has 5+ rows/steps or expresses relationships/sequencing between 3+ entities. Leave short enumerative lists as text. Keep prose to captions + citations.
- Always color nodes and make text large/readable. Start each block with:
  `%%{init: {'theme':'base','themeVariables':{'fontSize':'19px','fontFamily':'arial'},'flowchart':{'nodeSpacing':50,'rankSpacing':60,'htmlLabels':true}}}%%`
- Color via `classDef name fill:#RRGGBB,stroke:#darker,color:#fff,font-size:18px;` (white text on dark fills, black on yellow); add a color legend to the doc.
- Wrap long labels with `<br/>`; quote labels containing `()/:+`.
- Design/migration diagrams classifying change impact use this fixed palette (matches your internal design-doc convention): `entry #24292f` · `decision #6b46c1` · `final #0e7490` · `unchanged #e8d9a0` (black text) · `changed #3b6ea5` · `newcode #4a8f5c` · `removed #a3474d` · `legacy #8b949e` (dashed). Classify every node relative to **current code**, not to another proposal.
- classDiagram blocks: use per-class `style`, not `classDef` (see auto-memory mermaid-classdiagram-styling).
- Validate before finishing: every block opens with a valid type (`flowchart`/`graph`/`sequenceDiagram`/`classDiagram`) and `subgraph` count equals `end` count.

## Ledger labels (module/component flow diagrams)

Default node-label style whenever a box represents a module, service, or component and the interesting content is *what happened to each of its parts*. Replaces prose-in-a-box.

1. **One box = one module.** Sub-parts (branches, cases, predicates, helper classes) are never their own box — they become lines inside the owning module's label. Exceptions: entry/final nodes, join barriers `{{ }}`, decisions `{ }`.
2. **Line 1 = module name alone.** Every following line is `item: verdict`.
3. **Colon, not em dash**, as the item/verdict separator — dashes are already doing work inside verdict text.
4. **Parallel items across branches.** The same module appearing in two branches lists the *same items in the same order*, so the branches diff line-by-line. This is the highest-value property — it turns a diagram into a comparison.
5. **Cap ~6 lines per box.** Anything past that moves to a findings/notes section below the diagram, not into the label.
6. **Verdicts are terse and concrete.** Uppercase sparingly, for the one thing that matters (`GAP:`, `NEW`, `REMOVED`, `DECISION:`).

```
PaymentGateway
card: unchanged
wallet: not reached, no token
refund: NEW retry gate
```

Before proposing a rewrite of an overfull box, offer 3–4 concrete options (minimal / cause+effect / per-item ledger / split node) rather than picking silently — density is a taste call.
