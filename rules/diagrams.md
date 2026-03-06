---
paths:
  - "**/*.md"
  - "**/*.txt"
  - "**/*.adoc"
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
