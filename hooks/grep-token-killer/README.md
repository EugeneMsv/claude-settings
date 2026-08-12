# grep-token-killer

A Claude Code **PostToolUse** hook that compacts `grep` stdout before the model
sees it, to save context tokens — losslessly where possible. The dominant win is
hoisting the longest common path prefix into a single `# base:` header instead of
repeating an absolute path on every line; pathologically long lines are truncated
with a marker. Every grep seen is recorded to a JSONL audit log. When it actually
compacts, it surfaces a one-line `systemMessage` to you (not the model), e.g.
`grep-token-killer: saved 41.0% (~406 tokens, 20 lines)`; passthrough greps stay
quiet.

Measured on real deep-tree grep output: **~41% bytes** on deep `-rn`, **~61%** on
`-rln` file lists, no match dropped.

## How it works

```
stdin JSON ──▶ hook_io.parse_input ──▶ detector.decide(command)
                                            │ ineligible → log + passthrough
                                            ▼ eligible (+ctx)
                          parser.parse(stdout, ctx)  ── low confidence → passthrough
                                            ▼ confident records
                          compactor.compact ──▶ metrics ── savings<min → passthrough
                                            ▼ active mode
                          hook_io.build_updated_output ──▶ stdout JSON
                                  (every path: logger.append one JSONL record)
```

Two independent gates must **both** agree before a rewrite (defense in depth):

1. **detector** classifies the *command* — pipeline shape and grep flags.
2. **parser** re-validates the actual *output* lines; if too few conform to grep
   grammar (e.g. a count got prepended by an unrecognized pipe) it aborts.

Any exception anywhere ⇒ emit nothing ⇒ original output passes through untouched.

## Modules (one responsibility each)

| Module | Responsibility |
|--------|----------------|
| `hook.py` | Entry/orchestrator + global try/except net. Emits the saved-% `systemMessage`. |
| `config.py` | Resolve mode + thresholds: env → `config.json` → defaults. |
| `metrics.py` | `estimate_tokens` (chars/4) and `token_savings`. |
| `detector.py` | `decide(command) → Decision(eligible, reason, ctx)`. Pipeline + flag gating. |
| `parser.py` | `parse(stdout, ctx) → records[]` + confidence gate. |
| `compactor.py` | `compact(records, cfg) → (text, transforms)`. Drives `transforms/REGISTRY`, renders lines. |
| `transforms/` | One module per transform (see below), applied in `REGISTRY` order. |
| `hook_io.py` | stdin/stdout adapter; builds `updatedToolOutput`. |
| `logger.py` | Append one JSONL audit record per grep. |

## Transforms

Each compaction step is a self-contained module under `transforms/`, applied in
the order listed in `transforms/__init__.py`'s `REGISTRY`. `compactor.py` owns no
transform logic — it just runs the registry and renders the result. A transform
implements one contract:

```python
NAME = "prefix_strip"                      # label shown in CompactResult.transforms
def apply(records, cfg):                    # records: tuple of parser.Record
    ...
    return new_records, header_lines, fired # header_lines prepend above the body;
                                            # fired=True when it changed anything
```

Registered transforms:

| Order | Module | Scope | What it does |
|-------|--------|-------|--------------|
| 1 | `prefix_strip.py` | global | Finds the longest common path prefix (trimmed to the last `/`), emits one `# base: <prefix>` header, strips it from every path. Lossless. |
| 2 | `group_by_file.py` | global | For each run of ≥ 2 consecutive lines from the same file, prints the filename once as a `path:` header and indents the following lines as `  lineno:content` (path elided). Lossless — path/lineno/content are preserved on every record; only the rendering drops the repeated path. |
| 3 | `truncate.py` | per line | Caps each line's content at `line_max_output_chars`; the dropped tail becomes a marker reporting the dropped-char count and that line's own `path:lineno`. |

Order matters: `prefix_strip` runs first so downstream steps see the shortened
path; `group_by_file` then folds repeated filenames; `truncate` runs last so its
`path:lineno` hint reflects the (preserved) path even when grouping elides it from
the rendered body. To add a transform, drop a new module implementing the
contract and insert it into `REGISTRY` at the right position — nothing else changes.

**Grammar tradeoff:** `group_by_file` deliberately breaks the raw
`path:lineno:content` per-line grammar (a grouped body line is just
`  lineno:content`). This is safe because the hook's output is always terminal —
it replaces the tool result the *model* reads (PostToolUse), never re-fed into a
program that parses grep format. Grouping only fires when it saves; the output
stays fully readable and lossless. Measured on real recursive multi-file greps it
adds ~10–34% on top of `prefix_strip`, scaling with hits-per-file.

## Modes

- `active` (default) — rewrites eligible output, logs, and emits a
  `systemMessage` like `grep-token-killer: saved 41.0% (~406 tokens, 20 lines)`.
- `shadow` — never rewrites; logs would-be savings and emits a `would save …`
  `systemMessage` so you can see the impact without changing output.

The `systemMessage` is shown to you in the transcript, not sent to the model, and
only appears when a saving is realized — ineligible/passthrough greps stay quiet.

## Configuration

Precedence: environment variable → `config.json` (same dir) → default.

| Env var | config.json key | Default | Meaning |
|---------|-----------------|---------|---------|
| `GTK_MODE` | `mode` | `active` | `active` \| `shadow` |
| `GTK_LINE_MAX_OUTPUT_CHARS` | `line_max_output_chars` | `500` | Per-line: keep this many content chars; drop the rest behind a marker |
| `GTK_MIN_LINES` | `min_lines` | `3` | Skip compaction below this many matched lines |
| `GTK_MIN_SAVING_PCT` | `min_saving_pct` | `10.0` | Skip rewrite when estimated saving is smaller |

Invalid values fall back to the field default (the hook never raises on config).

## Supported vs passthrough

**Compacted:** bare `grep`, `-r`/`-R`, `-n`, `-l`/`-L` (path-only, prefix-strip
only). Pipelines with grep first followed by **any number** of grammar-preserving
stages — `head`, `tail`, `cat`, `tee`, `sort`, and trailing **filter-greps** (a
downstream `grep` carrying no output-reshaping flags, which only drops non-matching
lines), e.g. `grep -rn X dir | grep Y | head`. Compound chains too — when grep is the
**last** segment and every preceding segment is stdout-silent (`cd`, `pushd`, `popd`,
`export`, `unset`, `set`, `:`, `true`), e.g. `cd repo && grep -rn X .`; stdout is then
pure grep output.

**Passthrough (logged with reason):**
- compound operators `&&` / `||` / `;` when a non-grep segment emits stdout (`echo`,
  `sed`, …) or grep is not the last segment
- redirection to file (`>` / `>>` without `tee`)
- any grammar-breaking pipe stage after grep (`uniq`, `wc`, `awk`, `sed`, `cut`, `tr`,
  `xargs`, `column`, `nl`, `rev`, `fmt`, `fold`, `paste`, or a reshaping `grep` such as
  `grep -c`/`grep -l`) or an unknown trailing stage
- unsafe flags: `-h`, `-Z`/`--null`, `-c`/`--count`, `-o`/`--only-matching`,
  `-A`/`-B`/`-C` (context), `-b`/`--byte-offset`, `-q`/`--quiet`,
  `--color`/`--colour` unless `=never`
- low parse confidence, below `min_lines`, or saving below `min_saving_pct`
- out-of-band output (`persistedOutputPath`/`rawOutputPath` with empty stdout)

## Safety invariants

- One output line per input record (plus the optional header) — no match dropped.
- Path and line number are never truncated; only content tails are, always marked
  with the dropped-char count and that line's own `path:lineno` pointer.
- A rewrite is emitted only when it is actually smaller.

## Audit log

One JSONL record per grep at `~/.claude/feedback-loop/grep-token-killer.jsonl`:

```json
{"timestamp":"2026-06-21 14:03:01","command":"grep -rn ...","mode":"active",
 "eligible":true,"passthrough_reason":null,"original_tokens":525,
 "compacted_tokens":334,"tokens_removed":191,"pct_saved":36.4,
 "original_bytes":2101,"compacted_bytes":1336,"lines":10,
 "transforms":["prefix_strip","truncate"]}
```

## Registration

In `~/.claude/settings.json` under `hooks`:

```json
"PostToolUse": [
  { "matcher": "Bash",
    "hooks": [ { "type": "command", "if": "Bash(grep *)",
                 "command": "python3 ~/.claude/hooks/grep-token-killer/hook.py" } ] }
]
```

`if: "Bash(grep *)"` only matches commands **starting** with grep (`ls | grep`
won't trigger — acceptable; those outputs are small). Claude Code snapshots hooks
at startup, so a **session restart** is required after editing settings.

## Tests

```bash
cd ~/.claude/hooks/grep-token-killer
python3 -m unittest discover -s tests -p 'test_*.py'
```

Stdlib `unittest` only, zero dependencies. Fixtures under `tests/fixtures/` are
synthetic grep output (`-rn`/`-rln` samples, a `uniq -c`-corrupted sample that
must abort).
