# iOSiSH
# iSOiSH

```text
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
$$$$$$$$$$$$$$$$$$$$$$$$$$$$'`$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
$$$$$$$$$$$$$$$$$$$$$$$$$$$    $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
$$$$$$$$$$$$$$$$$$$$$$$$$(  $w  $$$$$$@"                   m$$$$$
$$$$$$$$$$$$$$$$$$$$$$$$. ,$$$@  B$$$                        !$$$
$$$$$$$$$$$$$$$$$$$$$$$  @$$$$$$  %$!                         ;$$
$$$$$$$$$$$$$$$$k,@$$1  $$$$$$$$$  )$h      d                  $$
$$$$$$$$$$$$$$$I   .  :$$$$$@|$$$$' `$@      @@;               $$
$$$$$$$$$$$$$@  B$U  @$$$$$$    @$$>  @B       @@              $$
$$$$$$$$$$$$c  $$$$$@$. i$z  ja:  ,$v  @@   %@B                $$
$$$$$$$$$$$'  $@I $@  O    ''  ,r[   d  @@        @@@@@@B      $$
$$$$$$$$$@  @@   k  ) vf          :."    @@                    $$
$$$$$$$$r  B  ?   ^  l:                   m@@                  $$
$$$$$$$' `  ..`                             @@@                $$
$$$$$$                      ?B@@$$$$@@@Bx     @@@B            ]$[
$$$$j               o$$$$$$@BBB@$$$$$@@@@@@@@@@@@@@@@@@@@@@@@@U $
$$$.           b$$$n                     U@@@@@@@@@@@@@@@@@Z   @$
$$         J@@Z@$@YI      'IU@$$$$@@^                      / ^$$$
t      .@$@d                       `@@$$@W.             @q !$$$$$
;  :@$$8`B$$$$$$$$$$$$$$$@<               b@@@@@@@@@@@"M$$$$$$$$$
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$@)             .p$$$$$$$$$$$$$$$$
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
```

Alpine Linux + iSH setup for iPhone with zsh, SSH, and quality-of-life tooling.

## Features

- Zsh + plugins
- SSH setup
- iSH-friendly package installs
- Mobile-focused workflow
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
- automatic installation of available **manpages/docs** for packages already on the system and packages installed by the script

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
- automatically try to install:
  - `mandoc`
  - `man-pages`
  - matching `*-doc` packages where Alpine provides them
- prompt you for:
  - iSH hostname
  - primary username
  - primary home directory
  - primary user password
  - root password
  - remote SSH host
  - remote SSH username
  - remote SSH port
  - local SOCKS tunnel port for `remote-tunnel`
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
- create these SSH client entries:
  - `ssh remote`
  - `ssh -N remote-tunnel`
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
REMOTE_TUNNEL_PORT="1080"

# To run script
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ADHD-exe/iOSiSH/main/iOSiSH.sh)"
```

---

## Generated SSH client profiles

The script writes a shared SSH client config with these entries:

### `remote`

Standard SSH login to the configured remote host:

```sh
ssh remote
```

### `remote-tunnel`

SOCKS proxy profile using `DynamicForward` on the chosen local port:

```sh
ssh -N remote-tunnel
```

By default the SOCKS listener is:

```text
localhost:1080
```
