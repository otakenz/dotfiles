# Implementation Patterns

## 1. Complete Table Pattern

```python
from reportlab.platypus import Table, TableStyle, Paragraph, KeepTogether

# a) Define cell style (no HTML rendering in Table cells)
style_tc = ParagraphStyle('TC', fontSize=8, leading=11, fontName='Helvetica', wordWrap='CJK')
style_th = ParagraphStyle('TH', parent=style_tc, fontName='Helvetica-Bold', textColor=white)

def _cell(text):
    """Wrap text as Paragraph. Strip any HTML tags — Table cells don't render HTML."""
    clean = re.sub(r'<[^>]+>', '', text)
    clean = clean.replace('&amp;', '&').replace('&lt;', '<').replace('&gt;', '>')
    return Paragraph(clean, style_tc)

def _hdr(text):
    return Paragraph(f'<b>{text}</b>', style_th)

# b) Build table with col_widths that sum <= 478
data = [[_hdr(h) for h in headers]] + [[_cell(c) for c in row] for row in rows]
t = Table(data, colWidths=col_widths, repeatRows=1)

# c) Style
style_cmds = [
    ('BACKGROUND', (0, 0), (-1, 0), TABLE_HDR_COLOR),
    ('FONTNAME', (0, 1), (-1, -1), 'Helvetica'),
    ('FONTSIZE', (0, 0), (-1, -1), 8),
    ('LEADING', (0, 0), (-1, -1), 11),
    ('BOTTOMPADDING', (0, 0), (-1, -1), 4),
    ('TOPPADDING', (0, 0), (-1, -1), 4),
    ('LEFTPADDING', (0, 0), (-1, -1), 6),
    ('RIGHTPADDING', (0, 0), (-1, -1), 6),
    ('GRID', (0, 0), (-1, -1), 0.5, LIGHT_GREY),
    ('VALIGN', (0, 0), (-1, -1), 'TOP'),
]
# Alternating rows
for i in range(1, len(data)):
    if i % 2 == 0:
        style_cmds.append(('BACKGROUND', (0, i), (-1, i), ALT_COLOR))
t.setStyle(TableStyle(style_cmds))

# d) Prevent orphan rows on small tables
story.append(KeepTogether(t))
```

## 2. Complete Flow Diagram Pattern

```python
import subprocess, os
from svglib.svglib import svg2rlg

# a) Write DOT file
DOT = '''\
digraph Flow {
    rankdir=TB; fontname="Helvetica"; fontsize=9;
    bgcolor="#fafbfc"; splines=polyline;
    nodesep=0.6; ranksep=0.5;
    size="6.5,8"; dpi=72;
    node [fontname="Helvetica" fontsize=9 shape=box style="filled,rounded"
          penwidth=1.3 margin="0.15,0.10"];
    A [label="Step A\\nDescription" fillcolor="#e8ecf1" color="#0f3460"];
    B [label="Step B\\nDescription" fillcolor="#d4dce8" color="#0f3460"];
    A -> B [color="#e94560" penwidth=1.5];
}
'''

svg_path = '/tmp/diagram.svg'
with open('/tmp/diagram.dot', 'w') as f:
    f.write(DOT)
subprocess.run(['dot', '-Tsvg', '/tmp/diagram.dot', '-o', svg_path], check=True)

# b) Load and embed
drawing = svg2rlg(svg_path)
avail_w = 595.27 - 2 * 20 * 2.8346  # A4 with 20mm margins ≈ 482 pts
if drawing and drawing.width > avail_w:
    scale = avail_w / drawing.width
    drawing.width *= scale
    drawing.height *= scale
    drawing.scale(scale, scale)
story.append(drawing)
```

**Key facts:**
- `Drawing` from svglib IS a Flowable — append directly to story
- `dot size` attribute controls output dimensions (inches × DPI)
- `splines=polyline` is more reliable than `ortho` across graphviz versions
- Set `dpi=72` in DOT to match PDF points

## 3. Complete Bookmark + Clickable TOC Pattern

```python
from reportlab.platypus.flowables import Flowable

class Bookmark(Flowable):
    """Creates a PDF named destination AND sidebar outline entry."""

    def __init__(self, name, title):
        Flowable.__init__(self)
        self._name = name
        self._title = title
        self.width = 0
        self.height = 1  # Must be > 0

    def wrap(self, availWidth, availHeight):
        return (0, 1)

    def draw(self):
        self.canv.bookmarkPage(self._name)
        self.canv.addOutlineEntry(self._title, self._name, 0, 1)


# In TOC (rendered first):
story.append(Paragraph(
    '<a href="#sec-intro" color="#0f3460">1. Introduction</a>',
    ParagraphStyle('TOCLink', fontSize=11, leading=20)))

# At each section (rendered after TOC):
story.append(Paragraph("1. Introduction", style_h1))
story.append(Bookmark("sec-intro", "1. Introduction"))
```

**Key facts:**
- `bookmarkPage(name)` creates the destination that `<a href="#name">` links to
- `addOutlineEntry(title, name, 0, 1)` adds it to the PDF sidebar outline
- The Bookmark flowable MUST be inserted AFTER its heading Paragraph
- The `<a href>` in the TOC can reference destinations defined LATER in the document
- Use `pypdf` to verify: check `r.outline` for sidebar entries, check page `/Annots` for link annotations

## 4. Complete DocTemplate Pattern

```python
from reportlab.platypus.doctemplate import BaseDocTemplate, PageTemplate, Frame

PAGE_W, PAGE_H = A4  # 595.27 × 841.89 pts
MARGIN = 20 * mm     # ~56.7 pts
AVAIL_W = PAGE_W - 2 * MARGIN

class DocTemplate(BaseDocTemplate):
    def __init__(self, filename, **kwargs):
        super().__init__(filename, **kwargs)
        frame = Frame(MARGIN, MARGIN, AVAIL_W, PAGE_H - 2 * MARGIN, id='main')
        self.addPageTemplates([
            PageTemplate(id='Main', frames=frame,
                         onPage=self._on_page, onPageEnd=self._on_page_end),
        ])

    def _on_page(self, canvas, doc):
        canvas.saveState()
        # Header line
        canvas.setStrokeColor(LIGHT_GREY)
        canvas.line(MARGIN, PAGE_H - MARGIN + 8, PAGE_W - MARGIN, PAGE_H - MARGIN + 8)
        canvas.setFont('Helvetica', 7)
        canvas.setFillColor(MID_GREY)
        canvas.drawString(MARGIN, PAGE_H - MARGIN + 12, "Document Title")
        canvas.drawRightString(PAGE_W - MARGIN, PAGE_H - MARGIN + 12, f"Page {canvas.getPageNumber()}")
        canvas.restoreState()

    def _on_page_end(self, canvas, doc):
        canvas.saveState()
        canvas.setStrokeColor(LIGHT_GREY)
        canvas.line(MARGIN, MARGIN - 8, PAGE_W - MARGIN, MARGIN - 8)
        canvas.setFont('Helvetica', 6)
        canvas.setFillColor(MID_GREY)
        canvas.drawCentredString(PAGE_W / 2, MARGIN - 16, f"Generated {date} — CONFIDENTIAL")
        canvas.restoreState()

# Build
doc = DocTemplate(output_path, pagesize=A4, title="...", author="...")
doc.build(story)
```

## 5. Cover Page Pattern

```python
def cover_background(canvas, doc):
    canvas.saveState()
    canvas.setFillColor(PRIMARY)
    canvas.rect(0, 0, PAGE_W, PAGE_H, fill=1, stroke=0)
    # Decorative accent line
    canvas.setStrokeColor(ACCENT)
    canvas.setLineWidth(3)
    canvas.line(MARGIN, PAGE_H * 0.42, PAGE_W * 0.4, PAGE_H * 0.42)
    canvas.restoreState()

cover_frame = Frame(MARGIN, MARGIN, AVAIL_W, PAGE_H - 2 * MARGIN, id='cover')
doc.addPageTemplates([
    PageTemplate(id='Cover', frames=cover_frame, onPage=cover_background),
])

# Cover content
story.append(Spacer(1, PAGE_H * 0.22))
story.append(Paragraph("Report Title<br/>Subtitle", style_cover_title))
story.append(Paragraph("Generated: Jan 1, 2025", style_cover_subtitle))
story.append(PageBreak())
```

## 6. Source Reference Table Pattern

When documenting code from multiple repositories (especially submodules):

```python
ref_files = [
    # (path_in_submodule, path_in_working_tree, github_repo, role_description)
    ("include/SensorTypes.h", "libcore/include/SensorTypes.h",
     "example-org/core", "Defines the sensor data structs"),
    ("decoders/IClient.h", "app/decoders/IClient.h",
     "example-org/app", "Interface: onDataUpdated()"),
]

table_data = []
for sub_path, tree_path, repo, role in ref_files:
    url = f"https://github.example.com/{repo}/blob/main/{sub_path}"
    table_data.append([tree_path, repo.split("/")[-1], url, role])

story.append(make_table(
    ["File (working tree)", "Repository", "Source URL", "Role"],
    table_data, col_widths=[145, 85, 118, 130]))
```

**To discover submodule repos:** `git -C <submodule-dir> remote -v` or check `.gitmodules`.

## 7. HTML-in-Paragraph Rules

`<font>`, `<b>`, `<i>`, `<a>` tags work in `Paragraph` body text (not table cells):

```python
# OK — body text
story.append(Paragraph(
    "Defined in <font face='Courier'>InputSensorTypes.h</font> (lines 404-412).",
    style_body))

# NOT OK — table cells (use Paragraph styles instead)
```

## 8. Common gotchas

| Symptom | Cause | Fix |
|---------|-------|-----|
| Table text cut off right side | `col_widths` sum > 478 | Recalculate, reduce column widths |
| `<font>` visible in table | Raw string in Table cell | Use Paragraph object, strip HTML |
| Flow diagram blank/invisible | Custom Flowable.draw() returns Drawing instead of drawing on canvas | Use `svg2rlg()` → append Drawing directly |
| TOC links all go to same page | `<a href>` without matching bookmark destination | Add `Bookmark` flowable after each heading |
| TOC links don't click | `<a name>` in invisible paragraph skipped by layout engine | Use `canvas.bookmarkPage()` in Bookmark flowable |
| Page X has 1 orphan table row, 90% empty | Table split across page boundary | Wrap table in `KeepTogether()` |
| Cover page uses body template | `addPageTemplates` replaces, doesn't append | Add cover template BEFORE body template in same list |
