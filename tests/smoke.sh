#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

sh -n iOSiSH.sh
bash -n shelly/shelly.sh
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

# iOSiSH should delegate shell ownership instead of handling old Zsh-only flow directly.
! grep -q 'write_profiles()' iOSiSH.sh
! grep -q 'install_shell_frameworks()' iOSiSH.sh
! grep -q 'install_repo_shell_assets()' iOSiSH.sh
! grep -q 'prime_zsh_for_user()' iOSiSH.sh
! grep -q 'clone_or_update_repo()' iOSiSH.sh
! grep -q 'download_text()' iOSiSH.sh

grep -q 'run_shelly_setup()' iOSiSH.sh
grep -q 'prompt_for_alias_install()' iOSiSH.sh
grep -q 'read_shelly_selection_state()' iOSiSH.sh
grep -q 'install_aliases_for_shell()' iOSiSH.sh

# iOSiSH should no longer install repo-managed Zsh assets or hard-force zsh.
! grep -q 'pkg_install_alias "zsh" zsh' iOSiSH.sh
! grep -q 'exec zsh -l' iOSiSH.sh
! grep -q '\.zshrc ->' iOSiSH.sh

# Shelly should own shell package selection and only install selected shells.
grep -q '^install_common_packages()' shelly/shelly.sh
grep -q '^install_selected_shell_packages()' shelly/shelly.sh
grep -q 'shell_is_selected zsh && install_zsh_packages' shelly/shelly.sh
grep -q 'shell_is_selected bash && install_bash_packages' shelly/shelly.sh
grep -q 'shell_is_selected fish && install_fish_packages' shelly/shelly.sh

grep -q '^install_zsh_packages()' shelly/shelly.sh
grep -q '^install_bash_packages()' shelly/shelly.sh
grep -q '^install_fish_packages()' shelly/shelly.sh

# Starship should be conditional on prompt choice instead of always installed.
grep -q '^should_install_starship()' shelly/shelly.sh
grep -q 'ZSH_PROMPT_CHOICE' shelly/shelly.sh
grep -q 'BASH_PROMPT_CHOICE' shelly/shelly.sh
grep -q 'FISH_PROMPT_CHOICE' shelly/shelly.sh

# Shelly should write a machine-readable state file for iOSiSH.
grep -q '^write_selection_state()' shelly/shelly.sh
grep -q 'INSTALL_SHELLS=' shelly/shelly.sh
grep -q 'ROOT_DEFAULT=' shelly/shelly.sh
grep -q 'USER_DEFAULT=' shelly/shelly.sh
grep -q 'CONFIGURED_SHELLS=' shelly/shelly.sh

# Each shell config should have an alias hook target under ~/.config/iosish.
grep -q 'aliases.zsh' shelly/shelly.sh
grep -q 'aliases.bash' shelly/shelly.sh
grep -q 'aliases.fish' shelly/shelly.sh

# Alias assets should be shell-aware and no longer rely on the legacy repo-root .aliases file.
test -f aliases/common.sh
test -f aliases/aliases.zsh
test -f aliases/aliases.bash
test -f aliases/common.fish
test -f aliases/aliases.fish
! grep -q '~/.config/zsh/.aliases' .aliases
! grep -q 'exec zsh -l' .aliases
! grep -q 'alias zshrc=' .aliases

# iOSiSH alias install path should target shell-specific destinations.
grep -q '\.config/iosish/aliases.zsh' iOSiSH.sh
grep -q '\.config/iosish/aliases.bash' iOSiSH.sh
grep -q '\.config/iosish/aliases.fish' iOSiSH.sh

grep -q 'Noninteractive mode: skipping optional alias integration prompt' iOSiSH.sh

DRY_RUN=1 NONINTERACTIVE=1 PRIMARY_USER=rabbit PRIMARY_HOME=/home/rabbit PRIMARY_PASSWORD=placeholder ROOT_PASSWORD=placeholder ISH_LISTEN_PORT=22 HOME_PC_HOST=example.com HOME_PC_USER=rabbit HOME_PC_PORT=22 PC_SOCKS_PORT=1080 ./iOSiSH.sh --dry-run --ssh-hardened >/tmp/iosish-smoke.log 2>&1

grep -q 'dry-run' /tmp/iosish-smoke.log
grep -q 'Delegating shell installation and configuration to Shelly' /tmp/iosish-smoke.log
grep -q 'hardened defaults' /tmp/iosish-smoke.log
