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
    printf 'Run shell setup:        %s\n' "${RUN_SHELL_SETUP:-}"
    printf 'Install shells:         %s\n' "${INSTALL_SHELLS:-}"
    printf 'User default shell:     %s\n' "${USER_DEFAULT_SHELL:-}"
    printf 'Root default shell:     %s\n' "${ROOT_DEFAULT_SHELL:-}"
    printf 'Zsh prompt:             %s\n' "${ZSH_PROMPT_CHOICE:-}"
    printf 'Bash prompt:            %s\n' "${BASH_PROMPT_CHOICE:-}"
    printf 'Fish prompt:            %s\n' "${FISH_PROMPT_CHOICE:-}"
    printf 'Fetch tool:             %s\n' "${FETCH_CHOICE:-}"
    printf 'Package mode:           %s\n' "${PACKAGE_MODE:-}"
    printf 'Package profile:        %s\n' "${PACKAGE_PROFILE:-}"
    printf 'Package categories:     %s\n' "${SELECTED_PACKAGE_CATEGORIES:-}"
    printf 'Selected packages:      %s\n' "${SELECTED_PACKAGES:-}"
    printf 'Excluded packages:      %s\n' "${EXCLUDED_PACKAGES:-}"
    printf 'Editor choice:          %s\n' "${EDITOR_CHOICE:-}"
    printf 'Editor profile:         %s\n' "${EDITOR_PROFILE:-}"
    printf 'Editor config:          %s\n' "${INSTALL_EDITOR_CONFIG:-}"
    printf 'Editor plugins:         %s\n' "${INSTALL_EDITOR_PLUGINS:-}"
    printf 'Install SSH client:     %s\n' "${INSTALL_SSH_CLIENT:-}"
    printf 'Install SSHD:           %s\n' "${INSTALL_SSHD:-}"
    printf 'SSHD port:              %s\n' "${SSHD_PORT:-}"
    printf 'SSHD allow root:        %s\n' "${SSHD_ALLOW_ROOT:-}"
    printf 'SSHD password auth:     %s\n' "${SSHD_PASSWORD_AUTH:-}"
    printf 'Enable services:        %s\n' "${ENABLED_SERVICES:-}"
    printf 'Start-now services:     %s\n' "${START_NOW_SERVICES:-}"
    printf 'Install sudo:           %s\n' "${INSTALL_SUDO:-}"
    printf 'Install doas:           %s\n' "${INSTALL_DOAS:-}"
    printf 'Install manpages:       %s\n' "${INSTALL_MANPAGES:-}"
    printf 'Install completions:    %s\n' "${INSTALL_COMPLETIONS:-}"
    printf 'Install doc wrapper:    %s\n' "${INSTALL_DOC_WRAPPER:-}"
    printf 'Install completion wrap:%s\n' "${INSTALL_COMPLETION_WRAPPER:-}"
    printf 'Install aliases:        %s\n' "${INSTALL_ALIASES:-}"
    printf 'Output mode:            %s\n' "${OUTPUT_MODE:-}"
    printf 'Color output:           %s\n' "${COLOR_OUTPUT:-}"
}

prompt_summary_action() {
    printf '\nWhat would you like to do?\n' >&2
    printf '  - proceed\n' >&2
    printf '  - edit\n' >&2
    printf '  - rerun\n' >&2
    printf '  - save-quit\n' >&2
    printf '  - reset\n' >&2
    printf '  - quit\n' >&2
    while :; do
        printf 'Choice [proceed]: ' >&2
        if [ "${NONINTERACTIVE:-0}" = "1" ]; then
            reply="proceed"
        else
            read -r reply || return 1
            [ -n "$reply" ] || reply="proceed"
        fi
        case "$reply" in
            proceed|edit|rerun|save-quit|reset|quit)
                printf '%s\n' "$reply"
                return 0
                ;;
        esac
        printf 'Invalid choice.\n' >&2
    done
}

prompt_edit_section() {
    printf '\nWhich section would you like to edit?\n' >&2
    printf '  - preferences\n' >&2
    printf '  - users\n' >&2
    printf '  - shells\n' >&2
    printf '  - packages\n' >&2
    printf '  - editor\n' >&2
    printf '  - ssh\n' >&2
    printf '  - sshd\n' >&2
    printf '  - services\n' >&2
    printf '  - privilege\n' >&2
    printf '  - extras\n' >&2
    while :; do
        printf 'Section [packages]: ' >&2
        if [ "${NONINTERACTIVE:-0}" = "1" ]; then
            reply="packages"
        else
            read -r reply || return 1
            [ -n "$reply" ] || reply="packages"
        fi
        case "$reply" in
            preferences|users|shells|packages|editor|ssh|sshd|services|privilege|extras)
                printf '%s\n' "$reply"
                return 0
                ;;
        esac
        printf 'Invalid section.\n' >&2
    done
}


show_resume_summary() {
    printf '\n== Resume Status ==\n'
    printf 'Install status:        %s\n' "${INSTALL_STATUS:-unknown}"
    printf 'Current step:          %s\n' "${CURRENT_STEP:-}"
    printf 'Last completed step:   %s\n' "${LAST_COMPLETED_STEP:-}"
    printf 'Completed step flags:  users=%s shells=%s packages=%s editor=%s ssh=%s sshd=%s privilege=%s services=%s extras=%s\n' \
        "${STEP_USERS_DONE:-no}" "${STEP_SHELLS_DONE:-no}" "${STEP_PACKAGES_DONE:-no}" "${STEP_EDITOR_DONE:-no}" \
        "${STEP_SSH_DONE:-no}" "${STEP_SSHD_DONE:-no}" "${STEP_PRIVILEGE_DONE:-no}" "${STEP_SERVICES_DONE:-no}" "${STEP_EXTRAS_DONE:-no}"
}

prompt_resume_action() {
    printf '\nExisting installer state detected. What would you like to do?\n' >&2
    printf '  - resume\n' >&2
    printf '  - review\n' >&2
    printf '  - reset\n' >&2
    printf '  - quit\n' >&2
    while :; do
        printf 'Choice [resume]: ' >&2
        if [ "${NONINTERACTIVE:-0}" = "1" ]; then
            reply="resume"
        else
            read -r reply || return 1
            [ -n "$reply" ] || reply="resume"
        fi
        case "$reply" in
            resume|review|reset|quit)
                printf '%s\n' "$reply"
                return 0
                ;;
        esac
        printf 'Invalid choice.\n' >&2
    done
}

prompt_rerun_section() {
    printf '\nWhich completed section would you like to rerun?\n' >&2
    printf '  - users\n' >&2
    printf '  - shells\n' >&2
    printf '  - packages\n' >&2
    printf '  - editor\n' >&2
    printf '  - ssh\n' >&2
    printf '  - sshd\n' >&2
    printf '  - services\n' >&2
    printf '  - privilege\n' >&2
    printf '  - extras\n' >&2
    while :; do
        printf 'Section [packages]: ' >&2
        if [ "${NONINTERACTIVE:-0}" = "1" ]; then
            reply="packages"
        else
            read -r reply || return 1
            [ -n "$reply" ] || reply="packages"
        fi
        case "$reply" in
            users|shells|packages|editor|ssh|sshd|services|privilege|extras)
                printf '%s\n' "$reply"
                return 0
                ;;
        esac
        printf 'Invalid section.\n' >&2
    done
}
