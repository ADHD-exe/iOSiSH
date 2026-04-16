#!/bin/sh
# installer/prompts.sh
# Shared prompt helpers for guided installer flows.

print_section_header() {
  title=$1
  printf '
== %s ==
' "$title"
}

print_help_text() {
  help_text=$1
  [ -n "$help_text" ] || return 0
  printf '%s
' "$help_text"
}

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
      printf 'yes
'
      return 0
      ;;
    n | no)
      printf 'no
'
      return 0
      ;;
    esac

    printf 'Invalid response. Please answer yes or no.
' >&2
  done
}

prompt_choice() {
  prompt_text=$1
  default_value=$2
  shift 2

  printf '%s
' "$prompt_text"
  for choice in "$@"; do
    printf '  - %s
' "$choice"
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
        printf '%s
' "$reply"
        return 0
      }
    done

    printf 'Invalid choice. Please choose one of the listed options.
' >&2
  done
}

prompt_section_action() {
  section_name=$1
  print_section_header "$section_name"
  print_help_text "Choose skip to leave this section unchanged, recommended to use the default guided setup, or customize to pick settings yourself."
  prompt_choice "How would you like to handle ${section_name}?" "recommended"     "skip" "recommended" "customize"
}
