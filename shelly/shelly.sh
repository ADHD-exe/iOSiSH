#!/usr/bin/env bash
set -u -o pipefail

SCRIPT_NAME="$(basename "$0")"
LOG_PREFIX="[${SCRIPT_NAME}]"

AUTO_INSTALL=0
NONINTERACTIVE=0
ROOT_ONLY=0

PRIMARY_USER=""
INSTALL_SHELLS=""
ROOT_DEFAULT=""
USER_DEFAULT=""

ZSH_PROMPT_CHOICE=""
BASH_PROMPT_CHOICE=""
FISH_PROMPT_CHOICE=""
FETCH_CHOICE=""

SHELLY_STATE_DIR=""
SHELLY_STATE_FILE=""

ALLOW_CHSH_ON_ISH="${ALLOW_CHSH_ON_ISH:-0}"

DEFAULT_INSTALL_SHELLS="all"
DEFAULT_ROOT_SHELL="bash"
DEFAULT_USER_SHELL="zsh"
DEFAULT_ZSH_PROMPT="powerlevel10k"
DEFAULT_BASH_PROMPT="starship"
DEFAULT_FISH_PROMPT="tide"
DEFAULT_FETCH_CHOICE="fastfetch"

CHANGED_FILES=()
INSTALLED_SHELLS=()
INSTALLED_COMPONENTS=()
MISSING_PACKAGES=()
SKIPPED_COMPONENTS=()

RED=$'\033[1;31m'
GREEN=$'\033[1;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[1;34m'
MAGENTA=$'\033[1;35m'
CYAN=$'\033[1;36m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

log()   { printf '%s %s\n' "${BLUE}${LOG_PREFIX}${RESET}" "$*"; }
ok()    { printf '%s %s\n' "${GREEN}${LOG_PREFIX}${RESET}" "$*"; }
warn()  { printf '%s %s\n' "${YELLOW}${LOG_PREFIX}${RESET}" "$*" >&2; }
err()   { printf '%s %s\n' "${RED}${LOG_PREFIX}${RESET}" "$*" >&2; }
die()   { err "$*"; exit 1; }

usage() {
  cat <<'EOF'
Usage:
  shelly.sh [options]

Options:
  --help
  --auto-install
  --noninteractive
  --root-only
  --primary-user USER
  --install-shells VALUE       zsh | bash | fish | all
  --root-shell VALUE           zsh | bash | fish
  --user-shell VALUE           zsh | bash | fish
  --zsh-prompt VALUE           omz | starship | powerlevel10k
  --bash-prompt VALUE          framework | starship
  --fish-prompt VALUE          tide | starship
  --fetch-tool VALUE           fastfetch | neofetch | neither

Environment:
  ALLOW_CHSH_ON_ISH=1
EOF
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

append_unique() {
  local value="$1"
  shift
  local -n arr_ref="$1"
  local x
  for x in "${arr_ref[@]:-}"; do
    [[ "$x" == "$value" ]] && return 0
  done
  arr_ref+=("$value")
}

append_component() { append_unique "$1" INSTALLED_COMPONENTS; }
append_shell() { append_unique "$1" INSTALLED_SHELLS; }
append_missing_package() { append_unique "$1" MISSING_PACKAGES; }
append_skipped_component() { append_unique "$1" SKIPPED_COMPONENTS; }
append_changed_file() { append_unique "$1" CHANGED_FILES; }

backup_file_if_needed() {
  local file="$1"
  [[ -e "$file" ]] || return 0

  local backup="${file}.bak"
  if [[ ! -e "$backup" ]]; then
    cp -p "$file" "$backup" 2>/dev/null || cp "$file" "$backup" 2>/dev/null || return 1
    append_changed_file "$backup"
  fi
}


require_root() {
  [[ "${EUID}" -eq 0 ]] || die "Run this script as root."
}

run_as_user() {
  local user="$1"
  shift
  su - "$user" -c "$*" >/dev/null 2>&1
}

user_home() {
  local user="$1"
  eval "echo ~${user}"
}

touch_owned() {
  local file="$1"
  local owner="$2"
  mkdir -p "$(dirname "$file")" 2>/dev/null || true
  touch "$file" 2>/dev/null || return 1
  chown "$owner:$owner" "$file" 2>/dev/null || true
}

ensure_line() {
  local file="$1"
  local line="$2"
  touch "$file" 2>/dev/null || return 1
  if ! grep -Fqx "$line" "$file" 2>/dev/null; then
    backup_file_if_needed "$file" || true
    printf '%s
' "$line" >> "$file"
    append_changed_file "$file"
  fi
}

ensure_block() {
  local file="$1"
  local marker="$2"
  local content="$3"
  touch "$file" 2>/dev/null || return 1
  if ! grep -Fq "$marker" "$file" 2>/dev/null; then
    backup_file_if_needed "$file" || true
    {
      printf '
%s
' "$marker"
      printf '%s
' "$content"
      printf '%s
' "${marker/BEGIN/END}"
    } >> "$file"
    append_changed_file "$file"
  fi
}

safe_mkdir_owned() {
  local dir="$1"
  local owner="$2"
  mkdir -p "$dir" 2>/dev/null || return 1
  chown "$owner:$owner" "$dir" 2>/dev/null || true
}

record_shell_hook() {
  local rc_file="$1"
  local shell_name="$2"
  case "$shell_name" in
    zsh)
      ensure_line "$rc_file" '[ -r "$HOME/.config/iosish/aliases.zsh" ] && . "$HOME/.config/iosish/aliases.zsh"' || true
      ;;
    bash)
      ensure_line "$rc_file" '[ -r "$HOME/.config/iosish/aliases.bash" ] && . "$HOME/.config/iosish/aliases.bash"' || true
      ;;
    fish)
      ensure_block "$rc_file" "# >>> shell setup BEGIN iosish aliases >>>" 'if test -r "$HOME/.config/iosish/aliases.fish"
    source "$HOME/.config/iosish/aliases.fish"
end' || true
      ;;
  esac
}

configure_state_paths() {
  local target_user="$1"
  local state_home
  state_home="$(user_home "$target_user")"
  SHELLY_STATE_DIR="${state_home}/.config/shelly"
  SHELLY_STATE_FILE="${SHELLY_STATE_DIR}/selection.env"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help) usage; exit 0 ;;
      --auto-install) AUTO_INSTALL=1 ;;
      --noninteractive) NONINTERACTIVE=1 ;;
      --root-only) ROOT_ONLY=1 ;;
      --primary-user) PRIMARY_USER="${2:-}"; shift ;;
      --install-shells) INSTALL_SHELLS="${2:-}"; shift ;;
      --root-shell) ROOT_DEFAULT="${2:-}"; shift ;;
      --user-shell) USER_DEFAULT="${2:-}"; shift ;;
      --zsh-prompt) ZSH_PROMPT_CHOICE="${2:-}"; shift ;;
      --bash-prompt) BASH_PROMPT_CHOICE="${2:-}"; shift ;;
      --fish-prompt) FISH_PROMPT_CHOICE="${2:-}"; shift ;;
      --fetch-tool) FETCH_CHOICE="${2:-}"; shift ;;
      *) die "Unknown argument: $1" ;;
    esac
    shift
  done
}

prompt_select() {
  local prompt_text="$1"
  shift
  local options=("$@")
  local idx=1
  local opt
  printf '%s%s%s\n' "${MAGENTA}" "$prompt_text" "${RESET}" >&2
  for opt in "${options[@]}"; do
    printf ' %d) %s\n' "$idx" "$opt"
    ((idx++))
  done
  while true; do
    read -r -p "Select an option [1-${#options[@]}]: " answer
    [[ "$answer" =~ ^[0-9]+$ ]] || { warn "Enter a number."; continue; }
    (( answer >= 1 && answer <= ${#options[@]} )) || { warn "Out of range."; continue; }
    printf '%s\n' "${options[$((answer - 1))]}"
    return 0
  done
}

shell_is_selected() {
  local s="$1"
  [[ "$INSTALL_SHELLS" == "all" || "$INSTALL_SHELLS" == "$s" ]]
}

manage_user_if_present_or_created() {
  [[ "$ROOT_ONLY" -eq 1 ]] && return 1

  if id "$PRIMARY_USER" >/dev/null 2>&1; then
    return 0
  fi

  if adduser -D -s /bin/bash "$PRIMARY_USER" >/dev/null 2>&1; then
    passwd "$PRIMARY_USER"
    addgroup "$PRIMARY_USER" wheel >/dev/null 2>&1 || true
    return 0
  fi

  append_skipped_component "user-create:${PRIMARY_USER}"
  return 1
}

interactive_questions() {
  if [[ "$ROOT_ONLY" -eq 0 ]]; then
    local scope_choice
    scope_choice="$(prompt_select "Who should be configured?" root_only root_and_primary_user)"
    [[ "$scope_choice" == "root_only" ]] && ROOT_ONLY=1
  fi

  [[ -n "$INSTALL_SHELLS" ]] || INSTALL_SHELLS="$(prompt_select "Which shell set do you want to install?" zsh bash fish all)"

  if [[ "$ROOT_ONLY" -eq 0 && -z "$PRIMARY_USER" ]]; then
    read -r -p "Enter the PRIMARY_USER username to create or manage: " PRIMARY_USER
    [[ -n "$PRIMARY_USER" ]] || die "PRIMARY_USER cannot be empty."
  fi

  [[ -n "$ROOT_DEFAULT" ]] || ROOT_DEFAULT="$(prompt_select "Which default shell should root use?" bash zsh fish)"
  [[ "$ROOT_ONLY" -eq 1 || -n "$USER_DEFAULT" ]] || USER_DEFAULT="$(prompt_select "Which default shell should ${PRIMARY_USER} use?" zsh bash fish)"
  [[ -n "$FETCH_CHOICE" ]] || FETCH_CHOICE="$(prompt_select "Install a system info banner tool?" fastfetch neofetch neither)"

  if shell_is_selected zsh && [[ -z "$ZSH_PROMPT_CHOICE" ]]; then
    ZSH_PROMPT_CHOICE="$(prompt_select "Choose the Zsh prompt style." omz starship powerlevel10k)"
  fi
  if shell_is_selected bash && [[ -z "$BASH_PROMPT_CHOICE" ]]; then
    BASH_PROMPT_CHOICE="$(prompt_select "Choose the Bash prompt style." framework starship)"
  fi
  if shell_is_selected fish && [[ -z "$FISH_PROMPT_CHOICE" ]]; then
    FISH_PROMPT_CHOICE="$(prompt_select "Choose the Fish prompt style." tide starship)"
  fi
}

apply_defaults_if_needed() {
  if [[ "$AUTO_INSTALL" -eq 1 ]]; then
    INSTALL_SHELLS="${INSTALL_SHELLS:-$DEFAULT_INSTALL_SHELLS}"
    ROOT_DEFAULT="${ROOT_DEFAULT:-$DEFAULT_ROOT_SHELL}"
    [[ "$ROOT_ONLY" -eq 0 ]] && USER_DEFAULT="${USER_DEFAULT:-$DEFAULT_USER_SHELL}"
    ZSH_PROMPT_CHOICE="${ZSH_PROMPT_CHOICE:-$DEFAULT_ZSH_PROMPT}"
    BASH_PROMPT_CHOICE="${BASH_PROMPT_CHOICE:-$DEFAULT_BASH_PROMPT}"
    FISH_PROMPT_CHOICE="${FISH_PROMPT_CHOICE:-$DEFAULT_FISH_PROMPT}"
    FETCH_CHOICE="${FETCH_CHOICE:-$DEFAULT_FETCH_CHOICE}"
  fi
}

validate_choices() {
  [[ "$INSTALL_SHELLS" =~ ^(zsh|bash|fish|all)$ ]] || die "Invalid install shell choice."
  [[ "$ROOT_DEFAULT" =~ ^(zsh|bash|fish)$ ]] || die "Invalid root shell choice."
  [[ "$FETCH_CHOICE" =~ ^(fastfetch|neofetch|neither)$ ]] || die "Invalid fetch tool choice."

  if [[ "$ROOT_ONLY" -eq 0 ]]; then
    [[ -n "$PRIMARY_USER" ]] || die "--primary-user USER is required unless --root-only is used."
    [[ "$USER_DEFAULT" =~ ^(zsh|bash|fish)$ ]] || die "Invalid user shell choice."
  fi

  if shell_is_selected zsh; then
    [[ "$ZSH_PROMPT_CHOICE" =~ ^(omz|starship|powerlevel10k)$ ]] || die "Invalid Zsh prompt choice."
  fi
  if shell_is_selected bash; then
    [[ "$BASH_PROMPT_CHOICE" =~ ^(framework|starship)$ ]] || die "Invalid Bash prompt choice."
  fi
  if shell_is_selected fish; then
    [[ "$FISH_PROMPT_CHOICE" =~ ^(tide|starship)$ ]] || die "Invalid Fish prompt choice."
  fi
}

pkg_install_alias() {
  local label="$1"
  shift
  local pkg
  for pkg in "$@"; do
    if apk search -q "$pkg" | grep -qx "$pkg"; then
      if apk add --no-cache "$pkg" >/dev/null 2>&1; then
        append_component "pkg:${label}:${pkg}"
        return 0
      fi
    fi
  done
  warn "Missing or failed package install for ${label}. Tried: $*"
  append_missing_package "$label"
  return 1
}

install_common_packages() {
  pkg_install_alias "git" git || true
  pkg_install_alias "curl" curl || true
  pkg_install_alias "wget" wget || true
  pkg_install_alias "sudo" sudo || true
  pkg_install_alias "fzf" fzf || true
  pkg_install_alias "zoxide" zoxide || true
  pkg_install_alias "perl" perl || true
  pkg_install_alias "make" make || true
}

install_zsh_packages() {
  pkg_install_alias "zsh" zsh || true
  pkg_install_alias "zsh-syntax-highlighting" zsh-syntax-highlighting || true
  pkg_install_alias "oh-my-zsh-package" oh-my-zsh || true
}

install_bash_packages() {
  pkg_install_alias "bash" bash || true
}

install_fish_packages() {
  pkg_install_alias "fish" fish || true
}

install_selected_shell_packages() {
  install_common_packages

  shell_is_selected zsh && install_zsh_packages
  shell_is_selected bash && install_bash_packages
  shell_is_selected fish && install_fish_packages
}

should_install_starship() {
  [[ "$ZSH_PROMPT_CHOICE" == "starship" || "$BASH_PROMPT_CHOICE" == "starship" || "$FISH_PROMPT_CHOICE" == "starship" ]]
}

install_base_packages() {
  install_selected_shell_packages
  should_install_starship && pkg_install_alias "starship" starship || true
}
install_fetch_tool() {
  case "$FETCH_CHOICE" in
    fastfetch) pkg_install_alias "fastfetch" fastfetch || append_skipped_component "fastfetch" ;;
    neofetch) pkg_install_alias "neofetch" neofetch || append_skipped_component "neofetch" ;;
    neither) ;;
  esac
}

git_clone_or_update() {
  local repo="$1"
  local dest="$2"
  if [[ -d "$dest/.git" ]]; then
    git -C "$dest" pull --ff-only >/dev/null 2>&1 || return 1
  elif [[ -d "$dest" ]]; then
    return 1
  else
    git clone --depth=1 "$repo" "$dest" >/dev/null 2>&1 || return 1
  fi
}

install_oh_my_zsh_for_user() {
  local user="$1"
  local home
  home="$(user_home "$user")"
  command_exists zsh || return 1

  if [[ -d "${home}/.oh-my-zsh" ]]; then
    :
  elif [[ -d /usr/share/oh-my-zsh ]]; then
    cp -a /usr/share/oh-my-zsh "${home}/.oh-my-zsh" 2>/dev/null || return 1
  else
    run_as_user "$user" 'RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended' || return 1
  fi

  append_component "oh-my-zsh:${user}"
}

configure_zsh_for_user() {
  local user="$1"
  local home custom zshrc
  home="$(user_home "$user")"
  custom="${home}/.oh-my-zsh/custom"
  zshrc="${home}/.zshrc"

  [[ -d "${home}/.oh-my-zsh" ]] || return 1

  mkdir -p "${custom}/plugins" "${custom}/themes" 2>/dev/null || true
  git_clone_or_update "https://github.com/zsh-users/zsh-autosuggestions.git" "${custom}/plugins/zsh-autosuggestions" || append_skipped_component "zsh-autosuggestions:${user}"
  git_clone_or_update "https://github.com/zsh-users/zsh-syntax-highlighting.git" "${custom}/plugins/zsh-syntax-highlighting" || append_skipped_component "zsh-syntax-highlighting:${user}"

  if [[ "$ZSH_PROMPT_CHOICE" == "powerlevel10k" ]]; then
    git_clone_or_update "https://github.com/romkatv/powerlevel10k.git" "${custom}/themes/powerlevel10k" || append_skipped_component "powerlevel10k:${user}"
  fi

  touch_owned "$zshrc" "$user" || return 1
  if ! grep -Fq 'source "$ZSH/oh-my-zsh.sh"' "$zshrc" 2>/dev/null; then
    backup_file_if_needed "$zshrc" || true
    cat > "$zshrc" <<'EOF'
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)
source "$ZSH/oh-my-zsh.sh"
EOF
    chown "$user:$user" "$zshrc" 2>/dev/null || true
    append_changed_file "$zshrc"
  fi

  if [[ "$ZSH_PROMPT_CHOICE" == "powerlevel10k" ]]; then
    if grep -Fq 'ZSH_THEME="robbyrussell"' "$zshrc" 2>/dev/null; then
      sed -i 's|^ZSH_THEME="robbyrussell"$|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$zshrc" 2>/dev/null || true
      append_changed_file "$zshrc"
    else
      ensure_line "$zshrc" 'ZSH_THEME="powerlevel10k/powerlevel10k"' || true
    fi
  fi

  ensure_block "$zshrc" "# >>> shell setup BEGIN zsh extras >>>" 'command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"
if [[ -o interactive ]] && [[ -z "${FETCH_SHOWN:-}" ]]; then
  export FETCH_SHOWN=1
  command -v fastfetch >/dev/null 2>&1 && fastfetch || command -v neofetch >/dev/null 2>&1 && neofetch
fi' || true

  if [[ "$ZSH_PROMPT_CHOICE" == "starship" ]]; then
    ensure_line "$zshrc" 'command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"' || true
  fi

  record_shell_hook "$zshrc" zsh
  append_changed_file "$zshrc"
  append_shell "zsh"
}

install_oh_my_bash_for_user() {
  local user="$1"
  local home
  home="$(user_home "$user")"
  command_exists bash || return 1
  if [[ ! -d "${home}/.oh-my-bash" ]]; then
    run_as_user "$user" 'bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh)" --unattended' || return 1
  fi
  append_component "oh-my-bash:${user}"
}

configure_bash_for_user() {
  local user="$1"
  local home bashrc
  home="$(user_home "$user")"
  bashrc="${home}/.bashrc"
  command_exists bash || return 1
  touch_owned "$bashrc" "$user" || return 1

  ensure_block "$bashrc" "# >>> shell setup BEGIN bash extras >>>" 'command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init bash)"
if [[ $- == *i* ]] && [[ -z "${FETCH_SHOWN:-}" ]]; then
  export FETCH_SHOWN=1
  command -v fastfetch >/dev/null 2>&1 && fastfetch || command -v neofetch >/dev/null 2>&1 && neofetch
fi' || true

  if [[ "$BASH_PROMPT_CHOICE" == "starship" ]]; then
    ensure_line "$bashrc" 'command -v starship >/dev/null 2>&1 && eval "$(starship init bash)"' || true
  fi

  record_shell_hook "$bashrc" bash
  append_changed_file "$bashrc"
  append_shell "bash"
}

install_fisher_for_user() {
  local user="$1"
  command_exists fish || return 1
  run_as_user "$user" "fish -lc 'functions -q fisher; or curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher'" || return 1
}

configure_fish_for_user() {
  local user="$1"
  local home config_dir config_fish
  home="$(user_home "$user")"
  config_dir="${home}/.config/fish"
  config_fish="${config_dir}/config.fish"
  command_exists fish || return 1

  mkdir -p "$config_dir" 2>/dev/null || true
  touch_owned "$config_fish" "$user" || return 1
  install_fisher_for_user "$user" || true

  [[ "$FISH_PROMPT_CHOICE" != "tide" ]] || run_as_user "$user" "fish -lc 'fisher list | grep -q IlanCosman/tide; or fisher install IlanCosman/tide@v6'" || append_skipped_component "tide:${user}"

  ensure_block "$config_fish" "# >>> shell setup BEGIN fish extras >>>" \
'if command -q zoxide
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
end' || true

  if [[ "$FISH_PROMPT_CHOICE" == "starship" ]]; then
    ensure_line "$config_fish" 'command -q starship; and starship init fish | source' || true
  fi

  record_shell_hook "$config_fish" fish
  append_changed_file "$config_fish"
  append_shell "fish"
}

shell_path_for_name() {
  case "$1" in
    bash) echo "/bin/bash" ;;
    zsh) echo "/bin/zsh" ;;
    fish) echo "/usr/bin/fish" ;;
    *) return 1 ;;
  esac
}

set_shell_via_launcher_fallback() {
  local user="$1"
  local shell_name="$2"
  local shell_path home profile
  shell_path="$(shell_path_for_name "$shell_name")" || return 1
  home="$(user_home "$user")"
  profile="${home}/.profile"

  touch_owned "$profile" "$user" || return 1
  ensure_block "$profile" "# >>> shell setup BEGIN launcher fallback >>>" \
"case \"\${-}\" in
  *i*) [ -x \"${shell_path}\" ] && exec \"${shell_path}\" -l ;;
esac" || true
}

set_default_shell() {
  local user="$1"
  local shell_name="$2"
  local shell_path
  shell_path="$(shell_path_for_name "$shell_name")" || return 1
  [[ -x "$shell_path" ]] || return 1

  if [[ "$ALLOW_CHSH_ON_ISH" == "1" ]] && command_exists chsh; then
    chsh -s "$shell_path" "$user" >/dev/null 2>&1 || set_shell_via_launcher_fallback "$user" "$shell_name"
  else
    set_shell_via_launcher_fallback "$user" "$shell_name"
  fi
}

configure_for_user_if_available() {
  local user="$1"
  shell_is_selected zsh && install_oh_my_zsh_for_user "$user" && configure_zsh_for_user "$user" || true
  shell_is_selected bash && install_oh_my_bash_for_user "$user" && configure_bash_for_user "$user" || true
  shell_is_selected fish && configure_fish_for_user "$user" || true
}

main_install() {
  install_base_packages
  install_fetch_tool

  configure_for_user_if_available root
  set_default_shell root "$ROOT_DEFAULT" || true

  if manage_user_if_present_or_created; then
    configure_for_user_if_available "$PRIMARY_USER"
    set_default_shell "$PRIMARY_USER" "$USER_DEFAULT" || true
    write_selection_state "$PRIMARY_USER"
  else
    write_selection_state root
  fi
}

write_selection_state() {
  local state_user="$1"
  local configured_shells="${INSTALLED_SHELLS[*]:-none}"
  configure_state_paths "$state_user"
  safe_mkdir_owned "$SHELLY_STATE_DIR" "$state_user" || return 1
  cat > "$SHELLY_STATE_FILE" <<EOF
INSTALL_SHELLS=${INSTALL_SHELLS}
ROOT_DEFAULT=${ROOT_DEFAULT}
USER_DEFAULT=${USER_DEFAULT}
CONFIGURED_SHELLS=${configured_shells}
FETCH_CHOICE=${FETCH_CHOICE}
ROOT_ONLY=${ROOT_ONLY}
EOF
  chown "$state_user:$state_user" "$SHELLY_STATE_FILE" 2>/dev/null || true
  append_changed_file "$SHELLY_STATE_FILE"
}

print_summary() {
  printf '\n%sSummary%s\n' "${BOLD}${CYAN}" "${RESET}"
  printf 'Scope: %s\n' "$([[ "$ROOT_ONLY" -eq 1 ]] && echo "root only" || echo "root and ${PRIMARY_USER}")"
  printf 'Installed shells: %s\n' "${INSTALLED_SHELLS[*]:-none}"
  printf 'Fetch tool: %s\n' "$FETCH_CHOICE"
  printf 'Installed components: %s\n' "${INSTALLED_COMPONENTS[*]:-none}"

  printf 'Changed files:\n'
  local c
  for c in "${CHANGED_FILES[@]:-}"; do printf '  %s\n' "$c"; done

  printf 'Missing packages:\n'
  local p
  for p in "${MISSING_PACKAGES[@]:-}"; do printf '  %s\n' "$p"; done

  printf 'Skipped components:\n'
  local s
  for s in "${SKIPPED_COMPONENTS[@]:-}"; do printf '  %s\n' "$s"; done
}

main() {
  require_root
  parse_args "$@"
  apply_defaults_if_needed

  if [[ "$NONINTERACTIVE" -eq 0 && "$AUTO_INSTALL" -eq 0 ]]; then
    interactive_questions
  fi

  if [[ "$NONINTERACTIVE" -eq 1 && "$AUTO_INSTALL" -eq 0 ]]; then
    FETCH_CHOICE="${FETCH_CHOICE:-$DEFAULT_FETCH_CHOICE}"
  fi

  validate_choices
  main_install
  print_summary
}

main "$@"
