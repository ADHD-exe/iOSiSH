#!/usr/bin/env bash
set -euo pipefail

sh -n iOSiSH.sh
sh -n installer/prompts.sh
sh -n installer/plan.sh
sh -n installer/summary.sh
sh -n installer/state.sh
sh -n installer/shells.sh

state_file="$(mktemp)"
log_file="$(mktemp)"

INSTALLER_STATE_FILE="$state_file" INSTALLER_RUNTIME_LOG="$log_file" DRY_RUN=1 NONINTERACTIVE=1 PRIMARY_USER=rabbit HOME_PC_HOST=example.invalid HOME_PC_USER=rabbit ./iOSiSH.sh --dry-run --ssh-hardened >/tmp/iosish-smoke.log 2>&1 || {
  cat /tmp/iosish-smoke.log
  exit 1
}

grep -q 'Starting shells step' "$log_file"
grep -q 'Completed shells step' "$log_file"
grep -q 'Native shell setup complete' /tmp/iosish-smoke.log
grep -q 'INSTALL_SHELLS=all' "$state_file"
grep -q 'ROOT_DEFAULT_SHELL=bash' "$state_file"
grep -q 'USER_DEFAULT_SHELL=zsh' "$state_file"
grep -q 'FETCH_CHOICE=fastfetch' "$state_file"
