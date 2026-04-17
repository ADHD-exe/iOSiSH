#!/bin/sh
# installer/plan.sh
# Planning helpers for guided installer sections.

package_catalog_categories() {
    printf '%s\n' \
        core \
        network \
        ssh \
        editors \
        terminal_tools \
        services \
        docs \
        privilege
}

package_catalog_description() {
    category=$1
    case "$category" in
        core) printf '%s\n' 'Base tools: curl, git, wget, less, jq, file utilities.' ;;
        network) printf '%s\n' 'Network helpers and client-side connectivity tools.' ;;
        ssh) printf '%s\n' 'SSH client/server packages and server prerequisites.' ;;
        editors) printf '%s\n' 'Editor packages such as vim, neovim, and nano.' ;;
        terminal_tools) printf '%s\n' 'Terminal quality-of-life tools like tmux, htop, tree, fzf.' ;;
        services) printf '%s\n' 'OpenRC-related service support packages.' ;;
        docs) printf '%s\n' 'Manpages and local command documentation packages.' ;;
        privilege) printf '%s\n' 'Privilege escalation tools such as sudo and doas.' ;;
        *) printf '%s\n' 'Unknown category.' ;;
    esac
}

package_catalog_members() {
    category=$1
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

show_package_catalog() {
    printf '\nAvailable package categories:\n'
    for category in $(package_catalog_categories); do
        printf '  - %s\n' "$category"
        printf '      %s\n' "$(package_catalog_description "$category")"
        printf '      packages: %s\n' "$(package_catalog_members "$category")"
    done
    printf '\n'
}

normalize_csv_list() {
    input=$1
    output=""
    old_ifs=$IFS
    IFS=,
    set -- $input
    IFS=$old_ifs

    for item in "$@"; do
        item=$(printf '%s' "$item" | sed 's/^ *//; s/ *$//')
        [ -n "$item" ] || continue
        case ",$output," in
            *",$item,"*) ;;
            *) output="${output:+$output,}$item" ;;
        esac
    done

    printf '%s\n' "$output"
}

validate_category_list() {
    categories=$(normalize_csv_list "$1")
    [ -n "$categories" ] || return 1

    old_ifs=$IFS
    IFS=,
    set -- $categories
    IFS=$old_ifs

    for category in "$@"; do
        valid=no
        for known in $(package_catalog_categories); do
            [ "$category" = "$known" ] && { valid=yes; break; }
        done
        [ "$valid" = "yes" ] || return 1
    done

    return 0
}

prompt_package_categories() {
    while :; do
        show_package_catalog
        printf 'Enter category list (comma-separated) or type all [core,network,ssh,editors]: '
        read -r categories || return 1
        [ -n "$categories" ] || categories='core,network,ssh,editors'

        if [ "$categories" = 'all' ]; then
            package_catalog_categories | paste -sd, -
            return 0
        fi

        categories=$(normalize_csv_list "$categories")
        if validate_category_list "$categories"; then
            printf '%s\n' "$categories"
            return 0
        fi

        printf 'Invalid category list. Use category IDs exactly as shown above.\n' >&2
    done
}

prompt_package_list() {
    while :; do
        printf 'Enter package list (space-separated): '
        read -r packages || return 1
        [ -n "$packages" ] || {
            printf 'Please enter at least one package, or choose another package mode.
' >&2
            continue
        }
        invalid=""
        for pkg in $packages; do
            case "$pkg" in
                *[!A-Za-z0-9+._-]*) invalid="$invalid $pkg" ;;
            esac
        done
        if [ -n "$invalid" ]; then
            printf 'These package names look invalid:%s
' "$invalid" >&2
            continue
        fi
        printf '%s
' "$packages"
        return 0
    done
}

prompt_package_exclusions() {
    while :; do
        printf 'Enter packages to exclude (space-separated) or leave blank for none: '
        read -r excluded || return 1
        [ -n "$excluded" ] || {
            printf '
'
            return 0
        }
        invalid=""
        for pkg in $excluded; do
            case "$pkg" in
                *[!A-Za-z0-9+._-]*) invalid="$invalid $pkg" ;;
            esac
        done
        if [ -n "$invalid" ]; then
            printf 'These package names look invalid:%s
' "$invalid" >&2
            continue
        fi
        printf '%s
' "$excluded"
        return 0
    done
}

build_package_preview_from_state() {
    selected=""

    case "${PACKAGE_MODE:-recommended}" in
        recommended|all-categories|category)
            categories="${SELECTED_PACKAGE_CATEGORIES:-core,network,ssh,editors}"
            old_ifs=$IFS
            IFS=,
            set -- $categories
            IFS=$old_ifs
            for category in "$@"; do
                category=$(printf '%s' "$category" | sed 's/^ *//; s/ *$//')
                members=$(package_catalog_members "$category")
                for pkg in $members; do
                    case " $selected " in
                        *" $pkg "*) ;;
                        *) selected="${selected:+$selected }$pkg" ;;
                    esac
                done
            done
            ;;
        package)
            for pkg in ${SELECTED_PACKAGES:-}; do
                case " $selected " in
                    *" $pkg "*) ;;
                    *) selected="${selected:+$selected }$pkg" ;;
                esac
            done
            ;;
        skip) ;;
    esac

    if [ -n "${EXCLUDED_PACKAGES:-}" ] && [ -n "$selected" ]; then
        filtered=""
        for pkg in $selected; do
            case " ${EXCLUDED_PACKAGES} " in
                *" $pkg "*) ;;
                *) filtered="${filtered:+$filtered }$pkg" ;;
            esac
        done
        selected="$filtered"
    fi

    printf '%s
' "$selected"
}

show_package_plan_review() {
    printf '
== Package Plan Review ==
'
    printf 'Mode:        %s
' "${PACKAGE_MODE:-}"
    printf 'Profile:     %s
' "${PACKAGE_PROFILE:-}"
    printf 'Categories:  %s
' "${SELECTED_PACKAGE_CATEGORIES:-<none>}"
    printf 'Packages:    %s
' "${SELECTED_PACKAGES:-<none>}"
    printf 'Excluded:    %s
' "${EXCLUDED_PACKAGES:-<none>}"
    printf 'Final list:  %s
' "$(build_package_preview_from_state)"
}

prompt_package_plan_action() {
    printf '
Package plan actions:
'
    printf '  - proceed
' >&2
    printf '  - edit-mode
' >&2
    printf '  - edit-categories
' >&2
    printf '  - edit-packages
' >&2
    printf '  - edit-exclusions
' >&2
    while :; do
        printf 'Choice [proceed]: ' >&2
        if [ "${NONINTERACTIVE:-0}" = "1" ]; then
            reply="proceed"
        else
            read -r reply || return 1
            [ -n "$reply" ] || reply="proceed"
        fi
        case "$reply" in
            proceed|edit-mode|edit-categories|edit-packages|edit-exclusions)
                printf '%s
' "$reply"
                return 0
                ;;
        esac
        printf 'Invalid choice.
' >&2
    done
}


plan_installer_preferences() {
    print_section_header "Installer Preferences"
    print_help_text "Choose how much output you want and whether color should be enabled by default."

    COLOR_OUTPUT=$(prompt_choice "Choose color output mode:" "auto" "auto" "on" "off") || return 1
    OUTPUT_MODE=$(prompt_choice "Choose output mode:" "normal" "quiet" "normal" "verbose") || return 1

    state_set COLOR_OUTPUT "$COLOR_OUTPUT"
    state_set OUTPUT_MODE "$OUTPUT_MODE"
}

plan_user_setup() {
    print_section_header "User and Root Setup"
    print_help_text "Choose whether to configure only root or both root and a primary non-root user."

    root_only=$(prompt_yes_no "Configure root only?" "no") || return 1
    state_set ROOT_ONLY "$root_only"

    if [ "$root_only" = "yes" ]; then
        state_set CONFIGURE_ROOT "yes"
        state_set PRIMARY_USER ""
        state_set PRIMARY_HOME "/root"
        return 0
    fi

    printf 'Enter primary username [rabbit]: ' >&2
    if [ "${NONINTERACTIVE:-0}" = "1" ]; then
        primary_user=${PRIMARY_USER:-rabbit}
    else
        read -r primary_user || return 1
        [ -n "$primary_user" ] || primary_user="${PRIMARY_USER:-rabbit}"
    fi

    state_set PRIMARY_USER "$primary_user"
    state_set PRIMARY_HOME "/home/$primary_user"
    state_set CONFIGURE_ROOT "yes"
}

plan_shell_setup() {
    print_section_header "Shell Setup"
    print_help_text "Shelly handles shell installation and configuration. You can skip it and keep the current shell state if needed."

    run_shelly=$(prompt_yes_no "Run Shelly for shell configuration?" "yes") || return 1
    state_set RUN_SHELLY "$run_shelly"
}

configure_package_mode_state() {
    package_mode=$1
    state_set PACKAGE_MODE "$package_mode"
    state_set PACKAGE_PROFILE ""
    state_set EXCLUDED_PACKAGES ""

    case "$package_mode" in
        skip)
            state_set PACKAGE_PROFILE "skip"
            state_set SELECTED_PACKAGE_CATEGORIES ""
            state_set SELECTED_PACKAGES ""
            ;;
        recommended)
            state_set PACKAGE_PROFILE "recommended"
            state_set SELECTED_PACKAGE_CATEGORIES "core,network,ssh,editors"
            state_set SELECTED_PACKAGES ""
            ;;
        all-categories)
            state_set PACKAGE_PROFILE "all-categories"
            state_set SELECTED_PACKAGE_CATEGORIES "$(package_catalog_categories | paste -sd, -)"
            state_set SELECTED_PACKAGES ""
            ;;
        category)
            categories=$(prompt_package_categories) || return 1
            state_set PACKAGE_PROFILE "custom-categories"
            state_set SELECTED_PACKAGE_CATEGORIES "$categories"
            state_set SELECTED_PACKAGES ""
            ;;
        package)
            packages=$(prompt_package_list) || return 1
            state_set PACKAGE_PROFILE "custom-packages"
            state_set SELECTED_PACKAGE_CATEGORIES ""
            state_set SELECTED_PACKAGES "$packages"
            ;;
        *)
            return 1
            ;;
    esac
}

plan_package_setup() {
    package_mode=$(prompt_choice         "Choose package setup mode:"         "recommended"         "skip" "recommended" "all-categories" "category" "package") || return 1

    configure_package_mode_state "$package_mode" || return 1

    if [ "$package_mode" != "skip" ]; then
        if [ "${NONINTERACTIVE:-0}" = "1" ]; then
            excluded="${EXCLUDED_PACKAGES:-}"
        else
            excluded=$(prompt_package_exclusions) || return 1
        fi
        state_set EXCLUDED_PACKAGES "$excluded"
    fi

    while :; do
        state_load || return 1
        show_package_plan_review
        action=$(prompt_package_plan_action) || return 1
        case "$action" in
            proceed)
                return 0
                ;;
            edit-mode)
                package_mode=$(prompt_choice                     "Choose package setup mode:"                     "${PACKAGE_MODE:-recommended}"                     "skip" "recommended" "all-categories" "category" "package") || return 1
                configure_package_mode_state "$package_mode" || return 1
                if [ "$package_mode" != "skip" ]; then
                    if [ "${NONINTERACTIVE:-0}" = "1" ]; then
                        excluded="${EXCLUDED_PACKAGES:-}"
                    else
                        excluded=$(prompt_package_exclusions) || return 1
                    fi
                    state_set EXCLUDED_PACKAGES "$excluded"
                fi
                ;;
            edit-categories)
                if [ "${PACKAGE_MODE:-}" = "category" ] || [ "${PACKAGE_MODE:-}" = "recommended" ] || [ "${PACKAGE_MODE:-}" = "all-categories" ]; then
                    categories=$(prompt_package_categories) || return 1
                    state_set SELECTED_PACKAGE_CATEGORIES "$categories"
                    state_set PACKAGE_MODE "category"
                    state_set PACKAGE_PROFILE "custom-categories"
                else
                    printf 'Current mode is not category-based. Use edit-mode first if you want categories.
' >&2
                fi
                ;;
            edit-packages)
                packages=$(prompt_package_list) || return 1
                state_set SELECTED_PACKAGES "$packages"
                state_set SELECTED_PACKAGE_CATEGORIES ""
                state_set PACKAGE_MODE "package"
                state_set PACKAGE_PROFILE "custom-packages"
                ;;
            edit-exclusions)
                excluded=$(prompt_package_exclusions) || return 1
                state_set EXCLUDED_PACKAGES "$excluded"
                ;;
        esac
    done
}

editor_choice_description() {
    choice=$1
    case "$choice" in
        vim) printf '%s
' 'Classic editor with a simple .vimrc path and low overhead.' ;;
        neovim) printf '%s
' 'Modern Vim fork with Lua config and easier future plugin growth.' ;;
        nano) printf '%s
' 'Very simple editor with a lightweight .nanorc setup.' ;;
        skip) printf '%s
' 'Do not configure a system editor in this installer run.' ;;
        *) printf '%s
' 'Unknown editor option.' ;;
    esac
}

show_editor_choices() {
    printf '
Editor options:
' >&2
    for choice in vim neovim nano skip; do
        printf '  - %s
' "$choice"
        printf '      %s
' "$(editor_choice_description "$choice")"
    done
}

show_editor_plan_review() {
    printf '
== Editor Plan Review ==
'
    printf 'Editor:      %s
' "${EDITOR_CHOICE:-skip}"
    printf 'Profile:     %s
' "${EDITOR_PROFILE:-skip}"
    printf 'Write config:%s
' " ${INSTALL_EDITOR_CONFIG:-no}"
    printf 'Plugins:     %s
' "${INSTALL_EDITOR_PLUGINS:-no}"
}

prompt_editor_plan_action() {
    printf '
Editor plan actions:
'
    printf '  - proceed
'
    printf '  - edit-editor
'
    printf '  - edit-profile
'
    printf '  - edit-config
'
    printf '  - edit-plugins
'
    while :; do
        printf 'Choice [proceed]: ' >&2
        if [ "${NONINTERACTIVE:-0}" = "1" ]; then
            reply="proceed"
        else
            read -r reply || return 1
            [ -n "$reply" ] || reply="proceed"
        fi
        case "$reply" in
            proceed|edit-editor|edit-profile|edit-config|edit-plugins)
                printf '%s
' "$reply"
                return 0
                ;;
        esac
        printf 'Invalid choice.
' >&2
    done
}

configure_editor_state() {
    editor_choice=$1
    state_set EDITOR_CHOICE "$editor_choice"

    if [ "$editor_choice" = "skip" ]; then
        state_set INSTALL_EDITOR_CONFIG "no"
        state_set INSTALL_EDITOR_PLUGINS "no"
        state_set EDITOR_PROFILE "skip"
        return 0
    fi

    editor_profile=$(prompt_choice "Choose editor profile:" "recommended" "minimal" "recommended" "coding") || return 1
    install_editor_config=$(prompt_yes_no "Install a starter ${editor_choice} configuration?" "yes") || return 1

    case "$editor_choice" in
        vim|neovim)
            install_editor_plugins=$(prompt_yes_no "Install a lightweight plugin-ready setup for ${editor_choice}?" "no") || return 1
            ;;
        *)
            install_editor_plugins="no"
            ;;
    esac

    state_set INSTALL_EDITOR_CONFIG "$install_editor_config"
    state_set INSTALL_EDITOR_PLUGINS "$install_editor_plugins"
    state_set EDITOR_PROFILE "$editor_profile"
}

plan_editor_setup() {
    editor_mode=$(prompt_choice "How would you like to handle editor setup?" "recommended" "skip" "recommended" "customize") || return 1

    case "$editor_mode" in
        skip)
            state_set EDITOR_SETUP_MODE "skip"
            configure_editor_state skip || return 1
            return 0
            ;;
        recommended)
            state_set EDITOR_SETUP_MODE "recommended"
            state_set EDITOR_CHOICE "vim"
            state_set EDITOR_PROFILE "recommended"
            state_set INSTALL_EDITOR_CONFIG "yes"
            state_set INSTALL_EDITOR_PLUGINS "no"
            ;;
        customize)
            state_set EDITOR_SETUP_MODE "customize"
            show_editor_choices
            editor_choice=$(prompt_choice "Choose system editor:" "vim" "skip" "vim" "neovim" "nano") || return 1
            configure_editor_state "$editor_choice" || return 1
            ;;
    esac

    while :; do
        state_load || return 1
        show_editor_plan_review
        action=$(prompt_editor_plan_action) || return 1
        case "$action" in
            proceed)
                return 0
                ;;
            edit-editor)
                show_editor_choices
                editor_choice=$(prompt_choice "Choose system editor:" "${EDITOR_CHOICE:-vim}" "skip" "vim" "neovim" "nano") || return 1
                configure_editor_state "$editor_choice" || return 1
                ;;
            edit-profile)
                if [ "${EDITOR_CHOICE:-skip}" = "skip" ]; then
                    printf 'Current editor choice is skip. Use edit-editor first.
' >&2
                else
                    editor_profile=$(prompt_choice "Choose editor profile:" "${EDITOR_PROFILE:-recommended}" "minimal" "recommended" "coding") || return 1
                    state_set EDITOR_PROFILE "$editor_profile"
                fi
                ;;
            edit-config)
                if [ "${EDITOR_CHOICE:-skip}" = "skip" ]; then
                    printf 'Current editor choice is skip. Use edit-editor first.
' >&2
                else
                    install_editor_config=$(prompt_yes_no "Install a starter ${EDITOR_CHOICE} configuration?" "${INSTALL_EDITOR_CONFIG:-yes}") || return 1
                    state_set INSTALL_EDITOR_CONFIG "$install_editor_config"
                fi
                ;;
            edit-plugins)
                case "${EDITOR_CHOICE:-skip}" in
                    vim|neovim)
                        install_editor_plugins=$(prompt_yes_no "Install a lightweight plugin-ready setup for ${EDITOR_CHOICE}?" "${INSTALL_EDITOR_PLUGINS:-no}") || return 1
                        state_set INSTALL_EDITOR_PLUGINS "$install_editor_plugins"
                        ;;
                    skip)
                        printf 'Current editor choice is skip. Use edit-editor first.
' >&2
                        ;;
                    *)
                        printf 'Plugin scaffolding is only available for vim and neovim right now.
' >&2
                        ;;
                esac
                ;;
        esac
    done
}

is_valid_port() {
    port=$1
    case "$port" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ "$port" -ge 1 ] && [ "$port" -le 65535 ]
}

prompt_sshd_port() {
    default_port=${1:-2222}
    while :; do
        printf 'Enter SSHD port [%s]: ' "$default_port"
        read -r sshd_port || return 1
        [ -n "$sshd_port" ] || sshd_port="$default_port"
        if is_valid_port "$sshd_port"; then
            printf '%s
' "$sshd_port"
            return 0
        fi
        printf 'Please enter a numeric port between 1 and 65535.
' >&2
    done
}

normalize_service_list() {
    services=$1
    normalized=""
    seen=" "
    for service in $services; do
        case "$service" in
            sshd)
                case "$seen" in
                    *" $service "*) ;;
                    *)
                        normalized="$normalized $service"
                        seen="$seen$service "
                        ;;
                esac
                ;;
        esac
    done
    printf '%s
' "$(printf '%s' "$normalized" | sed 's/^ *//;s/  */ /g;s/ *$//')"
}

prompt_service_targets() {
    prompt_text=$1
    default_services=$2
    printf '%s
' "$prompt_text"
    printf 'Available services: sshd
'
    printf 'Enter a space-separated service list or leave blank for none.
'
    while :; do
        if [ -n "$default_services" ]; then
            printf 'Services [%s]: ' "$default_services"
        else
            printf 'Services [none]: '
        fi
        read -r services || return 1
        [ -n "$services" ] || services="$default_services"
        normalized=$(normalize_service_list "$services") || return 1
        if [ -z "$services" ] || [ -n "$normalized" ] || [ -z "$default_services" ]; then
            printf '%s
' "$normalized"
            return 0
        fi
        printf 'Only supported services may be selected right now: sshd
' >&2
    done
}

plan_sshd_service_setup() {
    install_sshd=$1
    if [ "$install_sshd" = "yes" ]; then
        sshd_profile=$(prompt_choice "Choose SSHD setup mode:" "recommended" "recommended" "relaxed" "custom") || return 1
        case "$sshd_profile" in
            recommended)
                sshd_port="2222"
                sshd_allow_root="no"
                sshd_password_auth="yes"
                sshd_gateway_ports="no"
                sshd_hotspot_bypass="no"
                ;;
            relaxed)
                sshd_port="2222"
                sshd_allow_root="yes"
                sshd_password_auth="yes"
                sshd_gateway_ports="yes"
                sshd_hotspot_bypass="yes"
                ;;
            custom)
                sshd_port=$(prompt_sshd_port "2222") || return 1
                sshd_allow_root=$(prompt_yes_no "Allow root login over SSHD?" "no") || return 1
                sshd_password_auth=$(prompt_yes_no "Allow SSHD password authentication?" "yes") || return 1
                sshd_gateway_ports=$(prompt_yes_no "Enable SSHD GatewayPorts?" "no") || return 1
                sshd_hotspot_bypass=$(prompt_yes_no "Enable hotspot-bypass-friendly SSHD settings?" "no") || return 1
                ;;
        esac
        sshd_enable_at_boot=$(prompt_yes_no "Enable SSHD at boot with OpenRC?" "yes") || return 1
        sshd_start_now=$(prompt_yes_no "Start SSHD immediately after setup?" "yes") || return 1

        default_enabled=""
        default_started=""
        [ "$sshd_enable_at_boot" = "yes" ] && default_enabled="sshd"
        [ "$sshd_start_now" = "yes" ] && default_started="sshd"
        enabled_services=$(prompt_service_targets "Select services to enable at boot." "$default_enabled") || return 1
        start_now_services=$(prompt_service_targets "Select services to start immediately." "$default_started") || return 1

        case " $enabled_services " in
            *" sshd "*) sshd_enable_at_boot="yes" ;;
            *) sshd_enable_at_boot="no" ;;
        esac
        case " $start_now_services " in
            *" sshd "*) sshd_start_now="yes" ;;
            *) sshd_start_now="no" ;;
        esac

        state_set SSHD_PROFILE "$sshd_profile"
        state_set SSHD_PORT "$sshd_port"
        state_set SSHD_ALLOW_ROOT "$sshd_allow_root"
        state_set SSHD_PASSWORD_AUTH "$sshd_password_auth"
        state_set SSHD_GATEWAY_PORTS "$sshd_gateway_ports"
        state_set SSHD_HOTSPOT_BYPASS "$sshd_hotspot_bypass"
        state_set SSHD_ENABLE_AT_BOOT "$sshd_enable_at_boot"
        state_set SSHD_START_NOW "$sshd_start_now"
        [ "$sshd_hotspot_bypass" = "yes" ] && state_set SSH_RELAXED "1" || state_set SSH_RELAXED "0"
        state_set ENABLED_SERVICES "$enabled_services"
        state_set START_NOW_SERVICES "$start_now_services"
    else
        state_set SSHD_PROFILE "disabled"
        state_set SSHD_PORT ""
        state_set SSHD_ALLOW_ROOT "no"
        state_set SSHD_PASSWORD_AUTH "no"
        state_set SSHD_GATEWAY_PORTS "no"
        state_set SSHD_HOTSPOT_BYPASS "no"
        state_set SSHD_ENABLE_AT_BOOT "no"
        state_set SSHD_START_NOW "no"
        state_set ENABLED_SERVICES ""
        state_set START_NOW_SERVICES ""
    fi
}

plan_ssh_setup() {
    install_ssh_client=$(prompt_yes_no "Install SSH client tools?" "yes") || return 1
    install_sshd=$(prompt_yes_no "Install and configure SSHD?" "yes") || return 1

    state_set INSTALL_SSH_CLIENT "$install_ssh_client"
    state_set INSTALL_SSHD "$install_sshd"

    plan_sshd_service_setup "$install_sshd" || return 1
}

plan_privilege_setup() {
    install_sudo=$(prompt_yes_no "Install sudo?" "yes") || return 1
    install_doas=$(prompt_yes_no "Install doas?" "yes") || return 1

    state_set INSTALL_SUDO "$install_sudo"
    state_set INSTALL_DOAS "$install_doas"
}

plan_extras_setup() {
    install_manpages=$(prompt_yes_no "Install manpages?" "yes") || return 1
    install_completions=$(prompt_yes_no "Install shell completions?" "yes") || return 1
    install_doc_wrapper=$(prompt_yes_no "Install an iosish-docs wrapper command?" "no") || return 1
    install_completion_wrapper=$(prompt_yes_no "Install an iosish-completions wrapper command?" "no") || return 1
    install_aliases=$(prompt_yes_no "Install shell aliases?" "yes") || return 1

    state_set INSTALL_MANPAGES "$install_manpages"
    state_set INSTALL_COMPLETIONS "$install_completions"
    state_set INSTALL_DOC_WRAPPER "$install_doc_wrapper"
    state_set INSTALL_COMPLETION_WRAPPER "$install_completion_wrapper"
    state_set INSTALL_ALIASES "$install_aliases"
}

run_planning_phase() {
    plan_installer_preferences || return 1
    plan_user_setup || return 1
    plan_shell_setup || return 1
    plan_package_setup || return 1
    plan_editor_setup || return 1
    plan_ssh_setup || return 1
    plan_privilege_setup || return 1
    plan_extras_setup || return 1
}
