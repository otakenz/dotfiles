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
  write_fake git 'case "$*" in *clone*) for last; do :; done; mkdir -p "$last"; case "$*" in *tpm*) mkdir -p "$last/bin"; for b in install_plugins update_plugins; do printf "#!/bin/sh\necho \"$b \$*\" >>\"\$CALLS\"\n" >"$last/bin/$b"; chmod +x "$last/bin/$b"; done ;; esac ;; esac; exit 0'
  write_fake curl 'for url; do :; done
out=
while [ $# -gt 0 ]; do [ "$1" = -o ] && out="$2"; shift; done
bytes() { case "$1" in *setup.exe) printf "#!/bin/sh\necho \"setup.exe \$*\" >>\"\$CALLS\"\n" ;; *) printf FAKEBYTES ;; esac; }
hash() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | cut -d" " -f1; }
case "$url" in
*.sha256)
  h="$(bytes "${url%.sha256}" | hash)"
  [ "${FAKE_BAD_SHA:-}" = 1 ] && h="$(printf "%064d" 0)"
  printf "%s  %s\n" "$h" "${url%.sha256}" | sed "s# [^ ]*/# #" >"$out"
  ;;
*) [ -z "$out" ] || bytes "$url" >"$out" ;;
esac
exit 0'
  write_fake tasklist.exe '[ -z "${FAKE_EXIT_TASKLIST_EXE:-}" ] || exit "$FAKE_EXIT_TASKLIST_EXE"
[ "${FAKE_WEZTERM_RUNNING:-}" = 1 ] && echo "wezterm-gui.exe 123 Console 1 10 K"
exit 0'
  write_fake dpkg 'if [ "$1 ${2:-}" = "-s wezterm" ]; then [ "${FAKE_STABLE:-}" = 1 ]; exit; fi
exit 0'
  write_fake pacman 'if [ "$1 ${2:-}" = "-Q wezterm" ]; then [ "${FAKE_STABLE:-}" = 1 ]; exit; fi
exit 0'
  write_fake brew 'case "$*" in
"fetch --cask wezterm@nightly") exit "${FAKE_EXIT_BREW_FETCH:-0}" ;;
"list --cask wezterm@nightly") [ "${FAKE_NIGHTLY:-}" = 1 ]; exit ;;
"list --cask wezterm") [ "${FAKE_STABLE:-}" = 1 ]; exit ;;
esac
exit 0'
  cat >"${ROOT}/fake/makepkg" <<'EOS'
#!/bin/sh
echo "makepkg $* SRCDEST=$SRCDEST PKGDEST=$PKGDEST" >>"$CALLS"
if [ "$1" = --packagelist ]; then
  [ "${FAKE_MAKEPKG_LIST:-}" != fail ] || exit 1
  [ "${FAKE_MAKEPKG_LIST:-}" != empty ] || exit 0
  touch "$PKGDEST/wezterm-nightly-bin-1-1-x86_64.pkg.tar.zst"
  echo "$PKGDEST/wezterm-nightly-bin-1-1-x86_64.pkg.tar.zst"
  exit 0
fi
exit "${FAKE_EXIT_MAKEPKG:-0}"
EOS
  chmod +x "${ROOT}/fake/makepkg"
  local f
  write_fake apt-get '[ "${FAKE_APT_INSTALL_FAIL:-}" = 1 ] && [ "$1" = install ] && exit 1
exit "${FAKE_EXIT_APT_GET:-0}"'
  for f in gpg tee nvim tmux fastfetch; do
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
  [ "$(grep -nE '^(install_plugins|update_plugins)' "${CALLS}" | cut -d: -f2 | cut -d' ' -f1 | tr '\n' ' ')" = "install_plugins update_plugins " ] || fail "order"
}

t_wsl_installs() {
  skip_if_root "warn_root would prompt in WSL" || return 0
  scenario wsl
  run_install w1 --only wezterm || fail "exit"
  called '^setup.exe /SILENT /SUPPRESSMSGBOXES /NORESTART /SP-' || fail "installer not run"
  not_called 'winget' || fail "winget used"
}
t_wsl_running_wezterm_skips() {
  skip_if_root "warn_root would prompt in WSL" || return 0
  scenario wsl
  FAKE_WEZTERM_RUNNING=1 run_install w2 --only wezterm || fail "exit"
  not_called '^setup.exe' || fail "installer ran"
  grep -q "install --only wezterm" "${ROOT}/w2.log" || fail "no hint"
}
t_wsl_bad_checksum_fails() {
  skip_if_root "warn_root would prompt in WSL" || return 0
  scenario wsl
  ! FAKE_BAD_SHA=1 run_install w3 --only wezterm || fail "accepted bad hash"
  not_called '^setup.exe' || fail "installer ran"
  grep -q "try again" "${ROOT}/w3.log" || fail "no hint"
}
# wsl_config NAME: WSL scenario with its own Windows home
wsl_config() {
  scenario wsl
  WIN_USER_PATH="${ROOT}/win-${1}"
  mkdir -p "${WIN_USER_PATH}"
}
t_wsl_config_copied() {
  skip_if_root "warn_root would prompt in WSL" || return 0
  wsl_config c1
  run_install c1 --only wezterm || fail "exit"
  cmp -s "${REPO}/.config/wezterm/wezterm.lua" "${WIN_USER_PATH}/.wezterm.lua" || fail "not copied"
  [ ! -e "${WIN_USER_PATH}/.wezterm.lua.bak" ] || fail "backup without old copy"
}
t_wsl_config_stale_replaced() {
  skip_if_root "warn_root would prompt in WSL" || return 0
  wsl_config c2
  echo "old" >"${WIN_USER_PATH}/.wezterm.lua"
  FAKE_WEZTERM_RUNNING=1 run_install c2 --only wezterm || fail "exit"
  cmp -s "${REPO}/.config/wezterm/wezterm.lua" "${WIN_USER_PATH}/.wezterm.lua" || fail "not replaced"
  [ "$(cat "${WIN_USER_PATH}/.wezterm.lua.bak")" = old ] || fail "old copy not backed up"
}
t_wsl_config_current_untouched() {
  skip_if_root "warn_root would prompt in WSL" || return 0
  wsl_config c3
  cp "${REPO}/.config/wezterm/wezterm.lua" "${WIN_USER_PATH}/.wezterm.lua"
  run_install c3 --only wezterm || fail "exit"
  [ ! -e "${WIN_USER_PATH}/.wezterm.lua.bak" ] || fail "backed up an identical copy"
}
t_debian_stable_migrates() {
  scenario debian
  FAKE_STABLE=1 run_install d1 --only wezterm || fail "exit"
  called 'apt-get install -y wezterm-nightly wezterm-$' || fail "no single transaction"
  not_called 'apt-get remove' || fail "separate remove"
}
t_debian_nightly_updates() {
  scenario debian
  run_install d2 --only wezterm || fail "exit"
  not_called 'apt-get remove' || fail "removed"
  called 'apt-get install -y wezterm-nightly' || fail "nightly not installed"
}
t_arch_stable_migrates() {
  skip_if_root "makepkg cannot run as root" || return 0
  scenario arch
  FAKE_STABLE=1 run_install a1 --only wezterm || fail "exit"
  called 'pacman -R --noconfirm wezterm$' || fail "stable not removed"
  not_called 'pacman -Rns' || fail "recursive removal"
  called '^git clone https://aur.archlinux.org/wezterm-nightly-bin.git' || fail "no AUR clone"
  called '^makepkg -s --noconfirm SRCDEST=.*/pkg PKGDEST=.*/pkg' || fail "makepkg"
  called '^pacman -U --noconfirm .*/pkg/wezterm-nightly-bin' || fail "no pacman -U"
  [ "$(grep -nE '^(makepkg -s |pacman -R |pacman -Rns|pacman -U)' "${CALLS}" | cut -d: -f2 | cut -d' ' -f1-2 | tr '\n' ',')" = "makepkg -s,pacman -R,pacman -U," ] || fail "order"
}
t_arch_nightly_updates() {
  skip_if_root "makepkg cannot run as root" || return 0
  scenario arch
  run_install a2 --only wezterm || fail "exit"
  not_called 'pacman -R ' || fail "removed"
  called '^makepkg -s ' || fail "makepkg"
  called '^pacman -U ' || fail "no pacman -U"
}
t_arch_bad_checksum_fails() {
  skip_if_root "makepkg cannot run as root" || return 0
  scenario arch
  ! FAKE_STABLE=1 FAKE_BAD_SHA=1 run_install a3 --only wezterm || fail "accepted bad hash"
  not_called '^makepkg' || fail "makepkg ran"
  not_called 'pacman -R ' || fail "stable removed"
}
t_arch_build_failure_keeps_stable() {
  skip_if_root "makepkg cannot run as root" || return 0
  scenario arch
  ! FAKE_STABLE=1 FAKE_EXIT_MAKEPKG=1 run_install a4 --only wezterm || fail "build failure accepted"
  not_called 'pacman -R |pacman -Rns|pacman -U' || fail "stable removed"
}
t_macos_stable_migrates() {
  scenario macos
  FAKE_STABLE=1 run_install c1 --only wezterm || fail "exit"
  called 'brew fetch --cask wezterm@nightly' || fail "no fetch"
  called 'brew uninstall --cask wezterm$' || fail "stable not removed"
  called 'brew install --cask wezterm@nightly' || fail "nightly not installed"
}
t_macos_nightly_updates() {
  scenario macos
  FAKE_NIGHTLY=1 run_install c2 --only wezterm || fail "exit"
  called 'brew upgrade --cask --greedy wezterm@nightly' || fail "no upgrade"
  not_called 'brew uninstall' || fail "uninstalled"
}
t_arch_packagelist_failure_keeps_stable() {
  skip_if_root "makepkg cannot run as root" || return 0
  scenario arch
  ! FAKE_STABLE=1 FAKE_MAKEPKG_LIST=fail run_install a5 --only wezterm || fail "list failure accepted"
  not_called 'pacman -R |pacman -Rns|pacman -U' || fail "stable removed or install ran"
}
t_arch_empty_packagelist_keeps_stable() {
  skip_if_root "makepkg cannot run as root" || return 0
  scenario arch
  ! FAKE_STABLE=1 FAKE_MAKEPKG_LIST=empty run_install a6 --only wezterm || fail "empty list accepted"
  not_called 'pacman -R |pacman -Rns|pacman -U' || fail "stable removed or install ran"
}
t_debian_apt_failure_keeps_stable() {
  scenario debian
  ! FAKE_STABLE=1 FAKE_APT_INSTALL_FAIL=1 run_install d3 --only wezterm || fail "apt failure accepted"
  called 'apt-get install -y wezterm-nightly wezterm-$' || fail "transaction not attempted"
  not_called 'apt-get remove' || fail "separate remove"
}
t_macos_fetch_failure_keeps_stable() {
  scenario macos
  ! FAKE_STABLE=1 FAKE_EXIT_BREW_FETCH=1 run_install c3 --only wezterm || fail "fetch failure accepted"
  not_called 'brew (uninstall|install)' || fail "stable removed"
}
t_wsl_tasklist_failure_skips() {
  skip_if_root "warn_root would prompt in WSL" || return 0
  scenario wsl
  FAKE_EXIT_TASKLIST_EXE=1 run_install w4 --only wezterm || fail "exit"
  not_called '^setup.exe' || fail "installer ran"
  grep -q "tasklist.exe failed" "${ROOT}/w4.log" || fail "no diagnostic"
}
t_brew_packages_no_wezterm() {
  ! grep -qE '^  wezterm$' "${REPO}/install" || fail "wezterm in BREW_PACKAGES"
}

write_fakes
ALL_TESTS="$(declare -F | sed -n 's/^declare -f \(t_.*\)$/\1/p')"
for t in ${ONLY_TESTS:-${ALL_TESTS}}; do
  CURRENT="${t#t_}"
  printf "  %s\n" "${CURRENT}"
  "${t}"
done
echo "OK"
