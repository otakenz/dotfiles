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
opencode api post /api/location/reload >/dev/null 2>&1 && sleep 3
agents_json="$(opencode api get /api/agent 2>&1)" || {
  printf "FAIL: opencode api get /api/agent: %s\n" "${agents_json}" >&2
  exit 1
}

AGENTS_JSON="${agents_json}" python3 - <<'EOF'
import json, os, sys
from fnmatch import fnmatchcase

agents = {a["id"]: a for a in json.loads(os.environ["AGENTS_JSON"])["data"]}
status = 0

def fail(msg):
    global status
    status = 1
    print(f"FAIL: {msg}", file=sys.stderr)

def ok(msg):
    print(f"ok:   {msg}")

CHEAP = ["build-runner", "scribe", "jira", "confluence"]
INHERIT = ["cpp-reviewer", "investigator", "release-mapper"]
CHEAP_MODEL = {"providerID": "opencode-go", "id": "deepseek-v4.1-flash"}

def effect(agent, action, resource):
    """Last rule matching (action, resource) wins, as OpenCode evaluates."""
    result = None
    for r in agent.get("permissions", []):
        if fnmatchcase(action, r["action"]) and fnmatchcase(resource, r["resource"]):
            result = r["effect"]
    return result

if "commit" in agents:
    fail("V1 agent 'commit' is still loaded")
else:
    ok("no V1 'commit' agent")

for aid in INHERIT + CHEAP:
    a = agents.get(aid)
    if a is None:
        fail(f"{aid}: missing")
        continue
    if a.get("mode") != "subagent":
        fail(f"{aid}: mode is {a.get('mode')!r}, want 'subagent'")
    model = a.get("model")
    if aid in CHEAP:
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

for aid, own, other in [("jira", "jira", "confluence"), ("confluence", "confluence", "jira")]:
    a = agents.get(aid)
    if not a:
        continue
    for server in ["mcp-atlassian", "mcp_atlassian"]:
        if effect(a, f"{server}_{own}_search", "*") != "allow":
            fail(f"{aid}: {server}_{own}_* not allowed")
        if effect(a, f"{server}_{other}_search", "*") == "allow":
            fail(f"{aid}: {server}_{other}_* allowed")

sys.exit(status)
EOF
