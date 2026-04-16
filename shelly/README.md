# Shelly

Interactive shell setup tooling for Alpine Linux on iSH.

## Scope

Shelly is now the **sole shell owner** for this repository. It is responsible for:

- installing Bash, Zsh, Fish, or all three
- installing prompt/framework/plugin components for the selected shell(s)
- creating or updating shell config files
- selecting default shell behavior for root and the primary user
- writing a shell selection state file for downstream tools

## Main features

- `--auto-install` unattended defaults
- `--noninteractive` for scripted use with explicit flags
- `--root-only`
- `--primary-user USER`
- `--install-shells zsh|bash|fish|all`
- `--root-shell zsh|bash|fish`
- `--user-shell zsh|bash|fish`
- `--zsh-prompt omz|starship|powerlevel10k`
- `--bash-prompt framework|starship`
- `--fish-prompt tide|starship`
- `--fetch-tool fastfetch|neofetch|neither`
- writes `~/.config/shelly/selection.env` after setup
- inserts alias hook points so iOSiSH can later add optional shell-aware aliases

## Notes

- Shelly installs only the shell packages actually selected
- `iOSiSH.sh` should not install `.zshrc`, `.bashrc`, Fish config, Oh My Zsh, or Zinit directly
- optional aliases are a later step and are not forced during shell setup
