"""Build docs/agent-workflow.pdf: how the OpenCode primaries and subagents work together.

Run from the repo root: python3 docs/src/agent-workflow.py
Needs reportlab, svglib and graphviz (`dot`).
"""

import subprocess
import tempfile
from pathlib import Path

from reportlab.lib.colors import HexColor, white
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas as rl_canvas
from reportlab.platypus import (
    BaseDocTemplate,
    Flowable,
    Frame,
    KeepTogether,
    PageBreak,
    PageTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
)
from svglib.svglib import svg2rlg

OUT = Path(__file__).resolve().parents[1] / "agent-workflow.pdf"
TITLE = "Agent workflow: plan, build, coder"
UPDATED = "2026-11-19"

PAGE_W, PAGE_H = A4
MARGIN = 18 * mm
AVAIL_W = PAGE_W - 2 * MARGIN

NAVY = HexColor("#1f3a5f")
INK = HexColor("#1d1d1f")
MUTED = HexColor("#5f6b7a")
RULE = HexColor("#d5dbe3")
TINT = HexColor("#f3f6fa")
OPUS = HexColor("#6a4c93")
SONNET = HexColor("#2e7d32")
SOL = HexColor("#c2571a")
FLASH = HexColor("#546e7a")

FONT_DIR = Path("/usr/share/fonts/truetype/dejavu")
pdfmetrics.registerFont(TTFont("Sans", FONT_DIR / "DejaVuSans.ttf"))
pdfmetrics.registerFont(TTFont("Sans-Bold", FONT_DIR / "DejaVuSans-Bold.ttf"))
pdfmetrics.registerFont(TTFont("Mono", FONT_DIR / "DejaVuSansMono.ttf"))
pdfmetrics.registerFontFamily("Sans", normal="Sans", bold="Sans-Bold")

S_BODY = ParagraphStyle(
    "body", fontName="Sans", fontSize=8.6, leading=12.2, textColor=INK
)
S_LEAD = ParagraphStyle(
    "lead", parent=S_BODY, fontSize=9.2, leading=13, textColor=MUTED
)
S_H1 = ParagraphStyle(
    "h1",
    fontName="Sans-Bold",
    fontSize=15,
    leading=19,
    textColor=NAVY,
    spaceBefore=4,
    spaceAfter=3,
)
S_H2 = ParagraphStyle(
    "h2",
    fontName="Sans-Bold",
    fontSize=10.5,
    leading=14,
    textColor=NAVY,
    spaceBefore=8,
    spaceAfter=3,
)
S_CELL = ParagraphStyle(
    "cell", fontName="Sans", fontSize=7.6, leading=10, textColor=INK
)
S_HEAD = ParagraphStyle(
    "head", parent=S_CELL, fontName="Sans-Bold", fontSize=7, textColor=MUTED
)
S_NOTE = ParagraphStyle(
    "note", parent=S_BODY, fontSize=7.6, leading=10.4, textColor=MUTED
)
S_CODE = ParagraphStyle(
    "code",
    fontName="Mono",
    fontSize=7.6,
    leading=10.6,
    textColor=INK,
    backColor=TINT,
    borderPadding=(5, 6, 5, 6),
    spaceBefore=4,
    spaceAfter=6,
)
S_BAND_T = ParagraphStyle(
    "bandt", fontName="Sans-Bold", fontSize=20, leading=24, textColor=white
)
S_BAND = ParagraphStyle(
    "band", fontName="Sans", fontSize=8.4, leading=11.5, textColor=white
)

SECTIONS = [
    ("overview", "Overview"),
    ("choose", "Which primary when"),
    ("greenfield", "Greenfield walkthrough"),
    ("execute", "Two ways to execute a plan"),
    ("subagents", "Subagents"),
    ("models", "Models and cost"),
    ("guardrails", "Guardrails"),
    ("reference", "Quick reference"),
]


class Anchor(Flowable):
    """Zero-size destination for the index links and the PDF outline."""

    def __init__(self, key, title):
        super().__init__()
        self.key, self.title = key, title
        self.width = self.height = 0

    def wrap(self, *_):
        return 0, 0

    def draw(self):
        self.canv.bookmarkPage(self.key)
        self.canv.addOutlineEntry(self.title, self.key, 0, 0)


class NumberedCanvas(rl_canvas.Canvas):
    """Footer with 'page n / N', drawn after the page count is known."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._pages = []

    def showPage(self):
        self._pages.append(dict(self.__dict__))
        self._startPage()

    def save(self):
        total = len(self._pages)
        for state in self._pages:
            self.__dict__.update(state)
            self.setStrokeColor(RULE)
            self.line(MARGIN, 12 * mm, PAGE_W - MARGIN, 12 * mm)
            self.setFont("Sans", 7)
            self.setFillColor(MUTED)
            self.drawString(MARGIN, 8.5 * mm, f"{TITLE} (updated {UPDATED})")
            self.drawRightString(
                PAGE_W - MARGIN, 8.5 * mm, f"page {self._pageNumber} / {total}"
            )
            super().showPage()
        super().save()


def p(text, style=S_BODY):
    return Paragraph(text, style)


def code(text):
    text = (
        text.strip()
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
    )
    return Paragraph(
        text.replace("\n", "<br/>").replace("  ", "&nbsp;&nbsp;"), S_CODE
    )


def h1(n, key):
    title = dict(SECTIONS)[key]
    return [p(f"{n} {title}", S_H1), Anchor(key, f"{n} {title}")]


def table(rows, widths, header=True):
    scale = AVAIL_W / sum(widths)
    data = [
        [c if isinstance(c, Flowable) else p(c, S_CELL) for c in r]
        for r in rows
    ]
    if header:
        data[0] = [p(str(c).upper(), S_HEAD) for c in rows[0]]
    t = Table(
        data,
        colWidths=[w * scale for w in widths],
        repeatRows=1 if header else 0,
    )
    style = [
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LINEBELOW", (0, 0), (-1, -1), 0.4, RULE),
        ("TOPPADDING", (0, 0), (-1, -1), 3),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
        ("LEFTPADDING", (0, 0), (-1, -1), 4),
        ("RIGHTPADDING", (0, 0), (-1, -1), 4),
    ]
    if header:
        style.append(("LINEBELOW", (0, 0), (-1, 0), 0.8, NAVY))
    t.setStyle(TableStyle(style))
    return KeepTogether(t) if len(rows) < 12 else t


def chip(text, color):
    return f'<font color="{color.hexval().replace("0x", "#")}"><b>{text}</b></font>'


def diagram(dot_src, width_frac=1.0):
    with tempfile.TemporaryDirectory() as tmp:
        dot_file, svg_file = Path(tmp) / "d.dot", Path(tmp) / "d.svg"
        dot_file.write_text(dot_src)
        subprocess.run(
            ["dot", "-Tsvg", str(dot_file), "-o", str(svg_file)], check=True
        )
        drawing = svg2rlg(str(svg_file))
    scale = min(AVAIL_W * width_frac / drawing.width, 1.0)
    drawing.width, drawing.height = (
        drawing.width * scale,
        drawing.height * scale,
    )
    drawing.scale(scale, scale)
    drawing.hAlign = "CENTER"
    return drawing


GV_HEAD = """
  graph [fontname="Helvetica", fontsize=9, nodesep=0.25, ranksep=0.35, splines=true, pad=0.05];
  node  [fontname="Helvetica", fontsize=9, shape=box, style="rounded,filled", fillcolor="#ffffff",
         color="#9aa7b5", penwidth=0.8, margin="0.12,0.05"];
  edge  [fontname="Helvetica", fontsize=8, color="#7b8794", arrowsize=0.6, fontcolor="#5f6b7a"];
"""

D_OVERVIEW = (
    "digraph G { rankdir=TB; compound=true; newrank=true;"
    + GV_HEAD
    + """
  subgraph cluster_p { label="Primary agents: you talk to one, switch with Tab"; fontcolor="#1f3a5f";
    style="rounded"; color="#1f3a5f"; margin=10;
    plan  [label=<<b>plan</b><br/><font point-size="8">Opus 5.5<br/>think, no repo edits</font>>,
           color="#6a4c93", penwidth=1.4];
    build [label=<<b>build</b><br/><font point-size="8">Opus 5.5<br/>design, specs, plans</font>>,
           color="#6a4c93", penwidth=1.4];
    coder [label=<<b>coder</b><br/><font point-size="8">Sonnet 5.5<br/>implement plans</font>>,
           color="#2e7d32", penwidth=1.4];
    plan -> build [label=" decided "]; build -> coder [label=" plan file "];
    { rank=same; plan; build; coder; }
  }
  subgraph cluster_son { label="Sonnet 5.5: authors, research"; fontcolor="#2e7d32"; color="#2e7d32"; style=rounded;
    general; investigator; }
  subgraph cluster_sol { label="GPT-6.1 Sol: review"; fontcolor="#c2571a"; color="#c2571a"; style=rounded;
    "cpp-reviewer"; }
  subgraph cluster_ses { label="session model"; fontcolor="#6a4c93"; color="#6a4c93"; style=rounded;
    "release-mapper"; }
  subgraph cluster_fl { label="DeepSeek V4.1 Flash: mechanical"; fontcolor="#546e7a"; color="#546e7a"; style=rounded;
    "build-runner"; scribe; explore; jira; confluence; }
  { rank=same; general; investigator; "cpp-reviewer"; "release-mapper"; }
  build -> investigator [ltail=cluster_p, lhead=cluster_son, label=" delegate: fresh context,\\n summary back ", minlen=2];
  build -> "cpp-reviewer" [ltail=cluster_p, lhead=cluster_sol, minlen=2];
  build -> "release-mapper" [ltail=cluster_p, lhead=cluster_ses, minlen=2];
  { rank=same; "build-runner"; scribe; explore; jira; confluence; }
  "release-mapper" -> "build-runner" [style=invis];
  investigator -> scribe [style=invis];
}"""
)

D_CHOOSE = (
    "digraph G { rankdir=TB;"
    + GV_HEAD
    + """
  q1 [shape=diamond, style=filled, fillcolor="#f3f6fa", label="Do you know\\nwhat you want?"];
  q2 [shape=diamond, style=filled, fillcolor="#f3f6fa", label="Is there an\\napproved plan?"];
  q3 [shape=diamond, style=filled, fillcolor="#f3f6fa", label="Small, obvious\\nfix?"];
  plan  [label=<<b>plan</b><br/><font point-size="8">explore, ask, compare options</font>>, color="#6a4c93", penwidth=1.4];
  build [label=<<b>build</b><br/><font point-size="8">brainstorm, spec, plan</font>>, color="#6a4c93", penwidth=1.4];
  coder [label=<<b>coder</b><br/><font point-size="8">execute the plan, new session</font>>, color="#2e7d32", penwidth=1.4];
  fix   [label=<<b>build</b><br/><font point-size="8">just do it</font>>, color="#6a4c93", penwidth=1.4];
  q1 -> plan [label=" no"]; q1 -> q3 [label=" yes"];
  q3 -> fix [label=" yes"]; q3 -> q2 [label=" no"];
  q2 -> coder [label=" yes"]; q2 -> build [label=" no"];
  plan -> build [style=dashed, label=" decided"];
  build -> coder [style=dashed, label=" approved"];
  { rank=same; plan; q3; } { rank=same; fix; q2; } { rank=same; build; coder; }
}"""
)

D_GREENFIELD = (
    "digraph G { rankdir=TB; nodesep=0.35; ranksep=0.45;"
    + GV_HEAD
    + """
  s0 [label=<<b>0 Setup</b><br/><font point-size="8">you: repo, worktree</font>>];
  s1 [label=<<b>1 Explore</b><br/><font point-size="8">plan (Opus)</font>>, color="#6a4c93", penwidth=1.4];
  s2 [label=<<b>2 Spec + plan</b><br/><font point-size="8">build (Opus)</font>>, color="#6a4c93", penwidth=1.4];
  f  [shape=note, fillcolor="#f3f6fa", label=<<font point-size="8">specs/...-design.md<br/>plans/....md<br/>committed</font>>];
  s3 [label=<<b>3 Implement</b><br/><font point-size="8">coder (Sonnet), new session</font>>, color="#2e7d32", penwidth=1.4];
  s4 [label=<<b>4 Review</b><br/><font point-size="8">cpp-reviewer (Sol)</font>>, color="#c2571a", penwidth=1.4];
  s5 [label=<<b>5 Finish</b><br/><font point-size="8">build-runner, scribe (Flash)</font>>, color="#546e7a", penwidth=1.4];
  s6 [label=<<b>6 Afterwards</b><br/><font point-size="8">skill? wiki log</font>>];
  { rank=same; s0; s1; s2; f; }
  { rank=same; s6; s5; s4; s3; }
  s0 -> s1 -> s2 -> f;
  f -> s3 [label=" handoff "];
  s6 -> s5 -> s4 -> s3 [dir=back];
  s0 -> s2 [style=dotted, label=" know what you want ", constraint=false];
  s3 -> s2 [style=dashed, label=" plan does not fit ", constraint=false];
}"""
)

D_EXECUTE = (
    "digraph G { rankdir=TB; compound=true; newrank=true; ranksep=0.3;"
    + GV_HEAD
    + """
  subgraph cluster_a { label="A  executing-plans in coder (default)"; color="#2e7d32"; fontcolor="#2e7d32"; style=rounded;
    a1 [label=<<b>coder</b> (Sonnet)<br/><font point-size="8">task 1..N itself, TDD,<br/>ledger file</font>>];
    a2 [label=<<b>cpp-reviewer</b> (Sol)<br/><font point-size="8">one review at the end</font>>];
    a1 -> a2; { rank=same; a1; a2; }
  }
  subgraph cluster_b { label="B  subagent-driven from build (big or risky plans)"; color="#6a4c93"; fontcolor="#6a4c93"; style=rounded;
    b0 [label=<<b>build</b> (Opus)<br/><font point-size="8">coordinates</font>>];
    b1 [label=<<b>general</b> (Sonnet)<br/><font point-size="8">fresh implementer<br/>per task</font>>];
    b2 [label=<<b>reviewer</b><br/><font point-size="8">per task</font>>];
    b3 [label=<<b>final review</b><br/><font point-size="8">whole branch</font>>];
    b0 -> b1; b1 -> b2; b2 -> b0 [constraint=false]; b0 -> b3; { rank=same; b1; b2; b3; }
  }
  a1 -> b0 [style=invis];
}"""
)

D_GUARD = (
    "digraph G { rankdir=TB; ranksep=0.3;"
    + GV_HEAD
    + """
  need [label=<<font point-size="8">New skill or<br/>subagent wanted</font>>, style="rounded,filled", fillcolor="#f3f6fa"];
  ext  [shape=diamond, style=filled, fillcolor="#f3f6fa", label="Extend an\\nexisting one?"];
  test [shape=diamond, style=filled, fillcolor="#f3f6fa", label="Passes one\\nof 3 tests?"];
  edit [label="extend it"];
  skill [label="skill (or nothing)"];
  agent [label="subagent"];
  row  [label=<<b>inventory row</b><br/><font point-size="8">why, added, reviewed</font>>];
  chk  [label=<<b>test/ai-inventory.sh</b><br/><font point-size="8">unlisted, stale, over limit = FAIL</font>>, color="#c2571a", penwidth=1.2];
  need -> ext; ext -> edit [label=" yes"]; ext -> test [label=" no"];
  test -> agent [label=" yes"]; test -> skill [label=" no"];
  agent -> row; skill -> row; edit -> row [style=dotted]; row -> chk;
  { rank=same; edit; test; } { rank=same; agent; skill; } { rank=same; row; chk; }
}"""
)


def band():
    links = "&nbsp;&nbsp;&nbsp; ".join(
        f'<a href="#{k}" color="white">{i}&nbsp;{t.replace(" ", "&nbsp;")}</a>'
        for i, (k, t) in enumerate(SECTIONS, 1)
    )
    cell = [
        p(TITLE, S_BAND_T),
        Spacer(1, 3),
        p(
            "How the OpenCode primary agents and subagents in these dotfiles work together, "
            "which model runs where and why, and the steps from an idea to a merged change.",
            S_BAND,
        ),
        Spacer(1, 5),
        p(links, S_BAND),
    ]
    t = Table([[cell]], colWidths=[AVAIL_W])
    t.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), NAVY),
                ("LEFTPADDING", (0, 0), (-1, -1), 10),
                ("RIGHTPADDING", (0, 0), (-1, -1), 10),
                ("TOPPADDING", (0, 0), (-1, -1), 9),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 9),
            ]
        )
    )
    return t


def story():
    s = [band(), Spacer(1, 8)]

    # 1 Overview
    s += h1(1, "overview")
    s.append(
        p(
            "You always talk to one <b>primary</b> agent and switch between them with Tab. A primary "
            "hands self-contained jobs to <b>subagents</b>: each starts with an empty context, has its own "
            "permissions and model, and returns only a summary. The rule of thumb: think with the strongest "
            "model, implement with a cheaper one, review with a different model family.",
            S_LEAD,
        )
    )
    s.append(Spacer(1, 4))
    s.append(diagram(D_OVERVIEW))
    s.append(Spacer(1, 4))
    s.append(
        table(
            [
                ["Primary", "Model", "Can edit the repo", "Use it for"],
                [
                    chip("plan", OPUS),
                    "session (Opus 5.5)",
                    "No (only notes in ~/.opencode/plan)",
                    "Exploring, questions, weighing options",
                ],
                [
                    chip("build", OPUS),
                    "session (Opus 5.5)",
                    "Yes",
                    "Brainstorming, specs, plans, small direct fixes",
                ],
                [
                    chip("coder", SONNET),
                    "Sonnet 5.5",
                    "Yes",
                    "Carrying out an approved plan",
                ],
            ],
            [1.1, 1.6, 2.2, 3.2],
        )
    )
    s.append(
        p(
            "plan blocks the edit tool, not the shell: a command that writes files still runs unless the "
            "safety plugin stops it. Treat it as no-accidental-edits, not as a sandbox.",
            S_NOTE,
        )
    )

    # 2 Which primary when
    s.append(PageBreak())
    s += h1(2, "choose")
    s.append(
        p(
            "Pick by where the work is, not by habit. When in doubt, start in plan: switching up costs nothing.",
            S_LEAD,
        )
    )
    s.append(Spacer(1, 4))
    s.append(diagram(D_CHOOSE, 0.78))
    s.append(
        table(
            [
                ["Situation", "Agent", "Why"],
                [
                    "How does this work? Why does it fail?",
                    chip("plan", OPUS),
                    "Investigate with no risk of edits; can send investigator.",
                ],
                [
                    "Unsure what to build, comparing options",
                    chip("plan", OPUS),
                    "Talk it through before anything is written.",
                ],
                [
                    "Decided: write the spec and plan",
                    chip("build", OPUS),
                    "plan cannot save files in the repo; build can.",
                ],
                [
                    "Approved plan file exists",
                    chip("coder", SONNET),
                    "Half the price of Opus; the plan carries the design.",
                ],
                [
                    "coder stopped: plan does not fit the code",
                    chip("build", OPUS),
                    "A design decision; update the plan, then resume coder.",
                ],
                [
                    "One-line fix, typo, config tweak",
                    chip("build", OPUS),
                    "Planning would cost more than the fix.",
                ],
            ],
            [3.2, 0.9, 3.9],
        )
    )

    # 3 Greenfield
    s.append(PageBreak())
    s += h1(3, "greenfield")
    s.append(
        p(
            "Example: a new command-line tool that reads recording files and prints per-frame statistics. "
            "Steps 1 to 2 use Opus where judgement matters; the long middle runs on Sonnet; review on Sol; "
            "logs and text on Flash.",
            S_LEAD,
        )
    )
    s.append(Spacer(1, 4))
    s.append(diagram(D_GREENFIELD))
    s.append(Spacer(1, 4))
    steps = [
        ["Step", "Agent", "What you say", "What happens", "Output"],
        [
            "0 Setup",
            "you",
            "-",
            "Create the repo or a worktree; start OpenCode there. Run /init once code exists.",
            "Repo, later AGENTS.md",
        ],
        [
            "1 Explore",
            chip("plan", OPUS),
            "I need a tool that reads recordings and prints frame stats. What exists already, which language?",
            "Reads code, may send investigator to sibling repos or docs, talks it through. Skip if you already know.",
            "A decision, no files",
        ],
        [
            "2 Spec + plan",
            chip("build", OPUS),
            "Let's build it.",
            "brainstorming: questions, 2-3 approaches, you pick; spec written and checked by a reviewer; you approve; writing-plans writes tasks, tests, file names.",
            "Spec and plan files in git",
        ],
        [
            "3 Implement",
            chip("coder", SONNET),
            "Execute docs/superpowers/plans/....md with executing-plans.",
            "In a new session. Task by task: failing test, code, passing test, commit; a ledger file survives compaction. Long builds go to build-runner.",
            "Commits, one per task",
        ],
        [
            "4 Review",
            chip("cpp-reviewer", SOL),
            "Review the branch against main.",
            "Fresh context, different model family; findings by severity with file:line. Fixes go back to coder.",
            "Findings, fix commits",
        ],
        [
            "5 Finish",
            chip("build-runner", FLASH) + ", " + chip("scribe", FLASH),
            "Run the full build and tests. Draft the PR text.",
            "Verdict and first errors only; message in the repo's style. finishing-a-development-branch asks: merge, PR or keep.",
            "Merge or PR",
        ],
        [
            "6 Afterwards",
            "any",
            "-",
            "If facts were explained twice, the agent suggests a skill; new items get an inventory row. Decisions go to the wiki log.",
            "Skill, wiki entry",
        ],
    ]
    s.append(table(steps, [1.0, 1.35, 1.9, 3.2, 1.25]))
    s.append(Spacer(1, 4))
    s.append(
        p(
            "<b>Sessions:</b> steps 1 and 2 share one session: press Tab from plan to build and the "
            "exploration stays in context for brainstorming, on the same model. Step 3 starts a <b>new</b> "
            "session: Tab would keep the whole Opus conversation, and Sonnet would re-read it on every turn "
            "for nothing, because the plan file is the handoff. Steps 4 and 5 run inside the coder session. "
            "Exception: after a long, noisy exploration, start step 2 fresh in build and paste a short summary.",
            S_NOTE,
        )
    )

    # 4 Execute
    s.append(PageBreak())
    s += h1(4, "execute")
    s.append(
        p(
            "At the end of step 2, writing-plans asks how to run the plan. Both use TDD and end with one whole-branch review.",
            S_LEAD,
        )
    )
    s.append(Spacer(1, 4))
    s.append(diagram(D_EXECUTE))
    s.append(Spacer(1, 4))
    s.append(
        table(
            [
                [
                    "",
                    "A  executing-plans in coder",
                    "B  subagent-driven from build",
                ],
                [
                    "Who implements",
                    "coder (Sonnet), in one session",
                    "A fresh general (Sonnet) per task",
                ],
                [
                    "Who coordinates",
                    "coder itself, with a ledger file",
                    "build (Opus)",
                ],
                [
                    "Reviews",
                    "One whole-branch review at the end",
                    "A reviewer per task, plus a final one",
                ],
                ["Cost", "Lowest", "Higher: Opus coordinates, more reviews"],
                [
                    "Pick it for",
                    "Most plans",
                    "Large, risky or long plans whose later tasks would run on a compacted context",
                ],
            ],
            [1.4, 3.0, 3.6],
        )
    )

    # 5 Subagents
    s += h1(5, "subagents")
    s.append(
        p(
            "A subagent must pass at least one test: <b>noisy output</b> (only a summary matters), <b>strict "
            "limits</b> (read-only or narrowed shell) or <b>cheaper model</b>. Otherwise it should be a skill. "
            "The main agent calls them when their description fits; you can also ask by name.",
            S_LEAD,
        )
    )
    s.append(
        table(
            [
                ["Subagent", "Model", "Tests", "Does", "Typical call"],
                [
                    "investigator",
                    "Sonnet 5.5",
                    "limits",
                    "Read-only research: code across repos, vendor and library docs",
                    "How does X reach Y? What do the docs say about Z?",
                ],
                [
                    "cpp-reviewer",
                    "GPT-6.1 Sol",
                    "limits",
                    "Read-only C++ review by severity, file:line",
                    "Review this branch against main",
                ],
                [
                    "release-mapper",
                    "session",
                    "limits, noise",
                    "Upstream changelog or SDK diff to a change table, no shims",
                    "Map SDK 0.3 to 0.4 onto our code",
                ],
                [
                    "build-runner",
                    "Flash",
                    "noise, cheap",
                    "Runs build/test/deploy, returns verdict and first errors",
                    "Run the unit tests",
                ],
                [
                    "scribe",
                    "Flash",
                    "cheap, limits",
                    "Commit and PR text in the repo's style; commits only when asked",
                    "Draft the commit message",
                ],
                [
                    "jira, confluence",
                    "Flash",
                    "cheap, limits",
                    "One Atlassian tool set each; changes only when spelled out",
                    "Summarise ABC-123",
                ],
                [
                    "general (built-in)",
                    "Sonnet 5.5",
                    "-",
                    "Multi-step work; superpowers implementers",
                    "(used by skills)",
                ],
                [
                    "explore (built-in)",
                    "Flash",
                    "cheap",
                    "Fast read-only search",
                    "(used by skills)",
                ],
            ],
            [1.35, 1.0, 0.95, 2.9, 2.2],
        )
    )

    # 6 Models
    s.append(PageBreak())
    s += h1(6, "models")
    s.append(
        p(
            "<b>Authors on Claude, reviewers on GPT.</b> A reviewer from the same family tends to share the "
            "author's blind spots. Both Sonnet and Sol cost the same, so the split is free.",
            S_LEAD,
        )
    )
    s.append(
        table(
            [
                [
                    "Tier",
                    "Model",
                    "Price in/out per M tokens",
                    "Agents",
                    "Set in",
                ],
                [
                    chip("Think", OPUS),
                    "Claude Opus 5.5",
                    "$4 / $20",
                    "build, plan (session model)",
                    "your session's model choice",
                ],
                [
                    chip("Author", SONNET),
                    "Claude Sonnet 5.5",
                    "$2 / $10",
                    "coder, general, investigator",
                    "agent file; agents.general in both configs",
                ],
                [
                    chip("Review", SOL),
                    "GPT-6.1 Sol",
                    "$2 / $10",
                    "cpp-reviewer",
                    "agent file",
                ],
                [
                    chip("Mechanical", FLASH),
                    "DeepSeek V4.1 Flash",
                    "$0.15 / $0.60",
                    "build-runner, scribe, jira, confluence, explore, compaction",
                    "agent file; agents.* in both configs",
                ],
                [
                    "Inherit",
                    "session model",
                    "-",
                    "release-mapper",
                    "no model field",
                ],
            ],
            [1.0, 1.4, 1.5, 2.6, 2.3],
        )
    )
    s.append(
        p(
            "Prices: Copilot and OpenCode Go price lists, checked 2026-11-19. Built-in agents (general, explore, "
            "compaction) are changed under agents.&lt;id&gt; in opencode.json; an agents/&lt;id&gt;.md file would "
            "replace their built-in prompt. Never put model IDs in files committed to team repos.",
            S_NOTE,
        )
    )
    s.append(p("Signs a tier is wrong", S_H2))
    s.append(
        table(
            [
                ["Symptom", "Change"],
                [
                    "coder often stops on ambiguous steps",
                    "Make plans more detailed in build; or run that plan in build",
                ],
                [
                    "Review finds many issues coder should have caught",
                    "More tests in the plan; consider option B for that plan",
                ],
                [
                    "Flash summaries are wrong or miss errors",
                    "Move that agent to Sonnet; record why in the wiki",
                ],
                [
                    "Bills dominated by Opus",
                    "Start new coder sessions earlier; keep plan/build sessions short",
                ],
            ],
            [3.6, 4.4],
        )
    )

    # 7 Guardrails
    s.append(PageBreak())
    s += h1(7, "guardrails")
    s.append(Spacer(1, 2))
    s.append(diagram(D_GUARD, 0.62))
    s.append(Spacer(1, 4))
    s.append(
        table(
            [
                ["Guard", "Where", "What it does"],
                [
                    "Global rules",
                    ".config/opencode/AGENTS.md",
                    "Extend before adding; the three tests; one-line suggestions for new or unused skills and agents",
                ],
                [
                    "Personal rules",
                    "instructions.md in your private wiki",
                    "Loaded when present: e.g. a reply-name prefix that shows when standing rules are being ignored",
                ],
                [
                    "Inventory",
                    "inventory.md in your private wiki",
                    "Every agent, skill and plugin with why, added, reviewed; limits (agents < 20, skills < 50)",
                ],
                [
                    "Inventory check",
                    "test/ai-inventory.sh",
                    "Fails on unlisted items, stale rows or a limit reached; warns and passes without a wiki",
                ],
                [
                    "Agent check",
                    "test/opencode-agents.sh",
                    "Models, modes and permission rules of every agent",
                ],
                [
                    "Safety net",
                    "cc-safety-net plugin",
                    "Blocks destructive shell commands before they run",
                ],
            ],
            [1.4, 2.4, 4.2],
        )
    )

    # 8 Reference
    s.append(PageBreak())
    s += h1(8, "reference")
    s.append(p("Prompts that start each step", S_H2))
    s.append(
        code(
            """
[plan]   How does <component> work? / What are my options for <problem>?
[build]  Let's build <thing>.                 -> brainstorming, spec, writing-plans
[build]  Plan approved, I'll execute in coder.
[coder]  Execute docs/superpowers/plans/<file>.md with executing-plans.
[any]    Review the branch against main with cpp-reviewer.
[any]    Run the full build and tests with build-runner.
[any]    Draft the commit message with scribe.
"""
        )
    )
    s.append(p("Keys and commands", S_H2))
    s.append(
        table(
            [
                ["Action", "How"],
                ["Switch primary", "Tab (cycles through the primary agents)"],
                [
                    "New session for coder",
                    "New session in the TUI, then Tab to coder",
                ],
                ["Check agents", "test/opencode-agents.sh"],
                ["Check inventory", "test/ai-inventory.sh"],
                [
                    "Get the private wiki",
                    "./install --wiki &lt;git-url&gt; (to ~/wiki/ai-workflow or AI_WIKI_DIR)",
                ],
                [
                    "Reload agents after adding a file",
                    "opencode api post /api/location/reload",
                ],
            ],
            [2.6, 5.4],
        )
    )
    s.append(p("Files", S_H2))
    s.append(
        table(
            [
                ["Path", "Holds"],
                [
                    ".config/opencode/agents/*.md",
                    "Custom agents: coder and the subagents (model, permissions, prompt)",
                ],
                [
                    ".config/opencode/opencode.json, opencode_work.json",
                    "Built-in agent models, plugins, instructions entry",
                ],
                [
                    ".config/opencode/AGENTS.md",
                    "Global rules for every session",
                ],
                [
                    "&lt;repo&gt;/.agents/skills/&lt;name&gt;/SKILL.md",
                    "Project know-how shared with the team (OpenCode, Copilot, Codex)",
                ],
                [
                    "&lt;repo&gt;/docs/superpowers/{specs,plans}/",
                    "Specs and plans: the handoff between build and coder",
                ],
                ["docs/src/agent-workflow.py", "Generator of this PDF"],
            ],
            [3.4, 4.6],
        )
    )
    return s


def main():
    doc = BaseDocTemplate(
        str(OUT),
        pagesize=A4,
        leftMargin=MARGIN,
        rightMargin=MARGIN,
        topMargin=MARGIN,
        bottomMargin=16 * mm,
        title=TITLE,
        subject="OpenCode primaries, subagents, models and the plan-to-merge steps",
        author="dotfiles",
    )
    frame = Frame(
        MARGIN, 16 * mm, AVAIL_W, PAGE_H - MARGIN - 16 * mm, id="body"
    )
    doc.addPageTemplates([PageTemplate(id="page", frames=[frame])])
    doc.build(story(), canvasmaker=NumberedCanvas)
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
