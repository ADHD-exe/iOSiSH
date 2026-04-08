#!/bin/sh
# Alpine Linux / iSH setup script
# POSIX sh
# Safe to run as root
# Idempotent where practical

set -u

HOSTNAME_WANTED="iphoneish"
RABBIT_USER="rabbit"
ROOT_PASSWORD="Dorothy"
RABBIT_PASSWORD="Dorothy"

INSTALLED_PKGS=""
SKIPPED_PKGS=""

say() { printf '%s\n' "$*"; }
info() { printf '[INFO] %s\n' "$*"; }
ok() { printf '[ OK ] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; }
err() { printf '[ERR ] %s\n' "$*" >&2; }

append_csv() {
  if [ -n "${1:-}" ]; then
    printf '%s, %s' "$1" "$2"
  else
    printf '%s' "$2"
  fi
}

cmd_exists() {
  command -v "$1" >/dev/null 2>&1
}

pkg_installed() {
  apk info -e "$1" >/dev/null 2>&1
}

pkg_exists() {
  apk search -x "$1" >/dev/null 2>&1
}

install_pkg_alias() {
  label="$1"
  shift
  chosen=""

  for p in "$@"; do
    if pkg_installed "$p"; then
      chosen="$p"
      break
    fi
  done

  if [ -z "$chosen" ]; then
    for p in "$@"; do
      if pkg_exists "$p"; then
        chosen="$p"
        break
      fi
    done
  fi

  if [ -n "$chosen" ]; then
    if pkg_installed "$chosen"; then
      info "$label: already installed as $chosen"
    else
      info "$label: installing $chosen"
      if apk add --no-cache "$chosen" >/dev/null 2>&1; then
        ok "$label: installed $chosen"
      else
        warn "$label: failed to install $chosen"
        SKIPPED_PKGS=$(append_csv "$SKIPPED_PKGS" "$label")
        return 0
      fi
    fi
    INSTALLED_PKGS=$(append_csv "$INSTALLED_PKGS" "$label ($chosen)")
  else
    warn "$label: not found in Alpine repositories, skipping"
    SKIPPED_PKGS=$(append_csv "$SKIPPED_PKGS" "$label")
  fi
}

require_root() {
  if [ "$(id -u)" != "0" ]; then
    err "Run this script as root."
    exit 1
  fi
}

ensure_group_exists() {
  grp="$1"
  if grep -q "^${grp}:" /etc/group 2>/dev/null; then
    return 0
  fi
  if addgroup "$grp" >/dev/null 2>&1; then
    ok "Created group: $grp"
  else
    warn "Could not create group: $grp"
  fi
}

ensure_user() {
  if id "$RABBIT_USER" >/dev/null 2>&1; then
    ok "User $RABBIT_USER already exists"
  else
    info "Creating user $RABBIT_USER"
    if adduser -D -h "/home/$RABBIT_USER" "$RABBIT_USER" >/dev/null 2>&1; then
      ok "Created user $RABBIT_USER"
    else
      err "Failed to create user $RABBIT_USER"
      exit 1
    fi
  fi

  if [ ! -d "/home/$RABBIT_USER" ]; then
    mkdir -p "/home/$RABBIT_USER"
    ok "Created /home/$RABBIT_USER"
  fi

  chown "$RABBIT_USER:$RABBIT_USER" "/home/$RABBIT_USER" 2>/dev/null || true

  ensure_group_exists wheel

  if addgroup "$RABBIT_USER" wheel >/dev/null 2>&1; then
    ok "Ensured $RABBIT_USER is in wheel"
  else
    info "$RABBIT_USER may already be in wheel"
  fi

  if grep -q '^root:' /etc/group 2>/dev/null; then
    if adduser "$RABBIT_USER" root >/dev/null 2>&1; then
      ok "Ensured $RABBIT_USER is in root group"
    else
      info "$RABBIT_USER may already be in root group"
    fi
  else
    warn "Group root does not exist; skipping root-group membership"
  fi
}

set_passwords() {
  if cmd_exists chpasswd; then
    if printf 'root:%s\n%s:%s\n' "$ROOT_PASSWORD" "$RABBIT_USER" "$RABBIT_PASSWORD" | chpasswd >/dev/null 2>&1; then
      ok "Set passwords for root and $RABBIT_USER"
    else
      warn "Failed to set passwords with chpasswd"
    fi
  else
    warn "chpasswd not found; passwords were not set automatically"
  fi
}

set_hostname_live() {
  if hostname "$HOSTNAME_WANTED" >/dev/null 2>&1; then
    ok "Set live hostname to $HOSTNAME_WANTED"
  else
    warn "Could not set live hostname"
  fi
}

set_hostname_persistent() {
  printf '%s\n' "$HOSTNAME_WANTED" >/etc/hostname
  ok "Wrote /etc/hostname"

  if [ ! -f /etc/hosts ]; then
    printf '127.0.0.1\tlocalhost %s\n' "$HOSTNAME_WANTED" >/etc/hosts
    ok "Created /etc/hosts"
    return 0
  fi

  if grep -q "[[:space:]]$HOSTNAME_WANTED\$" /etc/hosts 2>/dev/null; then
    ok "/etc/hosts already contains $HOSTNAME_WANTED"
  else
    printf '127.0.0.1\tlocalhost %s\n' "$HOSTNAME_WANTED" >>/etc/hosts
    ok "Updated /etc/hosts"
  fi
}

set_shell_in_passwd() {
  usr="$1"
  newshell="$2"

  if ! grep -q "^${usr}:" /etc/passwd 2>/dev/null; then
    warn "User $usr not found in /etc/passwd"
    return 0
  fi

  current_shell="$(awk -F: -v u="$usr" '$1==u {print $7}' /etc/passwd 2>/dev/null)"
  if [ "$current_shell" = "$newshell" ]; then
    ok "Login shell for $usr already $newshell"
    return 0
  fi

  tmpf="/tmp/passwd.$$"
  if awk -F: -v OFS=: -v u="$usr" -v s="$newshell" '
        $1==u { $7=s }
        { print }
    ' /etc/passwd >"$tmpf"; then
    cat "$tmpf" >/etc/passwd
    rm -f "$tmpf"
    ok "Set login shell for $usr to $newshell"
  else
    rm -f "$tmpf"
    warn "Failed to update login shell for $usr"
  fi
}

write_profiles() {
  printf '%s\n' 'exec su - rabbit' >/root/.profile
  chmod 644 /root/.profile
  ok "Wrote /root/.profile"

  printf '%s\n' 'exec zsh -l' >"/home/$RABBIT_USER/.profile"
  chown "$RABBIT_USER:$RABBIT_USER" "/home/$RABBIT_USER/.profile" 2>/dev/null || true
  chmod 644 "/home/$RABBIT_USER/.profile"
  ok "Wrote /home/$RABBIT_USER/.profile"
}

clone_or_update_repo() {
  repo="$1"
  dest="$2"
  label="$3"

  parent="$(dirname "$dest")"
  [ -d "$parent" ] || mkdir -p "$parent"

  if [ -d "$dest/.git" ]; then
    ok "$label already present"
    return 0
  fi

  if ! cmd_exists git; then
    warn "git missing; cannot install $label"
    return 1
  fi

  if git clone --depth=1 "$repo" "$dest" >/dev/null 2>&1; then
    ok "Installed $label"
    return 0
  else
    warn "Failed to install $label"
    return 1
  fi
}

install_shell_frameworks() {
  home_dir="$1"
  owner_user="$2"

  omz_dir="$home_dir/.oh-my-zsh"
  zinit_dir="$home_dir/.local/share/zinit/zinit.git"

  clone_or_update_repo "https://github.com/ohmyzsh/ohmyzsh.git" \
    "$omz_dir" "Oh My Zsh for $owner_user" || true

  clone_or_update_repo "https://github.com/zdharma-continuum/zinit.git" \
    "$zinit_dir" "Zinit for $owner_user" || true

  mkdir -p "$home_dir/.cache/zsh"
  rm -f "$home_dir"/.zcompdump* "$home_dir"/.zcompdump*.zwc 2>/dev/null || true

  chown -R "$owner_user:$owner_user" "$home_dir/.oh-my-zsh" "$home_dir/.local" "$home_dir/.cache" 2>/dev/null || true
}

write_zshrc() {
  home_dir="$1"
  owner_user="$2"
  zshrc="$home_dir/.zshrc"

  cat >"$zshrc" <<'EOF'
# Generated by Alpine/iSH setup script
# Zinit-based, iSH-friendly, no Nerd Font dependencies

export LANG="${LANG:-C.UTF-8}"
export EDITOR="${EDITOR:-nvim}"
export VISUAL="${VISUAL:-nvim}"
export PAGER="${PAGER:-less}"
export LESS="-FRX"
export HISTFILE="$HOME/.zsh_history"
export HISTSIZE=50000
export SAVEHIST=50000
export ZSH="$HOME/.oh-my-zsh"
export ZINIT_HOME="$HOME/.local/share/zinit/zinit.git"

setopt APPEND_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_FIND_NO_DUPS
setopt HIST_REDUCE_BLANKS
setopt SHARE_HISTORY
setopt AUTO_CD
setopt INTERACTIVE_COMMENTS
setopt EXTENDED_GLOB
setopt COMPLETE_IN_WORD
setopt ALWAYS_TO_END
setopt PROMPT_SUBST

autoload -Uz compinit
mkdir -p "$HOME/.cache/zsh"
rm -f "$HOME"/.zcompdump*.zwc 2>/dev/null
compinit -d "$HOME/.cache/zsh/zcompdump-$HOST"

PROMPT='%F{cyan}%n@%m%f:%F{yellow}%~%f %# '
RPROMPT='%(?..%F{red}[%?]%f)'

if command -v eza >/dev/null 2>&1; then
    alias ls='eza --group-directories-first --icons=never'
    alias ll='eza -lah --group-directories-first --git --icons=never'
    alias la='eza -la --group-directories-first --icons=never'
elif command -v exa >/dev/null 2>&1; then
    alias ls='exa --group-directories-first'
    alias ll='exa -lah --group-directories-first --git'
    alias la='exa -la --group-directories-first'
else
    alias ls='ls --color=auto'
    alias ll='ls -lah --color=auto'
    alias la='ls -la --color=auto'
fi

alias grep='grep --color=auto'
alias diff='diff --color=auto'
alias cls='clear'
alias vi='nvim'
alias vim='nvim'
alias duh='du -sh ./* 2>/dev/null | sort -h'

if command -v bat >/dev/null 2>&1; then
    alias cat='bat --paging=never --style=plain'
fi

if command -v zoxide >/dev/null 2>&1; then
    eval "$(zoxide init zsh)"
fi

[ -r /usr/share/fzf/key-bindings.zsh ] && . /usr/share/fzf/key-bindings.zsh
[ -r /usr/share/fzf/completion.zsh ] && . /usr/share/fzf/completion.zsh

[ -r "$ZSH/lib/git.zsh" ] && . "$ZSH/lib/git.zsh"
[ -r "$ZSH/lib/history.zsh" ] && . "$ZSH/lib/history.zsh"
[ -r "$ZSH/lib/completion.zsh" ] && . "$ZSH/lib/completion.zsh"
[ -r "$ZSH/plugins/git/git.plugin.zsh" ] && . "$ZSH/plugins/git/git.plugin.zsh"
[ -r "$ZSH/plugins/colored-man-pages/colored-man-pages.plugin.zsh" ] && . "$ZSH/plugins/colored-man-pages/colored-man-pages.plugin.zsh"
[ -r "$ZSH/plugins/command-not-found/command-not-found.plugin.zsh" ] && . "$ZSH/plugins/command-not-found/command-not-found.plugin.zsh"
[ -r "$ZSH/plugins/history/history.plugin.zsh" ] && . "$ZSH/plugins/history/history.plugin.zsh"

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

    if [ ! -d "${ZINIT[PLUGINS_DIR]}/zdharma-continuum---fast-syntax-highlighting" ]; then
        zinit ice lucid wait'0'
        zinit light zsh-users/zsh-syntax-highlighting
    fi

    zinit ice lucid wait'0'
    zinit light marlonrichert/zsh-autocomplete
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
EOF

  chown "$owner_user:$owner_user" "$zshrc" 2>/dev/null || true
  chmod 644 "$zshrc"
  ok "Wrote $zshrc"
}

configure_sudo() {
  mkdir -p /etc/sudoers.d

  if [ ! -f /etc/sudoers.d/wheel ]; then
    printf '%%wheel ALL=(ALL) ALL\n' >/etc/sudoers.d/wheel
    chmod 440 /etc/sudoers.d/wheel
    ok "Configured sudo for wheel group"
  else
    chmod 440 /etc/sudoers.d/wheel 2>/dev/null || true
    ok "sudo wheel policy already present"
  fi
}

generate_host_keys_if_needed() {
  if [ -f /etc/ssh/ssh_host_rsa_key ] ||
    [ -f /etc/ssh/ssh_host_ed25519_key ] ||
    [ -f /etc/ssh/ssh_host_ecdsa_key ]; then
    ok "SSH host keys already exist"
    return 0
  fi

  if cmd_exists ssh-keygen; then
    info "Generating SSH host keys"
    if ssh-keygen -A >/dev/null 2>&1; then
      ok "Generated SSH host keys"
    else
      warn "Failed to generate SSH host keys"
    fi
  else
    warn "ssh-keygen not found; cannot generate SSH host keys"
  fi
}

ensure_sshd_config_key() {
  key="$1"
  value="$2"
  cfg="/etc/ssh/sshd_config"

  [ -f "$cfg" ] || touch "$cfg"

  tmpf="/tmp/sshd_config.$$"
  awk -v k="$key" -v v="$value" '
        BEGIN { done=0 }
        {
            if ($0 ~ "^[#[:space:]]*" k "[[:space:]]") {
                if (!done) {
                    print k " " v
                    done=1
                }
            } else {
                print
            }
        }
        END {
            if (!done) print k " " v
        }
    ' "$cfg" >"$tmpf" && cat "$tmpf" >"$cfg"
  rm -f "$tmpf"

  ok "Ensured sshd_config: $key $value"
}

start_sshd_safely() {
  mkdir -p /etc/ssh /run/sshd /var/run/sshd

  if ! cmd_exists sshd; then
    warn "sshd not found; SSH server cannot start"
    return 0
  fi

  if ! sshd -t >/dev/null 2>&1; then
    warn "sshd configuration test failed; not starting sshd"
    return 0
  fi

  if ps 2>/dev/null | grep '[s]shd' >/dev/null 2>&1; then
    ok "sshd already appears to be running"
    return 0
  fi

  if /usr/sbin/sshd >/dev/null 2>&1 || sshd >/dev/null 2>&1; then
    ok "Started sshd"
  else
    warn "Could not start sshd automatically"
  fi
}

main() {
  require_root

  info "Updating apk indexes"
  if apk update >/dev/null 2>&1; then
    ok "apk indexes updated"
  else
    warn "apk update failed; continuing anyway"
  fi

  info "Installing requested packages"

  install_pkg_alias "git" git
  install_pkg_alias "curl" curl
  install_pkg_alias "bat" bat
  install_pkg_alias "fzf" fzf
  install_pkg_alias "nano" nano
  install_pkg_alias "neovim" neovim
  install_pkg_alias "neofetch" neofetch
  install_pkg_alias "OpenSSH server" openssh-server openssh
  install_pkg_alias "OpenSSH client" openssh-client-default openssh-client openssh
  install_pkg_alias "ncurses" ncurses
  install_pkg_alias "less" less
  install_pkg_alias "zoxide" zoxide
  install_pkg_alias "tmux" tmux
  install_pkg_alias "htop" htop
  install_pkg_alias "ripgrep" ripgrep
  install_pkg_alias "fd" fd
  install_pkg_alias "lazygit" lazygit
  install_pkg_alias "tree" tree
  install_pkg_alias "unzip" unzip
  install_pkg_alias "zip" zip
  install_pkg_alias "wget" wget
  install_pkg_alias "grep" grep
  install_pkg_alias "sed" sed
  install_pkg_alias "coreutils" coreutils
  install_pkg_alias "util-linux" util-linux
  install_pkg_alias "linux headers/tools" linux-headers linux-lts-headers linux-edge-headers
  install_pkg_alias "diffutils" diffutils
  install_pkg_alias "findutils" findutils
  install_pkg_alias "file" file
  install_pkg_alias "patch" patch
  install_pkg_alias "bash" bash
  install_pkg_alias "zsh" zsh
  install_pkg_alias "sudo" sudo
  install_pkg_alias "eza/exa" eza exa

  set_hostname_live
  set_hostname_persistent

  ensure_user
  set_passwords

  if cmd_exists zsh; then
    set_shell_in_passwd "$RABBIT_USER" "$(command -v zsh)"
  else
    warn "zsh not installed; cannot set rabbit shell to zsh"
  fi

  write_profiles

  install_shell_frameworks /root root
  install_shell_frameworks "/home/$RABBIT_USER" "$RABBIT_USER"

  write_zshrc /root root
  write_zshrc "/home/$RABBIT_USER" "$RABBIT_USER"

  if cmd_exists sudo; then
    configure_sudo
  else
    warn "sudo not installed; skipping sudo configuration"
  fi

  info "Configuring OpenSSH server"
  mkdir -p /etc/ssh
  generate_host_keys_if_needed
  ensure_sshd_config_key "AllowTcpForwarding" "yes"
  ensure_sshd_config_key "PermitRootLogin" "yes"
  start_sshd_safely

  say
  say "============================================================"
  say "Setup complete"
  say "============================================================"
  say
  say "Installed packages:"
  if [ -n "$INSTALLED_PKGS" ]; then
    say "  $INSTALLED_PKGS"
  else
    say "  (none)"
  fi
  say
  say "Skipped packages:"
  if [ -n "$SKIPPED_PKGS" ]; then
    say "  $SKIPPED_PKGS"
  else
    say "  (none)"
  fi
  say
  say "Passwords set by script:"
  say "  root: $ROOT_PASSWORD"
  say "  $RABBIT_USER: $RABBIT_PASSWORD"
  say
  say "rabbit sudo usage:"
  say "  sudo apk update"
  say "  sudo apk add jq"
  say
  say "Keep-alive command:"
  say "  cat /dev/location > /dev/null &"
  say
  say "Also remember:"
  say "  - Allow location access in iSH"
  say "  - Enable keep screen turned on in iSH settings"
  say
  say "Linux client connection over iPhone Personal Hotspot:"
  say "  1. Connect Linux to the iPhone hotspot."
  say "  2. Find the gateway with:"
  say "     ip route show default"
  say "  3. Start the SOCKS proxy tunnel with:"
  say "     ssh -D 1080 -N -C root@172.20.10.1"
  say "  4. The terminal appearing to hang is expected."
  say "  5. Linux does not have true universal global proxying and some apps need separate proxy configuration."
  say
}

main "$@"
