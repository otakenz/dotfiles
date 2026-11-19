#!/usr/bin/env bash
# Hermetic test for `./install --wiki`: a file:// wiki repo and a throwaway
# HOME. Touches nothing outside a temp dir.

set -o errexit
set -o nounset
set -o pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d /tmp/wiki.XXXXXX)"
trap 'rm -rf "${ROOT}"' EXIT

REMOTE="${ROOT}/remote.git"
SEED="${ROOT}/seed"
failures=0

gitc() { git -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false "${@}"; }

git init -q --bare -b main "${REMOTE}"
git init -q -b main "${SEED}"
echo "# wiki" >"${SEED}/index.md"
gitc -C "${SEED}" add index.md
gitc -C "${SEED}" commit -q -m init
git -C "${SEED}" push -q "${REMOTE}" main

# run_wiki NAME [ENV=VAL...] -- ARGS...: install --wiki in a fresh-ish HOME.
run_wiki() {
  local name="${1}" home="${ROOT}/${1}"
  shift
  local envs=()
  while [ "${1}" != "--" ]; do
    envs+=("${1}")
    shift
  done
  shift
  mkdir -p "${home}"
  env -i PATH="${PATH}" HOME="${home}" USER="${USER:-test}" LANG=C.UTF-8 \
    GIT_CONFIG_GLOBAL=/dev/null "${envs[@]}" \
    bash "${REPO}/install" "${@}" </dev/null >"${home}.log" 2>&1
}

pass() { echo "ok:   ${1}"; }
fail() {
  echo "FAIL: ${1}" >&2
  failures=$((failures + 1))
}

# clones_into_default_dir
if run_wiki a -- --wiki "file://${REMOTE}" && [ -f "${ROOT}/a/wiki/ai-workflow/index.md" ]; then
  pass "clones into ~/wiki/ai-workflow"
else
  fail "clones into ~/wiki/ai-workflow (see a.log)"
fi

# second_run_pulls_new_commit
echo "more" >"${SEED}/log.md"
gitc -C "${SEED}" add log.md
gitc -C "${SEED}" commit -q -m more
git -C "${SEED}" push -q "${REMOTE}" main
if run_wiki a -- --wiki="file://${REMOTE}" && [ -f "${ROOT}/a/wiki/ai-workflow/log.md" ]; then
  pass "second run pulls new commits"
else
  fail "second run pulls new commits (see a.log)"
fi

# honours_AI_WIKI_DIR
if run_wiki b "AI_WIKI_DIR=${ROOT}/b/notes" -- --wiki "file://${REMOTE}" &&
  [ -f "${ROOT}/b/notes/index.md" ]; then
  pass "honours AI_WIKI_DIR"
else
  fail "honours AI_WIKI_DIR (see b.log)"
fi

# no_url_non_interactive_errors
if run_wiki c -- --wiki; then
  fail "--wiki without URL and without a terminal should fail"
elif grep -q -- "--wiki URL" "${ROOT}/c.log"; then
  pass "no URL without a terminal fails with a hint"
else
  fail "no URL: error lacks the '--wiki URL' hint (see c.log)"
fi

# non_repo_dir_errors_untouched
mkdir -p "${ROOT}/d/wiki/ai-workflow"
echo keep >"${ROOT}/d/wiki/ai-workflow/mine.txt"
if run_wiki d -- --wiki "file://${REMOTE}"; then
  fail "existing non-repo folder should fail"
elif [ "$(cat "${ROOT}/d/wiki/ai-workflow/mine.txt")" = keep ] &&
  [ ! -e "${ROOT}/d/wiki/ai-workflow/index.md" ] &&
  grep -q "not a git repository" "${ROOT}/d.log"; then
  pass "existing non-repo folder fails and is left alone"
else
  fail "existing non-repo folder was modified (see d.log)"
fi

[ "${failures}" -eq 0 ]
