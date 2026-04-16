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
    ./shelly/shelly.sh \
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
    bash -n ./shelly/shelly.sh && say 'OK   bash -n shelly/shelly.sh' || warn 'syntax check failed: shelly/shelly.sh'
else
    warn 'bash not present; Shelly syntax check skipped'
fi

if command -v apk >/dev/null 2>&1; then
    say "INFO Alpine release: $(cat /etc/alpine-release 2>/dev/null || printf 'unknown')"
else
    warn 'apk not present; this does not look like Alpine/iSH'
fi

say 'Next:'
say '  1. Fill in VALIDATION_CHECKLIST.md while testing.'
say '  2. Record bugs with BUG_REPORT_TEMPLATE.md.'
say '  3. Keep .iosish-install.log and .iosish-state.env after failures.'
