# iOSiSH
```

$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
$$$$$$$$$$$$$$$$$$$ |$$\ $$$$$$\  $$$$$$\ $$\ $$$$$$\ $$\   $$\ $$$$$$$$$$$$$$$$$$$$$$$$$$
$$$$$$$$$$$$$$$$$$$ |$$\$$ /  \__$$ /  $$ $$\$$ /  \__$$ |  $$ |$$$$$$$$$$$$$$$$$$$$$$$$$$
$$$$$$$$$$$$$$$$$$$ |$$ \$$$$$$\ $$ |  $$ $$ \$$$$$$\ $$$$$$$$ |$$$$$$$$$$$$$$$$$$$$$$$$$$
$$$$$$$$$$$$$$$$$$$ |$$ |\____$$\$$ |  $$ $$ |\____$$\$$  __$$ |$$$$$$$$$$$$$$$$$$$$$$$$$$
$$$$$$$$$$$$$$$$$$$ |$$ $$\   $$ $$ |  $$ $$ $$\   $$ $$ |  $$ |$$$$$$$$$$$$$$$$$$$$$$$$$$
$$$$$$$$$$$$$$$$$$$ |$$ \$$$$$$  |$$$$$$  $$ \$$$$$$  $$ |  $$ |$$$$$$$$$$$$$$$$$$$$$$$$$$
$$$$$$$$$$$$$$$$$$$ \__|\______/ \______/\__|\______/\__|  \__|$$$$$$$$$$$$$$$$$$$$$$$$$$$
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$@B$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$:   @$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$B      @$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$@[   $@   @$$$$$$$$@v.                         !$@$$$$$$
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$@`  +$$$@   p$$$$$$`                               f$$$$$
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$8   B$$$$$@^  <$$$z                                  .@$$$
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$1   @$$$$$$$$i  ^@$Q                                   `$$$
$$$$$$$$$$$$$$$$$$$$$$$@@$$$$$'  1$$$$$$$$$$$\  .@$@                                   B$$
$$$$$$$$$$$$$$$$$$$$$$.  .@$8   $$$$$$$$$$$$$$m   $$@       {@@B                       *$$
$$$$$$$$$$$$$$$$$$$$p         .$$$$$$$$B :@$$$$@   @$@         %@@p                    *$$
$$$$$$$$$$$$$$$$$$$<  '@$m   n@$$$$$$$)     n$$$$   8@B          #@@                   o$$
$$$$$$$$$$$$$$$$$B   8$$$$$n@$@z '$$@;  raI   `@$@`  [@@.     \@@B                     o$$
$$$$$$$$$$$$$$$$z   $$$$$$$$$)    r$.  {< qOu    l$:  .@@[  B@@                        o$$
$$$$$$$$$$$$$$$;  .$$@" '$$+  /Z^     '     n(]i        @@W           @@@@@@@@L        o$$
$$$$$$$$$$$$$@.  @$@.   $i  (j Xu             :; ;       @@B                           o$$
$$$$$$$$$$$$C   @@   u    !`  1-I                . .'    .@@B                          o$$
$$$$$$$$$$$;  `U   i-   '    I"  "                         %@@@                        o$$
$$$$$$$$$$   !    ."                                        .@@@@                      *$$
$$$$$$$$c                                   ^",,:".           .@@@@d                   #$C
$$$$$$@!                        ^M@@$$@@@$$$$$$$$$$$$$$$@@@@@@@q.B@@@@@@:          mB@@@l@
$$$$$$                    _@$$$$$@@@BQ>`  .;]zo$@@$@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@B  \$
$$$$f                `@$$$$wI                           (B@@@@@@@@@@@@@@@@@@@@@@@@@    1$$
$$@"             'B$$$f~B@@$$$$$@@$$$$$$$$$$$@|'               'aB@@@@@@@@@@B1     .  @$$$
$@            @@@@@@B).                   .,O@$$$$$@m.                           @  [$$$$$
j         ?@$$$Q                                 .($$$$$$@Y                 _@@< .@$$$$$$$
.     i@$$@w.'[B@$$$$$$$$$$$$$$@@M<.                   ./@@@@@@@@@@@@@@@@@@B `o@$$$$$$$$$$
$$$$$$$$@@$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$@].                       .'. "B$$$$$$$$$$$$$$$$$$
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$@@@ml'         .I_&$$$$$$$$$$$$$$$$$$$$$$$$$
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

```
Bootstrap script for **Alpine Linux on iSH (iPhone/iPad)**.

This repo is focused on getting a practical shell-first environment working on iSH with:

- a real primary user account
- Zsh as the login shell for both `root` and the primary user
- Oh My Zsh + Zinit
- stable Zsh plugins that are realistic for iSH
- OpenSSH server + SSH client config
- sudo + doas
- OpenRC best-effort service registration
- iSH-safe aliases
- persistent hostname handling for the iSH hostname limitation
- automatic installation of available manpages/docs for installed packages

---

## What this script does

The main script is:

- `iOSiSH.sh`

It is intended to be run as **root** on Alpine inside iSH.
### Packages installed include 


The setup script installs a solid Alpine/iSH baseline for shell workflow, editing, development, SSH access, networking, and optional security tooling.

- Shell and terminal basics
  - `bash`
  - `zsh`
  - `ncurses`
  - `less`
  - `grep`
  - `sed`
  - `coreutilsl`
  - `util-linux`
  - `diffutils`
  - `findutils`
  - `file`
  - `patch`
  - `tree`
  - `nano`

- Shell experience and workflow
  - `fzf`
  - `zoxide`
  - `tmux`
  - `htop`
  - `ripgrep`
  - `fd`
  - `lazygit`
  - `neofetch`

- Editors and coding environment
  - `neovim`
  - `git`
  - `jq`
  - `shellcheck`
  - `abuild`
  - `gcc`
  - `linux-headers`
  - `linux-lts-headers`
  - `linux-edge-headers`
  
- Programming languages and runtimes
  - `python3`
  - `py3-pip`
  - `py3-setuptools`
  - `nodejs`
  - `npm`
  - `go`
  - `rust`

- SSH, remote access, and privilege tools
  - `openssh`
  - `openssh-server`
  - `openssh-client`
  - `openssh-client-default`
  - `sudo`
  - `doas`
  - `shadow`
  - `openrc`
  - `iptables-openrc`
  - `util-linux-openrc`

- Archive and transfer tools
  - `curl`
  - `wget`
  - `unzip`
  - `zip`


- Torrent and transfer tools
  - `transmission`
  - `transmission-cli`
  - `transmission-daemon`

- Mail and server-related packages
  - `dovecot`

- Documentation and manpages
  - `man-pages`
  - `mandoc`
  - `less-doc`

- Security, pentesting, networking and diagnostics:
  - `nikto`
  - `aircrack-ng`
  - `sqlmap`
  - `masscan`
  - `snort`
  - `fwsnort`
  - `strongswan`
  - `nmap`
  - `bind-tools`
  - `socat`
  - `whois`
  - `jwhois`
  
Notes:

Some packages use Alpine fallback names in the script, so the exact installed variant can differ depending on repository availability.
Some heavier packages may be limited by iSH and iOS sandboxing.

### It will

- update `apk` indexes
- set the login shell to `zsh` for:
  - `root`
  - the primary user
- create:
  - `~/.config/zsh/.aliases`
- source that aliases file from `.zshrc`
- generate a shared SSH keypair
- write persistent hostname data to:
  - `/etc/hostname`
  - `/etc/hosts`
- configure the prompt to read `/etc/hostname` instead of relying on iSH’s live hostname behavior
- configure **OpenSSH server** in:
  - `/etc/ssh/sshd_config`
- configure **SSH client config** in:
  - `/home/<primary-user>/.ssh/config`
- link root back to the shared shell and SSH assets under `/root`
- start `sshd` in a best-effort way for iSH
- generate copy-ready SSH config snippets for a home PC

---

## Fresh iSH install run command

On a fresh iSH install you are already `root`, so you do **not** need `su - root`.

```sh
apk update && apk upgrade && apk add curl

curl -fsSL https://raw.githubusercontent.com/ADHD-exe/iOSiSH/main/iOSiSH.sh -o /tmp/iOSiSH.sh && \
chmod +x /tmp/iOSiSH.sh && \
/tmp/iOSiSH.sh
```

---

## Interactive setup

The installer prompts for values that match the current script behavior:
- iSH hostname
- primary username
- primary home directory
- primary user password
- root password
- iSH SSH listen port
- expected iSH hotspot IP
- home PC SSH host
- home PC SSH port
- home PC SSH username
- SOCKS5 port to use on the home PC

If you leave the **home PC SSH host** blank, the script skips the outbound `ssh-home` profile.

---

## Shell environment

The script builds a shared shell setup owned by the primary user and reused by root.

### Shared shell assets

- `/home/<primary-user>/.zshrc`
- `/home/<primary-user>/.config/zsh/.aliases`
- `/home/<primary-user>/.oh-my-zsh`
- `/home/<primary-user>/.local/share/zinit`

### Zsh behavior

The generated `.zshrc` is set up to provide:

- history settings tuned for interactive shell use
- completion initialization that avoids common iSH/ownership issues
- a hostname-aware prompt based on `/etc/hostname`
- Oh My Zsh library/plugin loading where available
- Zinit plugin loading for:
  - `zsh-completions`
  - `zsh-autosuggestions`
  - `zsh-history-substring-search`
  - `fast-syntax-highlighting`
- optional `neofetch` on shell startup if installed

### Aliases

The script writes a shared aliases file and sources it from `.zshrc`.

That keeps aliases separate from the main shell config and makes it easier to edit later.

---

## User, privilege, and hostname setup

The script creates a primary user, adds that user to `wheel`, and configures:

- `sudo`
- `doas`

It also writes:

- `/etc/hostname`
- `/etc/hosts`

This matters on iSH because the live hostname behavior is not always what you want the prompt to display.

---

## SSH setup

SSH is one major part of the script, but not the whole point of the repo.

The script configures iSH as an SSH server and also prepares client-side configs for common hotspot workflows.

### Server-side SSH settings

The script ensures these settings in `/etc/ssh/sshd_config`:

```text
Port 22
ListenAddress 0.0.0.0
AllowTcpForwarding yes
GatewayPorts yes
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
PermitEmptyPasswords no
Compression no
PermitTTY yes
PermitTunnel yes
```

### SSH assets on iSH

- `/home/<primary-user>/.ssh/config`
- `/home/<primary-user>/.ssh/id_ed25519`
- `/home/<primary-user>/.ssh/id_ed25519.pub`

### Three SSH workflows

#### `ish-hotspot`
From the **home PC**, open a **SOCKS5 proxy** through the iSH SSH server.

#### `ssh-home`
From **inside iSH**, connect back to the **home PC** over SSH.

#### `ssh-ish`
From the **home PC**, do a normal SSH login into the iSH SSH server.

### PC-side generated files

The script cannot directly edit your home PC, so it generates copy-ready files inside iSH at:

```text
/home/<primary-user>/pc-ssh-snippets
```

That directory contains:

- `pc_ssh_config.conf`
- `pc_commands.txt`
- `README.txt`

---

## Files created by the script

### Shell and shared assets

- `/home/<primary-user>/.zshrc`
- `/home/<primary-user>/.config/zsh/.aliases`
- `/home/<primary-user>/.oh-my-zsh`
- `/home/<primary-user>/.local/share/zinit`
- `/home/<primary-user>/.ssh/config`
- `/home/<primary-user>/.ssh/id_ed25519`
- `/home/<primary-user>/.ssh/id_ed25519.pub`

### PC-side snippets

- `/home/<primary-user>/pc-ssh-snippets/pc_ssh_config.conf`
- `/home/<primary-user>/pc-ssh-snippets/pc_commands.txt`
- `/home/<primary-user>/pc-ssh-snippets/README.txt`

### Root-side reuse

Root keeps its own home directory, but reuses the shared shell and SSH assets through symlinks under `/root`.

---

## iSH notes

A few parts of the script are intentionally **best effort** because iSH is not the same as a full native Alpine install.

That especially applies to:

- OpenRC behavior
- service startup behavior
- hotspot addressing stability
- long-running shell/server sessions on iPhone/iPad

A useful keep-awake helper is:

```sh
cat /dev/location > /dev/null &
```

You may also need to allow location access in iSH and enable the app’s keep-screen-on behavior depending on your setup.

---

## Notes

- this repo is a full iSH bootstrap/setup project, not just an SSH helper
- SSH is important here, but it is only one part of the environment being built
- manpages/docs are installed for both already-installed packages and packages added by the script where Alpine provides matching doc packages
- hotspot IPs can change, so generated PC-side SSH snippets may need to be updated later
