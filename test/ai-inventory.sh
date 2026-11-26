#!/usr/bin/env bash
# Checks the installed OpenCode agents and skills against the inventory in
# the private notes wiki (see `./install --wiki`; its skills/ folder counts as
# installed): every installed item needs a row, every row an installed item,
# and counts stay under the limits the
# inventory states. Also checks that reviewers run on another model family
# than the authors (opencode.json, agent files), and the starting context
# budget (instructions, skills, agents, session total, taken from the first step of recent sessions; own parts via count_tokens, else chars / 3.2). The plain
# check warns and passes without the wiki; --record needs it.
#
#   test/ai-inventory.sh              check this machine
#   test/ai-inventory.sh --self-test  check the checker against fixtures
#   test/ai-inventory.sh --record     check, then write the context table into
#                                     concepts/starting-context.md (once a day)
#   test/ai-inventory.sh --daily      once a day: --record, save the problems to the
#                                     state file, commit and push the wiki page
#                                     (run by the `opencode` wrapper in .aliases)
#   test/ai-inventory.sh --status     print the problems the last daily run found
#
# Env: AI_STATE_DIR (default ${XDG_STATE_HOME:-~/.local/state}/ai-inventory), AI_WIKI_DIR (default
# ~/wiki/ai-workflow), OPENCODE_CONFIG_DIR_CHECK (default ~/.config/opencode), AI_TODAY (record/daily
# date, default today), AI_INVENTORY_RETRY_DELAY (seconds between service API retries, default 2),
# AI_INVENTORY_PLUGINS (comma list; default: asked from the running OpenCode service).
# Token counting (all optional): AI_COUNT_URL (default: baseURL in <cfg>/plugins/llmi/index.ts; none
# = estimate silently), AI_COUNT_KEY_CMD (default gopass show -o work-unattended/llmi-api-token),
# AI_COUNT_MODEL (default claude-opus-5-5). The URL must be https. AI_COUNT_KEY_CMD must print the key
# (e.g. gopass show -o ..., cat <file>); never put the key itself in it.

set -o nounset

check() {
  local record="${1:-}"
  local wiki="${AI_WIKI_DIR:-${HOME}/wiki/ai-workflow}"
  local cfg="${OPENCODE_CONFIG_DIR_CHECK:-${HOME}/.config/opencode}"
  local plugins="${AI_INVENTORY_PLUGINS-}"

  if [ ! -f "${wiki}/inventory.md" ]; then
    if [ -d "${wiki}" ]; then
      printf "FAIL: %s/inventory.md is missing\n" "${wiki}" >&2
      return 1
    fi
    printf "WARN: no notes wiki at %s; inventory not checked (see ./install --wiki)\n" "${wiki}" >&2
    [ "${record}" = "--record" ] && return 1
    return 0
  fi

  local discover=
  [ -z "${AI_INVENTORY_PLUGINS+set}" ] && discover=1

  INVENTORY="${wiki}/inventory.md" CFG="${cfg}" PLUGINS="${plugins}" DISCOVER="${discover}" RECORD="${record}" WIKI="${wiki}" python3 - <<'EOF'
import hashlib, json, os, re, statistics, subprocess, sys, time
from pathlib import Path


def api(path):
    for _ in range(2):
        try:
            r = subprocess.run(["opencode", "api", "get", path],
                               capture_output=True, text=True, timeout=60)
            if r.returncode == 0:
                j = json.loads(r.stdout)
                return j["data"] if isinstance(j, dict) and "data" in j else j
        except Exception:
            pass
    return None

text = Path(os.environ["INVENTORY"]).read_text()
cfg = Path(os.environ["CFG"])
status = 0

def fail(msg):
    global status
    status = 1
    print(f"FAIL: {msg}", file=sys.stderr)

installed = {
    "Agents": {p.stem for p in (cfg / "agents").glob("*.md")},
    "Skills": {p.name for p in (cfg / "skills").iterdir()
               if p.is_dir() and not p.name.startswith(".")}
              if (cfg / "skills").is_dir() else set(),
    "Plugins": {p for p in os.environ["PLUGINS"].split(",") if p},
}
# Private skills live in the wiki (`skills` path in opencode.json).
wiki_skills = Path(os.environ["WIKI"]) / "skills"
if wiki_skills.is_dir():
    installed["Skills"] |= {p.name for p in wiki_skills.iterdir()
                            if (p / "SKILL.md").is_file()}
# Team skills shared across projects are a clone in ~/.agents/skills.
team_skills = Path(os.environ.get("TEAM_SKILLS", Path.home() / ".agents" / "skills"))
if team_skills.is_dir():
    installed["Skills"] |= {p.name for p in team_skills.iterdir()
                            if (p / "SKILL.md").is_file()}

listed, section = {k: set() for k in installed}, None
for line in text.splitlines():
    if line.startswith("## "):
        section = line[3:].strip()
    elif section in listed and line.startswith("|"):
        # First cell is the id, with or without backticks; skip header and rule.
        first = line.strip().strip("|").split("|")[0].strip().strip("`")
        if first and first != "Id" and not set(first) <= set("-: "):
            listed[section].add(first)

# Plugin skills live under .../node_modules/<package>/skills/<id>/SKILL.md.
# Right after the service starts the first lists can omit them for tens of
# seconds (cold boot, plugin reconciliation still running): ask up to 15 times.
# The daily run is unattended background, so a generous wait is cheap.
# Without an answer the plugins are unknown and only their comparison is skipped.
plugins_known = True
if os.environ.get("DISCOVER"):
    wanted = listed["Plugins"]
    for attempt in range(15):
        data = api("/api/skill?location[directory]=" + os.path.expanduser("~"))
        if not isinstance(data, list):
            plugins_known = False
            break
        installed["Plugins"] = {m.group(1) for s in data if isinstance(s, dict)
                                for m in [re.search(r"/node_modules/((?:@[^/]+/)?[^/]+)/skills/", str(s.get("path", "")))] if m}
        if wanted <= installed["Plugins"]:
            break
        if attempt < 14:
            time.sleep(float(os.environ.get("AI_INVENTORY_RETRY_DELAY", "2")))
    if not plugins_known:
        installed["Plugins"] = set(listed["Plugins"])
        print("WARN: could not list plugins from the OpenCode service; plugin rows not checked", file=sys.stderr)
        print("      (set AI_INVENTORY_PLUGINS to the comma-separated plugin names, e.g. superpowers, to pin them)", file=sys.stderr)

for kind in installed:
    for name in sorted(installed[kind] - listed[kind]):
        fail(f"{kind}: '{name}' is installed but not in the inventory")
    for name in sorted(listed[kind] - installed[kind]):
        fail(f"{kind}: '{name}' is in the inventory but not installed")

m = re.search(r"^Limits:\s*agents\s*<\s*(\d+),\s*skills\s*<\s*(\d+)", text, re.M)
if not m:
    fail("inventory has no 'Limits: agents < N, skills < M' line")
else:
    for kind, limit in (("Agents", int(m.group(1))), ("Skills", int(m.group(2)))):
        n = len(installed[kind])
        if n >= limit:
            fail(f"{kind}: {n} installed, limit is < {limit}; prune or raise the limit on purpose")
        else:
            print(f"ok:   {kind}: {n} installed, limit < {limit}")

# Reviews need another model family than the authors. Model comes from
# agents.<id>.model in opencode.json, else the agent file's `model:`.
AUTHORS, REVIEWERS = ("general", "coder"), ("reviewer", "cpp-reviewer")
FAMILIES = (("claude", r"claude|anthropic"), ("gpt", r"gpt|openai|\bo\d"),
            ("gemini", r"gemini"), ("deepseek", r"deepseek"), ("qwen", r"qwen"),
            ("hunyuan", r"hy4|hunyuan"))
conf = cfg / "opencode.json"
if not conf.is_file():
    print(f"WARN: no {conf}; model families not checked", file=sys.stderr)
else:
    try:
        data = json.loads(conf.read_text())
    except ValueError as e:
        data = None
        fail(f"{conf} is not plain JSON ({e}); model families not checked")
    if data is not None:
        pinned = data.get("agents") or data.get("agent") or {}
        def model_of(agent):
            m = (pinned.get(agent) or {}).get("model")
            f = cfg / "agents" / f"{agent}.md"
            if not m and f.is_file():
                fm = re.match(r"---\n(.*?)\n---", f.read_text(), re.S)
                mm = fm and re.search(r"^model:\s*(\S+)", fm.group(1), re.M)
                m = mm and mm.group(1)
            return m or None
        def family(model):
            return next((n for n, rx in FAMILIES if re.search(rx, model.split("/")[-1])), None)
        roles = {a: model_of(a) for a in AUTHORS + REVIEWERS}
        unknown = [f"{a}={m or 'inherit'}" for a, m in roles.items() if not m or not family(m)]
        if unknown:
            print(f"WARN: model family unknown, not checked: {', '.join(unknown)}", file=sys.stderr)
        known = {a: family(m) for a, m in roles.items() if m and family(m)}
        authors = {known[a] for a in AUTHORS if a in known}
        clash = [f"{r} ({known[r]})" for r in REVIEWERS if known.get(r) in authors]
        if clash:
            fail(f"same model family as the authors ({', '.join(sorted(authors))}): {', '.join(clash)}")
        elif authors and any(r in known for r in REVIEWERS):
            revs = sorted({known[r] for r in REVIEWERS if r in known})
            print(f"ok:   model families: authors {', '.join(sorted(authors))}, reviewers {', '.join(revs)}")

# Starting context: what a new session carries before the first prompt.
# Own parts are counted with the LLMi gateway (count_tokens); without it, estimated as chars / 3.2.

class Counter:
    def __init__(self):
        self.url = os.environ.get("AI_COUNT_URL") or self.plugin_url()
        self.model = os.environ.get("AI_COUNT_MODEL") or "claude-opus-5-5"
        self.key = ""
        self.base = 0
        self.exact = False
        self.warned = False
        if self.url:
            self.exact = self.start()

    def plugin_url(self):
        try:
            m = re.search(r'const baseURL = "([^"]+)"', (cfg / "plugins" / "llmi" / "index.ts").read_text())
            return m.group(1) if m else None
        except (OSError, ValueError):
            return None

    def start(self):
        if not self.url.lower().startswith("https://"):
            return self.give_up()
        try:
            cmd = os.environ.get("AI_COUNT_KEY_CMD") or "gopass show -o work-unattended/llmi-api-token"
            r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=10)
            self.key = r.stdout.strip() if r.returncode == 0 else ""
            if self.key:
                self.base = self.ask("x")
                if self.base is not None:
                    return True
        except Exception:
            pass
        return self.give_up()

    def give_up(self):
        self.exact = False
        if not self.warned:
            self.warned = True
            print("WARN: context: gateway count unavailable; estimate (chars / 3.2)", file=sys.stderr)
        return False

    def ask(self, text):
        import tempfile
        path = None
        n = None
        try:
            fd, path = tempfile.mkstemp()
            with os.fdopen(fd, "w") as f:
                json.dump({"model": self.model, "messages": [{"role": "user", "content": text}]}, f)
            headers = (f"Authorization: Bearer {self.key}\nx-api-key: {self.key}\n"
                       "anthropic-version: 2023-06-01\ncontent-type: application/json\n")
            r = subprocess.run(["curl", "--disable", "-sS", "--proto", "=https", "--max-time", "20",
                                "-w", "\n%{http_code}", "-X", "POST",
                                self.url.rstrip("/") + "/v1/messages/count_tokens",
                                "-H", "@-", "--data-binary", "@" + path],
                               input=headers, capture_output=True, text=True, timeout=25)
            body, _, status = r.stdout.rpartition("\n")
            n = json.loads(body)["input_tokens"] if r.returncode == 0 and status == "200" else None
            n = n if type(n) is int and n >= 0 else None
        except Exception:
            n = None
        finally:
            if path:
                try:
                    os.unlink(path)
                except FileNotFoundError:
                    pass
                except Exception:
                    n = None
        return n

    def count_all(self, parts):
        if self.exact:
            res = {}
            for k, t in parts.items():
                n = self.ask(t) if t else self.base
                if n is None:
                    self.give_up()
                    break
                res[k] = max(0, n - self.base)
            else:
                return res
        return {k: round(len(t) / 3.2) for k, t in parts.items()}

def hidden_skill(path):
    if not path or path.startswith("skill://") or not os.path.isfile(path):
        return False
    fm = re.match(r"---\n(.*?)\n---", Path(path).read_text(errors="replace"), re.S)
    return bool(fm and re.search(
        r"^\s*(opencode/autoinvoke:\s*false|disable-model-invocation:\s*true)\s*$",
        fm.group(1), re.M))

def measure():
    home = os.path.expanduser("~")
    global counter
    counter = Counter()
    parts = {}
    out = dict(instructions=0, skills=None, agents=None, bootstrap=0, own=None,
               total=None, sessions=0, rest=None, projects=[], missing=[])
    files = []
    texts = []
    conf = cfg / "opencode.json"
    if conf.is_file():
        try:
            files += [Path(os.path.expanduser(p)) for p in json.loads(conf.read_text()).get("instructions", [])]
        except ValueError:
            pass
    files.append(cfg / "AGENTS.md")
    for f in files:
        if f.is_file():
            texts.append(f.read_text(errors="replace"))
        else:
            out["missing"].append(str(f))
    parts["instructions"] = "\n\n".join(texts)
    skills = api("/api/skill?location[directory]=" + home)
    agents = api("/api/agent?location[directory]=" + home)
    def dicts(x):
        return [i for i in x if isinstance(i, dict)] if isinstance(x, list) else None
    def sval(d, k):
        v = d.get(k)
        return v if isinstance(v, str) else ""
    skills, agents = dicts(skills), dicts(agents)
    if skills is not None and agents is not None:
        parts["skills"] = "\n".join(
            f"<skill><id>{sval(s, 'id')}</id><name>{sval(s, 'id')}</name>"
            f"<description>{sval(s, 'description')}</description></skill>"
            for s in skills if not hidden_skill(sval(s, "path")))
        parts["agents"] = "\n".join(
            f"- {sval(a, 'name') or sval(a, 'id')}: {sval(a, 'description')}"
            for a in agents if a.get("mode") in ("subagent", "all") and not a.get("hidden"))
        boot = next((sval(s, "path") for s in skills if s.get("id") == "using-superpowers"), "")
        if boot and os.path.isfile(boot):
            parts["bootstrap"] = Path(boot).read_text(errors="replace")
    counts = counter.count_all(parts)
    out["instructions"] = counts["instructions"]
    if "skills" in parts:
        out["skills"], out["agents"] = counts["skills"], counts["agents"]
        out["bootstrap"] = counts.get("bootstrap", 0)
        out["own"] = out["instructions"] + out["skills"] + out["agents"] + out["bootstrap"]
    sess = api("/api/session?limit=200")
    sess = dicts(sess)
    out["sessions_ok"] = sess is not None
    def num(d, k):
        v = d.get(k) if isinstance(d, dict) else None
        return v if isinstance(v, (int, float)) and not isinstance(v, bool) else 0
    vals = []
    projs = {}
    roots = [s for s in sess or [] if isinstance(s.get("id"), str) and not s.get("parentID")]
    for s in sorted(roots, key=lambda s: num(s.get("time"), "created"), reverse=True):
        if len(vals) >= 10:
            break
        msgs = dicts(api(f"/api/session/{s['id']}/message?order=asc&limit=5"))
        if msgs is None:
            continue
        user = next((m for m in msgs if m.get("type") == "user"), {})
        asst = next((m for m in msgs if m.get("type") == "assistant"), None)
        if len(sval(user, "text")) > 500 or not asst or not isinstance(asst.get("tokens"), dict):
            continue
        mid = (asst.get("model") or {}).get("id") if isinstance(asst.get("model"), dict) else None
        if not isinstance(mid, str) or "claude" not in mid:
            continue
        t = asst["tokens"]
        cache = t.get("cache") if isinstance(t.get("cache"), dict) else {}
        parts = [d.get(k, 0) for d, k in ((t, "input"), (cache, "read"), (cache, "write"))]
        if not all(type(x) is int and x >= 0 for x in parts):
            continue
        v = sum(parts)
        if v:
            vals.append(v)
            loc = s.get("location")
            d = loc.get("directory") if isinstance(loc, dict) else None
            name = os.path.basename(d.rstrip("/")) if isinstance(d, str) and d.strip("/") else "?"
            projs.setdefault(name, []).append(v)
    out["projects"] = sorted(((k, int(statistics.median(v)), len(v)) for k, v in projs.items()),
                             key=lambda p: -p[2])
    out["sessions"] = len(vals)
    if vals:
        out["total"] = int(statistics.median(vals))
        if out["own"] is not None:
            out["rest"] = out["total"] - out["own"]
    return out

bm = re.search(r"^Context:\s*total\s*<\s*(\d+)\s*\(target\s*(\d+)\),\s*own\s*<\s*(\d+),"
               r"\s*instructions\s*<\s*(\d+),\s*skills\s*<\s*(\d+),\s*agents\s*<\s*(\d+)", text, re.M)
if not bm:
    fail("inventory has no 'Context: total < N (target T), own < N, instructions < N, skills < N, agents < N' line")
else:
    budgets = dict(zip(("total", "target", "own", "instructions", "skills", "agents"),
                       map(int, bm.groups())))
    ms = measure()
    ms["method"] = "count_tokens" if counter.exact else "estimate"
    for f in ms["missing"]:
        print(f"WARN: context: instruction file {f} not found", file=sys.stderr)
    parts = [("instructions", ms["instructions"])]
    if ms["skills"] is None:
        print("WARN: context: OpenCode service unavailable; skills, agents and own not measured", file=sys.stderr)
    else:
        parts += [("skills", ms["skills"]), ("agents", ms["agents"]), ("own", ms["own"])]
    for name, n in parts:
        if n >= budgets[name]:
            fail(f"context: {name} {n} >= {budgets[name]}")
        else:
            print(f"ok:   context: {name} {n} < {budgets[name]}")
    if ms["total"] is None:
        why = "no Claude sessions" if ms["sessions_ok"] else "OpenCode service unavailable"
        print(f"WARN: context: {why}; total not measured", file=sys.stderr)
    elif ms["total"] >= budgets["total"]:
        print(f"WARN: context: total {ms['total']} >= {budgets['total']} "
              f"(median of {ms['sessions']} sessions, target {budgets['target']})", file=sys.stderr)
    else:
        print(f"ok:   context: total {ms['total']} (median of {ms['sessions']} sessions, "
              f"{'over target' if ms['total'] >= budgets['target'] else 'target'} {budgets['target']})")

if status == 0 and os.environ.get("RECORD") == "--record":
    import datetime
    today = os.environ.get("AI_TODAY") or datetime.date.today().isoformat()
    page = Path(os.environ["WIKI"]) / "concepts" / "starting-context.md"
    body = page.read_text() if page.is_file() else ""
    pm = re.search(r"(<!-- context:begin -->\n)(.*?)(<!-- context:end -->)", body, re.S)
    if not pm:
        fail(f"{page} has no <!-- context:begin --> ... <!-- context:end --> block")
    elif pm.group(2).startswith(f"Recorded: {today}"):
        print("ok:   already recorded today")
    else:
        def cell(n):
            return "n/a" if n is None else str(n)
        how = "count_tokens" if ms["method"] == "count_tokens" else "estimate, chars / 3.2"
        rows = [("Instructions", ms["instructions"], budgets["instructions"], f"files in opencode.json + AGENTS.md, {how}"),
                ("Skill list", ms["skills"], budgets["skills"], f"id + name + description per visible skill, {how}"),
                ("Agent descriptions", ms["agents"], budgets["agents"], f"name + description per subagent, {how}"),
                ("Superpowers bootstrap", ms["bootstrap"], "", f"using-superpowers SKILL.md, {how}"),
                ("Own (sum)", ms["own"], budgets["own"], "instructions + skills + agents + bootstrap"),
                ("Session total (median of %d)" % ms["sessions"], ms["total"], budgets["total"], "first step of recent Claude sessions"),
                ("OpenCode + memory + plugins", ms["rest"], "", "derived: total - own")]
        lines = [f"Recorded: {today}", "", "| Part | Tokens | Budget | How measured |", "|---|---|---|---|"]
        lines += [f"| {a} | {cell(b)} | {c} | {d} |" for a, b, c, d in rows]
        if ms["projects"]:
            lines += ["", "Per project: " + ", ".join(f"{k} {m} ({n})" for k, m, n in ms["projects"])]
        out = body[:pm.start(2)] + "\n".join(lines) + "\n" + body[pm.start(3):]
        out = re.sub(r"\A(---\n.*?^)updated:[^\n]*", lambda m: f"{m.group(1)}updated: {today}", out, count=1, flags=re.S | re.M)
        data = out.encode()
        if os.environ.get("RECORD_GUARD"):
            r = subprocess.run(["git", "-C", os.environ["WIKI"], "show", "HEAD:concepts/starting-context.md"],
                               capture_output=True)
            if r.returncode != 0 or r.stdout != page.read_bytes():
                print("WARN: concepts/starting-context.md changed during the run; daily record skipped", file=sys.stderr)
                data = None
        if data is not None:
            page.write_bytes(data)
            blob = hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()
            print(f"ok:   recorded {today} in {page}")
            print(f"blob: {blob}")

if status == 0:
    print(f"ok:   inventory matches ({len(installed['Plugins'])} plugin(s) listed, not limited)")
sys.exit(status)
EOF
}

state_dir() {
  printf '%s' "${AI_STATE_DIR:-${XDG_STATE_HOME:-${HOME}/.local/state}/ai-inventory}"
}

daily_fail() { # STATE TODAY MESSAGE
  printf '%s\nFAIL: daily lock failed: %s\n' "${2}" "${3}" >"${1}/last" 2>/dev/null
}

# Runs non-interactively in the background (no prompts); all results go to the
# state file `last`. Git and network calls have no timeouts.
daily() {
  local state today wiki msg rc
  state="$(state_dir)"
  today="${AI_TODAY:-$(date +%F)}"
  wiki="${AI_WIKI_DIR:-${HOME}/wiki/ai-workflow}"
  mkdir -p "${state}" || return 0
  [ "$(head -n1 "${state}/last" 2>/dev/null)" = "${today}" ] && return 0
  # The kernel drops this lock when the process ends, so nothing goes stale.
  # The python child takes it on fd 9; it lives on while this shell keeps fd 9.
  # Exit 75 means another launch holds it; anything else is recorded in `last`.
  if [ -d "${state}/lock" ] && ! rmdir "${state}/lock" 2>/dev/null; then
    daily_fail "${state}" "${today}" "${state}/lock is a non-empty directory"
    return 0
  fi
  if ! { exec 9>"${state}/lock"; } 2>/dev/null; then
    daily_fail "${state}" "${today}" "cannot open ${state}/lock"
    return 0
  fi
  msg="$(python3 -c '
import fcntl, sys
try:
    fcntl.flock(9, fcntl.LOCK_EX | fcntl.LOCK_NB)
except BlockingIOError:
    sys.exit(75)
except Exception as e:
    print(e, file=sys.stderr)
    sys.exit(1)' 2>&1)" || {
    rc=$?
    [ "${rc}" -eq 75 ] && return 0
    daily_fail "${state}" "${today}" "${msg:-python3 exited ${rc}}"
    return 0
  }
  daily_record "${state}" "${today}" "${wiki}"
}

daily_record() { # STATE TODAY WIKI
  local state="${1}" today="${2}" wiki="${3}" out rc=0 problems page=concepts/starting-context.md dirty="" head tip branch remote mergeref nopush="" recsha newsha
  [ "$(head -n1 "${state}/last" 2>/dev/null)" = "${today}" ] && return 0
  export GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=true SSH_ASKPASS=true GIT_SSH_COMMAND="ssh -o BatchMode=yes"
  wgit() { git -C "${wiki}" -c credential.helper= -c core.hooksPath="${state}/no-hooks" "$@" </dev/null; }

  head="$(wgit rev-parse HEAD 2>/dev/null)"
  tip="$(wgit rev-parse '@{u}' 2>/dev/null)"
  branch="$(wgit symbolic-ref --short -q HEAD 2>/dev/null)"
  remote="$(wgit config "branch.${branch}.remote" 2>/dev/null)"
  mergeref="$(wgit config "branch.${branch}.merge" 2>/dev/null)"
  if [ -z "${tip}" ] || [ -z "${remote}" ] || [ -z "${mergeref}" ]; then
    nopush="no upstream"
  elif [ "${head}" != "${tip}" ]; then
    nopush="unpushed commits"
  fi

  if [ -n "$(wgit status --porcelain -- "${page}" 2>/dev/null)" ]; then
    dirty=1
    out="$(check 2>&1)" || rc=$?
  else
    wgit rev-parse --git-dir >/dev/null 2>&1 && export RECORD_GUARD=1
    out="$(check --record 2>&1)" || rc=$?
  fi
  problems="$(printf '%s\n' "${out}" | grep -E '^(FAIL|WARN):' || true)"
  if [ "${rc}" -ne 0 ] && ! printf '%s\n' "${out}" | grep -q '^FAIL:'; then
    problems="${problems:+${problems}$'\n'}FAIL: ai-inventory check exited ${rc}; run bash ~/dotfiles/test/ai-inventory.sh"
  fi

  if [ -n "${dirty}" ]; then
    problems="${problems:+${problems}$'\n'}WARN: ${page} has uncommitted edits; daily record skipped"
  elif [ "${rc}" -eq 0 ] && printf '%s\n' "${out}" | grep -q '^ok:   recorded ' &&
    wgit rev-parse --git-dir >/dev/null 2>&1; then
    recsha="$(printf '%s\n' "${out}" | sed -n 's/^blob: //p')"
    # Unsigned is intentional for the unattended daily record (user decision 2026-11-20).
    # All hooks are skipped (--no-verify, core.hooksPath to a missing dir): nobody is there to answer one.
    if [ -z "${recsha}" ] || [ "$(wgit hash-object --no-filters -- "${wiki}/${page}" 2>/dev/null)" != "${recsha}" ]; then
      problems="${problems:+${problems}$'\n'}WARN: ${page} changed during the run; daily commit skipped"
    elif [ "$(wgit rev-parse HEAD 2>/dev/null)" != "${head}" ]; then
      problems="${problems:+${problems}$'\n'}WARN: wiki HEAD moved during the run; daily record not committed"
    elif wgit -c commit.gpgsign=false commit -q --no-verify -m "chore: context record ${today}" -- "${page}" >/dev/null 2>&1; then
      newsha="$(wgit rev-parse HEAD 2>/dev/null)"
      if [ -z "${newsha}" ] || [ "$(wgit rev-parse "${newsha}^" 2>/dev/null)" != "${head}" ]; then
        problems="${problems:+${problems}$'\n'}WARN: wiki HEAD moved during the run; daily record committed but not pushed"
      elif [ -n "${nopush}" ]; then
        problems="${problems:+${problems}$'\n'}WARN: wiki has ${nopush}; daily record committed but not pushed"
      elif [ "$(wgit rev-parse HEAD 2>/dev/null)" != "${newsha}" ]; then
        problems="${problems:+${problems}$'\n'}WARN: wiki HEAD moved during the run; daily record committed but not pushed"
      else
        # Push exactly the new commit id, never other outstanding ones.
        wgit push -q --no-verify "${remote}" "${newsha}:${mergeref}" >/dev/null 2>&1 ||
          problems="${problems:+${problems}$'\n'}WARN: wiki push failed; push ~/wiki/ai-workflow by hand"
      fi
    else
      problems="${problems:+${problems}$'\n'}WARN: wiki commit failed; commit ${page} in ~/wiki/ai-workflow by hand"
    fi
  fi
  printf '%s\n%s\n' "${today}" "${problems}" | sed '/^$/d' >"${state}/last"
  return 0
}

status() {
  local f date d
  f="$(state_dir)/last"
  d="$(state_dir)"
  while [ ! -e "${d}" ] && [ "${d}" != "/" ] && [ "${d}" != "." ]; do d="$(dirname "${d}")"; done
  if [ ! -w "${d}" ]; then
    printf 'ai-inventory: %s is not writable; daily record cannot run\n' "$(state_dir)"
  fi
  [ -f "${f}" ] || return 0
  date="$(head -n1 "${f}")"
  tail -n +2 "${f}" | grep -E '^(FAIL|WARN):' | while IFS= read -r line; do
    printf 'ai-inventory (%s): %s\n' "${date}" "${line}"
  done
  return 0
}

self_test() {
  local root failures=0 RUN_ARG='' CASE_COUNT_KEY_CMD='' CASE_COUNT_URL=''
  root="$(mktemp -d /tmp/ai-inventory.XXXXXX)"
  export AI_COUNT_KEY_CMD=false AI_COUNT_URL=
  # shellcheck disable=SC2064 # expand now: root is local
  trap "rm -rf '${root}'" RETURN

  # fixture NAME AGENTS SKILLS: a config dir with those agents and skills.
  fixture() {
    local cfg="${root}/${1}/cfg" a s
    mkdir -p "${cfg}/agents" "${cfg}/skills" "${root}/${1}/wiki"
    for a in ${2}; do echo "---" >"${cfg}/agents/${a}.md"; done
    for s in ${3}; do mkdir -p "${cfg}/skills/${s}"; done
  }
  inventory() {
    cat >"${root}/${1}/wiki/inventory.md"
  }
  run() {
    local fake="${OC_FAKE_DIR:-${root}/bin-down}"
    [ -d "${root}/${1}/fake" ] && fake="${root}/${1}/fake"
    if [ -n "${CASE_COUNT_KEY_CMD}" ] || [ -n "${CASE_COUNT_URL}" ]; then
      if [ ! -f "${root}/${1}/fake/bin/curl" ] || [ ! -x "${root}/${1}/fake/bin/curl" ]; then
        echo "run ${1}: gateway override without a fixture fake curl" >"${root}/${1}.log"
        return 1
      fi
      fake="${root}/${1}/fake"
    fi
    PATH="${fake}/bin:${PATH}" \
      AI_WIKI_DIR="${root}/${1}/wiki" OPENCODE_CONFIG_DIR_CHECK="${root}/${1}/cfg" \
      AI_TODAY=2026-11-20 AI_STATE_DIR="${root}/${1}/state" \
      AI_COUNT_KEY_CMD="${CASE_COUNT_KEY_CMD:-false}" AI_COUNT_URL="${CASE_COUNT_URL-}" \
      AI_INVENTORY_PLUGINS="superpowers" bash "${BASH_SOURCE[0]}" ${RUN_ARG:+"${RUN_ARG}"} >"${root}/${1}.log" 2>&1
  }
  expect() { # NAME WANT_EXIT GREP
    local got=0
    run "${1}" || got=$?
    if [ "${got}" -eq "${2}" ] && { [ -z "${3}" ] || grep -q -- "${3}" "${root}/${1}.log"; }; then
      echo "ok:   ${1}"
    else
      echo "FAIL: ${1}: exit ${got}, want ${2} and '${3}'" >&2
      sed 's/^/      /' "${root}/${1}.log" >&2
      failures=$((failures + 1))
    fi
  }
  mkdir -p "${root}/bin-down/bin"
  printf '#!/bin/sh\nexit 1\n' >"${root}/bin-down/bin/opencode"
  chmod +x "${root}/bin-down/bin/opencode"
  # fake_service NAME SKILLS_JSON AGENTS_JSON SESSIONS_JSON: an opencode that
  # answers the API paths from files; add sessions with ctx_file.
  fake_service() {
    local d="${root}/${1}/fake"
    mkdir -p "${d}/bin"
    printf '{"data":%s}' "${2}" >"${d}/skills.json"
    printf '{"data":%s}' "${3}" >"${d}/agents.json"
    printf '{"data":%s}' "${4}" >"${d}/sessions.json"
    cat >"${d}/bin/opencode" <<'EOS'
#!/bin/sh
d="$(dirname "$0")/.."
echo "$*" >>"$d/calls.log"
case "$3" in
*/api/skill*) cat "$d/skills.json" ;;
*/api/agent*) cat "$d/agents.json" ;;
*/api/session/*/message\?order=asc\&limit=5)
  id="${3#*/api/session/}"
  cat "$d/ctx-${id%%/message*}.json"
  ;;
*/api/session\?*)
  [ -n "${FAKE_TOUCH:-}" ] && echo "edit during run" >>"$FAKE_TOUCH"
  if [ -n "${FAKE_COMMIT:-}" ]; then
    echo x >"${FAKE_COMMIT}/unrelated-run.md"
    git -C "${FAKE_COMMIT}" add unrelated-run.md
    git -C "${FAKE_COMMIT}" -c commit.gpgsign=false commit -q -m "unrelated during run" -- unrelated-run.md
  fi
  cat "$d/sessions.json"
  ;;
*) exit 1 ;;
esac
EOS
    chmod +x "${d}/bin/opencode"
  }
  # ctx_file NAME ID TOTAL USER_CHARS MODEL
  ctx_file() {
    local text
    text="$(printf '%*s' "${4}" '' | tr ' ' x)"
    printf '{"data":[{"type":"user","text":"%s"},{"type":"assistant","model":{"id":"%s","providerID":"p"},"tokens":{"input":%s,"output":0,"reasoning":0,"cache":{"read":0,"write":0}}}]}' \
      "${text}" "${5}" "${3}" >"${root}/${1}/fake/ctx-${2}.json"
  }
  # fake_gateway NAME [MODE]: a curl that logs its argv (never the key) and
  # answers input_tokens = 10 + len(content) // 5 only for a valid request:
  # POST to https://.../v1/messages/count_tokens, --disable first, --proto =https,
  # Authorization/x-api-key/anthropic-version headers on stdin with the key from
  # NAME/key, model claude-opus-5-5, one user message. A bad request answers 400.
  # MODE: down (exit 7), timeout (exit 28), bad (no input_tokens), late (fails
  # after two calls), status201, str ("12"), float (1.5).
  fake_gateway() {
    local d="${root}/${1}/fake"
    mkdir -p "${d}/bin"
    (umask 077 && printf 'SECRETKEY123' >"${root}/${1}/key")
    printf '%s' "${2:-}" >"${d}/mode"
    cat >"${d}/bin/curl" <<'EOS'
#!/usr/bin/env python3
import json, os, sys
d = os.path.join(os.path.dirname(os.path.abspath(sys.argv[0])), "..")
args = sys.argv[1:]
with open(os.path.join(d, "curl.log"), "a") as f:
    f.write(" ".join(args).replace("\n", "\\n") + "\n")
headers = sys.stdin.read()
mode = open(os.path.join(d, "mode")).read()
key = open(os.path.join(d, "..", "key")).read()
if args[:1] != ["--disable"]:
    sys.exit(2)
if mode == "down":
    sys.exit(7)
if mode == "timeout":
    sys.exit(28)
if mode == "late" and len(open(os.path.join(d, "curl.log")).read().splitlines()) > 2:
    sys.exit(7)
def out(body, status="200"):
    print(body + "\n" + status, end="")
    sys.exit(0)
if mode == "bad":
    out('{"x":1}')
ok = ("-X" in args and args[args.index("-X") + 1] == "POST"
      and "--proto" in args and args[args.index("--proto") + 1] == "=https"
      and any(a.startswith("https://") and a.endswith("/v1/messages/count_tokens") for a in args)
      and f"Authorization: Bearer {key}" in headers.splitlines()
      and f"x-api-key: {key}" in headers.splitlines()
      and "anthropic-version: 2023-06-01" in headers.splitlines())
body = None
for a in args:
    if a.startswith("@/"):
        body = json.load(open(a[1:]))
ok = ok and isinstance(body, dict) and body.get("model") == "claude-opus-5-5" \
    and isinstance(body.get("messages"), list) and len(body["messages"]) == 1 \
    and body["messages"][0].get("role") == "user"
if not ok:
    out('{"error":"bad request"}', "400")
n = 10 + len(body["messages"][0]["content"]) // 5
if mode == "str":
    n = str(n)
elif mode == "float":
    n = 1.5
out(json.dumps({"input_tokens": n}), "201" if mode == "status201" else "200")
EOS
    chmod +x "${d}/bin/curl"
  }
  # gw_expect NAME WANT_EXIT GREP [URL]: expect with the fixture's fake gateway;
  # the key is read from NAME/key, never written on a command line.
  gw_expect() {
    CASE_COUNT_URL="${4:-https://gw.test}" CASE_COUNT_KEY_CMD="cat '${root}/${1}/key'" expect "${1}" "${2}" "${3}"
  }
  # sessions_json N: root sessions s1..sN, newest last id first.
  sessions_json() {
    local i out=""
    for i in $(seq 1 "${1}"); do out="${out:+${out},}{\"id\":\"s${i}\",\"time\":{\"created\":${i}},\"location\":{\"directory\":\"/p/proj\"}}"; done
    echo "[${out}]"
  }
  # ctx_case NAME INSTR_CHARS SKILLS_JSON MODEL TOTAL...: fixture, inventory,
  # instructions file, fake service with one session per TOTAL.
  ctx_case() {
    local n="${1}" chars="${2}" skills="${3}" model="${4}" i=0 t
    shift 4
    fixture "${n}" "alpha beta" "one"
    good_inventory | inventory "${n}"
    printf '%*s' "${chars}" '' | tr ' ' x >"${root}/${n}/instr.md"
    printf '{"instructions": ["%s"]}' "${root}/${n}/instr.md" >"${root}/${n}/cfg/opencode.json"
    fake_service "${n}" "${skills}" '[{"id":"alpha","name":"alpha","description":"a","mode":"subagent"}]' "$(sessions_json "$#")"
    for t in "$@"; do
      i=$((i + 1))
      ctx_file "${n}" "s${i}" "${t}" 10 "${model}"
    done
  }
  small_skills='[{"id":"one","description":"d"},{"id":"two","description":"d"}]'
  big_skills() { # PATH
    printf '[{"id":"big","description":"%s","path":"%s"}]' "$(printf '%*s' 12000 '' | tr ' ' x)" "${1}"
  }
  good_inventory() {
    cat <<'EOF'
Limits: agents < 3, skills < 3
Context: total < 25000 (target 20000), own < 10000, instructions < 2000, skills < 3000, agents < 1000

## Agents

| Id | Why | Added | Reviewed |
|---|---|---|---|
| `alpha` | a | 2026-11-19 | 2026-11-19 |
| `beta` | b | 2026-11-19 | 2026-11-19 |

## Skills

| Id | Why | Added | Reviewed |
|---|---|---|---|
| `one` | c | 2026-11-19 | 2026-11-19 |

## Plugins

| Id | Why | Added | Reviewed |
|---|---|---|---|
| `superpowers` | d | 2026-11-19 | 2026-11-19 |

## Project skills

| Id | Repo | Added | Reviewed |
|---|---|---|---|
| `not-checked` | x | 2026-11-19 | 2026-11-19 |
EOF
  }

  fixture missing_wiki_warns_exit0 "alpha" ""
  rmdir "${root}/missing_wiki_warns_exit0/wiki"
  expect missing_wiki_warns_exit0 0 "WARN"

  fixture complete_inventory_passes "alpha beta" "one"
  good_inventory | inventory complete_inventory_passes
  expect complete_inventory_passes 0 "ok"

  fixture unlisted_agent_fails "alpha beta gamma" "one"
  good_inventory | inventory unlisted_agent_fails
  expect unlisted_agent_fails 1 "gamma"

  fixture stale_row_fails "alpha" "one"
  good_inventory | inventory stale_row_fails
  expect stale_row_fails 1 "beta"

  fixture agents_over_limit_fails "alpha beta gamma" "one"
  # shellcheck disable=SC2016 # literal backticks
  good_inventory | sed '/`beta`/a | `gamma` | g | 2026-11-19 | 2026-11-19 |' |
    inventory agents_over_limit_fails
  expect agents_over_limit_fails 1 "limit"

  fixture missing_limits_fails "alpha beta" "one"
  good_inventory | sed '/^Limits:/d' | inventory missing_limits_fails
  expect missing_limits_fails 1 "Limits"

  # Service down: no AI_INVENTORY_PLUGINS and an opencode that fails.
  fixture service_down_hints "alpha beta" "one"
  good_inventory | inventory service_down_hints
  mkdir -p "${root}/bin"
  printf '#!/bin/sh\nexit 1\n' >"${root}/bin/opencode"
  chmod +x "${root}/bin/opencode"
  local got=0
  PATH="${root}/bin:${PATH}" AI_WIKI_DIR="${root}/service_down_hints/wiki" \
    OPENCODE_CONFIG_DIR_CHECK="${root}/service_down_hints/cfg" \
    bash "${BASH_SOURCE[0]}" >"${root}/service_down_hints.log" 2>&1 || got=$?
  if [ "${got}" -eq 0 ] && grep -q "WARN: could not list plugins from the OpenCode service" "${root}/service_down_hints.log" &&
    grep -q "AI_INVENTORY_PLUGINS" "${root}/service_down_hints.log"; then
    echo "ok:   service_down_hints"
  else
    echo "FAIL: service_down_hints: exit ${got}, want 0 and a WARN naming AI_INVENTORY_PLUGINS" >&2
    sed 's/^/      /' "${root}/service_down_hints.log" >&2
    failures=$((failures + 1))
  fi

  ctx_case service_down_instructions_over_fails 8400 "${small_skills}" claude-x 20000
  got=0
  PATH="${root}/bin:${PATH}" AI_WIKI_DIR="${root}/service_down_instructions_over_fails/wiki" \
    OPENCODE_CONFIG_DIR_CHECK="${root}/service_down_instructions_over_fails/cfg" \
    bash "${BASH_SOURCE[0]}" >"${root}/service_down_instructions_over_fails.log" 2>&1 || got=$?
  if [ "${got}" -eq 1 ] && grep -q "FAIL: context: instructions .* >= 2000" "${root}/service_down_instructions_over_fails.log"; then
    echo "ok:   service_down_instructions_over_fails"
  else
    echo "FAIL: service_down_instructions_over_fails: exit ${got}, want 1 and the instructions FAIL" >&2
    sed 's/^/      /' "${root}/service_down_instructions_over_fails.log" >&2
    failures=$((failures + 1))
  fi

  # Plugins from the service: scoped packages keep their scope.
  fixture scoped_plugin_detected "alpha beta" "one"
  # shellcheck disable=SC2016 # literal backticks
  good_inventory | sed 's/`superpowers`/`@acme\/helpers`/' | inventory scoped_plugin_detected
  cat >"${root}/bin/opencode" <<'EOF'
#!/bin/sh
echo '{"data":[{"id":"x","path":"/c/node_modules/@acme/helpers/skills/x/SKILL.md"},{"id":"b","path":"skill://browser/SKILL.md"}]}'
EOF
  got=0
  PATH="${root}/bin:${PATH}" AI_WIKI_DIR="${root}/scoped_plugin_detected/wiki" \
    OPENCODE_CONFIG_DIR_CHECK="${root}/scoped_plugin_detected/cfg" \
    bash "${BASH_SOURCE[0]}" >"${root}/scoped_plugin_detected.log" 2>&1 || got=$?
  if [ "${got}" -eq 0 ]; then
    echo "ok:   scoped_plugin_detected"
  else
    echo "FAIL: scoped_plugin_detected: exit ${got}, want 0" >&2
    sed 's/^/      /' "${root}/scoped_plugin_detected.log" >&2
    failures=$((failures + 1))
  fi

  # flaky_plugins NAME FIRST_GOOD_CALL: opencode whose skill lists omit the
  # plugin until call FIRST_GOOD_CALL (a slow cold start; 99 = never).
  flaky_plugins() {
    local d="${root}/${1}/flaky"
    fixture "${1}" "alpha beta" "one"
    good_inventory | inventory "${1}"
    mkdir -p "${d}"
    cat >"${d}/opencode" <<EOS
#!/bin/sh
case "\$3" in
*/api/skill*)
  echo x >>"${d}/skill-calls"
  if [ "\$(wc -l <"${d}/skill-calls")" -lt "${2}" ]; then
    echo '{"data":[{"id":"b","path":"skill://b"}]}'
  else
    echo '{"data":[{"id":"x","path":"/c/node_modules/superpowers/skills/x/SKILL.md"}]}'
  fi
  ;;
*) echo '{"data":[]}' ;;
esac
EOS
    chmod +x "${d}/opencode"
    got=0
    PATH="${d}:${PATH}" AI_INVENTORY_RETRY_DELAY=0 AI_WIKI_DIR="${root}/${1}/wiki" \
      OPENCODE_CONFIG_DIR_CHECK="${root}/${1}/cfg" \
      bash "${BASH_SOURCE[0]}" >"${root}/${1}.log" 2>&1 || got=$?
  }
  flaky_plugins plugin_list_retried_passes 2
  if [ "${got}" -eq 0 ] && grep -q "inventory matches" "${root}/plugin_list_retried_passes.log"; then
    echo "ok:   plugin_list_retried_passes"
  else
    echo "FAIL: plugin_list_retried_passes: exit ${got}" >&2
    failures=$((failures + 1))
  fi
  flaky_plugins plugin_late_appears_passes 5
  if [ "${got}" -eq 0 ] && grep -q "inventory matches" "${root}/plugin_late_appears_passes.log"; then
    echo "ok:   plugin_late_appears_passes"
  else
    echo "FAIL: plugin_late_appears_passes: exit ${got}" >&2
    failures=$((failures + 1))
  fi
  flaky_plugins plugin_always_missing_fails 99
  if [ "${got}" -eq 1 ] && grep -q "'superpowers' is in the inventory but not installed" "${root}/plugin_always_missing_fails.log" &&
    [ "$(wc -l <"${root}/plugin_always_missing_fails/flaky/skill-calls")" -ge 3 ]; then
    echo "ok:   plugin_always_missing_fails"
  else
    echo "FAIL: plugin_always_missing_fails: exit ${got}" >&2
    failures=$((failures + 1))
  fi

  fixture hidden_skill_dir_ignored "alpha beta" "one .git"
  good_inventory | inventory hidden_skill_dir_ignored
  expect hidden_skill_dir_ignored 0 "Skills: 1 installed"

  fixture wiki_skill_unlisted_fails "alpha beta" "one"
  mkdir -p "${root}/wiki_skill_unlisted_fails/wiki/skills/private" "${root}/wiki_skill_unlisted_fails/wiki/skills/no-skill-md"
  echo "---" >"${root}/wiki_skill_unlisted_fails/wiki/skills/private/SKILL.md"
  good_inventory | inventory wiki_skill_unlisted_fails
  expect wiki_skill_unlisted_fails 1 "'private' is installed but not in the inventory"

  fixture wiki_skill_listed_passes "alpha beta" "one"
  mkdir -p "${root}/wiki_skill_listed_passes/wiki/skills/private"
  echo "---" >"${root}/wiki_skill_listed_passes/wiki/skills/private/SKILL.md"
  # shellcheck disable=SC2016 # literal backticks
  good_inventory | sed 's/^| `one` |.*/&\n| `private` | p | 2026-11-24 | 2026-11-24 |/' | inventory wiki_skill_listed_passes
  expect wiki_skill_listed_passes 0 "Skills: 2 installed"

  fixture row_without_backticks_counts "alpha beta" "one"
  # shellcheck disable=SC2016 # literal backticks
  good_inventory | sed 's/| `beta` |/| beta |/' | inventory row_without_backticks_counts
  expect row_without_backticks_counts 0 "inventory matches"

  # models NAME AUTHOR REVIEWER: an opencode.json pinning both roles.
  models() {
    cat >"${root}/${1}/cfg/opencode.json" <<EOF
{"model": "x/top", "agents": {
  "general": {"model": "${2}"}, "coder": {"model": "${2}"},
  "reviewer": {"model": "${3}"}, "cpp-reviewer": {"model": "${3}"}}}
EOF
  }

  fixture families_differ_passes "alpha beta" "one"
  good_inventory | inventory families_differ_passes
  models families_differ_passes github-copilot/claude-sonnet-9 github-copilot/gpt-9-sol
  expect families_differ_passes 0 "ok:   model families"

  fixture same_family_fails "alpha beta" "one"
  good_inventory | inventory same_family_fails
  models same_family_fails github-copilot/claude-sonnet-9 github-copilot/claude-opus-9
  expect same_family_fails 1 "same model family"

  fixture unknown_family_warns "alpha beta" "one"
  good_inventory | inventory unknown_family_warns
  models unknown_family_warns opencode/big-pickle opencode/big-pickle
  expect unknown_family_warns 0 "WARN: .*big-pickle"

  # Reviewer pinned only in its agent file, not in JSON.
  fixture agent_file_model_counts "alpha beta reviewer" "one"
  # shellcheck disable=SC2016 # literal backticks
  good_inventory | sed '/`beta`/a | `reviewer` | r | 2026-11-19 | 2026-11-19 |' |
    sed 's/agents < 3/agents < 9/' | inventory agent_file_model_counts
  echo '{"agents": {"general": {"model": "github-copilot/claude-sonnet-9"}}}' \
    >"${root}/agent_file_model_counts/cfg/opencode.json"
  printf -- '---\nmodel: github-copilot/claude-opus-9\n---\n' >"${root}/agent_file_model_counts/cfg/agents/reviewer.md"
  expect agent_file_model_counts 1 "same model family"

  ctx_case context_ok 400 "${small_skills}" claude-x 18000 19000 20000 21000 22000
  expect context_ok 0 "ok:   context: total 20000"
  if grep -q 'api/session?limit=200$' "${root}/context_ok/fake/calls.log"; then
    echo "ok:   context_lists_200_sessions"
  else
    echo "FAIL: context_lists_200_sessions: session list not requested with limit=200" >&2
    failures=$((failures + 1))
  fi

  ctx_case context_first_step_not_compacted 400 "${small_skills}" claude-x 20000
  printf '{"data":[{"type":"user","text":"x"},{"type":"assistant","model":{"id":"claude-x"},"tokens":{"input":15000,"cache":{"read":3000,"write":2000}}},{"type":"compaction"},{"type":"assistant","model":{"id":"claude-x"},"tokens":{"input":55000,"cache":{"read":0,"write":0}}}]}' \
    >"${root}/context_first_step_not_compacted/fake/ctx-s1.json"
  expect context_first_step_not_compacted 0 "ok:   context: total 20000"

  ctx_case context_first_reply_tokenless_skipped 400 "${small_skills}" claude-x 20000
  printf '{"data":[{"type":"user","text":"x"},{"type":"assistant","model":{"id":"big-pickle"}},{"type":"assistant","model":{"id":"claude-x"},"tokens":{"input":20000,"cache":{"read":0,"write":0}}}]}' \
    >"${root}/context_first_reply_tokenless_skipped/fake/ctx-s1.json"
  expect context_first_reply_tokenless_skipped 0 "WARN: context: no Claude sessions"

  ctx_case context_samples_ten 400 "${small_skills}" claude-x 1000 2000 3000 4000 5000 6000 7000 8000 9000 10000 11000 12000 99999 99999
  printf '{"data":[{"id":"s1","time":{"created":1}},{"id":"s2","time":{"created":2}},{"id":"s3","time":{"created":3}},{"id":"s4","time":{"created":4}},{"id":"s5","time":{"created":5}},{"id":"s6","time":{"created":6}},{"id":"s7","time":{"created":7}},{"id":"s8","time":{"created":8}},{"id":"s9","time":{"created":9}},{"id":"s10","time":{"created":10}},{"id":"s11","time":{"created":11}},{"id":"s12","time":{"created":12}},{"id":"s13","time":{"created":13},"parentID":"x"},{"id":"s14","time":{"created":14}}]}' \
    >"${root}/context_samples_ten/fake/sessions.json"
  ctx_file context_samples_ten s14 99999 10 big-pickle
  expect context_samples_ten 0 "median of 10 sessions"
  expect context_samples_ten 0 "total 7500 "

  ctx_case context_over_target_says_so 400 "${small_skills}" claude-x 21000 21000 21000
  expect context_over_target_says_so 0 "ok:   context: total 21000 .median of 3 sessions, over target 20000."

  ctx_case context_instructions_over_fails 8400 "${small_skills}" claude-x 20000
  expect context_instructions_over_fails 1 "instructions .* >= 2000"

  ctx_case context_skills_over_fails 400 "$(big_skills /nope)" claude-x 20000
  expect context_skills_over_fails 1 "skills .* >= 3000"

  ctx_case context_agents_over_fails 400 "${small_skills}" claude-x 20000
  printf '[{"id":"alpha","name":"alpha","description":"%s","mode":"subagent"}]' "$(printf '%*s' 4000 '' | tr ' ' x)" |
    sed 's/^/{"data":/; s/$/}/' >"${root}/context_agents_over_fails/fake/agents.json"
  expect context_agents_over_fails 1 "agents .* >= 1000"

  ctx_case context_own_over_fails 400 '[{"id":"using-superpowers","description":"d","path":"'"${root}"'/context_own_over_fails/boot.md"}]' claude-x 20000
  printf '%*s' 40000 '' | tr ' ' x >"${root}/context_own_over_fails/boot.md"
  expect context_own_over_fails 1 "own .* >= 10000"

  ctx_case context_hidden_skill_not_counted 400 "$(big_skills "${root}/context_hidden_skill_not_counted/SKILL.md")" claude-x 20000
  printf -- '---\nname: big\nmetadata:\n  opencode/autoinvoke: false\n---\n' >"${root}/context_hidden_skill_not_counted/SKILL.md"
  expect context_hidden_skill_not_counted 0 "ok:   context: skills"

  ctx_case context_total_over_warns 400 "${small_skills}" claude-x 26000 26000 26000 26000 26000
  expect context_total_over_warns 0 "WARN: context: total 26000 >= 25000"

  ctx_case context_long_prompt_skipped 400 "${small_skills}" claude-x 20000 20000 20000 20000 20000 90000
  ctx_file context_long_prompt_skipped s6 90000 600 claude-x
  expect context_long_prompt_skipped 0 "total 20000"

  ctx_case context_no_claude_warns 400 "${small_skills}" big-pickle 20000 20000
  expect context_no_claude_warns 0 "WARN: context: no Claude sessions"

  ctx_case count_exact 400 "${small_skills}" claude-x 20000
  fake_gateway count_exact
  gw_expect count_exact 0 "ok:   context: instructions 80 <"
  if [ -s "${root}/count_exact/fake/curl.log" ] && [ -s "${root}/count_exact.log" ] &&
    ! grep -q SECRETKEY123 "${root}/count_exact/fake/curl.log" "${root}/count_exact.log"; then
    echo "ok:   count_key_not_logged"
  else
    echo "FAIL: count_key_not_logged: key found in curl argv or run log" >&2
    failures=$((failures + 1))
  fi

  ctx_case count_gateway_down_estimates 400 "${small_skills}" claude-x 20000
  fake_gateway count_gateway_down_estimates down
  gw_expect count_gateway_down_estimates 0 "instructions 125 <"
  if [ "$(grep -c 'WARN: context: gateway count unavailable' "${root}/count_gateway_down_estimates.log")" -eq 1 ]; then
    echo "ok:   count_gateway_down_estimates one warn"
  else
    echo "FAIL: count_gateway_down_estimates: want exactly one gateway WARN" >&2
    failures=$((failures + 1))
  fi

  ctx_case count_bad_answer_estimates 400 "${small_skills}" claude-x 20000
  fake_gateway count_bad_answer_estimates bad
  gw_expect count_bad_answer_estimates 0 "instructions 125 <"
  if [ "$(grep -c 'WARN: context: gateway count unavailable' "${root}/count_bad_answer_estimates.log")" -eq 1 ] &&
    ! grep -q Traceback "${root}/count_bad_answer_estimates.log"; then
    echo "ok:   count_bad_answer_estimates one warn, no traceback"
  else
    echo "FAIL: count_bad_answer_estimates: want one WARN and no Traceback" >&2
    failures=$((failures + 1))
  fi

  if [ "$(grep -vc '^--disable ' "${root}/count_exact/fake/curl.log")" -eq 0 ]; then
    echo "ok:   count_curl_disables_config"
  else
    echo "FAIL: count_curl_disables_config: curl first argument is not --disable" >&2
    failures=$((failures + 1))
  fi

  # one_warn_case NAME MODE: the fake gateway in MODE leads to an all-estimate run with one WARN.
  one_warn_case() {
    ctx_case "${1}" 400 "${small_skills}" claude-x 20000
    fake_gateway "${1}" "${2}"
    gw_expect "${1}" 0 "instructions 125 <"
    if [ "$(grep -c 'WARN: context: gateway count unavailable' "${root}/${1}.log")" -eq 1 ]; then
      echo "ok:   ${1} one warn"
    else
      echo "FAIL: ${1}: want exactly one gateway WARN" >&2
      failures=$((failures + 1))
    fi
  }
  one_warn_case count_status_201_estimates status201
  one_warn_case count_string_count_estimates str
  one_warn_case count_float_count_estimates float
  one_warn_case count_timeout_estimates timeout

  ctx_case count_http_url_estimates 400 "${small_skills}" claude-x 20000
  fake_gateway count_http_url_estimates
  CASE_COUNT_URL=http://gw.test CASE_COUNT_KEY_CMD="touch '${root}/count_http_url_estimates/marker'; cat '${root}/count_http_url_estimates/key'" \
    expect count_http_url_estimates 0 "instructions 125 <"
  if [ "$(grep -c 'WARN: context: gateway count unavailable' "${root}/count_http_url_estimates.log")" -eq 1 ] &&
    [ ! -e "${root}/count_http_url_estimates/marker" ] && [ ! -e "${root}/count_http_url_estimates/fake/curl.log" ]; then
    echo "ok:   count_http_url_estimates key not fetched"
  else
    echo "FAIL: count_http_url_estimates: want one WARN, no key command, no curl" >&2
    failures=$((failures + 1))
  fi

  ctx_case count_plugin_undecodable_silent 400 "${small_skills}" claude-x 20000
  fake_gateway count_plugin_undecodable_silent
  mkdir -p "${root}/count_plugin_undecodable_silent/cfg/plugins/llmi"
  printf '\377\376 const baseURL = "https://gw.test"\n' >"${root}/count_plugin_undecodable_silent/cfg/plugins/llmi/index.ts"
  expect count_plugin_undecodable_silent 0 "instructions 125 <"
  if ! grep -q 'gateway\|Traceback' "${root}/count_plugin_undecodable_silent.log"; then
    echo "ok:   count_plugin_undecodable_silent"
  else
    echo "FAIL: count_plugin_undecodable_silent: unexpected message" >&2
    failures=$((failures + 1))
  fi

  ctx_case count_late_failure_all_estimate 400 "${small_skills}" claude-x 20000
  fake_gateway count_late_failure_all_estimate late
  gw_expect count_late_failure_all_estimate 0 "instructions 125 <"
  if [ "$(grep -c 'WARN: context: gateway count unavailable' "${root}/count_late_failure_all_estimate.log")" -eq 1 ]; then
    echo "ok:   count_late_failure_all_estimate one warn"
  else
    echo "FAIL: count_late_failure_all_estimate: want exactly one gateway WARN" >&2
    failures=$((failures + 1))
  fi

  ctx_case count_no_plugin_silent 400 "${small_skills}" claude-x 20000
  expect count_no_plugin_silent 0 "instructions 125 <"
  if ! grep -q gateway "${root}/count_no_plugin_silent.log"; then
    echo "ok:   count_no_plugin_silent"
  else
    echo "FAIL: count_no_plugin_silent: unexpected gateway message" >&2
    failures=$((failures + 1))
  fi

  ctx_case count_url_from_plugin 400 "${small_skills}" claude-x 20000
  fake_gateway count_url_from_plugin
  mkdir -p "${root}/count_url_from_plugin/cfg/plugins/llmi"
  echo 'const baseURL = "https://gw.test"' >"${root}/count_url_from_plugin/cfg/plugins/llmi/index.ts"
  CASE_COUNT_KEY_CMD="cat '${root}/count_url_from_plugin/key'" expect count_url_from_plugin 0 "instructions 80 <"
  if grep -q 'https://gw.test/v1/messages/count_tokens' "${root}/count_url_from_plugin/fake/curl.log"; then
    echo "ok:   count_url_from_plugin url"
  else
    echo "FAIL: count_url_from_plugin: url not used" >&2
    failures=$((failures + 1))
  fi

  fixture context_service_down_warns "alpha beta" "one"
  good_inventory | inventory context_service_down_warns
  expect context_service_down_warns 0 "WARN: context: OpenCode service unavailable"

  fixture context_missing_line_fails "alpha beta" "one"
  good_inventory | sed '/^Context:/d' | inventory context_missing_line_fails
  expect context_missing_line_fails 1 "Context"

  fixture context_missing_instructions_file_warns "alpha beta" "one"
  good_inventory | inventory context_missing_instructions_file_warns
  echo '{"instructions": ["~/nope.md"]}' >"${root}/context_missing_instructions_file_warns/cfg/opencode.json"
  expect context_missing_instructions_file_warns 0 "WARN: .*nope.md"
  expect context_missing_instructions_file_warns 0 "WARN: .*cfg/AGENTS.md"

  ctx_case context_nonfinite_tokens_skipped 400 "${small_skills}" claude-x 1e999
  expect context_nonfinite_tokens_skipped 0 "ok:   context: instructions"
  expect context_nonfinite_tokens_skipped 0 "WARN: context: no Claude sessions"

  ctx_case context_bad_session_shape_warns 400 "${small_skills}" claude-x 20000
  printf '{"data":{"error":"x"}}' >"${root}/context_bad_session_shape_warns/fake/sessions.json"
  expect context_bad_session_shape_warns 0 "ok:   context: instructions"
  expect context_bad_session_shape_warns 0 "WARN: context: OpenCode service unavailable; total"

  # record_case NAME PAGE_BODY [INSTR_CHARS]: a passing context case plus a page.
  record_case() {
    ctx_case "${1}" "${3:-400}" "${small_skills}" claude-x 20000 20000 20000
    mkdir -p "${root}/${1}/wiki/concepts"
    printf '%s\n' "${2}" >"${root}/${1}/wiki/concepts/starting-context.md"
  }
  RUN_ARG=--record
  record_case record_writes_table $'# P\n<!-- context:begin -->\n<!-- context:end -->\nafter'
  expect record_writes_table 0 "recorded"
  if grep -q "Recorded: 2026-11-20" "${root}/record_writes_table/wiki/concepts/starting-context.md" &&
    grep -q "^| Instructions | 125 |.*estimate, chars / 3.2 |" "${root}/record_writes_table/wiki/concepts/starting-context.md" &&
    grep -q "^Per project: proj 20000 (3)" "${root}/record_writes_table/wiki/concepts/starting-context.md" &&
    grep -q "^after" "${root}/record_writes_table/wiki/concepts/starting-context.md"; then
    echo "ok:   record_writes_table page"
  else
    echo "FAIL: record_writes_table page" >&2
    failures=$((failures + 1))
  fi

  record_case record_exact_table $'# P\n<!-- context:begin -->\n<!-- context:end -->\nafter'
  fake_gateway record_exact_table
  gw_expect record_exact_table 0 "recorded"
  if grep -q "^| Instructions | 80 |.*count_tokens |" "${root}/record_exact_table/wiki/concepts/starting-context.md" &&
    [ -s "${root}/record_exact_table/wiki/concepts/starting-context.md" ] &&
    ! grep -rq SECRETKEY123 "${root}/record_exact_table/wiki" "${root}/record_exact_table.log"; then
    echo "ok:   record_exact_table page"
  else
    echo "FAIL: record_exact_table page" >&2
    failures=$((failures + 1))
  fi

  d=$(printf '%*s' 100 '' | tr ' ' d)
  l1="<skill><id>using-superpowers</id><name>using-superpowers</name><description>${d}</description></skill>"
  l2="<skill><id>two</id><name>two</name><description>d</description></skill>"
  ctx_case count_parts_exact 400 '[{"id":"using-superpowers","description":"'"${d}"'","path":"'"${root}"'/count_parts_exact/boot.md"},{"id":"two","description":"d"}]' claude-x 20000
  printf '%*s' 1000 '' | tr ' ' x >"${root}/count_parts_exact/boot.md"
  mkdir -p "${root}/count_parts_exact/wiki/concepts"
  printf '<!-- context:begin -->\n<!-- context:end -->\n' >"${root}/count_parts_exact/wiki/concepts/starting-context.md"
  fake_gateway count_parts_exact
  gw_expect count_parts_exact 0 "recorded"
  page="${root}/count_parts_exact/wiki/concepts/starting-context.md"
  if grep -q "^| Instructions | 80 |" "${page}" &&
    grep -q "^| Skill list | $(((${#l1} + 1 + ${#l2}) / 5)) |" "${page}" &&
    grep -q "^| Agent descriptions | 2 |" "${page}" &&
    grep -q "^| Superpowers bootstrap | 200 |" "${page}"; then
    echo "ok:   count_parts_exact page"
  else
    echo "FAIL: count_parts_exact page" >&2
    sed 's/^/      /' "${page}" >&2
    failures=$((failures + 1))
  fi

  record_case record_late_failure_all_estimate $'# P\n<!-- context:begin -->\n<!-- context:end -->\nafter'
  fake_gateway record_late_failure_all_estimate late
  gw_expect record_late_failure_all_estimate 0 "recorded"
  page="${root}/record_late_failure_all_estimate/wiki/concepts/starting-context.md"
  if grep -q "^| Instructions | 125 |.*estimate, chars / 3.2 |" "${page}" && ! grep -q count_tokens "${page}"; then
    echo "ok:   record_late_failure_all_estimate page"
  else
    echo "FAIL: record_late_failure_all_estimate page" >&2
    failures=$((failures + 1))
  fi

  same_day=$'# P\n<!-- context:begin -->\nRecorded: 2026-11-20\n<!-- context:end -->'
  record_case record_same_day_noop "${same_day}"
  cp "${root}/record_same_day_noop/wiki/concepts/starting-context.md" "${root}/same.before"
  expect record_same_day_noop 0 "already recorded today"
  if cmp -s "${root}/same.before" "${root}/record_same_day_noop/wiki/concepts/starting-context.md"; then
    echo "ok:   record_same_day_noop bytes"
  else
    echo "FAIL: record_same_day_noop bytes changed" >&2
    failures=$((failures + 1))
  fi

  record_case record_missing_markers_fails "# no markers"
  expect record_missing_markers_fails 1 "context:begin"

  record_case record_check_fails_no_write $'<!-- context:begin -->\n<!-- context:end -->' 8400
  cp "${root}/record_check_fails_no_write/wiki/concepts/starting-context.md" "${root}/fail.before"
  expect record_check_fails_no_write 1 "instructions .* >= 2000"
  if cmp -s "${root}/fail.before" "${root}/record_check_fails_no_write/wiki/concepts/starting-context.md"; then
    echo "ok:   record_check_fails_no_write bytes"
  else
    echo "FAIL: record_check_fails_no_write bytes changed" >&2
    failures=$((failures + 1))
  fi
  record_case record_next_day_bumps_updated $'---\ntitle: T\nupdated: 2026-11-19\n---\n# P\n<!-- context:begin -->\nRecorded: 2026-11-19\nold\n<!-- context:end -->\nafter'
  expect record_next_day_bumps_updated 0 "recorded"
  page="${root}/record_next_day_bumps_updated/wiki/concepts/starting-context.md"
  if grep -q "^updated: 2026-11-20$" "${page}" && grep -q "^Recorded: 2026-11-20" "${page}" &&
    ! grep -q "2026-11-19" "${page}" && grep -q "^title: T$" "${page}" && grep -q "^after$" "${page}"; then
    echo "ok:   record_next_day_bumps_updated page"
  else
    echo "FAIL: record_next_day_bumps_updated page" >&2
    failures=$((failures + 1))
  fi
  RUN_ARG=

  # git_wiki NAME: the case's wiki as a git repo with a bare remote; the page
  # is committed and pushed, other.txt stays uncommitted.
  git_wiki() {
    local w="${root}/${1}/wiki" r="${root}/${1}/remote.git"
    git init -q --bare -b main "${r}"
    git init -q -b main "${w}"
    git -C "${w}" config user.name t
    git -C "${w}" config user.email t@t
    git -C "${w}" config commit.gpgsign false
    git -C "${w}" add concepts/starting-context.md
    git -C "${w}" commit -q -m init
    git -C "${w}" remote add origin "${r}"
    git -C "${w}" push -q -u origin main
    echo x >"${w}/other.txt"
    echo staged >"${w}/staged.txt"
    git -C "${w}" add staged.txt
  }
  RUN_ARG=--daily
  record_case daily_runs_once $'# P\n<!-- context:begin -->\n<!-- context:end -->\nafter'
  expect daily_runs_once 0 ""
  if [ "$(head -n1 "${root}/daily_runs_once/state/last")" = "2026-11-20" ] &&
    grep -q "Recorded: 2026-11-20" "${root}/daily_runs_once/wiki/concepts/starting-context.md"; then
    echo "ok:   daily_runs_once first"
  else
    echo "FAIL: daily_runs_once first" >&2
    failures=$((failures + 1))
  fi
  rm -f "${root}/daily_runs_once/fake/calls.log"
  record_case daily_gateway_timeout_estimates $'# P\n<!-- context:begin -->\n<!-- context:end -->\nafter'
  fake_gateway daily_gateway_timeout_estimates timeout
  gw_expect daily_gateway_timeout_estimates 0 ""
  page="${root}/daily_gateway_timeout_estimates/wiki/concepts/starting-context.md"
  last="${root}/daily_gateway_timeout_estimates/state/last"
  if [ -s "${page}" ] && [ -s "${last}" ] &&
    grep -q "^| Instructions | 125 |.*estimate, chars / 3.2 |" "${page}" &&
    [ "$(grep -c 'WARN: context: gateway count unavailable' "${last}")" -eq 1 ] &&
    ! grep -q '^FAIL' "${last}" &&
    ! grep -q SECRETKEY123 "${page}" "${last}" "${root}/daily_gateway_timeout_estimates.log"; then
    echo "ok:   daily_gateway_timeout_estimates"
  else
    echo "FAIL: daily_gateway_timeout_estimates" >&2
    sed 's/^/      /' "${last}" >&2
    failures=$((failures + 1))
  fi
  expect daily_runs_once 0 ""
  if [ ! -e "${root}/daily_runs_once/fake/calls.log" ]; then
    echo "ok:   daily_runs_once second"
  else
    echo "FAIL: daily_runs_once second made opencode calls" >&2
    failures=$((failures + 1))
  fi

  record_case daily_commits_only_page $'# P\n<!-- context:begin -->\n<!-- context:end -->'
  git_wiki daily_commits_only_page
  for h in pre-commit pre-push prepare-commit-msg post-commit; do
    printf '#!/bin/sh\ntouch "%s/hook-ran"\nexit 1\n' "${root}" >"${root}/daily_commits_only_page/wiki/.git/hooks/${h}"
    chmod +x "${root}/daily_commits_only_page/wiki/.git/hooks/${h}"
  done
  expect daily_commits_only_page 0 ""
  r="${root}/daily_commits_only_page/remote.git"
  if [ "$(git --git-dir="${r}" rev-list --count main)" = 2 ] &&
    [ "$(git --git-dir="${r}" diff-tree --no-commit-id --name-only -r main)" = "concepts/starting-context.md" ] &&
    [ "$(git --git-dir="${r}" log -1 --format=%s main)" = "chore: context record 2026-11-20" ] &&
    git -C "${root}/daily_commits_only_page/wiki" status --porcelain | grep -q '^?? other.txt' &&
    [ "$(git -C "${root}/daily_commits_only_page/wiki" diff --cached --name-only)" = "staged.txt" ] &&
    [ "$(git -C "${root}/daily_commits_only_page/wiki" show :staged.txt)" = "staged" ] &&
    [ ! -e "${root}/hook-ran" ]; then
    echo "ok:   daily_commits_only_page remote"
  else
    echo "FAIL: daily_commits_only_page remote" >&2
    failures=$((failures + 1))
  fi

  record_case daily_push_failure_warns $'# P\n<!-- context:begin -->\n<!-- context:end -->'
  git_wiki daily_push_failure_warns
  rm -rf "${root}/daily_push_failure_warns/remote.git"
  expect daily_push_failure_warns 0 ""
  if grep -q "^WARN: wiki push failed" "${root}/daily_push_failure_warns/state/last"; then
    echo "ok:   daily_push_failure_warns last"
  else
    echo "FAIL: daily_push_failure_warns last" >&2
    failures=$((failures + 1))
  fi

  commits_in_remote() {
    git --git-dir="${root}/${1}/remote.git" rev-list --count main
  }
  record_case daily_unpushed_commit_not_published $'# P\n<!-- context:begin -->\n<!-- context:end -->'
  git_wiki daily_unpushed_commit_not_published
  w="${root}/daily_unpushed_commit_not_published/wiki"
  echo u >"${w}/unrelated.md"
  git -C "${w}" add unrelated.md
  git -C "${w}" commit -q -m unrelated -- unrelated.md
  expect daily_unpushed_commit_not_published 0 ""
  if [ "$(git --git-dir="${root}/daily_unpushed_commit_not_published/remote.git" rev-list --count main)" = 1 ] &&
    [ "$(git -C "${w}" log -1 --format=%s)" = "chore: context record 2026-11-20" ] &&
    [ "$(git -C "${w}" rev-list --count HEAD)" = 3 ] &&
    grep -q "^WARN: wiki has unpushed commits; daily record committed but not pushed" "${root}/daily_unpushed_commit_not_published/state/last"; then
    echo "ok:   daily_unpushed_commit_not_published"
  else
    echo "FAIL: daily_unpushed_commit_not_published" >&2
    failures=$((failures + 1))
  fi

  record_case daily_page_edited_during_run $'# P\n<!-- context:begin -->\n<!-- context:end -->'
  git_wiki daily_page_edited_during_run
  w="${root}/daily_page_edited_during_run/wiki"
  FAKE_TOUCH="${w}/concepts/starting-context.md" expect daily_page_edited_during_run 0 ""
  if [ "$(git -C "${w}" rev-list --count HEAD)" = 1 ] &&
    [ "$(commits_in_remote daily_page_edited_during_run)" = 1 ] &&
    grep -q "^edit during run" "${w}/concepts/starting-context.md" &&
    ! grep -q "^Recorded:" "${w}/concepts/starting-context.md" &&
    grep -q "^WARN: concepts/starting-context.md changed during the run; daily record skipped" "${root}/daily_page_edited_during_run/state/last"; then
    echo "ok:   daily_page_edited_during_run"
  else
    echo "FAIL: daily_page_edited_during_run" >&2
    failures=$((failures + 1))
  fi

  record_case daily_head_moved_during_run $'# P\n<!-- context:begin -->\n<!-- context:end -->'
  git_wiki daily_head_moved_during_run
  w="${root}/daily_head_moved_during_run/wiki"
  FAKE_COMMIT="${w}" expect daily_head_moved_during_run 0 ""
  if [ "$(commits_in_remote daily_head_moved_during_run)" = 1 ] &&
    [ "$(git -C "${w}" rev-list --count HEAD)" = 2 ] &&
    [ "$(git -C "${w}" log -1 --format=%s)" = "unrelated during run" ] &&
    grep -q "^Recorded:" "${w}/concepts/starting-context.md" &&
    grep -q "^WARN: wiki HEAD moved during the run; daily record not committed" "${root}/daily_head_moved_during_run/state/last"; then
    echo "ok:   daily_head_moved_during_run"
  else
    echo "FAIL: daily_head_moved_during_run" >&2
    failures=$((failures + 1))
  fi

  record_case daily_failed_check_writes_last $'<!-- context:begin -->\n<!-- context:end -->' 8400
  expect daily_failed_check_writes_last 0 ""
  if [ "$(head -n1 "${root}/daily_failed_check_writes_last/state/last")" = "2026-11-20" ] &&
    grep -q "^FAIL: context: instructions" "${root}/daily_failed_check_writes_last/state/last"; then
    echo "ok:   daily_failed_check_writes_last last"
  else
    echo "FAIL: daily_failed_check_writes_last last" >&2
    failures=$((failures + 1))
  fi

  # dirty_case NAME INSTR_CHARS: a git wiki whose page has an uncommitted edit.
  dirty_case() {
    record_case "${1}" $'# P\n<!-- context:begin -->\n<!-- context:end -->' "${2}"
    git_wiki "${1}"
    echo "my edit" >>"${root}/${1}/wiki/concepts/starting-context.md"
  }
  dirty_case daily_dirty_page_failing_check 8400
  expect daily_dirty_page_failing_check 0 ""
  dirty_case daily_dirty_page_passing_check 400
  expect daily_dirty_page_passing_check 0 ""
  for n in daily_dirty_page_failing_check daily_dirty_page_passing_check; do
    if [ "$(commits_in_remote "${n}")" = 1 ] && [ "$(git -C "${root}/${n}/wiki" log --oneline | wc -l)" -eq 1 ] &&
      grep -q "^WARN: concepts/starting-context.md has uncommitted edits; daily record skipped" "${root}/${n}/state/last" &&
      grep -q "^my edit" "${root}/${n}/wiki/concepts/starting-context.md" &&
      ! grep -q "^Recorded:" "${root}/${n}/wiki/concepts/starting-context.md"; then
      echo "ok:   ${n} no commit"
    else
      echo "FAIL: ${n} no commit" >&2
      failures=$((failures + 1))
    fi
  done

  record_case daily_already_recorded_no_commit $'# P\n<!-- context:begin -->\nRecorded: 2026-11-20\n<!-- context:end -->'
  git_wiki daily_already_recorded_no_commit
  expect daily_already_recorded_no_commit 0 ""
  if [ "$(commits_in_remote daily_already_recorded_no_commit)" = 1 ] &&
    [ "$(git -C "${root}/daily_already_recorded_no_commit/wiki" log --oneline | wc -l)" -eq 1 ]; then
    echo "ok:   daily_already_recorded_no_commit"
  else
    echo "FAIL: daily_already_recorded_no_commit committed" >&2
    failures=$((failures + 1))
  fi

  # hold_lock NAME: a background python holding the case's lock; sets HOLDER.
  hold_lock() {
    local d="${root}/${1}/state" _
    mkdir -p "${d}"
    python3 -c 'import fcntl, sys, time
f = open(sys.argv[1], "w")
fcntl.flock(f, fcntl.LOCK_EX)
open(sys.argv[2], "w").close()
time.sleep(10)' "${d}/lock" "${d}/ready" &
    HOLDER=$!
    for _ in $(seq 50); do
      if [ -e "${d}/ready" ]; then return 0; fi
      sleep 0.1
    done
    echo "FAIL: ${1}: lock holder did not start" >&2
    failures=$((failures + 1))
    kill "${HOLDER}" 2>/dev/null
    return 1
  }
  record_case daily_lock_held_skips $'# P\n<!-- context:begin -->\n<!-- context:end -->'
  if hold_lock daily_lock_held_skips; then
    expect daily_lock_held_skips 0 ""
    kill "${HOLDER}" 2>/dev/null
    if [ ! -e "${root}/daily_lock_held_skips/fake/calls.log" ] && [ ! -e "${root}/daily_lock_held_skips/state/last" ]; then
      echo "ok:   daily_lock_held_skips no record"
    else
      echo "FAIL: daily_lock_held_skips recorded despite lock" >&2
      failures=$((failures + 1))
    fi
  fi

  record_case daily_lock_released_after_holder_dies $'# P\n<!-- context:begin -->\n<!-- context:end -->'
  if hold_lock daily_lock_released_after_holder_dies; then
    kill "${HOLDER}"
    wait "${HOLDER}" 2>/dev/null
    expect daily_lock_released_after_holder_dies 0 ""
    if [ "$(head -n1 "${root}/daily_lock_released_after_holder_dies/state/last")" = "2026-11-20" ]; then
      echo "ok:   daily_lock_released_after_holder_dies"
    else
      echo "FAIL: daily_lock_released_after_holder_dies did not record" >&2
      failures=$((failures + 1))
    fi
  fi

  # Lock taken, but another run finished the day in between: no record.
  record_case daily_last_rechecked_after_lock $'# P\n<!-- context:begin -->\n<!-- context:end -->'
  mkdir -p "${root}/daily_last_rechecked_after_lock/state"
  echo 2026-11-20 >"${root}/daily_last_rechecked_after_lock/state/last"
  (
    # shellcheck disable=SC2030 # subshell-local on purpose
    export PATH="${root}/daily_last_rechecked_after_lock/fake/bin:${PATH}" \
      AI_WIKI_DIR="${root}/daily_last_rechecked_after_lock/wiki" \
      OPENCODE_CONFIG_DIR_CHECK="${root}/daily_last_rechecked_after_lock/cfg" \
      AI_INVENTORY_PLUGINS=superpowers
    daily_record "${root}/daily_last_rechecked_after_lock/state" 2026-11-20 "${AI_WIKI_DIR}"
  ) >/dev/null 2>&1
  if [ ! -e "${root}/daily_last_rechecked_after_lock/fake/calls.log" ]; then
    echo "ok:   daily_last_rechecked_after_lock"
  else
    echo "FAIL: daily_last_rechecked_after_lock recorded" >&2
    failures=$((failures + 1))
  fi

  record_case daily_legacy_lock_dir_recorded $'# P\n<!-- context:begin -->\n<!-- context:end -->'
  mkdir -p "${root}/daily_legacy_lock_dir_recorded/state/lock"
  expect daily_legacy_lock_dir_recorded 0 ""
  if [ "$(head -n1 "${root}/daily_legacy_lock_dir_recorded/state/last")" = "2026-11-20" ] &&
    [ -f "${root}/daily_legacy_lock_dir_recorded/state/lock" ]; then
    echo "ok:   daily_legacy_lock_dir_recorded"
  else
    echo "FAIL: daily_legacy_lock_dir_recorded" >&2
    failures=$((failures + 1))
  fi

  record_case daily_legacy_lock_dir_not_empty_fails $'# P\n<!-- context:begin -->\n<!-- context:end -->'
  mkdir -p "${root}/daily_legacy_lock_dir_not_empty_fails/state/lock"
  touch "${root}/daily_legacy_lock_dir_not_empty_fails/state/lock/pid"
  expect daily_legacy_lock_dir_not_empty_fails 0 ""
  if grep -q "^FAIL: daily lock failed" "${root}/daily_legacy_lock_dir_not_empty_fails/state/last"; then
    echo "ok:   daily_legacy_lock_dir_not_empty_fails"
  else
    echo "FAIL: daily_legacy_lock_dir_not_empty_fails" >&2
    failures=$((failures + 1))
  fi

  record_case daily_lock_error_recorded $'# P\n<!-- context:begin -->\n<!-- context:end -->'
  printf '#!/bin/sh\ncase "$*" in *fcntl*) echo "boom" >&2; exit 1 ;; esac\nexec %s "$@"\n' "$(command -v python3)" >"${root}/daily_lock_error_recorded/fake/bin/python3"
  chmod +x "${root}/daily_lock_error_recorded/fake/bin/python3"
  expect daily_lock_error_recorded 0 ""
  if [ "$(head -n1 "${root}/daily_lock_error_recorded/state/last")" = "2026-11-20" ] &&
    grep -q "^FAIL: daily lock failed: boom" "${root}/daily_lock_error_recorded/state/last" &&
    [ ! -e "${root}/daily_lock_error_recorded/fake/calls.log" ]; then
    echo "ok:   daily_lock_error_recorded"
  else
    echo "FAIL: daily_lock_error_recorded" >&2
    failures=$((failures + 1))
  fi

  record_case daily_checker_crash_recorded $'# P\n<!-- context:begin -->\n<!-- context:end -->'
  # The lock still needs the real python3; only the checker's heredoc run crashes.
  printf '#!/bin/sh\ncase "$*" in *fcntl*) exec %s "$@" ;; esac\necho Traceback >&2\nexit 1\n' "$(command -v python3)" >"${root}/daily_checker_crash_recorded/fake/bin/python3"
  chmod +x "${root}/daily_checker_crash_recorded/fake/bin/python3"
  expect daily_checker_crash_recorded 0 ""
  if grep -q "^FAIL: ai-inventory check exited 1; run bash" "${root}/daily_checker_crash_recorded/state/last"; then
    echo "ok:   daily_checker_crash_recorded"
  else
    echo "FAIL: daily_checker_crash_recorded" >&2
    failures=$((failures + 1))
  fi

  RUN_ARG=--status
  mkdir -p "${root}/status_prints_problems/state"
  printf '2026-11-20\nWARN: something odd\n' >"${root}/status_prints_problems/state/last"
  expect status_prints_problems 0 "^ai-inventory (2026-11-20): WARN: something odd"

  mkdir -p "${root}/status_quiet_when_clean/state"
  printf '2026-11-20\n' >"${root}/status_quiet_when_clean/state/last"
  run status_quiet_when_clean
  if [ ! -s "${root}/status_quiet_when_clean.log" ]; then
    echo "ok:   status_quiet_when_clean"
  else
    echo "FAIL: status_quiet_when_clean printed output" >&2
    failures=$((failures + 1))
  fi
  if [ "$(id -u)" -eq 0 ]; then
    echo "skip: status_unwritable_state_warns (root)"
  else
    mkdir -p "${root}/status_unwritable_state_warns/state"
    chmod 555 "${root}/status_unwritable_state_warns/state"
    expect status_unwritable_state_warns 0 "is not writable; daily record cannot run"
    chmod 755 "${root}/status_unwritable_state_warns/state"
  fi
  if [ "$(id -u)" -eq 0 ]; then
    echo "skip: status_unwritable_parent_warns (root)"
  else
    mkdir -p "${root}/status_unwritable_parent_warns/ro"
    chmod 555 "${root}/status_unwritable_parent_warns/ro"
    # run() sets the state dir to <case>/state; point it below the read-only parent.
    got=0
    AI_WIKI_DIR="${root}/x" AI_STATE_DIR="${root}/status_unwritable_parent_warns/ro/sub/ai-inventory" \
      bash "${BASH_SOURCE[0]}" --status >"${root}/status_unwritable_parent_warns.log" 2>&1 || got=$?
    if [ "${got}" -eq 0 ] && grep -q "is not writable; daily record cannot run" "${root}/status_unwritable_parent_warns.log"; then
      echo "ok:   status_unwritable_parent_warns"
    else
      echo "FAIL: status_unwritable_parent_warns" >&2
      failures=$((failures + 1))
    fi
    chmod 755 "${root}/status_unwritable_parent_warns/ro"
  fi
  # wrapper_case NAME LINKED: source .aliases from a fake HOME and call opencode.
  wrapper_case() {
    local n="${1}" h="${root}/${1}" i
    mkdir -p "${h}/repo/test" "${h}/repo/.config/zsh" "${h}/home/.config/zsh" "${h}/bin"
    cp "$(dirname "${BASH_SOURCE[0]}")/../.config/zsh/.aliases" "${h}/repo/.config/zsh/.aliases"
    printf '#!/bin/sh\necho "$*" >>"%s/inv.log"\n' "${h}" >"${h}/repo/test/ai-inventory.sh"
    printf '#!/bin/sh\necho "$*" >>"%s/oc.log"\nexit 7\n' "${h}" >"${h}/bin/opencode"
    chmod +x "${h}/repo/test/ai-inventory.sh" "${h}/bin/opencode"
    if [ "${2}" = linked ]; then
      ln -s "${h}/repo/.config/zsh/.aliases" "${h}/home/.config/zsh/.aliases"
    else
      cp "${h}/repo/.config/zsh/.aliases" "${h}/home/.config/zsh/.aliases"
    fi
    got=0
    # shellcheck disable=SC2031 # PATH set in a subshell above is not wanted here
    HOME="${h}/home" XDG_CONFIG_HOME="${h}/home/.config" PATH="${h}/bin:${PATH}" \
      bash -c '. "$1" >/dev/null 2>&1; opencode run "a b"' _ "${h}/home/.config/zsh/.aliases" >"${h}.log" 2>&1 || got=$?
    for i in 1 2 3 4 5 6 7 8 9 10; do
      grep -qs -- "--daily" "${h}/inv.log" && break
      sleep 0.2
    done
  }
  wrapper_case wrapper_linked linked
  if [ "${got}" -eq 7 ] && grep -qx -- "--status" "${root}/wrapper_linked/inv.log" &&
    grep -qx -- "--daily" "${root}/wrapper_linked/inv.log" &&
    [ "$(cat "${root}/wrapper_linked/oc.log")" = "run a b" ]; then
    echo "ok:   wrapper_linked"
  else
    echo "FAIL: wrapper_linked (exit ${got})" >&2
    failures=$((failures + 1))
  fi
  wrapper_case wrapper_unlinked copy
  if [ "${got}" -eq 7 ] && [ ! -e "${root}/wrapper_unlinked/inv.log" ] &&
    [ "$(cat "${root}/wrapper_unlinked/oc.log")" = "run a b" ]; then
    echo "ok:   wrapper_unlinked"
  else
    echo "FAIL: wrapper_unlinked (exit ${got})" >&2
    failures=$((failures + 1))
  fi
  RUN_ARG=

  [ "${failures}" -eq 0 ]
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
elif [ "${1:-}" = "--daily" ]; then
  daily
elif [ "${1:-}" = "--status" ]; then
  status
else
  check "${1:-}"
fi
