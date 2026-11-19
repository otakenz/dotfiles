#!/usr/bin/env bash
# Prepares a bare CI container (run as root) for `yes | LOCAL=1 bash install`:
# sudo, curl, git, a fixed timezone so tzdata never prompts, and sudo keeping
# DEBIAN_FRONTEND. EXTRA_CA_DIR adds *.crt files to the system trust first.
# On macOS it only installs bash 4+, which the install script requires.

set -o errexit

if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  ln -fs /usr/share/zoneinfo/UTC /etc/localtime
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl git sudo >/dev/null
  if [ -d "${EXTRA_CA_DIR:-}" ]; then
    cp "${EXTRA_CA_DIR}"/*.crt /usr/local/share/ca-certificates/
    update-ca-certificates >/dev/null
  fi
  echo 'Defaults env_keep += "DEBIAN_FRONTEND"' >/etc/sudoers.d/keep-frontend
elif command -v pacman >/dev/null 2>&1; then
  if [ -d "${EXTRA_CA_DIR:-}" ]; then
    cp "${EXTRA_CA_DIR}"/*.crt /etc/ca-certificates/trust-source/anchors/
    update-ca-trust
  fi
  pacman -Syu --noconfirm --needed curl git sudo >/dev/null
elif command -v brew >/dev/null 2>&1; then
  brew install bash
else
  echo "No supported package manager found" >&2
  exit 1
fi
