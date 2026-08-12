#!/usr/bin/env python3
"""verify_mermaid.py — validate and readability-lint Mermaid diagrams in MD/HTML.

Errors (always exit 1):   empty block, missing/invalid diagram-type header,
                          unbalanced brackets, mmdc render failure (if mmdc present).
Readability warnings:     horizontal LR sprawl, too many nodes, no color, tiny font (HTML).
                          Warnings fail the run (exit 1) only with --strict.

Usage:
  python3 verify_mermaid.py FILE [FILE ...] [--strict] [--no-color]
                            [--max-nodes N] [--lr-node-limit N] [--min-font PX] [--no-mmdc]
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile

# --- known mermaid diagram-type headers (first meaningful line must start with one) ---
DIAGRAM_TYPES = (
    "graph", "flowchart", "sequenceDiagram", "classDiagram", "stateDiagram-v2",
    "stateDiagram", "erDiagram", "journey", "gantt", "pie", "gitGraph", "mindmap",
    "timeline", "quadrantChart", "requirementDiagram", "C4Context", "C4Container",
    "sankey-beta", "xychart-beta", "block-beta",
)
ARROW_RE = re.compile(r"<?-{1,3}[.x o>=]*-?>?|={2,3}>?|-\.[->]+|--[xo]")
STRUCT_PREFIXES = (
    "classdef", "class ", "style ", "linkstyle", "subgraph", "end", "direction",
    "click ", "%%", "graph", "flowchart",
)

# ---------- colored output ----------
class C:
    def __init__(self, on):
        self.G = "\033[32m" if on else ""
        self.R = "\033[31m" if on else ""
        self.Y = "\033[33m" if on else ""
        self.B = "\033[1m" if on else ""
        self.D = "\033[2m" if on else ""
        self.X = "\033[0m" if on else ""


def extract_blocks(text, is_html):
    """Return list of (block_text, locator) for each mermaid diagram."""
    blocks = []
    if is_html:
        # <div ... class="...mermaid...">...</div> and <pre class="mermaid">...</pre>
        for m in re.finditer(
            r"<(div|pre)[^>]*class=\"[^\"]*\bmermaid\b[^\"]*\"[^>]*>(.*?)</\1>",
            text, re.S | re.I,
        ):
            line = text[: m.start()].count("\n") + 1
            blocks.append((m.group(2).strip(), f"line {line}"))
    else:
        for m in re.finditer(r"```+\s*mermaid[^\n]*\n(.*?)```+", text, re.S | re.I):
            line = text[: m.start()].count("\n") + 1
            blocks.append((m.group(1).strip(), f"line {line}"))
    return blocks


def meaningful_lines(block):
    out = []
    for raw in block.splitlines():
        s = raw.strip()
        if not s or s.startswith("%%"):
            continue
        out.append(s)
    return out


def header_type(block):
    for s in meaningful_lines(block):
        return s  # first meaningful line
    return ""


def is_valid_header(line):
    low = line.lower()
    return any(low.startswith(t.lower()) for t in DIAGRAM_TYPES)


def bracket_balanced(block):
    # strip quoted labels to avoid false positives, then check (), [], {}
    stripped = re.sub(r"\"[^\"]*\"", "", block)
    for o, c in (("(", ")"), ("[", "]"), ("{", "}")):
        if stripped.count(o) != stripped.count(c):
            return False
    return True


def is_horizontal(block):
    head = header_type(block).lower()
    if re.search(r"\b(lr|rl)\b", head):
        return True
    return any(re.match(r"direction\s+(lr|rl)\b", s.lower()) for s in meaningful_lines(block))


def count_nodes(block):
    """Estimate distinct node ids in a flowchart-style diagram (0 for non-flowchart)."""
    head = header_type(block).lower()
    if not (head.startswith("graph") or head.startswith("flowchart")):
        return 0
    ids = set()
    for s in meaningful_lines(block):
        low = s.lower()
        if low.startswith(STRUCT_PREFIXES) and not ARROW_RE.search(s):
            continue
        # drop |edge labels| and quoted strings
        s2 = re.sub(r"\|[^|]*\|", " ", s)
        s2 = re.sub(r"\"[^\"]*\"", " ", s2)
        for endpoint in ARROW_RE.split(s2):
            tok = endpoint.strip()
            if not tok:
                continue
            mid = re.match(r"([A-Za-z0-9_]+)", tok)
            if mid:
                ids.add(mid.group(1))
    return len(ids)


def has_color(block):
    low = block.lower()
    # flowcharts: classDef/style/fill: ; sequence diagrams color via `box rgb(...)`/`box rgba(...)`
    return (
        ("classdef" in low)
        or ("style " in low)
        or ("fill:" in low)
        or ("box rgb(" in low)
        or ("box rgba(" in low)
    )


def html_font_ok(text, min_font):
    """File-level: if HTML configures mermaid, require a fontSize >= min_font."""
    if "mermaid.initialize" not in text and "fontsize" not in text.lower():
        return None  # no mermaid config at all -> not checkable, skip
    m = re.search(r"fontSize\s*:\s*['\"]?(\d+)", text)
    if not m:
        return False
    return int(m.group(1)) >= min_font


def mmdc_render_ok(block):
    with tempfile.NamedTemporaryFile("w", suffix=".mmd", delete=False) as f:
        f.write(block)
        src = f.name
    out = src + ".svg"
    try:
        r = subprocess.run(
            ["mmdc", "-i", src, "-o", out],
            capture_output=True, text=True, timeout=60,
        )
        return r.returncode == 0, (r.stderr or r.stdout).strip().splitlines()[-1:] or [""]
    except Exception as e:  # noqa: BLE001
        return False, [str(e)]
    finally:
        for p in (src, out):
            try:
                os.remove(p)
            except OSError:
                pass


def check_file(path, args, col, use_mmdc):
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except OSError as e:
        print(f"{col.R}✗ cannot read {path}: {e}{col.X}")
        return 1, 0
    is_html = path.lower().endswith((".html", ".htm"))
    blocks = extract_blocks(text, is_html)
    print(f"\n{col.B}{path}{col.X} {col.D}({len(blocks)} diagram(s)){col.X}")
    if not blocks:
        print(f"  {col.D}no mermaid diagrams found{col.X}")
        return 0, 0

    errors = warnings = 0
    # file-level HTML font check
    if is_html:
        fok = html_font_ok(text, args.min_font)
        if fok is False:
            warnings += 1
            print(f"  {col.Y}⚠ font: set mermaid themeVariables.fontSize >= {args.min_font}px for readable HTML diagrams{col.X}")

    for i, (block, loc) in enumerate(blocks, 1):
        tag = f"  [{i}] {loc}:"
        if not block:
            errors += 1
            print(f"{tag} {col.R}✗ empty diagram block{col.X}")
            continue
        head = header_type(block)
        if not is_valid_header(head):
            errors += 1
            print(f"{tag} {col.R}✗ invalid/missing diagram type (got: '{head[:40]}'){col.X}")
            continue
        if not bracket_balanced(block):
            errors += 1
            print(f"{tag} {col.R}✗ unbalanced brackets () [] {{}}{col.X}")
            continue

        nodes = count_nodes(block)
        local_warn = []
        if nodes > args.max_nodes:
            local_warn.append(f"{nodes} nodes (> {args.max_nodes}) — split this diagram")
        if is_horizontal(block) and nodes > args.lr_node_limit:
            local_warn.append(f"horizontal (LR/RL) with {nodes} nodes — use vertical (graph TD)")
        if not has_color(block):
            local_warn.append("no color (classDef/style/fill:) — add colors + a legend")

        render_note = ""
        if use_mmdc:
            ok, msg = mmdc_render_ok(block)
            if not ok:
                errors += 1
                print(f"{tag} {col.R}✗ mmdc render failed: {msg[0]}{col.X}")
                continue
            render_note = f" {col.D}[mmdc ok]{col.X}"

        if local_warn:
            warnings += len(local_warn)
            print(f"{tag} {col.Y}⚠ {('; '.join(local_warn))}{col.X}{render_note}")
        else:
            print(f"{tag} {col.G}✓ ok{col.X} {col.D}({nodes or 'n/a'} nodes){col.X}{render_note}")

    return errors, warnings


def main():
    ap = argparse.ArgumentParser(
        description="Validate + readability-lint Mermaid diagrams in Markdown/HTML.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    ap.add_argument("files", nargs="+", help="MD or HTML files to check")
    ap.add_argument("--strict", action="store_true", help="readability warnings also fail (exit 1)")
    ap.add_argument("--no-color", action="store_true", help="disable colored output")
    ap.add_argument("--max-nodes", type=int, default=25, help="warn above this node count")
    ap.add_argument("--lr-node-limit", type=int, default=12, help="warn on LR/RL above this node count")
    ap.add_argument("--min-font", type=int, default=14, help="min mermaid fontSize (px) for HTML")
    ap.add_argument("--no-mmdc", action="store_true", help="skip real mmdc render even if installed")
    args = ap.parse_args()

    col = C(on=(not args.no_color) and sys.stdout.isatty())
    mmdc = shutil.which("mmdc")
    use_mmdc = bool(mmdc) and not args.no_mmdc
    print(f"{col.B}verify_mermaid{col.X} — mmdc: "
          + (f"{col.G}{mmdc}{col.X}" if use_mmdc else f"{col.Y}not used (static lint only){col.X}"))

    total_err = total_warn = 0
    for path in args.files:
        e, w = check_file(path, args, col, use_mmdc)
        total_err += e
        total_warn += w

    print(f"\n{col.B}Summary:{col.X} "
          f"{col.R if total_err else col.G}{total_err} error(s){col.X}, "
          f"{col.Y if total_warn else col.G}{total_warn} warning(s){col.X}")
    if total_err or (args.strict and total_warn):
        sys.exit(1)
    sys.exit(0)


if __name__ == "__main__":
    main()
