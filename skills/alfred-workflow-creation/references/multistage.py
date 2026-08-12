"""Multi-stage (cascading) Alfred Script Filter skeleton.

ONE script drives every stage of a chained workflow. Each Script Filter object
in info.plist runs `/usr/bin/python3 multistage.py <stage>`; prior selections
arrive as environment variables (set by each item's `variables`, propagated
downstream by Alfred and accumulated across the chain).

Rules embodied below:
  - Non-final items: arg="" (field appears cleared), valid=True, variables={...}.
  - Final stage: arg=<the URL/result> -> flows to the connected Open URL action.
  - Every item has a stable, context-scoped `uid` so Alfred learns usage order.
  - Absolute interpreter + stdlib only (Alfred's PATH is minimal).

Connections in info.plist (one line):
  SF_stage1 -> SF_stage2 -> SF_finalize -> OpenURL
Only SF_stage1 has a `keyword`; the rest have an empty keyword and fire via the
connection. Set `alfredfiltersresults` true on each so typing narrows the stage.
"""

import json
import os
import sys

# Replace with the real option sets (or compute them per upstream selection).
STAGE1 = ["alpha", "beta"]
STAGE2 = ["dev", "prod"]


def item(title, subtitle, uid, variables=None, arg="", valid=True):
    result = {
        "uid": uid,            # stable + context-scoped => usage-order learning
        "title": title,
        "subtitle": subtitle,
        "arg": arg,            # "" clears the field; real value only on final stage
        "valid": valid,
        "autocomplete": title,
    }
    if variables:
        result["variables"] = variables   # propagates downstream as env vars
    return result


def build(stage, env):
    if stage == "stage1":
        return [
            item(s, f"pick {s}", f"wf:s1:{s}", variables={"s1": s})
            for s in STAGE1
        ]
    if stage == "stage2":
        s1 = env.get("s1", "")
        return [
            item(s, f"{s1} / {s}", f"wf:s2:{s1}:{s}", variables={"s2": s})
            for s in STAGE2
        ]
    if stage == "finalize":
        s1, s2 = env.get("s1", ""), env.get("s2", "")
        url = f"https://example.com/{s1}/{s2}"
        return [item("Open", f"{s1}/{s2}", f"wf:fin:{s1}:{s2}", arg=url)]
    return []


def main():
    stage = sys.argv[1] if len(sys.argv) > 1 else "stage1"
    print(json.dumps({"items": build(stage, os.environ)}))


if __name__ == "__main__":
    main()
