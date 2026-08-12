"""Markdown -> ADF node converter for inserting verbatim markdown content into
an existing Confluence page (as opposed to editing an existing macro's
codeBlock text in place, which adf_tool.py already covers).

Supports the common subset needed for pasting a knowledge doc/section
verbatim: ATX headings (# / ## / ...), paragraphs (soft-wrapped lines joined
by a single space, matching how markdown itself treats soft line breaks),
bullet lists (- item, with indented continuation lines folded into the same
item), pipe tables (header row + |---|---| separator + body rows), inline
`code`/**bold**/*italic* (including a mark nested inside another, e.g.
**bold `code`**), and fenced ```mermaid code blocks (emitted as a real
extension+expand macro pair, not an inert code block).

No summarization: every paragraph/bullet/cell's text is carried through
verbatim — only the wrapping newlines *inside* a single paragraph/bullet are
collapsed to single spaces, which is what markdown itself does for soft line
breaks. If you need to insert content and are unsure it's verbatim, run
adf_tool.py's `fidelity` subcommand against the same markdown line range
before pushing.

Not handled (falls through to a lone paragraph or breaks in weird ways):
ordered lists, nested/multi-level bullet lists, links, images, block quotes,
setext headings, tables with cells spanning multiple lines. Extend the
`convert()` loop if you need these.
"""
import re
import secrets


def new_local_id():
    return secrets.token_hex(6)


def parse_inline(text):
    """Stack-based inline scanner: `code` spans (content taken verbatim, so a
    literal `*` inside backticks like `granular_*` is never mistaken for
    emphasis), plus **bold**/*italic* delimiters that may wrap across a code
    span (marks stack, so a code node inside a bold span carries both marks).
    """
    i = 0
    n = len(text)
    nodes = []
    active_marks = []  # stack of 'strong'/'em'
    buf = ""

    def flush():
        nonlocal buf
        if buf:
            node = {"type": "text", "text": buf}
            if active_marks:
                node["marks"] = [{"type": m} for m in active_marks]
            nodes.append(node)
            buf = ""

    while i < n:
        ch = text[i]
        if ch == "`":
            end = text.find("`", i + 1)
            if end != -1:
                flush()
                code_text = text[i + 1 : end]
                marks = [{"type": m} for m in active_marks] + [{"type": "code"}]
                nodes.append({"type": "text", "text": code_text, "marks": marks})
                i = end + 1
                continue
        if text[i : i + 2] == "**":
            flush()
            if active_marks and active_marks[-1] == "strong":
                active_marks.pop()
            else:
                active_marks.append("strong")
            i += 2
            continue
        if ch == "*":
            flush()
            if active_marks and active_marks[-1] == "em":
                active_marks.pop()
            else:
                active_marks.append("em")
            i += 1
            continue
        buf += ch
        i += 1
    flush()
    return nodes


def plain_text_of_source(text):
    """Run source markdown text through parse_inline and concatenate the
    resulting node text — i.e. "what parse_inline considers the content, with
    all markup stripped". Used as the ground truth by adf_tool.py's fidelity
    check, so both sides of the diff agree on what counts as markup vs.
    content (a naive text.replace('*','') is wrong whenever a literal '*' or
    '`' appears inside a code span, e.g. `granular_*`)."""
    return "".join(n["text"] for n in parse_inline(text))


def paragraph(text):
    return {"type": "paragraph", "attrs": {"localId": new_local_id()}, "content": parse_inline(text)}


def heading(level, text):
    return {
        "type": "heading",
        "attrs": {"level": level, "localId": new_local_id()},
        "content": parse_inline(text),
    }


def mermaid_pair(mermaid_source, guest_index):
    """Build the (extension, expand) node pair Confluence's Mermaid Forge app
    renders. guest_index becomes parameters.guestParams.index — it MUST be
    unique across the whole page (see adf_tool.py's `validate`/`next-index`)."""
    ext_local = new_local_id()
    ext = {
        "type": "extension",
        "attrs": {
            "layout": "default",
            "extensionType": "com.atlassian.ecosystem",
            "extensionKey": "23392b90-4271-4239-98ca-a3e96c663cbb/63d4d207-ac2f-4273-865c-0240d37f044a/static/mermaid-diagram",
            "text": "Mermaid diagram",
            "parameters": {
                "guestParams": {"index": guest_index},
                "layout": "extension",
                "forgeEnvironment": "PRODUCTION",
                "extensionId": "ari:cloud:ecosystem::extension/23392b90-4271-4239-98ca-a3e96c663cbb/63d4d207-ac2f-4273-865c-0240d37f044a/static/mermaid-diagram",
                "localId": ext_local,
                "extensionTitle": "Mermaid diagram",
            },
            "localId": ext_local,
        },
    }
    expand_node = {
        "type": "expand",
        "attrs": {"title": "Diagram", "localId": new_local_id()},
        "content": [
            {
                "type": "codeBlock",
                "attrs": {"language": "mermaid", "localId": new_local_id()},
                "content": [{"type": "text", "text": mermaid_source}],
            }
        ],
    }
    return [ext, expand_node]


def bullet_list_from_lines(item_texts):
    return {
        "type": "bulletList",
        "attrs": {"localId": new_local_id()},
        "content": [
            {
                "type": "listItem",
                "attrs": {"localId": new_local_id()},
                "content": [paragraph(t)],
            }
            for t in item_texts
        ],
    }


def _split_table_row(line):
    """Split a markdown table row '| a | b | c |' into cell strings, respecting
    that a `|` inside an inline code span (e.g. `a|b`) must NOT be treated as a
    column separator."""
    cells = []
    buf = ""
    in_code = False
    s = line.strip()
    if s.startswith("|"):
        s = s[1:]
    if s.endswith("|"):
        s = s[:-1]
    i = 0
    n = len(s)
    while i < n:
        ch = s[i]
        if ch == "`":
            in_code = not in_code
            buf += ch
            i += 1
            continue
        if ch == "|" and not in_code:
            cells.append(buf.strip())
            buf = ""
            i += 1
            continue
        buf += ch
        i += 1
    cells.append(buf.strip())
    return cells


def table_from_markdown_rows(header_cells, body_rows):
    """Build an ADF table node: table -> tableRow -> tableHeader/tableCell,
    each cell wrapping a single paragraph (see references/ for the full shape
    reverse-engineered from a live page's existing table)."""

    def cell_node(text, is_header):
        return {
            "type": "tableHeader" if is_header else "tableCell",
            "attrs": {"colspan": 1, "rowspan": 1, "localId": new_local_id()},
            "content": [paragraph(text)],
        }

    def row_node(cells, is_header):
        return {
            "type": "tableRow",
            "attrs": {"localId": new_local_id()},
            "content": [cell_node(c, is_header) for c in cells],
        }

    rows = [row_node(header_cells, True)]
    for r in body_rows:
        rows.append(row_node(r, False))

    return {
        "type": "table",
        "attrs": {"layout": "default", "localId": new_local_id()},
        "content": rows,
    }


def count_mermaid_blocks(md_lines):
    """Count ```mermaid fenced blocks in the given lines — use this to size a
    mermaid_guest_indices list (e.g. list(range(start, start + count)))
    before calling convert()."""
    return sum(1 for l in md_lines if l.rstrip("\n").strip() == "```mermaid")


def convert(md_lines, mermaid_guest_indices):
    """
    md_lines: list of raw lines (with trailing '\\n'), VERBATIM from a source
               markdown file — pass an exact line-range slice, not a
               paraphrase or summary.
    mermaid_guest_indices: list of ints, guestParams.index values to assign to
               each ```mermaid block found, in document order. Length must
               equal count_mermaid_blocks(md_lines) exactly (asserted).
               Get unique values via adf_tool.py's `next-index` subcommand
               rather than guessing 0/1/2.

    Returns a flat list of ADF nodes suitable for splicing into a `content`
    array (e.g. body['content'][i:i] = nodes, or as an `expand` node's own
    `content`).
    """
    nodes = []
    i = 0
    n = len(md_lines)
    mermaid_idx_cursor = 0

    while i < n:
        line = md_lines[i].rstrip("\n")

        if line.strip() == "":
            i += 1
            continue

        # Heading: # text / ## text / ...
        m = re.match(r"^(#{1,6})\s+(.*)$", line)
        if m:
            level = len(m.group(1))
            nodes.append(heading(level, m.group(2).strip()))
            i += 1
            continue

        # Markdown table: header row, separator row (---), then body rows —
        # all lines starting with '|'.
        if line.strip().startswith("|") and i + 1 < n and re.match(
            r"^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)+\|?\s*$", md_lines[i + 1].rstrip("\n")
        ):
            header_cells = _split_table_row(line)
            i += 2  # skip header row + separator row
            body_rows = []
            while i < n:
                row_line = md_lines[i].rstrip("\n")
                if not row_line.strip().startswith("|"):
                    break
                body_rows.append(_split_table_row(row_line))
                i += 1
            nodes.append(table_from_markdown_rows(header_cells, body_rows))
            continue

        # Mermaid fenced code block
        if line.strip() == "```mermaid":
            i += 1
            code_lines = []
            while i < n and md_lines[i].rstrip("\n") != "```":
                code_lines.append(md_lines[i].rstrip("\n"))
                i += 1
            i += 1  # skip closing ```
            mermaid_source = "\n".join(code_lines)
            guest_index = mermaid_guest_indices[mermaid_idx_cursor]
            mermaid_idx_cursor += 1
            ext, expand_node = mermaid_pair(mermaid_source, guest_index)
            nodes.append(ext)
            nodes.append(expand_node)
            continue

        # Bullet list item: "- text" possibly continued on following indented lines
        m = re.match(r"^- (.*)$", line)
        if m:
            items = []
            item_text = m.group(1)
            i += 1
            while i < n:
                cont = md_lines[i].rstrip("\n")
                if cont.strip() == "":
                    break
                m2 = re.match(r"^- (.*)$", cont)
                if m2:
                    items.append(item_text)
                    item_text = m2.group(1)
                    i += 1
                    continue
                m3 = re.match(r"^\s+(\S.*)$", cont)
                if m3:
                    item_text += " " + m3.group(1).strip()
                    i += 1
                    continue
                break
            items.append(item_text)
            nodes.append(bullet_list_from_lines(items))
            continue

        # Otherwise: paragraph, possibly wrapped across following lines until a
        # blank line or a line starting a new construct (#, ```, -, |).
        para_text = line
        i += 1
        while i < n:
            nxt = md_lines[i].rstrip("\n")
            if nxt.strip() == "":
                break
            if (
                re.match(r"^#{1,6}\s", nxt)
                or nxt.strip() == "```mermaid"
                or re.match(r"^- ", nxt)
                or nxt.strip().startswith("|")
            ):
                break
            para_text += " " + nxt.strip()
            i += 1
        nodes.append(paragraph(para_text))

    assert mermaid_idx_cursor == len(mermaid_guest_indices), (
        f"expected {len(mermaid_guest_indices)} mermaid guest indices, "
        f"found {mermaid_idx_cursor} ```mermaid block(s) in the input — "
        f"use count_mermaid_blocks(md_lines) to size the list correctly"
    )
    return nodes
