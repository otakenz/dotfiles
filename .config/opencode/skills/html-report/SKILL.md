---
name: html-report
description: Use when writing a milestone, status or progress report as an HTML page, or updating a project's report overview (docs/reports/index.html).
---

# HTML milestone report

One self-contained HTML file per milestone, plus `docs/reports/index.html`.
Readers skim: pictures and numbers first, text short. Start from
[template.html](template.html) and keep its CSS and section order.

## Inputs

A facts file (the controller writes it). Every number, date, name and link
in the report comes from it. A fact you would like but cannot find: leave it
out. Never round, convert or combine numbers beyond what the facts state.

## The report is these parts, in this order

1. **Banner:** `M<n> · <title>`, project, date, one-line outcome (≤ 15
   words), status badge (`done`, `progress`, `next`, `planned`, `blocked`).
2. **Roadmap strip:** one entry per milestone from the facts, classes per
   status, `current` on this one; link only reports that exist.
3. **Cards:** 3–5 key numbers, each with a ≤ 6-word label.
4. **At a glance:** 1–3 Graphviz diagrams (see below), each with a caption.
5. **Goal → result table:** 4–6 rows; status cell `ok` ✔, `warn` ⚠, `bad` ✘.
6. **Key decisions → why:** table, 2–5 rows, one per decision in the facts
   (what was decided, the reason in ≤ 20 words, what it costs or enables).
   Readers ask "why" first; keep this visible, not in Details.
7. **Open issues | Next:** two columns, ≤ 5 bullets each, links to issues.
8. **Details (`<details>`, collapsed):** how it was done, links; bullets
   ≤ 20 words.
9. **Footer.**

Visible text outside `<details>`: ≤ 250 words.

## Diagrams

Graphviz only, inlined as SVG:

Write each diagram as a `.dot` file under `/tmp/opencode/` and put a
placeholder inside its `<figure>`: `<!-- dot: /tmp/opencode/<name>.dot -->`.
Whoever has a shell then runs
`python3 ~/.config/opencode/skills/html-report/inline_dot.py <report>.html`,
which swaps every placeholder for the rendered SVG (fails if a `.dot` is broken).
Style in the `.dot`: `rankdir=LR`,
`node [shape=box, style="rounded,filled", fillcolor="#eef3f8",
fontname="Helvetica", fontsize=11]`, done/ok `#d3f9d8`, planned `#f1f3f5`,
problem `#ffe3e3`. ≤ 10 nodes per diagram, ≤ 6 in one row (wrap longer
chains with `rankdir=TB` or two ranks): diagrams sit one per row and must
stay readable at 100 % zoom, so labels ≥ 11 pt in the final page. Good picks: pipeline/architecture,
before → after, roadmap, build flow.

## Overview page

Every run also writes `docs/reports/index.html` from the same template: banner
(project, date), roadmap diagram, one row per milestone (status, one line,
link). Milestones without a report have no link.

## Check before you hand over

Search the written files (grep tool) for `<script|<link|@import|src="https?:`:
there must be no match. After `inline_dot.py`, `<!-- dot:` must not match either.

- Each number appears in the facts file.
- Opens offline; narrow window stacks to one column (template does this).
