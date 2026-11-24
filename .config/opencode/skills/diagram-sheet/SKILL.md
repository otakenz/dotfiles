---
name: diagram-sheet
description: Use when drawing architecture, integration or data-flow diagrams as printable A4-landscape HTML/PDF sheets, when a new sheet must look like earlier ones, or when answering a reviewer's annotated PDF of such a sheet with a side-by-side Q&A.
---

# A4-landscape diagram sheets

Hand-drawn SVG sheets, one A4-landscape `.page` per view, printed to PDF.
Every sheet uses the same frame, palette and legend, so several sheets (and
sheets by different people) read as one set.

## Start from the house style

1. If the project already has a sheet, copy its `<style>` and `<defs>` and
   keep its class names. Otherwise start from [template.html](template.html).
2. A page is exactly: `.hdr` (h1 title, `.sub` "n · what this view shows",
   right: `Page n / N` + state, e.g. branch) → `.body` (one `svg.dia`, then
   `.legend`) → `.ftr` (sheet title left, one abbreviation or rule right).
3. Draw in a fixed `viewBox` (e.g. `0 0 1400 830`), connections first so the
   boxes cover their ends.

## Palette: colour = ownership, not decoration

| Meaning | Class | Fill / stroke |
|---|---|---|
| Our framework, our container (dashed outline) | `.fw`, `.fw2` | `#e8f0fb` / `#2f6db5` |
| Our module wrapping vendor modules; vendor names inside in `.cc` brown | `.box` | `#f4f4f4` / `#8c8c8c` |
| In-house algorithm (no vendor calls) | `.own` | `#e9f5e9` / `#3c8d40` |
| Vendor deliverable | `.ccb` | `#fff1de` / `#e07b00` |
| Variant-only (one build, one product line), dashed | `.var` | `#f3edfa` / `#7b4bb7` |
| Not present / removed, dashed grey | `.ccx` | `#fafafa` / `#b0b0b0` |
| Rule or note | `.note` | `#fffbe6` / `#c9a800` |
| External actor, info box | `.info` | `#fff` / `#9a9a9a` |

Edges: black `a-k` data/control, orange `a-o` vendor API calls, red `a-r`
NN inference, blue `a-b` our API back to the caller. Chips: `.chip-nn` (NN),
`.chip-img` (reads the image), `.chip-var`. The legend lists exactly the
classes and edge colours used on that page.

## Print and check

```bash
python3 ~/.config/opencode/skills/diagram-sheet/print_pdf.py sheet.html --png /tmp/opencode/sheet-png
```

It fails when content is clipped. Then look at every PNG (read tool) before
handing over: text overlapping boxes, arrows ending in empty space, legend
entries for classes that are not on the page. A page count alone proves
nothing.

## Answering a reviewer's annotated PDF

When a reviewer marks up a sheet (highlights, sticky notes, replies), answer
in a Q&A sheet in the same style: their page left with numbered pins, answer
cards right, plus an overview and an open-points page.

1. Write the answers YAML. Ids are the PDF annotation order (page, then PDF
   order; replies count as their own item). List them first with
   `python3 -c "import qa_sheet as q,pathlib; [print(a['id'],a['page'],a['text'][:60]) for a in q.extract_annotations(pathlib.Path('X.pdf'))]"`
   run from the skill folder.

   ```yaml
   title: "Vendor review of the integration architecture – Q&A"
   review_date: "2026-11-20"
   reviewer: "Name (Vendor)"
   ours: "Us"            # label on our answers
   theirs: "Vendor"      # label on their comments
   sheet_date: "2026-11-24"
   footer: "optional, defaults to title"
   items:
     - id: 1
       page: 1
       anchor: "text they highlighted"
       comment: "their comment, shortened"
       answer: "2-4 lines, only what the code guarantees"
       question: "optional: what we need from them"
       status: "Agree – diagram fix"   # or: Agree – change on our side | Discuss | Question to reviewer
       followup: "optional: Us: action"
   ```
2. Check every claim in `answer` against the code before the meeting; an
   answer read out to the reviewer is a commitment. State what is
   guaranteed today and label everything else as a proposal.
3. Build: `python3 qa_sheet.py SOURCE.pdf answers.yaml out.html --style original_sheet.html --pdf`.
   It fails on missing or extra ids and splits a page's cards over more
   sheets until nothing is clipped.
4. For a repo deliverable, copy `qa_sheet.py` into the repo next to the
   answers, so others can rebuild it without this skill.

## Common mistakes

- Picking colours by taste (e.g. "ours green, vendor blue"): use the
  ownership table above.
- Inventing a new header/footer or legend layout per sheet.
- Edges starting in empty space at a container border: every edge starts
  at the box that makes the call; several callers join one bus line.
- A short `viewBox` (e.g. 1400×560) on a full page: the drawing scales to the
  width and leaves the bottom empty. Keep about 1400×830.
- Calling a sheet done from `pdfinfo` without looking at the pages.
