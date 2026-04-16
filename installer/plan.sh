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
            printf 'Please enter at least one package, or choose another package mode.\n' >&2
            continue
        }
        printf '%s\n' "$packages"
        return 0
    done
}

plan_installer_preferences() {
    COLOR_OUTPUT=$(prompt_choice "Choose color output mode:" "auto" "auto" "on" "off") || return 1
    OUTPUT_MODE=$(prompt_choice "Choose output mode:" "normal" "quiet" "normal" "verbose") || return 1

    state_set COLOR_OUTPUT "$COLOR_OUTPUT"
    state_set OUTPUT_MODE "$OUTPUT_MODE"
}

plan_user_setup() {
    root_only=$(prompt_yes_no "Configure root only?" "no") || return 1
    state_set ROOT_ONLY "$root_only"

    if [ "$root_only" = "yes" ]; then
        state_set CONFIGURE_ROOT "yes"
        state_set PRIMARY_USER ""
        state_set PRIMARY_HOME "/root"
        return 0
    fi

    printf 'Enter primary username [user]: '
    read -r primary_user || return 1
    [ -n "$primary_user" ] || primary_user="user"

    state_set PRIMARY_USER "$primary_user"
    state_set PRIMARY_HOME "/home/$primary_user"
    state_set CONFIGURE_ROOT "yes"
}

plan_shell_setup() {
    run_shelly=$(prompt_yes_no "Run Shelly for shell configuration?" "yes") || return 1
    state_set RUN_SHELLY "$run_shelly"
}

plan_package_setup() {
    package_mode=$(prompt_choice \
        "Choose package setup mode:" \
        "recommended" \
        "skip" "recommended" "all-categories" "category" "package") || return 1

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
    esac
}

plan_editor_setup() {
    editor_choice=$(prompt_choice         "Choose system editor:"         "vim"         "skip" "vim" "neovim" "nano") || return 1

    state_set EDITOR_CHOICE "$editor_choice"

    if [ "$editor_choice" = "skip" ]; then
        state_set INSTALL_EDITOR_CONFIG "no"
        state_set INSTALL_EDITOR_PLUGINS "no"
        state_set EDITOR_PROFILE "skip"
        return 0
    fi

    editor_profile=$(prompt_choice         "Choose editor profile:"         "recommended"         "minimal" "recommended" "coding") || return 1
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

plan_ssh_setup() {
    install_ssh_client=$(prompt_yes_no "Install SSH client tools?" "yes") || return 1
    install_sshd=$(prompt_yes_no "Install and configure SSHD?" "yes") || return 1

    state_set INSTALL_SSH_CLIENT "$install_ssh_client"
    state_set INSTALL_SSHD "$install_sshd"

    if [ "$install_sshd" = "yes" ]; then
        sshd_mode=$(prompt_choice "Choose SSHD setup mode:" "recommended" "recommended" "customize") || return 1
        case "$sshd_mode" in
            recommended)
                state_set SSHD_PORT "22"
                state_set SSHD_ALLOW_ROOT "no"
                state_set SSHD_PASSWORD_AUTH "yes"
                state_set SSHD_HOTSPOT_BYPASS "no"
                state_set ENABLE_SSHD_SERVICE "yes"
                state_set START_SSHD_NOW "yes"
                state_set ENABLED_SERVICES "sshd"
                state_set START_NOW_SERVICES "sshd"
                ;;
            customize)
                sshd_port=$(prompt_text_entry "Choose SSHD listen port" "22") || return 1
                sshd_allow_root=$(prompt_yes_no "Allow root login over SSH?" "no") || return 1
                sshd_password_auth=$(prompt_yes_no "Allow password authentication?" "yes") || return 1
                sshd_hotspot_bypass=$(prompt_yes_no "Enable hotspot-bypass-friendly forwarding options?" "no") || return 1
                enable_sshd_service=$(prompt_yes_no "Enable sshd at iSH startup via OpenRC?" "yes") || return 1
                start_sshd_now=$(prompt_yes_no "Start sshd immediately after setup?" "yes") || return 1
                state_set SSHD_PORT "$sshd_port"
                state_set SSHD_ALLOW_ROOT "$sshd_allow_root"
                state_set SSHD_PASSWORD_AUTH "$sshd_password_auth"
                state_set SSHD_HOTSPOT_BYPASS "$sshd_hotspot_bypass"
                state_set ENABLE_SSHD_SERVICE "$enable_sshd_service"
                state_set START_SSHD_NOW "$start_sshd_now"
                [ "$enable_sshd_service" = "yes" ] && state_set ENABLED_SERVICES "sshd" || state_set ENABLED_SERVICES ""
                [ "$start_sshd_now" = "yes" ] && state_set START_NOW_SERVICES "sshd" || state_set START_NOW_SERVICES ""
                ;;
        esac
    else
        state_set SSHD_PORT "22"
        state_set SSHD_ALLOW_ROOT "no"
        state_set SSHD_PASSWORD_AUTH "no"
        state_set SSHD_HOTSPOT_BYPASS "no"
        state_set ENABLE_SSHD_SERVICE "no"
        state_set START_SSHD_NOW "no"
        state_set ENABLED_SERVICES ""
        state_set START_NOW_SERVICES ""
    fi
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
    install_aliases=$(prompt_yes_no "Install shell aliases?" "yes") || return 1
    install_doc_wrapper=$(prompt_yes_no "Install an iosish-docs helper wrapper?" "no") || return 1
    install_completion_wrapper=$(prompt_yes_no "Install an iosish-completions helper wrapper?" "no") || return 1

    state_set INSTALL_MANPAGES "$install_manpages"
    state_set INSTALL_COMPLETIONS "$install_completions"
    state_set INSTALL_ALIASES "$install_aliases"
    state_set INSTALL_DOC_WRAPPER "$install_doc_wrapper"
    state_set INSTALL_COMPLETION_WRAPPER "$install_completion_wrapper"
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
