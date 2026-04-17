# iOSiSH

Bootstrap and workflow tooling for **Alpine Linux on iSH**.

## Current architecture

The repo now separates responsibilities clearly:

- `shelly/shelly.sh` is the **only owner** of shell installation and shell configuration
- `iOSiSH.sh` is being refactored into a **state-driven guided installer**
- optional iOSiSH aliases are offered **after** Shelly completes, and only for the shell(s) the user actually chose

## Ownership boundary

### `shelly/shelly.sh` owns
- installing Bash, Zsh, Fish, or all three
- installing prompt/framework/plugin components for the selected shell(s)
- creating or updating user shell config files such as `.zshrc`, `.bashrc`, and Fish config
- selecting default shell behavior for root and the primary user
- writing a state file at `~/.config/shelly/selection.env` so later steps can read the chosen shell setup

### `iOSiSH.sh` owns
- the guided planning and execution flow
- primary-user and hostname setup
- package/bootstrap tasks outside shell ownership
- editor setup
- SSH server/client configuration
- OpenRC/service wiring
- optional alias, docs, and completion wrapper installation

## Guided installer status

The installer now has a state-driven planning layer with:

- resume-aware state loading
- a plan summary
- section editing during review
- save-and-quit support
- reset support
- runtime execution logging

Current state files/logs:

- `$INSTALLER_STATE_FILE` (default `./.iosish-state.env`) — installer state
- `$INSTALLER_RUNTIME_LOG` (default `./.iosish-install.log`) — runtime execution log
- `REPO_WORKLOG.md` — repo-tracked handoff/progress log
- `~/.config/shelly/selection.env` — machine-readable shell selection state written by Shelly

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

Legacy repo-root shell reference files now live under `legacy/`. They are not part of the active install path and should not be copied into a home directory as-is.

## Validation and tests

The repository includes lightweight validation assets:

- `tests/smoke.sh` - top-level smoke test runner
- `tests/state_smoke.sh` - installer state helper checks
- `tests/planner_smoke.sh` - package planner and summary checks
- `tests/runtime/ish-runtime-preflight.sh` - preflight checks to run inside iSH before manual validation
- `VALIDATION_CHECKLIST.md` - manual runtime validation checklist
- `BUG_REPORT_TEMPLATE.md` - structured bug report template for runtime findings

Run the automated checks from the repo root with:

```sh
bash tests/smoke.sh
```

## Main scripts

### `iOSiSH.sh`
- loads installer modules
- builds or resumes installer state
- shows a review summary with edit/save-quit options
- applies the selected plan
- configures user/system/editor/SSH/service pieces

### `shelly/shelly.sh`
- interactive or unattended shell installer
- supports `bash`, `zsh`, `fish`, or `all`
- writes shell config files directly
- installs only the shell packages selected by the user/config

## Quick start

### Clone the repo and run the installer

```bash
git clone https://github.com/ADHD-exe/iOSiSH.git
cd iOSiSH
sh ./iOSiSH.sh
```

### One-line clone + run

```bash
git clone https://github.com/ADHD-exe/iOSiSH.git && cd iOSiSH && sh ./iOSiSH.sh
```

If you already downloaded a zip archive instead of cloning, unpack it, `cd` into the repo directory, and run:

```bash
sh ./iOSiSH.sh
```

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
bash ./shelly/shelly.sh --primary-user <username-here>
```


## Runtime validation assets

The repo now includes manual runtime-validation assets for testing inside real iSH:

- `VALIDATION_CHECKLIST.md` — scenario-based pass/fail checklist
- `BUG_REPORT_TEMPLATE.md` — structured bug report template
- `tests/runtime/ish-runtime-preflight.sh` — preflight checks before a manual validation pass

Recommended workflow:

```bash
sh tests/runtime/ish-runtime-preflight.sh
```

Then work through `VALIDATION_CHECKLIST.md` and record any failures with `BUG_REPORT_TEMPLATE.md`.

## Testing

Current smoke coverage checks:

- `sh -n iOSiSH.sh`
- `bash -n shelly/shelly.sh`
- installer module syntax
- dry-run smoke execution

## Notes

- Shell ownership intentionally lives in Shelly.
- Root no longer reuses shared Zsh assets through shell symlinks.
- Optional aliases are shell-aware and opt-in.
- The package catalog and editor subsystem are now state-driven.


## Recent guided-installer package improvements

- package setup now supports a review loop before execution
- category-based plans can be edited before proceeding
- package-specific plans can be switched in-place from the planner
- exclusions are supported for recommended/category/package modes

- SSHD now supports recommended, relaxed, and custom planning modes with port validation and explicit boot/start service selection.


## Recent guided-installer polish

- Package selection now supports a richer review loop before execution.
- SSHD/service planning now supports stronger validation and profile-driven choices.
- Editor setup now supports editor profiles (`minimal`, `recommended`, `coding`) for Vim, Neovim, and Nano, plus optional lightweight plugin scaffolding for Vim/Neovim.


## Guided installer flow

The guided installer currently follows this high-level flow:

1. load or initialize `$INSTALLER_STATE_FILE` (default `./.iosish-state.env`)
2. prompt through the planning sections
3. show a review summary with edit/rerun/save-quit options
4. execute the selected steps
5. write progress to `$INSTALLER_RUNTIME_LOG` (default `./.iosish-install.log`)
6. allow resume, review, or reset on the next run if the install was interrupted

## Resetting installer state

If you want to throw away the current guided-installer plan, you can:

- choose `reset` from the guided installer when prompted, or
- remove the state file manually:

```sh
rm -f "${INSTALLER_STATE_FILE:-./.iosish-state.env}" "${INSTALLER_RUNTIME_LOG:-./.iosish-install.log}"
```

## Troubleshooting

### Installer says a module is missing
Make sure you are running `iOSiSH.sh` from the repository root and that the `installer/` directory is present.

### Installer keeps resuming an old run
Use the guided installer's `reset` option, or remove `$INSTALLER_STATE_FILE` (default `./.iosish-state.env`) manually.

### Shell setup does not match expectations
Check `~/.config/shelly/selection.env` to confirm what Shelly actually selected and wrote.

### Wrappers are installed but not found
Make sure `~/.local/bin` is in your `PATH`, or run the wrapper with its full path.

### SSHD does not start
Review the selected SSHD/service settings in the summary, inspect `$INSTALLER_RUNTIME_LOG` (default `./.iosish-install.log`), and verify the chosen port and auth settings inside iSH.
