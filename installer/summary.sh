#!/bin/sh
# installer/summary.sh
# Summary and review helpers.

show_progress_summary() {
    printf '\n== Installer Progress ==\n'
    printf 'Status: %s\n' "${INSTALL_STATUS:-unknown}"
    printf 'Current step: %s\n' "${CURRENT_STEP:-}"
    printf 'Last completed step: %s\n' "${LAST_COMPLETED_STEP:-}"
    printf '\n'
    printf 'Users:      %s\n' "${STEP_USERS_DONE:-no}"
    printf 'Shells:     %s\n' "${STEP_SHELLS_DONE:-no}"
    printf 'Packages:   %s\n' "${STEP_PACKAGES_DONE:-no}"
    printf 'Editor:     %s\n' "${STEP_EDITOR_DONE:-no}"
    printf 'SSH:        %s\n' "${STEP_SSH_DONE:-no}"
    printf 'SSHD:       %s\n' "${STEP_SSHD_DONE:-no}"
    printf 'Privilege:  %s\n' "${STEP_PRIVILEGE_DONE:-no}"
    printf 'Services:   %s\n' "${STEP_SERVICES_DONE:-no}"
    printf 'Extras:     %s\n' "${STEP_EXTRAS_DONE:-no}"
}

show_plan_summary() {
    printf '\n== Planned Configuration ==\n'
    printf 'Primary user:           %s\n' "${PRIMARY_USER:-}"
    printf 'Root only:              %s\n' "${ROOT_ONLY:-}"
    printf 'Configure root:         %s\n' "${CONFIGURE_ROOT:-}"
    printf 'Run Shelly:             %s\n' "${RUN_SHELLY:-}"
    printf 'Install shells:         %s\n' "${INSTALL_SHELLS:-}"
    printf 'User default shell:     %s\n' "${USER_DEFAULT_SHELL:-}"
    printf 'Root default shell:     %s\n' "${ROOT_DEFAULT_SHELL:-}"
    printf 'Package mode:           %s\n' "${PACKAGE_MODE:-}"
    printf 'Package categories:     %s\n' "${SELECTED_PACKAGE_CATEGORIES:-}"
    printf 'Selected packages:      %s\n' "${SELECTED_PACKAGES:-}"
    printf 'Editor choice:          %s\n' "${EDITOR_CHOICE:-}"
    printf 'Install SSH client:     %s\n' "${INSTALL_SSH_CLIENT:-}"
    printf 'Install SSHD:           %s\n' "${INSTALL_SSHD:-}"
    printf 'Install sudo:           %s\n' "${INSTALL_SUDO:-}"
    printf 'Install doas:           %s\n' "${INSTALL_DOAS:-}"
    printf 'Install manpages:       %s\n' "${INSTALL_MANPAGES:-}"
    printf 'Install completions:    %s\n' "${INSTALL_COMPLETIONS:-}"
    printf 'Install aliases:        %s\n' "${INSTALL_ALIASES:-}"
    printf 'Output mode:            %s\n' "${OUTPUT_MODE:-}"
    printf 'Color output:           %s\n' "${COLOR_OUTPUT:-}"
}

prompt_summary_action() {
    printf '\nWhat would you like to do?\n'
    printf '  - proceed\n'
    printf '  - quit\n'
    while :; do
        printf 'Choice [proceed]: '
        read -r reply || return 1
        [ -n "$reply" ] || reply="proceed"
        case "$reply" in
            proceed|quit)
                printf '%s\n' "$reply"
                return 0
                ;;
        esac
        printf 'Invalid choice.\n' >&2
    done
}
