# HTML Output Template (rich theme)

Self-contained dark-theme page distilled from prior internal knowledge docs. Same section order as the MD template. Features: switchable banner, sticky TOC nav, glossary `abbr.gloss` hover tooltips, collapsible `<details class="deep">`, trust chips, alternating tables, Mermaid with readable font, back-to-top.

Fill `<…>` placeholders. Keep content bullet-first and colored-diagram-first (see `presentation-and-diagrams.md`).

```html
<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title><Topic> — Knowledge</title>
<style>
:root{
  --bg:#0f1419;--panel:#161c24;--panel2:#1c242e;--ink:#e8edf2;--muted:#9fb0c0;
  --line:#2a3542;--accent:#43A047;--accent2:#1E88E5;--warn:#E53935;--gold:#FDD835;--code:#0b0f14;
}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font:15.5px/1.6 system-ui,-apple-system,Segoe UI,Roboto,sans-serif}
main{max-width:1040px;margin:0 auto;padding:0 22px 80px}
h1,h2,h3{scroll-margin-top:70px;line-height:1.25}
h2{border-bottom:1px solid var(--line);padding-bottom:6px;margin-top:38px}
a{color:#6fb7ff;text-decoration:none}a:hover{text-decoration:underline}
code{background:var(--code);color:#d7e3ad;padding:1px 5px;border-radius:4px;font-size:13.5px}
blockquote{border-left:4px solid var(--accent2);background:var(--panel);margin:14px 0;padding:10px 14px;color:var(--muted)}
table{border-collapse:collapse;width:100%;margin:14px 0;font-size:14.5px}
th,td{border:1px solid var(--line);padding:8px 11px;text-align:left;vertical-align:top}
th{background:var(--panel2);color:#fff}
tr:nth-child(even) td{background:var(--panel)}
td:first-child{color:#ffd479;font-weight:600}
/* sticky nav */
nav.toc{position:sticky;top:0;z-index:40;background:rgba(15,20,25,.93);backdrop-filter:blur(8px);
  border-bottom:1px solid var(--line);display:flex;flex-wrap:wrap;gap:6px 14px;padding:10px 22px;font-size:13.5px}
nav.toc a{color:var(--muted)}nav.toc a:hover{color:var(--ink)}
/* trust chips */
.rel{display:inline-block;padding:1px 7px;border-radius:10px;font-size:12px;font-weight:600;color:#000}
.rel.s{background:#43A047;color:#fff}.rel.p{background:#FDD835}.rel.w{background:#E53935;color:#fff}
/* collapsible deep-dive */
details.deep{background:var(--panel);border:1px solid var(--line);border-left:4px solid var(--accent2);border-radius:6px;margin:12px 0;padding:0 14px}
details.deep>summary{cursor:pointer;padding:13px 2px;font-weight:600;list-style:none}
details.deep>summary::before{content:"\25B8";display:inline-block;margin-right:8px;transition:transform .15s}
details.deep[open]>summary::before{transform:rotate(90deg)}
/* glossary tooltip */
abbr.gloss{border-bottom:1px dotted var(--gold);cursor:help;text-decoration:none}
.gloss-tip{position:fixed;z-index:60;max-width:320px;background:var(--panel2);border:1px solid var(--gold);
  color:var(--ink);padding:8px 11px;border-radius:6px;font-size:13px;box-shadow:0 6px 24px rgba(0,0,0,.5)}
/* back to top */
.totop{position:fixed;right:18px;bottom:18px;opacity:0;transition:opacity .2s;background:var(--accent2);
  color:#fff;border:0;border-radius:50%;width:44px;height:44px;font-size:20px;cursor:pointer}
.totop.show{opacity:.92}
.mermaid{background:var(--panel);border:1px solid var(--line);border-radius:6px;padding:12px;margin:14px 0}
.legend{color:var(--muted);font-size:13px;margin:-6px 0 14px}
</style></head>
<body>

<!-- SWITCHABLE BANNER (see trust-model.md for the 3 states) -->
<div style="background:#2a1010;color:#E53935;border:1px solid #E53935;padding:8px 14px;font:14px/1.4 system-ui;text-align:center">⚠️ <strong>Verification:</strong> NOT human-verified — AI-generated, pending review. Generated <NAME>, <YYYY-MM-DD>.</div>

<nav class="toc">
  <a href="#s1">1. <Section></a>
  <a href="#s2">2. <Section></a>
  <a href="#contradictions">Contradictions</a>
  <a href="#references">References</a>
  <a href="#method">Method</a>
  <a href="#glossary">Glossary</a>
</nav>

<main>
<h1><Topic> — Knowledge</h1>
<blockquote><strong>What this is:</strong> <scope>. <strong>Sourcing:</strong> repo = ground truth; Confluence = narrative, trust-scored
<span class="rel s">strong</span> <span class="rel p">partial</span> <span class="rel w">weak</span>. <strong>Today: <YYYY-MM-DD>.</strong></blockquote>

<h2 id="s1">1. <Section></h2>
<ul><li><bullet fact> <strong><keyword></strong>.</li></ul>

<div class="mermaid">
graph TD
  client[Caller]:::client --> svcA[<Service>]:::svc
  svcA --> db[(<Store>)]:::store
  classDef svc fill:#BBDEFB,stroke:#0D47A1,color:#000
  classDef store fill:#C8E6C9,stroke:#1B5E20,color:#000
  classDef client fill:#FFF9C4,stroke:#F57F17,color:#000
</div>
<p class="legend">Legend: 🟦 service · 🟩 datastore · 🟨 client.</p>

<details class="deep"><summary>Deep dive: <optional detail></summary>
  <ul><li>…</li></ul>
</details>

<p><strong>Sources:</strong> <a href="https://your-site.atlassian.net/wiki/spaces/SPACE/pages/<id>"><Page Name></a> (<date>) <span class="rel p">partial</span> · <code>[repo] path/to/file:line</code> <span class="rel s">strong</span></p>

<h2 id="contradictions">Contradictions &amp; Open Items</h2>
<table><thead><tr><th>#</th><th>Topic</th><th>Claim A</th><th>Claim B</th><th>Resolved</th><th>Trust</th></tr></thead>
<tbody><tr><td>1</td><td>…</td><td>…</td><td>…</td><td><strong>Repo wins</strong> — …</td><td><span class="rel s">strong</span></td></tr></tbody></table>

<h2 id="references">References</h2>
<table><thead><tr><th>#</th><th>Source</th><th>Type</th><th>Date</th><th>Trust</th></tr></thead>
<tbody><tr><td>1</td><td><a href="…"><Page Name></a></td><td>Confluence</td><td><date></td><td><span class="rel p">partial</span></td></tr></tbody></table>

<h2 id="method">Method note</h2>
<p>Facts gathered treating the <strong><repo></strong> monorepo as ground truth and Confluence space <strong><SPACE></strong> as narrative. Keyword/CQL + repo led discovery; Rovo was fallback/cross-check only. Repo wins on conflict; doc-vs-doc resolves to newest or is flagged.</p>

<h2 id="glossary">Glossary</h2>
<table><thead><tr><th>Term</th><th>Meaning</th></tr></thead><tbody>
  <tr><td><ABBR></td><td><Full name — meaning></td></tr>
  <tr><td><ABBR2></td><td><…> (inferred) <span class="rel w">weak</span></td></tr>
</tbody></table>
</main>

<button class="totop" onclick="scrollTo({top:0,behavior:'smooth'})">↑</button>

<script type="module">
import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';
mermaid.initialize({ startOnLoad:false, theme:'dark', themeVariables:{ fontSize:'16px' } });
await mermaid.run({ querySelector:'.mermaid' });

// glossary tooltips: wrap known terms in abbr.gloss, show floating def on hover
const GLOSS = { /* "<ABBR>":"<definition>" — populate from the glossary table */ };
// (optional) walk text nodes and wrap GLOSS keys in <abbr class="gloss" data-def="...">
let tip;
document.addEventListener('mouseover',e=>{const a=e.target.closest('abbr.gloss');if(!a)return;
  tip=document.createElement('div');tip.className='gloss-tip';tip.textContent=a.dataset.def;
  document.body.appendChild(tip);const r=a.getBoundingClientRect();
  tip.style.left=Math.min(r.left,innerWidth-340)+'px';tip.style.top=(r.bottom+6)+'px';});
document.addEventListener('mouseout',e=>{if(e.target.closest('abbr.gloss')&&tip){tip.remove();tip=null;}});

// back-to-top visibility
const btn=document.querySelector('.totop');
addEventListener('scroll',()=>btn.classList.toggle('show',scrollY>500));
</script>
</body></html>
```

## Notes
- The banner div is the switchable element — swap to the 🟡/✅ variant in `trust-model.md` to upgrade.
- Trust chips: `<span class="rel s|p|w">strong|partial|weak</span>` mirror 🟢/🟡/🔴.
- Populate the `GLOSS` JS object from the glossary so acronyms get hover tooltips; mark inferred ones in the definition text.
- Mermaid `fontSize:'16px'` keeps diagram text legible — required by `verify_mermaid.py` readability checks for HTML.
- Run `python3 scripts/verify_mermaid.py <file>.html --strict` after writing.
