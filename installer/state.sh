#!/bin/sh
# installer/state.sh
# State management helpers for the iOSiSH guided installer.

: "${INSTALLER_STATE_FILE:=./.iosish-state.env}"

state_file_path() {
  printf '%s\n' "$INSTALLER_STATE_FILE"
}

state_ensure_file() {
  state_dir=$(dirname "$INSTALLER_STATE_FILE")
  [ -d "$state_dir" ] || mkdir -p "$state_dir" || return 1
  [ -f "$INSTALLER_STATE_FILE" ] || : >"$INSTALLER_STATE_FILE" || return 1
}

state_has_key() {
  key=$1
  [ -n "$key" ] || return 1
  [ -f "$INSTALLER_STATE_FILE" ] || return 1
  grep -Eq "^${key}=" "$INSTALLER_STATE_FILE"
}

state_get() {
  key=$1
  [ -n "$key" ] || return 1
  [ -f "$INSTALLER_STATE_FILE" ] || return 1
  awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, "", $0); print; exit }' "$INSTALLER_STATE_FILE"
}

state_set() {
  key=$1
  value=$2

  [ -n "$key" ] || return 1
  state_ensure_file || return 1

  escaped_value=$(printf '%s' "$value" | sed 's/[\/&]/\\&/g')

  if state_has_key "$key"; then
    sed "s/^${key}=.*/${key}=${escaped_value}/" "$INSTALLER_STATE_FILE" >"${INSTALLER_STATE_FILE}.tmp" || return 1
    mv "${INSTALLER_STATE_FILE}.tmp" "$INSTALLER_STATE_FILE" || return 1
  else
    printf '%s=%s\n' "$key" "$value" >>"$INSTALLER_STATE_FILE" || return 1
  fi
}

state_unset() {
  key=$1
  [ -n "$key" ] || return 1
  [ -f "$INSTALLER_STATE_FILE" ] || return 0

  grep -Ev "^${key}=" "$INSTALLER_STATE_FILE" >"${INSTALLER_STATE_FILE}.tmp" || return 1
  mv "${INSTALLER_STATE_FILE}.tmp" "$INSTALLER_STATE_FILE" || return 1
}

state_load() {
  state_ensure_file || return 1
  # shellcheck disable=SC1090
  . "$INSTALLER_STATE_FILE"
}

state_init_defaults() {
  state_ensure_file || return 1

  state_set INSTALL_STATUS "new"
  state_set LAST_COMPLETED_STEP ""
  state_set CURRENT_STEP ""
  state_set STEP_USERS_DONE "no"
  state_set STEP_SHELLS_DONE "no"
  state_set STEP_PACKAGES_DONE "no"
  state_set STEP_EDITOR_DONE "no"
  state_set STEP_SSH_DONE "no"
  state_set STEP_SSHD_DONE "no"
  state_set STEP_PRIVILEGE_DONE "no"
  state_set STEP_SERVICES_DONE "no"
  state_set STEP_EXTRAS_DONE "no"
  state_set COLOR_OUTPUT "auto"
  state_set OUTPUT_MODE "normal"
  state_set INTERACTIVE_MODE "yes"
  state_set EDITOR_SETUP_MODE "recommended"
  state_set SSHD_PROFILE "recommended"
  state_set SSHD_PORT "2222"
  state_set SSHD_ALLOW_ROOT "no"
  state_set SSHD_PASSWORD_AUTH "yes"
  state_set SSHD_GATEWAY_PORTS "no"
  state_set SSHD_HOTSPOT_BYPASS "no"
  state_set SSHD_ENABLE_AT_BOOT "yes"
  state_set SSHD_START_NOW "yes"
  state_set ENABLED_SERVICES ""
  state_set START_NOW_SERVICES ""
  state_set INSTALL_DOC_WRAPPER "no"
  state_set INSTALL_COMPLETION_WRAPPER "no"
}

state_mark_step_started() {
  step=$1
  [ -n "$step" ] || return 1
  state_set CURRENT_STEP "$step"
  state_set INSTALL_STATUS "in_progress"
}

state_mark_step_done() {
  step=$1
  [ -n "$step" ] || return 1

  state_set CURRENT_STEP ""
  state_set LAST_COMPLETED_STEP "$step"
  state_set INSTALL_STATUS "in_progress"

  case "$step" in
  users) state_set STEP_USERS_DONE "yes" ;;
  shells) state_set STEP_SHELLS_DONE "yes" ;;
  packages) state_set STEP_PACKAGES_DONE "yes" ;;
  editor) state_set STEP_EDITOR_DONE "yes" ;;
  ssh) state_set STEP_SSH_DONE "yes" ;;
  sshd) state_set STEP_SSHD_DONE "yes" ;;
  privilege) state_set STEP_PRIVILEGE_DONE "yes" ;;
  services) state_set STEP_SERVICES_DONE "yes" ;;
  extras) state_set STEP_EXTRAS_DONE "yes" ;;
  esac
}

state_mark_failed() {
  step=$1
  [ -n "$step" ] || step="unknown"
  state_set CURRENT_STEP "$step"
  state_set INSTALL_STATUS "failed"
}

state_mark_complete() {
  state_set CURRENT_STEP ""
  state_set INSTALL_STATUS "complete"
}

state_step_done() {
  step=$1
  [ -n "$step" ] || return 1
  case "$step" in
    users) [ "$(state_get STEP_USERS_DONE 2>/dev/null || true)" = "yes" ] ;;
    shells) [ "$(state_get STEP_SHELLS_DONE 2>/dev/null || true)" = "yes" ] ;;
    packages) [ "$(state_get STEP_PACKAGES_DONE 2>/dev/null || true)" = "yes" ] ;;
    editor) [ "$(state_get STEP_EDITOR_DONE 2>/dev/null || true)" = "yes" ] ;;
    ssh) [ "$(state_get STEP_SSH_DONE 2>/dev/null || true)" = "yes" ] ;;
    sshd) [ "$(state_get STEP_SSHD_DONE 2>/dev/null || true)" = "yes" ] ;;
    privilege) [ "$(state_get STEP_PRIVILEGE_DONE 2>/dev/null || true)" = "yes" ] ;;
    services) [ "$(state_get STEP_SERVICES_DONE 2>/dev/null || true)" = "yes" ] ;;
    extras) [ "$(state_get STEP_EXTRAS_DONE 2>/dev/null || true)" = "yes" ] ;;
    *) return 1 ;;
  esac
}

state_reset() {
  rm -f -- "$INSTALLER_STATE_FILE"
  state_ensure_file || return 1
  state_init_defaults
}

state_any_completed() {
  for step in users shells packages editor ssh sshd privilege services extras; do
    if state_step_done "$step"; then
      return 0
    fi
  done
  return 1
}

state_set_install_status() {
  value=$1
  [ -n "$value" ] || return 1
  state_set INSTALL_STATUS "$value"
}
