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

# Guided installer module paths
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
INSTALLER_DIR="${INSTALLER_DIR:-$SCRIPT_DIR/installer}"
INSTALLER_STATE_FILE="${INSTALLER_STATE_FILE:-$SCRIPT_DIR/.iosish-state.env}"

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
fail() { printf '%s[FAIL] %s%s
' "$C_RED" "$*" "$C_RESET"; }

load_guided_installer_modules() {
    [ -r "$INSTALLER_DIR/state.sh" ] || {
        printf 'Missing installer module: %s/state.sh
' "$INSTALLER_DIR" >&2
        return 1
    }
    [ -r "$INSTALLER_DIR/prompts.sh" ] || {
        printf 'Missing installer module: %s/prompts.sh
' "$INSTALLER_DIR" >&2
        return 1
    }
    [ -r "$INSTALLER_DIR/summary.sh" ] || {
        printf 'Missing installer module: %s/summary.sh
' "$INSTALLER_DIR" >&2
        return 1
    }
    [ -r "$INSTALLER_DIR/plan.sh" ] || {
        printf 'Missing installer module: %s/plan.sh
' "$INSTALLER_DIR" >&2
        return 1
    }

    # shellcheck disable=SC1091
    . "$INSTALLER_DIR/state.sh" || return 1
    # shellcheck disable=SC1091
    . "$INSTALLER_DIR/prompts.sh" || return 1
    # shellcheck disable=SC1091
    . "$INSTALLER_DIR/summary.sh" || return 1
    # shellcheck disable=SC1091
    . "$INSTALLER_DIR/plan.sh" || return 1
}

INSTALLER_RUNTIME_LOG="${INSTALLER_RUNTIME_LOG:-$SCRIPT_DIR/.iosish-install.log}"

log_install_event() {
    level=$1
    shift
    message=$*
    timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || printf '%s' 'unknown-time')
    printf '%s [%s] %s\n' "$timestamp" "$level" "$message" >> "$INSTALLER_RUNTIME_LOG" 2>/dev/null || true
}

init_runtime_log() {
    : > "$INSTALLER_RUNTIME_LOG" 2>/dev/null || true
    log_install_event INFO "Starting iOSiSH installer run"
}

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
pkg_installed() {
    cmd_exists apk || return 1
    apk info -e "$1" >/dev/null 2>&1
}
pkg_exists() {
    if ! cmd_exists apk; then
        [ "${DRY_RUN:-0}" = "1" ] && return 0
        return 1
    fi
    apk search -x "$1" >/dev/null 2>&1
}


populate_defaults() {
    if [ -z "${PRIMARY_HOME:-}" ] && [ -n "${PRIMARY_USER:-}" ]; then
        if [ "$PRIMARY_USER" = "root" ]; then
            PRIMARY_HOME="/root"
        else
            PRIMARY_HOME="/home/$PRIMARY_USER"
        fi
    fi
}

apply_guided_state_to_runtime() {
    state_load || return 1

    ROOT_ONLY="$(state_get ROOT_ONLY 2>/dev/null || true)"
    state_primary_user="$(state_get PRIMARY_USER 2>/dev/null || true)"
    state_primary_home="$(state_get PRIMARY_HOME 2>/dev/null || true)"

    if [ "$ROOT_ONLY" = "yes" ]; then
        PRIMARY_USER="root"
        PRIMARY_HOME="/root"
        CONFIGURE_ROOT="yes"
    else
        [ -n "$state_primary_user" ] && PRIMARY_USER="$state_primary_user"
        [ -n "$state_primary_home" ] && PRIMARY_HOME="$state_primary_home"
        CONFIGURE_ROOT="$(state_get CONFIGURE_ROOT 2>/dev/null || true)"
    fi

    RUN_SHELLY="$(state_get RUN_SHELLY 2>/dev/null || true)"
    PACKAGE_MODE="$(state_get PACKAGE_MODE 2>/dev/null || true)"
    PACKAGE_PROFILE="$(state_get PACKAGE_PROFILE 2>/dev/null || true)"
    SELECTED_PACKAGE_CATEGORIES="$(state_get SELECTED_PACKAGE_CATEGORIES 2>/dev/null || true)"
    SELECTED_PACKAGES="$(state_get SELECTED_PACKAGES 2>/dev/null || true)"
    EXCLUDED_PACKAGES="$(state_get EXCLUDED_PACKAGES 2>/dev/null || true)"
    EDITOR_SETUP_MODE="$(state_get EDITOR_SETUP_MODE 2>/dev/null || true)"
    EDITOR_CHOICE="$(state_get EDITOR_CHOICE 2>/dev/null || true)"
    INSTALL_EDITOR_CONFIG="$(state_get INSTALL_EDITOR_CONFIG 2>/dev/null || true)"
    INSTALL_EDITOR_PLUGINS="$(state_get INSTALL_EDITOR_PLUGINS 2>/dev/null || true)"
    EDITOR_PROFILE="$(state_get EDITOR_PROFILE 2>/dev/null || true)"
    INSTALL_ALIASES="$(state_get INSTALL_ALIASES 2>/dev/null || true)"
    INSTALL_SSH_CLIENT="$(state_get INSTALL_SSH_CLIENT 2>/dev/null || true)"
    INSTALL_SSHD="$(state_get INSTALL_SSHD 2>/dev/null || true)"
    INSTALL_SUDO="$(state_get INSTALL_SUDO 2>/dev/null || true)"
    INSTALL_DOAS="$(state_get INSTALL_DOAS 2>/dev/null || true)"
    INSTALL_MANPAGES="$(state_get INSTALL_MANPAGES 2>/dev/null || true)"
    INSTALL_COMPLETIONS="$(state_get INSTALL_COMPLETIONS 2>/dev/null || true)"
    GUIDED_PLAN_ACTIVE=1
    export GUIDED_PLAN_ACTIVE
    populate_defaults
}

package_category_members() {
    category="$1"
    case "$category" in
        core) printf '%s\n' 'curl git wget less grep sed coreutils util-linux diffutils findutils file patch unzip zip shadow jq' ;;
        network) printf '%s\n' 'bind-tools busybox-extras iproute2 net-tools' ;;
        ssh) printf '%s\n' 'openssh-server openssh-client-default' ;;
        editors) printf '%s\n' 'vim neovim nano' ;;
        terminal_tools) printf '%s\n' 'tmux htop ripgrep fd tree fzf zoxide neofetch' ;;
        services) printf '%s\n' 'openrc util-linux-openrc iptables-openrc' ;;
        docs) printf '%s\n' 'mandoc man-pages less-doc' ;;
        privilege) printf '%s\n' 'sudo doas' ;;
        *) printf '%s\n' '' ;;
    esac
}

append_unique_words() {
    existing="$1"
    shift
    for word in "$@"; do
        [ -n "$word" ] || continue
        case " $existing " in
            *" $word "*) ;;
            *) existing="${existing:+$existing }$word" ;;
        esac
    done
    printf '%s\n' "$existing"
}

build_selected_package_list_from_state() {
    selected=""

    case "${PACKAGE_MODE:-recommended}" in
        recommended|category)
            categories="${SELECTED_PACKAGE_CATEGORIES:-core,network,ssh,editors}"
            old_ifs=$IFS
            IFS=,
            set -- $categories
            IFS=$old_ifs
            for category in "$@"; do
                category=$(printf '%s' "$category" | sed 's/^ *//; s/ *$//')
                members=$(package_category_members "$category")
                for pkg in $members; do
                    selected=$(append_unique_words "$selected" "$pkg")
                done
            done
            ;;
        package)
            for pkg in ${SELECTED_PACKAGES:-}; do
                selected=$(append_unique_words "$selected" "$pkg")
            done
            ;;
        skip) ;;
    esac

    selected=$(append_unique_words "$selected" shadow)
    [ "${INSTALL_SSH_CLIENT:-yes}" = "yes" ] && selected=$(append_unique_words "$selected" openssh-client-default)
    if [ "${INSTALL_SSHD:-yes}" = "yes" ]; then
        selected=$(append_unique_words "$selected" openssh-server openrc util-linux-openrc iptables-openrc)
    fi
    [ "${INSTALL_SUDO:-yes}" = "yes" ] && selected=$(append_unique_words "$selected" sudo)
    [ "${INSTALL_DOAS:-yes}" = "yes" ] && selected=$(append_unique_words "$selected" doas)
    [ "${INSTALL_MANPAGES:-yes}" = "yes" ] && selected=$(append_unique_words "$selected" mandoc man-pages less-doc)

    printf '%s\n' "$selected"
}

run_pkg_install_list() {
    pkg_list="$1"
    [ -n "$pkg_list" ] || return 0
    for pkg in $pkg_list; do
        pkg_install_alias "$pkg" "$pkg"
    done
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

    if [ "${GUIDED_PLAN_ACTIVE:-0}" != "1" ]; then
        while :; do
            old_user="$PRIMARY_USER"
            PRIMARY_USER="$(prompt_text "Primary username" "$PRIMARY_USER")"
            is_valid_username "$PRIMARY_USER" || { warn "Invalid username."; continue; }
            if [ -z "$PRIMARY_HOME" ] || [ "$PRIMARY_HOME" = "/home/$old_user" ]; then
                if [ "$PRIMARY_USER" = "root" ]; then
                    PRIMARY_HOME="/root"
                else
                    PRIMARY_HOME="/home/$PRIMARY_USER"
                fi
            fi
            break
        done

        while :; do
            PRIMARY_HOME="$(prompt_text "Primary home directory" "$PRIMARY_HOME")"
            is_valid_abs_path "$PRIMARY_HOME" && break
            warn "Use an absolute path like /home/$PRIMARY_USER"
        done
    fi

    if [ "$PRIMARY_USER" = "root" ]; then
        ROOT_PASSWORD="$(prompt_password_confirmed "root")"
        PRIMARY_PASSWORD="$ROOT_PASSWORD"
    else
        PRIMARY_PASSWORD="$(prompt_password_confirmed "$PRIMARY_USER")"
        ROOT_PASSWORD="$(prompt_password_confirmed "root")"
    fi

    if [ "${INSTALL_SSHD:-yes}" = "yes" ]; then
        while :; do
            ISH_LISTEN_PORT="$(prompt_text "iSH sshd listen port" "$ISH_LISTEN_PORT")"
            is_valid_port "$ISH_LISTEN_PORT" && break
            warn "Port must be 1-65535."
        done

        ISH_HOTSPOT_IP="$(prompt_text "Expected iSH hotspot IP used by the home PC" "$ISH_HOTSPOT_IP")"
    fi

    if [ "${INSTALL_SSH_CLIENT:-yes}" = "yes" ]; then
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
    fi

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
    [ "$PRIMARY_USER" = "root" ] || is_valid_username "$PRIMARY_USER" || { err "Invalid PRIMARY_USER"; exit 1; }
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
    if ! cmd_exists bash; then
        if [ "$DRY_RUN" = "1" ]; then
            info "[dry-run] apk add --no-cache bash"
        else
            info "bash not found; installing bash before running Shelly"
            apk add --no-cache bash >/dev/null 2>&1 || { err "failed to install bash for Shelly"; exit 1; }
        fi
    fi

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
    if ! sync_shelly_state_into_installer_state; then
        err "Shelly completed but selection state could not be read"
        exit 1
    fi
    case ",${CONFIGURED_SHELLS:-}," in
        *,${USER_DEFAULT_SHELL:-},*|*,${ROOT_DEFAULT_SHELL:-},*) : ;;
        *) [ -n "${USER_DEFAULT_SHELL:-}${ROOT_DEFAULT_SHELL:-}" ] && { err "Shelly did not confirm configured default shells"; exit 1; } ;;
    esac
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
    if [ "${INSTALL_SUDO:-yes}" = "yes" ] && cmd_exists sudo; then
        mkdir -p /etc/sudoers.d
        printf '%%wheel ALL=(ALL) ALL\n' > /etc/sudoers.d/wheel
        chmod 440 /etc/sudoers.d/wheel
        ok "Configured sudo"
    else
        info "Skipping sudo configuration"
    fi
    if [ "${INSTALL_DOAS:-yes}" = "yes" ] && cmd_exists doas; then
        printf 'permit persist :wheel\n' > /etc/doas.conf
        chmod 0400 /etc/doas.conf
        ok "Configured doas"
    else
        info "Skipping doas configuration"
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
    if [ "${INSTALL_SSHD:-yes}" != "yes" ]; then
        info "Guided plan skipped sshd server configuration"
        return 0
    fi
    run_cmd mkdir -p /etc/ssh /root/.ssh "$PRIMARY_HOME/.ssh"
    run_cmd chmod 700 /root/.ssh "$PRIMARY_HOME/.ssh" 2>/dev/null || true
    run_cmd chown "$PRIMARY_USER:$PRIMARY_USER" "$PRIMARY_HOME/.ssh" 2>/dev/null || true

    generate_host_keys_if_needed

    ensure_sshd_config_key "Port" "${SSHD_PORT:-$ISH_LISTEN_PORT}"
    ensure_sshd_config_key "ListenAddress" "0.0.0.0"
    ensure_sshd_config_key "AllowTcpForwarding" "yes"
    ensure_sshd_config_key "GatewayPorts" "${SSHD_GATEWAY_PORTS:-no}"
    ensure_sshd_config_key "PermitRootLogin" "${SSHD_ALLOW_ROOT:-no}"
    ensure_sshd_config_key "PasswordAuthentication" "${SSHD_PASSWORD_AUTH:-yes}"
    if [ "${SSHD_HOTSPOT_BYPASS:-no}" = "yes" ]; then
        ensure_sshd_config_key "PermitTunnel" "yes"
    else
        ensure_sshd_config_key "PermitTunnel" "no"
    fi
    ensure_sshd_config_key "PubkeyAuthentication" "yes"
    ensure_sshd_config_key "PermitEmptyPasswords" "no"
    ensure_sshd_config_key "Compression" "no"
    ensure_sshd_config_key "PermitTTY" "yes"
    if [ "$DRY_RUN" = "1" ]; then
        ok "Configured sshd server"
        return 0
    fi
    if ! cmd_exists sshd && [ ! -x /usr/sbin/sshd ]; then
        err "sshd binary not found after configuration"
        return 1
    fi
    if cmd_exists sshd; then
        sshd -t >/dev/null 2>&1 || { err "sshd configuration validation failed"; return 1; }
    elif [ -x /usr/sbin/sshd ]; then
        /usr/sbin/sshd -t >/dev/null 2>&1 || { err "sshd configuration validation failed"; return 1; }
    fi
    ok "Configured sshd server"
}

configure_openrc_and_start_sshd() {
    if [ "${INSTALL_SSHD:-yes}" != "yes" ]; then
        info "Guided plan skipped sshd service enable/start"
        return 0
    fi
    if [ "$DRY_RUN" = "1" ]; then
        info "[dry-run] would reconcile requested OpenRC services"
        return 0
    fi
    case " ${ENABLED_SERVICES:-} " in
        *" sshd "*)
            if cmd_exists rc-update; then
                rc-update add sshd default >/dev/null 2>&1 || true
            else
                warn "rc-update not available; sshd will not be enabled at boot"
            fi
            ;;
    esac
    case " ${START_NOW_SERVICES:-} " in
        *" sshd "*)
            started=0
            if cmd_exists service; then
                run_cmd service sshd restart >/dev/null 2>&1 || run_cmd service sshd start >/dev/null 2>&1 && started=1
            fi
            if [ "$started" -ne 1 ] && cmd_exists rc-service; then
                run_cmd rc-service sshd restart >/dev/null 2>&1 || run_cmd rc-service sshd start >/dev/null 2>&1 && started=1
            fi
            if [ "$started" -ne 1 ] && { cmd_exists sshd || [ -x /usr/sbin/sshd ]; }; then
                run_cmd pkill sshd >/dev/null 2>&1 || true
                run_cmd /usr/sbin/sshd >/dev/null 2>&1 || run_cmd sshd >/dev/null 2>&1 && started=1
            fi
            [ "$started" -eq 1 ] || { err "failed to start sshd with available service commands"; return 1; }
            ;;
    esac
    ok "Reconciled requested sshd service state"
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

sync_shelly_state_into_installer_state() {
    read_shelly_selection_state || return 1
    state_set INSTALL_SHELLS "$INSTALL_SHELLS_SELECTED"
    state_set USER_DEFAULT_SHELL "$USER_DEFAULT_SHELL"
    state_set ROOT_DEFAULT_SHELL "$ROOT_DEFAULT_SHELL"
    state_set CONFIGURED_SHELLS "$CONFIGURED_SHELLS"
}

ensure_profile_d_environment() {
    target_home="$1"
    target_user="$2"
    profile_d_dir="$target_home/.config/profile.d"
    editor_env_file="$profile_d_dir/editor.sh"

    run_cmd mkdir -p "$profile_d_dir" || return 1
    if [ "$DRY_RUN" = "1" ]; then
        info "[dry-run] write $editor_env_file"
    else
        cat > "$editor_env_file" <<EOF
export EDITOR=${EDITOR_CHOICE}
export VISUAL=${EDITOR_CHOICE}
EOF
        chown -R "$target_user:$target_user" "$target_home/.config" 2>/dev/null || true
    fi

    shell_rc_files=".profile .shrc .bashrc .zshrc"
    for rc_name in $shell_rc_files; do
        rc_path="$target_home/$rc_name"
        [ -f "$rc_path" ] || continue
        if grep -Fq '. "$HOME/.config/profile.d/editor.sh"' "$rc_path" 2>/dev/null; then
            continue
        fi
        if [ "$DRY_RUN" = "1" ]; then
            info "[dry-run] append editor env hook to $rc_path"
        else
            printf '\n[ -r "$HOME/.config/profile.d/editor.sh" ] && . "$HOME/.config/profile.d/editor.sh"\n' >> "$rc_path"
            chown "$target_user:$target_user" "$rc_path" 2>/dev/null || true
        fi
    done
}

editor_profile_comment() {
    case "${EDITOR_PROFILE:-recommended}" in
        minimal) printf '%s
' 'minimal profile' ;;
        coding) printf '%s
' 'coding profile' ;;
        *) printf '%s
' 'recommended profile' ;;
    esac
}

write_vimrc_for_user() {
    target_home="$1"
    target_user="$2"
    vimrc_path="$target_home/.vimrc"
    vim_dir="$target_home/.vim"

    run_cmd mkdir -p "$vim_dir" || return 1
    if [ "${INSTALL_EDITOR_PLUGINS:-no}" = "yes" ]; then
        run_cmd mkdir -p "$vim_dir/pack/iosish/start/commentary/plugin" || return 1
        if [ "$DRY_RUN" = "1" ]; then
            info "[dry-run] write lightweight vim plugin stub"
        else
            cat > "$vim_dir/pack/iosish/start/commentary/plugin/commentary.vim" <<'EOF'
" Minimal placeholder plugin stub for future repo-managed vim plugins.
command! IOSiSHCommentary echo "Plugin scaffold installed"
EOF
        fi
    fi

    if [ "$DRY_RUN" = "1" ]; then
        info "[dry-run] write $vimrc_path"
        return 0
    fi

    case "${EDITOR_PROFILE:-recommended}" in
        minimal)
            cat > "$vimrc_path" <<EOF
set nocompatible
syntax on
set number
set backspace=indent,eol,start
set hidden
set tabstop=4
set shiftwidth=4
set expandtab
" profile: $(editor_profile_comment)
EOF
            ;;
        coding)
            cat > "$vimrc_path" <<EOF
set nocompatible
syntax on
filetype plugin indent on
set number
set relativenumber
set backspace=indent,eol,start
set wildmenu
set showcmd
set ruler
set hidden
set ignorecase
set smartcase
set incsearch
set hlsearch
set tabstop=4
set shiftwidth=4
set softtabstop=4
set expandtab
set autoindent
set smartindent
set cursorline
set splitbelow
set splitright
set mouse=
set clipboard=
" profile: $(editor_profile_comment)
EOF
            ;;
        *)
            cat > "$vimrc_path" <<EOF
set nocompatible
syntax on
filetype plugin indent on
set number
set backspace=indent,eol,start
set wildmenu
set showcmd
set ruler
set hidden
set ignorecase
set smartcase
set incsearch
set hlsearch
set tabstop=4
set shiftwidth=4
set expandtab
set autoindent
set mouse=
" profile: $(editor_profile_comment)
EOF
            ;;
    esac
    if [ "${INSTALL_EDITOR_PLUGINS:-no}" = "yes" ]; then
        printf 'set runtimepath^=$HOME/.vim/pack/iosish/start/commentary
packloadall
' >> "$vimrc_path"
    fi
    chown -R "$target_user:$target_user" "$vimrc_path" "$vim_dir" 2>/dev/null || true
}

write_nvim_config_for_user() {
    target_home="$1"
    target_user="$2"
    nvim_dir="$target_home/.config/nvim"
    init_lua="$nvim_dir/init.lua"

    run_cmd mkdir -p "$nvim_dir" || return 1
    if [ "${INSTALL_EDITOR_PLUGINS:-no}" = "yes" ]; then
        run_cmd mkdir -p "$nvim_dir/pack/iosish/start/commentary/plugin" || return 1
        if [ "$DRY_RUN" = "1" ]; then
            info "[dry-run] write lightweight neovim plugin stub"
        else
            cat > "$nvim_dir/pack/iosish/start/commentary/plugin/commentary.lua" <<'EOF'
vim.api.nvim_create_user_command("IOSiSHCommentary", function()
  print("Plugin scaffold installed")
end, {})
EOF
        fi
    fi

    if [ "$DRY_RUN" = "1" ]; then
        info "[dry-run] write $init_lua"
        return 0
    fi

    case "${EDITOR_PROFILE:-recommended}" in
        minimal)
            cat > "$init_lua" <<EOF
vim.opt.number = true
vim.opt.expandtab = true
vim.opt.shiftwidth = 4
vim.opt.tabstop = 4
-- profile: $(editor_profile_comment)
EOF
            ;;
        coding)
            cat > "$init_lua" <<EOF
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.hlsearch = true
vim.opt.incsearch = true
vim.opt.expandtab = true
vim.opt.shiftwidth = 4
vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.mouse = ""
vim.opt.splitbelow = true
vim.opt.splitright = true
vim.opt.cursorline = true
vim.opt.termguicolors = false
-- profile: $(editor_profile_comment)
EOF
            ;;
        *)
            cat > "$init_lua" <<EOF
vim.opt.number = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.hlsearch = true
vim.opt.incsearch = true
vim.opt.expandtab = true
vim.opt.shiftwidth = 4
vim.opt.tabstop = 4
vim.opt.mouse = ""
-- profile: $(editor_profile_comment)
EOF
            ;;
    esac
    if [ "${INSTALL_EDITOR_PLUGINS:-no}" = "yes" ]; then
        printf 'vim.opt.runtimepath:prepend(vim.fn.expand("~/.config/nvim/pack/iosish/start/commentary"))
vim.cmd("packloadall")
' >> "$init_lua"
    fi
    chown -R "$target_user:$target_user" "$target_home/.config/nvim" 2>/dev/null || true
}

write_nano_config_for_user() {
    target_home="$1"
    target_user="$2"
    nanorc_path="$target_home/.nanorc"

    if [ "$DRY_RUN" = "1" ]; then
        info "[dry-run] write $nanorc_path"
        return 0
    fi

    case "${EDITOR_PROFILE:-recommended}" in
        minimal)
            cat > "$nanorc_path" <<EOF
set tabsize 4
set autoindent
EOF
            ;;
        coding)
            cat > "$nanorc_path" <<EOF
set linenumbers
set tabsize 4
set autoindent
set smooth
set positionlog
set softwrap
set tabstospaces
EOF
            ;;
        *)
            cat > "$nanorc_path" <<EOF
set linenumbers
set mouse
set tabsize 4
set autoindent
set smooth
EOF
            ;;
    esac
    chown "$target_user:$target_user" "$nanorc_path" 2>/dev/null || true
}

run_editor_setup_from_state() {
    if ! should_run_step editor; then
        info "Skipping editor step; already completed in installer state"
        return 0
    fi
    log_install_event INFO "Starting editor step"
    state_mark_step_started editor || return 1
    info "Editor plan: ${EDITOR_CHOICE:-skip} (${EDITOR_PROFILE:-skip})"

    if [ "${EDITOR_CHOICE:-skip}" = "skip" ]; then
        info "Guided plan skipped editor setup"
        state_mark_step_done editor || return 1
        return 0
    fi

    case "$EDITOR_CHOICE" in
        vim) pkg_install_alias "vim" vim ;;
        neovim) pkg_install_alias "neovim" neovim ;;
        nano) pkg_install_alias "nano" nano ;;
        *) warn "Unknown editor choice: $EDITOR_CHOICE"; state_mark_failed editor; return 1 ;;
    esac

    ensure_profile_d_environment "$PRIMARY_HOME" "$PRIMARY_USER" || { state_mark_failed editor; return 1; }
    [ "$PRIMARY_USER" = "root" ] || ensure_profile_d_environment /root root || true

    if [ "${INSTALL_EDITOR_CONFIG:-yes}" = "yes" ]; then
        case "$EDITOR_CHOICE" in
            vim) write_vimrc_for_user "$PRIMARY_HOME" "$PRIMARY_USER" || { state_mark_failed editor; return 1; } ;;
            neovim) write_nvim_config_for_user "$PRIMARY_HOME" "$PRIMARY_USER" || { state_mark_failed editor; return 1; } ;;
            nano) write_nano_config_for_user "$PRIMARY_HOME" "$PRIMARY_USER" || { state_mark_failed editor; return 1; } ;;
        esac
    else
        info "Guided plan skipped editor config files"
    fi

    state_mark_step_done editor || return 1
    log_install_event INFO "Completed editor step"
}

run_user_setup_from_state() {
    if ! should_run_step users; then
        info "Skipping users step; already completed in installer state"
        return 0
    fi
    log_install_event INFO "Starting users step"
    state_mark_step_started users || return 1
    set_hostname_files || { log_install_event ERROR "users step failed during hostname setup"; state_mark_failed users; return 1; }
    ensure_primary_user || { log_install_event ERROR "users step failed during user creation"; state_mark_failed users; return 1; }
    set_passwords || { log_install_event ERROR "users step failed during password setup"; state_mark_failed users; return 1; }
    state_mark_step_done users || return 1
    log_install_event INFO "Completed users step"
}

run_shell_setup_from_state() {
    if ! should_run_step shells; then
        info "Skipping shells step; already completed in installer state"
        return 0
    fi
    log_install_event INFO "Starting shells step"
    state_mark_step_started shells || return 1
    if [ "${RUN_SHELLY:-yes}" = "yes" ]; then
        run_shelly_setup || { log_install_event ERROR "shells step failed while running Shelly"; state_mark_failed shells; return 1; }
        sync_shelly_state_into_installer_state || warn "Could not import Shelly state into installer state"
    else
        info "Guided plan skipped Shelly shell configuration"
    fi
    state_mark_step_done shells || return 1
    log_install_event INFO "Completed shells step"
}

run_alias_setup_from_state() {
    if [ "${INSTALL_ALIASES:-no}" = "yes" ]; then
        read_shelly_selection_state || {
            warn "Shelly state file missing; skipping optional alias integration"
            return 0
        }
        for shell_name in zsh bash fish; do
            case " $CONFIGURED_SHELLS " in
                *" $shell_name "*|*"$shell_name"*)
                    install_aliases_for_shell "$shell_name" "$PRIMARY_HOME" "$PRIMARY_USER" || true
                    ;;
            esac
        done
    else
        info "Guided plan skipped optional alias integration"
    fi
}

run_package_setup_from_state() {
    if ! should_run_step packages; then
        info "Skipping packages step; already completed in installer state"
        return 0
    fi
    log_install_event INFO "Starting packages step"
    state_mark_step_started packages || return 1
    info "Updating apk indexes"
    run_cmd apk update >/dev/null 2>&1 || warn "apk update failed"
    pkg_list=$(build_selected_package_list_from_state)
    log_install_event INFO "Selected package list: ${pkg_list:-<none>}"
    if [ -n "$pkg_list" ]; then
        info "Installing state-selected packages"
        run_pkg_install_list "$pkg_list"
    else
        info "Guided plan selected no extra packages"
    fi
    state_mark_step_done packages || return 1
    log_install_event INFO "Completed packages step"
}

run_ssh_setup_from_state() {
    if ! should_run_step ssh; then
        info "Skipping ssh step; already completed in installer state"
        return 0
    fi
    log_install_event INFO "Starting ssh step"
    state_mark_step_started ssh || return 1
    if [ "${INSTALL_SSH_CLIENT:-yes}" = "yes" ]; then
        ensure_shared_ssh_keypair
        write_ish_client_config
        write_pc_side_snippets
        link_root_to_shared_assets
    else
        info "Guided plan skipped SSH client configuration"
    fi
    state_mark_step_done ssh || return 1
    log_install_event INFO "Completed ssh step"
}

run_privilege_setup_from_state() {
    if ! should_run_step privilege; then
        info "Skipping privilege step; already completed in installer state"
        return 0
    fi
    log_install_event INFO "Starting privilege step"
    state_mark_step_started privilege || return 1
    if [ "${INSTALL_SUDO:-yes}" = "yes" ] || [ "${INSTALL_DOAS:-yes}" = "yes" ]; then
        configure_sudo_doas || { state_mark_failed privilege; return 1; }
    else
        info "Guided plan skipped sudo/doas configuration"
    fi
    state_mark_step_done privilege || return 1
    log_install_event INFO "Completed privilege step"
}

install_completions_from_state() {
    [ "${INSTALL_COMPLETIONS:-yes}" = "yes" ] || {
        info "Guided plan skipped shell completions"
        return 0
    }
    read_shelly_selection_state || return 0
    case " $CONFIGURED_SHELLS " in
        *" zsh "*|*"zsh"*) pkg_install_alias "zsh-completions" zsh-completions ;;
    esac
    case " $CONFIGURED_SHELLS " in
        *" bash "*|*"bash"*) pkg_install_alias "bash-completion" bash-completion ;;
    esac
}

install_wrapper_script() {
    target_home="$1"
    target_user="$2"
    script_name="$3"
    script_body="$4"
    target_dir="$target_home/.local/bin"
    target_path="$target_dir/$script_name"

    if [ "$DRY_RUN" = "1" ]; then
        info "[dry-run] would write wrapper $target_path"
        return 0
    fi

    mkdir -p "$target_dir" || return 1
    cat > "$target_path" <<EOF
#!/bin/sh
$script_body
EOF
    chmod 755 "$target_path" || return 1
    chown -R "$target_user:$target_user" "$target_home/.local" 2>/dev/null || true
}

install_docs_wrapper_from_state() {
    [ "${INSTALL_DOC_WRAPPER:-no}" = "yes" ] || return 0
    install_wrapper_script "$PRIMARY_HOME" "$PRIMARY_USER" "iosish-docs" 'exec apk add --no-cache "$(printf "%s-doc" "$@")"' || return 1
}

install_completion_wrapper_from_state() {
    [ "${INSTALL_COMPLETION_WRAPPER:-no}" = "yes" ] || return 0
    install_wrapper_script "$PRIMARY_HOME" "$PRIMARY_USER" "iosish-completions" 'echo "Installed completion packages depend on the shells chosen in Shelly. Re-run iOSiSH to reconcile completions."' || return 1
}

run_extras_setup_from_state() {
    if ! should_run_step extras; then
        info "Skipping extras step; already completed in installer state"
        return 0
    fi
    log_install_event INFO "Starting extras step"
    state_mark_step_started extras || return 1
    if [ "${INSTALL_MANPAGES:-yes}" = "yes" ]; then
        install_docs_for_installed_packages
    else
        info "Guided plan skipped manpages/docs installation"
    fi
    install_completions_from_state || true
    install_docs_wrapper_from_state || { state_mark_failed extras; return 1; }
    install_completion_wrapper_from_state || { state_mark_failed extras; return 1; }
    state_mark_step_done extras || return 1
    log_install_event INFO "Completed extras step"
}

run_service_setup_from_state() {
    if ! should_run_step services; then
        info "Skipping services step; already completed in installer state"
        return 0
    fi
    log_install_event INFO "Starting services step"
    state_mark_step_started services || return 1
    if [ "${INSTALL_SSHD:-yes}" = "yes" ]; then
        configure_openrc_and_start_sshd || { state_mark_failed services; return 1; }
    else
        info "Guided plan skipped service enablement"
    fi
    state_mark_step_done services || return 1
    log_install_event INFO "Completed services step"
}

mark_step_pending_from() {
    step=$1
    case "$step" in
        users) state_set STEP_USERS_DONE "no" ; state_set STEP_SHELLS_DONE "no" ; state_set STEP_PACKAGES_DONE "no" ; state_set STEP_EDITOR_DONE "no" ; state_set STEP_SSH_DONE "no" ; state_set STEP_SSHD_DONE "no" ; state_set STEP_PRIVILEGE_DONE "no" ; state_set STEP_SERVICES_DONE "no" ; state_set STEP_EXTRAS_DONE "no" ;;
        shells) state_set STEP_SHELLS_DONE "no" ; state_set STEP_SSH_DONE "no" ; state_set STEP_SSHD_DONE "no" ; state_set STEP_SERVICES_DONE "no" ; state_set STEP_EXTRAS_DONE "no" ;;
        packages) state_set STEP_PACKAGES_DONE "no" ; state_set STEP_EDITOR_DONE "no" ; state_set STEP_PRIVILEGE_DONE "no" ; state_set STEP_EXTRAS_DONE "no" ; state_set STEP_SERVICES_DONE "no" ;;
        editor) state_set STEP_EDITOR_DONE "no" ;;
        ssh) state_set STEP_SSH_DONE "no" ; state_set STEP_SSHD_DONE "no" ; state_set STEP_SERVICES_DONE "no" ;;
        sshd) state_set STEP_SSHD_DONE "no" ; state_set STEP_SERVICES_DONE "no" ;;
        services) state_set STEP_SERVICES_DONE "no" ;;
        privilege) state_set STEP_PRIVILEGE_DONE "no" ;;
        extras) state_set STEP_EXTRAS_DONE "no" ;;
    esac
    state_set CURRENT_STEP ""
    state_set INSTALL_STATUS "in_progress"
}

rerun_completed_section() {
    step=$1
    [ -n "$step" ] || return 1
    mark_step_pending_from "$step" || return 1
    log_install_event INFO "Marked section for rerun: $step"
}

edit_plan_section() {
    section=$1
    case "$section" in
        preferences) plan_installer_preferences ;;
        users) plan_user_setup ; mark_step_pending_from users ;;
        shells) plan_shell_setup ; mark_step_pending_from shells ;;
        packages) plan_package_setup ; mark_step_pending_from packages ;;
        editor) plan_editor_setup ; mark_step_pending_from editor ;;
        ssh) plan_ssh_setup ; mark_step_pending_from ssh ;;
        sshd) plan_sshd_service_setup "${INSTALL_SSHD:-yes}" ; mark_step_pending_from ssh ;;
        services) plan_sshd_service_setup "${INSTALL_SSHD:-yes}" ; mark_step_pending_from ssh ;;
        privilege) plan_privilege_setup ; mark_step_pending_from privilege ;;
        extras) plan_extras_setup ; mark_step_pending_from extras ;;
        *) return 1 ;;
    esac
}

should_run_step() {
    step=$1
    if state_step_done "$step"; then
        return 1
    fi
    return 0
}

run_guided_planning_phase() {
    load_guided_installer_modules || return 1

    state_ensure_file || return 1

    if ! state_has_key INSTALL_STATUS; then
        state_init_defaults || return 1
    fi

    state_load || return 1

    printf '\n'
    printf '== iOSiSH Guided Installer Planning ==\n'

    install_status=$(state_get INSTALL_STATUS)

    if [ "$install_status" = "new" ] || ! state_any_completed; then
        run_planning_phase || return 1
    else
        show_resume_summary
        resume_action=$(prompt_resume_action) || return 1
        case "$resume_action" in
            resume)
                log_install_event INFO "Resuming installer from saved state"
                ;;
            review)
                log_install_event INFO "Reviewing saved installer state before execution"
                ;;
            reset)
                state_reset || return 1
                state_load || return 1
                run_planning_phase || return 1
                ;;
            quit)
                log_install_event INFO "Installer exited from resume prompt"
                return 1
                ;;
        esac
    fi

    while :; do
        state_load || return 1
        show_plan_summary
        show_progress_summary
        if state_any_completed; then
            show_resume_summary
        fi

        summary_action=$(prompt_summary_action) || return 1
        case "$summary_action" in
            proceed)
                apply_guided_state_to_runtime || return 1
                return 0
                ;;
            edit)
                section=$(prompt_edit_section) || return 1
                edit_plan_section "$section" || return 1
                ;;
            rerun)
                rerun_section=$(prompt_rerun_section) || return 1
                rerun_completed_section "$rerun_section" || return 1
                ;;
            save-quit)
                state_set INSTALL_STATUS "in_progress"
                log_install_event INFO "Saved installer plan and exited before execution"
                return 2
                ;;
            reset)
                state_reset || return 1
                state_load || return 1
                run_planning_phase || return 1
                ;;
            quit)
                log_install_event INFO "Installer cancelled during planning summary"
                return 1
                ;;
        esac
    done
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
    init_runtime_log
    run_guided_planning_phase
    planning_rc=$?
    case "$planning_rc" in
        0) ;;
        2)
            say "Installer plan saved to $(state_file_path). Exiting before execution."
            exit 0
            ;;
        *)
            err "guided planning phase failed or was cancelled"
            exit 1
            ;;
    esac
    require_root
    apply_guided_state_to_runtime || {
        err "failed to apply guided installer state"
        exit 1
    }
    collect_config
    validate_config

    run_package_setup_from_state || exit 1
    run_editor_setup_from_state || exit 1
    run_user_setup_from_state || exit 1
    run_shell_setup_from_state || exit 1
    run_alias_setup_from_state || exit 1
    run_ssh_setup_from_state || exit 1
    run_privilege_setup_from_state || exit 1
    if should_run_step sshd; then
        log_install_event INFO "Starting sshd step"
        state_mark_step_started sshd || true
        configure_sshd_server || { log_install_event ERROR "sshd step failed"; state_mark_failed sshd || true; exit 1; }
        state_mark_step_done sshd || true
        log_install_event INFO "Completed sshd step"
    else
        info "Skipping sshd step; already completed in installer state"
    fi
    fix_permissions
    run_service_setup_from_state || exit 1
    run_extras_setup_from_state || exit 1
    state_mark_complete || true
    log_install_event INFO "Installer run completed successfully"

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
