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
  # FAKE_SKILLS_SRC: tree an anthropics/skills clone gets; FAKE_SKILLS_SHA: its HEAD.
  write_fake git '[ -z "${FAKE_EXIT_GIT:-}" ] || exit "$FAKE_EXIT_GIT"
case "$*" in *rev-parse*) echo "${FAKE_SKILLS_SHA:-0000000}"; exit 0 ;; esac
case "$*" in *clone*anthropics/skills*) for last; do :; done; mkdir -p "$last"; [ -z "${FAKE_SKILLS_SRC:-}" ] || cp -R "$FAKE_SKILLS_SRC/." "$last"; exit 0 ;; esac
case "$*" in *clone*) for last; do :; done; mkdir -p "$last"; case "$*" in *tpm*) mkdir -p "$last/bin"; for b in install_plugins update_plugins; do printf "#!/bin/sh\necho \"$b \$*\" >>\"\$CALLS\"\n" >"$last/bin/$b"; chmod +x "$last/bin/$b"; done ;; esac ;; esac; exit 0'
  write_fake curl 'for url; do :; done
out=
while [ $# -gt 0 ]; do [ "$1" = -o ] && out="$2"; shift; done
bytes() { case "$1" in *setup.exe) printf "#!/bin/sh\necho \"setup.exe \$*\" >>\"\$CALLS\"\n" ;; *) printf FAKEBYTES ;; esac; }
hash() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | cut -d" " -f1; }
case "$url" in
*.sha256)
  h="$(bytes "${url%.sha256}" | hash)"
  [ "${FAKE_BAD_SHA:-}" = 1 ] && h="$(printf "%064d" 0)"
  printf "%s  %s\n" "$h" "${url%.sha256}" | sed "s# [^ ]*/# #" >"${out:-/dev/stdout}"
  ;;
*) [ -z "$out" ] || bytes "$url" >"$out" ;;
esac
exit 0'
  write_fake tasklist.exe '[ -z "${FAKE_EXIT_TASKLIST_EXE:-}" ] || exit "$FAKE_EXIT_TASKLIST_EXE"
[ "${FAKE_WEZTERM_RUNNING:-}" = 1 ] && echo "wezterm-gui.exe 123 Console 1 10 K"
exit 0'
  write_fake reg.exe
  write_fake wslpath 'echo "C:\\win\\${2##*/}"'
  write_fake dpkg 'if [ "$1 ${2:-}" = "-s wezterm" ]; then [ "${FAKE_STABLE:-}" = 1 ]; exit; fi
exit 0'
  # FAKE_PULSE: missing | residual (removed, config kept) | unset = installed
  write_fake dpkg-query 'case "${FAKE_PULSE:-}" in
missing) exit 1 ;;
residual) printf "deinstall ok config-files" ;;
*) printf "install ok installed" ;;
esac'
  write_fake pacman 'if [ "$1 ${2:-}" = "-Q wezterm" ]; then [ "${FAKE_STABLE:-}" = 1 ]; exit; fi
if [ "$1 ${2:-}" = "-Q libpulse" ]; then [ "${FAKE_PULSE:-}" != missing ]; exit; fi
exit 0'
  # `uv venv DIR` leaves a python stub in DIR/bin that logs as "venv-python".
  write_fake uv 'if [ "$1" = venv ]; then
  for last; do :; done
  mkdir -p "$last/bin"
  printf "#!/bin/sh\necho \"venv-python \$*\" >>\"\$CALLS\"\n" >"$last/bin/python"
  chmod +x "$last/bin/python"
fi
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
  for f in gpg tee nvim tmux fastfetch nvidia-smi systemctl; do
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
  rm -rf "${home}/dotfiles/.git" "${home}/dotfiles/vscode-llmi/node_modules" "${home}/dotfiles/vscode-llmi/dist"
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
  grep -q "zsh, wezterm, tmux, skills, health, voice-input" "${ROOT}/m1.log" || fail "valid names not listed"
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
  [ "$(cat "${ROOT}/w1/.local/state/dotfiles/wezterm-nightly.sha256")" = "$(nightly_sha)" ] || fail "stamp not saved"
}
nightly_sha() { CALLS=/dev/null "${ROOT}/fake/curl" -fsSL "https://x/nightly/WezTerm-nightly-setup.exe.sha256"; }
pre_stamp_current() { mkdir -p "${1}/.local/state/dotfiles" && nightly_sha >"${1}/.local/state/dotfiles/wezterm-nightly.sha256"; }
pre_stamp_old() { mkdir -p "${1}/.local/state/dotfiles" && echo old >"${1}/.local/state/dotfiles/wezterm-nightly.sha256"; }
t_wsl_up_to_date_skips() {
  skip_if_root "warn_root would prompt in WSL" || return 0
  scenario wsl
  FAKE_WEZTERM_RUNNING=1 PRE=pre_stamp_current run_install w5 --only wezterm || fail "exit"
  not_called '^(tasklist.exe|setup.exe)' || fail "checked processes or installed"
  grep -q "up to date" "${ROOT}/w5.log" || fail "no message"
}
t_wsl_new_nightly_installs() {
  skip_if_root "warn_root would prompt in WSL" || return 0
  scenario wsl
  PRE=pre_stamp_old run_install w6 --only wezterm || fail "exit"
  called '^setup.exe' || fail "installer not run"
  [ "$(cat "${ROOT}/w6/.local/state/dotfiles/wezterm-nightly.sha256")" = "$(nightly_sha)" ] || fail "stamp not updated"
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
WEZTERM_FONTS="MesloLGSNerdFontMono-Regular.ttf MesloLGSNerdFontMono-Bold.ttf MesloLGSNerdFontMono-Italic.ttf MesloLGSNerdFontMono-BoldItalic.ttf SymbolsNerdFontMono-Regular.ttf"
pre_fonts() {
  local f
  mkdir -p "${1}/.local/share/fonts"
  for f in ${WEZTERM_FONTS} MesloLGSNerdFont-Regular.ttf; do
    echo "font ${f}" >"${1}/.local/share/fonts/${f}"
  done
}
win_fonts() { echo "${WIN_USER_PATH}/AppData/Local/Microsoft/Windows/Fonts"; }
t_wsl_fonts_copied() {
  skip_if_root "warn_root would prompt in WSL" || return 0
  wsl_config f1
  PRE=pre_fonts run_install f1 --only wezterm || fail "exit"
  local f
  for f in ${WEZTERM_FONTS}; do
    [ "$(cat "$(win_fonts)/${f}")" = "font ${f}" ] || fail "${f} not copied"
  done
  [ ! -e "$(win_fonts)/MesloLGSNerdFont-Regular.ttf" ] || fail "unused variant copied"
  [ "$(grep -c '^reg.exe add ' "${CALLS}")" -eq 5 ] || fail "not 5 registrations"
  called '^reg.exe add HKCU\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts /v MesloLGS Nerd Font Mono Bold Italic \(TrueType\) /t REG_SZ /d C:\\win\\MesloLGSNerdFontMono-BoldItalic.ttf /f$' ||
    fail "Bold Italic not registered"
  called '^reg.exe add .* /v Symbols Nerd Font Mono \(TrueType\) /t REG_SZ /d C:\\win\\SymbolsNerdFontMono-Regular.ttf /f$' ||
    fail "Symbols not registered"
}
t_wsl_fonts_current_untouched() {
  skip_if_root "warn_root would prompt in WSL" || return 0
  wsl_config f2
  local f
  mkdir -p "$(win_fonts)"
  for f in ${WEZTERM_FONTS}; do echo "font ${f}" >"$(win_fonts)/${f}"; done
  PRE=pre_fonts run_install f2 --only wezterm || fail "exit"
  ! grep -q "Copied .*\.ttf" "${ROOT}/f2.log" || fail "identical font copied again"
  ! grep -q "Restart WezTerm" "${ROOT}/f2.log" || fail "restart hint without change"
}
t_wsl_fonts_missing_in_wsl() {
  skip_if_root "warn_root would prompt in WSL" || return 0
  wsl_config f3
  run_install f3 --only wezterm || fail "exit"
  not_called '^reg.exe' || fail "registered fonts that are not there"
}
t_wsl_fonts_no_windows_home() {
  skip_if_root "warn_root would prompt in WSL" || return 0
  scenario wsl
  WIN_USER_PATH="${ROOT}/no-such-win"
  PRE=pre_fonts run_install f4 --only wezterm || fail "exit"
  not_called '^reg.exe' || fail "registered without a Windows home"
  [ ! -e "$(win_fonts)" ] || fail "created the Windows font folder"
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

# The real install-windows.sh calls cmd.exe and powershell.exe; never run it here.
pre_voice() {
  printf '#!/bin/sh\necho "install-windows.sh $*" >>"$CALLS"\nexit "${FAKE_AHK_EXIT:-0}"\n' \
    >"${1}/dotfiles/voice-input/install-windows.sh"
}
# pre_voice_done HOME: venv that imports faster_whisper, and a complete turbo model
TURBO=models--mobiuslabsgmbh--faster-whisper-large-v3-turbo
model_files() { # DIR FILES...: a snapshot holding FILES
  local dir="${1}" f
  shift
  mkdir -p "${dir}"
  for f in "${@}"; do touch "${dir}/${f}"; done
}
ALL_MODEL_FILES=(config.json model.bin preprocessor_config.json tokenizer.json vocabulary.json)
pre_voice_venv() {
  pre_voice "${1}"
  local data="${1}/.local/share/voice-input"
  mkdir -p "${data}/.venv/bin"
  printf '#!/bin/sh\necho "venv-python $*" >>"$CALLS"\n' >"${data}/.venv/bin/python"
  chmod +x "${data}/.venv/bin/python"
}
pre_voice_done() {
  pre_voice_venv "${1}"
  model_files "${1}/.local/share/voice-input/models/${TURBO}/snapshots/abc" "${ALL_MODEL_FILES[@]}"
}
pre_voice_partial() { # model.bin finished, tokenizer.json still downloading
  pre_voice_venv "${1}"
  model_files "${1}/.local/share/voice-input/models/${TURBO}/snapshots/abc" config.json model.bin
}
pre_voice_other_model() { # only large-v3, which the service does not load
  pre_voice_venv "${1}"
  model_files "${1}/.local/share/voice-input/models/models--Systran--faster-whisper-large-v3/snapshots/abc" "${ALL_MODEL_FILES[@]}"
}
pre_voice_mixed() { # older complete snapshot, newer one (the service's pick) incomplete
  pre_voice_done "${1}"
  model_files "${1}/.local/share/voice-input/models/${TURBO}/snapshots/zzz" model.bin
}
t_voice_skips_off_wsl() {
  scenario debian
  run_install v1 --only voice-input || fail "exit"
  not_called '^(nvidia-smi|uv|systemctl|apt-get)' || fail "ran setup off WSL"
  grep -q "needs WSL2" "${ROOT}/v1.log" || fail "no skip message"
}
t_voice_skips_macos() {
  scenario macos
  run_install v2 --only voice-input || fail "exit"
  not_called '^(nvidia-smi|uv|systemctl|brew)' || fail "ran setup on macOS"
  grep -q "needs WSL2" "${ROOT}/v2.log" || fail "no skip message"
}
t_voice_installs() {
  skip_if_root "warn_root would prompt in WSL" || return 0
  scenario wsl
  FAKE_PULSE=missing PRE=pre_voice run_install v3 --only voice-input || fail "exit"
  local home="${ROOT}/v3"
  called '^nvidia-smi -L' || fail "GPU not checked"
  called 'apt-get install -y pulseaudio-utils' || fail "parecord not installed"
  called '^uv venv --python 3\.12 .*/\.local/share/voice-input/\.venv$' || fail "no venv"
  called '^uv pip install --python .*/\.venv faster-whisper==1\.2\.1 nvidia-cublas-cu12 nvidia-cudnn-cu12==9\.\* av<16$' || fail "packages"
  called '^venv-python -c .*download_model\("large-v3-turbo", cache_dir=sys\.argv\[1\]\) .*/\.local/share/voice-input/models$' || fail "model not downloaded, or cache dir not passed as an argument"
  called '^systemctl --user daemon-reload' || fail "no daemon-reload"
  called '^systemctl --user enable --now voice-input$' || fail "service not enabled"
  called '^install-windows.sh' || fail "Windows side not installed"
  [ -L "${home}/.config/voice-input" ] || fail "config not linked"
  [ -L "${home}/.config/systemd/user/voice-input.service" ] || fail "unit not linked"
  [ -L "${home}/.local/bin/voice-input" ] || fail "wrapper not linked"
  [ "$(grep -nE '^(uv venv|systemctl --user enable)' "${CALLS}" | cut -d: -f2 | cut -d' ' -f1 | tr '\n' ' ')" = "uv systemctl " ] || fail "order"
  grep -q "Let desktop apps access your microphone" "${ROOT}/v3.log" || fail "no mic reminder"
}
t_voice_residual_pulse_installs() {
  skip_if_root "warn_root would prompt in WSL" || return 0
  scenario wsl
  FAKE_PULSE=residual PRE=pre_voice_done run_install v11 --only voice-input || fail "exit"
  called 'apt-get install -y pulseaudio-utils' || fail "removed package (config kept) taken as installed"
}
t_voice_installed_pulse_skips() {
  skip_if_root "warn_root would prompt in WSL" || return 0
  scenario wsl
  PRE=pre_voice_done run_install v12 --only voice-input || fail "exit"
  not_called 'apt-get install' || fail "reinstalled parecord"
}
pre_voice_own_config() { # a real folder with the user's own word list
  pre_voice_done "${1}"
  mkdir -p "${1}/.config/voice-input"
  echo "MyTerm" >"${1}/.config/voice-input/vocab.txt"
}
t_voice_keeps_own_config_dir() {
  skip_if_root "warn_root would prompt in WSL" || return 0
  scenario wsl
  PRE=pre_voice_own_config run_install v13 --only voice-input || fail "exit"
  local dir="${ROOT}/v13/.config/voice-input"
  [ ! -L "${dir}" ] || fail "folder replaced"
  [ ! -e "${dir}/voice-input" ] || fail "nested link created"
  [ "$(cat "${dir}/vocab.txt")" = MyTerm ] || fail "word list changed"
  grep -q "Kept your own" "${ROOT}/v13.log" || fail "not reported"
}
t_voice_no_gpu_fails() {
  skip_if_root "warn_root would prompt in WSL" || return 0
  scenario wsl
  ! FAKE_EXIT_NVIDIA_SMI=1 PRE=pre_voice run_install v4 --only voice-input || fail "accepted no GPU"
  not_called '^(uv|venv-python|systemctl|apt-get)' || fail "set up without GPU"
  grep -q "NVIDIA" "${ROOT}/v4.log" || fail "no hint"
}
t_voice_no_ahk_hints() {
  skip_if_root "warn_root would prompt in WSL" || return 0
  scenario wsl
  FAKE_AHK_EXIT=3 PRE=pre_voice run_install v5 --only voice-input || fail "exit"
  called '^systemctl --user enable --now voice-input$' || fail "service not enabled"
  grep -q "winget install AutoHotkey.AutoHotkey" "${ROOT}/v5.log" || fail "no hint"
}
t_voice_windows_failure_fails() {
  skip_if_root "warn_root would prompt in WSL" || return 0
  scenario wsl
  ! FAKE_AHK_EXIT=1 PRE=pre_voice run_install v8 --only voice-input || fail "accepted a failed Windows install"
}
t_voice_rerun_skips() {
  skip_if_root "warn_root would prompt in WSL" || return 0
  scenario wsl
  PRE=pre_voice_done run_install v6 --only voice-input || fail "exit"
  not_called '^(uv|apt-get)' || fail "reinstalled"
  not_called 'download_model' || fail "downloaded again"
  called '^systemctl --user enable --now voice-input$' || fail "service not enabled"
}
t_voice_partial_model_downloads() {
  skip_if_root "warn_root would prompt in WSL" || return 0
  scenario wsl
  PRE=pre_voice_partial run_install v7 --only voice-input || fail "exit"
  called 'download_model' || fail "partial model taken as done"
  not_called '^uv' || fail "venv reinstalled"
}

t_voice_other_model_downloads() {
  skip_if_root "warn_root would prompt in WSL" || return 0
  scenario wsl
  PRE=pre_voice_other_model run_install v9 --only voice-input || fail "exit"
  called 'download_model\("large-v3-turbo"' || fail "large-v3 taken as the turbo model"
}
t_voice_mixed_snapshots_download() {
  skip_if_root "warn_root would prompt in WSL" || return 0
  scenario wsl
  PRE=pre_voice_mixed run_install v10 --only voice-input || fail "exit"
  called 'download_model' || fail "older complete snapshot hid the incomplete one the service loads"
}

# Upstream: a (folded description, own metadata, new.txt), b (plain),
# e (no metadata). Local: listed a (stale.txt), c (gone upstream); own d.
skills_src() {
  local src="${ROOT}/skills-src/skills"
  [ -d "${src}" ] && return 0
  mkdir -p "${src}/a" "${src}/b" "${src}/e"
  printf -- '---\nname: a\ndescription: >\n  Long upstream\n  description text\nlicense: Apache\nmetadata:\n  author: x\n---\n# A body v2\n' >"${src}/a/SKILL.md"
  echo new >"${src}/a/new.txt"
  printf -- '---\nname: b\ndescription: B upstream\n---\nB body\n' >"${src}/b/SKILL.md"
  printf -- '---\nname: e\ndescription: E upstream\nlicense: L\n---\nE body\n' >"${src}/e/SKILL.md"
  mkdir -p "${src}/f" "${src}/g"
  printf -- '---\nname: f\ndescription: |-\n  Para one\n\n  Para two\nmetadata:\n    author: y\n    opencode/autoinvoke: true\n---\nF body\n' >"${src}/f/SKILL.md"
  printf -- '---\nname: g\nmetadata: # note\n    author: z\nlicense: L\n---\nG body\n' >"${src}/g/SKILL.md"
}
t_skills_multiparagraph_description() {
  run_skills s6 || fail "exit"
  local f="${ROOT}/s6/dotfiles/.config/opencode/skills/f/SKILL.md"
  ! grep -q 'Para' "${f}" || fail "description paragraph left behind"
  grep -qxF 'description: "Short f"' "${f}" || fail "f description not overridden"
}
t_skills_existing_key_set_false() {
  run_skills s7 || fail "exit"
  local f="${ROOT}/s7/dotfiles/.config/opencode/skills/f/SKILL.md"
  ! grep -q 'autoinvoke: true' "${f}" || fail "upstream true kept"
  [ "$(grep -c '^    opencode/autoinvoke: false$' "${f}")" -eq 1 ] || fail "key not set to false"
  grep -q '^    author: y$' "${f}" || fail "metadata entry lost"
}
t_skills_metadata_comment_indent() {
  run_skills s8 || fail "exit"
  local f="${ROOT}/s8/dotfiles/.config/opencode/skills/g/SKILL.md"
  [ "$(grep -c '^metadata:' "${f}")" -eq 1 ] || fail "second metadata added"
  grep -A2 '^metadata:' "${f}" | grep -qx '    opencode/autoinvoke: false' || fail "key not under metadata with its indent"
}
pre_skills() {
  local s="${1}/dotfiles/.config/opencode/skills"
  rm -rf "${s}"
  mkdir -p "${s}/a" "${s}/c" "${s}/d"
  cat >"${s}/upstream.conf" <<'EOF'
# comment
commit old

a | hidden | Short "a" \x
b | - |
c | - |
e | hidden |
f | hidden | Short f
g | hidden |
EOF
  printf -- '---\nname: a\ndescription: old\n---\nold body\n' >"${s}/a/SKILL.md"
  echo stale >"${s}/a/stale.txt"
  echo "local c" >"${s}/c/SKILL.md"
  echo "own d" >"${s}/d/SKILL.md"
  cp -R "${s}" "${1}/before"
}
run_skills() { # NAME [PRE]: refresh against the fixture
  skills_src
  scenario debian
  FAKE_SKILLS_SRC="${ROOT}/skills-src" FAKE_SKILLS_SHA=abc123 PRE="${2:-pre_skills}" \
    run_install "${1}" --only skills
}
t_skills_refresh() {
  run_skills s1 || fail "exit"
  local s="${ROOT}/s1/dotfiles/.config/opencode/skills" b="${ROOT}/s1/before"
  local up="${ROOT}/skills-src/skills"
  grep -qxF 'description: "Short \"a\" \\x"' "${s}/a/SKILL.md" || fail "a description not overridden"
  ! grep -q 'Long upstream\|description text' "${s}/a/SKILL.md" || fail "folded description left behind"
  [ "$(grep -c '^metadata:' "${s}/a/SKILL.md")" -eq 1 ] || fail "metadata duplicated"
  [ "$(grep -c '^  opencode/autoinvoke: false$' "${s}/a/SKILL.md")" -eq 1 ] || fail "a not hidden"
  grep -q '^  author: x$' "${s}/a/SKILL.md" || fail "upstream metadata lost"
  grep -q '^# A body v2$' "${s}/a/SKILL.md" || fail "a body not upstream"
  [ -f "${s}/a/new.txt" ] || fail "new upstream file missing"
  [ ! -e "${s}/a/stale.txt" ] || fail "stale file kept"
  cmp -s "${up}/b/SKILL.md" "${s}/b/SKILL.md" || fail "b changed"
  grep -q "c.*not in anthropics/skills" "${ROOT}/s1.log" || fail "no warning for c"
  cmp -s "${b}/c/SKILL.md" "${s}/c/SKILL.md" || fail "local c changed"
  cmp -s "${b}/d/SKILL.md" "${s}/d/SKILL.md" || fail "own d changed"
  grep -qx 'commit abc123' "${s}/upstream.conf" || fail "commit not recorded"
  ! grep -qx 'commit old' "${s}/upstream.conf" || fail "old commit kept"
  grep -qx 'a | hidden | Short "a" \\x' "${s}/upstream.conf" || fail "manifest lines changed"
}
t_skills_hidden_no_metadata() {
  run_skills s2 || fail "exit"
  local f="${ROOT}/s2/dotfiles/.config/opencode/skills/e/SKILL.md"
  [ "$(awk 'NR > 1 && /^---$/ { exit } NR > 1' "${f}" | tail -n 2 | tr '\n' '|')" = "metadata:|  opencode/autoinvoke: false|" ] ||
    fail "metadata not added at the end of the frontmatter"
  grep -q '^description: E upstream$' "${f}" || fail "e description changed"
  grep -q '^E body$' "${f}" || fail "e body lost"
}
pre_skills_again() {
  pre_skills "${1}"
  rm -rf "${1}/dotfiles/.config/opencode/skills"
  cp -R "${ROOT}/s3a/dotfiles/.config/opencode/skills" "${1}/dotfiles/.config/opencode/skills"
}
t_skills_refresh_twice() {
  run_skills s3a || fail "first exit"
  run_skills s3b pre_skills_again || fail "second exit"
  local s="${ROOT}/s3b/dotfiles/.config/opencode/skills"
  [ "$(grep -c 'opencode/autoinvoke: false' "${s}/a/SKILL.md")" -eq 1 ] || fail "a hidden twice"
  [ "$(grep -c 'opencode/autoinvoke: false' "${s}/e/SKILL.md")" -eq 1 ] || fail "e hidden twice"
  [ "$(grep -c '^metadata:' "${s}/e/SKILL.md")" -eq 1 ] || fail "e metadata twice"
}
t_skills_clone_failure() {
  FAKE_EXIT_GIT=1 run_skills s4 && fail "clone failure accepted"
  diff -r "${ROOT}/s4/before" "${ROOT}/s4/dotfiles/.config/opencode/skills" >/dev/null || fail "skills changed"
}
t_only_zsh_no_skills() {
  scenario debian
  run_install s5 --only zsh || fail "exit"
  not_called 'anthropics/skills' || fail "skills fetched"
}

write_fakes
ALL_TESTS="$(declare -F | sed -n 's/^declare -f \(t_.*\)$/\1/p')"
for t in ${ONLY_TESTS:-${ALL_TESTS}}; do
  CURRENT="${t#t_}"
  printf "  %s\n" "${CURRENT}"
  "${t}"
done
echo "OK"
