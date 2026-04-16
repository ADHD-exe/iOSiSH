#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
export INSTALLER_STATE_FILE="$tmpdir/test-state.env"

# shellcheck disable=SC1091
. ./installer/state.sh

state_ensure_file
[ -f "$INSTALLER_STATE_FILE" ]

state_init_defaults

grep -q '^INSTALL_STATUS=new$' "$INSTALLER_STATE_FILE"
grep -q '^STEP_USERS_DONE=no$' "$INSTALLER_STATE_FILE"
grep -q '^EDITOR_SETUP_MODE=recommended$' "$INSTALLER_STATE_FILE"

state_set PRIMARY_USER rabbit
[ "$(state_get PRIMARY_USER)" = "rabbit" ]
state_has_key PRIMARY_USER

state_mark_step_started users
[ "$(state_get CURRENT_STEP)" = "users" ]
[ "$(state_get INSTALL_STATUS)" = "in_progress" ]

state_mark_step_done users
[ "$(state_get STEP_USERS_DONE)" = "yes" ]
[ "$(state_get LAST_COMPLETED_STEP)" = "users" ]
state_step_done users
state_any_completed

state_mark_failed shells
[ "$(state_get CURRENT_STEP)" = "shells" ]
[ "$(state_get INSTALL_STATUS)" = "failed" ]

state_unset PRIMARY_USER
! state_has_key PRIMARY_USER

state_reset
[ "$(state_get INSTALL_STATUS)" = "new" ]
[ "$(state_get STEP_USERS_DONE)" = "no" ]
! state_any_completed
