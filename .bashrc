#!usr/bin/env bash
# This file runs every time you open a new terminal window.

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# Limit number of lines and entries in the history. HISTFILESIZE controls the
# history file on disk and HISTSIZE controls lines stored in memory.
export HISTFILESIZE=50000
export HISTSIZE=50000

# Add a timestamp to each command.
export HISTTIMEFORMAT="%Y/%m/%d %H:%M:%S:   "

# Duplicate lines and lines starting with a space are not put into the history.
export HISTCONTROL=ignoreboth

# Append to the history file, don't overwrite it.
shopt -s histappend

# Ensure $LINES and $COLUMNS always get updated.
shopt -s checkwinsize

# If you add the following code to your .bashrc on a system with the default
# git bash completion scripts installed, it will automatically create
# completion-aware g<alias> bash aliases for each of your git aliases.
if [ -f /etc/bash_completion ] && ! shopt -oq posix; then
    . /etc/bash_completion
fi

if ! declare -f __git_complete &>/dev/null; then
	#Notes:
	#* __git_complete (defined in https://github.com/git/git/blob/master/contrib/completion/git-completion.bash#L3496-L3505)
	# is not public and is loaded by bash_completion dynamically on demand
	#* If __git_complete are not defined, then __git_complete_command and __gitcompappend are also undefined
	#* Solution is to source git completions (from one of these common locations)
	if [ -e /usr/share/bash-completion/completions/git ]; then
		# shellcheck disable=SC1091
		. /usr/share/bash-completion/completions/git
	elif [ -f /usr/local/share/bash-completion/completions/git ]; then
		# shellcheck disable=SC1091
		. /usr/local/share/bash-completion/completions/git
	elif [ -e /etc/bash_completion.d/git ]; then
		# shellcheck disable=SC1091
		. /etc/bash_completion.d/git
	else
		#return early because `__git_complete` is not defined
		return
	fi
fi

function_exists() {
    declare -f -F $1 > /dev/null
    return $?
}

# for al in `__git_aliases`; do
for al in `git --list-cmds=alias`; do
    alias g$al="git $al"

    complete_func="git $(__git_aliased_command $al)"
    function_exists $complete_fnc && __git_complete g$al $complete_func
done


# Improve output of less for binary files.
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# Load aliases if they exist.
[ -f "${HOME}/.aliases" ] && source "${HOME}/.aliases"
[ -f "${HOME}/.aliases.local" ] && source "${HOME}/.aliases.local"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# Determine git branch.
parse_git_branch() {
    git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/(\1)/'
}

PS1='${debian_chroot:+($debian_chroot)}\[[01;32m\]\u@\h\[[00m\]:\[[01;34m\]\w\[[00m\] \[[01;33m\]$(parse_git_branch)\[[00m\]\$ '

# If this is an xterm set the title to user@host:dir
case "$TERM" in
xterm*|rxvt*)
    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
    ;;
*)
    ;;
esac

# Enable asdf to manage various programming runtime versions.
#   Requires: https://asdf-vm.com/#/
# source "${HOME}"/.asdf/asdf.sh

# Enable a better reverse search experience.
#   Requires: https://github.com/junegunn/fzf (to use fzf in general)
#   Requires: https://github.com/BurntSushi/ripgrep (for using rg below)
export FZF_DEFAULT_COMMAND="rg --files --hidden --follow --glob '!.git'"
export FZF_DEFAULT_OPTS="--color=dark --bind ctrl-a:select-all"
[ -f "${HOME}/.fzf.bash" ] && source "${HOME}/.fzf.bash"

# # WSL 2 specific settings.
# if grep -q "microsoft" /proc/version &>/dev/null; then
#     # Requires: https://sourceforge.net/projects/vcxsrv/ (or alternative)
#     export DISPLAY="$(/sbin/ip route | awk '/default/ { print $3 }'):0"

#     # Allows your gpg passphrase prompt to spawn (useful for signing commits).
#     # export GPG_TTY=$(tty)
# fi

# # WSL 1 specific settings.
# if grep -qE "(Microsoft|WSL)" /proc/version &>/dev/null; then
#     echo "wsl1"
#     if [ "$(umask)" = "0000" ]; then
#         umask 0022
#     fi

#     # Requires: https://sourceforge.net/projects/vcxsrv/ (or alternative)
#     export DISPLAY=:0
# fi

# Auto sign-in to git
# eval `keychain --eval --agents ssh id_ed25519`

# unset LD_LIBRARY_PATH
#source /opt/ros/noetic/setup.bash
# source /opt/ros/foxy/setup.bash

# # modify the path to 'sw.sys.algo' or 'icp.sw.sys.algo', which you want to debug
# source /home/uie55151/sw.sys.algo/ROS-app/devel/setup.bash
# export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/usr/local/lib:/usr/lib"

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/home/uie55151/miniconda3/bin/conda' 'shell.bash' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/home/uie55151/miniconda3/etc/profile.d/conda.sh" ]; then
        . "/home/uie55151/miniconda3/etc/profile.d/conda.sh"
    else
        export PATH="/home/uie55151/miniconda3/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<

# export CPLUS_INCLUDE_PATH="/usr/local/include"
# export LIBRARY_PATH="/usr/local/lib"
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/usr/local/lib"
#export MESA_GL_VERSION_OVERRIDE=4.5



[ -f ~/.fzf.bash ] && source ~/.fzf.bash
