#!/bin/sh
# Alpine Linux / iSH setup script
# POSIX sh
# Safe to run as root
# Rabbit-owned shared shell assets; root reuses them

set -u

HOSTNAME_WANTED="iOSiSH"
RABBIT_USER="rabbit"
RABBIT_HOME="/home/$RABBIT_USER"
ROOT_PASSWORD="default"
RABBIT_PASSWORD="default"
CACHYOS_HOST="172.20.10.7"
CACHYOS_USER="rabbit"
CACHYOS_PORT="22"
ALIASES_URL="https://raw.githubusercontent.com/ADHD-exe/iOSiSH/main/.aliases"

INSTALLED_PKGS=""
SKIPPED_PKGS=""

say() { printf '%s\n' "$*"; }
info() { printf '[INFO] %s\n' "$*"; }
ok() { printf '[ OK ] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; }
err() { printf '[ERR ] %s\n' "$*"; >&2; }

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

    for p in "$@"; do
        if pkg_installed "$p"; then
            info "$label: already installed as $p"
            INSTALLED_PKGS=$(append_csv "$INSTALLED_PKGS" "$label ($p)")
            return 0
        fi
    done

    found_any=0
    for p in "$@"; do
        if pkg_exists "$p"; then
            found_any=1
            info "$label: installing $p"
            if apk add --no-cache "$p" >/dev/null 2>&1; then
                ok "$label: installed $p"
                INSTALLED_PKGS=$(append_csv "$INSTALLED_PKGS" "$label ($p)")
                return 0
            else
                warn "$label: failed to install $p"
            fi
        fi
    done

    if [ "$found_any" -eq 1 ]; then
        warn "$label: all candidate packages failed, skipping"
    else
        warn "$label: not found in Alpine repositories, skipping"
    fi

    SKIPPED_PKGS=$(append_csv "$SKIPPED_PKGS" "$label")
    return 0
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
        if adduser -D -h "$RABBIT_HOME" -s /bin/sh "$RABBIT_USER" >/dev/null 2>&1; then
            ok "Created user $RABBIT_USER"
        else
            err "Failed to create user $RABBIT_USER"
            exit 1
        fi
    fi

    mkdir -p "$RABBIT_HOME"
    chown "$RABBIT_USER:$RABBIT_USER" "$RABBIT_HOME" 2>/dev/null || true

    ensure_group_exists wheel

    if addgroup "$RABBIT_USER" wheel >/dev/null 2>&1; then
        ok "Ensured $RABBIT_USER is in wheel"
    else
        info "$RABBIT_USER may already be in wheel"
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

set_hostname_persistent() {
    printf '%s\n' "$HOSTNAME_WANTED" > /etc/hostname
    ok "Wrote /etc/hostname"

    if [ ! -f /etc/hosts ]; then
        printf '127.0.0.1\tlocalhost %s\n' "$HOSTNAME_WANTED" > /etc/hosts
        ok "Created /etc/hosts"
        return 0
    fi

    if grep -q "[[:space:]]$HOSTNAME_WANTED\$" /etc/hosts 2>/dev/null; then
        ok "/etc/hosts already contains $HOSTNAME_WANTED"
    else
        printf '127.0.0.1\tlocalhost %s\n' "$HOSTNAME_WANTED" >> /etc/hosts
        ok "Updated /etc/hosts"
    fi

    info "iSH may still report localhost internally; prompt will use /etc/hostname"
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

    if cmd_exists usermod; then
        if usermod -s "$newshell" "$usr" >/dev/null 2>&1; then
            ok "Set login shell for $usr to $newshell"
            return 0
        fi
    fi

    tmpf="/tmp/passwd.$$"
    if awk -F: -v OFS=: -v u="$usr" -v s="$newshell" '
        $1==u { $7=s }
        { print }
    ' /etc/passwd > "$tmpf"; then
        if [ -s "$tmpf" ]; then
            mv "$tmpf" /etc/passwd
            ok "Set login shell for $usr to $newshell"
        else
            rm -f "$tmpf"
            warn "Generated passwd replacement was empty; not updating /etc/passwd"
        fi
    else
        rm -f "$tmpf"
        warn "Failed to update login shell for $usr"
    fi
}

write_profiles() {
    printf '%s\n' 'exec zsh -l' > /root/.profile
    chmod 644 /root/.profile
    ok "Wrote /root/.profile"

    printf '%s\n' 'exec zsh -l' > "$RABBIT_HOME/.profile"
    chown "$RABBIT_USER:$RABBIT_USER" "$RABBIT_HOME/.profile" 2>/dev/null || true
    chmod 644 "$RABBIT_HOME/.profile"
    ok "Wrote $RABBIT_HOME/.profile"
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
    omz_dir="$RABBIT_HOME/.oh-my-zsh"
    zinit_dir="$RABBIT_HOME/.local/share/zinit/zinit.git"

    clone_or_update_repo "https://github.com/ohmyzsh/ohmyzsh.git" "$omz_dir" "Oh My Zsh for $RABBIT_USER" || true
    clone_or_update_repo "https://github.com/zdharma-continuum/zinit.git" "$zinit_dir" "Zinit for $RABBIT_USER" || true

    mkdir -p "$RABBIT_HOME/.cache/zsh" "$RABBIT_HOME/.local/share" "$RABBIT_HOME/.ssh" "$RABBIT_HOME/.config/zsh"
    rm -f "$RABBIT_HOME"/.zcompdump* 2>/dev/null || true

    chown -R "$RABBIT_USER:$RABBIT_USER" \
        "$RABBIT_HOME/.oh-my-zsh" \
        "$RABBIT_HOME/.local" \
        "$RABBIT_HOME/.cache" \
        "$RABBIT_HOME/.ssh" \
        "$RABBIT_HOME/.config" 2>/dev/null || true

    chmod 700 "$RABBIT_HOME/.ssh" 2>/dev/null || true
}

install_shared_aliases() {
    alias_dir="$RABBIT_HOME/.config/zsh"
    alias_file="$alias_dir/.aliases"

    mkdir -p "$alias_dir"

    if [ -f ".aliases" ]; then
        cp -f ".aliases" "$alias_file"
        chown "$RABBIT_USER:$RABBIT_USER" "$alias_file" 2>/dev/null || true
        chmod 644 "$alias_file" 2>/dev/null || true
        ok "Installed shared aliases from local repo copy"
        return 0
    fi

    if [ -f "$(dirname "$0")/.aliases" ]; then
        cp -f "$(dirname "$0")/.aliases" "$alias_file"
        chown "$RABBIT_USER:$RABBIT_USER" "$alias_file" 2>/dev/null || true
        chmod 644 "$alias_file" 2>/dev/null || true
        ok "Installed shared aliases from script directory"
        return 0
    fi

    if cmd_exists curl; then
        if curl -fsSL "$ALIASES_URL" -o "$alias_file"; then
            chown "$RABBIT_USER:$RABBIT_USER" "$alias_file" 2>/dev/null || true
            chmod 644 "$alias_file" 2>/dev/null || true
            ok "Installed shared aliases from GitHub"
            return 0
        fi
    fi

    warn "Failed to install shared aliases"
    return 1
}

write_shared_zshrc() {
    zshrc="$RABBIT_HOME/.zshrc"

    cat > "$zshrc" <<EOF
# Generated by Alpine/iSH setup script
# Rabbit-owned shared Zsh config; reused by root via symlink

export SHARED_HOME="$RABBIT_HOME"
export LANG="\${LANG:-C.UTF-8}"
export EDITOR="\${EDITOR:-nvim}"
export VISUAL="\${VISUAL:-nvim}"
export PAGER="\${PAGER:-less}"
export LESS="-FRX"

# Keep history per-user even though the rest of the shell stack is shared.
export HISTFILE="\$HOME/.zsh_history"
export HISTSIZE=50000
export SAVEHIST=50000

# Shared shell framework locations always come from rabbit's home.
export ZSH="\$SHARED_HOME/.oh-my-zsh"
export ZINIT_HOME="\$SHARED_HOME/.local/share/zinit/zinit.git"

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
setopt NULL_GLOB

mkdir -p "\$HOME/.cache/zsh" "\$HOME/.ssh"
mkdir -p "\$SHARED_HOME/.config/zsh" "\$SHARED_HOME/.local/share"

autoload -Uz compinit
rm -f "\$HOME"/.zcompdump*
compinit -i -d "\$HOME/.cache/zsh/zcompdump-\$(id -un 2>/dev/null)"

HOST_DISPLAY="\$(cat /etc/hostname 2>/dev/null || echo localhost)"
if [ "\$(id -u 2>/dev/null)" = "0" ]; then
    USER_COLOR="red"
else
    USER_COLOR="cyan"
fi
PROMPT='%F{'\$USER_COLOR'}%n@'"\$HOST_DISPLAY"'%f:%F{yellow}%~%f %# '
RPROMPT='%(?..%F{red}[%?]%f)'

[ -r "\$SHARED_HOME/.config/zsh/.aliases" ] && . "\$SHARED_HOME/.config/zsh/.aliases"

if command -v zoxide >/dev/null 2>&1; then
    eval "\$(zoxide init zsh)"
fi

[ -r /usr/share/fzf/key-bindings.zsh ] && . /usr/share/fzf/key-bindings.zsh
[ -r /usr/share/fzf/completion.zsh ] && . /usr/share/fzf/completion.zsh

[ -r "\$ZSH/lib/git.zsh" ] && . "\$ZSH/lib/git.zsh"
[ -r "\$ZSH/lib/history.zsh" ] && . "\$ZSH/lib/history.zsh"
[ -r "\$ZSH/lib/completion.zsh" ] && . "\$ZSH/lib/completion.zsh"
[ -r "\$ZSH/plugins/git/git.plugin.zsh" ] && . "\$ZSH/plugins/git/git.plugin.zsh"
[ -r "\$ZSH/plugins/colored-man-pages/colored-man-pages.plugin.zsh" ] && . "\$ZSH/plugins/colored-man-pages/colored-man-pages.plugin.zsh"
[ -r "\$ZSH/plugins/command-not-found/command-not-found.plugin.zsh" ] && . "\$ZSH/plugins/command-not-found/command-not-found.plugin.zsh"
[ -r "\$ZSH/plugins/history/history.plugin.zsh" ] && . "\$ZSH/plugins/history/history.plugin.zsh"

if [ -r "\$ZINIT_HOME/zinit.zsh" ]; then
    . "\$ZINIT_HOME/zinit.zsh"

    zinit ice lucid wait'0' blockf
    zinit light zsh-users/zsh-completions

    zinit ice lucid wait'0'
    zinit light zsh-users/zsh-autosuggestions

    zinit ice lucid wait'0'
    zinit light zsh-users/zsh-history-substring-search

    zinit ice lucid wait'0'
    zinit light zdharma-continuum/fast-syntax-highlighting

    if [ ! -d "\${ZINIT[PLUGINS_DIR]}/zdharma-continuum---fast-syntax-highlighting" ]; then
        zinit ice lucid wait'0'
        zinit light zsh-users/zsh-syntax-highlighting
    fi
fi

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
zstyle ':completion:*' list-colors "\${(s.:.)LS_COLORS}"

if typeset -f history-substring-search-up >/dev/null 2>&1; then
    bindkey '^[[A' history-substring-search-up
    bindkey '^[[B' history-substring-search-down
fi

bindkey -e
umask 022
EOF

    chown "$RABBIT_USER:$RABBIT_USER" "$zshrc" 2>/dev/null || true
    chmod 644 "$zshrc"
    ok "Wrote shared Zsh config: $zshrc"
}

ensure_shared_ssh_keypair() {
    key="$RABBIT_HOME/.ssh/id_ed25519"

    mkdir -p "$RABBIT_HOME/.ssh"
    if [ ! -f "$key" ]; then
        if cmd_exists ssh-keygen; then
            if ssh-keygen -q -t ed25519 -N '' -f "$key" >/dev/null 2>&1; then
                ok "Generated shared SSH key for $RABBIT_USER"
            else
                warn "Failed to generate shared SSH key"
            fi
        else
            warn "ssh-keygen not found; cannot create SSH key"
        fi
    else
        ok "Shared SSH key already exists"
    fi

    chown -R "$RABBIT_USER:$RABBIT_USER" "$RABBIT_HOME/.ssh" 2>/dev/null || true
    chmod 700 "$RABBIT_HOME/.ssh" 2>/dev/null || true
    find "$RABBIT_HOME/.ssh" -type f -exec chmod 600 {} \; 2>/dev/null || true
    [ -f "$RABBIT_HOME/.ssh/id_ed25519.pub" ] && chmod 644 "$RABBIT_HOME/.ssh/id_ed25519.pub" 2>/dev/null || true
}

write_shared_ssh_config() {
    cfg="$RABBIT_HOME/.ssh/config"

    mkdir -p "$RABBIT_HOME/.ssh"
    cat > "$cfg" <<EOF
Host *
    ServerAliveInterval 30
    ServerAliveCountMax 3
    TCPKeepAlive yes

Host cachyos
    HostName $CACHYOS_HOST
    User $CACHYOS_USER
    Port $CACHYOS_PORT
    PreferredAuthentications publickey,password
    PubkeyAuthentication yes
    IdentitiesOnly yes
    IdentityFile $RABBIT_HOME/.ssh/id_ed25519

Host cachyos-tunnel
    HostName $CACHYOS_HOST
    User $CACHYOS_USER
    Port $CACHYOS_PORT
    PreferredAuthentications publickey,password
    PubkeyAuthentication yes
    IdentitiesOnly yes
    IdentityFile $RABBIT_HOME/.ssh/id_ed25519
    DynamicForward 1080
    Compression yes
    ExitOnForwardFailure yes
EOF
    chmod 600 "$cfg"
    chown -R "$RABBIT_USER:$RABBIT_USER" "$RABBIT_HOME/.ssh" 2>/dev/null || true
    ok "Wrote shared SSH client config"
}

link_path_force() {
    src="$1"
    dst="$2"

    parent="$(dirname "$dst")"
    mkdir -p "$parent"

    rm -rf "$dst"
    ln -s "$src" "$dst"
}

link_root_to_rabbit_assets() {
    mkdir -p /root /root/.config /root/.local/share /root/.cache /root/.ssh

    # Shared shell stack
    link_path_force "$RABBIT_HOME/.zshrc" /root/.zshrc
    link_path_force "$RABBIT_HOME/.oh-my-zsh" /root/.oh-my-zsh
    mkdir -p /root/.local/share
    link_path_force "$RABBIT_HOME/.local/share/zinit" /root/.local/share/zinit
    mkdir -p /root/.config
    link_path_force "$RABBIT_HOME/.config/zsh" /root/.config/zsh

    # Shared SSH assets
    link_path_force "$RABBIT_HOME/.ssh/config" /root/.ssh/config
    link_path_force "$RABBIT_HOME/.ssh/id_ed25519" /root/.ssh/id_ed25519
    link_path_force "$RABBIT_HOME/.ssh/id_ed25519.pub" /root/.ssh/id_ed25519.pub

    chmod 700 /root/.ssh 2>/dev/null || true

    ok "Linked root to rabbit-owned shared shell and SSH assets"
}

configure_sudo() {
    mkdir -p /etc/sudoers.d
    printf '%%wheel ALL=(ALL) ALL\n' > /etc/sudoers.d/wheel
    chmod 440 /etc/sudoers.d/wheel
    ok "Configured sudo for wheel group"
}

configure_doas() {
    printf 'permit persist :wheel\n' > /etc/doas.conf
    chmod 0400 /etc/doas.conf
    ok "Configured doas for wheel group"
}

generate_host_keys_if_needed() {
    if [ -f /etc/ssh/ssh_host_ed25519_key ] || [ -f /etc/ssh/ssh_host_rsa_key ]; then
        ok "SSH host keys already exist"
        return 0
    fi

    if cmd_exists ssh-keygen; then
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

    if grep -Eq "^[#[:space:]]*${key}[[:space:]]+" "$cfg" 2>/dev/null; then
        tmpf="/tmp/sshd_config.$$"
        if awk -v k="$key" -v v="$value" '
            BEGIN { done=0 }
            {
                if ($0 ~ "^[#[:space:]]*" k "[[:space:]]+") {
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
        ' "$cfg" > "$tmpf"; then
            mv "$tmpf" "$cfg"
        else
            rm -f "$tmpf"
            warn "Failed updating $key in $cfg"
            return 1
        fi
    else
        printf '%s %s\n' "$key" "$value" >> "$cfg"
    fi

    ok "Ensured sshd_config: $key $value"
}

configure_openrc() {
    if ! cmd_exists rc-update; then
        warn "OpenRC not available; skipping rc-update"
        return 0
    fi

    if rc-update add sshd default >/dev/null 2>&1; then
        ok "Added sshd to OpenRC default runlevel"
    else
        warn "Could not add sshd to OpenRC default runlevel"
    fi
}

start_sshd_safely() {
    if cmd_exists service; then
        if service sshd restart >/dev/null 2>&1 || service sshd start >/dev/null 2>&1; then
            ok "Started sshd via service"
            return 0
        fi
    fi

    if cmd_exists rc-service; then
        if rc-service sshd restart >/dev/null 2>&1 || rc-service sshd start >/dev/null 2>&1; then
            ok "Started sshd via rc-service"
            return 0
        fi
    fi

    if cmd_exists sshd; then
        if pkill sshd >/dev/null 2>&1 || true; then :; fi
        if /usr/sbin/sshd >/dev/null 2>&1 || sshd >/dev/null 2>&1; then
            ok "Started sshd directly"
        else
            warn "Could not start sshd automatically"
        fi
    fi
}

fix_permissions() {
    chown "$RABBIT_USER:$RABBIT_USER" "$RABBIT_HOME" 2>/dev/null || true
    chmod 755 "$RABBIT_HOME" 2>/dev/null || true

    for d in \
        "$RABBIT_HOME/.oh-my-zsh" \
        "$RABBIT_HOME/.local" \
        "$RABBIT_HOME/.cache" \
        "$RABBIT_HOME/.config"
    do
        if [ -e "$d" ]; then
            chown -R "$RABBIT_USER:$RABBIT_USER" "$d" 2>/dev/null || true
            chmod -R go-w "$d" 2>/dev/null || true
        fi
    done

    if [ -d "$RABBIT_HOME/.ssh" ]; then
        chown -R "$RABBIT_USER:$RABBIT_USER" "$RABBIT_HOME/.ssh" 2>/dev/null || true
        chmod 700 "$RABBIT_HOME/.ssh" 2>/dev/null || true
        find "$RABBIT_HOME/.ssh" -type f -exec chmod 600 {} \; 2>/dev/null || true
        [ -f "$RABBIT_HOME/.ssh/id_ed25519.pub" ] && chmod 644 "$RABBIT_HOME/.ssh/id_ed25519.pub" 2>/dev/null || true
    fi

    chown root:root /root 2>/dev/null || true
    chmod 700 /root 2>/dev/null || true
    chmod 700 /root/.ssh 2>/dev/null || true

    ok "Fixed permissions for shared rabbit assets and /root links"
}

prime_zsh_for_user() {
    owner_user="$1"

    if [ "$owner_user" = "root" ]; then
        if zsh -ic 'exit 0' >/dev/null 2>&1; then
            ok "Primed Zsh for root"
        else
            warn "Could not fully prime Zsh for root on first pass"
        fi
    else
        if su - "$owner_user" -c 'zsh -ic "exit 0"' >/dev/null 2>&1; then
            ok "Primed Zsh for $owner_user"
        else
            warn "Could not fully prime Zsh for $owner_user on first pass"
        fi
    fi
}

post_run_self_test() {
    say
    say "Post-run self-test:"

    if [ -L /root/.zshrc ] && [ "$(readlink /root/.zshrc)" = "$RABBIT_HOME/.zshrc" ]; then
        say "  [OK] root .zshrc symlinked to rabbit"
    else
        say "  [WARN] root .zshrc is not symlinked to rabbit"
    fi

    if [ -L /root/.ssh/config ] && [ "$(readlink /root/.ssh/config)" = "$RABBIT_HOME/.ssh/config" ]; then
        say "  [OK] root SSH config symlinked to rabbit"
    else
        say "  [WARN] root SSH config is not symlinked to rabbit"
    fi

    if zsh -lc 'exit 0' >/dev/null 2>&1; then
        say "  [OK] root zsh startup"
    else
        say "  [WARN] root zsh startup"
    fi

    if su - "$RABBIT_USER" -c 'zsh -lc "exit 0"' >/dev/null 2>&1; then
        say "  [OK] rabbit zsh startup"
    else
        say "  [WARN] rabbit zsh startup"
    fi

    if ssh -G 127.0.0.1 >/dev/null 2>&1; then
        say "  [OK] SSH client config parse"
    else
        say "  [WARN] SSH client config parse"
    fi

    if sshd -t >/dev/null 2>&1; then
        say "  [OK] SSH server config parse"
    else
        say "  [WARN] SSH server config parse"
    fi

    if su - "$RABBIT_USER" -c 'sudo -l' >/dev/null 2>&1; then
        say "  [OK] sudo check"
    else
        say "  [INFO] sudo check may require interactive auth"
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
    install_pkg_alias "wget" wget
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
    install_pkg_alias "doas" doas
    install_pkg_alias "shadow" shadow
    install_pkg_alias "openrc" openrc
    install_pkg_alias "iptables-openrc" iptables-openrc
    install_pkg_alias "util-linux-openrc" util-linux-openrc
    install_pkg_alias "exa" exa

    set_hostname_persistent
    ensure_user
    set_passwords

    if cmd_exists zsh; then
        set_shell_in_passwd root "$(command -v zsh)"
        set_shell_in_passwd "$RABBIT_USER" "$(command -v zsh)"
    else
        warn "zsh not installed; cannot set login shells"
    fi

    write_profiles

    install_shell_frameworks
    install_shared_aliases
    write_shared_zshrc
    ensure_shared_ssh_keypair
    write_shared_ssh_config
    link_root_to_rabbit_assets

    if cmd_exists sudo; then
        configure_sudo
    else
        warn "sudo not installed; skipping sudo configuration"
    fi

    if cmd_exists doas; then
        configure_doas
    else
        warn "doas not installed; skipping doas configuration"
    fi

    info "Configuring OpenSSH server"
    mkdir -p /etc/ssh /root/.ssh "$RABBIT_HOME/.ssh"
    chmod 700 /root/.ssh "$RABBIT_HOME/.ssh" 2>/dev/null || true
    chown "$RABBIT_USER:$RABBIT_USER" "$RABBIT_HOME/.ssh" 2>/dev/null || true

    generate_host_keys_if_needed
    ensure_sshd_config_key "AllowTcpForwarding" "yes"
    ensure_sshd_config_key "PermitRootLogin" "yes"
    ensure_sshd_config_key "PasswordAuthentication" "yes"
    ensure_sshd_config_key "PubkeyAuthentication" "yes"
    ensure_sshd_config_key "PermitEmptyPasswords" "no"

    configure_openrc
    start_sshd_safely

    fix_permissions

    prime_zsh_for_user root
    prime_zsh_for_user "$RABBIT_USER"

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
    say "Shared shell owner:"
    say "  $RABBIT_USER ($RABBIT_HOME)"
    say
    say "Shared shell assets:"
    say "  $RABBIT_HOME/.zshrc"
    say "  $RABBIT_HOME/.config/zsh/.aliases"
    say "  $RABBIT_HOME/.oh-my-zsh"
    say "  $RABBIT_HOME/.local/share/zinit"
    say
    say "Shared SSH assets:"
    say "  $RABBIT_HOME/.ssh/config"
    say "  $RABBIT_HOME/.ssh/id_ed25519.pub"
    say
    say "Root reuses rabbit assets via symlinks under /root"
    say
    say "Privilege escalation:"
    say "  sudo apk update"
    say "  doas apk update"
    say
    say "SSH client aliases:"
    say "  ssh cachyos"
    say "  ssh -N cachyos-tunnel"
    say
    say "SSH server config ensured in /etc/ssh/sshd_config:"
    say "  AllowTcpForwarding yes"
    say "  PermitRootLogin yes"
    say "  PasswordAuthentication yes"
    say "  PubkeyAuthentication yes"
    say "  PermitEmptyPasswords no"
    say
    say "OpenRC:"
    say "  sshd will be added where applicable"
    say "  iSH may still limit full init behavior"
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

    post_run_self_test
}

main "$@"
