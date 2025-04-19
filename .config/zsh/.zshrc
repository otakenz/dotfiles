# shellcheck shell=bash

# shellcheck disable=SC2034
zsh_start_time=$(date +%s%N) # nanoseconds

# ---- P10K ---- #
# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
# shellcheck disable=SC2296
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-$(print -P %n).zsh" ]]; then
  # shellcheck disable=SC1090
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-$(print -P %n).zsh"
fi

# shellcheck disable=SC1090
source ~/powerlevel10k/powerlevel10k.zsh-theme

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
# shellcheck disable=SC1090
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
# ---- P10K ---- #

# ---- FZF ---- #
# Setup FZF key bindings and fuzzy completion
# zsh-vi-mode-plugin sets a few key binds such as CTRL+r/p/n which may conflict
# with other binds. This ensures fzf and our binds always win. If you choose
# to remove this zsh plugin then each array item can exist normally in zshrc.
# shellcheck disable=SC1090
zvm_after_init_commands+=(
  ". <(fzf --zsh)"
  # Ctrl + n/p to search through history forward/backward
  "bindkey '^p' history-search-backward"
  "bindkey '^n' history-search-forward"
  "bindkey '^k' history-search-backward"
  "bindkey '^j' history-search-forward"
)

## Configure FZF
export FZF_DEFAULT_OPTS="--highlight-line --info=inline-right --ansi --layout=reverse --border=none"
export FZF_DEFAULT_COMMAND="fd --hidden --strip-cwd-prefix --exclude .git"
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND="fd --type=d --hidden --strip-cwd-prefix --exclude .git"

# Setup FZF theme
# shellcheck disable=SC1091
source "${XDG_CONFIG_HOME}"/zsh/themes/fzf/tokyonight-moon.sh

# Use fd (https://github.com/sharkdp/fd) for listing path candidates.
# - The first argument to the function ($1) is the base path to start traversal
# - See the source code (completion.{bash,zsh}) for the details.
# Blazing fast tab completion with fd
_fzf_compgen_path() {
  fd --hidden --exclude .git . "$1"
}

# Use fd to generate the list for directory completion
_fzf_compgen_dir() {
  fd --type=d --hidden --exclude .git . "$1"
}

# shellcheck disable=SC1091
source "${HOME}/.fzf-git.sh/fzf-git.sh"

# Preview directory with eza, or preview file with bat
show_file_or_dir_preview="if [ -d {} ]; then eza --tree --color=always {} | head -200;
			  else bat -n --color=always --line-range :500 {}; fi"

export FZF_CTRL_T_OPTS="--preview '$show_file_or_dir_preview' --bind pgup:preview-page-up,pgdn:preview-page-down"
export FZF_ALT_C_OPTS="--preview 'eza --tree --color=always {} | head -200'"

# Advanced customization of fzf options via _fzf_comprun function
# - The first argument to the function is the name of the command.
# - You should make sure to pass the rest of the arguments to fzf.
_fzf_comprun() {
  local command=$1
  shift

  case "$command" in
  cd) fzf --preview 'eza --tree --color=always {} | head -200' "$@" ;;
  export | unset) fzf --preview "eval 'echo \${}'" "$@" ;;
  ssh) fzf --preview 'dig {}' "$@" ;;
  *) fzf --preview "$show_file_or_dir_preview" "$@" ;;
  esac
}
# ---- FZF ---- #

# ---- Mise (better asdf) ---- #
eval "$(/home/test/.local/bin/mise activate zsh)"

# ---- Bat (better cat) ---- #
export BAT_THEME=tokyonight_night

# ---- Eza (better ls) ---- #
alias ls="eza --icons=always"

# ---- TheFuck (fix typo command) ---- #
#eval $(thefuck --alias fixit)

# ---- Zoxide (better cd) ---- #
eval "$(zoxide init zsh)"
alias cd="z"

# ---- Zsh settings ---- #
## History settings
HISTFILE=${XDG_CACHE_HOME}/zsh/.zsh_history
HISTTIMEFORMAT="%Y/%m/%d %H:%M:%S  "
HISTSIZE=50000 # History lines stored in memory
SAVEHIST=50000 # History lines stored in disk
setopt SHARE_HISTORY
setopt HIST_VERIFY
setopt INC_APPEND_HISTORY     # Immediately append commands to history file
setopt HIST_IGNORE_ALL_DUPS   # Never add duplicate entries
setopt HIST_IGNORE_SPACE      # Ignore commands that start with a space
setopt HIST_REDUCE_BLANKS     # Remove unnecessary blank lines
setopt HIST_EXPIRE_DUPS_FIRST # Remove oldest history first

## Load Zsh plugins
# Better at syntax highlighting than zsh-syntax-highlighting
# shellcheck disable=SC1091
source "${XDG_DATA_HOME}"/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh
# shellcheck disable=SC1091
source "${XDG_DATA_HOME}"/zsh-autosuggestions/zsh-autosuggestions.zsh
export ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
# shellcheck disable=SC1091
source "${XDG_DATA_HOME}"/zsh-vi-mode/zsh-vi-mode.plugin.zsh
# shellcheck disable=SC1091
source "${XDG_DATA_HOME}"/fzf-tab/fzf-tab.plugin.zsh

# zsh-vi-mode settings
ZVM_LINE_INIT_MODE=$ZVM_MODE_INSERT
ZVM_VI_INSERT_ESCAPE_BINDKEY='jk'

## Zsh completion system
# Include dotfiles for compinit
_comp_options+=(globdots)
# Set default path for completion cache
_comp_dumpfile="${ZDOTDIR:-$HOME}/.zcompdump"

# Shows a menu when there are 2+ matches
# Makes completions more descriptive and forgiving
# Groups and labes the matches nicely
# Improves UX when completing anything from files to commands
zstyle ":completion:*" menu select=2
zstyle ":completion:*" auto-description "specify: %d"
zstyle ":completion:*" completer _expand _complete _correct _approximate
zstyle ":completion:*" format "Completing %d"
zstyle ":completion:*" group-name ""

# dircolors set up filetype-based colorization in Zsh's complete menu
# N/A in MacOS
command -v dircolors &>/dev/null && eval "$(dircolors -b)"

# Make tab-completion colorful and fuzzy
# Improve suggestions with smart matching (case-insensitive,underscores vs dashes)
# Add helpful prompts when scrolling through long completion list
# shellcheck disable=SC2016,SC2296
zstyle ":completion:*:default" list-colors '${(s.:.)LS_COLORS}'
zstyle ":completion:*" list-prompt %SAt %p: Hit TAB for more, or the character to insert%s
zstyle ":completion:*" matcher-list "" "m:{a-z}={A-Z}" "m:{a-zA-Z}={A-Za-z}" "r:|[._-]=* r:|=* l:|=*"
zstyle ':completion:*' select-prompt %SScrolling active: current selection at %p%s
zstyle ":completion:*" use-compctl false
zstyle ":completion:*" verbose true

# Ensure colors match by using FZF_DEFAULT_OPTS.
# zstyle ":fzf-tab:*" use-fzf-default-opts yes
# Preview file contents when tab completing directories.
zstyle ":fzf-tab:complete:cd:*" fzf-preview "eza --tree --color=always \${realpath} | head -n 200"
# switch group using `<` and `>`
zstyle ':fzf-tab:*' switch-group '<' '>'
# Rebind to tab to select multiple results
zstyle ':fzf-tab:*' fzf-bindings 'tab:toggle'

## Key bindings
# Use vi bindings for zsh
bindkey -v
# Ctrl + left/right move a word in cli
bindkey "^[[1;5D" backward-word # Ctrl+Left
bindkey "^[[1;5C" forward-word  # Ctrl+Right
bindkey '^F' toggle-fzf-tab # Ctrl+f

## Misc
# Allows your gpg passphrase prompt to spawn (useful for signing commits)
GPG_TTY="$(tty)"
export GPG_TTY

# Load colors so we can access $fg and more.
autoload -U colors && colors

# Disable Ctrl + s from accidentally freezing terminal output
[ -t 0 ] && stty stop undef

# Enable comments when working in an interactive shell
setopt interactive_comments

# Load aliases
# shellcheck disable=SC1091
[ -f "${XDG_CONFIG_HOME}/zsh/.aliases" ] && . "${XDG_CONFIG_HOME}/zsh/.aliases"

# Load local aliases if it exist
# shellcheck disable=SC1091
if [ -f "${XDG_CONFIG_HOME}/zsh/.aliases.local" ]; then . "${XDG_CONFIG_HOME}/zsh/.aliases.local"; fi

# ---- Zsh settings ---- #

# shellcheck disable=SC2034
zsh_end_time=$(date +%s%N)
#echo ".zshrc startup time: $(( (zsh_end_time - zsh_start_time)/1000000 )) ms"
