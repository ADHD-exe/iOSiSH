# Optional iOSiSH aliases for zsh.
[ -r "$HOME/.config/iosish/common.sh" ] && . "$HOME/.config/iosish/common.sh"

alias _='sudo '
alias sudo='nocorrect sudo'
alias su='nocorrect su'
alias ip='ip'
alias rl='exec zsh -l'

if command -v nvim >/dev/null 2>&1; then
    alias edit='nvim'
    alias v='nvim'
    alias vi='nvim'
    alias vim='nvim'
    alias svim='sudo nvim'
    alias shellrc='nvim ~/.zshrc'
    alias zshrc='nvim ~/.zshrc'
    alias al='nvim ~/.config/iosish/aliases.zsh'
elif command -v nano >/dev/null 2>&1; then
    alias edit='nano'
    alias shellrc='nano ~/.zshrc'
    alias zshrc='nano ~/.zshrc'
    alias al='nano ~/.config/iosish/aliases.zsh'
fi
