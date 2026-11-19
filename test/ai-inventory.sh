#!/usr/bin/env bash
# Checks the installed OpenCode agents and skills against the inventory in
# the private notes wiki (see `./install --wiki`): every installed item needs
# a row, every row an installed item, and counts stay under the limits the
# inventory states. Without the wiki it warns and passes.
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
        if (m := re.search(r"/node_modules/([^/]+)/skills/", s.get("path", "")))}
print(",".join(sorted(pkgs)))' 2>/dev/null)" || {
      printf "FAIL: could not list skills from the OpenCode service; start opencode, or set\n" >&2
      printf "      AI_INVENTORY_PLUGINS to the comma-separated plugin names (e.g. superpowers)\n" >&2
      return 1
    }
  fi

  INVENTORY="${wiki}/inventory.md" CFG="${cfg}" PLUGINS="${plugins}" python3 - <<'EOF'
import os, re, sys
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
    "Skills": {p.name for p in (cfg / "skills").iterdir() if p.is_dir()}
              if (cfg / "skills").is_dir() else set(),
    "Plugins": {p for p in os.environ["PLUGINS"].split(",") if p},
}

listed, section = {k: set() for k in installed}, None
for line in text.splitlines():
    if line.startswith("## "):
        section = line[3:].strip()
    elif section in listed and (m := re.match(r"\|\s*`([^`]+)`", line)):
        listed[section].add(m.group(1))

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
  good_inventory() {
    cat <<'EOF'
Limits: agents < 3, skills < 3

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

  [ "${failures}" -eq 0 ]
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
else
  check
fi
