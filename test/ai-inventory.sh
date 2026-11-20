#!/usr/bin/env bash
# Checks the installed OpenCode agents and skills against the inventory in
# the private notes wiki (see `./install --wiki`): every installed item needs
# a row, every row an installed item, and counts stay under the limits the
# inventory states. Also checks that reviewers run on another model family
# than the authors (opencode.json, agent files), and the starting context
# budget (instructions, skills, agents, session total; chars // 4). Without the wiki it warns
# and passes.
#
#   test/ai-inventory.sh              check this machine
#   test/ai-inventory.sh --self-test  check the checker against fixtures
#
# Env: AI_WIKI_DIR (default ~/wiki/ai-workflow), OPENCODE_CONFIG_DIR_CHECK
# (default ~/.config/opencode), AI_INVENTORY_PLUGINS (comma list; default:
# asked from the running OpenCode service).

set -o nounset

check() {
  local wiki="${AI_WIKI_DIR:-${HOME}/wiki/ai-workflow}"
  local cfg="${OPENCODE_CONFIG_DIR_CHECK:-${HOME}/.config/opencode}"
  local plugins="${AI_INVENTORY_PLUGINS-}"

  if [ ! -f "${wiki}/inventory.md" ]; then
    if [ -d "${wiki}" ]; then
      printf "FAIL: %s/inventory.md is missing\n" "${wiki}" >&2
      return 1
    fi
    printf "WARN: no notes wiki at %s; inventory not checked (see ./install --wiki)\n" "${wiki}" >&2
    return 0
  fi

  if [ -z "${AI_INVENTORY_PLUGINS+set}" ]; then
    # Plugin skills live under .../node_modules/<package>/skills/<id>/SKILL.md.
    plugins="$(opencode api get "/api/skill?location[directory]=${HOME}" 2>/dev/null | python3 -c '
import json, re, sys
pkgs = {m.group(1) for s in json.load(sys.stdin)["data"]
        if (m := re.search(r"/node_modules/((?:@[^/]+/)?[^/]+)/skills/", s.get("path", "")))}
print(",".join(sorted(pkgs)))' 2>/dev/null)" || {
      printf "FAIL: could not list skills from the OpenCode service; start opencode, or set\n" >&2
      printf "      AI_INVENTORY_PLUGINS to the comma-separated plugin names (e.g. superpowers)\n" >&2
      return 1
    }
  fi

  INVENTORY="${wiki}/inventory.md" CFG="${cfg}" PLUGINS="${plugins}" python3 - <<'EOF'
import json, os, re, sys
from pathlib import Path

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

listed, section = {k: set() for k in installed}, None
for line in text.splitlines():
    if line.startswith("## "):
        section = line[3:].strip()
    elif section in listed and line.startswith("|"):
        # First cell is the id, with or without backticks; skip header and rule.
        first = line.strip().strip("|").split("|")[0].strip().strip("`")
        if first and first != "Id" and not set(first) <= set("-: "):
            listed[section].add(first)

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
            ("gemini", r"gemini"), ("deepseek", r"deepseek"), ("qwen", r"qwen"))
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
# Tokens are estimated as chars // 4.
import statistics, subprocess

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

def tok(s):
    return len(s) // 4

def hidden_skill(path):
    if not path or path.startswith("skill://") or not os.path.isfile(path):
        return False
    fm = re.match(r"---\n(.*?)\n---", Path(path).read_text(errors="replace"), re.S)
    return bool(fm and re.search(
        r"^\s*(opencode/autoinvoke:\s*false|disable-model-invocation:\s*true)\s*$",
        fm.group(1), re.M))

def measure():
    home = os.path.expanduser("~")
    out = dict(instructions=0, skills=None, agents=None, bootstrap=0, own=None,
               total=None, sessions=0, rest=None, missing=[])
    files = []
    conf = cfg / "opencode.json"
    if conf.is_file():
        try:
            files += [Path(os.path.expanduser(p)) for p in json.loads(conf.read_text()).get("instructions", [])]
        except ValueError:
            pass
    files.append(cfg / "AGENTS.md")
    for f in files:
        if f.is_file():
            out["instructions"] += tok(f.read_text(errors="replace"))
        else:
            out["missing"].append(str(f))
    skills = api("/api/skill?location[directory]=" + home)
    agents = api("/api/agent?location[directory]=" + home)
    def dicts(x):
        return [i for i in x if isinstance(i, dict)] if isinstance(x, list) else None
    def sval(d, k):
        v = d.get(k)
        return v if isinstance(v, str) else ""
    skills, agents = dicts(skills), dicts(agents)
    if skills is not None and agents is not None:
        out["skills"] = sum(
            len(sval(s, "id")) + len(sval(s, "description")) + 40
            for s in skills if not hidden_skill(sval(s, "path"))) // 4
        out["agents"] = sum(
            len(sval(a, "name") or sval(a, "id")) + len(sval(a, "description")) + 10
            for a in agents if a.get("mode") in ("subagent", "all") and not a.get("hidden")) // 4
        boot = next((sval(s, "path") for s in skills if s.get("id") == "using-superpowers"), "")
        if boot and os.path.isfile(boot):
            out["bootstrap"] = tok(Path(boot).read_text(errors="replace"))
        out["own"] = out["instructions"] + out["skills"] + out["agents"] + out["bootstrap"]
    sess = api("/api/session?limit=40")
    sess = dicts(sess)
    out["sessions_ok"] = sess is not None
    def num(d, k):
        v = d.get(k) if isinstance(d, dict) else None
        return v if isinstance(v, (int, float)) and not isinstance(v, bool) else 0
    vals = []
    roots = [s for s in sess or [] if isinstance(s.get("id"), str) and not s.get("parentID")]
    for s in sorted(roots, key=lambda s: num(s.get("time"), "created"), reverse=True):
        if len(vals) >= 5:
            break
        msgs = dicts(api(f"/api/session/{s['id']}/context"))
        if msgs is None:
            continue
        user = next((m for m in msgs if m.get("type") == "user"), {})
        asst = next((m for m in msgs if m.get("type") == "assistant"
                     and isinstance(m.get("tokens"), dict)), None)
        if len(sval(user, "text")) > 500 or not asst:
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
              f"target {budgets['target']})")

if status == 0:
    print(f"ok:   inventory matches ({len(installed['Plugins'])} plugin(s) listed, not limited)")
sys.exit(status)
EOF
}

self_test() {
  local root failures=0
  root="$(mktemp -d /tmp/ai-inventory.XXXXXX)"
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
    PATH="${fake}/bin:${PATH}" \
      AI_WIKI_DIR="${root}/${1}/wiki" OPENCODE_CONFIG_DIR_CHECK="${root}/${1}/cfg" \
      AI_INVENTORY_PLUGINS="superpowers" bash "${BASH_SOURCE[0]}" >"${root}/${1}.log" 2>&1
  }
  expect() { # NAME WANT_EXIT GREP
    local got=0
    run "${1}" || got=$?
    if [ "${got}" -eq "${2}" ] && grep -q -- "${3}" "${root}/${1}.log"; then
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
case "$3" in
*/api/skill*) cat "$d/skills.json" ;;
*/api/agent*) cat "$d/agents.json" ;;
*/api/session/*/context)
  id="${3#*/api/session/}"
  cat "$d/ctx-${id%/context}.json"
  ;;
*/api/session?*) cat "$d/sessions.json" ;;
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
  # sessions_json N: root sessions s1..sN, newest last id first.
  sessions_json() {
    local i out=""
    for i in $(seq 1 "${1}"); do out="${out:+${out},}{\"id\":\"s${i}\",\"time\":{\"created\":${i}}}"; done
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
  if [ "${got}" -eq 1 ] && grep -q "AI_INVENTORY_PLUGINS" "${root}/service_down_hints.log"; then
    echo "ok:   service_down_hints"
  else
    echo "FAIL: service_down_hints: exit ${got}, want 1 and a hint naming AI_INVENTORY_PLUGINS" >&2
    sed 's/^/      /' "${root}/service_down_hints.log" >&2
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

  fixture hidden_skill_dir_ignored "alpha beta" "one .git"
  good_inventory | inventory hidden_skill_dir_ignored
  expect hidden_skill_dir_ignored 0 "Skills: 1 installed"

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

  [ "${failures}" -eq 0 ]
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
else
  check
fi
