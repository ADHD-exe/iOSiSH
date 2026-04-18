#!/bin/sh
# Lightweight preflight checks for a manual iSH validation pass.

set -eu

say() { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }

say '== iOSiSH runtime preflight =='

for path in \
    ./iOSiSH.sh \
    ./installer/state.sh \
    ./installer/prompts.sh \
    ./installer/summary.sh \
    ./installer/plan.sh \
    ./shells/shells.sh \
    ./VALIDATION_CHECKLIST.md \
    ./BUG_REPORT_TEMPLATE.md
 do
    if [ -e "$path" ]; then
        say "OK   $path"
    else
        warn "missing: $path"
    fi
done

if command -v sh >/dev/null 2>&1; then
    sh -n ./iOSiSH.sh && say 'OK   sh -n iOSiSH.sh' || warn 'syntax check failed: iOSiSH.sh'
fi

if command -v bash >/dev/null 2>&1; then
    bash -n ./shells/shells.sh && say 'OK   bash -n shells/shells.sh' || warn 'syntax check failed: shells/shells.sh'
else
    warn 'bash not present; native shell setup syntax check skipped'
fi

if command -v apk >/dev/null 2>&1; then
    say "INFO Alpine release: $(cat /etc/alpine-release 2>/dev/null || printf 'unknown')"
else
    warn 'apk not present; this does not look like Alpine/iSH'
fi

say 'Next:'
say '  1. Fill in VALIDATION_CHECKLIST.md while testing.'
say '  2. Record bugs with BUG_REPORT_TEMPLATE.md.'
say '  3. Keep the active installer runtime log and state file after failures.'
