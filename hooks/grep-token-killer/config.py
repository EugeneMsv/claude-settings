"""Resolve grep-token-killer runtime config: env -> config.json -> defaults.

Single responsibility: produce an immutable Config. Never raises on bad input;
an invalid value for a field falls back to that field's default.
"""
from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path

VALID_MODES = ("active", "shadow")

DEFAULT_MODE = "active"
DEFAULT_LINE_MAX_OUTPUT_CHARS = 500
DEFAULT_MIN_LINES = 3
DEFAULT_MIN_SAVING_PCT = 10.0

_CONFIG_FILENAME = "config.json"


@dataclass(frozen=True)
class Config:
    mode: str = DEFAULT_MODE
    line_max_output_chars: int = DEFAULT_LINE_MAX_OUTPUT_CHARS
    min_lines: int = DEFAULT_MIN_LINES
    min_saving_pct: float = DEFAULT_MIN_SAVING_PCT


def _coerce_mode(value, fallback):
    return value if value in VALID_MODES else fallback


def _coerce_int(value, fallback):
    try:
        coerced = int(value)
    except (TypeError, ValueError):
        return fallback
    return coerced if coerced >= 0 else fallback


def _coerce_float(value, fallback):
    try:
        coerced = float(value)
    except (TypeError, ValueError):
        return fallback
    return coerced if coerced >= 0 else fallback


def _load_file(config_path):
    try:
        with open(config_path, "r", encoding="utf-8") as handle:
            loaded = json.load(handle)
    except (OSError, ValueError):
        return {}
    return loaded if isinstance(loaded, dict) else {}


def load(env=None, config_path=None):
    """Resolve config with precedence env > config.json > defaults."""
    env = os.environ if env is None else env
    if config_path is None:
        config_path = Path(__file__).resolve().parent / _CONFIG_FILENAME
    file_cfg = _load_file(config_path)

    return Config(
        mode=_coerce_mode(
            env.get("GTK_MODE", file_cfg.get("mode", DEFAULT_MODE)), DEFAULT_MODE),
        line_max_output_chars=_coerce_int(
            env.get("GTK_LINE_MAX_OUTPUT_CHARS",
                    file_cfg.get("line_max_output_chars", DEFAULT_LINE_MAX_OUTPUT_CHARS)),
            DEFAULT_LINE_MAX_OUTPUT_CHARS),
        min_lines=_coerce_int(
            env.get("GTK_MIN_LINES", file_cfg.get("min_lines", DEFAULT_MIN_LINES)),
            DEFAULT_MIN_LINES),
        min_saving_pct=_coerce_float(
            env.get("GTK_MIN_SAVING_PCT", file_cfg.get("min_saving_pct", DEFAULT_MIN_SAVING_PCT)),
            DEFAULT_MIN_SAVING_PCT),
    )
