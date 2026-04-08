# iOSiSH

Bootstrap script for **Alpine Linux on iSH (iPhone/iPad)**.

This repo is focused on getting a practical shell-first environment working on iSH with:

- a real user account
- Zsh as the login shell for both `root` and `rabbit`
- Oh My Zsh + Zinit
- stable Zsh plugins that work on iSH
- OpenSSH server + client config
- sudo + doas
- OpenRC best-effort service registration
- iSH-safe aliases
- persistent hostname handling for the iSH hostname limitation

---

## What this script does

The main script is:

- `iOSiSH.sh`

It is intended to be run as **root** on Alpine inside iSH.

### It will:

- update and upgrade packages with `apk`
- install core tools including:
  - `zsh`
  - `git`
  - `curl`
  - `openssh`
  - `sudo`
  - `doas`
  - `openrc`
  - `tmux`
  - `exa`
- create/configure the user:
  - `rabbit`
- set login shell to `zsh` for:
  - `root`
  - `rabbit`
- set passwords exactly to:
  - `root: dorothy`
  - `rabbit: dorothy`
- install **Oh My Zsh** for both users
- install **Zinit** for both users
- enable these plugin components:
  - `zsh-completions`
  - `zsh-autosuggestions`
  - `zsh-history-substring-search`
  - `fast-syntax-highlighting`
  - fallback `zsh-syntax-highlighting`
- create:
  - `~/.config/zsh/.aliases`
- source that aliases file from `.zshrc`
- configure **OpenSSH server** in:
  - `/etc/ssh/sshd_config`
- configure **SSH client aliases** in:
  - `/root/.ssh/config`
  - `/home/rabbit/.ssh/config`
- generate SSH keys for:
  - `root`
  - `rabbit`
- write persistent hostname:
  - `iOSiSH`
- configure prompt to read `/etc/hostname` instead of relying on the live hostname
- install OpenRC and attempt to register `sshd`
- start `sshd` in a best-effort way for iSH

---

## Important iSH behavior

iSH has some constraints that affect normal Alpine/Linux behavior.

### Hostname limitation

On iSH, this often fails:

```sh
hostname iOSiSH
