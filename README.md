# iOSiSH

Bootstrap script for **Alpine Linux on iSH (iPhone/iPad)**.

This repo sets up a practical shell-first environment on iSH with:

- a configurable **primary non-root user**
- **Zsh** as the login shell for both `root` and the primary user
- **Oh My Zsh** + **Zinit**
- shared shell assets owned by the primary user
- shared SSH client assets owned by the primary user
- **OpenSSH server** + client config
- **sudo** + **doas**
- OpenRC best-effort service registration
- iSH-safe aliases
- persistent hostname handling for the iSH hostname limitation

---

## What this script does

The main script is:

- `iOSiSH.sh`

It is intended to be run as **root** inside Alpine on iSH.

### It will:

- update `apk` indexes
- install a practical package set, including tools like:
  - `zsh`
  - `git`
  - `curl`
  - `openssh`
  - `sudo`
  - `doas`
  - `openrc`
  - `tmux`
  - `ripgrep`
  - `fd`
  - `fzf`
  - `neovim`
- prompt you for:
  - iSH hostname
  - primary username
  - primary home directory
  - primary user password
  - root password
  - remote SSH host
  - remote SSH username
  - remote SSH port
- confirm passwords before applying them
- let you review and re-edit the full configuration summary before install continues
- create or configure the primary user
- set the login shell to `zsh` for:
  - `root`
  - the primary user
- install **Oh My Zsh** for the primary user
- install **Zinit** for the primary user
- write a shared `.zshrc` owned by the primary user
- install a shared aliases file at:
  - `PRIMARY_HOME/.config/zsh/.aliases`
- generate a shared SSH keypair owned by the primary user
- write a shared SSH client config at:
  - `PRIMARY_HOME/.ssh/config`
- symlink root to the shared shell and SSH assets
- write a persistent hostname to:
  - `/etc/hostname`
- update `/etc/hosts`
- apply editable SSH server defaults to:
  - `/etc/ssh/sshd_config`
- install OpenRC and attempt to register `sshd`
- start `sshd` in a best-effort way for iSH
- run a small self-test at the end

---

## Shared asset model

This repo now uses a **shared asset** design.

The primary user owns the shell and SSH client assets, and `root` reuses them through symlinks.

### Primary user owns:

- `PRIMARY_HOME/.zshrc`
- `PRIMARY_HOME/.config/zsh/.aliases`
- `PRIMARY_HOME/.oh-my-zsh`
- `PRIMARY_HOME/.local/share/zinit`
- `PRIMARY_HOME/.ssh/config`
- `PRIMARY_HOME/.ssh/id_ed25519`
- `PRIMARY_HOME/.ssh/id_ed25519.pub`

### Root keeps its own real home:

- `/root`
- `/root/.profile`
- `/root/.zsh_history`
- `/root/.cache/...`

But root reuses the primary user's shell and SSH client config through symlinks under `/root`.

This avoids maintaining two separate Zsh/SSH setups.

---

## Default variable names used by the script

The script now uses these generic variable names:

```sh
ISH_HOSTNAME="iOSiSH"

PRIMARY_USER="rabbit"
PRIMARY_HOME="/home/$PRIMARY_USER"
PRIMARY_PASSWORD="insert-password"

ROOT_PASSWORD="insert-password"

REMOTE_HOST="1.1.1.1"
REMOTE_USER="insert_username"
REMOTE_PORT="22"
