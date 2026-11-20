#!/usr/bin/env bash
# Tests .local/bin/opencode-cli-sync in a throwaway dotfiles repo and config
# dir.
#
#   bash test/opencode-cli-sync.sh

# shellcheck disable=SC2317,SC2329 # test functions are called by name from the loop
set -o nounset

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

failed=0
pass() { printf "PASS %s\n" "$1"; }
fail() {
  printf "FAIL %s: %s\n" "$1" "$2"
  failed=1
}

REPO="${TMP}/dotfiles"
REPO_FILE="${REPO}/.config/opencode/cli.json"
LIVE="${TMP}/config/opencode/cli.json"

setup() {
  rm -rf "${REPO}" "${TMP}/config"
  mkdir -p "${REPO}/.config/opencode" "${TMP}/config/opencode"
  git init -q -b main "${REPO}"
  printf '{ "theme": "a" }\n' >"${REPO_FILE}"
  git -C "${REPO}" add .
  git -C "${REPO}" -c commit.gpgsign=false commit -q -m base
  ln -s "${REPO_FILE}" "${LIVE}"
}

run_sync() {
  XDG_CONFIG_HOME="${TMP}/config" bash "${ROOT}/.local/bin/opencode-cli-sync" "${REPO}" 2>&1
}

replace_link() { # content: what OpenCode's settings save does (tmp + rename)
  printf '%s\n' "$1" >"${LIVE}.tmp"
  mv "${LIVE}.tmp" "${LIVE}"
}

t_link_untouched() {
  setup
  local out rc=0
  out="$(run_sync)" || rc=$?
  [[ "${rc}" -eq 0 && -z "${out}" && -L "${LIVE}" ]] || fail "$1" "rc=${rc} out=${out}"
}

t_identical_copy_relinked() {
  setup
  replace_link '{ "theme": "a" }'
  local out rc=0
  out="$(run_sync)" || rc=$?
  [[ "${rc}" -eq 0 && -z "${out}" && -L "${LIVE}" ]] || fail "$1" "rc=${rc} out=${out}"
  [ "$(readlink "${LIVE}")" = "${REPO_FILE}" ] || fail "$1" "link target $(readlink "${LIVE}")"
}

t_changed_copy_moves_into_repo() {
  setup
  replace_link '{ "theme": "b" }'
  local out rc=0
  out="$(run_sync)" || rc=$?
  [[ "${rc}" -eq 0 && "${out}" == *"diff .config/opencode/cli.json"* && -L "${LIVE}" ]] || fail "$1" "rc=${rc} out=${out}"
  grep -q '"b"' "${REPO_FILE}" || fail "$1" "repo file not updated"
}

t_dirty_repo_file_left_alone() {
  setup
  printf '{ "theme": "repo-edit" }\n' >"${REPO_FILE}"
  replace_link '{ "theme": "b" }'
  local out rc=0
  out="$(run_sync)" || rc=$?
  [[ "${rc}" -eq 0 && "${out}" == *"uncommitted"* && ! -L "${LIVE}" ]] || fail "$1" "rc=${rc} out=${out}"
  grep -q 'repo-edit' "${REPO_FILE}" || fail "$1" "repo edit lost"
  grep -q '"b"' "${LIVE}" || fail "$1" "live settings lost"
}

t_staged_repo_edit_left_alone() {
  setup
  printf '{ "theme": "staged" }\n' >"${REPO_FILE}"
  git -C "${REPO}" add .config/opencode/cli.json
  replace_link '{ "theme": "b" }'
  local out rc=0
  out="$(run_sync)" || rc=$?
  [[ "${out}" == *"uncommitted"* && ! -L "${LIVE}" ]] || fail "$1" "rc=${rc} out=${out}"
  grep -q 'staged' "${REPO_FILE}" || fail "$1" "staged edit overwritten"
}

t_failed_copy_keeps_live_file() {
  if [ "$(id -u)" -eq 0 ]; then
    printf "skipped (root ignores read-only dirs)\n"
    return 0
  fi
  setup
  replace_link '{ "theme": "b" }'
  chmod a-w "${REPO}/.config/opencode"
  local out rc=0
  out="$(run_sync)" || rc=$?
  chmod u+w "${REPO}/.config/opencode"
  [[ "${rc}" -ne 0 && ! -L "${LIVE}" ]] || fail "$1" "rc=${rc} out=${out}"
  grep -q '"b"' "${LIVE}" || fail "$1" "live settings lost"
}

t_missing_live_linked() {
  setup
  rm "${LIVE}"
  local out rc=0
  out="$(run_sync)" || rc=$?
  [[ "${rc}" -eq 0 && -L "${LIVE}" ]] || fail "$1" "rc=${rc} out=${out}"
}

for t in t_link_untouched t_identical_copy_relinked t_changed_copy_moves_into_repo \
  t_dirty_repo_file_left_alone t_staged_repo_edit_left_alone \
  t_failed_copy_keeps_live_file t_missing_live_linked; do
  "${t}" "${t}" >"${TMP}/out.txt" 2>&1
  if grep -q '^FAIL' "${TMP}/out.txt"; then
    cat "${TMP}/out.txt"
    failed=1
  else
    pass "${t}"
  fi
done

exit "${failed}"
