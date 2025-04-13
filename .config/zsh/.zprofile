# shellcheck shell=bash

# Add all local binaries to the system path.
export PATH="${PATH}:${HOME}/.local/bin:${HOME}/.local/bin/local"

# Confiure Mise (programming language run-time manager)
export PATH="${XDG_DATA_HOME}/mise/shims:${PATH}"

# Default programs to run.
export EDITOR="nvim"

# Add colors to the less and man commands.
export LESS=-R
#LESS_TERMCAP_ue="$(printf '%b' '[0m')"
#export LESS_TERMCAP_ue
export LESS_TERMCAP_mb=$'\e[1;31mm'   # begin blinking
export LESS_TERMCAP_md=$'\e[1;36m'    # begin bold
export LESS_TERMCAP_us=$'\e[1;332m'   # begin underline
export LESS_TERMCAP_so=$'\e[1;44;33m' # begin standout-mode - info box
export LESS_TERMCAP_me=$'\e[0m'       # end mode
export LESS_TERMCAP_ue=$'\e[0m'       # end underline
export LESS_TERMCAP_se=$'\e[0m'       # end standout-mode
