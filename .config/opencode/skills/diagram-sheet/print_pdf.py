#!/usr/bin/env python3
"""Print an A4-landscape diagram sheet to PDF with Playwright Chromium.

Fails (exit 1) when a page's content is clipped, i.e. an element inside a
`.page` scrolls instead of fitting. Then optionally renders every PDF page to
PNG so the sheet can be checked by eye.

Usage: python3 print_pdf.py SHEET.html [OUT.pdf] [--png DIR]
"""

import argparse
import pathlib
import subprocess
import sys

CLIPPED_JS = """() => [...document.querySelectorAll('.page')].flatMap((p, i) =>
    [...p.querySelectorAll('.body, .body > *, .cards')]
      .filter(e => e.scrollHeight > e.clientHeight + 1 || e.scrollWidth > e.clientWidth + 1)
      .map(e => `page ${i + 1}: ${e.className || e.tagName}`))"""


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("html", type=pathlib.Path)
    parser.add_argument("pdf", type=pathlib.Path, nargs="?")
    parser.add_argument("--png", type=pathlib.Path, help="also render each PDF page to DIR/page-N.png")
    args = parser.parse_args()
    pdf = args.pdf or args.html.with_suffix(".pdf")

    from playwright.sync_api import sync_playwright

    with sync_playwright() as pw:
        browser = pw.chromium.launch()
        page = browser.new_page()
        page.emulate_media(media="print")
        page.goto(args.html.resolve().as_uri())
        clipped = page.evaluate(CLIPPED_JS)
        if clipped:
            browser.close()
            sys.exit("print_pdf: content clipped: " + "; ".join(clipped))
        page.pdf(path=str(pdf), prefer_css_page_size=True, print_background=True)
        pages = page.evaluate("document.querySelectorAll('.page').length")
        browser.close()
    print(f"wrote {pdf} ({pages} pages)")

    if args.png:
        args.png.mkdir(parents=True, exist_ok=True)
        subprocess.run(["pdftoppm", "-r", "80", "-png", str(pdf), str(args.png / "page")], check=True)
        print(f"rendered PNGs to {args.png}")


if __name__ == "__main__":
    main()
