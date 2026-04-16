# Optional iOSiSH aliases for fish.
if test -r "$HOME/.config/iosish/common.fish"
    source "$HOME/.config/iosish/common.fish"
end

alias _ 'sudo '
alias rl 'exec fish -l'

if command -q nvim
    alias edit 'nvim'
    alias v 'nvim'
    alias vi 'nvim'
    alias vim 'nvim'
    alias svim 'sudo nvim'
    alias shellrc 'nvim ~/.config/fish/config.fish'
    alias fishrc 'nvim ~/.config/fish/config.fish'
    alias al 'nvim ~/.config/iosish/aliases.fish'
else if command -q nano
    alias edit 'nano'
    alias shellrc 'nano ~/.config/fish/config.fish'
    alias fishrc 'nano ~/.config/fish/config.fish'
    alias al 'nano ~/.config/iosish/aliases.fish'
end
