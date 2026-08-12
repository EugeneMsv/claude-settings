# Trust Model

Every block and every source carries a trust level. Score by **corroboration, freshness, and code-backing** — not by how authoritative a page *looks*.

## Ground truth rule
- The **repo is ground truth** for any live value/config (it is config-as-code).
- **Confluence is narrative.** Treat each Confluence claim as a hypothesis to confirm against code.
- On conflict: repo wins (live values) · newest page wins (doc-vs-doc) · else flag in Contradictions.

## The three tiers

| Tier | Emoji | Assign when… |
|---|---|---|
| **Strong** | 🟢 | Backed by **≥2 corroborating pages**, OR **current-year / fresh**, OR **confirmed in code**. |
| **Partial** | 🟡 | **Minor contradictions** vs other pages/repo, OR **stale (~2+ years** since last update). |
| **Weak** | 🔴 | **Single unconfirmed source**, **not found in code**, and/or **multiple contradictions** (especially vs code). |

Notes:
- "Current year" = the year shown in the doc's `Today:` line. State dates explicitly so the tier is auditable.
- Code-backing is the strongest single signal: a Confluence claim verified in the repo is 🟢 even if the page is old.
- A claim with **no source at all** ("folklore") is always 🔴 and must say so.
- Score is applied **per source** on the `Sources:` line and may be summarized **per block** (use the lowest contributing tier as the block's headline confidence).

## Switchable verification banner (top of every doc)
Default to AI-generated / not human-verified. Make it a one-line swap to upgrade. Use these exact states:

**Markdown** (first line after the H1):
```markdown
> **Verification:** ⚠️ NOT human-verified — AI-generated, pending review. Generated <NAME>, <YYYY-MM-DD>.
```
Upgrade by replacing that single line with one of:
```markdown
> **Verification:** 🟡 MOSTLY VERIFIED — <NAME>, <YYYY-MM-DD>. Most claims spot-checked against code; some details unverified.
> **Verification:** ✅ FULLY HUMAN-VERIFIED — <NAME>, <YYYY-MM-DD>.
```

**HTML** (single colored banner div; swap the three attributes + text):
```html
<!-- states: warn(red #E53935) / partial(gold #FDD835) / verified(green #43A047) -->
<div style="background:#2a1010;color:#E53935;border:1px solid #E53935;padding:8px 14px;font:14px/1.4 system-ui,sans-serif;text-align:center">⚠️ <strong>Verification:</strong> NOT human-verified — AI-generated, pending review. Generated <NAME>, <YYYY-MM-DD>.</div>
```
Upgrade variants:
```html
<div style="background:#2a2f10;color:#FDD835;border:1px solid #FDD835;padding:8px 14px;font:14px/1.4 system-ui,sans-serif;text-align:center">🟡 <strong>Verification:</strong> MOSTLY VERIFIED — <NAME>, <YYYY-MM-DD>. Most claims spot-checked against code; some details unverified.</div>
<div style="background:#10240f;color:#43A047;border:1px solid #43A047;padding:8px 14px;font:14px/1.4 system-ui,sans-serif;text-align:center">✅ <strong>Verification:</strong> FULLY HUMAN-VERIFIED — <NAME>, <YYYY-MM-DD>.</div>
```

The banner is **the very first element** of the document. Switching state = editing this one line/div only.
