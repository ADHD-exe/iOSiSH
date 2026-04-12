# iOSiSH

Bootstrap script for **Alpine Linux on iSH** with an SSH workflow designed around an iPhone hotspot and a home PC.

This setup is built around **three SSH profiles**:

1. **`ish-hotspot`**  
   From the **home PC**, open a **SOCKS5 proxy** through the iSH SSH server.

2. **`ssh-home`**  
   From **inside iSH**, connect back to the **home PC** over SSH.

3. **`ssh-ish`**  
   From the **home PC**, do a normal SSH login into the iSH SSH server.

---

## What this script configures

### On iSH

- installs and configures **OpenSSH server**
- configures `sshd` to listen on all interfaces
- enables forwarding-related options for tunnel use:
  - `AllowTcpForwarding yes`
  - `GatewayPorts yes`
  - `PermitTunnel yes`
- enables normal SSH login:
  - `PermitRootLogin yes`
  - `PasswordAuthentication yes`
  - `PubkeyAuthentication yes`
- generates SSH host keys
- creates a primary user
- sets passwords for `root` and the primary user
- installs Zsh, Oh My Zsh, Zinit, tools, and manpages/docs
- writes an iSH-side SSH client profile named **`ssh-home`**
- generates **PC-side SSH config snippets** for:
  - `ish-hotspot`
  - `ssh-ish`

### On the home PC

The script **cannot directly edit your home PC**, but it generates ready-to-copy files inside iSH at:

```text
/home/<primary-user>/pc-ssh-snippets
```

That directory contains:

- `pc_ssh_config.conf`
- `pc_commands.txt`
- `README.txt`

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

## Interactive values the script asks for

The installer now asks for values that actually match the final setup:

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

If you leave the **home PC SSH host** blank, the script skips `ssh-home`.

---

## The three SSH setups

## 1) `ish-hotspot`

This is for the **home PC**.

It creates a local SOCKS5 proxy on the home PC, routed through the iSH SSH server over your iPhone hotspot.

### Direct command from the home PC

```sh
ssh -N -D 1080 root@172.20.10.10 -p 22
```

### Recommended SSH config on the home PC

```sshconfig
Host ish-hotspot
    HostName 172.20.10.10
    User root
    Port 22
    DynamicForward 1080
    ExitOnForwardFailure yes
    ServerAliveInterval 30
    ServerAliveCountMax 3
    TCPKeepAlive yes
```

### Start it

```sh
ssh -N ish-hotspot
```

### Then point apps on the home PC to

```text
Host: 127.0.0.1
Port: 1080
Type: SOCKS5
```

---

## 2) `ssh-home`

This is created **inside iSH**.

It is an outbound SSH client profile from iSH to your home PC.

### Inside iSH

```sh
ssh ssh-home
```

The script writes this profile into:

```text
/home/<primary-user>/.ssh/config
```

Example generated structure:

```sshconfig
Host ssh-home
    HostName <home-pc-host>
    User <home-pc-user>
    Port <home-pc-port>
    IdentityFile /home/<primary-user>/.ssh/id_ed25519
    IdentitiesOnly yes
    PreferredAuthentications publickey,password
    PubkeyAuthentication yes
```

---

## 3) `ssh-ish`

This is for the **home PC**.

It is a normal SSH login into iSH over the hotspot.

### Direct command from the home PC

```sh
ssh root@172.20.10.10 -p 22
```

### Recommended SSH config on the home PC

```sshconfig
Host ssh-ish
    HostName 172.20.10.10
    User root
    Port 22
    ServerAliveInterval 30
    ServerAliveCountMax 3
    TCPKeepAlive yes
```

### Start it

```sh
ssh ssh-ish
```

---

## SSH server settings applied on iSH

The script ensures these server-side settings in `/etc/ssh/sshd_config`:

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

---

## Files created by the script

### Shared shell assets

- `/home/<primary-user>/.zshrc`
- `/home/<primary-user>/.config/zsh/.aliases`
- `/home/<primary-user>/.oh-my-zsh`
- `/home/<primary-user>/.local/share/zinit`

### Shared SSH assets on iSH

- `/home/<primary-user>/.ssh/config`
- `/home/<primary-user>/.ssh/id_ed25519`
- `/home/<primary-user>/.ssh/id_ed25519.pub`

### PC-side snippets generated from iSH

- `/home/<primary-user>/pc-ssh-snippets/pc_ssh_config.conf`
- `/home/<primary-user>/pc-ssh-snippets/pc_commands.txt`
- `/home/<primary-user>/pc-ssh-snippets/README.txt`

Root is then linked back to the shared shell and SSH assets through symlinks under `/root`.

---

## Important limitation

The script can prepare the **config snippets** for your home PC, but it cannot automatically write into your home PC's `~/.ssh/config` from inside iSH.

You still need to:

1. copy the generated PC snippet file out of iSH
2. merge it into the home PC's `~/.ssh/config`

---

## Hotspot reminder

The default hotspot IP often used in this setup is:

```text
172.20.10.10
```

But hotspot addressing can change.

If the iSH hotspot IP changes, update the **home PC** config snippet for:

- `ish-hotspot`
- `ssh-ish`

---

## Notes

- `ish-hotspot` and `ssh-ish` are **PC-side** profiles
- `ssh-home` is an **iSH-side** profile
- the installer now matches that architecture directly
- manpages/docs are installed for both already-installed packages and packages added by the script where Alpine provides matching doc packages
