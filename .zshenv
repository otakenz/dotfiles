# shellcheck shell=bash

# Set up a few standard directories based on:
#   https://wiki.archlinux.org/title/XDG_Base_Directory
export XDG_CONFIG_HOME="$HOME/.config"

# Point to where .zshrc is
export ZDOTDIR="${XDG_CONFIG_HOME}/zsh"
