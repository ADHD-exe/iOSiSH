# Real iSH Runtime Validation

This directory holds assets for **manual runtime validation inside iSH/Alpine**.

These files do not replace automated tests. They exist because some critical behavior in this repo must be validated inside the real target environment:

- package installation
- user creation
- shell handoff to `shelly/shelly.sh`
- ssh/sshd behavior
- OpenRC startup behavior
- resume and logging behavior

## Files

- `../../VALIDATION_CHECKLIST.md` — full runtime checklist
- `../../BUG_REPORT_TEMPLATE.md` — reusable bug report template
- `ish-runtime-preflight.sh` — lightweight preflight script to run before a manual validation pass

## Suggested flow

1. Start with a fresh or known test container.
2. Run `sh tests/runtime/ish-runtime-preflight.sh`.
3. Run through `../../VALIDATION_CHECKLIST.md`.
4. Record failures with `../../BUG_REPORT_TEMPLATE.md`.
5. Update `REPO_WORKLOG.md` with findings and next fixes.

## Notes

This validation pass should be done on real iSH. Desktop shell validation is still useful, but it is not enough for service/process/package behavior.
