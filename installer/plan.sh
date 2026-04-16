#!/bin/sh
# installer/plan.sh
# Planning helpers for guided installer sections.

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
        "skip" "recommended" "category" "package") || return 1

    state_set PACKAGE_MODE "$package_mode"

    case "$package_mode" in
        skip)
            state_set SELECTED_PACKAGE_CATEGORIES ""
            state_set SELECTED_PACKAGES ""
            ;;
        recommended)
            state_set SELECTED_PACKAGE_CATEGORIES "core,network,ssh,editors"
            state_set SELECTED_PACKAGES ""
            ;;
        category)
            printf 'Enter category list (comma-separated): '
            read -r categories || return 1
            state_set SELECTED_PACKAGE_CATEGORIES "$categories"
            state_set SELECTED_PACKAGES ""
            ;;
        package)
            printf 'Enter package list (space-separated): '
            read -r packages || return 1
            state_set SELECTED_PACKAGE_CATEGORIES ""
            state_set SELECTED_PACKAGES "$packages"
            ;;
    esac
}

plan_editor_setup() {
    editor_choice=$(prompt_choice \
        "Choose system editor:" \
        "vim" \
        "skip" "vim" "neovim" "nano") || return 1

    state_set EDITOR_CHOICE "$editor_choice"
}

plan_ssh_setup() {
    install_ssh_client=$(prompt_yes_no "Install SSH client tools?" "yes") || return 1
    install_sshd=$(prompt_yes_no "Install and configure SSHD?" "yes") || return 1

    state_set INSTALL_SSH_CLIENT "$install_ssh_client"
    state_set INSTALL_SSHD "$install_sshd"
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

    state_set INSTALL_MANPAGES "$install_manpages"
    state_set INSTALL_COMPLETIONS "$install_completions"
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
