#!/usr/bin/env bash
# Tests test/public-leak.sh and .githooks/pre-push in throwaway git repos with
# a made-up pattern file. Fixtures use invented identifiers only.
#
#   bash test/public-leak-test.sh

# shellcheck disable=SC2317 # test functions are called by name from the loop
set -o nounset

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
ZERO=0000000000000000000000000000000000000000

printf '# test patterns\n\nACME-[0-9]+\nexample-corp\n' >"${TMP}/patterns.txt"
export PUBLIC_LEAK_PATTERNS="${TMP}/patterns.txt"

failed=0
pass() { printf "PASS %s\n" "$1"; }
fail() {
  printf "FAIL %s: %s\n" "$1" "$2"
  failed=1
}

new_repo() {
  rm -rf "${TMP}/repo"
  git init -q -b main "${TMP}/repo"
  cd "${TMP}/repo" || exit 1
  git config commit.gpgsign false
  printf 'clean\nold line ACME-1\n' >f.txt
  git add f.txt
  git commit -q -m "base"
}

commit_file() { # content message
  printf '%s\n' "$1" >>f.txt
  git add f.txt
  git commit -q -m "$2"
}

run_script() { bash "${ROOT}/test/public-leak.sh" "$@" 2>&1; }

t_added_line_blocks() {
  new_repo
  commit_file "uses example-corp host" "add host"
  local out rc=0
  out="$(run_script HEAD~1..HEAD)" || rc=$?
  [[ "${rc}" -eq 1 && "${out}" == *"f.txt:"*"example-corp"* && "${out}" == *"--no-verify"* ]] ||
    fail "$1" "rc=${rc} out=${out}"
}

t_preexisting_passes() {
  new_repo
  commit_file "harmless" "add harmless"
  local out rc=0
  out="$(run_script HEAD~1..HEAD)" || rc=$?
  [[ "${rc}" -eq 0 ]] || fail "$1" "rc=${rc} out=${out}"
}

t_message_blocks() {
  new_repo
  commit_file "harmless" "fix ACME-42 thing"
  local out rc=0
  out="$(run_script HEAD~1..HEAD)" || rc=$?
  [[ "${rc}" -eq 1 && "${out}" == *"message: fix ACME-42 thing"* ]] ||
    fail "$1" "rc=${rc} out=${out}"
}

t_deleted_line_passes() {
  new_repo
  printf 'clean\n' >f.txt
  git commit -q -am "drop old line"
  local out rc=0
  out="$(run_script HEAD~1..HEAD)" || rc=$?
  [[ "${rc}" -eq 0 ]] || fail "$1" "rc=${rc} out=${out}"
}

t_missing_patterns_warns() {
  new_repo
  commit_file "uses example-corp host" "add host"
  local out rc=0
  out="$(PUBLIC_LEAK_PATTERNS="${TMP}/none.txt" run_script HEAD~1..HEAD)" || rc=$?
  [[ "${rc}" -eq 0 && "${out}" == *"WARN"* ]] || fail "$1" "rc=${rc} out=${out}"
}

hook() { # stdin line from args
  printf '%s\n' "$1" | bash "${ROOT}/.githooks/pre-push" origin url 2>&1
}

t_hook_new_branch() {
  new_repo
  git update-ref refs/remotes/origin/main HEAD
  git checkout -q -b feat
  commit_file "uses example-corp host" "add host"
  local sha out rc=0
  sha="$(git rev-parse HEAD)"
  out="$(hook "refs/heads/feat ${sha} refs/heads/feat ${ZERO}")" || rc=$?
  [[ "${rc}" -ne 0 && "${out}" == *"example-corp"* ]] || fail "$1" "rc=${rc} out=${out}"
  # same branch, existing remote sha: range remote..local
  git checkout -q main
  git checkout -q -b feat2
  commit_file "fine" "fine"
  sha="$(git rev-parse HEAD)"
  rc=0
  out="$(hook "refs/heads/feat2 ${sha} refs/heads/feat2 $(git rev-parse HEAD~1)")" || rc=$?
  [[ "${rc}" -eq 0 ]] || fail "$1" "clean range blocked: rc=${rc} out=${out}"
}

t_hook_skips_deletion() {
  new_repo
  local rc=0 out
  out="$(hook "(delete) ${ZERO} refs/heads/gone $(git rev-parse HEAD)")" || rc=$?
  [[ "${rc}" -eq 0 ]] || fail "$1" "rc=${rc} out=${out}"
}

t_merge_result_blocks() {
  new_repo
  git checkout -q -b side
  printf 'side\n' >s.txt
  git add s.txt
  git commit -q -m "side"
  git checkout -q main
  commit_file "main work" "main work"
  git merge -q --no-commit --no-ff side >/dev/null
  printf 'uses example-corp in merge\n' >>f.txt
  git add f.txt
  git commit -q -m "merge side"
  local out rc=0
  out="$(run_script HEAD~1..HEAD)" || rc=$?
  [[ "${rc}" -eq 1 && "${out}" == *"example-corp in merge"* ]] || fail "$1" "rc=${rc} out=${out}"
}

t_binary_blocks() {
  new_repo
  printf 'example-corp\0tail\n' >bin.dat
  git add bin.dat
  git commit -q -m "nul file"
  local out rc=0
  out="$(run_script HEAD~1..HEAD)" || rc=$?
  [[ "${rc}" -eq 1 ]] || fail "$1" "NUL file: rc=${rc} out=${out}"
  new_repo
  printf '*.dat binary\n' >.gitattributes
  printf 'plain example-corp text\n' >x.dat
  git add .gitattributes x.dat
  git commit -q -m "attr binary"
  rc=0
  out="$(run_script HEAD~1..HEAD)" || rc=$?
  [[ "${rc}" -eq 1 ]] || fail "$1" "attr binary: rc=${rc} out=${out}"
}

t_anchored_pattern() {
  new_repo
  printf '^ACME-[0-9]+\n' >"${TMP}/anch.txt"
  commit_file "ACME-5 starts the line" "add"
  local out rc=0
  out="$(PUBLIC_LEAK_PATTERNS="${TMP}/anch.txt" run_script HEAD~1..HEAD)" || rc=$?
  [[ "${rc}" -eq 1 ]] || fail "$1" "rc=${rc} out=${out}"
}

t_filename_only_passes() {
  new_repo
  printf 'clean\n' >example-corp.txt
  git add example-corp.txt
  git commit -q -m "named file"
  local out rc=0
  out="$(run_script HEAD~1..HEAD)" || rc=$?
  [[ "${rc}" -eq 0 ]] || fail "$1" "rc=${rc} out=${out}"
}

t_plusplus_line_blocks() {
  new_repo
  commit_file "++ example-corp" "add"
  local out rc=0
  out="$(run_script HEAD~1..HEAD)" || rc=$?
  [[ "${rc}" -eq 1 ]] || fail "$1" "rc=${rc} out=${out}"
}

t_invalid_pattern_errors() {
  new_repo
  commit_file "fine" "fine"
  printf 'good\nbad(\n' >"${TMP}/bad.txt"
  local out rc=0
  out="$(PUBLIC_LEAK_PATTERNS="${TMP}/bad.txt" run_script HEAD~1..HEAD)" || rc=$?
  [[ "${rc}" -eq 2 && "${out}" == *"bad("* ]] || fail "$1" "rc=${rc} out=${out}"
}

t_hook_unknown_remote_blocks() {
  new_repo
  local out rc=0
  out="$(hook "refs/heads/main $(git rev-parse HEAD) refs/heads/main 1111111111111111111111111111111111111111")" || rc=$?
  [[ "${rc}" -ne 0 && "${out}" == *"git fetch first"* ]] || fail "$1" "rc=${rc} out=${out}"
}

t_hook_new_branch_two_tips() {
  new_repo
  git update-ref refs/remotes/origin/main HEAD
  git checkout -q -b oldwork
  commit_file "old ACME-9 work" "old work"
  git update-ref refs/remotes/origin/oldwork HEAD
  git checkout -q -b feat1
  commit_file "clean one" "one"
  git checkout -q main
  git checkout -q -b feat2
  printf 'other\n' >g.txt
  git add g.txt
  git commit -q -m "two"
  git checkout -q feat1
  git merge -q --no-edit feat2
  local out rc=0
  out="$(hook "refs/heads/feat1 $(git rev-parse HEAD) refs/heads/feat1 ${ZERO}")" || rc=$?
  [[ "${rc}" -eq 0 ]] || fail "$1" "rc=${rc} out=${out}"
}

t_delete_then_add_file() {
  new_repo
  printf 'gone\n' >a.txt
  git add a.txt
  git commit -q -m "add a"
  git rm -q a.txt
  printf 'one\nuses example-corp\n' >b.txt
  git add b.txt
  git commit -q -m "swap files"
  local out rc=0
  out="$(run_script HEAD~1..HEAD)" || rc=$?
  [[ "${rc}" -eq 1 && "${out}" == *"b.txt:2: uses example-corp"* ]] || fail "$1" "rc=${rc} out=${out}"
}

t_two_added_files_location() {
  new_repo
  printf 'fine\n' >a.txt
  printf 'x\ny\nexample-corp z\n' >b.txt
  git add a.txt b.txt
  git commit -q -m "two files"
  local out rc=0
  out="$(run_script HEAD~1..HEAD)" || rc=$?
  [[ "${rc}" -eq 1 && "${out}" == *"b.txt:3: example-corp z"* && "${out}" != *"a.txt"* ]] ||
    fail "$1" "rc=${rc} out=${out}"
}

t_second_file_name_only_passes() {
  new_repo
  printf 'fine\n' >a.txt
  printf 'harmless\n' >example-corp.txt
  git add a.txt example-corp.txt
  git commit -q -m "two files"
  local out rc=0
  out="$(run_script HEAD~1..HEAD)" || rc=$?
  [[ "${rc}" -eq 0 ]] || fail "$1" "rc=${rc} out=${out}"
}

t_unreadable_patterns_errors() {
  if [[ "$(id -u)" -eq 0 ]]; then
    printf "skipped (root)\n"
    return 0
  fi
  new_repo
  commit_file "uses example-corp host" "add host"
  cp "${TMP}/patterns.txt" "${TMP}/locked.txt"
  chmod 000 "${TMP}/locked.txt"
  local out rc=0
  out="$(PUBLIC_LEAK_PATTERNS="${TMP}/locked.txt" run_script HEAD~1..HEAD)" || rc=$?
  chmod 600 "${TMP}/locked.txt"
  [[ "${rc}" -eq 2 ]] || fail "$1" "rc=${rc} out=${out}"
}

for t in t_added_line_blocks t_preexisting_passes t_message_blocks t_deleted_line_passes \
  t_missing_patterns_warns t_hook_new_branch t_hook_skips_deletion \
  t_merge_result_blocks t_binary_blocks t_anchored_pattern t_filename_only_passes \
  t_plusplus_line_blocks t_invalid_pattern_errors t_hook_unknown_remote_blocks \
  t_hook_new_branch_two_tips t_delete_then_add_file t_two_added_files_location \
  t_second_file_name_only_passes t_unreadable_patterns_errors; do
  "${t}" "${t}" >"${TMP}/out.txt" 2>&1
  if grep -q '^FAIL' "${TMP}/out.txt"; then
    cat "${TMP}/out.txt"
    failed=1
  else
    pass "${t}"
  fi
done

exit "${failed}"
