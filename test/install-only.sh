#!/usr/bin/env bash
# shellcheck disable=SC2016
# Hermetic test for `./install --only`: fakes on PATH, a throwaway HOME per
# run, nothing outside a temp dir is touched. ONLY_TESTS="a b" selects tests.

set -o errexit
set -o nounset
set -o pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d /tmp/install-only.XXXXXX)"
CALLS=

cleanup() {
  if [ -n "${KEEP:-}" ]; then
    echo "kept ${ROOT}"
  else
    rm -rf "${ROOT}"
  fi
}
trap cleanup EXIT

CURRENT=
fail() {
  printf "  \e[31mFAIL\e[0m %s: %s\n" "${CURRENT}" "${*}" >&2
  local log
  for log in "${ROOT}"/*.log; do
    [ -f "${log}" ] && {
      printf -- "--- %s\n" "${log##*/}"
      tail -n 25 "${log}"
    } >&2
  done
  exit 1
}

set -o errtrace
trap 'fail "unexpected error: ${BASH_COMMAND} (line ${LINENO})"' ERR

called() { grep -qE "${1}" "${CALLS}"; }
not_called() { ! grep -qE "${1}" "${CALLS}"; }

write_fake() { # NAME [BODY]: logs "<name> <args>" to $CALLS, then runs BODY
  local body="${2:-}"
  local var
  var="$(printf '%s' "${1}" | tr '[:lower:]' '[:upper:]' | tr -c 'A-Z0-9' _)"
  [ -n "${body}" ] || body="exit \"\${FAKE_EXIT_${var}:-0}\""
  {
    printf '#!/bin/sh\n'
    printf 'echo "%s $*" >>"$CALLS"\n' "${1}"
    printf '%s\n' "${body}"
  } >"${ROOT}/fake/${1}"
  chmod +x "${ROOT}/fake/${1}"
}

write_fakes() {
  mkdir -p "${ROOT}/fake"
  write_fake uname 'case "$1" in
-m) echo x86_64 ;;
-a) echo "${FAKE_UNAME_A:-Linux host 6.1 x86_64 GNU/Linux}" ;;
*) echo "${FAKE_UNAME_S:-Linux}" ;;
esac'
  # Runs the rest only when it is one of our fakes; never real system tools.
  {
    printf '#!/bin/sh\n'
    printf 'echo "sudo $*" >>"$CALLS"\n'
    printf '[ -x "%s/fake/$1" ] && exec "$@"\nexit 0\n' "${ROOT}"
  } >"${ROOT}/fake/sudo"
  chmod +x "${ROOT}/fake/sudo"
  write_fake git 'case "$*" in *clone*) for last; do :; done; mkdir -p "$last/bin"; for b in install_plugins update_plugins; do printf "#!/bin/sh\necho \"$b \$*\" >>\"\$CALLS\"\n" >"$last/bin/$b"; chmod +x "$last/bin/$b"; done ;; esac; exit 0'
  local f
  for f in curl apt-get dpkg gpg tee pacman makepkg brew tasklist.exe tmux nvim fastfetch; do
    write_fake "${f}"
  done
}

# run_install NAME ARGS...: fresh HOME and repo copy; log in $ROOT/NAME.log
run_install() {
  local name="${1}"
  shift
  local home="${ROOT}/${name}"
  CALLS="${ROOT}/${name}.calls"
  : >"${CALLS}"
  mkdir -p "${home}"
  cp -R "${REPO}" "${home}/dotfiles"
  rm -rf "${home}/dotfiles/.git"
  [ -z "${PRE:-}" ] || "${PRE}" "${home}"
  mkdir -p "${home}/dotfiles/.local/bin"
  printf '#!/bin/sh\necho "update-zsh-plugins $*" >>"$CALLS"\n' >"${home}/dotfiles/.local/bin/update-zsh-plugins"
  chmod +x "${home}/dotfiles/.local/bin/update-zsh-plugins"
  local rc=0 v
  local fake_env=()
  for v in $(compgen -v FAKE_); do
    fake_env+=("${v}=${!v}")
  done
  (
    cd "${home}/dotfiles"
    env -i HOME="${home}" LOCAL=1 DOTFILES_PATH="${home}/dotfiles" \
      PATH="${ROOT}/fake:${PATH}" CALLS="${CALLS}" TERM=dumb \
      FAKE_UNAME_S="${FAKE_UNAME_S:-Linux}" FAKE_UNAME_A="${FAKE_UNAME_A:-}" \
      "${fake_env[@]}" \
      OS_RELEASE_FILE="${OS_RELEASE_FILE:-}" WIN_USER_PATH="${WIN_USER_PATH:-}" \
      IN_CONTAINER="${IN_CONTAINER:-}" \
      bash ./install "${@}" </dev/null >"${ROOT}/${name}.log" 2>&1
  ) || rc=$?
  return "${rc}"
}

# skip_if_root REASON: use as `skip_if_root "why" || return 0`
skip_if_root() {
  [ "${EUID}" = 0 ] || return 0
  echo "  skipped (root): ${1}"
  return 1
}

scenario() { # debian | arch | macos | wsl
  FAKE_UNAME_S=Linux FAKE_UNAME_A="" IN_CONTAINER=1 WIN_USER_PATH=""
  case "${1}" in
  debian | arch)
    printf 'ID=%s\n' "$([ "${1}" = arch ] && echo arch || echo ubuntu)" >"${ROOT}/os-release"
    OS_RELEASE_FILE="${ROOT}/os-release"
    ;;
  macos)
    FAKE_UNAME_S=Darwin
    OS_RELEASE_FILE=
    ;;
  wsl)
    printf 'ID=ubuntu\n' >"${ROOT}/os-release"
    OS_RELEASE_FILE="${ROOT}/os-release"
    FAKE_UNAME_A="Linux host 5.15 microsoft-standard-WSL2 x86_64"
    IN_CONTAINER=
    WIN_USER_PATH="${ROOT}/win"
    ;;
  esac
  export FAKE_UNAME_S FAKE_UNAME_A IN_CONTAINER WIN_USER_PATH OS_RELEASE_FILE
}

t_only_unknown_piece() {
  scenario debian
  ! run_install m1 --only zsh,nope || fail "unknown piece accepted"
  grep -q "zsh, wezterm, tmux, health" "${ROOT}/m1.log" || fail "valid names not listed"
  not_called '^(git|apt-get|update-zsh-plugins|tmux|fastfetch)' || fail "ran something"
}
t_only_empty() {
  scenario debian
  ! run_install m2 --only "" || fail "empty --only accepted"
}
t_only_with_keys() {
  scenario debian
  ! run_install m3 --only zsh --keys /tmp/x || fail "--only with --keys accepted"
}
t_only_runs_in_order() {
  scenario debian
  run_install m4 --only health,zsh || fail "exit non-zero"
  [ "$(grep -E '^(update-zsh-plugins|tmux -V)' "${ROOT}/m4.calls" | cut -d' ' -f1 | tr '\n' ' ')" = "update-zsh-plugins tmux " ] || fail "order"
  called 'git clone .*powerlevel10k' || fail "powerlevel10k not cloned"
  not_called '^(apt-get|git clone .*tpm)' || fail "ran other pieces"
}
t_only_with_wiki() {
  scenario debian
  ! run_install m6 --only zsh --wiki || fail "--only with --wiki accepted"
}
t_only_no_value() {
  scenario debian
  ! run_install m7 --only || fail "--only without value accepted"
  grep -q "needs piece names" "${ROOT}/m7.log" || fail "no hint"
}
t_only_equals_empty() {
  scenario debian
  ! run_install m8 --only= || fail "--only= accepted"
  grep -q "needs piece names" "${ROOT}/m8.log" || fail "no hint"
}
t_only_wsl_health() {
  skip_if_root "warn_root would prompt in WSL" || return 0
  scenario wsl
  run_install m9 --only health || fail "exit non-zero"
  called '^uname -a' || fail "uname -a not consulted"
  called '^fastfetch' || fail "health not run"
}
t_only_equals_form() {
  scenario debian
  run_install m5 --only=health || fail "--only= form"
  called '^fastfetch' || fail "health not run"
}

pre_p10k() { mkdir -p "${1}/powerlevel10k/.git"; }
t_zsh_pulls_p10k() {
  scenario debian
  PRE=pre_p10k run_install m10 --only zsh || fail "exit"
  called '^git -C .*/powerlevel10k pull --ff-only' || fail "p10k not pulled"
  called '^update-zsh-plugins' || fail "zsh plugins not updated"
}
t_zsh_clones_p10k() {
  scenario debian
  run_install m11 --only zsh || fail "exit"
  called '^git clone --depth=1 https://github.com/romkatv/powerlevel10k.git' || fail "p10k not cloned"
}
t_tmux_updates() {
  scenario debian
  run_install m12 --only tmux || fail "exit"
  called '^install_plugins' || fail "plugins not installed"
  called '^update_plugins all' || fail "plugins not updated"
}

write_fakes
ALL_TESTS="$(declare -F | sed -n 's/^declare -f \(t_.*\)$/\1/p')"
for t in ${ONLY_TESTS:-${ALL_TESTS}}; do
  CURRENT="${t#t_}"
  printf "  %s\n" "${CURRENT}"
  "${t}"
done
echo "OK"
