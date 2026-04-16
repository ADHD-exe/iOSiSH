# Common fish aliases and helpers for iOSiSH optional shell integration.
alias ... 'cd ../..'
alias .... 'cd ../../..'
alias ..... 'cd ../../../..'
alias c 'clear'
alias cls 'clear'
alias md 'mkdir -p'
alias rd 'rmdir'
alias du 'du -h'
alias df 'df -h'
alias h 'history'
alias hl 'history | less'
alias hs 'history | grep'
alias hsi 'history | grep -i'

if command -q bat
    alias cat 'bat --paging=never --style=plain'
    alias rcat 'command cat'
end

alias g 'git'
alias ga 'git add'
alias gaa 'git add --all'
alias gc 'git commit'
alias gca 'git commit --amend'
alias gco 'git checkout'
alias gcb 'git checkout -b'
alias gd 'git diff'
alias gf 'git fetch'
alias gl 'git pull'
alias gp 'git push'
alias gs 'git status'
alias gst 'git status'
alias glog 'git log --oneline --decorate --graph'
alias gloga 'git log --oneline --decorate --graph --all'
alias gpf 'git push --force-with-lease --force-if-includes'

if command -q fd
    alias f 'fd'
end
if command -q tmux
    alias t 'tmux'
end
if command -q lazygit
    alias lg 'lazygit'
end
if command -q tree
    alias tree 'tree -C'
end
if command -q ip
    alias ipa 'ip a'
    alias ipr 'ip r'
    alias ip 'ip'
end
if command -q doas
    alias se 'doas rc-update add'
    alias sd 'doas rc-update del'
    alias sr 'doas rc-service'
    alias fw 'doas iptables'
    alias apku 'doas apk update'
    alias apki 'doas apk add'
    alias apkr 'doas apk del'
end
if command -q rc-service
    alias ss 'rc-service'
end
if command -q sudo
    alias please 'sudo'
end

if command -q exa
    alias ls 'exa --group-directories-first'
    alias l 'exa -lh --group-directories-first'
    alias la 'exa -la --group-directories-first'
    alias ll 'exa -lah --group-directories-first --git'
    alias lt 'exa -T --level=2 --group-directories-first'
else if command -q tree
    alias lt 'tree -L 2'
end

function apkaddplus
    if test (count $argv) -eq 0
        echo 'usage: apkaddplus <package> [package...]'
        return 1
    end

    echo "[apk] installing: $argv"
    command apk add $argv; or return $status
    echo '[apk] base install complete'

    for pkg in $argv
        if string match -qr '^-' -- $pkg
            continue
        end

        if apk search -qe "$pkg-doc" >/dev/null 2>&1
            echo "[doc] installing $pkg-doc"
            command apk add "$pkg-doc" >/dev/null 2>&1
        end
    end
end

alias add 'apkaddplus'

if test -r "$HOME/.aliases.local.fish"
    source "$HOME/.aliases.local.fish"
end
