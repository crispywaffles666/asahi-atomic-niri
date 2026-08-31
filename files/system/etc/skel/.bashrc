#
# ~/.bashrc
#

# PATH
path_prepend() {
  [[ ":$PATH:" == *":$1:"* ]] || PATH="$1:$PATH"
}

path_prepend "$HOME/bin"
path_prepend "$HOME/.local/bin"
export PATH

# env vars
export EDITOR=micro
export VISUAL=micro
export MANPAGER="less -R"

[[ $- != *i* ]] && return

# Reset login shell hooks from /etc/profile.d/ that conflict with ble.sh
PROMPT_COMMAND=()
PS0=

command -v pfetch >/dev/null && pfetch

# completions
[[ -r /usr/share/bash-completion/bash_completion ]] && source /usr/share/bash-completion/bash_completion

# navigation
shopt -s autocd

# history
HISTFILE=~/.bash_history
HISTSIZE=10000
HISTFILESIZE=10000
HISTCONTROL=ignoredups
shopt -s histappend

# keybinds
bind '"\e[1;2D": backward-word'
bind '"\e[1;2C": forward-word'
bind '"\e[1;5D": beginning-of-line'
bind '"\e[1;5C": end-of-line'

# aliases
alias ls='ls --color=auto -A'
alias grep='grep --color=auto'
alias fastfetch='/usr/bin/fastfetch -c ~/.config/fastfetch/fastfetch.jsonc'
alias neofetch='/usr/bin/fastfetch -c ~/.config/fastfetch/fastfetch.jsonc'
alias cat="bat --theme=base16 --paging=never"

# prompt
eval "$(starship init bash)"

# fzf
eval "$(fzf --bash)"
[[ $BLE_VERSION ]] || [[ ! -r ~/.local/share/blesh/ble.sh ]] || source ~/.local/share/blesh/ble.sh --attach=prompt
