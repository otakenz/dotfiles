# shellcheck shell=bash

# Set up a few standard directories based on:
#   https://wiki.archlinux.org/title/XDG_Base_Directory
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="${HOME}/.local/state"

# Point to where .zshrc is
export ZDOTDIR="${XDG_CONFIG_HOME}/zsh"
