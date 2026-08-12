#!/usr/bin/env python3
"""Regression tests for confluence-page-editor's scripts.

Covers md_to_adf.py (inline parsing, tables, mermaid extraction, fidelity),
adf_tool.py (outline/validate/next-index/fidelity against a built body), and
the argument-validation paths of confluence-get.sh/confluence-push.sh (no
live network calls — those are exercised manually against a real page, per
scripts/README.md's troubleshooting section).

Run with no arguments: python3 tests/run_tests.py
Exit 0 = all pass, 1 = at least one failure (each failure prints what/why).
"""
import json
import os
import subprocess
import sys
import tempfile
import unittest

SCRIPTS_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIXTURES_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures")
sys.path.insert(0, SCRIPTS_DIR)

import md_to_adf  # noqa: E402


class TestParseInline(unittest.TestCase):
    def test_plain_text_passthrough(self):
        nodes = md_to_adf.parse_inline("just plain text")
        self.assertEqual(nodes, [{"type": "text", "text": "just plain text"}])

    def test_bold_span(self):
        nodes = md_to_adf.parse_inline("a **bold** word")
        texts_marks = [(n["text"], [m["type"] for m in n.get("marks", [])]) for n in nodes]
        self.assertIn(("bold", ["strong"]), texts_marks)
        self.assertIn(("a ", []), texts_marks)

    def test_italic_span(self):
        nodes = md_to_adf.parse_inline("an *italic* word")
        texts_marks = [(n["text"], [m["type"] for m in n.get("marks", [])]) for n in nodes]
        self.assertIn(("italic", ["em"]), texts_marks)

    def test_code_span_literal_asterisk_not_emphasis(self):
        """A literal '*' inside `backticks` must stay inside the code mark,
        never be parsed as the start of *emphasis* — this was the actual bug
        that motivated the stack-based rewrite (see md_to_adf.py history)."""
        nodes = md_to_adf.parse_inline("see `granular_*` for details")
        code_nodes = [n for n in nodes if "code" in [m["type"] for m in n.get("marks", [])]]
        self.assertEqual(len(code_nodes), 1)
        self.assertEqual(code_nodes[0]["text"], "granular_*")
        # and nothing after it should carry an unclosed 'em' mark
        for n in nodes:
            marks = [m["type"] for m in n.get("marks", [])]
            self.assertNotIn("em", marks, f"unexpected stray em mark on {n!r}")

    def test_bold_wrapping_code_span_carries_both_marks(self):
        nodes = md_to_adf.parse_inline("**bold `code` text**")
        code_nodes = [n for n in nodes if "code" in [m["type"] for m in n.get("marks", [])]]
        self.assertEqual(len(code_nodes), 1)
        marks = [m["type"] for m in code_nodes[0]["marks"]]
        self.assertIn("strong", marks)
        self.assertIn("code", marks)

    def test_pipe_inside_code_span_not_a_column_separator(self):
        cells = md_to_adf._split_table_row("| `a|b` | plain |")
        self.assertEqual(cells, ["`a|b`", "plain"])


class TestConvert(unittest.TestCase):
    def setUp(self):
        with open(os.path.join(FIXTURES_DIR, "sample.md"), encoding="utf-8") as f:
            self.lines = f.readlines()

    def test_heading_detected(self):
        nodes = md_to_adf.convert(self.lines, mermaid_guest_indices=[5])
        headings = [n for n in nodes if n["type"] == "heading"]
        self.assertEqual(len(headings), 1)
        self.assertEqual(headings[0]["attrs"]["level"], 1)
        self.assertEqual(headings[0]["content"][0]["text"], "Test Page")

    def test_table_parsed_with_correct_rows_and_headers(self):
        nodes = md_to_adf.convert(self.lines, mermaid_guest_indices=[5])
        tables = [n for n in nodes if n["type"] == "table"]
        self.assertEqual(len(tables), 1)
        table = tables[0]
        header_row, body_row_1, body_row_2 = table["content"]
        self.assertEqual(header_row["content"][0]["type"], "tableHeader")
        header_text = header_row["content"][0]["content"][0]["content"][0]["text"]
        self.assertEqual(header_text, "Field")
        self.assertEqual(body_row_1["content"][0]["type"], "tableCell")
        # first body row's first cell should be the `id` code span
        cell_para = body_row_1["content"][0]["content"][0]
        self.assertEqual(cell_para["content"][0]["text"], "id")
        self.assertIn("code", [m["type"] for m in cell_para["content"][0].get("marks", [])])

    def test_bullet_list_with_continuation_line_folded_in(self):
        nodes = md_to_adf.convert(self.lines, mermaid_guest_indices=[5])
        bullet_lists = [n for n in nodes if n["type"] == "bulletList"]
        self.assertEqual(len(bullet_lists), 1)
        items = bullet_lists[0]["content"]
        self.assertEqual(len(items), 2)
        second_item_text = items[1]["content"][0]["content"][0]["text"]
        self.assertIn("continues", second_item_text)
        self.assertIn("wrapped line", second_item_text)

    def test_mermaid_block_becomes_extension_and_expand_pair_with_given_index(self):
        nodes = md_to_adf.convert(self.lines, mermaid_guest_indices=[42])
        extensions = [n for n in nodes if n["type"] == "extension"]
        self.assertEqual(len(extensions), 1)
        self.assertEqual(
            extensions[0]["attrs"]["parameters"]["guestParams"]["index"], 42
        )
        expand_idx = nodes.index(extensions[0]) + 1
        expand_node = nodes[expand_idx]
        self.assertEqual(expand_node["type"], "expand")
        code_block = expand_node["content"][0]
        self.assertEqual(code_block["attrs"]["language"], "mermaid")
        self.assertIn("flowchart TD", code_block["content"][0]["text"])

    def test_mermaid_count_mismatch_raises(self):
        with self.assertRaises(AssertionError):
            md_to_adf.convert(self.lines, mermaid_guest_indices=[1, 2])  # only 1 block in fixture

    def test_count_mermaid_blocks(self):
        self.assertEqual(md_to_adf.count_mermaid_blocks(self.lines), 1)

    def test_no_content_dropped_end_to_end(self):
        """Every distinctive fixture string must survive conversion somewhere
        in the built nodes' text — the fidelity guarantee this whole toolset
        exists to protect, exercised directly rather than via the CLI."""
        nodes = md_to_adf.convert(self.lines, mermaid_guest_indices=[5])

        def all_text(n):
            out = []
            if n.get("type") == "text":
                out.append(n["text"])
            for c in n.get("content", []) or []:
                out.extend(all_text(c))
            return out

        combined = " ".join(t for n in nodes for t in all_text(n))
        for expected in [
            "Test Page", "inline_code", "bold text", "italic text", "star_*",
            "First bullet", "a_code_span", "continues", "wrapped line",
            "The record id", "Plain text value",
        ]:
            self.assertIn(expected, combined, f"missing expected content: {expected!r}")


class TestTableFromMarkdownRows(unittest.TestCase):
    def test_shape_matches_reference_doc(self):
        table = md_to_adf.table_from_markdown_rows(["A", "B"], [["1", "2"], ["3", "4"]])
        self.assertEqual(table["type"], "table")
        self.assertEqual(len(table["content"]), 3)  # header + 2 body rows
        header_row = table["content"][0]
        self.assertTrue(all(c["type"] == "tableHeader" for c in header_row["content"]))
        body_row = table["content"][1]
        self.assertTrue(all(c["type"] == "tableCell" for c in body_row["content"]))
        for cell in body_row["content"]:
            self.assertEqual(cell["attrs"]["colspan"], 1)
            self.assertEqual(cell["attrs"]["rowspan"], 1)


class TestAdfToolCli(unittest.TestCase):
    """Exercise adf_tool.py's subcommands as a subprocess, same as real usage."""

    def setUp(self):
        with open(os.path.join(FIXTURES_DIR, "sample.md"), encoding="utf-8") as f:
            lines = f.readlines()
        nodes = md_to_adf.convert(lines, mermaid_guest_indices=[0])
        self.body = {"type": "doc", "version": 1, "content": nodes}
        self.tmpdir = tempfile.TemporaryDirectory()
        self.body_path = os.path.join(self.tmpdir.name, "body.json")
        with open(self.body_path, "w") as f:
            json.dump(self.body, f)

    def tearDown(self):
        self.tmpdir.cleanup()

    def _run(self, *args):
        return subprocess.run(
            [sys.executable, os.path.join(SCRIPTS_DIR, "adf_tool.py"), *args],
            capture_output=True, text=True,
        )

    def test_outline_lists_all_top_level_nodes(self):
        result = self._run("outline", self.body_path)
        self.assertEqual(result.returncode, 0)
        self.assertIn("heading L1: Test Page", result.stdout)
        self.assertIn("table (", result.stdout)
        self.assertIn("extension:", result.stdout)

    def test_validate_passes_on_well_formed_body(self):
        result = self._run("validate", self.body_path)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("Validation complete.", result.stdout)
        self.assertIn("guestParams.index values are unique", result.stdout)

    def test_validate_fails_on_duplicate_mermaid_index(self):
        # Duplicate the extension+expand pair with the SAME index -> must fail.
        ext_idx = next(i for i, n in enumerate(self.body["content"]) if n["type"] == "extension")
        dup_ext = json.loads(json.dumps(self.body["content"][ext_idx]))  # deep copy
        dup_expand = json.loads(json.dumps(self.body["content"][ext_idx + 1]))
        self.body["content"].extend([dup_ext, dup_expand])
        with open(self.body_path, "w") as f:
            json.dump(self.body, f)
        result = self._run("validate", self.body_path)
        self.assertEqual(result.returncode, 1)
        self.assertIn("NOT unique", result.stdout)

    def test_next_index_reports_correct_free_value(self):
        result = self._run("next-index", self.body_path)
        self.assertEqual(result.returncode, 0)
        self.assertIn("Next free index: 1", result.stdout)  # only index 0 used

    def test_fidelity_passes_against_true_source(self):
        table_idx = next(i for i, n in enumerate(self.body["content"]) if n["type"] == "heading")
        # fidelity compares a single content node against a line range; use
        # the whole fixture file since that's what was converted into `nodes`
        # (a single flat list, not one node per line range) — so instead
        # build a tiny body whose ONE top-level node is everything, wrapped.
        wrapper_body = {"type": "doc", "version": 1, "content": [
            {"type": "expand", "attrs": {"title": "wrap", "localId": "w1"},
             "content": self.body["content"]}
        ]}
        wrapper_path = os.path.join(self.tmpdir.name, "wrapper.json")
        with open(wrapper_path, "w") as f:
            json.dump(wrapper_body, f)
        with open(os.path.join(FIXTURES_DIR, "sample.md"), encoding="utf-8") as f:
            n_lines = len(f.readlines())
        result = self._run("fidelity", wrapper_path, "0", os.path.join(FIXTURES_DIR, "sample.md"), "1", str(n_lines))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("FIDELITY OK", result.stdout)

    def test_fidelity_fails_on_deliberately_altered_source(self):
        table_idx = next(i for i, n in enumerate(self.body["content"]) if n["type"] == "heading")
        wrapper_body = {"type": "doc", "version": 1, "content": [
            {"type": "expand", "attrs": {"title": "wrap", "localId": "w1"},
             "content": self.body["content"]}
        ]}
        wrapper_path = os.path.join(self.tmpdir.name, "wrapper.json")
        with open(wrapper_path, "w") as f:
            json.dump(wrapper_body, f)
        # Copy the fixture but delete a line's worth of content, simulating a
        # summarization bug where built content no longer matches source.
        with open(os.path.join(FIXTURES_DIR, "sample.md"), encoding="utf-8") as f:
            lines = f.readlines()
        altered_path = os.path.join(self.tmpdir.name, "altered.md")
        with open(altered_path, "w", encoding="utf-8") as f:
            f.writelines(l for l in lines if "First bullet" not in l)
        result = self._run("fidelity", wrapper_path, "0", altered_path, "1", str(len(lines)))
        self.assertEqual(result.returncode, 1)
        self.assertIn("FIDELITY MISMATCH", result.stdout)


class TestShellScriptArgValidation(unittest.TestCase):
    """Exercise argument-validation error paths only — no network calls, so
    safe to run anytime without touching a live Confluence page. Live-network
    behavior (auth, actual GET/PUT) is verified manually per README's
    troubleshooting section, not here."""

    def _run_with_isolated_env(self, script_name, args, env_contents=None):
        script_path = os.path.join(SCRIPTS_DIR, script_name)
        with tempfile.TemporaryDirectory() as d:
            isolated_script = os.path.join(d, script_name)
            with open(script_path) as f:
                content = f.read()
            with open(isolated_script, "w") as f:
                f.write(content)
            os.chmod(isolated_script, 0o755)
            if env_contents is not None:
                with open(os.path.join(d, ".env"), "w") as f:
                    f.write(env_contents)
            clean_env = {k: v for k, v in os.environ.items()
                         if k not in ("ATLASSIAN_TOKEN", "ATLASSIAN_EMAIL", "CONFLUENCE_BASE_URL")}
            return subprocess.run(
                [isolated_script, *args], capture_output=True, text=True, env=clean_env,
            )

    def test_get_missing_page_id_errors(self):
        result = self._run_with_isolated_env(
            "confluence-get.sh", ["-o", "/tmp/unused.json"],
            env_contents='ATLASSIAN_EMAIL="a@b.com"\nATLASSIAN_TOKEN="x"\nCONFLUENCE_BASE_URL="https://example.atlassian.net"\n',
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("-p/--page-id is required", result.stderr)

    def test_get_missing_credentials_errors_without_leaking_defaults(self):
        result = self._run_with_isolated_env(
            "confluence-get.sh", ["-p", "123", "-o", "/tmp/unused.json"],
            env_contents=None,  # no .env at all
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("ATLASSIAN_EMAIL/ATLASSIAN_TOKEN not set", result.stderr)

    def test_get_missing_base_url_errors(self):
        result = self._run_with_isolated_env(
            "confluence-get.sh", ["-p", "123", "-o", "/tmp/unused.json"],
            env_contents='ATLASSIAN_EMAIL="a@b.com"\nATLASSIAN_TOKEN="x"\n',  # no CONFLUENCE_BASE_URL
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("no Confluence base URL", result.stderr)

    def test_push_missing_action_errors(self):
        result = self._run_with_isolated_env(
            "confluence-push.sh", ["-f", "/tmp/unused.json", "-t", "T"],
            env_contents='ATLASSIAN_EMAIL="a@b.com"\nATLASSIAN_TOKEN="x"\nCONFLUENCE_BASE_URL="https://example.atlassian.net"\n',
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("-a/--action is required", result.stderr)

    def test_push_missing_base_url_errors(self):
        result = self._run_with_isolated_env(
            "confluence-push.sh", ["-a", "update", "-f", "/tmp/unused.json", "-t", "T", "-p", "1"],
            env_contents='ATLASSIAN_EMAIL="a@b.com"\nATLASSIAN_TOKEN="x"\n',
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("no Confluence base URL", result.stderr)

    def test_no_org_specific_defaults_hardcoded_in_scripts(self):
        """This skill must stay org-agnostic outside of .env: no script may
        hardcode a specific Confluence site URL — .env's CONFLUENCE_BASE_URL
        is the only place that value should ever live."""
        for script_name in ("confluence-get.sh", "confluence-push.sh"):
            with open(os.path.join(SCRIPTS_DIR, script_name)) as f:
                content = f.read()
            self.assertNotIn("atlassian.net", content,
                              f"{script_name} has a hardcoded site URL — should come from .env")


if __name__ == "__main__":
    unittest.main(verbosity=2)
