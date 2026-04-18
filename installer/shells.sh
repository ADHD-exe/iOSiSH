#!/bin/sh
# installer/shells.sh
# Native shell setup for iOSiSH. This replaces the old Shelly handoff.

shell_pkg_candidates() {
    case "$1" in
        bash) printf '%s\n' bash ;;
        zsh) printf '%s\n' zsh zsh-syntax-highlighting oh-my-zsh git curl ;;
        fish) printf '%s\n' fish curl ;;
        common) printf '%s\n' git curl wget sudo fzf zoxide perl make ;;
        starship) printf '%s\n' starship ;;
        fastfetch) printf '%s\n' fastfetch ;;
        neofetch) printf '%s\n' neofetch ;;
    esac
}

append_csv_unique() {
    existing=$1
    value=$2
    [ -n "$value" ] || { printf '%s\n' "$existing"; return; }
    case ",$existing," in
        *,"$value",*) printf '%s\n' "$existing" ;;
        *) [ -n "$existing" ] && printf '%s,%s\n' "$existing" "$value" || printf '%s\n' "$value" ;;
    esac
}

shell_selected() {
    shell_name=$1
    case "${INSTALL_SHELLS:-all}" in
        all|"$shell_name"|*,$shell_name,*|$shell_name,*|*,$shell_name) return 0 ;;
        *) return 1 ;;
    esac
}

shell_path_for_name() {
    case "$1" in
        bash) printf '%s\n' '/bin/bash' ;;
        zsh) printf '%s\n' '/bin/zsh' ;;
        fish) printf '%s\n' '/usr/bin/fish' ;;
        *) return 1 ;;
    esac
}

user_home_dir() {
    user_name=$1
    if [ "$user_name" = "root" ]; then
        printf '%s\n' /root
    else
        printf '/home/%s\n' "$user_name"
    fi
}

touch_owned_file() {
    file=$1
    owner=$2
    [ "$DRY_RUN" = "1" ] && { info "[dry-run] touch $file"; return 0; }
    mkdir -p "$(dirname "$file")" || return 1
    : > "$file" 2>/dev/null || touch "$file" || return 1
    chown "$owner:$owner" "$file" 2>/dev/null || true
}

ensure_line_in_file() {
    file=$1
    line=$2
    [ "$DRY_RUN" = "1" ] && { info "[dry-run] ensure line in $file: $line"; return 0; }
    mkdir -p "$(dirname "$file")" || return 1
    [ -f "$file" ] || : >"$file" || return 1
    grep -Fqx "$line" "$file" 2>/dev/null || printf '%s\n' "$line" >> "$file"
}

ensure_block_in_file() {
    file=$1
    marker=$2
    content=$3
    [ "$DRY_RUN" = "1" ] && { info "[dry-run] ensure block in $file: $marker"; return 0; }
    mkdir -p "$(dirname "$file")" || return 1
    [ -f "$file" ] || : >"$file" || return 1
    if ! grep -Fq "$marker" "$file" 2>/dev/null; then
        {
            printf '\n%s\n' "$marker"
            printf '%s\n' "$content"
            printf '%s\n' "$(printf %s "$marker" | sed "s/BEGIN/END/")"
        } >> "$file"
    fi
}

record_shell_alias_hook() {
    rc_file=$1
    shell_name=$2
    case "$shell_name" in
        zsh)
            ensure_line_in_file "$rc_file" '[ -r "$HOME/.config/iosish/aliases.zsh" ] && . "$HOME/.config/iosish/aliases.zsh"'
            ;;
        bash)
            ensure_line_in_file "$rc_file" '[ -r "$HOME/.config/iosish/aliases.bash" ] && . "$HOME/.config/iosish/aliases.bash"'
            ;;
        fish)
            ensure_block_in_file "$rc_file" "# >>> shell setup BEGIN iosish aliases >>>" 'if test -r "$HOME/.config/iosish/aliases.fish"
    source "$HOME/.config/iosish/aliases.fish"
end'
            ;;
    esac
}

install_shell_package_group() {
    group=$1
    pkgs=$(shell_pkg_candidates "$group")
    [ -n "$pkgs" ] || return 0
    for p in $pkgs; do
        pkg_install_alias "$p" "$p" || true
    done
}

configure_zsh_for_user_native() {
    user_name=$1
    home_dir=$(user_home_dir "$user_name")
    zshrc="$home_dir/.zshrc"
    [ "$DRY_RUN" = "1" ] && {
        info "[dry-run] configure zsh for $user_name"
        CONFIGURED_SHELLS=$(append_csv_unique "${CONFIGURED_SHELLS:-}" zsh)
        return 0
    }
    mkdir -p "$home_dir/.oh-my-zsh/custom/plugins" "$home_dir/.oh-my-zsh/custom/themes" "$home_dir/.cache/zsh" || return 1
    chown -R "$user_name:$user_name" "$home_dir/.cache" "$home_dir/.oh-my-zsh" 2>/dev/null || true
    touch_owned_file "$zshrc" "$user_name" || return 1
    if ! grep -Fq 'source "$ZSH/oh-my-zsh.sh"' "$zshrc" 2>/dev/null; then
        cat > "$zshrc" <<'ZRC'
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git)
source "$ZSH/oh-my-zsh.sh"
ZRC
        chown "$user_name:$user_name" "$zshrc" 2>/dev/null || true
    fi
    ensure_line_in_file "$zshrc" 'plugins=(git zsh-syntax-highlighting)'
    ensure_block_in_file "$zshrc" "# >>> shell setup BEGIN zsh extras >>>" 'command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"
if [[ -o interactive ]] && [[ -z "${FETCH_SHOWN:-}" ]]; then
  export FETCH_SHOWN=1
  command -v fastfetch >/dev/null 2>&1 && fastfetch || command -v neofetch >/dev/null 2>&1 && neofetch
fi'
    case "${ZSH_PROMPT_CHOICE:-powerlevel10k}" in
        powerlevel10k)
            if grep -Fq 'ZSH_THEME="robbyrussell"' "$zshrc" 2>/dev/null; then
                sed -i 's|^ZSH_THEME="robbyrussell"$|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$zshrc" 2>/dev/null || true
            else
                ensure_line_in_file "$zshrc" 'ZSH_THEME="powerlevel10k/powerlevel10k"'
            fi
            ;;
        starship)
            ensure_line_in_file "$zshrc" 'command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"'
            ;;
    esac
    record_shell_alias_hook "$zshrc" zsh
    CONFIGURED_SHELLS=$(append_csv_unique "${CONFIGURED_SHELLS:-}" zsh)
}

configure_bash_for_user_native() {
    user_name=$1
    home_dir=$(user_home_dir "$user_name")
    bashrc="$home_dir/.bashrc"
    [ "$DRY_RUN" = "1" ] && {
        info "[dry-run] configure bash for $user_name"
        CONFIGURED_SHELLS=$(append_csv_unique "${CONFIGURED_SHELLS:-}" bash)
        return 0
    }
    touch_owned_file "$bashrc" "$user_name" || return 1
    ensure_block_in_file "$bashrc" "# >>> shell setup BEGIN bash extras >>>" 'command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init bash)"
if [[ $- == *i* ]] && [[ -z "${FETCH_SHOWN:-}" ]]; then
  export FETCH_SHOWN=1
  command -v fastfetch >/dev/null 2>&1 && fastfetch || command -v neofetch >/dev/null 2>&1 && neofetch
fi'
    [ "${BASH_PROMPT_CHOICE:-starship}" = "starship" ] && ensure_line_in_file "$bashrc" 'command -v starship >/dev/null 2>&1 && eval "$(starship init bash)"'
    record_shell_alias_hook "$bashrc" bash
    CONFIGURED_SHELLS=$(append_csv_unique "${CONFIGURED_SHELLS:-}" bash)
}

configure_fish_for_user_native() {
    user_name=$1
    home_dir=$(user_home_dir "$user_name")
    config_fish="$home_dir/.config/fish/config.fish"
    [ "$DRY_RUN" = "1" ] && {
        info "[dry-run] configure fish for $user_name"
        CONFIGURED_SHELLS=$(append_csv_unique "${CONFIGURED_SHELLS:-}" fish)
        return 0
    }
    touch_owned_file "$config_fish" "$user_name" || return 1
    ensure_block_in_file "$config_fish" "# >>> shell setup BEGIN fish extras >>>" 'if command -q zoxide
    zoxide init fish | source
end
if status is-interactive
    if not set -q FETCH_SHOWN
        set -gx FETCH_SHOWN 1
        if command -q fastfetch
            fastfetch
        else if command -q neofetch
            neofetch
        end
    end
end'
    [ "${FISH_PROMPT_CHOICE:-tide}" = "starship" ] && ensure_line_in_file "$config_fish" 'command -q starship; and starship init fish | source'
    record_shell_alias_hook "$config_fish" fish
    CONFIGURED_SHELLS=$(append_csv_unique "${CONFIGURED_SHELLS:-}" fish)
}

set_shell_via_launcher_fallback_native() {
    user_name=$1
    shell_name=$2
    shell_path=$(shell_path_for_name "$shell_name") || return 1
    profile="$(user_home_dir "$user_name")/.profile"
    ensure_block_in_file "$profile" "# >>> shell setup BEGIN launcher fallback >>>" "case \"\${-}\" in
  *i*) [ -x \"${shell_path}\" ] && exec \"${shell_path}\" -l ;;
esac"
    [ "$DRY_RUN" = "1" ] || chown "$user_name:$user_name" "$profile" 2>/dev/null || true
}

set_default_shell_native() {
    user_name=$1
    shell_name=$2
    shell_path=$(shell_path_for_name "$shell_name") || return 1
    [ "$DRY_RUN" = "1" ] && { info "[dry-run] set default shell for $user_name to $shell_name"; return 0; }
    [ -x "$shell_path" ] || return 1
    if [ "${ALLOW_CHSH_ON_ISH:-0}" = "1" ] && command -v chsh >/dev/null 2>&1; then
        chsh -s "$shell_path" "$user_name" >/dev/null 2>&1 || set_shell_via_launcher_fallback_native "$user_name" "$shell_name"
    else
        set_shell_via_launcher_fallback_native "$user_name" "$shell_name"
    fi
}

configure_shells_for_target_user_native() {
    user_name=$1
    shell_selected zsh && configure_zsh_for_user_native "$user_name" || true
    shell_selected bash && configure_bash_for_user_native "$user_name" || true
    shell_selected fish && configure_fish_for_user_native "$user_name" || true
}

native_run_shell_setup_from_state() {
    if ! should_run_step shells; then
        info "Skipping shells step; already completed in installer state"
        return 0
    fi
    log_install_event INFO "Starting shells step"
    state_mark_step_started shells || return 1
    INSTALL_SHELLS="${INSTALL_SHELLS:-all}"
    ROOT_DEFAULT_SHELL="${ROOT_DEFAULT_SHELL:-bash}"
    USER_DEFAULT_SHELL="${USER_DEFAULT_SHELL:-zsh}"
    ZSH_PROMPT_CHOICE="${ZSH_PROMPT_CHOICE:-powerlevel10k}"
    BASH_PROMPT_CHOICE="${BASH_PROMPT_CHOICE:-starship}"
    FISH_PROMPT_CHOICE="${FISH_PROMPT_CHOICE:-tide}"
    FETCH_CHOICE="${FETCH_CHOICE:-fastfetch}"
    CONFIGURED_SHELLS="${CONFIGURED_SHELLS:-}"

    install_shell_package_group common
    shell_selected zsh && install_shell_package_group zsh
    shell_selected bash && install_shell_package_group bash
    shell_selected fish && install_shell_package_group fish
    case "$ZSH_PROMPT_CHOICE $BASH_PROMPT_CHOICE $FISH_PROMPT_CHOICE" in
        *starship*) install_shell_package_group starship ;;
    esac
    case "$FETCH_CHOICE" in
        fastfetch) install_shell_package_group fastfetch ;;
        neofetch) install_shell_package_group neofetch ;;
    esac

    configure_shells_for_target_user_native root
    set_default_shell_native root "$ROOT_DEFAULT_SHELL" || warn "Could not set default shell for root"
    if [ "${ROOT_ONLY:-no}" != "yes" ]; then
        configure_shells_for_target_user_native "$PRIMARY_USER"
        set_default_shell_native "$PRIMARY_USER" "$USER_DEFAULT_SHELL" || warn "Could not set default shell for $PRIMARY_USER"
    fi

    state_set INSTALL_SHELLS "$INSTALL_SHELLS"
    state_set ROOT_DEFAULT_SHELL "$ROOT_DEFAULT_SHELL"
    state_set USER_DEFAULT_SHELL "$USER_DEFAULT_SHELL"
    state_set ZSH_PROMPT_CHOICE "$ZSH_PROMPT_CHOICE"
    state_set BASH_PROMPT_CHOICE "$BASH_PROMPT_CHOICE"
    state_set FISH_PROMPT_CHOICE "$FISH_PROMPT_CHOICE"
    state_set FETCH_CHOICE "$FETCH_CHOICE"
    state_set CONFIGURED_SHELLS "$CONFIGURED_SHELLS"
    state_mark_step_done shells || return 1
    log_install_event INFO "Completed shells step"
    ok "Native shell setup complete"
}
