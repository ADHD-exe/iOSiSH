# iOSiSH

This is my iSH setup script for Alpine on iPhone.

It sets up the stuff I actually use, gets `rabbit` configured, fixes up SSH in both directions, and puts Zsh, Oh My Zsh, and Zinit in place without adding a bunch of extra theme junk.

## What it does

- installs the packages I use in iSH
- sets up the `rabbit` user
- makes both `root` and `rabbit` start in Zsh
- configures Oh My Zsh and Zinit plugins
- sets up `sudo` and `doas`
- configures the iSH SSH server in `/etc/ssh/sshd_config`
- writes SSH client aliases in `~/.ssh/config`
- writes persistent hostname config for iSH

## Run it

Run it as root in iSH:

```sh
su - root
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ADHD-exe/iOSiSH/main/iOSiSH.sh)"
