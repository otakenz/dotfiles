# PDF Report Dependencies

## Python Packages

```bash
pip install reportlab svglib pypdf
```

| Package | Version Tested | Purpose |
|---------|---------------|---------|
| `reportlab` | 4.5.1 | PDF generation — Paragraph, Table, Preformatted, BaseDocTemplate, PageTemplate, Frame, Flowable, Drawing |
| `svglib` | latest | Convert SVG (from graphviz) to reportlab Drawing objects |
| `pypdf` | latest | Verify PDF output — check outlines, annotations, named destinations, page count |

## System Tools

```bash
# Debian/Ubuntu
apt install graphviz

# macOS
brew install graphviz
```

| Tool | Version Tested | Purpose |
|------|---------------|---------|
| `dot` (graphviz) | 2.43.0 | Generate flow diagrams as SVG from DOT description files |
| `pdftotext` (poppler-utils) | any | Quick verification of PDF text content during development |

## Verify Installation

```bash
python3 -c "import reportlab; print('reportlab:', reportlab.Version)"
python3 -c "from svglib.svglib import svg2rlg; print('svglib: ok')"
python3 -c "from pypdf import PdfReader; print('pypdf: ok')"
dot -V
```

## Common Issues

- **`ValueError: format not resolved`** — `<a href="#anchor">` in a Paragraph has no matching `Bookmark` destination. Add `story.append(Bookmark("anchor", "Title"))` after the heading.
- **SVG too wide** — Set `size="6.5,8"; dpi=72;` in the DOT file header, or scale the drawing: `drawing.scale(avail_w / drawing.width, 1.0)`.
- **Table text truncated** — `col_widths` sum exceeds 482 pts (A4 with 20mm margins). Recalculate: `(595.27 - 2 × 20 × 2.8346) ≈ 482`.
- **HTML tags visible in table cells** — reportlab `Table` cells don't render HTML. Use `Paragraph(text, style)` objects instead of raw strings.
