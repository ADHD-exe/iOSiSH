# iOSiSH Installer Modules

This directory contains the guided-installer modules for `iOSiSH.sh`.

## Files

- `state.sh`  
  State storage, progress tracking, and resume helpers.

- `prompts.sh`  
  Reusable interactive prompt helpers.

- `summary.sh`  
  Summary, review, and edit-navigation helpers for the planning phase.

- `plan.sh`  
  Planning-phase functions that collect installer choices and store them in state.

## State file

By default, installer state is stored in:

- `$INSTALLER_STATE_FILE` (default `./.iosish-state.env`)

You can override this path by exporting:

```sh
INSTALLER_STATE_FILE=/path/to/custom-state.env
```

## Runtime install log

By default, runtime execution logging is written to:

- `$INSTALLER_RUNTIME_LOG` (default `./.iosish-install.log`)

This log is intended to help with interrupted iSH sessions and handoffs.

## Current coverage

The guided-installer layer now tracks and/or plans:

- installer preferences
- user/root setup
- shell setup handoff to Shelly
- package profile/category/package selection
- editor setup
- SSH / SSHD basics
- sudo / doas selection
- service enable/start choices
- aliases, manpages, docs wrappers, and completion wrappers

## Review flow

The summary step now supports:

- `proceed`
- `edit`
- `save-quit`
- `reset`
- `quit`

## Intended execution flow

1. Initialize or load state
2. Run planning prompts
3. Show summary
4. Proceed, edit a section, save and quit, reset, or cancel
5. Execute selected steps
6. Mark steps complete for resume support

## Notes

The SSH/SSHD planning flow now stores an explicit `SSHD_PROFILE` and supports separate service enable/start selections for supported services such as `sshd`.

The repo is still in a hybrid state: a large part of execution is now state-driven, but some legacy execution logic remains in `iOSiSH.sh` and should continue being migrated toward smaller step functions.


## Runtime validation

The guided installer now ships with manual runtime-validation assets in the repo root and `tests/runtime/`.
Use them when validating the installer inside real iSH sessions, especially after changes to resume logic, package planning, sshd/service behavior, or shell handoff.


## Package planning UX

The package planner now includes a review loop with these actions:

- proceed
- edit-mode
- edit-categories
- edit-packages
- edit-exclusions

The final package preview is saved into installer state as `PACKAGE_PREVIEW`.


## Editor planning notes

The editor planner now supports:

- setup mode: `skip`, `recommended`, `customize`
- editor choice: `vim`, `neovim`, `nano`, `skip`
- editor profiles: `minimal`, `recommended`, `coding`
- optional config generation
- optional lightweight plugin scaffolding for Vim and Neovim

Relevant state keys include `EDITOR_SETUP_MODE`, `EDITOR_CHOICE`, `EDITOR_PROFILE`, `INSTALL_EDITOR_CONFIG`, and `INSTALL_EDITOR_PLUGINS`.

## Resume behavior

If an installer state file already exists, the guided installer can resume, review the saved plan, reset it, or quit. The summary screen also supports rerunning a completed section by marking that section and its dependent later steps pending again.

## Related validation assets

The guided installer also has repo-level validation helpers:

- `tests/state_smoke.sh` - validates state helper behavior such as init, set/get, reset, and step markers
- `tests/planner_smoke.sh` - validates package catalog helpers and summary output
- `tests/runtime/ish-runtime-preflight.sh` - runtime preflight to execute inside iSH before manual validation

These are intentionally lightweight smoke checks; real iSH validation should still follow `VALIDATION_CHECKLIST.md`.


## Prompt conventions

The guided installer is being normalized around these section modes where possible:

- `skip`
- `recommended`
- `customize`

Sections may still have a few legacy prompts, but new or polished sections should follow that pattern so the setup flow stays predictable.

## Resume and logging notes

- `$INSTALLER_STATE_FILE` (default `./.iosish-state.env`) stores the current installer plan and step progress.
- `$INSTALLER_RUNTIME_LOG` (default `./.iosish-install.log`) records runtime execution events.
- `save-quit` keeps the current plan so it can be resumed later.
- `reset` clears the guided plan so a new one can be created from scratch.
