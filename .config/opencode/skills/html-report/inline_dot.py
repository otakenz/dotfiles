#!/usr/bin/env python3
"""Replace <!-- dot: /path/x.dot --> placeholders in HTML files with inline SVG.

Usage: python3 inline_dot.py report.html [more.html ...]
Each .dot is rendered with `dot -Tsvg`; the XML prolog/doctype is dropped.
Exit 1 if a .dot file is missing or dot fails; files are only rewritten on success.
"""
import re
import subprocess
import sys

PLACEHOLDER = re.compile(r"<!--\s*dot:\s*(\S+?\.dot)\s*-->")


def render(path: str) -> str:
    svg = subprocess.run(["dot", "-Tsvg", path], check=True, capture_output=True, text=True).stdout
    start = svg.find("<svg")
    if start < 0:
        raise RuntimeError(f"{path}: no <svg> in dot output")
    return svg[start:].strip()


def main(files: list[str]) -> int:
    if not files:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    for name in files:
        with open(name, encoding="utf-8") as f:
            html = f.read()
        try:
            out, n = PLACEHOLDER.subn(lambda m: render(m.group(1)), html)
        except (OSError, subprocess.CalledProcessError, RuntimeError) as e:
            print(f"{name}: {e}", file=sys.stderr)
            return 1
        with open(name, "w", encoding="utf-8") as f:
            f.write(out)
        print(f"{name}: {n} diagram(s) inlined")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
