# iOSiSH Installer Modules

This directory contains the Phase 1 scaffolding for a state-driven guided installer.

## Files

- `state.sh`  
  State storage and progress tracking helpers.

- `prompts.sh`  
  Reusable interactive prompt helpers.

- `summary.sh`  
  Functions for displaying current plan and progress.

- `plan.sh`  
  Planning-phase functions that collect installer choices and store them in state.

## State File

By default, installer state is stored in:

- `./.iosish-state.env`

You can override this path by exporting:

```sh
INSTALLER_STATE_FILE=/path/to/custom-state.env


The current planning layer also tracks system editor selection, starter editor configuration, and lightweight plugin-ready scaffolding for vim/neovim.
