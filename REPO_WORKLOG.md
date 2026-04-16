# iOSiSH Repository Worklog

Purpose: persistent handoff log for maintainers, contributors, or future agents. Update this file whenever meaningful work is started, completed, blocked, or reprioritized so recovery after interruption is fast and accurate.

## How to use this log
- Add a new dated entry at the top of the Activity Log.
- Keep entries factual and concise.
- Record what changed, what remains, blockers, and exact next step.
- Update the checklist status when a numbered phase is completed.
- Prefer file/function names over vague descriptions.

## Current objective
Refactor the repository so `shelly/shelly.sh` is the sole owner of shell installation and shell configuration, while `iOSiSH.sh` delegates shell setup to Shelly and only resumes afterward for optional alias integration and other iSH-specific setup.

## Active checklist status
- [x] 1. `shelly/shelly.sh` — make Shelly the only shell owner (first pass complete)
- [ ] 2. `iOSiSH.sh` — remove shell ownership and delegate to Shelly
- [x] 3. `.aliases` — split into shell-aware files
- [x] 4. `.zshrc` — stop using as canonical repo-managed config
- [ ] 5. New alias install path in `iOSiSH.sh`
- [ ] 6. Documentation updates
- [ ] 7. Test updates

## Last known good state
- Archive after step 1 existed as `iOSiSH_step1_shelly_fixed.tar.gz`.
- `bash -n shelly/shelly.sh` passed after the step 1 edits.
- Step 2 had **not** started when this log entry was created.

## Known completed work
### Step 1 completed (first pass)
File changed:
- `shelly/shelly.sh`

Implemented:
- Package installation now respects selected shells instead of always installing bash, zsh, and fish.
- Added split package functions:
  - `install_common_packages()`
  - `install_zsh_packages()`
  - `install_bash_packages()`
  - `install_fish_packages()`
  - `install_selected_shell_packages()`
- Starship installation is conditional on prompt choice.
- Added shell-specific alias hook points:
  - `~/.config/iosish/aliases.zsh`
  - `~/.config/iosish/aliases.bash`
  - `~/.config/iosish/aliases.fish`
- Added Shelly state file output:
  - `~/.config/shelly/selection.env`
- Moved Zsh config generation further toward Shelly ownership.

## Known remaining work
### Immediate next step
- Modify `iOSiSH.sh` so it no longer installs or forces Zsh directly and instead delegates shell setup to `shelly/shelly.sh`.

### Still expected later
- Split current `.aliases` into shell-aware files.
- Remove `iOSiSH.sh` dependency on repo root `.zshrc`.
- Add post-Shelly alias opt-in prompt and installer path.
- Update docs and tests to match the new architecture.

## Known bugs / risks / validation gaps
- Step 1 was a first pass and still needs end-to-end validation against the full repo flow.
- `iOSiSH.sh` still likely contains overlapping shell ownership until step 2 is applied.
- Repo root `.zshrc` and current `.aliases` are still present and may conflict with the new architecture until later steps are completed.
- Tests have not yet been updated to validate the new Shelly-owned shell flow.

## Handoff notes
If work resumes after interruption, start by:
1. Reading this file.
2. Confirming current tree state matches the checklist above.
3. Continuing from step 2 unless the repo diverged.
4. Re-running syntax checks after each numbered step.

## Activity log

### 2026-04-15
#### Entry: repository handoff log added before step 2
Status:
- Work paused after step 1 by user request to add a persistent repo log.

What was being worked on:
- The checklist-driven refactor to move shell ownership fully into `shelly/shelly.sh`.

What was completed:
- Step 1 first pass in `shelly/shelly.sh`.
- Added this `REPO_WORKLOG.md` file for persistent handoff and crash recovery.

What is next:
- Start step 2 in `iOSiSH.sh`.


## Update: Step 2 completed

### Scope completed
- Added `run_shelly_setup()` to `iOSiSH.sh` so shell installation/configuration is delegated to `shelly/shelly.sh`
- Removed direct `bash`/`zsh` package installation from the main iOSiSH package list
- Removed direct main-flow Zsh ownership in `iOSiSH.sh`:
  - no forced `set_shell_in_passwd ... zsh`
  - no `write_profiles`
  - no `install_shell_frameworks`
  - no `install_repo_shell_assets`
  - no `prime_zsh_for_user`
- Added post-Shelly alias prompt flow scaffolding:
  - `read_shelly_selection_state()`
  - `prompt_for_alias_install()`
  - `install_aliases_for_shell()`
- Reduced `link_root_to_shared_assets()` to SSH-only linking so it no longer mirrors shared Zsh assets into `/root`
- Reduced `fix_permissions()` root-shell assumptions so it no longer expects shared Zsh symlinks in `/root`

### Current known limitations after step 2
- Obsolete helper functions still exist in `iOSiSH.sh` but are no longer called; they are intentionally deferred to later cleanup steps
- Alias asset installation is scaffolded, but the actual shell-specific alias files are still pending step 3
- `iOSiSH.sh` now expects Shelly to be the shell owner; behavior should be validated end-to-end after step 3 alias assets land

### Validation
- `bash -n shelly/shelly.sh` passed before this step
- `sh -n iOSiSH.sh` equivalent syntax validation via `bash -n` on the POSIX shell script content passed in this environment

### Next planned work
- Step 3: split the old shared `.aliases` into shell-aware alias files and wire the optional install flow to real assets


## 2026-04-15 — Step 3 completed
- Added `aliases/common.sh`, `aliases/aliases.zsh`, `aliases/aliases.bash`, `aliases/common.fish`, and `aliases/aliases.fish`.
- Moved optional alias content toward shell-aware assets instead of reusing the old duplicated repo-root `.aliases` file.
- Fish aliases were rewritten in fish syntax instead of copying POSIX shell aliases.
- The legacy repo-root `.aliases` file still exists for backward reference and older documentation paths; full cleanup remains for later checklist steps.
- Next planned work: step 4 cleanup, including removing obsolete Zsh-only helper code and revisiting remaining legacy docs/tests.

## Activity update

### 2026-04-15 — Step 4 completed
- Removed obsolete Zsh-only helper functions from `iOSiSH.sh` that no longer fit the delegated shell architecture.
- Kept `run_shelly_setup()` and post-Shelly alias handling as the active path.
- Confirmed `link_root_to_shared_assets()` is SSH-only and no longer mirrors shared shell assets into `/root`.
- Rewrote `README.md`, `shelly/README.md`, and `shelly/shelly-doc.md` to document the new ownership model.
- Updated `tests/smoke.sh` to assert that the removed legacy helper functions are gone and that delegated shell setup remains present.

### Remaining next steps
- Step 5 cleanup, if desired, should focus on removing or clearly labeling remaining legacy compatibility artifacts such as the repo-root `.zshrc` and `.aliases`.


## 2026-04-15 - Gap-closing pass

### Completed
- Cleaned the legacy repo-root `.aliases` file into a minimal compatibility/reference shim instead of leaving duplicated Zsh-specific alias blocks in place.
- Expanded `tests/smoke.sh` to cover the remaining checklist gaps with static contract checks for:
  - shell-selection-based package ownership in `shelly/shelly.sh`
  - conditional Starship install logic
  - Shelly selection state file fields
  - alias hook insertion points for Zsh, Bash, and Fish
  - shell-aware alias asset presence and legacy `.aliases` cleanup
  - iOSiSH shell-specific alias install destinations
- Added syntax checks for the new alias assets, with optional `zsh -n` / `fish -n` validation when those shells are available in the environment.

### Remaining caution
- The repo now matches the checklist more closely, but end-to-end runtime validation of every interactive branch still depends on a real iSH/Alpine execution environment with package/network access.

## 2026-04-15 - Phase 2A wire-in
- iOSiSH.sh now applies guided installer state to runtime before execution.
- User/root execution, Shelly execution, alias installation, and progress markers are now state-driven.
- Root-only planning is normalized to run with root as the effective primary user for the current execution path.
- Existing collect_config prompts still handle SSH hostname/port/password details until those sections are fully migrated.

## 2026-04-16 - package catalog planning upgrade
- Added a real package catalog to installer/plan.sh with category descriptions and package membership.
- Added package modes: recommended, all-categories, category, package, skip.
- Added package profile tracking in state and summary output.
- Aligned iOSiSH.sh package category membership with the new planner catalog.

- Added Phase 4 editor subsystem scaffold: state-driven editor choice, EDITOR/VISUAL env setup, starter config writers for vim/neovim/nano, and lightweight plugin-ready scaffolding.


## 2026-04-16 - Advanced SSHD / service / wrapper pass
- Added SSHD planning keys for port, root login, password auth, gateway ports, hotspot bypass, enable-at-boot, and start-now.
- Wired service state through OpenRC/sshd handling.
- Added optional iosish-docs and iosish-completions wrapper generation.
- Kept aliases optional and shell-aware under the extras path.


## 2026-04-16 - Resume/edit-summary polish and runtime logging

### Completed
- Added summary review actions: `edit`, `save-quit`, `reset`, `quit`, `proceed`.
- Added section-level edit routing during the planning summary.
- Added runtime install logging to `.iosish-install.log`.
- Added step-aware resume helpers so completed steps can be skipped on resume.
- Updated `README.md` and `installer/README.md` to reflect the guided-installer architecture.

### Notes
- The installer is still in a hybrid migration state, but planning/review/resume are materially stronger now.
- Further polish is still needed for deeper section editing and end-to-end runtime validation inside real iSH sessions.


## 2026-04-16 - Real iSH runtime validation prep

### Completed
- Added `VALIDATION_CHECKLIST.md` to guide manual runtime testing inside real iSH.
- Added `BUG_REPORT_TEMPLATE.md` for structured runtime bug triage.
- Added `tests/runtime/README.md` and `tests/runtime/ish-runtime-preflight.sh`.
- Updated `README.md` and `installer/README.md` to point to the runtime validation assets.

### Notes
- This step prepares the real-device/runtime pass, but does not replace actual execution inside iSH.
- Next work should use the checklist and bug template to drive concrete runtime fixes.


## Package UX polish update

- Added package-plan review loop
- Added package exclusions prompt and preview
- Added support for all-categories preview in both planner and executor
- Added final package preview to installer summary

- Step 3 completed: polished SSHD/service planning with validated ports, explicit SSHD profiles, separate boot/start service selection, and summary/edit support for SSHD and services.

- Step 4 completed: polished editor subsystem with setup modes, editor plan review/edit loop, stronger profile-aware config generation for vim/neovim/nano, and updated docs.


## Update: resume polish and README quick start
- Added README quick-start clone/run snippet.
- Improved resume flow with explicit resume/review/reset/quit prompt.
- Added rerun support for completed sections from the summary screen.
- Tightened dependency invalidation so edited/rerun sections mark downstream steps pending again.

## Step 6 - test expansion
- Added tests/state_smoke.sh for state init/reset/marking behavior.
- Added tests/planner_smoke.sh for package catalog, preview building, and summary output.
- Updated tests/smoke.sh to execute the new smoke tests.
- Updated README.md and installer/README.md with test/validation guidance.


- Step 7 completed: docs and UX polish. README now includes guided-installer flow, reset/troubleshooting notes, and the prompt helpers now use clearer messaging plus a more explicit section-mode explanation.
