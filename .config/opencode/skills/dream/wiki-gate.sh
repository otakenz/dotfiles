#!/usr/bin/env bash
# usage: wiki-gate.sh "<commit message>" <file>...   (paths relative to the wiki repo)
# Stages only the given files, scans their staged diff for secrets, and commits
# (path-limited) and pushes only on an explicit clean result. Fails closed;
# never prints diff text.
set -u
W="${WIKI_DIR:-${HOME}/wiki/ai-workflow}"
msg="$1"
shift
files=("$@")
PAT='-----BEGIN [A-Z ]*KEY|gh[pousr]_[A-Za-z0-9]{10,}|github_pat_|sk-[A-Za-z0-9_-]{10,}|xox[bp]-|AKIA[A-Z0-9]{12,}|(password|passwd|token|secret|api[_-]?key)[A-Za-z0-9_]*["'"'"']?[[:space:]]*[=:]'
tmp="$(mktemp)" || exit 1
trap 'rm -f "${tmp}"' EXIT

fail() {
  local why="$1"
  if git -C "${W}" reset -q -- "${files[@]}"; then
    echo "wiki-gate: ${why}; unstaged, nothing committed" >&2
  else
    echo "wiki-gate: ${why}; could not unstage, check 'git status' in the wiki" >&2
  fi
  exit 1
}

git -C "${W}" add -- "${files[@]}" || fail "git add failed"
for f in "${files[@]}"; do
  git -C "${W}" diff --cached --text -- "${f}" >"${tmp}" || fail "diff failed for ${f}"
  n="$(grep -aciE -e "${PAT}" "${tmp}")"
  rc=$?
  { [ "${rc}" -le 1 ] && [ "${n}" = 0 ]; } || fail "possible secret or scan error in ${f}"
done
git -C "${W}" commit -q -m "${msg}" -- "${files[@]}" && git -C "${W}" push -q
