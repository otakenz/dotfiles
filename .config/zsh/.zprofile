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

# Function to safely prepend to PATH
prepend_path() {
  case ":$PATH:" in
  *":$1:"*) ;; # Already in PATH, do nothing
  *) PATH="$1:$PATH" ;;
  esac
}

# Safely append to PATH
append_path() {
  case ":$PATH:" in
  *":$1:"*) ;; # Already in PATH
  *) PATH="$PATH:$1" ;;
  esac
}

# When searching for binaries, my order of preference is:
# 1. Mason bin
# 2. Mise bin (Install those that are not provided by Mason)
# 3. System bin (Install those that are not provided by Mise)

pnpm_bin="${XDG_DATA_HOME:-$HOME/.local/share}/pnpm"
export PNPM_HOME="${pnpm_bin}"

# Since this is prepend, last one will be the first one found.
prepend_path "${HOME}/.local/bin"
prepend_path "${HOME}/.cargo/bin"
prepend_path "${pnpm_bin}"
prepend_path "${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims"
prepend_path "${XDG_DATA_HOME:-$HOME/.local/share}/nvim/mason/bin"

# Manually appendWindowsPath
if [[ "$(uname -a)" == *"WSL2"* ]]; then
  append_path "/c/Windows"
  append_path "/c/Program Files/WezTerm"
  # append_path "/c/Program Files/usbipd-win"
  # append_path "/c/Program Files/usbipd-win/WSL"
  append_path "/c/Users/$(/c/Windows/System32/cmd.exe /c 'echo %USERNAME%' 2>/dev/null |
    tr -d '\r')/AppData/Local/Programs/Microsoft VS Code/bin"

  # Set Microsoft Edge as the default browser for WSL
  export BROWSER='sh -c "\"/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe\" \"$@\"" _'
fi

export PATH

export CSPELL_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/nvim/spell/cspell.json"

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

# Configure GPG and pass locations.
export GNUPGHOME="${XDG_CONFIG_HOME}/gnupg"
export PASSWORD_STORE_DIR="${XDG_CONFIG_HOME}/password-store"

# Configure delta (diffs) defaults.
# https://dandavison.github.io/delta/environment-variables.html
export DELTA_FEATURES="diff-so-fancy"

# Load local settings if they exist.
# shellcheck disable=SC1091
if [ -f "${XDG_CONFIG_HOME}/zsh/.zprofile.local" ]; then . "${XDG_CONFIG_HOME}/zsh/.zprofile.local"; fi
