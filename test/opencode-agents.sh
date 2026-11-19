#!/usr/bin/env bash
# Checks the global OpenCode subagents through the running OpenCode service:
# IDs, modes, models and the permission rules that keep each one in its lane.
# Run after changing .config/opencode/agents/.

set -o nounset

if ! command -v opencode >/dev/null 2>&1; then
  printf "FAIL: opencode not on PATH\n" >&2
  exit 1
fi

# Reload so a freshly created or re-linked agents/ folder is picked up; the
# reload finishes asynchronously, so give it a moment before reading.
if opencode api post /api/location/reload >/dev/null 2>&1; then
  sleep 3
else
  printf "WARN: opencode location reload failed; agents may be stale\n" >&2
fi
agents_json="$(opencode api get /api/agent 2>&1)" || {
  printf "FAIL: opencode api get /api/agent: %s\n" "${agents_json}" >&2
  exit 1
}
config_json="$(opencode api get /api/config 2>&1)" || {
  printf "FAIL: opencode api get /api/config: %s\n" "${config_json}" >&2
  exit 1
}

AGENTS_JSON="${agents_json}" CONFIG_JSON="${config_json}" python3 - <<'EOF'
import json, os, sys
from fnmatch import fnmatchcase

agents = {a["id"]: a for a in json.loads(os.environ["AGENTS_JSON"])["data"]}
cfg = next((e["info"] for e in json.loads(os.environ["CONFIG_JSON"])
            if e.get("type") == "document" and e["path"].endswith("opencode.json")), {})
# Work config (opencode_work.json) carries the LLMi provider; personal does not.
WORK = "aumovio-llmi" in cfg.get("providers", {})
status = 0

def fail(msg):
    global status
    status = 1
    print(f"FAIL: {msg}", file=sys.stderr)

def ok(msg):
    print(f"ok:   {msg}")

CHEAP = ["build-runner", "scribe", "jira", "confluence"]
INHERIT = ["release-mapper"]
CHEAP_MODEL = {"providerID": "opencode-go", "id": "deepseek-v4.1-flash"}
# Models are pinned per config: Copilot at work, the free model at home.
# At work the reviewer runs on a different model family than the Opus author.
FREE = {"providerID": "opencode", "id": "big-pickle"}
SONNET = {"providerID": "github-copilot", "id": "claude-sonnet-5.5"} if WORK else FREE
SOL = {"providerID": "github-copilot", "id": "gpt-6.1-sol"} if WORK else FREE
PINNED = {"cpp-reviewer": SOL, "reviewer": SOL,
          "investigator": SONNET}

def match(value, pattern):
    """OpenCode whole-value wildcard match. A shell pattern ending in ' *'
    also matches the bare command (docs: 'git status *' matches 'git status')."""
    if fnmatchcase(value, pattern):
        return True
    return pattern.endswith(" *") and value == pattern[:-2]

def effect(agent, action, resource):
    """Last rule matching (action, resource) wins, as OpenCode evaluates.
    Approximation of OpenCode's matcher; confirm surprising results with a
    real run of the agent."""
    result = None
    for r in agent.get("permissions", []):
        if match(action, r["action"]) and match(resource, r["resource"]):
            result = r["effect"]
    return result

def expect(aid, cmd, want):
    a = agents.get(aid)
    if not a:
        return
    got = effect(a, "shell", cmd)
    if (got == "allow") != (want == "allow"):
        fail(f"{aid}: shell '{cmd}' is {got}, want {want}")

# Authors (coder primary, built-in general) run on Sonnet; Opus stays on build.
for aid, mode in [("coder", "primary"), ("general", "subagent")]:
    a = agents.get(aid)
    if a is None:
        fail(f"{aid}: missing")
        continue
    model = a.get("model") or {}
    if a.get("mode") != mode:
        fail(f"{aid}: mode is {a.get('mode')!r}, want {mode!r}")
    elif {k: model.get(k) for k in SONNET} != SONNET:
        fail(f"{aid}: model {a.get('model')!r}, want {SONNET}")
    elif aid == "coder" and effect(a, "edit", "src/main.cpp") != "allow":
        fail("coder: edit is not allowed")
    else:
        ok(f"{aid}: {mode} on {SONNET['id']}")

if "commit" in agents:
    fail("V1 agent 'commit' is still loaded")
else:
    ok("no V1 'commit' agent")

for aid in INHERIT + CHEAP + list(PINNED):
    a = agents.get(aid)
    if a is None:
        fail(f"{aid}: missing")
        continue
    if a.get("mode") != "subagent":
        fail(f"{aid}: mode is {a.get('mode')!r}, want 'subagent'")
    model = a.get("model")
    if aid in PINNED:
        want = PINNED[aid]
        if not model or {k: model.get(k) for k in want} != want:
            fail(f"{aid}: model {model!r}, want {want}")
    elif aid in CHEAP:
        if not model or {k: model.get(k) for k in CHEAP_MODEL} != CHEAP_MODEL:
            fail(f"{aid}: model {model!r}, want {CHEAP_MODEL}")
    elif model:
        fail(f"{aid}: model {model!r}, want none (inherit)")
    if effect(a, "edit", "src/main.cpp") != "deny":
        fail(f"{aid}: edit is not denied")
    else:
        ok(f"{aid}: loaded, model and edit-deny correct")

for aid in ["investigator", "release-mapper"]:
    a = agents.get(aid)
    if a and effect(a, "external_directory", "/home/u/gitprojects/x/*") != "allow":
        fail(f"{aid}: external_directory not allowed")

scribe = agents.get("scribe")
if scribe:
    for cmd in ["git reset --hard", "git clean -fdx", "git checkout -- .",
                "git restore .", "git rebase -i main", "git stash drop"]:
        if effect(scribe, "shell", cmd) == "allow":
            fail(f"scribe: '{cmd}' is allowed")
    for cmd in ["git commit -m x", "git diff --cached"]:
        if effect(scribe, "shell", cmd) != "allow":
            fail(f"scribe: '{cmd}' is not allowed")
    if effect(scribe, "shell", "git push origin main") != "ask":
        fail("scribe: git push does not ask")

# Read-only agents: allowed tools must not be able to run commands or write.
for aid in ["cpp-reviewer", "reviewer", "investigator", "release-mapper"]:
    expect(aid, "git status", "allow" if aid in ("cpp-reviewer", "reviewer") else "not allow")
    expect(aid, "git diff --output=src/x.cpp", "not allow")
    expect(aid, "git log -p --output=/tmp/x", "not allow")
for aid in ["reviewer", "investigator", "release-mapper"]:
    expect(aid, "rg -n foo src", "allow")
    expect(aid, "fd -e cpp", "allow")
    expect(aid, "fd . -x rm {}", "not allow")
    expect(aid, "fd -X rm", "not allow")
    expect(aid, "fd . --exec rm {}", "not allow")
    expect(aid, "rg --pre ./evil foo", "not allow")
expect("release-mapper", "tar -tf sdk.tar.gz", "allow")
expect("release-mapper", "tar -xzf sdk.tar.gz -C /tmp/opencode/sdk-0.3.0", "allow")
expect("release-mapper", "tar -xf sdk.tar -C src", "not allow")
expect("release-mapper", "tar -xf sdk.tar", "not allow")
expect("release-mapper", "unzip -l sdk.zip", "allow")
expect("release-mapper", "unzip -o sdk.zip -d /tmp/opencode/sdk", "allow")
expect("release-mapper", "unzip -o sdk.zip", "not allow")

# scribe: no branch deletion or history rewrite without asking.
expect("scribe", "git status", "allow")
expect("scribe", "git branch --show-current", "allow")
expect("scribe", "git branch -D feature", "not allow")
expect("scribe", "git branch -d feature", "not allow")
expect("scribe", "git commit --amend --no-edit", "not allow")
expect("scribe", "git commit -m x --amend", "not allow")

# build-runner: builds run freely, destructive git asks.
expect("build-runner", "./build.sh.pi", "allow")
expect("build-runner", "cmake --build build/debug -j8", "allow")
for cmd in ["git reset --hard", "git clean -fdx", "git checkout -- .",
            "git restore .", "git stash drop", "git push origin main"]:
    expect("build-runner", cmd, "not allow")

for aid, own, other in [("jira", "jira", "confluence"), ("confluence", "confluence", "jira")]:
    a = agents.get(aid)
    if not a:
        continue
    for server in ["mcp-atlassian", "mcp_atlassian"]:
        if effect(a, f"{server}_{own}_search", "*") != "allow":
            fail(f"{aid}: {server}_{own}_* not allowed")
        if effect(a, f"{server}_{other}_search", "*") == "allow":
            fail(f"{aid}: {server}_{other}_* allowed")

# Work secrets: the unattended store is off limits to agents, and no key is
# substituted into the config (the API returns substituted values).
def policy(resource):
    result = None
    for p in cfg.get("policies", []):
        if p["action"] == "tool.use" and match(resource, p["resource"]):
            result = p["effect"]
    return result

if WORK:
    for res in ["shell:gopass show -o work-unattended/jira-pat",
                "shell:gopass show -c work-unattended/llmi-api-token",
                "read:/home/u/.local/share/gopass/stores/work-unattended/jira-pat.gpg"]:
        if policy(res) != "deny":
            fail(f"policy does not deny {res}")
    llmi = cfg.get("providers", {}).get("aumovio-llmi", {})
    if "apiKey" in llmi.get("settings", {}) or "Authorization" in llmi.get("headers", {}):
        fail("aumovio-llmi still carries a key in config")
    cmd = cfg.get("mcp", {}).get("servers", {}).get("mcp-atlassian", {}).get("command", [])
    if cmd[:2] != ["uvx", "mcp-atlassian==0.24.6"] or "--env-file" not in cmd:
        fail(f"mcp-atlassian command is {cmd}")

sys.exit(status)
EOF
