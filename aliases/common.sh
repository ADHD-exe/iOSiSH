# Common POSIX-style aliases and helpers for iOSiSH optional shell integration.
# This file is intended to be sourced from bash or zsh.

if [ -t 1 ]; then
    C_RESET="$(printf '\033[0m')"
    C_RED="$(printf '\033[31m')"
    C_GREEN="$(printf '\033[32m')"
    C_YELLOW="$(printf '\033[33m')"
else
    C_RESET=""
    C_RED=""
    C_GREEN=""
    C_YELLOW=""
fi

_cmsg() { printf '%s%s%s\n' "$1" "$2" "$C_RESET"; }

alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias .3='cd ../../..'
alias .4='cd ../../../..'
alias .5='cd ../../../../..'

alias c='clear'
alias cls='clear'
alias md='mkdir -p'
alias mkdir='mkdir -pv'
alias cp='cp -iv'
alias mv='mv -iv'
alias rm='rm -Iv'
alias rd='rmdir'
alias du='du -h'
alias df='df -h'
alias h='history'
alias hl='history | less'
alias hs='history | grep'
alias hsi='history | grep -i'

grep --help >/dev/null 2>&1 && alias grep='grep --color=auto'
alias egrep='grep -E'
alias fgrep='grep -F'
diff --help >/dev/null 2>&1 && alias diff='diff --color=auto'

if command -v bat >/dev/null 2>&1; then
    alias cat='bat --paging=never --style=plain'
    alias rcat='command cat'
fi

alias g='git'
alias ga='git add'
alias gaa='git add --all'
alias gc='git commit'
alias gca='git commit --amend'
alias gco='git checkout'
alias gcb='git checkout -b'
alias gd='git diff'
alias gf='git fetch'
alias gl='git pull'
alias gp='git push'
alias gs='git status'
alias gst='git status'
alias glog='git log --oneline --decorate --graph'
alias gloga='git log --oneline --decorate --graph --all'
alias gpf='git push --force-with-lease --force-if-includes'

command -v fd >/dev/null 2>&1 && alias f='fd'
command -v tmux >/dev/null 2>&1 && alias t='tmux'
command -v lazygit >/dev/null 2>&1 && alias lg='lazygit'
command -v tree >/dev/null 2>&1 && alias tree='tree -C'
command -v ip >/dev/null 2>&1 && alias ipa='ip a'
command -v ip >/dev/null 2>&1 && alias ipr='ip r'

command -v doas >/dev/null 2>&1 && alias se='doas rc-update add'
command -v doas >/dev/null 2>&1 && alias sd='doas rc-update del'
command -v rc-service >/dev/null 2>&1 && alias ss='rc-service'
command -v doas >/dev/null 2>&1 && alias sr='doas rc-service'
command -v doas >/dev/null 2>&1 && alias fw='doas iptables'
command -v doas >/dev/null 2>&1 && alias apku='doas apk update'
command -v doas >/dev/null 2>&1 && alias apki='doas apk add'
command -v doas >/dev/null 2>&1 && alias apkr='doas apk del'

command -v sudo >/dev/null 2>&1 && alias please='sudo'

if command -v exa >/dev/null 2>&1; then
    alias ls='exa --group-directories-first'
    alias l='exa -lh --group-directories-first'
    alias la='exa -la --group-directories-first'
    alias ll='exa -lah --group-directories-first --git'
    alias lt='exa -T --level=2 --group-directories-first'
else
    alias ls='ls --color=auto'
    alias l='ls -lh --color=auto'
    alias la='ls -la --color=auto'
    alias ll='ls -lah --color=auto'
    command -v tree >/dev/null 2>&1 && alias lt='tree -L 2'
fi

apkaddplus() {
    if [ "$#" -eq 0 ]; then
        echo "usage: apkaddplus <package> [package...]"
        return 1
    fi

    _cmsg "$C_YELLOW" "[apk] installing: $*"
    command apk add "$@" || return $?
    _cmsg "$C_GREEN" "[apk] base install complete"

    local pkg
    for pkg in "$@"; do
        case "$pkg" in
            -*)
                continue
                ;;
        esac

        if command apk search -qe "${pkg}-doc" >/dev/null 2>&1; then
            _cmsg "$C_YELLOW" "[doc] installing ${pkg}-doc"
            if command apk add "${pkg}-doc"; then
                _cmsg "$C_GREEN" "[doc] installed ${pkg}-doc"
            else
                _cmsg "$C_RED" "[doc] failed to install ${pkg}-doc"
            fi
        else
            _cmsg "$C_RED" "[doc] ${pkg}-doc not available"
        fi

        if command apk search -qe "${pkg}-zsh-completion" >/dev/null 2>&1; then
            _cmsg "$C_YELLOW" "[zsh] installing ${pkg}-zsh-completion"
            if command apk add "${pkg}-zsh-completion"; then
                _cmsg "$C_GREEN" "[zsh] installed ${pkg}-zsh-completion"
            else
                _cmsg "$C_RED" "[zsh] failed to install ${pkg}-zsh-completion"
            fi
        else
            _cmsg "$C_RED" "[zsh] ${pkg}-zsh-completion not available"
        fi
    done
}

alias add='apkaddplus'

if [ -r "$HOME/.aliases.local" ]; then
    . "$HOME/.aliases.local"
fi
