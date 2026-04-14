# Shell Setup Repo

Interactive shell setup scripts for:

- Arch Linux
- Alpine Linux on iSH

## Features

- Interactive by default
- Optional unattended flags
- Root only mode
- `--primary-user USER` identify or create behavior
- Zsh, Bash, Fish, or all three
- Per shell prompt selection
- Optional fetch tool setup:
  - fastfetch
  - neofetch
  - neither
- Continues when packages are missing
- Package alias helpers
- Backups for changed config files
- Summary output for changed files, missing packages, and skipped components

## Repo contents

- `scripts/arch_shell_setup.sh`
- `scripts/alpine_ish_shell_setup.sh`
- `docs/arch_shell_setup_doc.md`
- `docs/alpine_ish_shell_setup_doc.md`

## Examples

### Interactive
```bash
sudo bash scripts/arch_shell_setup.sh
sudo bash scripts/alpine_ish_shell_setup.sh
