"""Word list and replacement rules from ~/.config/voice-input."""

import re
import sys
from pathlib import Path

Rule = tuple[re.Pattern[str], str]


def _lines(path: Path) -> list[str]:
    try:
        text = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return []
    lines = (line.strip() for line in text.splitlines())
    return [line for line in lines if line and not line.startswith("#")]


def load_vocab(path: Path) -> str:
    terms = _lines(path)
    return ", ".join(terms) + "." if terms else ""


def load_replacements(path: Path) -> list[Rule]:
    rules: list[Rule] = []
    for line in _lines(path):
        pattern, sep, replacement = line.partition(" => ")
        if not sep:
            print(f"voice-input: no ' => ' in rule: {line}", file=sys.stderr)
            continue
        try:
            compiled = re.compile(pattern)
            compiled.sub(replacement, "")  # checks group references
            rules.append((compiled, replacement))
        except (re.error, IndexError) as err:
            print(f"voice-input: bad rule {line!r}: {err}", file=sys.stderr)
    return rules


def apply_replacements(text: str, rules: list[Rule]) -> str:
    for pattern, replacement in rules:
        text = pattern.sub(replacement, text)
    return " ".join(text.split())
