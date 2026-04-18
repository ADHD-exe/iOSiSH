#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
export INSTALLER_STATE_FILE="$tmpdir/test-state.env"

# shellcheck disable=SC1091
. ./installer/state.sh
# shellcheck disable=SC1091
. ./installer/prompts.sh
# shellcheck disable=SC1091
. ./installer/plan.sh
# shellcheck disable=SC1091
. ./installer/summary.sh

state_init_defaults
state_load

# Catalog sanity
package_catalog_categories | grep -qx 'core'
package_catalog_categories | grep -qx 'ssh'
[ "$(package_catalog_description ssh)" != "Unknown category." ]
package_catalog_members editors | grep -qw 'vim'
validate_category_list 'core,ssh'
! validate_category_list 'core,notreal'

# Preview building
PACKAGE_MODE=recommended
SELECTED_PACKAGE_CATEGORIES='core,ssh'
EXCLUDED_PACKAGES='curl'
preview="$(build_package_preview_from_state)"
printf '%s\n' "$preview" | grep -qw 'openssh-server'
! printf '%s\n' "$preview" | grep -qw 'curl'

PACKAGE_MODE=package
SELECTED_PACKAGES='vim nano vim'
EXCLUDED_PACKAGES='nano'
preview="$(build_package_preview_from_state)"
[ "$preview" = 'vim' ]

# Summary output should include key fields
state_set PRIMARY_USER rabbit
state_set RUN_SHELL_SETUP yes
state_set INSTALL_SHELLS all
state_set ROOT_DEFAULT_SHELL zsh
state_set USER_DEFAULT_SHELL zsh
state_set ZSH_PROMPT_CHOICE omz
state_set BASH_PROMPT_CHOICE framework
state_set FISH_PROMPT_CHOICE tide
state_set FETCH_CHOICE fastfetch
state_set PACKAGE_MODE recommended
state_set PACKAGE_PROFILE recommended
state_set SELECTED_PACKAGE_CATEGORIES 'core,ssh'
state_set EXCLUDED_PACKAGES 'curl'
state_set FINAL_PACKAGE_PREVIEW "$preview"
state_set EDITOR_CHOICE vim
state_set INSTALL_SSHD yes
state_set SSHD_PROFILE recommended
state_set INSTALL_SUDO yes
state_set INSTALL_DOAS no
state_set INSTALL_MANPAGES yes
state_load
summary_output="$(show_plan_summary)"
printf '%s\n' "$summary_output" | grep -q 'Primary user:.*rabbit'
printf '%s\n' "$summary_output" | grep -q 'Run shell setup:.*yes'
printf '%s\n' "$summary_output" | grep -q 'Install shells:.*all'
printf '%s\n' "$summary_output" | grep -q 'Package profile:.*recommended'
printf '%s\n' "$summary_output" | grep -q 'Editor choice:.*vim'
printf '%s\n' "$summary_output" | grep -q 'Install SSHD:.*yes'

progress_output="$(show_progress_summary)"
printf '%s\n' "$progress_output" | grep -q 'Users:.*no'
