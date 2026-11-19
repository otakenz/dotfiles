#!/usr/bin/env bash
# Installs what test/keys.sh needs (bash 4+, git, gnupg, gopass) on the CI
# platforms: Debian/Ubuntu and Arch containers run as root, macOS uses brew.
# Debian/Ubuntu take gopass from mise, as ./install does (apt's is too old or
# missing). EXTRA_CA_DIR adds *.crt files to the system trust first, for runs
# behind a TLS-intercepting proxy.

set -o errexit

_trust_extra_ca() {
  local anchors="${1}" update="${2}"
  [ -d "${EXTRA_CA_DIR:-}" ] || return 0
  cp "${EXTRA_CA_DIR}"/*.crt "${anchors}/"
  "${update}" >/dev/null
}

if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl git gnupg >/dev/null
  _trust_extra_ca /usr/local/share/ca-certificates update-ca-certificates

  curl -fsSL https://mise.run | MISE_INSTALL_PATH=/usr/local/bin/mise sh >/dev/null
  mise use --global --yes gopass@latest >/dev/null
  ln -sf "$(mise which gopass)" /usr/local/bin/gopass
elif command -v pacman >/dev/null 2>&1; then
  _trust_extra_ca /etc/ca-certificates/trust-source/anchors update-ca-trust
  pacman -Syu --noconfirm --needed git gnupg gopass >/dev/null
elif command -v brew >/dev/null 2>&1; then
  brew install bash gnupg gopass
else
  echo "No supported package manager found" >&2
  exit 1
fi

bash --version | head -n 1
gpg --version | head -n 1
gopass version
