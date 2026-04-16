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
DRY_RUN="${DRY_RUN:-0}"
SSH_RELAXED="${SSH_RELAXED:-0}"
REPO_RAW_BASE="${REPO_RAW_BASE:-https://raw.githubusercontent.com/ADHD-exe/iOSiSH/main}"

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

say() { printf '%s\n' "$*"; }
info() { printf '%s[INFO] %s%s\n' "$C_YELLOW" "$*" "$C_RESET"; }
ok() { printf '%s[ OK ] %s%s\n' "$C_GREEN" "$*" "$C_RESET"; }
warn() { printf '%s[WARN] %s%s\n' "$C_RED" "$*" "$C_RESET"; }
err() { printf '%s[ERR ] %s%s\n' "$C_RED" "$*" "$C_RESET" >&2; }
scan() { printf '%s[SCAN] %s%s\n' "$C_YELLOW" "$*" "$C_RESET"; }
fail() { printf '%s[FAIL] %s%s\n' "$C_RED" "$*" "$C_RESET"; }

usage() {
    cat <<EOF
Usage: iOSiSH.sh [options]

Options:
  --noninteractive       Disable prompts and require env/config values.
  --dry-run              Print planned actions without applying system changes.
  --ssh-relaxed          Opt into the legacy permissive SSH posture.
  --ssh-hardened         Force the safer SSH posture (default).
  -h, --help             Show this help text.

Environment overrides remain supported, for example:
  PRIMARY_USER, PRIMARY_PASSWORD, ROOT_PASSWORD, ISH_LISTEN_PORT, HOME_PC_HOST
EOF
}

run_cmd() {
    if [ "$DRY_RUN" = "1" ]; then
        info "[dry-run] $*"
        return 0
    fi
    "$@"
}

run_sh() {
    if [ "$DRY_RUN" = "1" ]; then
        info "[dry-run] sh -c $*"
        return 0
    fi
    sh -c "$*"
}

write_file() {
    file="$1"
    content="$2"
    if [ "$DRY_RUN" = "1" ]; then
        info "[dry-run] write $file"
        return 0
    fi
    printf '%s' "$content" > "$file"
}

append_file() {
    file="$1"
    content="$2"
    if [ "$DRY_RUN" = "1" ]; then
        info "[dry-run] append $file"
        return 0
    fi
    printf '%s' "$content" >> "$file"
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --noninteractive) NONINTERACTIVE=1 ;;
            --dry-run) DRY_RUN=1 ;;
            --ssh-relaxed) SSH_RELAXED=1 ;;
            --ssh-hardened) SSH_RELAXED=0 ;;
            -h|--help) usage; exit 0 ;;
            *) err "Unknown option: $1"; usage; exit 1 ;;
        esac
        shift
    done
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
    say "Dry run:              $DRY_RUN"
    if [ "$SSH_RELAXED" = "1" ]; then
        say "SSH posture:          relaxed (legacy-compatible)"
    else
        say "SSH posture:          hardened defaults"
    fi
    say ""
    confirm_yes "Proceed with this configuration" "Y" || { err "Aborted."; exit 1; }
}

validate_config() {
    populate_defaults
    is_valid_hostname "$ISH_HOSTNAME" || { err "Invalid ISH_HOSTNAME"; exit 1; }
    is_valid_username "$PRIMARY_USER" || { err "Invalid PRIMARY_USER"; exit 1; }
    is_valid_abs_path "$PRIMARY_HOME" || { err "Invalid PRIMARY_HOME"; exit 1; }
    if [ "$DRY_RUN" != "1" ]; then
        [ -n "$PRIMARY_PASSWORD" ] || { err "PRIMARY_PASSWORD cannot be empty"; exit 1; }
        [ -n "$ROOT_PASSWORD" ] || { err "ROOT_PASSWORD cannot be empty"; exit 1; }
    fi
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
        scan "$label: checking candidate $p"
        if pkg_installed "$p"; then
            ok "$label: already installed as $p"
            return 0
        fi
    done
    found_any=0
    for p in "$@"; do
        if pkg_exists "$p"; then
            found_any=1
            info "$label: installing $p"
            if run_cmd apk add --no-cache "$p"; then
                ok "$label: installed $p"
                return 0
            fi
            fail "$label: failed to install $p"
        else
            fail "$label: package not available as $p"
        fi
    done
    [ "$found_any" -eq 1 ] && warn "$label: all candidates failed" || warn "$label: package not found"
}

install_doc_package() {
    doc_pkg="$1"
    source_pkg="${2:-unknown}"

    if pkg_installed "$doc_pkg"; then
        ok "[docs] $source_pkg -> $doc_pkg already installed"
        return 0
    fi

    if ! pkg_exists "$doc_pkg"; then
        fail "[docs] $source_pkg -> $doc_pkg not available"
        return 1
    fi

    info "[docs] installing $doc_pkg for $source_pkg"
    if run_cmd apk add --no-cache "$doc_pkg"; then
        ok "[docs] installed $doc_pkg for $source_pkg"
        return 0
    fi

    fail "[docs] failed to install $doc_pkg for $source_pkg"
    return 1
}

install_docs_for_pkg() {
    pkg="$1"
    scan "[docs] scanning package: $pkg"
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
}

install_docs_for_installed_packages() {
    info "[docs] starting installed package scan"
    install_doc_package "mandoc" "manual reader" || true
    install_doc_package "man-pages" "system manpages" || true
    install_doc_package "less-doc" "less" || true
    for pkg in $(apk info 2>/dev/null); do
        install_docs_for_pkg "$pkg"
    done
    ok "[docs] finished installed package scan"
}

require_root() {
    [ "$(id -u)" = "0" ] || { err "Run as root."; exit 1; }
}

ensure_group_exists() {
    grp="$1"
    grep -q "^${grp}:" /etc/group 2>/dev/null && return 0
    run_cmd addgroup "$grp" >/dev/null 2>&1 && ok "Created group: $grp" || warn "Could not create group: $grp"
}

ensure_primary_user() {
    if id "$PRIMARY_USER" >/dev/null 2>&1; then
        ok "User $PRIMARY_USER already exists"
    else
        run_cmd adduser -D -h "$PRIMARY_HOME" -s /bin/sh "$PRIMARY_USER" >/dev/null 2>&1 || {
            err "Failed to create user $PRIMARY_USER"
            exit 1
        }
        ok "Created user $PRIMARY_USER"
    fi
    run_cmd mkdir -p "$PRIMARY_HOME"
    run_cmd chown "$PRIMARY_USER:$PRIMARY_USER" "$PRIMARY_HOME" 2>/dev/null || true
    ensure_group_exists wheel
    run_cmd addgroup "$PRIMARY_USER" wheel >/dev/null 2>&1 || true
}

set_passwords() {
    if [ "$DRY_RUN" = "1" ]; then
        info "[dry-run] would update passwords for root and $PRIMARY_USER"
        return 0
    fi
    if cmd_exists chpasswd; then
        printf 'root:%s\n%s:%s\n' "$ROOT_PASSWORD" "$PRIMARY_USER" "$PRIMARY_PASSWORD" | chpasswd >/dev/null 2>&1 \
            && ok "Set passwords for root and $PRIMARY_USER" \
            || warn "Failed to set passwords"
    else
        warn "chpasswd not found"
    fi
}

set_hostname_files() {
    if [ "$DRY_RUN" = "1" ]; then
        info "[dry-run] would write /etc/hostname and update /etc/hosts for $ISH_HOSTNAME"
        return 0
    fi
    printf '%s\n' "$ISH_HOSTNAME" > /etc/hostname
    if [ ! -f /etc/hosts ]; then
        printf '127.0.0.1\tlocalhost %s\n' "$ISH_HOSTNAME" > /etc/hosts
    elif ! grep -q "[[:space:]]$ISH_HOSTNAME\$" /etc/hosts 2>/dev/null; then
        printf '127.0.0.1\tlocalhost %s\n' "$ISH_HOSTNAME" >> /etc/hosts
    fi
    ok "Updated hostname files"
}

script_dir() {
    case "$0" in
        */*) cd "$(dirname "$0")" 2>/dev/null && pwd -P ;;
        *) pwd -P ;;
    esac
}

run_shelly_setup() {
    src_dir="$(script_dir)"
    shelly_script="$src_dir/shelly/shelly.sh"
    [ -f "$shelly_script" ] || { err "Missing Shelly installer at $shelly_script"; exit 1; }
    cmd_exists bash || { err "bash is required to run Shelly"; exit 1; }

    info "Delegating shell installation and configuration to Shelly"
    if [ "$DRY_RUN" = "1" ]; then
        info "[dry-run] bash $shelly_script --primary-user $PRIMARY_USER"
        return 0
    fi

    if [ "$NONINTERACTIVE" = "1" ]; then
        PRIMARY_HOME="$PRIMARY_HOME" NONINTERACTIVE="$NONINTERACTIVE" bash "$shelly_script" --primary-user "$PRIMARY_USER" --noninteractive --auto-install
    else
        PRIMARY_HOME="$PRIMARY_HOME" NONINTERACTIVE="$NONINTERACTIVE" bash "$shelly_script" --primary-user "$PRIMARY_USER"
    fi
    status=$?
    [ "$status" -eq 0 ] || { err "Shelly failed with exit code $status"; exit 1; }
    ok "Shelly finished shell setup"
}

read_shelly_selection_state() {
    state_file="$PRIMARY_HOME/.config/shelly/selection.env"
    [ -f "$state_file" ] || return 1
    INSTALL_SHELLS_SELECTED="$(awk -F= '/^INSTALL_SHELLS=/{sub(/^INSTALL_SHELLS=/,""); print; exit}' "$state_file")"
    ROOT_DEFAULT_SHELL="$(awk -F= '/^ROOT_DEFAULT=/{sub(/^ROOT_DEFAULT=/,""); print; exit}' "$state_file")"
    USER_DEFAULT_SHELL="$(awk -F= '/^USER_DEFAULT=/{sub(/^USER_DEFAULT=/,""); print; exit}' "$state_file")"
    CONFIGURED_SHELLS="$(awk -F= '/^CONFIGURED_SHELLS=/{sub(/^CONFIGURED_SHELLS=/,""); print; exit}' "$state_file")"
    return 0
}

copy_alias_asset_if_present() {
    src="$1"
    dst="$2"
    owner="$3"
    if [ ! -f "$src" ]; then
        warn "Alias asset not found yet: $src"
        return 1
    fi
    if [ "$DRY_RUN" = "1" ]; then
        info "[dry-run] would install alias asset $dst from $src"
        return 0
    fi
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst" || return 1
    chown "$owner:$owner" "$dst" 2>/dev/null || true
    chmod 644 "$dst" 2>/dev/null || true
    return 0
}

install_aliases_for_shell() {
    shell_name="$1"
    target_home="$2"
    target_user="$3"
    src_dir="$(script_dir)"
    case "$shell_name" in
        zsh) alias_src="$src_dir/aliases/aliases.zsh"; alias_dst="$target_home/.config/iosish/aliases.zsh" ;;
        bash) alias_src="$src_dir/aliases/aliases.bash"; alias_dst="$target_home/.config/iosish/aliases.bash" ;;
        fish) alias_src="$src_dir/aliases/aliases.fish"; alias_dst="$target_home/.config/iosish/aliases.fish" ;;
        *) return 0 ;;
    esac
    copy_alias_asset_if_present "$alias_src" "$alias_dst" "$target_user"         && ok "Installed optional $shell_name aliases for $target_user"         || return 1
}

prompt_for_alias_install() {
    read_shelly_selection_state || { warn "Shelly state file missing; skipping optional alias integration"; return 0; }
    shell_summary="$CONFIGURED_SHELLS"
    [ -n "$shell_summary" ] || shell_summary="$INSTALL_SHELLS_SELECTED"
    [ -n "$shell_summary" ] || shell_summary="selected shell(s)"

    if [ "$NONINTERACTIVE" = "1" ]; then
        info "Noninteractive mode: skipping optional alias integration prompt"
        return 0
    fi

    confirm_yes "Shelly configured $shell_summary. Install optional iOSiSH aliases for the configured shell(s)?" "N" || {
        info "Skipped optional alias integration"
        return 0
    }

    for shell_name in zsh bash fish; do
        case " $CONFIGURED_SHELLS " in
            *" $shell_name "*|*"$shell_name"*)
                install_aliases_for_shell "$shell_name" "$PRIMARY_HOME" "$PRIMARY_USER" || true
                ;;
        esac
    done
}

ensure_shared_ssh_keypair() {
    key="$PRIMARY_HOME/.ssh/id_ed25519"
    run_cmd mkdir -p "$PRIMARY_HOME/.ssh"
    if [ ! -f "$key" ]; then
        cmd_exists ssh-keygen && run_cmd ssh-keygen -q -t ed25519 -N '' -f "$key" >/dev/null 2>&1 \
            && ok "Generated shared SSH keypair" || warn "Failed to generate shared SSH keypair"
    else
        ok "Shared SSH keypair already exists"
    fi
    run_cmd chown -R "$PRIMARY_USER:$PRIMARY_USER" "$PRIMARY_HOME/.ssh" 2>/dev/null || true
    run_cmd chmod 700 "$PRIMARY_HOME/.ssh" 2>/dev/null || true
    [ "$DRY_RUN" = "1" ] || find "$PRIMARY_HOME/.ssh" -type f -exec chmod 600 {} \; 2>/dev/null || true
    [ -f "$PRIMARY_HOME/.ssh/id_ed25519.pub" ] && run_cmd chmod 644 "$PRIMARY_HOME/.ssh/id_ed25519.pub" 2>/dev/null || true
}

write_ish_client_config() {
    cfg="$PRIMARY_HOME/.ssh/config"
    if [ "$DRY_RUN" = "1" ]; then
        info "[dry-run] would write iSH SSH client config to $cfg"
        return 0
    fi
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
    if [ "$DRY_RUN" = "1" ]; then
        info "[dry-run] would write PC-side SSH snippets to $outdir"
        return 0
    fi
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
    if [ "$DRY_RUN" = "1" ]; then
        info "[dry-run] would symlink $dst -> $src"
        return 0
    fi
    mkdir -p "$(dirname "$dst")"
    rm -rf "$dst"
    ln -s "$src" "$dst"
}

link_root_to_shared_assets() {
    run_cmd mkdir -p /root /root/.ssh
    link_path_force "$PRIMARY_HOME/.ssh/config" /root/.ssh/config
    [ -f "$PRIMARY_HOME/.ssh/id_ed25519" ] && link_path_force "$PRIMARY_HOME/.ssh/id_ed25519" /root/.ssh/id_ed25519
    [ -f "$PRIMARY_HOME/.ssh/id_ed25519.pub" ] && link_path_force "$PRIMARY_HOME/.ssh/id_ed25519.pub" /root/.ssh/id_ed25519.pub
    run_cmd chmod 700 /root/.ssh 2>/dev/null || true
    ok "Linked root to shared SSH assets"
}

configure_sudo_doas() {
    if [ "$DRY_RUN" = "1" ]; then
        info "[dry-run] would configure sudo/doas policy"
        return 0
    fi
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
        cmd_exists ssh-keygen && run_cmd ssh-keygen -A >/dev/null 2>&1 && ok "Generated SSH host keys" || warn "Failed to generate SSH host keys"
    }
}

ensure_sshd_config_key() {
    key="$1"; value="$2"; cfg="/etc/ssh/sshd_config"
    if [ "$DRY_RUN" = "1" ]; then
        info "[dry-run] ensure sshd_config: $key $value"
        return 0
    fi
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
    run_cmd mkdir -p /etc/ssh /root/.ssh "$PRIMARY_HOME/.ssh"
    run_cmd chmod 700 /root/.ssh "$PRIMARY_HOME/.ssh" 2>/dev/null || true
    run_cmd chown "$PRIMARY_USER:$PRIMARY_USER" "$PRIMARY_HOME/.ssh" 2>/dev/null || true

    generate_host_keys_if_needed

    ensure_sshd_config_key "Port" "$ISH_LISTEN_PORT"
    ensure_sshd_config_key "ListenAddress" "0.0.0.0"
    ensure_sshd_config_key "AllowTcpForwarding" "yes"
    if [ "$SSH_RELAXED" = "1" ]; then
        ensure_sshd_config_key "GatewayPorts" "yes"
        ensure_sshd_config_key "PermitRootLogin" "yes"
        ensure_sshd_config_key "PasswordAuthentication" "yes"
        ensure_sshd_config_key "PermitTunnel" "yes"
    else
        ensure_sshd_config_key "GatewayPorts" "no"
        ensure_sshd_config_key "PermitRootLogin" "no"
        ensure_sshd_config_key "PasswordAuthentication" "yes"
        ensure_sshd_config_key "PermitTunnel" "no"
    fi
    ensure_sshd_config_key "PubkeyAuthentication" "yes"
    ensure_sshd_config_key "PermitEmptyPasswords" "no"
    ensure_sshd_config_key "Compression" "no"
    ensure_sshd_config_key "PermitTTY" "yes"
    ok "Configured sshd server"
}

configure_openrc_and_start_sshd() {
    if [ "$DRY_RUN" = "1" ]; then
        info "[dry-run] would enable and start sshd"
        return 0
    fi
    if cmd_exists rc-update; then
        rc-update add sshd default >/dev/null 2>&1 || true
    fi
    if cmd_exists service; then
        run_cmd service sshd restart >/dev/null 2>&1 || run_cmd service sshd start >/dev/null 2>&1 || true
    fi
    if cmd_exists rc-service; then
        run_cmd rc-service sshd restart >/dev/null 2>&1 || run_cmd rc-service sshd start >/dev/null 2>&1 || true
    fi
    if cmd_exists sshd; then
        run_cmd pkill sshd >/dev/null 2>&1 || true
        run_cmd /usr/sbin/sshd >/dev/null 2>&1 || run_cmd sshd >/dev/null 2>&1 || true
    fi
    ok "Attempted to start sshd"
}

fix_permissions() {
    if [ "$DRY_RUN" = "1" ]; then
        info "[dry-run] would normalize ownership and permissions under $PRIMARY_HOME and /root"
        return 0
    fi
    chown "$PRIMARY_USER:$PRIMARY_USER" "$PRIMARY_HOME" 2>/dev/null || true
    chmod 755 "$PRIMARY_HOME" 2>/dev/null || true

    for d in "$PRIMARY_HOME/.oh-my-zsh" "$PRIMARY_HOME/.local" "$PRIMARY_HOME/.cache" "$PRIMARY_HOME/.config"; do
        [ -e "$d" ] || continue
        chown -R "$PRIMARY_USER:$PRIMARY_USER" "$d" 2>/dev/null || true
        chmod -R go-w "$d" 2>/dev/null || true
    done

    [ -d "$PRIMARY_HOME/.oh-my-zsh" ] && find "$PRIMARY_HOME/.oh-my-zsh" -type d -exec chmod 755 {} \; 2>/dev/null || true
    [ -d "$PRIMARY_HOME/.local" ] && find "$PRIMARY_HOME/.local" -type d -exec chmod 755 {} \; 2>/dev/null || true
    [ -d "$PRIMARY_HOME/.cache" ] && find "$PRIMARY_HOME/.cache" -type d -exec chmod 755 {} \; 2>/dev/null || true
    [ -d "$PRIMARY_HOME/.config" ] && find "$PRIMARY_HOME/.config" -type d -exec chmod 755 {} \; 2>/dev/null || true

    [ -d "$PRIMARY_HOME/.oh-my-zsh" ] && find "$PRIMARY_HOME/.oh-my-zsh" -type f -exec chmod 644 {} \; 2>/dev/null || true
    [ -d "$PRIMARY_HOME/.local" ] && find "$PRIMARY_HOME/.local" -type f -exec chmod 644 {} \; 2>/dev/null || true
    [ -d "$PRIMARY_HOME/.config" ] && find "$PRIMARY_HOME/.config" -type f -exec chmod 644 {} \; 2>/dev/null || true

    [ -d "$PRIMARY_HOME/.cache/zsh" ] && chmod 700 "$PRIMARY_HOME/.cache/zsh" 2>/dev/null || true
    rm -f "$PRIMARY_HOME"/.zcompdump* "$PRIMARY_HOME/.cache/zsh"/zcompdump-* 2>/dev/null || true

    if [ -d "$PRIMARY_HOME/.ssh" ]; then
        chown -R "$PRIMARY_USER:$PRIMARY_USER" "$PRIMARY_HOME/.ssh" 2>/dev/null || true
        chmod 700 "$PRIMARY_HOME/.ssh" 2>/dev/null || true
        find "$PRIMARY_HOME/.ssh" -type f -exec chmod 600 {} \; 2>/dev/null || true
        [ -f "$PRIMARY_HOME/.ssh/id_ed25519.pub" ] && chmod 644 "$PRIMARY_HOME/.ssh/id_ed25519.pub" 2>/dev/null || true
    fi

    chown -h root:root /root/.ssh/config /root/.ssh/id_ed25519 /root/.ssh/id_ed25519.pub 2>/dev/null || true
    chmod 700 /root 2>/dev/null || true
    run_cmd chmod 700 /root/.ssh 2>/dev/null || true
    [ -L /root/.ssh/config ] && [ "$(readlink /root/.ssh/config 2>/dev/null)" = "$PRIMARY_HOME/.ssh/config" ] || warn "root .ssh/config is not linked to shared SSH asset"

    chmod 700 /root 2>/dev/null || true
    run_cmd chmod 700 /root/.ssh 2>/dev/null || true
    ok "Fixed permissions"
}

self_test() {
    say ""
    say "Post-run self-test:"
    if [ "$DRY_RUN" = "1" ]; then
        say "  [INFO] dry-run mode: skipped live service/config validation"
        return 0
    fi
    sshd -t >/dev/null 2>&1 && say "  [OK] sshd config parse" || say "  [WARN] sshd config parse"
    ssh -G 127.0.0.1 >/dev/null 2>&1 && say "  [OK] ssh client parse" || say "  [WARN] ssh client parse"
    [ -n "$HOME_PC_HOST" ] && ssh -G ssh-home >/dev/null 2>&1 && say "  [OK] ssh-home profile parse" || true
    [ -f "$PRIMARY_HOME/pc-ssh-snippets/pc_ssh_config.conf" ] && say "  [OK] PC-side snippets generated" || say "  [WARN] PC-side snippets missing"
}

main() {
    parse_args "$@"
    require_root
    collect_config
    validate_config

    info "Updating apk indexes"
    run_cmd apk update >/dev/null 2>&1 || warn "apk update failed"

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
    run_shelly_setup
    prompt_for_alias_install
    ensure_shared_ssh_keypair
    write_ish_client_config
    write_pc_side_snippets
    link_root_to_shared_assets
    configure_sudo_doas
    configure_sshd_server
    fix_permissions
    configure_openrc_and_start_sshd

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
    if [ "$SSH_RELAXED" = "1" ]; then
        say "SSH posture:"
        say "  relaxed legacy mode enabled (--ssh-relaxed)"
    else
        say "SSH posture:"
        say "  hardened defaults enabled"
    fi
    say "  If hotspot addressing changes, update the home PC config snippet."
    say ""
    say "Fresh iSH keep-awake helper:"
    say "  cat /dev/location > /dev/null &"
    self_test
}

main "$@"
