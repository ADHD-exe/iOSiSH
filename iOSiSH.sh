#!/bin/sh
# iOSiSH bootstrap for Alpine Linux on iSH
# Purpose:
#   1) Configure iSH as an SSH server reachable from a home PC over iPhone hotspot
#   2) Configure iSH as an SSH client for connecting back to a home PC (ssh-home)
#   3) Generate PC-side SSH config snippets for:
#        - ish-hotspot : SOCKS5 proxy from home PC through iSH
#        - ssh-ish     : normal SSH login from home PC into iSH
#
# Run as root on a fresh iSH install.

set -u

ISH_HOSTNAME="${ISH_HOSTNAME:-iOSiSH}"
PRIMARY_USER="${PRIMARY_USER:-rabbit}"
PRIMARY_HOME="${PRIMARY_HOME:-}"
PRIMARY_PASSWORD="${PRIMARY_PASSWORD:-}"
ROOT_PASSWORD="${ROOT_PASSWORD:-}"
ISH_LISTEN_PORT="${ISH_LISTEN_PORT:-22}"
ISH_HOTSPOT_IP="${ISH_HOTSPOT_IP:-172.20.10.10}"

HOME_PC_HOST="${HOME_PC_HOST:-}"
HOME_PC_PORT="${HOME_PC_PORT:-22}"
HOME_PC_USER="${HOME_PC_USER:-rabbit}"

PC_SOCKS_PORT="${PC_SOCKS_PORT:-1080}"

NONINTERACTIVE="${NONINTERACTIVE:-0}"
REPO_RAW_BASE="${REPO_RAW_BASE:-https://raw.githubusercontent.com/ADHD-exe/iOSiSH/main}"

INSTALLED_PKGS=""
SKIPPED_PKGS=""
DOCS_INSTALLED_PKGS=""
DOCS_SKIPPED_PKGS=""

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

cmd_exists() { command -v "$1" >/dev/null 2>&1; }
pkg_installed() { apk info -e "$1" >/dev/null 2>&1; }
pkg_exists() { apk search -x "$1" >/dev/null 2>&1; }

populate_defaults() {
    if [ -z "${PRIMARY_HOME:-}" ] && [ -n "${PRIMARY_USER:-}" ]; then
        PRIMARY_HOME="/home/$PRIMARY_USER"
    fi
}

tty_available() { [ -r /dev/tty ] && [ -w /dev/tty ]; }

prompt_text() {
    prompt="$1"
    default="${2:-}"
    answer=""
    if tty_available; then
        if [ -n "$default" ]; then
            printf '%s [%s]: ' "$prompt" "$default" > /dev/tty
        else
            printf '%s: ' "$prompt" > /dev/tty
        fi
        IFS= read -r answer < /dev/tty || true
    else
        if [ -n "$default" ]; then
            printf '%s [%s]: ' "$prompt" "$default"
        else
            printf '%s: ' "$prompt"
        fi
        IFS= read -r answer || true
    fi
    [ -n "$answer" ] && printf '%s' "$answer" || printf '%s' "$default"
}

prompt_password_once() {
    prompt="$1"
    pw=""
    if tty_available; then
        printf '%s: ' "$prompt" > /dev/tty
        stty -echo < /dev/tty 2>/dev/null || true
        IFS= read -r pw < /dev/tty || true
        stty echo < /dev/tty 2>/dev/null || true
        printf '\n' > /dev/tty
    else
        printf '%s: ' "$prompt" >&2
        stty -echo 2>/dev/null || true
        IFS= read -r pw || true
        stty echo 2>/dev/null || true
        printf '\n' >&2
    fi
    printf '%s' "$pw"
}

prompt_password_confirmed() {
    label="$1"
    while :; do
        pw1="$(prompt_password_once "Set password for $label")"
        [ -n "$pw1" ] || { warn "Password cannot be empty."; continue; }
        pw2="$(prompt_password_once "Confirm password for $label")"
        [ "$pw1" = "$pw2" ] && { printf '%s' "$pw1"; return 0; }
        warn "Passwords did not match."
    done
}

confirm_yes() {
    prompt="$1"
    default="${2:-N}"
    answer=""
    if tty_available; then
        case "$default" in
            Y|y) printf '%s [Y/n]: ' "$prompt" > /dev/tty ;;
            *) printf '%s [y/N]: ' "$prompt" > /dev/tty ;;
        esac
        IFS= read -r answer < /dev/tty || true
    else
        case "$default" in
            Y|y) printf '%s [Y/n]: ' "$prompt" ;;
            *) printf '%s [y/N]: ' "$prompt" ;;
        esac
        IFS= read -r answer || true
    fi
    [ -n "$answer" ] || answer="$default"
    case "$answer" in
        Y|y|yes|YES|Yes) return 0 ;;
        *) return 1 ;;
    esac
}

is_valid_username() {
    case "$1" in
        ""|*[!a-z0-9_-]*|[-_]* ) return 1 ;;
        * ) return 0 ;;
    esac
}

is_valid_hostname() {
    case "$1" in
        ""|*[!A-Za-z0-9._-]* ) return 1 ;;
        * ) return 0 ;;
    esac
}

is_valid_abs_path() {
    case "$1" in
        /* ) return 0 ;;
        * ) return 1 ;;
    esac
}

is_valid_port() {
    case "$1" in
        ""|*[!0-9]* ) return 1 ;;
    esac
    [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

collect_config() {
    populate_defaults
    [ "$NONINTERACTIVE" = "1" ] && return 0

    say ""
    say "This script sets up 3 SSH workflows:"
    say "  1) ish-hotspot : home PC -> iSH SOCKS5 over iPhone hotspot"
    say "  2) ssh-home    : iSH -> home PC SSH client profile"
    say "  3) ssh-ish     : home PC -> iSH normal SSH login"
    say ""

    while :; do
        ISH_HOSTNAME="$(prompt_text "iSH hostname" "$ISH_HOSTNAME")"
        is_valid_hostname "$ISH_HOSTNAME" && break
        warn "Invalid hostname."
    done

    while :; do
        old_user="$PRIMARY_USER"
        PRIMARY_USER="$(prompt_text "Primary username" "$PRIMARY_USER")"
        is_valid_username "$PRIMARY_USER" || { warn "Invalid username."; continue; }
        if [ -z "$PRIMARY_HOME" ] || [ "$PRIMARY_HOME" = "/home/$old_user" ]; then
            PRIMARY_HOME="/home/$PRIMARY_USER"
        fi
        break
    done

    while :; do
        PRIMARY_HOME="$(prompt_text "Primary home directory" "$PRIMARY_HOME")"
        is_valid_abs_path "$PRIMARY_HOME" && break
        warn "Use an absolute path like /home/$PRIMARY_USER"
    done

    PRIMARY_PASSWORD="$(prompt_password_confirmed "$PRIMARY_USER")"
    ROOT_PASSWORD="$(prompt_password_confirmed "root")"

    while :; do
        ISH_LISTEN_PORT="$(prompt_text "iSH sshd listen port" "$ISH_LISTEN_PORT")"
        is_valid_port "$ISH_LISTEN_PORT" && break
        warn "Port must be 1-65535."
    done

    ISH_HOTSPOT_IP="$(prompt_text "Expected iSH hotspot IP used by the home PC" "$ISH_HOTSPOT_IP")"

    HOME_PC_HOST="$(prompt_text "Home PC SSH host/IP for ssh-home (leave blank to skip ssh-home profile)" "$HOME_PC_HOST")"

    if [ -n "$HOME_PC_HOST" ]; then
        HOME_PC_USER="$(prompt_text "Home PC SSH username for ssh-home" "$HOME_PC_USER")"
        while :; do
            HOME_PC_PORT="$(prompt_text "Home PC SSH port for ssh-home" "$HOME_PC_PORT")"
            is_valid_port "$HOME_PC_PORT" && break
            warn "Port must be 1-65535."
        done
    fi

    while :; do
        PC_SOCKS_PORT="$(prompt_text "SOCKS5 port to use on the home PC for ish-hotspot" "$PC_SOCKS_PORT")"
        is_valid_port "$PC_SOCKS_PORT" && break
        warn "Port must be 1-65535."
    done

    say ""
    say "Summary"
    say "-------"
    say "iSH hostname:         $ISH_HOSTNAME"
    say "Primary user:         $PRIMARY_USER"
    say "Primary home:         $PRIMARY_HOME"
    say "iSH sshd listen port: $ISH_LISTEN_PORT"
    say "iSH hotspot IP:       $ISH_HOTSPOT_IP"
    if [ -n "$HOME_PC_HOST" ]; then
        say "ssh-home target:      $HOME_PC_USER@$HOME_PC_HOST:$HOME_PC_PORT"
    else
        say "ssh-home target:      skipped"
    fi
    say "Home PC SOCKS port:   $PC_SOCKS_PORT"
    say ""
    confirm_yes "Proceed with this configuration" "Y" || { err "Aborted."; exit 1; }
}

validate_config() {
    populate_defaults
    is_valid_hostname "$ISH_HOSTNAME" || { err "Invalid ISH_HOSTNAME"; exit 1; }
    is_valid_username "$PRIMARY_USER" || { err "Invalid PRIMARY_USER"; exit 1; }
    is_valid_abs_path "$PRIMARY_HOME" || { err "Invalid PRIMARY_HOME"; exit 1; }
    [ -n "$PRIMARY_PASSWORD" ] || { err "PRIMARY_PASSWORD cannot be empty"; exit 1; }
    [ -n "$ROOT_PASSWORD" ] || { err "ROOT_PASSWORD cannot be empty"; exit 1; }
    is_valid_port "$ISH_LISTEN_PORT" || { err "Invalid ISH_LISTEN_PORT"; exit 1; }
    is_valid_port "$PC_SOCKS_PORT" || { err "Invalid PC_SOCKS_PORT"; exit 1; }
    if [ -n "$HOME_PC_HOST" ]; then
        [ -n "$HOME_PC_USER" ] || { err "HOME_PC_USER required when HOME_PC_HOST is set"; exit 1; }
        is_valid_port "$HOME_PC_PORT" || { err "Invalid HOME_PC_PORT"; exit 1; }
    fi
}

pkg_install_alias() {
    label="$1"; shift
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
            fi
            warn "$label: failed to install $p"
        fi
    done
    [ "$found_any" -eq 1 ] && warn "$label: all candidates failed" || warn "$label: package not found"
    SKIPPED_PKGS=$(append_csv "$SKIPPED_PKGS" "$label")
}

install_doc_package() {
    doc_pkg="$1"
    source_pkg="$2"
    if pkg_installed "$doc_pkg"; then
        DOCS_INSTALLED_PKGS=$(append_csv "$DOCS_INSTALLED_PKGS" "$source_pkg -> $doc_pkg")
        return 0
    fi
    pkg_exists "$doc_pkg" || return 1
    if apk add --no-cache "$doc_pkg" >/dev/null 2>&1; then
        DOCS_INSTALLED_PKGS=$(append_csv "$DOCS_INSTALLED_PKGS" "$source_pkg -> $doc_pkg")
        return 0
    fi
    return 1
}

install_docs_for_pkg() {
    pkg="$1"
    case "$pkg" in
        ""|*-doc|mandoc|man-pages|docs) return 0 ;;
    esac
    case "$pkg" in
        openssh|openssh-server|openssh-client|openssh-client-default) install_doc_package "openssh-doc" "$pkg" && return 0 ;;
        python3|py3-pip|py3-setuptools) install_doc_package "python3-doc" "$pkg" && return 0 ;;
        nodejs|npm) install_doc_package "nodejs-doc" "$pkg" && return 0 ;;
        util-linux|util-linux-openrc) install_doc_package "util-linux-doc" "$pkg" && return 0 ;;
        openrc|iptables-openrc) install_doc_package "openrc-doc" "$pkg" && return 0 ;;
        zsh|bash|less|neovim|git|tmux|curl|wget|nano|grep|sed|coreutils|findutils|diffutils|patch|file|jq)
            install_doc_package "${pkg}-doc" "$pkg" && return 0
            ;;
    esac
    install_doc_package "${pkg}-doc" "$pkg" && return 0
    DOCS_SKIPPED_PKGS=$(append_csv "$DOCS_SKIPPED_PKGS" "$pkg")
}

install_docs_for_installed_packages() {
    install_doc_package "mandoc" "manual reader" || true
    install_doc_package "man-pages" "system manpages" || true
    install_doc_package "less-doc" "less" || true
    for pkg in $(apk info 2>/dev/null); do
        install_docs_for_pkg "$pkg"
    done
}

require_root() {
    [ "$(id -u)" = "0" ] || { err "Run as root."; exit 1; }
}

ensure_group_exists() {
    grp="$1"
    grep -q "^${grp}:" /etc/group 2>/dev/null && return 0
    addgroup "$grp" >/dev/null 2>&1 && ok "Created group: $grp" || warn "Could not create group: $grp"
}

ensure_primary_user() {
    if id "$PRIMARY_USER" >/dev/null 2>&1; then
        ok "User $PRIMARY_USER already exists"
    else
        adduser -D -h "$PRIMARY_HOME" -s /bin/sh "$PRIMARY_USER" >/dev/null 2>&1 || {
            err "Failed to create user $PRIMARY_USER"
            exit 1
        }
        ok "Created user $PRIMARY_USER"
    fi
    mkdir -p "$PRIMARY_HOME"
    chown "$PRIMARY_USER:$PRIMARY_USER" "$PRIMARY_HOME" 2>/dev/null || true
    ensure_group_exists wheel
    addgroup "$PRIMARY_USER" wheel >/dev/null 2>&1 || true
}

set_passwords() {
    if cmd_exists chpasswd; then
        printf 'root:%s\n%s:%s\n' "$ROOT_PASSWORD" "$PRIMARY_USER" "$PRIMARY_PASSWORD" | chpasswd >/dev/null 2>&1 \
            && ok "Set passwords for root and $PRIMARY_USER" \
            || warn "Failed to set passwords"
    else
        warn "chpasswd not found"
    fi
}

set_hostname_files() {
    printf '%s\n' "$ISH_HOSTNAME" > /etc/hostname
    if [ ! -f /etc/hosts ]; then
        printf '127.0.0.1\tlocalhost %s\n' "$ISH_HOSTNAME" > /etc/hosts
    elif ! grep -q "[[:space:]]$ISH_HOSTNAME\$" /etc/hosts 2>/dev/null; then
        printf '127.0.0.1\tlocalhost %s\n' "$ISH_HOSTNAME" >> /etc/hosts
    fi
    ok "Updated hostname files"
}

set_shell_in_passwd() {
    usr="$1"
    newshell="$2"
    grep -q "^${usr}:" /etc/passwd 2>/dev/null || return 0
    current_shell="$(awk -F: -v u="$usr" '$1==u {print $7}' /etc/passwd 2>/dev/null)"
    [ "$current_shell" = "$newshell" ] && return 0
    if cmd_exists usermod; then
        usermod -s "$newshell" "$usr" >/dev/null 2>&1 && return 0
    fi
    tmpf="/tmp/passwd.$$"
    awk -F: -v OFS=: -v u="$usr" -v s="$newshell" '$1==u {$7=s} {print}' /etc/passwd > "$tmpf" && mv "$tmpf" /etc/passwd
}

write_profiles() {
    printf '%s\n' 'exec zsh -l' > /root/.profile
    printf '%s\n' 'exec zsh -l' > "$PRIMARY_HOME/.profile"
    chown "$PRIMARY_USER:$PRIMARY_USER" "$PRIMARY_HOME/.profile" 2>/dev/null || true
}

clone_or_update_repo() {
    repo="$1"; dest="$2"; label="$3"
    [ -d "$(dirname "$dest")" ] || mkdir -p "$(dirname "$dest")"
    if [ -d "$dest/.git" ]; then
        ok "$label already present"
        return 0
    fi
    cmd_exists git || { warn "git missing: cannot install $label"; return 1; }
    git clone --depth=1 "$repo" "$dest" >/dev/null 2>&1 && ok "Installed $label" || warn "Failed to install $label"
}

install_shell_frameworks() {
    clone_or_update_repo "https://github.com/ohmyzsh/ohmyzsh.git" "$PRIMARY_HOME/.oh-my-zsh" "Oh My Zsh" || true
    clone_or_update_repo "https://github.com/zdharma-continuum/zinit.git" "$PRIMARY_HOME/.local/share/zinit/zinit.git" "Zinit" || true
    mkdir -p "$PRIMARY_HOME/.cache/zsh" "$PRIMARY_HOME/.local/share" "$PRIMARY_HOME/.ssh" "$PRIMARY_HOME/.config/zsh"
    rm -f "$PRIMARY_HOME"/.zcompdump* 2>/dev/null || true
    chown -R "$PRIMARY_USER:$PRIMARY_USER" "$PRIMARY_HOME/.oh-my-zsh" "$PRIMARY_HOME/.local" "$PRIMARY_HOME/.cache" "$PRIMARY_HOME/.ssh" "$PRIMARY_HOME/.config" 2>/dev/null || true
    chmod 700 "$PRIMARY_HOME/.ssh" 2>/dev/null || true
}

download_text() {
    url="$1"
    if cmd_exists curl; then
        curl -fsSL "$url"
        return $?
    fi
    if cmd_exists wget; then
        wget -qO- "$url"
        return $?
    fi
    return 1
}

script_dir() {
    case "$0" in
        */*) cd "$(dirname "$0")" 2>/dev/null && pwd -P ;;
        *) pwd -P ;;
    esac
}

install_repo_shell_assets() {
    src_dir="$(script_dir)"
    tmp_zshrc="/tmp/iosish.zshrc.$$"
    tmp_aliases="/tmp/iosish.aliases.$$"
    dst_zshrc="$PRIMARY_HOME/.zshrc"
    dst_aliases="$PRIMARY_HOME/.config/zsh/.aliases"

    rm -f "$tmp_zshrc" "$tmp_aliases"
    mkdir -p "$(dirname "$dst_aliases")"

    if [ -f "$src_dir/.zshrc" ] && [ -f "$src_dir/.aliases" ]; then
        cp "$src_dir/.zshrc" "$tmp_zshrc" || { err "Failed to stage .zshrc from $src_dir"; exit 1; }
        cp "$src_dir/.aliases" "$tmp_aliases" || { err "Failed to stage .aliases from $src_dir"; exit 1; }
        info "Using bundled .zshrc and .aliases from $src_dir"
    else
        download_text "$REPO_RAW_BASE/.zshrc" > "$tmp_zshrc" || { err "Failed to download .zshrc from $REPO_RAW_BASE"; rm -f "$tmp_zshrc" "$tmp_aliases"; exit 1; }
        download_text "$REPO_RAW_BASE/.aliases" > "$tmp_aliases" || { err "Failed to download .aliases from $REPO_RAW_BASE"; rm -f "$tmp_zshrc" "$tmp_aliases"; exit 1; }
        info "Downloaded .zshrc and .aliases from $REPO_RAW_BASE"
    fi

    sed "s|__PRIMARY_HOME__|$PRIMARY_HOME|g" "$tmp_zshrc" > "$dst_zshrc" || { err "Failed to render .zshrc"; rm -f "$tmp_zshrc" "$tmp_aliases"; exit 1; }
    cp "$tmp_aliases" "$dst_aliases" || { err "Failed to install .aliases"; rm -f "$tmp_zshrc" "$tmp_aliases"; exit 1; }

    chown "$PRIMARY_USER:$PRIMARY_USER" "$dst_zshrc" "$dst_aliases" 2>/dev/null || true
    chmod 644 "$dst_zshrc" "$dst_aliases"

    rm -f "$tmp_zshrc" "$tmp_aliases"
    ok "Installed repo-managed Zsh config and aliases"
}

ensure_shared_ssh_keypair() {
    key="$PRIMARY_HOME/.ssh/id_ed25519"
    mkdir -p "$PRIMARY_HOME/.ssh"
    if [ ! -f "$key" ]; then
        cmd_exists ssh-keygen && ssh-keygen -q -t ed25519 -N '' -f "$key" >/dev/null 2>&1 \
            && ok "Generated shared SSH keypair" || warn "Failed to generate shared SSH keypair"
    else
        ok "Shared SSH keypair already exists"
    fi
    chown -R "$PRIMARY_USER:$PRIMARY_USER" "$PRIMARY_HOME/.ssh" 2>/dev/null || true
    chmod 700 "$PRIMARY_HOME/.ssh" 2>/dev/null || true
    find "$PRIMARY_HOME/.ssh" -type f -exec chmod 600 {} \; 2>/dev/null || true
    [ -f "$PRIMARY_HOME/.ssh/id_ed25519.pub" ] && chmod 644 "$PRIMARY_HOME/.ssh/id_ed25519.pub" 2>/dev/null || true
}

write_ish_client_config() {
    cfg="$PRIMARY_HOME/.ssh/config"
    mkdir -p "$PRIMARY_HOME/.ssh"
    {
        printf '%s\n' 'Host *'
        printf '%s\n' '    ServerAliveInterval 30'
        printf '%s\n' '    ServerAliveCountMax 3'
        printf '%s\n' '    TCPKeepAlive yes'
        if [ -n "$HOME_PC_HOST" ]; then
            printf '\n%s\n' 'Host ssh-home'
            printf '    HostName %s\n' "$HOME_PC_HOST"
            printf '    User %s\n' "$HOME_PC_USER"
            printf '    Port %s\n' "$HOME_PC_PORT"
            printf '    IdentityFile %s\n' "$PRIMARY_HOME/.ssh/id_ed25519"
            printf '%s\n' '    IdentitiesOnly yes'
            printf '%s\n' '    PreferredAuthentications publickey,password'
            printf '%s\n' '    PubkeyAuthentication yes'
        fi
    } > "$cfg"
    chmod 600 "$cfg"
    chown "$PRIMARY_USER:$PRIMARY_USER" "$cfg" 2>/dev/null || true
    ok "Wrote iSH SSH client config"
}

write_pc_side_snippets() {
    outdir="$PRIMARY_HOME/pc-ssh-snippets"
    mkdir -p "$outdir"

    cat > "$outdir/pc_ssh_config.conf" <<EOF
Host ish-hotspot
    HostName $ISH_HOTSPOT_IP
    User root
    Port $ISH_LISTEN_PORT
    DynamicForward $PC_SOCKS_PORT
    ExitOnForwardFailure yes
    ServerAliveInterval 30
    ServerAliveCountMax 3
    TCPKeepAlive yes

Host ssh-ish
    HostName $ISH_HOTSPOT_IP
    User root
    Port $ISH_LISTEN_PORT
    ServerAliveInterval 30
    ServerAliveCountMax 3
    TCPKeepAlive yes
EOF

    cat > "$outdir/pc_commands.txt" <<EOF
# 1) SOCKS5 proxy from the home PC through iSH
ssh -N -D $PC_SOCKS_PORT root@$ISH_HOTSPOT_IP -p $ISH_LISTEN_PORT

# Or if you copy the config snippet into ~/.ssh/config on the home PC:
ssh -N ish-hotspot

# 2) Normal SSH login from the home PC into iSH
ssh root@$ISH_HOTSPOT_IP -p $ISH_LISTEN_PORT

# Or with the config snippet:
ssh ssh-ish

# 3) From inside iSH, connect to the home PC
ssh ssh-home
EOF

    cat > "$outdir/README.txt" <<EOF
Copy pc_ssh_config.conf into ~/.ssh/config on the home PC, or merge the Host blocks manually.

The 3 SSH setups are:

1) ish-hotspot
   Creates a SOCKS5 proxy on the home PC on 127.0.0.1:$PC_SOCKS_PORT
   Intended command on the home PC:
   ssh -N ish-hotspot

2) ssh-home
   Created inside iSH at:
   $PRIMARY_HOME/.ssh/config
   Intended command inside iSH:
   ssh ssh-home

3) ssh-ish
   Normal SSH login from the home PC into iSH
   Intended command on the home PC:
   ssh ssh-ish

Current assumed iSH hotspot IP:
$ISH_HOTSPOT_IP

Reminder:
Hotspot IPs can change. If the iSH hotspot IP changes, update the home PC config snippet.
EOF

    chown -R "$PRIMARY_USER:$PRIMARY_USER" "$outdir" 2>/dev/null || true
    chmod 644 "$outdir"/* 2>/dev/null || true
    ok "Wrote PC-side SSH snippets to $outdir"
}

link_path_force() {
    src="$1"; dst="$2"
    mkdir -p "$(dirname "$dst")"
    rm -rf "$dst"
    ln -s "$src" "$dst"
}

link_root_to_shared_assets() {
    mkdir -p /root /root/.config /root/.local/share /root/.cache /root/.ssh
    link_path_force "$PRIMARY_HOME/.zshrc" /root/.zshrc
    link_path_force "$PRIMARY_HOME/.oh-my-zsh" /root/.oh-my-zsh
    link_path_force "$PRIMARY_HOME/.local/share/zinit" /root/.local/share/zinit
    link_path_force "$PRIMARY_HOME/.config/zsh" /root/.config/zsh
    link_path_force "$PRIMARY_HOME/.ssh/config" /root/.ssh/config
    link_path_force "$PRIMARY_HOME/.ssh/id_ed25519" /root/.ssh/id_ed25519
    link_path_force "$PRIMARY_HOME/.ssh/id_ed25519.pub" /root/.ssh/id_ed25519.pub
    chmod 700 /root/.ssh 2>/dev/null || true
    ok "Linked root to shared shell and SSH assets"
}

configure_sudo_doas() {
    if cmd_exists sudo; then
        mkdir -p /etc/sudoers.d
        printf '%%wheel ALL=(ALL) ALL\n' > /etc/sudoers.d/wheel
        chmod 440 /etc/sudoers.d/wheel
        ok "Configured sudo"
    fi
    if cmd_exists doas; then
        printf 'permit persist :wheel\n' > /etc/doas.conf
        chmod 0400 /etc/doas.conf
        ok "Configured doas"
    fi
}

generate_host_keys_if_needed() {
    [ -f /etc/ssh/ssh_host_ed25519_key ] || [ -f /etc/ssh/ssh_host_rsa_key ] || {
        cmd_exists ssh-keygen && ssh-keygen -A >/dev/null 2>&1 && ok "Generated SSH host keys" || warn "Failed to generate SSH host keys"
    }
}

ensure_sshd_config_key() {
    key="$1"; value="$2"; cfg="/etc/ssh/sshd_config"
    [ -f "$cfg" ] || touch "$cfg"
    if grep -Eq "^[#[:space:]]*${key}[[:space:]]+" "$cfg" 2>/dev/null; then
        tmpf="/tmp/sshd_config.$$"
        awk -v k="$key" -v v="$value" '
            BEGIN { done=0 }
            {
                if ($0 ~ "^[#[:space:]]*" k "[[:space:]]+") {
                    if (!done) { print k " " v; done=1 }
                } else print
            }
            END { if (!done) print k " " v }
        ' "$cfg" > "$tmpf" && mv "$tmpf" "$cfg"
    else
        printf '%s %s\n' "$key" "$value" >> "$cfg"
    fi
}

configure_sshd_server() {
    mkdir -p /etc/ssh /root/.ssh "$PRIMARY_HOME/.ssh"
    chmod 700 /root/.ssh "$PRIMARY_HOME/.ssh" 2>/dev/null || true
    chown "$PRIMARY_USER:$PRIMARY_USER" "$PRIMARY_HOME/.ssh" 2>/dev/null || true

    generate_host_keys_if_needed

    ensure_sshd_config_key "Port" "$ISH_LISTEN_PORT"
    ensure_sshd_config_key "ListenAddress" "0.0.0.0"
    ensure_sshd_config_key "AllowTcpForwarding" "yes"
    ensure_sshd_config_key "GatewayPorts" "yes"
    ensure_sshd_config_key "PermitRootLogin" "yes"
    ensure_sshd_config_key "PasswordAuthentication" "yes"
    ensure_sshd_config_key "PubkeyAuthentication" "yes"
    ensure_sshd_config_key "PermitEmptyPasswords" "no"
    ensure_sshd_config_key "Compression" "no"
    ensure_sshd_config_key "PermitTTY" "yes"
    ensure_sshd_config_key "PermitTunnel" "yes"
    ok "Configured sshd server"
}

configure_openrc_and_start_sshd() {
    if cmd_exists rc-update; then
        rc-update add sshd default >/dev/null 2>&1 || true
    fi
    if cmd_exists service; then
        service sshd restart >/dev/null 2>&1 || service sshd start >/dev/null 2>&1 || true
    fi
    if cmd_exists rc-service; then
        rc-service sshd restart >/dev/null 2>&1 || rc-service sshd start >/dev/null 2>&1 || true
    fi
    if cmd_exists sshd; then
        pkill sshd >/dev/null 2>&1 || true
        /usr/sbin/sshd >/dev/null 2>&1 || sshd >/dev/null 2>&1 || true
    fi
    ok "Attempted to start sshd"
}

fix_permissions() {
    chown "$PRIMARY_USER:$PRIMARY_USER" "$PRIMARY_HOME" 2>/dev/null || true
    chmod 755 "$PRIMARY_HOME" 2>/dev/null || true
    for d in "$PRIMARY_HOME/.oh-my-zsh" "$PRIMARY_HOME/.local" "$PRIMARY_HOME/.cache" "$PRIMARY_HOME/.config"; do
        [ -e "$d" ] || continue
        chown -R "$PRIMARY_USER:$PRIMARY_USER" "$d" 2>/dev/null || true
        chmod -R go-w "$d" 2>/dev/null || true
    done
    if [ -d "$PRIMARY_HOME/.ssh" ]; then
        chown -R "$PRIMARY_USER:$PRIMARY_USER" "$PRIMARY_HOME/.ssh" 2>/dev/null || true
        chmod 700 "$PRIMARY_HOME/.ssh" 2>/dev/null || true
        find "$PRIMARY_HOME/.ssh" -type f -exec chmod 600 {} \; 2>/dev/null || true
        [ -f "$PRIMARY_HOME/.ssh/id_ed25519.pub" ] && chmod 644 "$PRIMARY_HOME/.ssh/id_ed25519.pub" 2>/dev/null || true
    fi
    chmod 700 /root 2>/dev/null || true
    chmod 700 /root/.ssh 2>/dev/null || true
    ok "Fixed permissions"
}

prime_zsh_for_user() {
    target_user="$1"
    if [ "$target_user" = "root" ]; then
        zsh -lc 'exit 0' >/dev/null 2>&1 || true
    else
        su - "$target_user" -c 'zsh -lc "exit 0"' >/dev/null 2>&1 || true
    fi
}

self_test() {
    say ""
    say "Post-run self-test:"
    sshd -t >/dev/null 2>&1 && say "  [OK] sshd config parse" || say "  [WARN] sshd config parse"
    ssh -G 127.0.0.1 >/dev/null 2>&1 && say "  [OK] ssh client parse" || say "  [WARN] ssh client parse"
    [ -n "$HOME_PC_HOST" ] && ssh -G ssh-home >/dev/null 2>&1 && say "  [OK] ssh-home profile parse" || true
    [ -f "$PRIMARY_HOME/pc-ssh-snippets/pc_ssh_config.conf" ] && say "  [OK] PC-side snippets generated" || say "  [WARN] PC-side snippets missing"
}

main() {
    require_root
    collect_config
    validate_config

    info "Updating apk indexes"
    apk update >/dev/null 2>&1 || warn "apk update failed"

    info "Installing packages"
    pkg_install_alias "curl" curl
    pkg_install_alias "git" git
    pkg_install_alias "wget" wget
    pkg_install_alias "nano" nano
    pkg_install_alias "neovim" neovim
    pkg_install_alias "neofetch" neofetch
    pkg_install_alias "OpenSSH server" openssh-server openssh
    pkg_install_alias "OpenSSH client" openssh-client-default openssh-client openssh
    pkg_install_alias "less" less
    pkg_install_alias "zoxide" zoxide
    pkg_install_alias "tmux" tmux
    pkg_install_alias "htop" htop
    pkg_install_alias "ripgrep" ripgrep
    pkg_install_alias "fd" fd
    pkg_install_alias "tree" tree
    pkg_install_alias "unzip" unzip
    pkg_install_alias "zip" zip
    pkg_install_alias "grep" grep
    pkg_install_alias "sed" sed
    pkg_install_alias "coreutils" coreutils
    pkg_install_alias "util-linux" util-linux
    pkg_install_alias "diffutils" diffutils
    pkg_install_alias "findutils" findutils
    pkg_install_alias "file" file
    pkg_install_alias "patch" patch
    pkg_install_alias "bash" bash
    pkg_install_alias "zsh" zsh
    pkg_install_alias "sudo" sudo
    pkg_install_alias "doas" doas
    pkg_install_alias "shadow" shadow
    pkg_install_alias "openrc" openrc
    pkg_install_alias "util-linux-openrc" util-linux-openrc
    pkg_install_alias "iptables-openrc" iptables-openrc
    pkg_install_alias "man-pages" man-pages
    pkg_install_alias "mandoc" mandoc
    pkg_install_alias "less-doc" less-doc
    pkg_install_alias "fzf" fzf
    pkg_install_alias "jq" jq

    install_docs_for_installed_packages

    set_hostname_files
    ensure_primary_user
    set_passwords

    if cmd_exists zsh; then
        set_shell_in_passwd root "$(command -v zsh)"
        set_shell_in_passwd "$PRIMARY_USER" "$(command -v zsh)"
    fi

    write_profiles
    install_shell_frameworks
    install_repo_shell_assets
    ensure_shared_ssh_keypair
    write_ish_client_config
    write_pc_side_snippets
    link_root_to_shared_assets
    configure_sudo_doas
    configure_sshd_server
    configure_openrc_and_start_sshd
    fix_permissions
    prime_zsh_for_user root
    prime_zsh_for_user "$PRIMARY_USER"

    say ""
    say "============================================================"
    say "Setup complete"
    say "============================================================"
    say ""
    say "Three SSH setups created:"
    say "  1) ish-hotspot : home PC -> iSH SOCKS5 proxy"
    say "  2) ssh-home    : iSH -> home PC"
    say "  3) ssh-ish     : home PC -> iSH normal SSH login"
    say ""
    say "Files created:"
    say "  iSH client config: $PRIMARY_HOME/.ssh/config"
    say "  PC snippets dir:   $PRIMARY_HOME/pc-ssh-snippets"
    say ""
    say "Commands:"
    say "  Inside iSH:"
    [ -n "$HOME_PC_HOST" ] && say "    ssh ssh-home" || say "    ssh-home skipped"
    say ""
    say "  On the home PC after copying $PRIMARY_HOME/pc-ssh-snippets/pc_ssh_config.conf into ~/.ssh/config:"
    say "    ssh -N ish-hotspot"
    say "    ssh ssh-ish"
    say ""
    say "SOCKS5 on home PC:"
    say "  Host: 127.0.0.1"
    say "  Port: $PC_SOCKS_PORT"
    say ""
    say "Hotspot IP reminder:"
    say "  Expected iSH hotspot IP: $ISH_HOTSPOT_IP"
    say "  If hotspot addressing changes, update the home PC config snippet."
    say ""
    say "Fresh iSH keep-awake helper:"
    say "  cat /dev/location > /dev/null &"
    self_test
}

main "$@"
