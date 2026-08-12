#!/usr/bin/env python3
"""ADF helper for safe Confluence page edits.

Confluence stores its body as ADF (Atlassian Document Format) JSON. App macros
such as Mermaid diagrams are NATIVE nodes (an `extension` node followed by an
`expand` node whose `codeBlock` holds the diagram source). Editing a page via
contentFormat=markdown FLATTENS those macros into inert code blocks and the
diagrams stop rendering. The safe path is to edit the ADF directly, touching
only the text inside macro code blocks and leaving the extension nodes,
localIds, and marks intact.

This tool never calls Atlassian itself — it has no MCP access, only local file
I/O. The page must already have been read via the Atlassian MCP tool and its
result saved to disk; `fetch` then extracts the `body` object from that saved
file (handling the case where the MCP result was too large to return inline
and got written to a tool-results/*.txt file instead). Workflow:

  1. Read the page with the Atlassian MCP tool (contentFormat=adf). For any
     page of moderate size (roughly >90KB) the MCP result itself exceeds the
     tool's token cap and gets written to a `tool-results/*.txt` file instead
     of being returned inline — use `fetch` to pull `body` out of that file
     into a clean body.json in one step, instead of hand-writing the same
     `json.load(...)['content']['nodes'][0]['body']` extraction each time.
  2. `outline`  — print a numbered list of top-level nodes so edits can be
                  targeted by index.
  3. `show`     — dump one node (and any macro code block following it).
  4. Edit body.json programmatically or by hand. For inserting new verbatim
     markdown content (not just editing an existing macro's codeBlock text),
     use `md_to_adf.py`'s `convert()` instead of writing ADF nodes by hand.
  5. `next-index` — before adding a NEW mermaid extension node, get the next
                  free `guestParams.index` (and see how many existing indices
                  would need bumping if you're inserting the diagram earlier
                  in the document than existing ones).
  6. `validate` — re-parse, re-print the outline, and check every Mermaid code
                  block for syntax hazards before pushing.
  7. `fidelity` — when the edit is "insert this markdown verbatim", diff the
                  plain text (and mermaid blocks) of the built ADF node(s)
                  against the same markdown line range to catch accidental
                  paraphrasing/summarization/omission before pushing.
  8. Push body.json back with updateConfluencePage (contentFormat=adf), or via
     the REST script for bodies over ~50KB (see SKILL.md step 8).

Subcommands:
  fetch      <tool_result.txt> <out_body.json>
  outline    <body.json>
  show       <body.json> <index>
  next-index <body.json>
  validate   <body.json>
  fidelity   <body.json> <expand_or_content_index> <md_file> <start_line> <end_line>
             (line numbers are 1-based, inclusive, matching an editor's gutter)
"""
import json
import re
import sys


def load(path):
    with open(path) as f:
        data = json.load(f)
    # Accept either a raw ADF doc or a full getConfluencePage response.
    if data.get("type") == "doc":
        return data
    if isinstance(data.get("body"), dict) and data["body"].get("type") == "doc":
        return data["body"]
    raise SystemExit("ERROR: file is not an ADF doc (expected type=doc or .body.type=doc)")


def node_label(node):
    t = node.get("type")
    if t == "heading":
        txt = "".join(c.get("text", "") for c in node.get("content", []))
        return f"heading L{node.get('attrs', {}).get('level')}: {txt.strip()}"
    if t == "paragraph":
        txt = "".join(c.get("text", "") for c in node.get("content", []))
        return f"paragraph: {txt[:60]}"
    if t in ("extension", "bodiedExtension"):
        ek = node.get("attrs", {}).get("extensionKey", "")
        return f"{t}: {ek}"
    if t == "expand":
        inner = node.get("content", [])
        lang = ""
        if inner and inner[0].get("type") == "codeBlock":
            lang = inner[0].get("attrs", {}).get("language", "")
        return f"expand (codeBlock lang={lang})"
    if t == "codeBlock":
        return f"codeBlock lang={node.get('attrs', {}).get('language', '')}"
    if t == "table":
        return f"table ({len(node.get('content', []))} rows)"
    return t


def find_mermaid_blocks(doc):
    """Yield (path, text) for every mermaid codeBlock, including inside expands."""
    def walk(node, path):
        if node.get("type") == "codeBlock" and node.get("attrs", {}).get("language") == "mermaid":
            txt = "".join(c.get("text", "") for c in node.get("content", []))
            yield (path, txt)
        for i, child in enumerate(node.get("content", []) or []):
            yield from walk(child, path + [i])
    yield from walk(doc, [])


def find_mermaid_extensions(doc):
    """Yield (path, localId, guestParams.index) for every mermaid extension node.

    Each mermaid diagram on a page is rendered by a Forge app extension node.
    The app looks up which diagram's source to render using
    parameters.guestParams.index. If every extension on the page shares the
    same index (most commonly 0, e.g. all copy-pasted from one template),
    every diagram block renders the SAME (first) diagram's content instead of
    its own — a silent, hard-to-spot bug since the page still "renders fine",
    it just shows duplicate diagrams. Each extension's index must be unique.
    """
    def walk(node, path):
        if node.get("type") == "extension":
            ek = node.get("attrs", {}).get("extensionKey", "")
            if ek.endswith("static/mermaid-diagram"):
                local_id = node.get("attrs", {}).get("localId")
                idx = node.get("attrs", {}).get("parameters", {}).get("guestParams", {}).get("index")
                yield (path, local_id, idx)
        for i, child in enumerate(node.get("content", []) or []):
            yield from walk(child, path + [i])
    yield from walk(doc, [])


# Mermaid classDiagram return types must be single identifiers. These tokens
# silently break rendering when used as a member return type / trailing value.
def lint_mermaid(text):
    problems = []
    lines = text.splitlines()
    is_class = any(l.strip().startswith("classDiagram") for l in lines)
    if is_class:
        for n, line in enumerate(lines, 1):
            s = line.strip()
            # member line like "+method() return type with spaces"
            if (s.startswith("+") or s.startswith("-") or s.startswith("#")) and "(" in s and ")" in s:
                after = s.split(")", 1)[1].strip()
                if after and (" " in after or "-" in after):
                    problems.append(
                        f"  line {n}: member return type '{after}' has a space or hyphen "
                        f"(use a single identifier, e.g. 'boolean'/'Stream'): {s!r}")
    return problems


def cmd_fetch(tool_result_path, out_path):
    """Extract the `body` object from an oversized getConfluencePage tool-result
    dump (the .txt file the harness writes when the MCP response exceeds its
    token cap) into a clean ADF body.json ready for outline/show/validate.

    Accepts either shape: {"content": {"nodes": [{..., "body": {...}}]}} (the
    getConfluencePage tool-result envelope) or a bare {"body": {...}} / a raw
    ADF doc — load() already handles the latter two, so this just unwraps the
    former one extra layer first.
    """
    with open(tool_result_path) as f:
        data = json.load(f)
    if "content" in data and isinstance(data["content"], dict) and "nodes" in data["content"]:
        node = data["content"]["nodes"][0]
        body = node["body"]
        print(f"lastModified: {node.get('lastModified', '?')}")
        print(f"title: {node.get('title', '?')}")
    else:
        body = data.get("body", data)
    with open(out_path, "w") as f:
        json.dump(body, f)
    print(f"OK — wrote {out_path} ({len(body.get('content', []))} top-level nodes)")


def cmd_next_index(path):
    """Print the next free mermaid guestParams.index, and flag any existing
    diagram indices that would need bumping if new diagrams are about to be
    inserted at a given top-level position (pass that position as an optional
    3rd arg to see the split)."""
    doc = load(path)
    extensions = list(find_mermaid_extensions(doc))
    indices = sorted(idx for _, _, idx in extensions if idx is not None)
    next_idx = (max(indices) + 1) if indices else 0
    print(f"Existing mermaid guestParams.index values (sorted): {indices}")
    print(f"Next free index: {next_idx}")
    if len(sys.argv) > 3:
        insert_at = int(sys.argv[3])
        after = [(p, lid, idx) for p, lid, idx in extensions if p and p[0] >= insert_at]
        if after:
            print(
                f"\nInserting new top-level node(s) at position {insert_at} would shift "
                f"these existing extensions after it — bump each one's index by the "
                f"number of NEW mermaid diagrams you insert before them:"
            )
            for p, lid, idx in after:
                print(f"  path={p} localId={lid} current index={idx}")
        else:
            print(f"\nNo existing mermaid extensions sit at/after top-level position {insert_at}.")


def cmd_fidelity(body_path, node_index, md_path, start_line, end_line):
    """Diff the plain text (and mermaid block source) of an already-built ADF
    node against the same line range of a source markdown file, to catch
    accidental paraphrasing/summarization/truncation before pushing. Both
    sides are run through the SAME inline-markup stripping logic (md_to_adf's
    parse_inline) so a literal '*' or '`' inside a code span, e.g.
    `granular_*`, isn't mistaken for markdown emphasis on either side.
    """
    sys.path.insert(0, __file__.rsplit("/", 1)[0])
    from md_to_adf import plain_text_of_source

    doc = load(body_path)
    node = doc["content"][int(node_index)]

    def collect_text_blocks(n):
        t = n.get("type")
        if t == "extension":
            return []
        if t == "expand" and n.get("attrs", {}).get("title") == "Diagram":
            cb = n["content"][0]
            return [("MERMAID", cb["content"][0]["text"])]
        if t in ("paragraph", "heading"):
            txt = "".join(c.get("text", "") for c in n.get("content", []) if c.get("type") == "text")
            return [("TEXT", txt)]
        if t == "bulletList":
            out = []
            for li in n["content"]:
                for c in li["content"]:
                    out.extend(collect_text_blocks(c))
            return out
        if t == "table":
            out = []
            for row in n["content"]:
                for cell in row["content"]:
                    for c in cell["content"]:
                        out.extend(collect_text_blocks(c))
            return out
        out = []
        for c in n.get("content", []) or []:
            out.extend(collect_text_blocks(c))
        return out

    blocks = collect_text_blocks(node)
    mermaid_built = [b[1] for b in blocks if b[0] == "MERMAID"]
    text_blocks = [b[1] for b in blocks if b[0] == "TEXT"]
    built_plain = re.sub(r"\s+", " ", " ".join(text_blocks)).strip()

    with open(md_path, encoding="utf-8") as f:
        all_lines = f.readlines()
    src_lines = all_lines[int(start_line) - 1 : int(end_line)]
    source_text = "".join(src_lines)

    mermaid_in_src = re.findall(r"```mermaid\n(.*?)\n```", source_text, re.DOTALL)
    src = re.sub(r"```mermaid\n.*?\n```", "", source_text, flags=re.DOTALL)
    src = re.sub(r"^#{1,6}\s+", "", src, flags=re.MULTILINE)
    src = re.sub(r"^- ", "", src, flags=re.MULTILINE)
    src = re.sub(r"^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)+\|?\s*$", "", src, flags=re.MULTILINE)

    def table_line_to_text(line):
        s = line.strip()
        if s.startswith("|"):
            s = s[1:]
        if s.endswith("|"):
            s = s[:-1]
        return " ".join(c.strip() for c in s.split("|"))

    src = "\n".join(
        table_line_to_text(l) if l.strip().startswith("|") else l for l in src.split("\n")
    )
    para_blocks = re.split(r"\n\s*\n", src.strip())
    src_text_blocks = []
    for pb in para_blocks:
        lines = [l.strip() for l in pb.split("\n") if l.strip()]
        src_text_blocks.append(plain_text_of_source(" ".join(lines)))
    src_plain = re.sub(r"\s+", " ", " ".join(src_text_blocks)).strip()

    text_match = src_plain == built_plain
    mermaid_match = mermaid_built == mermaid_in_src
    print(f"Source plain-text length: {len(src_plain)}")
    print(f"Built  plain-text length: {len(built_plain)}")
    print(f"Text match: {text_match}")
    print(f"Mermaid block(s) byte-identical: {mermaid_match} ({len(mermaid_in_src)} found in source, {len(mermaid_built)} in built node)")
    if not text_match:
        for i, (a, b) in enumerate(zip(src_plain, built_plain)):
            if a != b:
                print(f"\nFirst diff at char {i}:")
                print(f"  SOURCE: {src_plain[max(0, i-100):i+100]!r}")
                print(f"  BUILT:  {built_plain[max(0, i-100):i+100]!r}")
                break
        else:
            print(f"\nOne is a prefix of the other; length delta {len(src_plain) - len(built_plain)}")
    ok = text_match and mermaid_match
    print("\nFIDELITY OK" if ok else "\nFIDELITY MISMATCH — do not push until resolved.")
    sys.exit(0 if ok else 1)


def cmd_outline(path):
    doc = load(path)
    for i, node in enumerate(doc["content"]):
        print(f"[{i:2}] {node_label(node)}")


def cmd_show(path, index):
    doc = load(path)
    node = doc["content"][int(index)]
    print(json.dumps(node, indent=2, ensure_ascii=False))


def cmd_validate(path):
    doc = load(path)
    print(f"OK: parsed ADF doc, {len(doc['content'])} top-level nodes\n")
    cmd_outline(path)
    print()
    blocks = list(find_mermaid_blocks(doc))
    print(f"Found {len(blocks)} mermaid code block(s)")
    any_problem = False
    for path_idx, text in blocks:
        problems = lint_mermaid(text)
        if problems:
            any_problem = True
            print(f"\n!! mermaid block at {path_idx} has issues:")
            for p in problems:
                print(p)
    if not any_problem:
        print("No mermaid classDiagram return-type hazards detected.")

    extensions = list(find_mermaid_extensions(doc))
    if extensions:
        indices = [idx for _, _, idx in extensions]
        seen = {}
        dupes = []
        for path_idx, local_id, idx in extensions:
            if idx in seen:
                dupes.append((path_idx, local_id, idx))
            seen.setdefault(idx, (path_idx, local_id))
        if dupes:
            any_problem = True
            print(f"\n!! {len(extensions)} mermaid extension node(s) found, "
                  f"but guestParams.index is NOT unique per diagram:")
            print(f"   indices seen: {indices}")
            print("   Every mermaid block will render the SAME diagram (whichever "
                  "index they collide on) instead of its own. Assign each mermaid "
                  "extension a distinct guestParams.index (0, 1, 2, ... in document "
                  "order) before pushing.")
            for path_idx, local_id, idx in dupes:
                print(f"     duplicate: path={path_idx} localId={local_id} index={idx}")
        else:
            print(f"\n{len(extensions)} mermaid extension(s): guestParams.index values "
                  f"are unique ({sorted(indices)}) — OK.")

    print("\nValidation complete." if not any_problem else "\nVALIDATION FOUND ISSUES — fix before pushing.")
    sys.exit(1 if any_problem else 0)


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(2)
    cmd, path = sys.argv[1], sys.argv[2]
    if cmd == "outline":
        cmd_outline(path)
    elif cmd == "show":
        cmd_show(path, sys.argv[3])
    elif cmd == "validate":
        cmd_validate(path)
    elif cmd == "fetch":
        cmd_fetch(path, sys.argv[3])
    elif cmd == "next-index":
        cmd_next_index(path)
    elif cmd == "fidelity":
        if len(sys.argv) < 7:
            print("usage: fidelity <body.json> <content_index> <md_file> <start_line> <end_line>")
            sys.exit(2)
        cmd_fidelity(path, sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6])
    else:
        print(f"Unknown command: {cmd}")
        print(__doc__)
        sys.exit(2)


if __name__ == "__main__":
    main()
