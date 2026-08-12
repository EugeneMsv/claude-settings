"""grep-token-killer PostToolUse entry / orchestrator.

Single responsibility: wire the modules and decide rewrite vs passthrough. Every
path appends exactly one JSONL audit record; only the active mode with a real,
sufficient saving emits `updatedToolOutput`. A global try/except net guarantees
that on ANY failure the hook emits nothing (`{}`) so the original tool output
passes through untouched. No `systemMessage` is ever produced (silent by design).
"""
from __future__ import annotations

import json
import sys
from datetime import datetime

import compactor
import config
import detector
import hook_io
import logger
import metrics
import parser


# Detector reasons that mean the command is not a grep at all -> silent no-op,
# no audit record (the JSONL holds one record per grep actually seen).
_NOT_A_GREP = frozenset({"not_grep_first_stage", "empty_command", "unparseable_command"})


def _timestamp(now):
    moment = now if now is not None else datetime.now()
    return moment.strftime("%Y-%m-%d %H:%M:%S")


def _base_record(command, mode, eligible, now):
    return {
        "timestamp": _timestamp(now),
        "command": command,
        "mode": mode,
        "eligible": eligible,
        "passthrough_reason": None,
        "original_tokens": None,
        "compacted_tokens": None,
        "tokens_removed": None,
        "pct_saved": None,
        "original_bytes": None,
        "compacted_bytes": None,
        "lines": None,
        "transforms": None,
    }


def run(raw_input, env=None, log_path=None, now=None):
    """Return the response dict to print ({} = passthrough). Never raises."""
    try:
        cfg = config.load(env)
        parsed_input = hook_io.parse_input(raw_input)
        if parsed_input is None or parsed_input.tool_name != "Bash" or not parsed_input.command:
            return {}

        decision = detector.decide(parsed_input.command)
        if not decision.eligible and decision.reason in _NOT_A_GREP:
            return {}
        record = _base_record(parsed_input.command, cfg.mode, decision.eligible, now)

        if not decision.eligible:
            return _passthrough(record, decision.reason, log_path)
        if parsed_input.out_of_band:
            return _passthrough(record, "out_of_band_output", log_path)

        parse_result = parser.parse(parsed_input.stdout, decision.ctx)
        if not parse_result.confident:
            return _passthrough(record, parse_result.reason or "parse_low_confidence", log_path)
        if len(parse_result.records) < cfg.min_lines:
            return _passthrough(record, "below_min_lines", log_path)

        compacted = compactor.compact(parse_result.records, cfg)
        before = metrics.estimate_tokens(parsed_input.stdout)
        after = metrics.estimate_tokens(compacted.text)
        savings = metrics.token_savings(before, after)
        record.update(
            original_tokens=before,
            compacted_tokens=after,
            tokens_removed=savings.removed,
            pct_saved=savings.pct,
            original_bytes=len(parsed_input.stdout),
            compacted_bytes=len(compacted.text),
            lines=len(parse_result.records),
            transforms=list(compacted.transforms),
        )

        if len(compacted.text) >= len(parsed_input.stdout) or savings.pct < cfg.min_saving_pct:
            return _passthrough(record, "savings_below_min", log_path)

        logger.append(record, log_path)
        message = _system_message(cfg.mode, savings, len(parse_result.records))
        if cfg.mode == "active":
            response = hook_io.build_updated_output(parsed_input.tool_response, compacted.text)
            response["systemMessage"] = message
            return response
        return {"systemMessage": message}
    except Exception:
        return {}


def _system_message(mode, savings, lines):
    verb = "saved" if mode == "active" else "would save"
    return (f"grep-token-killer: {verb} {savings.pct}% "
            f"(~{savings.removed} tokens, {lines} lines)")


def _passthrough(record, reason, log_path):
    record["passthrough_reason"] = reason
    logger.append(record, log_path)
    return {}


def main():
    response = run(sys.stdin.read())
    if response:
        sys.stdout.write(json.dumps(response))
    sys.exit(0)


if __name__ == "__main__":
    main()
