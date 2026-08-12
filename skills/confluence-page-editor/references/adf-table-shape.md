# ADF table node shape

Reverse-engineered from an existing table on a live Confluence page (not from
official docs — treat field presence as confirmed, but don't assume every
optional attribute below is required).

```json
{
  "type": "table",
  "attrs": {
    "layout": "default",
    "localId": "<uuid-or-hex>"
  },
  "content": [
    {
      "type": "tableRow",
      "attrs": { "localId": "<uuid-or-hex>" },
      "content": [
        {
          "type": "tableHeader",
          "attrs": {
            "colspan": 1,
            "rowspan": 1,
            "localId": "<uuid-or-hex>"
          },
          "content": [
            {
              "type": "paragraph",
              "attrs": { "localId": "<uuid-or-hex>" },
              "content": [{ "type": "text", "text": "Column header" }]
            }
          ]
        }
      ]
    },
    {
      "type": "tableRow",
      "attrs": { "localId": "<uuid-or-hex>" },
      "content": [
        {
          "type": "tableCell",
          "attrs": {
            "colspan": 1,
            "rowspan": 1,
            "localId": "<uuid-or-hex>"
          },
          "content": [
            {
              "type": "paragraph",
              "attrs": { "localId": "<uuid-or-hex>" },
              "content": [{ "type": "text", "text": "Cell value" }]
            }
          ]
        }
      ]
    }
  ]
}
```

Key points:

- Header row uses `tableHeader` cells; every subsequent row uses `tableCell`.
  Both wrap their content in exactly one `paragraph` node (a cell CAN contain
  more than one block in principle — headings, lists, panels — but the common
  case, and the only one `md_to_adf.py`'s `table_from_markdown_rows()`
  produces, is a single paragraph per cell).
- `colspan`/`rowspan` default to `1` — set explicitly even for non-spanning
  cells; the live example always includes them.
- Every node (`table`, `tableRow`, `tableHeader`/`tableCell`, `paragraph`) has
  its own unique `localId`. Confluence tolerates any unique string here in
  practice (hex tokens work fine, don't need to be RFC4122 UUIDs) — but keep
  them unique across the whole document, not just within the table.
- An existing live-page example also had `"width": 760` on the top-level
  `table.attrs` — this appears to be a saved column-width hint from manual
  resizing in the UI, not something you need to set when building a table
  programmatically. Confluence lays out columns fine without it.
- Optional layout values seen elsewhere in Confluence docs (not confirmed on
  a table built by this skill): `"layout"` can be `"wide"` or `"full-width"`
  in addition to `"default"`; individual cells can carry a `"background"`
  attr for cell shading. Neither has been exercised by this skill's tooling.

## Markdown → ADF mapping used by `md_to_adf.py`

A pipe table:

```
| Event | Fact table | Fields carried |
|---|---|---|
| `ro` | `fact_order_events` | `order_rule_id` |
```

becomes one `table` node with one `tableHeader` row (3 cells) and one
`tableCell` row (3 cells), each cell's paragraph running through the same
inline parser (`parse_inline`) used for regular paragraph text — so inline
`` `code` ``, `**bold**`, and `*italic*` inside a cell are preserved with the
correct ADF marks, not flattened to plain text.

The separator row (`|---|---|---|`) is detected via a regex requiring only
`-`/`:` characters between pipes and is consumed without producing any node.

**Not handled**: cells spanning multiple source lines, cell alignment markers
(`:---`/`---:`/`:---:`) are parsed but not translated into any ADF alignment
attribute (Confluence tables don't expose per-column alignment via this
shape as far as this skill has found), and a literal `|` inside a cell's
inline code span (e.g. `` `a|b` ``) is correctly NOT treated as a column
separator (see `_split_table_row`'s `in_code` state).
