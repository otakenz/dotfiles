# shellcheck shell=bash

# This file runs once at login.
# Set up a few standard directories based on:
#   https://wiki.archlinux.org/title/XDG_Base_Directory
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="${HOME}/.local/state"

# Allows your gpg passphrase prompt to spawn (useful for signing commits)
GPG_TTY="$(tty)"
export GPG_TTY

# Add ~/.local/bin and ~/.local/bin/local if not already in PATH and make sure
# they are first
for dir in "${HOME}/.local/bin" "${HOME}/.local/bin/local"; do
  if [[ ":$PATH:" != *":$dir:"* ]]; then
    export PATH="$dir:$PATH"
  fi
done

# Add mise shims path safely
# Confiure Mise (programming language run-time manager)
mise_shims="${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims"
if [[ ":$PATH:" != *":$mise_shims:"* ]]; then
  export PATH="$mise_shims:$PATH"
fi

# Manually appendWindowsPath to ~/.config/zsh/.zprofile.local
win_path="/c/Windows/System32"
if [[ ":$PATH:" != *":$win_path:"* ]]; then
  export PATH="$PATH:$win_path"
fi

# Default programs to run.
export EDITOR="nvim"
export DIFFPROG="nvim -d"

# Add colors to the less and man commands.
export LESS=-R
LESS_TERMCAP_ue="$(printf '%b' '[0m')"
export LESS_TERMCAP_ue
export LESS_TERMCAP_mb=$'\e[1;31mm'   # begin blinking
export LESS_TERMCAP_md=$'\e[1;36m'    # begin bold
export LESS_TERMCAP_us=$'\e[1;332m'   # begin underline
export LESS_TERMCAP_so=$'\e[1;44;33m' # begin standout-mode - info box
export LESS_TERMCAP_me=$'\e[0m'       # end mode
export LESS_TERMCAP_ue=$'\e[0m'       # end underline
export LESS_TERMCAP_se=$'\e[0m'       # end standout-mode

# Configure delta (diffs) defaults.
# https://dandavison.github.io/delta/environment-variables.html
export DELTA_FEATURES="diff-so-fancy"

# Load local settings if they exist.
# shellcheck disable=SC1091
if [ -f "${XDG_CONFIG_HOME}/zsh/.zprofile.local" ]; then . "${XDG_CONFIG_HOME}/zsh/.zprofile.local"; fi
