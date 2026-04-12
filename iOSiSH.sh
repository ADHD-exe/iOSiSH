#!/bin/sh
# Alpine Linux / iSH setup script
# POSIX sh
# Safe to run as root
# Interactive bootstrap with shared shell/SSH assets owned by PRIMARY_USER

set -u

ISH_HOSTNAME_DEFAULT="iOSiSH"
PRIMARY_USER_DEFAULT="rabbit"
PRIMARY_HOME_DEFAULT=""
PRIMARY_PASSWORD_DEFAULT=""
ROOT_PASSWORD_DEFAULT=""
REMOTE_HOST_DEFAULT=""
REMOTE_USER_DEFAULT=""
REMOTE_PORT_DEFAULT="22"
REMOTE_TUNNEL_PORT_DEFAULT="1080"
NONINTERACTIVE="${NONINTERACTIVE:-0}"

# Semicolon-separated key=value pairs for sshd_config management
SSHD_DEFAULTS_DEFAULT="AllowTcpForwarding=yes;PermitRootLogin=no;PasswordAuthentication=no;PubkeyAuthentication=yes;PermitEmptyPasswords=no;GatewayPorts=yes;Compression=no;PermitTTY=yes;PermitTunnel=yes"
SSHD_DEFAULTS="${SSHD_DEFAULTS:-$SSHD_DEFAULTS_DEFAULT}"

ALIASES_URL="https://raw.githubusercontent.com/ADHD-exe/iOSiSH/main/.aliases"

ISH_HOSTNAME="${ISH_HOSTNAME:-$ISH_HOSTNAME_DEFAULT}"
PRIMARY_USER="${PRIMARY_USER:-$PRIMARY_USER_DEFAULT}"
PRIMARY_HOME="${PRIMARY_HOME:-$PRIMARY_HOME_DEFAULT}"
PRIMARY_PASSWORD="${PRIMARY_PASSWORD:-$PRIMARY_PASSWORD_DEFAULT}"
ROOT_PASSWORD="${ROOT_PASSWORD:-$ROOT_PASSWORD_DEFAULT}"
REMOTE_HOST="${REMOTE_HOST:-$REMOTE_HOST_DEFAULT}"
REMOTE_USER="${REMOTE_USER:-$REMOTE_USER_DEFAULT}"
REMOTE_PORT="${REMOTE_PORT:-$REMOTE_PORT_DEFAULT}"
REMOTE_TUNNEL_PORT="${REMOTE_TUNNEL_PORT:-$REMOTE_TUNNEL_PORT_DEFAULT}"

INSTALLED_PKGS=""
SKIPPED_PKGS=""
DOCS_INSTALLED_PKGS=""
DOCS_SKIPPED_PKGS=""
SEEN_DOC_PKGS=""

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

pause_line() {
    printf '\n'
}

tty_available() {
    [ -r /dev/tty ] && [ -w /dev/tty ]
}

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

    if [ -n "$answer" ]; then
        printf '%s' "$answer"
    else
        printf '%s' "$default"
    fi
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
    pw1=""
    pw2=""

    while :; do
        pw1="$(prompt_password_once "What password should be set for $label")"
        if [ -z "$pw1" ]; then
            warn "Password cannot be empty."
            continue
        fi

        pw2="$(prompt_password_once "Confirm password for $label")"
        if [ "$pw1" != "$pw2" ]; then
            warn "Passwords did not match. Please try again."
            continue
        fi

        printf '%s' "$pw1"
        return 0
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

    if [ -z "$answer" ]; then
        answer="$default"
    fi

    case "$answer" in
        Y|y|yes|YES|Yes) return 0 ;;
        *) return 1 ;;
    esac
}

prompt_choice() {
    prompt="$1"
    default="$2"
    answer=""

    if tty_available; then
        printf '%s' "$prompt" > /dev/tty
        IFS= read -r answer < /dev/tty || true
    else
        printf '%s' "$prompt"
        IFS= read -r answer || true
    fi

    if [ -z "$answer" ]; then
        answer="$default"
    fi

    printf '%s' "$answer"
}

is_valid_username() {
    val="$1"
    case "$val" in
        ""|*[!a-z0-9_-]*|[-_]*)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

is_valid_hostname() {
    val="$1"
    case "$val" in
        ""|*[!A-Za-z0-9._-]*)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

is_valid_abs_path() {
    val="$1"
    case "$val" in
        /*) return 0 ;;
        *) return 1 ;;
    esac
}

is_valid_port() {
    val="$1"
    case "$val" in
        ""|*[!0-9]*)
            return 1
            ;;
    esac

    if [ "$val" -ge 1 ] && [ "$val" -le 65535 ]; then
        return 0
    fi
    return 1
}

require_nonempty() {
    val="$1"
    [ -n "$val" ]
}

is_valid_sshd_key() {
    key="$1"
    case "$key" in
        ""|*[!A-Za-z0-9]*)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

is_valid_sshd_value() {
    val="$1"
    case "$val" in
        ""|*";"*|*"="*)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

normalize_yes_no_default() {
    val="$1"
    case "$val" in
        yes|Yes|YES|y|Y|on|On|ON|true|True|TRUE|1) printf 'yes' ;;
        no|No|NO|n|N|off|Off|OFF|false|False|FALSE|0) printf 'no' ;;
        *) printf '%s' "$val" ;;
    esac
}

populate_derived_defaults() {
    if [ -z "$PRIMARY_HOME" ] && [ -n "$PRIMARY_USER" ]; then
        PRIMARY_HOME="/home/$PRIMARY_USER"
    fi
}

print_sshd_defaults() {
    oldifs="$IFS"
    IFS=';'
    set -- $SSHD_DEFAULTS
    IFS="$oldifs"

    idx=1
    for pair in "$@"; do
        [ -n "$pair" ] || continue
        key=${pair%%=*}
        value=${pair#*=}
        printf '  %s. %s %s\n' "$idx" "$key" "$value"
        idx=$((idx + 1))
    done
}

sshd_defaults_has_key() {
    find_key="$1"
    oldifs="$IFS"
    IFS=';'
    set -- $SSHD_DEFAULTS
    IFS="$oldifs"

    for pair in "$@"; do
        [ -n "$pair" ] || continue
        key=${pair%%=*}
        if [ "$key" = "$find_key" ]; then
            return 0
        fi
    done
    return 1
}

sshd_defaults_upsert() {
    target_key="$1"
    target_value="$2"
    newlist=""

    oldifs="$IFS"
    IFS=';'
    set -- $SSHD_DEFAULTS
    IFS="$oldifs"

    found=0
    for pair in "$@"; do
        [ -n "$pair" ] || continue
        key=${pair%%=*}
        value=${pair#*=}

        if [ "$key" = "$target_key" ]; then
            pair="${target_key}=${target_value}"
            found=1
        else
            pair="${key}=${value}"
        fi

        if [ -n "$newlist" ]; then
            newlist="${newlist};${pair}"
        else
            newlist="${pair}"
        fi
    done

    if [ "$found" -eq 0 ]; then
        if [ -n "$newlist" ]; then
            newlist="${newlist};${target_key}=${target_value}"
        else
            newlist="${target_key}=${target_value}"
        fi
    fi

    SSHD_DEFAULTS="$newlist"
}

sshd_defaults_remove() {
    target_key="$1"
    newlist=""

    oldifs="$IFS"
    IFS=';'
    set -- $SSHD_DEFAULTS
    IFS="$oldifs"

    for pair in "$@"; do
        [ -n "$pair" ] || continue
        key=${pair%%=*}
        value=${pair#*=}

        if [ "$key" = "$target_key" ]; then
            continue
        fi

        if [ -n "$newlist" ]; then
            newlist="${newlist};${key}=${value}"
        else
            newlist="${key}=${value}"
        fi
    done

    SSHD_DEFAULTS="$newlist"
}

validate_sshd_defaults() {
    count=0
    oldifs="$IFS"
    IFS=';'
    set -- $SSHD_DEFAULTS
    IFS="$oldifs"

    for pair in "$@"; do
        [ -n "$pair" ] || continue

        case "$pair" in
            *=*)
                key=${pair%%=*}
                value=${pair#*=}
                ;;
            *)
                err "Invalid SSHD_DEFAULTS entry: $pair"
                exit 1
                ;;
        esac

        if ! is_valid_sshd_key "$key"; then
            err "Invalid sshd setting name: $key"
            exit 1
        fi

        if ! is_valid_sshd_value "$value"; then
            err "Invalid sshd setting value for $key: $value"
            exit 1
        fi

        count=$((count + 1))
    done

    if [ "$count" -eq 0 ]; then
        err "SSHD_DEFAULTS cannot be empty"
        exit 1
    fi
}

interactive_edit_sshd_defaults() {
    pause_line
    say "SSH server defaults"
    say "These settings will be applied to /etc/ssh/sshd_config."
    print_sshd_defaults
    pause_line

    if confirm_yes "Keep these SSH server defaults" "Y"; then
        return 0
    fi

    while :; do
        pause_line
        say "Current SSH server defaults:"
        print_sshd_defaults
        pause_line
        say "Options:"
        say "  a = add or change a setting"
        say "  r = remove a setting"
        say "  x = reset to recommended defaults"
        say "  d = done"
        pause_line

        action="$(prompt_choice "Choose [a/r/x/d] [d]: " "d")"

        case "$action" in
            a|A)
                key="$(prompt_text "Enter sshd setting name (example: X11Forwarding)" "")"
                if ! is_valid_sshd_key "$key"; then
                    warn "Setting names must be alphanumeric only, for example PasswordAuthentication."
                    continue
                fi

                value="$(prompt_text "Enter value for $key" "")"
                value="$(normalize_yes_no_default "$value")"
                if ! is_valid_sshd_value "$value"; then
                    warn "Value cannot be empty and cannot contain ';' or '='."
                    continue
                fi

                sshd_defaults_upsert "$key" "$value"
                ok "Saved $key $value"
                ;;
            r|R)
                key="$(prompt_text "Enter sshd setting name to remove" "")"
                if ! sshd_defaults_has_key "$key"; then
                    warn "Setting not found: $key"
                    continue
                fi
                sshd_defaults_remove "$key"
                ok "Removed $key"
                if [ -z "$SSHD_DEFAULTS" ]; then
                    warn "SSH server defaults cannot be empty; resetting to recommended defaults."
                    SSHD_DEFAULTS="$SSHD_DEFAULTS_DEFAULT"
                fi
                ;;
            x|X)
                SSHD_DEFAULTS="$SSHD_DEFAULTS_DEFAULT"
                ok "Reset SSH server defaults to recommended values"
                ;;
            d|D|"")
                validate_sshd_defaults
                return 0
                ;;
            *)
                warn "Please choose a, r, x, or d."
                ;;
        esac
    done
}

interactive_collect_user_config() {
    pause_line
    say "Interactive setup"
    say "Press Enter to accept a default when one is shown."
    say "This script will create:"
    say "  - ssh remote          (normal remote login)"
    say "  - ssh -N remote-tunnel (SOCKS proxy on localhost:$REMOTE_TUNNEL_PORT)"
    pause_line

    while :; do
        ISH_HOSTNAME="$(prompt_text "What should this iSH system hostname be" "$ISH_HOSTNAME")"
        if is_valid_hostname "$ISH_HOSTNAME"; then
            break
        fi
        warn "Hostname cannot be empty and may only contain letters, digits, dot, underscore, and hyphen."
    done

    while :; do
        old_primary_user="$PRIMARY_USER"
        PRIMARY_USER="$(prompt_text "What should the primary username be" "$PRIMARY_USER")"
        if is_valid_username "$PRIMARY_USER"; then
            if [ -z "$PRIMARY_HOME" ] || [ "$PRIMARY_HOME" = "/home/$old_primary_user" ]; then
                PRIMARY_HOME="/home/$PRIMARY_USER"
            fi
            break
        fi
        warn "Username must use only lowercase letters, digits, underscore, or hyphen."
    done

    populate_derived_defaults

    while :; do
        PRIMARY_HOME="$(prompt_text "What home directory should be used for $PRIMARY_USER" "$PRIMARY_HOME")"
        if is_valid_abs_path "$PRIMARY_HOME"; then
            break
        fi
        warn "Home directory must be an absolute path, for example /home/$PRIMARY_USER"
    done

    PRIMARY_PASSWORD="$(prompt_password_confirmed "$PRIMARY_USER")"
    ROOT_PASSWORD="$(prompt_password_confirmed "root")"

    while :; do
        REMOTE_HOST="$(prompt_text "What remote SSH host should be used for the generated client config" "$REMOTE_HOST")"
        if require_nonempty "$REMOTE_HOST"; then
            break
        fi
        warn "Remote host cannot be empty."
    done

    while :; do
        REMOTE_USER="$(prompt_text "What remote SSH username should be used for ssh remote and remote-tunnel" "$REMOTE_USER")"
        if require_nonempty "$REMOTE_USER"; then
            break
        fi
        warn "Remote SSH username cannot be empty."
    done

    while :; do
        REMOTE_PORT="$(prompt_text "What remote SSH port should be used for ssh remote and remote-tunnel" "$REMOTE_PORT")"
        if is_valid_port "$REMOTE_PORT"; then
            break
        fi
        warn "Remote SSH port must be a number from 1 to 65535."
    done

    while :; do
        REMOTE_TUNNEL_PORT="$(prompt_text "What local SOCKS port should ssh -N remote-tunnel listen on" "$REMOTE_TUNNEL_PORT")"
        if is_valid_port "$REMOTE_TUNNEL_PORT"; then
            break
        fi
        warn "Local SOCKS port must be a number from 1 to 65535."
    done

    interactive_edit_sshd_defaults
}

validate_user_config() {
    populate_derived_defaults

    if ! is_valid_hostname "$ISH_HOSTNAME"; then
        err "Invalid ISH_HOSTNAME: $ISH_HOSTNAME"
        exit 1
    fi

    if ! is_valid_username "$PRIMARY_USER"; then
        err "Invalid PRIMARY_USER: $PRIMARY_USER"
        exit 1
    fi

    if ! is_valid_abs_path "$PRIMARY_HOME"; then
        err "Invalid PRIMARY_HOME: $PRIMARY_HOME"
        exit 1
    fi

    if ! require_nonempty "$PRIMARY_PASSWORD"; then
        err "PRIMARY_PASSWORD cannot be empty"
        exit 1
    fi

    if ! require_nonempty "$ROOT_PASSWORD"; then
        err "ROOT_PASSWORD cannot be empty"
        exit 1
    fi

    if ! require_nonempty "$REMOTE_HOST"; then
        err "REMOTE_HOST cannot be empty"
        exit 1
    fi

    if ! require_nonempty "$REMOTE_USER"; then
        err "REMOTE_USER cannot be empty"
        exit 1
    fi

    if ! is_valid_port "$REMOTE_PORT"; then
        err "Invalid REMOTE_PORT: $REMOTE_PORT"
        exit 1
    fi

    if ! is_valid_port "$REMOTE_TUNNEL_PORT"; then
        err "Invalid REMOTE_TUNNEL_PORT: $REMOTE_TUNNEL_PORT"
        exit 1
    fi

    validate_sshd_defaults
}

confirm_user_config_loop() {
    while :; do
        pause_line
        say "Configuration summary"
        say "---------------------"
        say "Hostname:          $ISH_HOSTNAME"
        say "Primary user:      $PRIMARY_USER"
        say "Primary home:      $PRIMARY_HOME"
        say "SSH remote:        $REMOTE_USER@$REMOTE_HOST:$REMOTE_PORT"
        say "SOCKS tunnel:      localhost:$REMOTE_TUNNEL_PORT via ssh -N remote-tunnel"
        say "SSH defaults:"
        print_sshd_defaults
        pause_line

        if [ "$NONINTERACTIVE" = "1" ]; then
            ok "NONINTERACTIVE=1 detected; proceeding without prompts."
            return 0
        fi

        choice="$(prompt_choice "Proceed, edit, or quit? [p/e/q] [p]: " "p")"
        case "$choice" in
            p|P|"")
                return 0
                ;;
            e|E)
                interactive_collect_user_config
                validate_user_config
                ;;
            q|Q)
                err "Aborted by user."
                exit 1
                ;;
            *)
                warn "Please choose p, e, or q."
                ;;
        esac
    done
}

collect_and_validate_config() {
    populate_derived_defaults

    if [ "$NONINTERACTIVE" = "1" ]; then
        validate_user_config
        confirm_user_config_loop
        return 0
    fi

    while :; do
        interactive_collect_user_config
        validate_user_config
        confirm_user_config_loop
        return 0
    done
}

pkg_install_alias() {
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

remember_doc_pkg() {
    pkg="$1"
    [ -n "$pkg" ] || return 0
    case ",$SEEN_DOC_PKGS," in
        *,"$pkg",*) return 0 ;;
    esac
    if [ -n "$SEEN_DOC_PKGS" ]; then
        SEEN_DOC_PKGS="${SEEN_DOC_PKGS},${pkg}"
    else
        SEEN_DOC_PKGS="$pkg"
    fi
}

install_doc_package() {
    doc_pkg="$1"
    source_pkg="$2"

    if [ -z "$doc_pkg" ]; then
        return 1
    fi

    if pkg_installed "$doc_pkg"; then
        info "Docs for $source_pkg: already installed as $doc_pkg"
        DOCS_INSTALLED_PKGS=$(append_csv "$DOCS_INSTALLED_PKGS" "$source_pkg -> $doc_pkg")
        return 0
    fi

    if ! pkg_exists "$doc_pkg"; then
        return 1
    fi

    info "Docs for $source_pkg: installing $doc_pkg"
    if apk add --no-cache "$doc_pkg" >/dev/null 2>&1; then
        ok "Docs for $source_pkg: installed $doc_pkg"
        DOCS_INSTALLED_PKGS=$(append_csv "$DOCS_INSTALLED_PKGS" "$source_pkg -> $doc_pkg")
        return 0
    fi

    warn "Docs for $source_pkg: failed to install $doc_pkg"
    return 1
}

install_docs_for_pkg() {
    pkg="$1"
    [ -n "$pkg" ] || return 0

    remember_doc_pkg "$pkg"

    case "$pkg" in
        *-doc|man-pages|mandoc|docs)
            return 0
            ;;
    esac

    case "$pkg" in
        openssh|openssh-server|openssh-client|openssh-client-default)
            install_doc_package "openssh-doc" "$pkg" && return 0
            ;;
        python3|py3-pip|py3-setuptools)
            install_doc_package "python3-doc" "$pkg" && return 0
            ;;
        nodejs|node.js|npm)
            install_doc_package "nodejs-doc" "$pkg" && return 0
            ;;
        util-linux|util-linux-openrc)
            install_doc_package "util-linux-doc" "$pkg" && return 0
            ;;
        openrc|iptables-openrc)
            install_doc_package "openrc-doc" "$pkg" && return 0
            ;;
        zsh)
            install_doc_package "zsh-doc" "$pkg" && return 0
            ;;
        bash)
            install_doc_package "bash-doc" "$pkg" && return 0
            ;;
        less)
            install_doc_package "less-doc" "$pkg" && return 0
            ;;
        neovim)
            install_doc_package "neovim-doc" "$pkg" && return 0
            ;;
        git)
            install_doc_package "git-doc" "$pkg" && return 0
            ;;
        tmux)
            install_doc_package "tmux-doc" "$pkg" && return 0
            ;;
        curl)
            install_doc_package "curl-doc" "$pkg" && return 0
            ;;
        wget)
            install_doc_package "wget-doc" "$pkg" && return 0
            ;;
        nano)
            install_doc_package "nano-doc" "$pkg" && return 0
            ;;
        grep)
            install_doc_package "grep-doc" "$pkg" && return 0
            ;;
        sed)
            install_doc_package "sed-doc" "$pkg" && return 0
            ;;
        coreutils)
            install_doc_package "coreutils-doc" "$pkg" && return 0
            ;;
        findutils)
            install_doc_package "findutils-doc" "$pkg" && return 0
            ;;
        diffutils)
            install_doc_package "diffutils-doc" "$pkg" && return 0
            ;;
        patch)
            install_doc_package "patch-doc" "$pkg" && return 0
            ;;
        file)
            install_doc_package "file-doc" "$pkg" && return 0
            ;;
        jq)
            install_doc_package "jq-doc" "$pkg" && return 0
            ;;
        bind-tools)
            install_doc_package "bind-doc" "$pkg" && return 0
            ;;
        *)
            install_doc_package "${pkg}-doc" "$pkg" && return 0
            ;;
    esac

    DOCS_SKIPPED_PKGS=$(append_csv "$DOCS_SKIPPED_PKGS" "$pkg")
    info "Docs for $pkg: no matching doc package found"
    return 0
}

install_docs_for_installed_packages() {
    info "Installing manpages and docs for requested and already installed packages"

    install_doc_package "mandoc" "manual reader" || true
    install_doc_package "man-pages" "system manpages" || true
    install_doc_package "less-doc" "less" || true

    if ! cmd_exists apk; then
        warn "apk not available; cannot inspect installed packages for docs"
        return 0
    fi

    for pkg in $(apk info 2>/dev/null); do
        install_docs_for_pkg "$pkg"
    done
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

ensure_primary_user() {
    if id "$PRIMARY_USER" >/dev/null 2>&1; then
        ok "User $PRIMARY_USER already exists"
    else
        info "Creating user $PRIMARY_USER"
        if adduser -D -h "$PRIMARY_HOME" -s /bin/sh "$PRIMARY_USER" >/dev/null 2>&1; then
            ok "Created user $PRIMARY_USER"
        else
            err "Failed to create user $PRIMARY_USER"
            exit 1
        fi
    fi

    mkdir -p "$PRIMARY_HOME"
    chown "$PRIMARY_USER:$PRIMARY_USER" "$PRIMARY_HOME" 2>/dev/null || true

    ensure_group_exists wheel

    if addgroup "$PRIMARY_USER" wheel >/dev/null 2>&1; then
        ok "Ensured $PRIMARY_USER is in wheel"
    else
        info "$PRIMARY_USER may already be in wheel"
    fi
}

set_passwords() {
    if cmd_exists chpasswd; then
        if printf 'root:%s\n%s:%s\n' "$ROOT_PASSWORD" "$PRIMARY_USER" "$PRIMARY_PASSWORD" | chpasswd >/dev/null 2>&1; then
            ok "Set passwords for root and $PRIMARY_USER"
        else
            warn "Failed to set passwords with chpasswd"
        fi
    else
        warn "chpasswd not found; passwords were not set automatically"
    fi
}

set_hostname_persistent() {
    printf '%s\n' "$ISH_HOSTNAME" > /etc/hostname
    ok "Wrote /etc/hostname"

    if [ ! -f /etc/hosts ]; then
        printf '127.0.0.1\tlocalhost %s\n' "$ISH_HOSTNAME" > /etc/hosts
        ok "Created /etc/hosts"
        return 0
    fi

    if grep -q "[[:space:]]$ISH_HOSTNAME\$" /etc/hosts 2>/dev/null; then
        ok "/etc/hosts already contains $ISH_HOSTNAME"
    else
        printf '127.0.0.1\tlocalhost %s\n' "$ISH_HOSTNAME" >> /etc/hosts
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

    printf '%s\n' 'exec zsh -l' > "$PRIMARY_HOME/.profile"
    chown "$PRIMARY_USER:$PRIMARY_USER" "$PRIMARY_HOME/.profile" 2>/dev/null || true
    chmod 644 "$PRIMARY_HOME/.profile"
    ok "Wrote $PRIMARY_HOME/.profile"
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
    omz_dir="$PRIMARY_HOME/.oh-my-zsh"
    zinit_dir="$PRIMARY_HOME/.local/share/zinit/zinit.git"

    clone_or_update_repo "https://github.com/ohmyzsh/ohmyzsh.git" "$omz_dir" "Oh My Zsh for $PRIMARY_USER" || true
    clone_or_update_repo "https://github.com/zdharma-continuum/zinit.git" "$zinit_dir" "Zinit for $PRIMARY_USER" || true

    mkdir -p "$PRIMARY_HOME/.cache/zsh" "$PRIMARY_HOME/.local/share" "$PRIMARY_HOME/.ssh" "$PRIMARY_HOME/.config/zsh"
    rm -f "$PRIMARY_HOME"/.zcompdump* 2>/dev/null || true

    chown -R "$PRIMARY_USER:$PRIMARY_USER" \
        "$PRIMARY_HOME/.oh-my-zsh" \
        "$PRIMARY_HOME/.local" \
        "$PRIMARY_HOME/.cache" \
        "$PRIMARY_HOME/.ssh" \
        "$PRIMARY_HOME/.config" 2>/dev/null || true

    chmod 700 "$PRIMARY_HOME/.ssh" 2>/dev/null || true
}

install_shared_aliases() {
    alias_dir="$PRIMARY_HOME/.config/zsh"
    alias_file="$alias_dir/.aliases"

    mkdir -p "$alias_dir"

    if [ -f ".aliases" ]; then
        cp -f ".aliases" "$alias_file"
        chown "$PRIMARY_USER:$PRIMARY_USER" "$alias_file" 2>/dev/null || true
        chmod 644 "$alias_file" 2>/dev/null || true
        ok "Installed shared aliases from local repo copy"
        return 0
    fi

    if [ -f "$(dirname "$0")/.aliases" ]; then
        cp -f "$(dirname "$0")/.aliases" "$alias_file"
        chown "$PRIMARY_USER:$PRIMARY_USER" "$alias_file" 2>/dev/null || true
        chmod 644 "$alias_file" 2>/dev/null || true
        ok "Installed shared aliases from script directory"
        return 0
    fi

    if cmd_exists curl; then
        if curl -fsSL "$ALIASES_URL" -o "$alias_file"; then
            chown "$PRIMARY_USER:$PRIMARY_USER" "$alias_file" 2>/dev/null || true
            chmod 644 "$alias_file" 2>/dev/null || true
            ok "Installed shared aliases from GitHub"
            return 0
        fi
    fi

    warn "Failed to install shared aliases"
    return 1
}

write_shared_zshrc() {
    zshrc="$PRIMARY_HOME/.zshrc"

    cat > "$zshrc" <<EOF
# Generated by Alpine/iSH setup script
# Shared Zsh config owned by PRIMARY_USER and reused by root

export SHARED_HOME="$PRIMARY_HOME"
export LANG="\${LANG:-C.UTF-8}"
export EDITOR="\${EDITOR:-nvim}"
export VISUAL="\${VISUAL:-nvim}"
export PAGER="\${PAGER:-less}"
export LESS="-FRX"

# Prevent Oh My Zsh compfix noise in shared-asset mode.
export ZSH_DISABLE_COMPFIX=true

export HISTFILE="\$HOME/.zsh_history"
export HISTSIZE=50000
export SAVEHIST=50000

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

# Root is intentionally reusing PRIMARY_USER-owned completion/plugin paths.
# That ownership pattern will trigger compaudit, so root must use -u.
if [ "\$(id -u 2>/dev/null)" = "0" ]; then
    compinit -u -d "\$HOME/.cache/zsh/zcompdump-\$(id -un 2>/dev/null)"
else
    compinit -i -d "\$HOME/.cache/zsh/zcompdump-\$(id -un 2>/dev/null)"
fi

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

    chown "$PRIMARY_USER:$PRIMARY_USER" "$zshrc" 2>/dev/null || true
    chmod 644 "$zshrc"
    ok "Wrote shared Zsh config: $zshrc"
}

ensure_shared_ssh_keypair() {
    key="$PRIMARY_HOME/.ssh/id_ed25519"

    mkdir -p "$PRIMARY_HOME/.ssh"
    if [ ! -f "$key" ]; then
        if cmd_exists ssh-keygen; then
            if ssh-keygen -q -t ed25519 -N '' -f "$key" >/dev/null 2>&1; then
                ok "Generated shared SSH key for $PRIMARY_USER"
            else
                warn "Failed to generate shared SSH key"
            fi
        else
            warn "ssh-keygen not found; cannot create SSH key"
        fi
    else
        ok "Shared SSH key already exists"
    fi

    chown -R "$PRIMARY_USER:$PRIMARY_USER" "$PRIMARY_HOME/.ssh" 2>/dev/null || true
    chmod 700 "$PRIMARY_HOME/.ssh" 2>/dev/null || true
    find "$PRIMARY_HOME/.ssh" -type f -exec chmod 600 {} \; 2>/dev/null || true
    [ -f "$PRIMARY_HOME/.ssh/id_ed25519.pub" ] && chmod 644 "$PRIMARY_HOME/.ssh/id_ed25519.pub" 2>/dev/null || true
}

write_shared_ssh_config() {
    cfg="$PRIMARY_HOME/.ssh/config"

    mkdir -p "$PRIMARY_HOME/.ssh"
    cat > "$cfg" <<EOF
Host *
    ServerAliveInterval 30
    ServerAliveCountMax 3
    TCPKeepAlive yes

Host remote
    HostName $REMOTE_HOST
    User $REMOTE_USER
    Port $REMOTE_PORT
    PreferredAuthentications publickey,password
    PubkeyAuthentication yes
    IdentitiesOnly yes
    IdentityFile $PRIMARY_HOME/.ssh/id_ed25519

Host remote-tunnel
    HostName $REMOTE_HOST
    User $REMOTE_USER
    Port $REMOTE_PORT
    PreferredAuthentications publickey,password
    PubkeyAuthentication yes
    IdentitiesOnly yes
    IdentityFile $PRIMARY_HOME/.ssh/id_ed25519
    DynamicForward $REMOTE_TUNNEL_PORT
    Compression no
    ExitOnForwardFailure yes
EOF
    chmod 600 "$cfg"
    chown -R "$PRIMARY_USER:$PRIMARY_USER" "$PRIMARY_HOME/.ssh" 2>/dev/null || true
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

link_root_to_shared_assets() {
    mkdir -p /root /root/.config /root/.local/share /root/.cache /root/.ssh

    link_path_force "$PRIMARY_HOME/.zshrc" /root/.zshrc
    link_path_force "$PRIMARY_HOME/.oh-my-zsh" /root/.oh-my-zsh
    mkdir -p /root/.local/share
    link_path_force "$PRIMARY_HOME/.local/share/zinit" /root/.local/share/zinit
    mkdir -p /root/.config
    link_path_force "$PRIMARY_HOME/.config/zsh" /root/.config/zsh

    link_path_force "$PRIMARY_HOME/.ssh/config" /root/.ssh/config
    link_path_force "$PRIMARY_HOME/.ssh/id_ed25519" /root/.ssh/id_ed25519
    link_path_force "$PRIMARY_HOME/.ssh/id_ed25519.pub" /root/.ssh/id_ed25519.pub

    chmod 700 /root/.ssh 2>/dev/null || true

    ok "Linked root to shared shell and SSH assets in $PRIMARY_HOME"
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

apply_sshd_defaults() {
    oldifs="$IFS"
    IFS=';'
    set -- $SSHD_DEFAULTS
    IFS="$oldifs"

    for pair in "$@"; do
        [ -n "$pair" ] || continue
        key=${pair%%=*}
        value=${pair#*=}
        ensure_sshd_config_key "$key" "$value"
    done
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
    chown "$PRIMARY_USER:$PRIMARY_USER" "$PRIMARY_HOME" 2>/dev/null || true
    chmod 755 "$PRIMARY_HOME" 2>/dev/null || true

    parent_home="$(dirname "$PRIMARY_HOME")"
    if [ -n "$parent_home" ] && [ "$parent_home" != "." ] && [ -d "$parent_home" ]; then
        chmod go-w "$parent_home" 2>/dev/null || true
    fi

    for d in \
        "$PRIMARY_HOME/.oh-my-zsh" \
        "$PRIMARY_HOME/.local" \
        "$PRIMARY_HOME/.cache" \
        "$PRIMARY_HOME/.config"
    do
        if [ -e "$d" ]; then
            chown -R "$PRIMARY_USER:$PRIMARY_USER" "$d" 2>/dev/null || true
            chmod -R go-w "$d" 2>/dev/null || true
        fi
    done

    if [ -d "$PRIMARY_HOME/.ssh" ]; then
        chown -R "$PRIMARY_USER:$PRIMARY_USER" "$PRIMARY_HOME/.ssh" 2>/dev/null || true
        chmod 700 "$PRIMARY_HOME/.ssh" 2>/dev/null || true
        find "$PRIMARY_HOME/.ssh" -type f -exec chmod 600 {} \; 2>/dev/null || true
        [ -f "$PRIMARY_HOME/.ssh/id_ed25519.pub" ] && chmod 644 "$PRIMARY_HOME/.ssh/id_ed25519.pub" 2>/dev/null || true
    fi

    chown root:root /root 2>/dev/null || true
    chmod 700 /root 2>/dev/null || true
    chmod 700 /root/.ssh 2>/dev/null || true

    ok "Fixed permissions for shared assets and /root links"
}

prime_zsh_for_user() {
    target_user="$1"

    if [ "$target_user" = "root" ]; then
        if zsh -lc 'exit 0' >/dev/null 2>&1; then
            ok "Primed Zsh for root"
        else
            warn "Could not fully prime Zsh for root on first pass"
        fi
    else
        if su - "$target_user" -c 'zsh -lc "exit 0"' >/dev/null 2>&1; then
            ok "Primed Zsh for $target_user"
        else
            warn "Could not fully prime Zsh for $target_user on first pass"
        fi
    fi
}

post_run_self_test() {
    say
    say "Post-run self-test:"

    if [ -L /root/.zshrc ] && [ "$(readlink /root/.zshrc)" = "$PRIMARY_HOME/.zshrc" ]; then
        say "  [OK] root .zshrc symlinked to shared config"
    else
        say "  [WARN] root .zshrc is not symlinked to shared config"
    fi

    if [ -L /root/.ssh/config ] && [ "$(readlink /root/.ssh/config)" = "$PRIMARY_HOME/.ssh/config" ]; then
        say "  [OK] root SSH config symlinked to shared config"
    else
        say "  [WARN] root SSH config is not symlinked to shared config"
    fi

    if zsh -lc 'exit 0' >/dev/null 2>&1; then
        say "  [OK] root zsh startup"
    else
        say "  [WARN] root zsh startup"
    fi

    if su - "$PRIMARY_USER" -c 'zsh -lc "exit 0"' >/dev/null 2>&1; then
        say "  [OK] $PRIMARY_USER zsh startup"
    else
        say "  [WARN] $PRIMARY_USER zsh startup"
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

    if su - "$PRIMARY_USER" -c 'sudo -l' >/dev/null 2>&1; then
        say "  [OK] sudo check"
    else
        say "  [INFO] sudo check may require interactive auth"
    fi

    if [ -n "$REMOTE_TUNNEL_PORT" ] && ssh -G remote-tunnel >/dev/null 2>&1; then
        say "  [OK] remote-tunnel client profile parse"
    else
        say "  [WARN] remote-tunnel client profile parse"
    fi
}

main() {
    require_root
    collect_and_validate_config

    info "Updating apk indexes"
    if apk update >/dev/null 2>&1; then
        ok "apk indexes updated"
    else
        warn "apk update failed; continuing anyway"
    fi

    info "Installing requested packages"
    pkg_install_alias "git" git
    pkg_install_alias "curl" curl
    pkg_install_alias "wget" wget
    pkg_install_alias "bat" bat
    pkg_install_alias "fzf" fzf
    pkg_install_alias "nano" nano
    pkg_install_alias "neovim" neovim
    pkg_install_alias "neofetch" neofetch
    pkg_install_alias "OpenSSH server" openssh-server openssh
    pkg_install_alias "OpenSSH client" openssh-client-default openssh-client openssh
    pkg_install_alias "ncurses" ncurses
    pkg_install_alias "less" less
    pkg_install_alias "zoxide" zoxide
    pkg_install_alias "tmux" tmux
    pkg_install_alias "htop" htop
    pkg_install_alias "ripgrep" ripgrep
    pkg_install_alias "fd" fd
    pkg_install_alias "lazygit" lazygit
    pkg_install_alias "tree" tree
    pkg_install_alias "unzip" unzip
    pkg_install_alias "zip" zip
    pkg_install_alias "grep" grep
    pkg_install_alias "sed" sed
    pkg_install_alias "coreutils" coreutils
    pkg_install_alias "util-linux" util-linux
    pkg_install_alias "linux headers/tools" linux-headers linux-lts-headers linux-edge-headers
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
    pkg_install_alias "iptables-openrc" iptables-openrc
    pkg_install_alias "util-linux-openrc" util-linux-openrc
    pkg_install_alias "nmap" nmap
    pkg_install_alias "python3" python3
    pkg_install_alias "py3-pip" py3-pip pip
    pkg_install_alias "py3-setuptools" py3-setuptools
    pkg_install_alias "nikto" nikto
    pkg_install_alias "aircrack-ng" aircrack-ng
    pkg_install_alias "sqlmap" sqlmap
    pkg_install_alias "node.js" nodejs node.js
    pkg_install_alias "transmission-cli" transmission-cli
    pkg_install_alias "transmission-daemon" transmission-daemon
    pkg_install_alias "masscan" masscan
    pkg_install_alias "whois" whois
    pkg_install_alias "bind-tools" bind-tools
    pkg_install_alias "socat" socat
    pkg_install_alias "transmission" transmission
    pkg_install_alias "dovecot" dovecot
    pkg_install_alias "strongswan" strongswan
    pkg_install_alias "snort" snort
    pkg_install_alias "fwsnort" fwsnort
    pkg_install_alias "jwhois" jwhois
    pkg_install_alias "go" go
    pkg_install_alias "rust" rust
    pkg_install_alias "npm" npm
    pkg_install_alias "gcc" gcc
    pkg_install_alias "jq" jq
    pkg_install_alias "shellcheck" shellcheck
    pkg_install_alias "abuild" abuild
    pkg_install_alias "man-pages" man-pages
    pkg_install_alias "mandoc" mandoc
    pkg_install_alias "less-doc" less-doc

    install_docs_for_installed_packages

    set_hostname_persistent
    ensure_primary_user
    set_passwords

    if cmd_exists zsh; then
        set_shell_in_passwd root "$(command -v zsh)"
        set_shell_in_passwd "$PRIMARY_USER" "$(command -v zsh)"
    else
        warn "zsh not installed; cannot set login shells"
    fi

    write_profiles
    install_shell_frameworks
    install_shared_aliases
    write_shared_zshrc
    ensure_shared_ssh_keypair
    write_shared_ssh_config
    link_root_to_shared_assets

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
    mkdir -p /etc/ssh /root/.ssh "$PRIMARY_HOME/.ssh"
    chmod 700 /root/.ssh "$PRIMARY_HOME/.ssh" 2>/dev/null || true
    chown "$PRIMARY_USER:$PRIMARY_USER" "$PRIMARY_HOME/.ssh" 2>/dev/null || true

    generate_host_keys_if_needed
    apply_sshd_defaults

    configure_openrc
    start_sshd_safely
    fix_permissions

    prime_zsh_for_user root
    prime_zsh_for_user "$PRIMARY_USER"

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
    say "Installed doc packages:"
    if [ -n "$DOCS_INSTALLED_PKGS" ]; then
        say "  $DOCS_INSTALLED_PKGS"
    else
        say "  (none)"
    fi
    say
    say "Doc packages not found:"
    if [ -n "$DOCS_SKIPPED_PKGS" ]; then
        say "  $DOCS_SKIPPED_PKGS"
    else
        say "  (none)"
    fi
    say
    say "Primary user:"
    say "  $PRIMARY_USER"
    say "  $PRIMARY_HOME"
    say
    say "Shared shell assets:"
    say "  $PRIMARY_HOME/.zshrc"
    say "  $PRIMARY_HOME/.config/zsh/.aliases"
    say "  $PRIMARY_HOME/.oh-my-zsh"
    say "  $PRIMARY_HOME/.local/share/zinit"
    say
    say "Shared SSH assets:"
    say "  $PRIMARY_HOME/.ssh/config"
    say "  $PRIMARY_HOME/.ssh/id_ed25519.pub"
    say
    say "Root reuses shared assets via symlinks under /root"
    say
    say "Privilege escalation:"
    say "  sudo apk update"
    say "  doas apk update"
    say
    say "SSH client aliases:"
    say "  ssh remote"
    say "  ssh -N remote-tunnel"
    say
    say "Configured remote target:"
    say "  $REMOTE_USER@$REMOTE_HOST:$REMOTE_PORT"
    say "  SOCKS proxy listens on localhost:$REMOTE_TUNNEL_PORT"
    say
    say "Applied SSH server defaults:"
    print_sshd_defaults
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

    post_run_self_test
}

main "$@"
