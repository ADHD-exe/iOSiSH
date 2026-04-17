# iOSiSH Guided Installer Validation Checklist

Use this checklist while testing **inside real iSH on iPhone/iPad**. The goal is to validate behavior in the actual target environment, not just syntax in a desktop shell.

## Test environment info
- Date:
- Device:
- iOS version:
- iSH version:
- Alpine version:
- Fresh container or existing:
- Network status:
- Repo commit/archive tested:

## 1. Baseline sanity checks
### 1.1 Script/module syntax
- [ ] `sh -n iOSiSH.sh` passes
- [ ] `sh -n installer/state.sh` passes
- [ ] `sh -n installer/prompts.sh` passes
- [ ] `sh -n installer/summary.sh` passes
- [ ] `sh -n installer/plan.sh` passes
- [ ] `bash -n shelly/shelly.sh` passes

### 1.2 File presence
- [ ] `installer/` directory exists
- [ ] `.iosish-state.env.example` exists
- [ ] `REPO_WORKLOG.md` exists
- [ ] runtime log path is created when installer runs
- [ ] docs/wrapper paths are created correctly if selected

## 2. Fresh guided installer flow
### 2.1 Planning starts correctly
- [ ] installer launches the guided planning phase
- [ ] no missing module errors
- [ ] installer state file is created at the active `$INSTALLER_STATE_FILE` path
- [ ] defaults initialize correctly
- [ ] planning prompts appear in expected order

### 2.2 Summary screen
- [ ] summary prints planned values clearly
- [ ] progress summary prints correctly
- [ ] `proceed` works
- [ ] `quit` works
- [ ] `save-quit` works
- [ ] `reset` works
- [ ] `edit` works

## 3. Root-only flow
### 3.1 Planning
- [ ] choosing root-only does not require a primary username
- [ ] root-only state is written correctly
- [ ] summary reflects root-only mode correctly

### 3.2 Execution
- [ ] installer does not break when no non-root user is configured
- [ ] root shell setup still works
- [ ] aliases/extras do not assume a non-root user exists
- [ ] editor config path works for root-only
- [ ] wrappers install correctly for root-only

## 4. Root + primary user flow
### 4.1 Planning
- [ ] primary username prompt works
- [ ] chosen primary user is saved into state
- [ ] primary home is derived correctly
- [ ] summary reflects root + user mode correctly

### 4.2 Execution
- [ ] user creation/config path works
- [ ] permissions are set correctly
- [ ] shell setup applies to the selected user
- [ ] user-level files land in the correct home directory

## 5. Shelly integration
### 5.1 Zsh-only
- [ ] Shelly runs when selected
- [ ] only Zsh-related packages are installed
- [ ] `.zshrc` is created by Shelly
- [ ] alias hook exists in `.zshrc`
- [ ] completion behavior is correct for Zsh
- [ ] `selection.env` is written
- [ ] installer imports Shelly state correctly

### 5.2 Bash-only
- [ ] only Bash-related packages are installed
- [ ] `.bashrc` is created/updated
- [ ] alias hook exists in `.bashrc`
- [ ] Bash completion behavior is correct
- [ ] state import works

### 5.3 Fish-only
- [ ] only Fish-related packages are installed
- [ ] Fish config is created/updated
- [ ] Fish alias hook exists
- [ ] Fish config syntax remains valid
- [ ] state import works

### 5.4 All shells
- [ ] all selected shell packages install correctly
- [ ] default root shell selection works
- [ ] default user shell selection works
- [ ] alias/completion handling behaves correctly across multiple configured shells

## 6. Package planner validation
### 6.1 Recommended mode
- [ ] recommended mode builds a package plan
- [ ] packages install without obvious omissions
- [ ] duplicates are not installed twice

### 6.2 All-categories mode
- [ ] all categories are recognized
- [ ] combined package list builds correctly
- [ ] package install does not fail due to bad category merge

### 6.3 Category mode
- [ ] category list input is accepted
- [ ] invalid categories are handled cleanly
- [ ] selected categories map to expected packages
- [ ] summary reflects category selection correctly

### 6.4 Package mode
- [ ] specific package input is accepted
- [ ] packages install correctly
- [ ] invalid package names fail cleanly
- [ ] summary reflects explicit package selection correctly

### 6.5 Exclusion behavior
- [ ] excluded packages are respected if implemented
- [ ] exclusions do not break category/recommended mode

## 7. Editor subsystem validation
### 7.1 Vim
- [ ] selecting Vim sets `EDITOR` correctly
- [ ] selecting Vim sets `VISUAL` correctly
- [ ] `.vimrc` is created when requested
- [ ] Vim config content is valid enough to load
- [ ] plugin-ready scaffolding is created if selected

### 7.2 Neovim
- [ ] selecting Neovim sets `EDITOR` correctly
- [ ] `~/.config/nvim/init.lua` is created
- [ ] config loads without obvious syntax errors
- [ ] plugin-ready scaffolding is created if selected

### 7.3 Nano
- [ ] selecting Nano sets `EDITOR` correctly
- [ ] `.nanorc` is created when requested
- [ ] config content is sane

### 7.4 Editor profile behavior
- [ ] editor profile is saved in state
- [ ] summary reflects editor profile correctly
- [ ] editing the editor section resets dependent steps if needed

## 8. SSH client validation
- [ ] SSH client setup only runs when selected
- [ ] no SSH client prompts appear if disabled
- [ ] SSH client config/snippets are generated correctly if selected
- [ ] state reflects SSH client choice correctly
- [ ] generated SSH config works if host info is provided

## 9. SSHD validation
### 9.1 Basic
- [ ] SSHD only installs/configures when selected
- [ ] config file is written or updated correctly
- [ ] no SSHD actions occur if disabled

### 9.2 Customization
- [ ] custom port works if selected
- [ ] password auth setting is applied correctly
- [ ] root login setting is applied correctly
- [ ] gateway ports setting is applied correctly
- [ ] hotspot bypass behavior is applied correctly if selected

### 9.3 Runtime
- [ ] sshd starts correctly when requested
- [ ] sshd does not start when not requested
- [ ] OpenRC enable-at-boot setting is respected
- [ ] you can actually connect to sshd from another device if applicable

## 10. Privilege tools validation
### 10.1 Sudo
- [ ] sudo installs only when selected
- [ ] sudo config is valid
- [ ] sudo works for the intended user

### 10.2 Doas
- [ ] doas installs only when selected
- [ ] doas config is valid
- [ ] doas works for the intended user

### 10.3 Combination cases
- [ ] sudo only works correctly
- [ ] doas only works correctly
- [ ] both works correctly
- [ ] neither does not break the install flow

## 11. OpenRC and services validation
### 11.1 Service enablement
- [ ] selected services are enabled at boot
- [ ] unselected services are not enabled
- [ ] service state is reflected in installer state if tracked

### 11.2 Start-now behavior
- [ ] selected services start immediately when requested
- [ ] unselected services do not start unexpectedly

### 11.3 Service prompts
- [ ] service choices are clear
- [ ] summary reflects service selections correctly
- [ ] edit-summary flow can revise service choices cleanly

## 12. Extras validation
### 12.1 Aliases
- [ ] aliases install only when selected
- [ ] correct shell-specific alias file is installed
- [ ] Bash gets Bash aliases
- [ ] Zsh gets Zsh aliases
- [ ] Fish gets Fish aliases
- [ ] alias hooks load the installed aliases correctly

### 12.2 Completions
- [ ] completions install only when selected
- [ ] Bash gets Bash completion package/config if selected
- [ ] Zsh gets Zsh completion package/config if selected
- [ ] completions wrapper is created if selected

### 12.3 Docs / manpages
- [ ] manpages install only when selected
- [ ] docs wrapper is created when selected
- [ ] docs wrapper is executable
- [ ] docs wrapper behaves sensibly when called

## 13. Resume / interruption validation
### 13.1 Mid-install interruption
- [ ] stop the installer mid-run
- [ ] restart it
- [ ] installer detects existing state
- [ ] installer offers resume behavior
- [ ] already completed steps are skipped correctly
- [ ] incomplete/failed step resumes correctly

### 13.2 Edit after partial completion
- [ ] edit a previously planned section
- [ ] dependent later steps are marked dirty/reset if appropriate
- [ ] installer does not wrongly skip steps that need rerunning

### 13.3 Reset
- [ ] reset clears state correctly
- [ ] reset allows a clean new install plan

## 14. Logging validation
### 14.1 Runtime log
- [ ] runtime log file is created
- [ ] step start events are logged
- [ ] step completion events are logged
- [ ] failures are logged
- [ ] resume/reset actions are logged

### 14.2 Repo work log
- [ ] `REPO_WORKLOG.md` still makes sense after current changes
- [ ] handoff information remains useful

## 15. Documentation validation
### 15.1 README
- [ ] README matches current guided installer behavior
- [ ] README describes state-driven flow
- [ ] README mentions resume/logging behavior
- [ ] README explains Shelly ownership clearly

### 15.2 Installer docs
- [ ] `installer/README.md` matches actual module behavior
- [ ] `.iosish-state.env.example` matches current keys, defaults, and documented optional flags
- [ ] wrapper docs are accurate if present

## 16. Final pass/fail summary
### Passed
- [ ] Fresh install
- [ ] Root-only
- [ ] Root + user
- [ ] Zsh path
- [ ] Bash path
- [ ] Fish path
- [ ] Package planner
- [ ] Editor setup
- [ ] SSH client
- [ ] SSHD
- [ ] sudo/doas
- [ ] OpenRC/services
- [ ] Extras
- [ ] Resume/reset
- [ ] Logging
- [ ] Docs

### Failed / needs fixes
- [ ] List issue 1
- [ ] List issue 2
- [ ] List issue 3
