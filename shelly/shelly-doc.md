# Shelly script reference

## Purpose

Installs and configures Bash, Zsh, Fish, or all three on Alpine Linux inside iSH.

## Ownership model

Shelly is the canonical owner of:

- shell package installation
- shell frameworks and prompt components
- `.zshrc`, `.bashrc`, and Fish config generation/update
- default shell selection behavior

`iOSiSH.sh` should delegate shell setup to Shelly, then continue with non-shell tasks.

## Main flags

- `--help`
- `--auto-install`
- `--noninteractive`
- `--root-only`
- `--primary-user USER`
- `--install-shells zsh|bash|fish|all`
- `--root-shell zsh|bash|fish`
- `--user-shell zsh|bash|fish`
- `--zsh-prompt omz|starship|powerlevel10k`
- `--bash-prompt framework|starship`
- `--fish-prompt tide|starship`
- `--fetch-tool fastfetch|neofetch|neither`

## Output state

Shelly writes `~/.config/shelly/selection.env` with fields such as:

- `INSTALL_SHELLS`
- `ROOT_DEFAULT`
- `USER_DEFAULT`
- `CONFIGURED_SHELLS`

This file is intended for downstream consumers such as `iOSiSH.sh`.

## Alias hooks

Shelly can place stable alias hook points in shell config files so optional alias files can be installed later:

- `~/.config/iosish/aliases.zsh`
- `~/.config/iosish/aliases.bash`
- `~/.config/iosish/aliases.fish`

## iSH-specific behavior

- does not modify `/etc/apk/repositories`
- uses current configured repositories only
- uses launcher fallback when shell switching is risky
- can attempt `chsh` only when `ALLOW_CHSH_ON_ISH=1`

## Default unattended behavior

- install all three shells
- root shell is bash
- primary user shell is zsh
- zsh prompt is powerlevel10k
- bash prompt is starship
- fish prompt is tide
- fetch tool is fastfetch

## Safety behavior

- creates `.bak` backups before appending managed shell blocks to existing shell config files
- warns and continues on many package failures
- tracks skipped components
