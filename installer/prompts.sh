#!/bin/sh
# installer/prompts.sh
# Shared prompt helpers for guided installer flows.

prompt_yes_no() {
  prompt_text=$1
  default_value=$2

  while :; do
    case "$default_value" in
    yes) printf '%s [Y/n]: ' "$prompt_text" ;;
    no) printf '%s [y/N]: ' "$prompt_text" ;;
    *) printf '%s [y/n]: ' "$prompt_text" ;;
    esac

    read -r reply || return 1
    reply=$(printf '%s' "$reply" | tr '[:upper:]' '[:lower:]')

    [ -n "$reply" ] || reply=$default_value

    case "$reply" in
    y | yes)
      printf 'yes\n'
      return 0
      ;;
    n | no)
      printf 'no\n'
      return 0
      ;;
    esac

    printf 'Please answer yes or no.\n' >&2
  done
}

prompt_choice() {
  prompt_text=$1
  default_value=$2
  shift 2

  printf '%s\n' "$prompt_text"
  for choice in "$@"; do
    printf '  - %s\n' "$choice"
  done

  while :; do
    if [ -n "$default_value" ]; then
      printf 'Choice [%s]: ' "$default_value"
    else
      printf 'Choice: '
    fi

    read -r reply || return 1
    [ -n "$reply" ] || reply=$default_value

    for choice in "$@"; do
      [ "$reply" = "$choice" ] && {
        printf '%s\n' "$reply"
        return 0
      }
    done

    printf 'Invalid choice.\n' >&2
  done
}

prompt_section_action() {
  section_name=$1
  prompt_choice "How would you like to handle ${section_name}?" "recommended" \
    "skip" "recommended" "customize"
}
