#!/usr/bin/env python3
"""Checks that skill descriptions make a model pick the right skill.

Each case is a realistic user request and the skills that should be loaded
for it ("-" = none of the skills under test). The model sees the same skill
list OpenCode shows (from the running service) and names the skills it
would load. Skills under test = every id named in the cases file.

  test/skill-triggers.py [--cases FILE] [--override FILE] [--reps N] [--dir DIR]

--cases     TSV: expected<TAB>request (default ~/wiki/ai-workflow/skill-triggers.tsv)
--override  candidate descriptions to try before editing: lines "id<TAB>description"
--dir       project directory whose skills are listed (default ~/dotfiles)

Env: AI_COUNT_URL, AI_COUNT_KEY_CMD, AI_COUNT_MODEL as in test/ai-inventory.sh.
"""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HOME = Path.home()
CFG = HOME / ".config" / "opencode"


def api(path):
    r = subprocess.run(
        ["opencode", "api", "get", path],
        check=False,
        capture_output=True,
        text=True,
        timeout=60,
    )
    if r.returncode != 0:
        sys.exit("FAIL: opencode api: " + r.stderr.strip()[:200])
    j = json.loads(r.stdout)
    return j["data"] if isinstance(j, dict) and "data" in j else j


def hidden(path):
    if not path or not os.path.isfile(path):
        return False
    fm = re.match(
        r"---\n(.*?)\n---", Path(path).read_text(errors="replace"), re.DOTALL
    )
    return bool(
        fm
        and re.search(
            r"^\s*(opencode/autoinvoke:\s*false|disable-model-invocation:\s*true)\s*$",
            fm.group(1),
            re.MULTILINE,
        )
    )


def gateway():
    url = os.environ.get("AI_COUNT_URL")
    if not url:
        m = re.search(
            r'const baseURL = "([^"]+)"',
            (CFG / "plugins" / "llmi" / "index.ts").read_text(),
        )
        url = m.group(1) if m else ""
    if not url.lower().startswith("https://"):
        sys.exit("FAIL: no https gateway URL")
    cmd = (
        os.environ.get("AI_COUNT_KEY_CMD")
        or "gopass show -o work-unattended/llmi-api-token"
    )
    key = subprocess.run(
        cmd,
        check=False,
        shell=True,
        capture_output=True,
        text=True,
        timeout=10,
    ).stdout.strip()
    if not key:
        sys.exit("FAIL: no gateway key")
    return url.rstrip("/") + "/v1/messages", key


def ask(url, key, model, system, request):
    body = {
        "model": model,
        "max_tokens": 1024,
        "system": [
            {
                "type": "text",
                "text": system,
                "cache_control": {"type": "ephemeral"},
            }
        ],
        "messages": [{"role": "user", "content": request}],
    }
    fd, path = tempfile.mkstemp()
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(body, f)
        headers = (
            f"Authorization: Bearer {key}\nx-api-key: {key}\n"
            "anthropic-version: 2023-06-01\ncontent-type: application/json\n"
        )
        r = subprocess.run(
            [
                "curl",
                "--disable",
                "-sS",
                "--proto",
                "=https",
                "--max-time",
                "60",
                "-X",
                "POST",
                url,
                "-H",
                "@-",
                "--data-binary",
                "@" + path,
            ],
            input=headers,
            check=False,
            capture_output=True,
            text=True,
            timeout=70,
        )
        j = json.loads(r.stdout)
        text = "".join(c.get("text", "") for c in j.get("content", []))
        return (
            text
            if text.strip()
            else "ERROR "
            + json.dumps(
                {k: j.get(k) for k in ("stop_reason", "content", "usage")}
            )[:300]
        )
    except (OSError, ValueError, subprocess.SubprocessError) as e:
        return "ERROR " + str(e)[:80]
    finally:
        os.unlink(path)


def main():
    p = argparse.ArgumentParser()
    p.add_argument(
        "--cases",
        default=str(HOME / "wiki" / "ai-workflow" / "skill-triggers.tsv"),
    )
    p.add_argument("--override")
    p.add_argument("--reps", type=int, default=2)
    p.add_argument("--dir", default=str(HOME / "dotfiles"))
    a = p.parse_args()

    cases = []
    for line in Path(a.cases).read_text().splitlines():
        if line.strip() and not line.startswith("#"):
            exp, req = line.split("\t", 1)
            cases.append(
                ({x for x in exp.split(",") if x and x != "-"}, req.strip())
            )
    under_test = set().union(*(c[0] for c in cases))

    over = {}
    if a.override:
        for line in Path(a.override).read_text().splitlines():
            if "\t" in line and not line.startswith("#"):
                k, v = line.split("\t", 1)
                over[k.strip()] = v.strip()

    skills = [
        s
        for s in api("/api/skill?location[directory]=" + a.dir)
        if not hidden(s.get("path"))
    ]
    ids = {s["id"] for s in skills}
    missing = under_test - ids
    if missing:
        sys.exit("FAIL: not installed: " + ", ".join(sorted(missing)))
    listing = "\n".join(
        f"  <skill>\n    <id>{s['id']}</id>\n    <description>{over.get(s['id'], s.get('description', ''))}</description>\n  </skill>"
        for s in skills
    )
    system = (
        "You are a coding agent. Skills provide specialized instructions and workflows for "
        "specific tasks. Load a skill with the skill tool when the task matches its description.\n"
        f"<available_skills>\n{listing}\n</available_skills>\n\n"
        "For the user's message, reply with only the ids of the skills you would load before "
        "acting, comma-separated, or 'none'. Do not act on the request."
    )

    url, key = gateway()
    model = os.environ.get("AI_COUNT_MODEL") or "claude-opus-5-5"
    jobs = [(i, r) for i in range(len(cases)) for r in range(a.reps)]

    def ask_retry(j):
        for _ in range(3):
            ans = ask(url, key, model, system, cases[j[0]][1])
            if not ans.startswith("ERROR"):
                return ans
        return ans

    with ThreadPoolExecutor(4) as ex:
        answers = list(ex.map(ask_retry, jobs))
    errors = [x for x in answers if x.startswith("ERROR")]
    if errors:
        print(
            f"WARN: {len(errors)} calls failed, e.g. {errors[0][:100]}",
            file=sys.stderr,
        )

    fails = 0
    per = {}
    for (i, _), ans in zip(jobs, answers):
        per.setdefault(i, []).append(ans)
    for i, (exp, req) in enumerate(cases):
        ok_n = 0
        got_all = []
        for ans in per[i]:
            if ans.startswith("ERROR"):
                got_all.append("ERR")
                continue
            got = {
                x
                for x in re.findall(r"[a-z0-9][a-z0-9-]+", ans.lower())
                if x in ids
            }
            own = got & under_test
            ok = bool(own & exp) and not (own - exp) if exp else not own
            ok_n += ok
            got_all.append(",".join(sorted(own)) or "none")
        n = len(per[i]) - got_all.count("ERR")
        mark = (
            "ERR "
            if not n
            else "ok  "
            if ok_n == n
            else ("FLAK" if ok_n else "MISS")
        )
        fails += ok_n != n or not n
        print(
            f"{mark} want {','.join(sorted(exp)) or '-':28} got {' | '.join(got_all):40} {req[:60]}"
        )
    print(
        f"\n{len(cases) - fails}/{len(cases)} cases stable ({a.reps} reps, {model})"
    )
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
