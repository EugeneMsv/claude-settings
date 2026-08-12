---
name: alfred-workflow-creation
description: Create or debug an Alfred (macOS) workflow that launches by a keyword, presents a list of options via a Script Filter, and opens a URL (or runs an action) when one is chosen. Covers single-stage menus, a single-fixed-URL instant launcher (no menu), AND multi-stage/cascading wizards (pick A → field clears → pick B → …) plus usage-order learning. Use when the user asks to "create/build an Alfred workflow", "make an Alfred keyword launcher", "open this URL instantly with one keyword/Enter", "multi-step / cascading Alfred menu", "fix my Alfred workflow", "why do I need to press Enter twice", build a Script Filter, or produce a `.alfredworkflow` package.
allowed-tools: Write, Read, Edit, Glob, Grep, Bash(plutil:*), Bash(zip:*), Bash(open:*), Bash(osascript:*), Bash(pgrep:*), Bash(ls:*), Bash(find:*), Bash(which:*), Bash(test:*), Bash(grep:*), Bash(cp:*), Bash(mkdir:*), Bash(uuidgen:*), Bash(/usr/bin/python3:*)
---

# Alfred Workflow Creation

Build a keyword-launched Alfred workflow: type a keyword → see a menu of options → pick one → it runs an action (commonly Open URL). The canonical primitive is a **Script Filter** feeding an **Open URL** (or other) action.

**Exception — single fixed URL, no menu, one Enter:** if the workflow always opens the *same* URL with no choices, do NOT use a Script Filter (see gotcha #10). Use the native **Keyword input** object instead — see *Single fixed-URL instant launcher* below.

An Alfred workflow is just a directory containing `info.plist` (a property list) plus any script/asset files, distributed as a `.alfredworkflow` (a renamed zip).

## When to Use

- "Create an Alfred workflow that launches by keyword X and offers options…"
- "Make a keyword launcher that opens different URLs / queries"
- "Open this one URL instantly when I type a keyword" (no menu, no options)
- "My Alfred workflow keyword doesn't work / shows Google-Amazon-Wikipedia fallbacks"
- "Package this as a `.alfredworkflow`"
- "Make a multi-step / cascading menu: pick service → environment → resource → … where each pick clears the field and shows the next list"
- "Show my most-used / recent options on top"
- "Why do I have to press Enter twice?"

## Critical gotchas (these are the whole point of this skill)

1. **`type` in the Script Filter config is the script-language selector, NOT the object type.** Valid values: `0`=bash, `1`=zsh, `8`=python3 (others: php/ruby/perl/osascript). An **invalid/out-of-range value (e.g. `9`) makes Alfred silently drop the keyword** — it won't register at all.
2. **`type` dictates how `script` is interpreted — match them or the task won't launch.** If `script` is a **shell command line** (e.g. `/usr/bin/python3 grafana.py kind`), you MUST use **`type=0`** (bash) so the shell runs that command. **`type=8` means `script` is treated as inline *Python source code*** run by Alfred's own (often unset) python — so a command line under `type=8` fails with **`Code -1 … 'launch path not accessible'`** (empty launch path). Rule of thumb: **invoking an interpreter in `script` ⇒ `type=0`.** Reserve `type=8` for when `script` literally contains Python statements. The verified `info.plist.template` uses `type=0` for exactly this reason.
3. **Symptom → diagnosis:** typing the keyword shows only the web-search **fallbacks** (Search Google/Amazon/Wikipedia) ⇒ the keyword was **never registered** (malformed input object or bad/out-of-range `type`). This is NOT a script error — a script that errors still shows the workflow row or "no results", never the fallbacks. Contrast: a menu that *appears* but errors with **`'launch path not accessible'`** is the `type`/`script` mismatch in gotcha #2, not a registration problem.
4. **Alfred runs scripts with a minimal PATH** that does NOT include `/opt/homebrew/bin` or pyenv/`~/.pyenv/shims`. A bare `python3 script.py` fails when the user's python3 is Homebrew/pyenv. **Always use an absolute interpreter path** (`/usr/bin/python3`) — and keep scripts to the stdlib so system python3 runs them.
5. **Don't set both `script` and `scriptfile`.** Pick one: inline `script` (with `scriptfile` empty) running e.g. `/usr/bin/python3 jira.py`, OR `scriptfile` set with `script` empty.
6. **Alfred normalizes `info.plist` on load** (fills in default keys) but **trusts your `type` integer verbatim** — so a bad `type` survives normalization and keeps failing.
7. **Edit the INSTALLED copy** at `~/Library/Application Support/Alfred/Alfred.alfredpreferences/workflows/user.workflow.<UUID>/info.plist`. **Quit Alfred before editing** (so it can't flush stale in-memory config over your change on exit), then **relaunch to reload**. Quit gracefully — `osascript -e 'quit app "Alfred 5"'` — never force-kill.
8. **`vitoclose` on a connection = *veto the close*, not *do close*.** `vitoclose=false` (the default) lets the Alfred window **close** after the action runs; `vitoclose=true` **keeps the window open**. The name reads backwards, so it's easy to set `true` intending "close" and get the opposite. **Symptom:** the action fires (URL opens) but the window lingers ⇒ a connection in the actioned path has `vitoclose=true`. **Rule of thumb: set `vitoclose=false` on EVERY connection** — including drill-down `SF→SF` links and terminal `SF→OpenURL` links. The known-working `gcp` multi-stage workflow uses `false` everywhere. Only set `true` if you deliberately want the window to stay up after acting.
9. **Per-item icons are set in the script's JSON, not the plist.** The plist has no per-item icon field — a Script Filter item shows a custom icon only if its JSON object carries `"icon": {"path": "<file>.png"}`, where `<file>.png` is a workflow asset (already sitting in the installed `user.workflow.<UUID>/` dir, referenced by relative filename — no subfolder). Without it, Alfred falls back to the workflow's own icon, so items often "just look right" until you add a *new* branch (like a substep menu) that needs to explicitly match a specific parent's icon. When a new substep/branch should visually inherit its parent step's icon, find that icon's filename in the workflow dir (`ls <workflow-dir>/*.png`) and set the same `"icon": {"path": ...}` on every item the substep emits — this is a **script-only edit**, no plist change or Alfred restart needed.
10. **A Script Filter for a single fixed URL causes a double-Enter requirement.** A Script Filter always renders an async results list you must select into — the first Enter can race the script's result commit and get swallowed, so the user needs a second Enter. **Symptom:** the menu/item appears correctly, selecting it works, but it takes two Enters instead of one. **Fix:** when the workflow always opens the *same* URL with no choices, skip the Script Filter (and the script) entirely — wire a native **`alfred.workflow.input.keyword`** object directly to Open URL. This fires the action on a single Enter, no list, no script. See *Single fixed-URL instant launcher*.
11. **In a Keyword input object (`alfred.workflow.input.keyword`), the bold row title is the `text` field, not `title`.** Setting `title` and leaving `text` empty renders a blank title with only the `subtext` line showing (looks like the item has no name). Always set `text` to the label you want bolded.

## Key config fields (Script Filter `config` dict)

- `keyword` — the launch word.
- `type` — script language: `0` bash, `8` python3. **For a `script` that is a command line invoking an interpreter, use `0` (bash); `8` treats `script` as inline Python source. Get this right (gotchas #1–#2).**
- `script` — inline command, e.g. `/usr/bin/python3 jira.py` (pairs with `type=0`). `scriptfile` empty.
- `argumenttype` — `0`=required, `1`=optional, `2`=none. **Use `1`** for a menu that shows on the bare keyword.
- `withspace` — `true` requires/auto-adds a trailing space; `false` triggers on the bare keyword. `false` is most forgiving for a static menu.
- `runningsubtext`, `subtext`, `title` — UI labels.

## Script Filter output (stdout JSON)

```json
{"items":[{"title":"Label","subtitle":"Detail","arg":"https://…","autocomplete":"Label"}]}
```

The selected item's `arg` flows to the connected action as `{query}`. For Open URL, set `browser` to empty string = **default browser**.

## Single fixed-URL instant launcher (no menu, one Enter)

When the workflow always opens the *same* URL with no choices — "type `litellm`, press Enter once, open the usage page" — do not build a Script Filter + script. Use a **Keyword input → Open URL** pair, wired directly:

```
objects:     [Keyword, OpenURL]
connections: Keyword → OpenURL   (vitoclose:false)
```

Keyword object `config`:

- `keyword` — the launch word (e.g. `litellm`).
- `argumenttype` — `2` (none). There's no query to capture.
- `text` — the bold row label, e.g. `LiteLLM Usage`. **Not `title`** (gotcha #11).
- `subtext` — the description line, e.g. the target URL.
- `withspace` — `false`.

Open URL object `config`:

- `url` — the **literal target URL** (not `{query}` — there's no upstream Script Filter feeding a query).
- `browser` — empty string for default browser.

No script file, no `zip -j` script bundling — just `info.plist`. This avoids gotcha #10's double-Enter entirely because there's no async results list to select into.

## Multi-stage (cascading) workflows

When the user wants discrete screens — pick A, **field clears**, pick B, field clears, … then open — **chain multiple Script Filters**, one per stage, wired output→input. (A single Script Filter with `valid:false`+`autocomplete` only drills down within the *same* query line and keeps the accumulated text visible; users who want the field to reset between stages need the chain.)

Mechanics (verified on the `gcp` workflow):

1. **One script, many filters.** Drive every stage from one script; pass the stage name as a fixed arg in each filter's `script`: `/usr/bin/python3 gcp.py service`, `… channel`, `… resource`, `… finalize`.
2. **State travels in `variables`, not the query.** Each item carries `"variables": {"svc":"auth"}`. When the item is actioned, Alfred exposes those to every downstream object as **environment variables**; session variables **accumulate** down the chain. The next stage's script reads `os.environ`.
3. **Clear the field with `arg=""`.** Non-final items set `arg=""` so the next filter opens with an empty query (looks cleared) while state rides invisibly in `variables`. Only the **final** filter sets a real `arg` (the URL) → flows to Open URL as `{query}`.
4. **Only the first filter has a `keyword`.** Downstream filters have an **empty `keyword`** — they can't be typed to directly; they fire only via the connection from the previous filter. (You *can* connect a Script Filter's output into another Script Filter's input — that is the entire mechanism.)
5. **`alfredfiltersresults: true`** on each filter lets the user type to narrow the current stage's items.

plist shape — N Script Filters + 1 action, connected in a line:

```
objects:     [SF_service, SF_channel, SF_resource, SF_finalize, OpenURL]
connections: SF_service → SF_channel → SF_resource → SF_finalize → OpenURL
```

Each `connections[<SF_n uid>] = [{destinationuid: <SF_n+1 uid>, modifiers:0, modifiersubtext:"", vitoclose:false}]`. Keep `vitoclose:false` on every link (gotcha #8). Stage-script skeleton: see `references/multistage.py`.

### Branching one menu to different downstream paths

When the FIRST menu's items must go to *different* destinations (e.g. `docs` → OpenURL directly, `repo` → a sub-menu Script Filter), do NOT add multiple connections straight off the Script Filter — Alfred fires **all** of them on any selection. Instead insert an `alfred.workflow.utility.conditional` object between the menu and the destinations, and have each menu item carry a routing var (`"variables": {"section":"docs"}`):

- The conditional's `config.conditions[]` each have a `matchstring`, `inputstring` like `{var:section}`, and a stable `uid`.
- Wire the **match** branch with `connections[<cond uid>][i].sourceoutputuid = <that condition's uid>`.
- Wire the **else** branch (the `elselabel` output) as a plain connection that **omits `sourceoutputuid` entirely** — do NOT invent a value like `"else"`, or that branch is silently dropped.
- Every conditional output link keeps `vitoclose:false`.

## Usage-order (most-used / recent on top)

Alfred reorders Script Filter results by how often/recently you action each item — **but only if the item has a stable `uid`**. No `uid` ⇒ fixed order, no learning.

- Add `"uid"` to **every** item. Make it **stable across runs** and **scoped to the prior selections** so ordering is contextual, e.g. `gcp:chan:<svc>:<channel>` learns the favorite environment *per service* (auth's top env stays independent of billing's).
- Do **not** set top-level `skipknowledge: true` — that pins your given order and disables learning.
- Knowledge is recorded when an item is **actioned** (selected) — in a chain that happens at every stage. Reset via Alfred → Preferences → Advanced → **Clear knowledge**.

## Install layout & reload semantics

- Install by copying `info.plist` + script into a fresh `…/workflows/user.workflow.<UUID>/` dir (`uuidgen` for the UUID), then relaunch Alfred. (Or `open <name>.alfredworkflow` to import via the dialog.) Keep a source copy under `.claude/<name>-alfred-workflow/` and the installed copy in sync.
- **Script-only edits need NO restart** — changing the `.py` takes effect on the next invocation. **Only `info.plist` changes** (new objects, connections, config) require quitting + relaunching Alfred. This makes iterating on menu contents/URLs fast.

## Method

1. **Decide the action.** Single fixed URL, no choices ⇒ **Keyword input → Open URL**, no script (see *Single fixed-URL instant launcher*). URL menu with choices ⇒ Script Filter whose script assembles per-option URLs (e.g. base + `urllib.parse.quote(jql)`), each item's `arg` a full URL.
2. **Write the script**, if any (skip entirely for the single-fixed-URL case) in a build dir under `.claude/` (e.g. `.claude/<name>-alfred-workflow/<name>.py`). Stdlib only. Emit the items JSON. See `references/scriptfilter.py`.
3. **Write `info.plist`** from `references/info.plist.template`: one input object (`alfred.workflow.input.keyword` for the fixed-URL case, `alfred.workflow.input.scriptfilter` for a menu) → one `alfred.workflow.action.openurl` object, wired in `connections`. Set `type`, `script` (absolute interpreter), `argumenttype`, `withspace` per the gotchas — for the Keyword case, set `text` (not `title`) per gotcha #11. **For a cascading wizard**, repeat the Script Filter object once per stage and chain the connections (see *Multi-stage*); drive all stages from one script via a stage arg, and add a `uid` per item for usage-order (see *Usage-order*).
4. **Lint:** `plutil -lint info.plist` must say `OK`.
5. **Package & install:** `zip -j <name>.alfredworkflow info.plist <name>.py` (omit the script arg for the fixed-URL case) then `open <name>.alfredworkflow` to import via Alfred's dialog.
6. **Verify the install** (if debugging): locate it under `…/workflows/user.workflow.*/`, confirm `disabled` is `false`, `keyword` is set, `type` is `0` (bash) for command-line `script`s — every filter in a chain, not just the first — and the interpreter path is absolute.

## Verification

| Claim | Check |
|-------|-------|
| Script emits valid items JSON | `/usr/bin/python3 <name>.py` prints `{"items":[…]}` |
| plist well-formed | `plutil -lint info.plist` → `OK` |
| Keyword registered | Type the keyword in Alfred → custom menu appears (NOT the Google/Amazon/Wikipedia fallbacks) |
| Action works | Select an item → URL opens in default browser |
| No `launch path not accessible` | Menu appears AND selecting runs without `Code -1 … 'launch path not accessible'` (every chained filter has `type=0` for its command-line `script`) |
| Window closes after action | Selecting a final item opens the URL **and** the Alfred window closes — if it lingers, a connection in that path has `vitoclose=true` (gotcha #8); set all to `false` |
| Substep icons match parent | If a new branch should inherit its parent step's icon, every item it emits has `"icon": {"path": "<parent's .png>"}` (gotcha #9) — check with `/usr/bin/python3 <name>.py <stage> \| grep icon` |
| Single Enter opens fixed-URL workflow | Type keyword, press Enter **once** → URL opens. If it takes two Enters, a Script Filter is in the path (gotcha #10) — replace with `alfred.workflow.input.keyword` |
| Fixed-URL item shows a real title | The bold row label is populated (not blank) — check the Keyword object's `text` field is set, not `title` (gotcha #11) |

If the keyword still shows fallbacks: quit Alfred, re-check `type` (out-of-range value drops the keyword), absolute interpreter path, `disabled=false`; relaunch Alfred.
If the menu appears but selecting errors with `'launch path not accessible'`: the `script` is a command line under `type=8` — change `type` to `0` on **every** Script Filter (gotcha #2), quit + relaunch Alfred.
If a single fixed-URL launcher needs two Enters: it's using a Script Filter — replace with `alfred.workflow.input.keyword` → Open URL (gotcha #10, see *Single fixed-URL instant launcher*).
If a Keyword-input item shows a blank title: set `text`, not `title` (gotcha #11).

## Editing / debugging an existing workflow

1. `find ~/Library/Application\ Support/Alfred -name "<scriptfile>"` to locate the install dir.
2. `osascript -e 'quit app "Alfred 5"'` (quit gracefully so it won't clobber — never force-kill).
3. Edit `info.plist` (and/or the script).
4. `plutil -lint` the plist.
5. `open "/Applications/Alfred 5.app"` to relaunch and reload.
