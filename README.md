# iOSiSH

Bootstrap and workflow tooling for **Alpine Linux on iSH**.

## Current architecture

The repo now separates responsibilities clearly:

- `shelly/shelly.sh` is the **only owner** of shell installation and shell configuration
- `iOSiSH.sh` handles iSH/bootstrap/SSH/system setup, then delegates shell work to Shelly
- optional iOSiSH aliases are offered **after** Shelly completes, and only for the shell(s) the user actually chose

## Ownership boundary

### `shelly/shelly.sh` owns
- installing Bash, Zsh, Fish, or all three
- installing prompt/framework/plugin components for the selected shell(s)
- creating or updating `.zshrc`, `.bashrc`, and Fish config
- selecting default shell behavior for root and the primary user
- writing a state file at `~/.config/shelly/selection.env` so later steps can read the chosen shell setup

### `iOSiSH.sh` owns
- primary-user and hostname setup
- package/bootstrap tasks outside shell ownership
- SSH server/client configuration
- OpenRC/service wiring
- optional alias installation into `~/.config/iosish/` after Shelly finishes

## Alias flow

After Shelly completes, `iOSiSH.sh` can prompt to install optional alias assets for the configured shell(s):

- Zsh: `~/.config/iosish/aliases.zsh`
- Bash: `~/.config/iosish/aliases.bash`
- Fish: `~/.config/iosish/aliases.fish`

The alias files live in the repo under:

- `aliases/common.sh`
- `aliases/aliases.zsh`
- `aliases/aliases.bash`
- `aliases/common.fish`
- `aliases/aliases.fish`

## Important migration note

The repo root `.zshrc` and legacy `.aliases` are no longer the canonical install path. They may remain in the repository temporarily as compatibility/reference artifacts, but `iOSiSH.sh` should not install them.

## Main scripts

### `iOSiSH.sh`
- validates config
- prepares the system and primary user
- delegates shell setup to Shelly
- offers optional alias installation
- configures SSH and supporting iSH workflow pieces

### `shelly/shelly.sh`
- interactive or unattended shell installer
- supports `bash`, `zsh`, `fish`, or `all`
- writes shell config files directly
- installs only the shell packages selected by the user/config

## Quick usage

### Interactive

```bash
sh ./iOSiSH.sh
```

### Dry-run

```bash
sh ./iOSiSH.sh --dry-run
```

### Run Shelly directly

```bash
bash ./shelly/shelly.sh --primary-user rabbit
```

## Generated state and handoff files

- `REPO_WORKLOG.md` — repo-tracked progress and handoff log
- `~/.config/shelly/selection.env` — machine-readable shell selection state written by Shelly

## Testing

Current smoke coverage checks:

- `sh -n iOSiSH.sh`
- `bash -n shelly/shelly.sh`
- `iOSiSH.sh --help`
- dry-run smoke execution

## Notes

- Shell ownership intentionally lives in Shelly now.
- Root no longer reuses shared Zsh assets through shell symlinks.
- Optional aliases are shell-aware and opt-in.
