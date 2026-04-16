# Optional iOSiSH aliases for bash.
[ -r "$HOME/.config/iosish/common.sh" ] && . "$HOME/.config/iosish/common.sh"

alias _='sudo '
alias ip='ip'
alias rl='exec bash -l'

if command -v nvim >/dev/null 2>&1; then
    alias edit='nvim'
    alias v='nvim'
    alias vi='nvim'
    alias vim='nvim'
    alias svim='sudo nvim'
    alias shellrc='nvim ~/.bashrc'
    alias bashrc='nvim ~/.bashrc'
    alias al='nvim ~/.config/iosish/aliases.bash'
elif command -v nano >/dev/null 2>&1; then
    alias edit='nano'
    alias shellrc='nano ~/.bashrc'
    alias bashrc='nano ~/.bashrc'
    alias al='nano ~/.config/iosish/aliases.bash'
fi
