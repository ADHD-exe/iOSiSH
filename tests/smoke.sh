#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

state_file="$(mktemp "${TMPDIR:-/tmp}/iosish-state.XXXXXX")"
log_file="$(mktemp "${TMPDIR:-/tmp}/iosish-log.XXXXXX")"
cleanup() {
  rm -f "$state_file" "$log_file" /tmp/iosish-smoke.log
}
trap cleanup EXIT

sh -n iOSiSH.sh
bash -n aliases/common.sh
bash -n aliases/aliases.bash

if command -v zsh >/dev/null 2>&1; then
  zsh -n aliases/aliases.zsh
fi
if command -v fish >/dev/null 2>&1; then
  fish --no-config -n aliases/common.fish
  fish --no-config -n aliases/aliases.fish
fi

./iOSiSH.sh --help >/dev/null

bash tests/state_smoke.sh
bash tests/planner_smoke.sh

# iOSiSH should use the native shell module instead of the old Zsh-only flow.
! grep -q 'write_profiles()' iOSiSH.sh
! grep -q 'install_shell_frameworks()' iOSiSH.sh
! grep -q 'install_repo_shell_assets()' iOSiSH.sh
! grep -q 'prime_zsh_for_user()' iOSiSH.sh
! grep -q 'clone_or_update_repo()' iOSiSH.sh
! grep -q 'download_text()' iOSiSH.sh

grep -q 'install_aliases_for_shell()' iOSiSH.sh
grep -q 'run_shell_setup_from_state()' installer/shells.sh

# iOSiSH should no longer install repo-managed Zsh assets or hard-force zsh.
! grep -q 'pkg_install_alias "zsh" zsh' iOSiSH.sh
! grep -q 'exec zsh -l' iOSiSH.sh
! grep -q '\.zshrc ->' iOSiSH.sh

# Native shell module should own shell package selection and only install selected shells.
grep -q '^install_selected_shell_packages()' installer/shells.sh
grep -q '^configure_zsh_for_user()' installer/shells.sh
grep -q '^configure_bash_for_user()' installer/shells.sh
grep -q '^configure_fish_for_user()' installer/shells.sh
grep -q '^run_shell_setup_from_state()' installer/shells.sh
grep -q 'ZSH_PROMPT_CHOICE' installer/shells.sh
grep -q 'BASH_PROMPT_CHOICE' installer/shells.sh
grep -q 'FISH_PROMPT_CHOICE' installer/shells.sh
grep -q 'CONFIGURED_SHELLS' installer/shells.sh

# Each shell config should have an alias hook target under ~/.config/iosish.
grep -q 'aliases.zsh' installer/shells.sh
grep -q 'aliases.bash' installer/shells.sh
grep -q 'aliases.fish' installer/shells.sh

# Alias assets should be shell-aware and no longer rely on legacy repo-root compatibility files.
test -f aliases/common.sh
test -f aliases/aliases.zsh
test -f aliases/aliases.bash
test -f aliases/common.fish
test -f aliases/aliases.fish

# iOSiSH alias install path should target shell-specific destinations.
grep -q '\.config/iosish/aliases.zsh' iOSiSH.sh
grep -q '\.config/iosish/aliases.bash' iOSiSH.sh
grep -q '\.config/iosish/aliases.fish' iOSiSH.sh

INSTALLER_STATE_FILE="$state_file" INSTALLER_RUNTIME_LOG="$log_file" DRY_RUN=1 NONINTERACTIVE=1 PRIMARY_USER=rabbit PRIMARY_HOME=/home/rabbit PRIMARY_PASSWORD=placeholder ROOT_PASSWORD=placeholder ISH_LISTEN_PORT=22 HOME_PC_HOST=example.com HOME_PC_USER=rabbit HOME_PC_PORT=22 PC_SOCKS_PORT=1080 ./iOSiSH.sh --dry-run --ssh-hardened >/tmp/iosish-smoke.log 2>&1

grep -q 'dry-run' /tmp/iosish-smoke.log
grep -q 'Running native shell installation and configuration' /tmp/iosish-smoke.log
grep -q 'hardened defaults' /tmp/iosish-smoke.log
