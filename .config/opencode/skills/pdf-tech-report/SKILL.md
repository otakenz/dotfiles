---
name: pdf-tech-report
description: "Use when asked to \"create a PDF\" or write a \"technical report\": A4 PDF with graphviz diagrams, TOC, code, appendices."
---

# PDF Technical Report Generation

Generate polished A4 PDFs using reportlab. This skill captures proven patterns that avoid
common pitfalls with tables, diagrams, links, and layout.

## Pre-Flight

```bash
pip install reportlab svglib pypdf
```

System requirement: `dot` (graphviz) for flow diagrams. Install via `apt install graphviz` or equivalent.

## Quick Start

```python
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.platypus import Paragraph, Spacer, PageBreak, Table, Preformatted, KeepTogether, HRFlowable
from reportlab.platypus.doctemplate import PageTemplate, BaseDocTemplate, Frame
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.colors import HexColor
from reportlab.lib.enums import TA_LEFT, TA_CENTER, TA_JUSTIFY
from reportlab.platypus.flowables import Flowable
from reportlab.graphics.shapes import Drawing
from svglib.svglib import svg2rlg
```

## Workflow

1. **Set up document**: `BaseDocTemplate` with `PageTemplate` and `Frame`
2. **Define styles**: color palette, H1/H2/H3/body/code/caption styles
3. **Build cover page**: `PageTemplate` with `onPage` background callback
4. **Add page headers/footers**: via `onPage`/`onPageEnd` callbacks
5. **Build content**: sections with tables, diagrams, code blocks
6. **Add TOC**: clickable entries using `Bookmark` flowable
7. **Add source appendix**: file paths + repo URLs in a table
8. **Build**: `doc.build(story)`

## Critical Patterns

### Tables

```python
# ALWAYS wrap cells in Paragraph objects — NEVER use raw strings with HTML tags
style_tc = ParagraphStyle('TC', fontSize=8, leading=11, fontName='Helvetica')
def _cell(text):
    clean = re.sub(r'<[^>]+>', '', text)  # strip HTML
    return Paragraph(clean, style_tc)

# BUILD table with Paragraph cells
data = [[_cell(c) for c in row] for row in rows]
t = Table(data, colWidths=col_widths, repeatRows=1)

# COLUMN WIDTHS: sum must be ≤ 478 pts for A4 with 20mm margins
# A4 = 595.27 pts, margins = 20mm × 2 = 113.4 pts, available = 482 pts
```

**Rules for tables:**
- Wrap small tables (< 10 rows) in `KeepTogether()` to prevent orphan rows
- No `<font>`, `<b>`, `<a>` tags in table cells — use Paragraph styles instead
- Set `repeatRows=1` for multi-page tables with headers
- Verify `sum(col_widths) + padding ≤ 482`

### Flow Diagrams

Use graphviz → SVG → svglib → reportlab. **Never use custom Flowable subclasses.**

```python
# 1. Write DOT file
with open('/tmp/diagram.dot', 'w') as f:
    f.write('digraph { ... }')

# 2. Generate SVG
import subprocess
subprocess.run(['dot', '-Tsvg', '/tmp/diagram.dot', '-o', '/tmp/diagram.svg'])

# 3. Embed in PDF
drawing = svg2rlg('/tmp/diagram.svg')
scale = min(avail_width / drawing.width, 1.0)
drawing.scale(scale, scale)
story.append(drawing)
```

**Rules for diagrams:**
- Set `size="6.5,8"; dpi=72;` in DOT for A4 fit
- Use `splines=polyline` (ortho unreliable in older graphviz)
- SVG output: 468×336 pts fits in A4 with 20mm margins
- `Drawing` from svglib is itself a valid Flowable — append directly

### Clickable TOC + Sidebar Bookmarks

Use `Bookmark` flowable with `canvas.bookmarkPage()`. **Never rely on `<a>` tags alone.**

```python
class Bookmark(Flowable):
    def __init__(self, name, title):
        Flowable.__init__(self)
        self._name = name
        self._title = title
        self.width = self.height = 0

    def wrap(self, w, h):
        return (0, 1)

    def draw(self):
        self.canv.bookmarkPage(self._name)
        self.canv.addOutlineEntry(self._title, self._name, 0, 1)

# After each H1:
story.append(Paragraph("1. Overview", style_h1))
story.append(Bookmark("sec-overview", "1. Overview"))

# In TOC, use <a href="#sec-overview"> for clickable text
story.append(Paragraph('<a href="#sec-overview" color="#0f3460">1. Overview</a>', style_toc))
```

**Rules for TOC:**
- `Bookmark` destination MUST be added AFTER the heading Paragraph
- The `<a href="#name">` in TOC resolves to the bookmark destination
- Bookmarks also appear in the PDF reader's sidebar navigation panel

### Code Blocks

```python
style_code = ParagraphStyle('Code', fontSize=8, leading=11, fontName='Courier',
    backColor=HexColor("#f4f4f5"), borderWidth=0.5, borderPadding=6)

def code(text):
    return Preformatted(text, style_code)

story.append(code("""\
    struct RPI_DMS_Data_t {
        uint8_t version;
        ...
    };"""))
```

### Cover Page

```python
def cover_bg(canvas, doc):
    canvas.setFillColor(PRIMARY_COLOR)
    canvas.rect(0, 0, PAGE_W, PAGE_H, fill=1, stroke=0)

cover_frame = Frame(MARGIN, MARGIN, AVAIL_W, PAGE_H - 2 * MARGIN, id='cover')
doc.addPageTemplates([PageTemplate(id='Cover', frames=cover_frame, onPage=cover_bg)])
```

### Source Reference Appendix

When documenting code from multiple repos (especially with submodules), include a table with:

```python
columns = ["File (working tree)", "Repository", "Source URL", "Role"]
# Each row: file path in working tree, repo short name, full GitHub URL, one-line role
```

Get submodule remotes: `git -C <submodule-path> remote -v`

### Page Headers/Footers

Use `BaseDocTemplate` with `_on_page`/`_on_page_end` callbacks, NOT `SimpleDocTemplate`:

```python
class DocTemplate(BaseDocTemplate):
    def _on_page(self, canvas, doc):
        canvas.drawString(MARGIN, PAGE_H - MARGIN + 12, "Document Title")
        canvas.drawRightString(PAGE_W - MARGIN, PAGE_H - MARGIN + 12, f"Page {canvas.getPageNumber()}")
```

## Reference Files

- **[patterns.md](references/patterns.md)** — Detailed implementation examples for each pattern above
- **[dependencies.md](references/dependencies.md)** — Complete package list with version notes
