#!/usr/bin/env python3
"""Build a side-by-side review Q&A sheet from a reviewer-annotated PDF.

Left: each annotated page (rendered with the reviewer's markup) with numbered
pins at the comments. Right: answer cards. Plus an overview page and an
open-points page. Ids in the answers YAML follow the PDF annotation order.

Usage: python3 qa_sheet.py SOURCE_PDF ANSWERS_YAML OUT_HTML [--style SHEET_HTML] [--pdf]
Needs pdftoppm, pypdf, PyYAML; --pdf needs Playwright and checks that no text is clipped.
"""

import argparse
import base64
import html
import pathlib
import subprocess
import sys
import tempfile

import yaml
from pypdf import PdfReader

HERE = pathlib.Path(__file__).resolve().parent
TEMPLATE = HERE / "template.html"
# Set by main(): source, answers, style, ours, theirs, date, footer.
CFG = {}

STATUS_CLASS = {
    "Agree – diagram fix": "st-fix",
    "Agree – change on our side": "st-change",
    "Discuss": "st-discuss",
    "Question to reviewer": "st-question",
}
COMMENT_SUBTYPES = ("/Highlight", "/Text")
# Rough text budget of the card column on one page, in characters.
COLUMN_BUDGET = 2900


def extract_annotations(pdf_path):
    """Return comment annotations in PDF order, with page size and position in percent."""
    found = []
    for page_no, page in enumerate(PdfReader(str(pdf_path)).pages, start=1):
        width = float(page.mediabox.width)
        height = float(page.mediabox.height)
        for ref in page.get("/Annots") or []:
            annot = ref.get_object()
            if annot.get("/Subtype") not in COMMENT_SUBTYPES:
                continue
            x0, y0, x1, y1 = (float(v) for v in annot["/Rect"])
            quad = annot.get("/QuadPoints")
            if quad:
                xs, ys = [float(v) for v in quad[0::2]], [float(v) for v in quad[1::2]]
                x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
            found.append({
                "page": page_no,
                "subtype": annot["/Subtype"],
                "text": str(annot.get("/Contents") or ""),
                "left": 100.0 * x0 / width,
                "top": 100.0 * (height - y1) / height,
                "width": 100.0 * (x1 - x0) / width,
                "height": 100.0 * (y1 - y0) / height,
            })
    for number, annot in enumerate(found, start=1):
        annot["id"] = number
        annot["pin_left"], annot["pin_top"] = annot["left"], annot["top"]
    spread_pins(found)
    return found


def spread_pins(annotations, min_gap=2.6):
    """Move a pin to the right while it would cover an earlier pin on the same page."""
    for i, annot in enumerate(annotations):
        earlier = [a for a in annotations[:i] if a["page"] == annot["page"]]
        while any(abs(a["pin_left"] - annot["pin_left"]) < min_gap and abs(a["pin_top"] - annot["pin_top"]) < min_gap * 1.4
                  for a in earlier):
            annot["pin_left"] += min_gap


def check_answers(annotations, items):
    """Fail when the answers do not match the annotations one to one."""
    errors = []
    by_id = {item["id"]: item for item in items}
    if len(by_id) != len(items):
        errors.append("duplicate ids in the answers file")
    expected = {a["id"] for a in annotations}
    for missing in sorted(expected - by_id.keys()):
        errors.append(f"no answer for annotation {missing}")
    for extra in sorted(by_id.keys() - expected):
        errors.append(f"answer {extra} has no annotation")
    for annot in annotations:
        item = by_id.get(annot["id"])
        if item is None:
            continue
        if item["page"] != annot["page"]:
            errors.append(f"item {item['id']}: page {item['page']} but annotation is on page {annot['page']}")
        if item["status"] not in STATUS_CLASS:
            errors.append(f"item {item['id']}: unknown status {item['status']!r}")
    if errors:
        sys.exit("qa_sheet: " + "; ".join(errors))
    return by_id


def render_pages(pdf_path, dpi=150):
    """Render every page to PNG (with annotations) and return base64 strings in page order."""
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(["pdftoppm", "-r", str(dpi), "-png", str(pdf_path), f"{tmp}/p"], check=True)
        files = sorted(pathlib.Path(tmp).glob("p-*.png"), key=lambda p: int(p.stem.split("-")[1]))
        return [base64.b64encode(f.read_bytes()).decode() for f in files]


def base_css(style_html):
    """Reuse the page frame of the reviewed sheet (or the template) so both documents look alike."""
    text = pathlib.Path(style_html).read_text(encoding="utf-8")
    style = text[text.index("<style>") + len("<style>"):text.index("</style>")]
    return style[:style.index("/* SVG styles */")]


EXTRA_CSS = """
  .qa { display: flex; gap: 4mm; flex: 1; min-height: 0; }
  .qa .shot { flex: 0 0 64%; position: relative; align-self: flex-start; border: 1px solid #bbb; }
  .qa .shot img { width: 100%; display: block; }
  .qa .cards { flex: 1; display: flex; flex-direction: column; gap: 2.2mm; min-height: 0; overflow: hidden; }
  .pin { position: absolute; transform: translate(-90%, -90%); width: 5.2mm; height: 5.2mm; border-radius: 50%;
         background: #c62828; color: #fff; font-size: 7.5pt; font-weight: 700; display: flex; align-items: center;
         justify-content: center; box-shadow: 0 0 0 1.2px #fff, 0 1px 3px rgba(0,0,0,.4); }
  .pin.dim { background: #9a9a9a; }
  .mark { position: absolute; border: 1.4px solid #c62828; border-radius: 0.8mm; }
  .qcard { border: 1px solid #c8c8c8; border-left: 4px solid #2f6db5; border-radius: 1.6mm; padding: 1.6mm 2.4mm;
           font-size: 7.6pt; line-height: 1.32; }
  .qcard .top { display: flex; align-items: center; gap: 1.6mm; margin-bottom: 0.8mm; }
  .qcard .num { flex: 0 0 auto; width: 4.6mm; height: 4.6mm; border-radius: 50%; background: #c62828; color: #fff;
                font-size: 7pt; font-weight: 700; display: flex; align-items: center; justify-content: center; }
  .qcard .anchor { font-weight: 700; font-size: 8.4pt; flex: 1; }
  .qcard .cc { color: #9a4f00; font-style: italic; margin-bottom: 0.8mm; }
  .qcard .q { margin-top: 0.8mm; font-weight: 700; color: #6a3d9a; }
  .lab { font-weight: 700; font-style: normal; }
  .chip { display: inline-block; font-size: 6.6pt; font-weight: 700; padding: 0.2mm 1.4mm; border-radius: 1mm;
          border: 1px solid; white-space: nowrap; }
  .st-fix { color: #2f6db5; border-color: #2f6db5; background: #e8f0fb; }
  .st-change { color: #9a4f00; border-color: #e07b00; background: #fff1de; }
  .st-discuss { color: #7b4bb7; border-color: #7b4bb7; background: #f3edfa; }
  .st-question { color: #3c8d40; border-color: #3c8d40; background: #e9f5e9; }
  .qcard.st-fix { border-left-color: #2f6db5; } .qcard.st-change { border-left-color: #e07b00; }
  .qcard.st-discuss { border-left-color: #7b4bb7; } .qcard.st-question { border-left-color: #3c8d40; }
  .qcard.st-fix, .qcard.st-change, .qcard.st-discuss, .qcard.st-question { background: #fff; color: #1a1a1a; }
  table.sum { border-collapse: collapse; width: 100%; font-size: 8.6pt; margin-top: 2mm; }
  table.sum th { background: #2f6db5; color: #fff; text-align: left; padding: 1.2mm 2mm; }
  table.sum td { border-bottom: 1px solid #ddd; padding: 1.1mm 2mm; vertical-align: top; }
  table.sum td.n { font-weight: 700; color: #c62828; width: 8mm; }
  .counts { display: flex; gap: 4mm; margin-top: 2mm; font-size: 9pt; align-items: center; }
  .cols { display: flex; gap: 6mm; flex: 1; min-height: 0; }
  .cols > div { flex: 1; }
  .cols h2 { font-size: 11pt; margin: 0 0 2mm 0; }
  .cols ol { margin: 0; padding-left: 0; list-style: none; font-size: 8.6pt; line-height: 1.4; }
  .cols li { margin-bottom: 1.4mm; }
"""


def esc(text):
    return html.escape(str(text).strip())


def frame(title, sub, page_label, body):
    return f"""<div class="page">
  <div class="hdr"><div><h1>{esc(title)}</h1><div class="sub">{esc(sub)}</div></div>
    <div class="right"><b>{esc(page_label)}</b><br>Draft for discussion, {esc(CFG["date"])}</div></div>
  <div class="body">{body}</div>
  <div class="ftr"><span>{esc(CFG["footer"])}</span>
    <span>Pins and numbers refer to the comments in {esc(CFG["source"].name)}</span></div>
</div>"""


def chip(status):
    return f'<span class="chip {STATUS_CLASS[status]}">{esc(status)}</span>'


def card(item):
    question = f'<div class="q">Question: {esc(item["question"])}</div>' if item.get("question") else ""
    return f"""<div class="qcard {STATUS_CLASS[item['status']]}">
  <div class="top"><span class="num">{item['id']}</span><span class="anchor">{esc(item['anchor'])}</span>{chip(item['status'])}</div>
  <div class="cc"><span class="lab">{esc(CFG["theirs"])}:</span> {esc(item['comment'])}</div>
  <div><span class="lab">{esc(CFG["ours"])}:</span> {esc(item['answer'])}</div>{question}
</div>"""


def card_size(item):
    return len(item["comment"]) + len(item["answer"]) + len(item.get("question") or "") + 160


def greedy_chunks(items, budget):
    chunks, current, used = [], [], 0
    for item in items:
        size = card_size(item)
        if current and used + size > budget:
            chunks.append(current)
            current, used = [], 0
        current.append(item)
        used += size
    if current:
        chunks.append(current)
    return chunks


def chunk_cards(items, column_budget):
    """Split one page's cards into as few columns as the text budget allows, filled evenly."""
    count = len(greedy_chunks(items, column_budget))
    if count <= 1:
        return [items] if items else []
    total = sum(card_size(i) for i in items)
    budget = total / count
    while len(greedy_chunks(items, budget)) > count:
        budget += 50
    return greedy_chunks(items, budget)


def shot(image_b64, annotations, active_ids):
    marks = []
    for a in annotations:
        dim = "" if a["id"] in active_ids else " dim"
        if a["subtype"] == "/Highlight" and a["id"] in active_ids:
            marks.append(f'<div class="mark" style="left:{a["left"]:.2f}%;top:{a["top"]:.2f}%;'
                         f'width:{a["width"]:.2f}%;height:{a["height"]:.2f}%"></div>')
        marks.append(f'<div class="pin{dim}" style="left:{a["pin_left"]:.2f}%;top:{a["pin_top"]:.2f}%">{a["id"]}</div>')
    return f'<div class="shot"><img src="data:image/png;base64,{image_b64}" alt="">{"".join(marks)}</div>'


def next_step(item):
    owners = [name for name, key in ((CFG["ours"], "followup"), (CFG["theirs"], "question")) if item.get(key)]
    return " + ".join(owners) or "–"


def cover(data, items):
    rows = "".join(
        f'<tr><td class="n">{i["id"]}</td><td>{i["page"]}</td><td>{esc(i["anchor"])}</td>'
        f'<td>{esc(i["comment"])}</td><td>{chip(i["status"])}</td><td>{next_step(i)}</td></tr>' for i in items)
    counts = "".join(f'<span>{chip(s)} × {sum(1 for i in items if i["status"] == s)}</span>' for s in STATUS_CLASS)
    body = f"""<div class="counts"><b>{len(items)} comments</b>{counts}</div>
<table class="sum"><tr><th>#</th><th>Page</th><th>Where</th><th>{esc(CFG["theirs"])} comment</th><th>Status</th><th>Next step</th></tr>{rows}</table>"""
    return frame(data["title"], f'Comments by {data["reviewer"]}, {data["review_date"]}; answers by {CFG["ours"]}',
                 "Overview", body)


def closing(items):
    followups = "".join(f'<li><b>#{i["id"]}</b> {esc(i["followup"])}</li>' for i in items if i.get("followup"))
    questions = "".join(f'<li><b>#{i["id"]}</b> {esc(i["question"])}</li>' for i in items if i.get("question"))
    body = f"""<div class="cols"><div><h2>Questions to {esc(CFG["theirs"])}</h2><ol>{questions}</ol></div>
<div><h2>Follow-ups</h2><ol>{followups}</ol></div></div>"""
    return frame("Open points", "Collected from the cards; to be confirmed in the meeting", "Summary", body)


def build_html(column_budget=COLUMN_BUDGET):
    data = yaml.safe_load(CFG["answers"].read_text(encoding="utf-8"))
    annotations = extract_annotations(CFG["source"])
    by_id = check_answers(annotations, data["items"])
    items = [by_id[a["id"]] for a in annotations]
    images = render_pages(CFG["source"])

    pages = [cover(data, items)]
    for page_no, image in enumerate(images, start=1):
        page_annots = [a for a in annotations if a["page"] == page_no]
        page_items = [by_id[a["id"]] for a in page_annots]
        chunks = chunk_cards(page_items, column_budget) or [[]]
        for part, chunk in enumerate(chunks, start=1):
            label = f"Page {page_no} / {len(images)}" + (f" ({part}/{len(chunks)})" if len(chunks) > 1 else "")
            active = {i["id"] for i in chunk}
            body = f'<div class="qa">{shot(image, page_annots, active)}<div class="cards">{"".join(card(i) for i in chunk)}</div></div>'
            pages.append(frame(data["title"], f"Their page {page_no} with comments (left) and our answers (right)", label, body))
    pages.append(closing(items))

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>{esc(data['title'])}</title>
<style>{base_css(CFG["style"])}{EXTRA_CSS}</style>
</head>
<body>
{"".join(pages)}
</body>
</html>
"""


CLIPPED_JS = """() => [...document.querySelectorAll('.page')].flatMap(p =>
    [...p.querySelectorAll('.cards, .body')].filter(e => e.scrollHeight > e.clientHeight + 1)
      .map(() => p.querySelector('.hdr .right b').textContent))"""


def write_fitting_pdf(html_path, pdf_path):
    """Write HTML and PDF, lowering the card budget until no page clips its text."""
    from playwright.sync_api import sync_playwright

    with sync_playwright() as pw:
        browser = pw.chromium.launch()
        page = browser.new_page()
        page.emulate_media(media="print")
        for budget in range(COLUMN_BUDGET, 900, -200):
            html_path.write_text(build_html(budget), encoding="utf-8")
            page.goto(html_path.resolve().as_uri())
            clipped = page.evaluate(CLIPPED_JS)
            if not clipped:
                page.pdf(path=str(pdf_path), prefer_css_page_size=True, print_background=True)
                browser.close()
                return
        browser.close()
    sys.exit(f"qa_sheet: text clipped on {sorted(set(clipped))} even with the smallest budget; shorten the answers")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("source_pdf", type=pathlib.Path, help="PDF with the reviewer's annotations")
    parser.add_argument("answers", type=pathlib.Path, help="answers YAML (see SKILL.md)")
    parser.add_argument("out_html", type=pathlib.Path)
    parser.add_argument("--style", type=pathlib.Path, default=TEMPLATE,
                        help="sheet HTML whose page CSS to reuse (default: the skill template)")
    parser.add_argument("--pdf", action="store_true", help="also print to PDF next to the HTML")
    args = parser.parse_args()
    data = yaml.safe_load(args.answers.read_text(encoding="utf-8"))
    CFG.update(source=args.source_pdf, answers=args.answers, style=args.style,
               ours=data["ours"], theirs=data["theirs"], date=str(data["sheet_date"]),
               footer=data.get("footer", data["title"]))
    if args.pdf:
        pdf_path = args.out_html.with_suffix(".pdf")
        write_fitting_pdf(args.out_html, pdf_path)
        print(f"wrote {args.out_html} and {pdf_path}")
    else:
        args.out_html.write_text(build_html(), encoding="utf-8")
        print(f"wrote {args.out_html} (text fit not checked; use --pdf)")


if __name__ == "__main__":
    main()
