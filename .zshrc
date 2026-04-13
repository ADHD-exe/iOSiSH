# iOSiSH shared zsh config

export TERM=xterm-256color 
export SHARED_HOME="${SHARED_HOME:-__PRIMARY_HOME__}"
export LANG="${LANG:-C.UTF-8}"
export EDITOR="${EDITOR:-nvim}"
export VISUAL="${VISUAL:-nvim}"
export PAGER="${PAGER:-less}"
export LESS="-FRX"
export ZSH_DISABLE_COMPFIX=true
export HISTFILE="$HOME/.zsh_history"
export HISTSIZE=50000
export SAVEHIST=50000
export ZSH="$SHARED_HOME/.oh-my-zsh"
export ZINIT_HOME="$SHARED_HOME/.local/share/zinit/zinit.git"

setopt APPEND_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_SPACE HIST_EXPIRE_DUPS_FIRST HIST_FIND_NO_DUPS
setopt HIST_REDUCE_BLANKS SHARE_HISTORY AUTO_CD INTERACTIVE_COMMENTS EXTENDED_GLOB COMPLETE_IN_WORD ALWAYS_TO_END PROMPT_SUBST NULL_GLOB

mkdir -p "$HOME/.cache/zsh" "$HOME/.ssh" "$SHARED_HOME/.config/zsh" "$SHARED_HOME/.local/share"

autoload -Uz compinit
rm -f "$HOME"/.zcompdump*
compinit -u -d "$HOME/.cache/zsh/zcompdump-$(id -un 2>/dev/null)"

HOST_DISPLAY="$(cat /etc/hostname 2>/dev/null || echo localhost)"
if [ "$(id -u 2>/dev/null)" = "0" ]; then USER_COLOR="red"; else USER_COLOR="cyan"; fi
PROMPT='%F{'$USER_COLOR'}%n@'"$HOST_DISPLAY"'%f:%F{yellow}%~%f %# '
RPROMPT='%(?..%F{red}[%?]%f)'

[ -r "$SHARED_HOME/.config/zsh/.aliases" ] && . "$SHARED_HOME/.config/zsh/.aliases"

if command -v zoxide >/dev/null 2>&1; then eval "$(zoxide init zsh)"; fi
[ -r /usr/share/fzf/key-bindings.zsh ] && . /usr/share/fzf/key-bindings.zsh
[ -r /usr/share/fzf/completion.zsh ] && . /usr/share/fzf/completion.zsh

[ -r "$ZSH/lib/git.zsh" ] && . "$ZSH/lib/git.zsh"
[ -r "$ZSH/lib/history.zsh" ] && . "$ZSH/lib/history.zsh"
[ -r "$ZSH/lib/completion.zsh" ] && . "$ZSH/lib/completion.zsh"
[ -r "$ZSH/plugins/git/git.plugin.zsh" ] && . "$ZSH/plugins/git/git.plugin.zsh"
[ -r "$ZSH/plugins/colored-man-pages/colored-man-pages.plugin.zsh" ] && . "$ZSH/plugins/colored-man-pages/colored-man-pages.plugin.zsh"

if [ -r "$ZINIT_HOME/zinit.zsh" ]; then
    . "$ZINIT_HOME/zinit.zsh"
    zinit ice lucid wait'0' blockf
    zinit light zsh-users/zsh-completions
    zinit ice lucid wait'0'
    zinit light zsh-users/zsh-autosuggestions
    zinit ice lucid wait'0'
    zinit light zsh-users/zsh-history-substring-search
    zinit ice lucid wait'0'
    zinit light zdharma-continuum/fast-syntax-highlighting
fi

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

if typeset -f history-substring-search-up >/dev/null 2>&1; then
    bindkey '^[[A' history-substring-search-up
    bindkey '^[[B' history-substring-search-down
fi

bindkey -e
umask 022

if command -v neofetch >/dev/null 2>&1 && [ -z "$IOSISH_NO_NEOFETCH" ]; then
    neofetch
fi
