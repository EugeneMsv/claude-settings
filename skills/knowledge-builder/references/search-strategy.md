# Search Strategy

How to discover sources. **Order matters: Rovo + repo lead; CQL is a fallback.**

## Endpoints & defaults
- Atlassian cloudId / site host: `<your-site>.atlassian.net`.
- Default Confluence space key: **<SPACE>** (override per run if the user names another).
- Default repo: **<repo-name>** monorepo (override per run). Note where most of your relevant code lives if the repo is large.

## 1. Primary — Rovo (`mcp__atlassian__search`)
Rovo is unreliable — run **two parallel calls** per topic and merge results:
- **Phrase call** — short natural-language question: `"how does <component> resolve <behavior> from <input>"`
- **Keyword call** — raw terms only: `"<component> <behavior> <input>"`

If your workspace has a default team/org scope suffix that improves search relevance, append it to every query call unless the user explicitly says otherwise.

After merging the two call results:
- **Rank intersection first** — pages appearing in both calls are highest-confidence; surface them before phrase-only or keyword-only hits.
- **Read the top 2–3 hits** — call `getConfluencePage` immediately; excerpts don't verify claims and can be stale or misleading. If `last-modified` is older than 1 year, flag the page as potentially stale and cross-check against repo before citing.
- **Zero-yield fallback** — if both calls return fewer than 2 useful hits, retry using known team/system aliases (if your workspace maintains such a list) before falling to CQL.

Anything Rovo surfaces still gets opened, dated, and cross-checked like any other page.
- Always open the actual page (`getConfluencePage`) to capture the **title** (link text) and confirm the **last-modified date** — never cite from a search snippet alone.
- List a page's children to find related detail: `getConfluencePageDescendants`.
- Jira context (optional): `searchJiraIssuesUsingJql` / `getJiraIssue` for tickets that explain *why* a thing exists.

## 2. Parallel — repo discovery (ground truth)
Run concurrently with the Confluence pass. Launch `deep-researcher` subagents (default) that investigate the repo — broad map first, then dig into the actual source/config until the mechanism is understood, not just located:
- Config-as-code: `*.properties`, `*.ini`, `*.yaml`, terraform `*.tf`, helm/`values*.yaml`.
- Source: servers, servlets, modules, constants for the topic.
- Build/IaC: `BUILD.bazel`, `docker/`, `terraform/environments/**`.

`deep-researcher` is read-only and CANNOT spawn other agents — give each one an explicit brief (what to research, where to look, how deep to go). Fall back to `Explore` only for a quick, shallow file/symbol locate where deep investigation isn't warranted.

Cite repo facts as `[repo] path/to/file:line`. Repo values override Confluence for anything live.

## 3. Fallback — Confluence CQL (`searchConfluenceUsingCql`)
Use **only** when:
- Rovo + repo find nothing for a sub-topic, **or**
- exact field filtering is needed (space, date range, assignee).

Always sort newest-first so freshness is visible:
```
space = <SPACE> AND type = page AND text ~ "<TOPIC>" ORDER BY lastmodified DESC
space = <SPACE> AND type = page AND title ~ "<TOPIC>" ORDER BY lastmodified DESC
```

Topic-narrowing variants (combine the topic with a facet keyword):
```
space = <SPACE> AND text ~ "<TOPIC> architecture"      ORDER BY lastmodified DESC
space = <SPACE> AND text ~ "<TOPIC> design"             ORDER BY lastmodified DESC
space = <SPACE> AND text ~ "<TOPIC> API OR contract"   ORDER BY lastmodified DESC
space = <SPACE> AND text ~ "<TOPIC> data model"         ORDER BY lastmodified DESC
space = <SPACE> AND text ~ "<TOPIC> runbook OR oncall"  ORDER BY lastmodified DESC
space = <SPACE> AND text ~ "<TOPIC> release OR deploy"  ORDER BY lastmodified DESC
```

- Multi-space search: drop `space = <SPACE> AND` or use `space in (<SPACE>, OTHER)`.

## Cross-checking & contradiction resolution
- Pull **several** pages per sub-topic; select by **relevance AND date**, not first-hit.
- **Repo vs doc** (live value/config) → **repo wins**.
- **Doc vs doc** → **most recently updated wins**. If the conflict can't be cleanly resolved, **do not pick silently** — record both claims in the Contradictions & Open Items table and flag it.
- **Confirm code-backing** for each Confluence claim: code-confirmed → trust up; absent from code → still usable but lower trust and noted; contradicted by code → 🔴.
- Feed every resolved/unresolved conflict into the closing Contradictions table.
