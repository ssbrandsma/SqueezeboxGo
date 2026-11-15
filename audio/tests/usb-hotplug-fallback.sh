#!/bin/sh
# usb-hotplug-fallback.sh — USB DAC hotplug + fallback test (WP1)
#
# Validates the output-selection policy:
#   USB DAC present → ALSA_USB_PCM=usb (USEALSADEVICE resolves to the DAC)
#   USB DAC absent  → ALSA_USB_PCM=internal (safe fallback, never silence,
#                     never a dangling hw: reference)
# plus the jive_alsa-side survival property: ENODEV on a removed device
# leads to wait-and-reopen (do_open=2), not exit (asserted statically
# against the pinned backend source when available, else SKIP).
#
# Modes: fixture-driven resolver checks run on the host
# (PROC_ASOUND=<fixture>); --monitor tails udev for real hotplug events
# (target only, needs udevadm + root or input/video group).
#
# Output: TAP. Exit 0 iff all assertions pass.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
PROC_ASOUND="${PROC_ASOUND:-/proc/asound}"
MONITOR_SECS=0
BACKEND_SRC="${BACKEND_SRC:-}"   # path to decode_alsa_backend.c for static checks
while [ $# -gt 0 ]; do
    case "$1" in
        --proc-asound) PROC_ASOUND="$2"; shift 2 ;;
        --monitor) MONITOR_SECS="${2:-10}"; shift 2 ;;
        --backend-src) BACKEND_SRC="$2"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

n=0; failed=0
ok()   { n=$((n+1)); echo "ok $n - $1"; }
nok()  { n=$((n+1)); failed=$((failed+1)); echo "not ok $n - $1"; [ -n "${2:-}" ] && echo "  $2"; }
skip() { n=$((n+1)); echo "ok $n - $1 # SKIP $2"; }

DETECT="$HERE/../alsa/capability-detect.sh"

# resolve_usb_pcm <proc-asound-dir>: prints the ALSA_USB_PCM value the
# launcher policy would choose (usb|internal). Single source of truth for
# the fallback decision, shared by tests and (via copy) image scripts.
resolve_usb_pcm() {
    usb="$(PROC_ASOUND="$1" SYS_ROOT="${SYS_ROOT:-/sys}" sh "$DETECT" --quiet 2>/dev/null \
        | sed -n 's/^usb\.card=//p' | head -1)"
    if [ -n "$usb" ] && [ "$usb" != "-1" ]; then echo "usb"; else echo "internal"; fi
}

# --- 1. resolver: DAC-present fixture → usb -------------------------------
FIX_FULL="$HERE/fixtures/proc-asound"
if [ -r "$FIX_FULL/cards" ]; then
    got="$(resolve_usb_pcm "$FIX_FULL")"
    [ "$got" = "usb" ] && ok "resolver: DAC-present fixture → usb" \
                       || nok "resolver: DAC-present fixture → usb" "got '$got'"
else
    skip "resolver: DAC-present fixture" "fixture missing"
fi

# --- 2. resolver: internal-only fixture → internal (fallback) -------------
FIX_INT="$HERE/fixtures/proc-asound-no-usb"
if [ -r "$FIX_INT/cards" ]; then
    got="$(resolve_usb_pcm "$FIX_INT")"
    [ "$got" = "internal" ] && ok "resolver: internal-only fixture → internal (fallback)" \
                             || nok "resolver: internal-only fixture → internal (fallback)" "got '$got'"
else
    skip "resolver: internal-only fixture" "fixture missing"
fi

# --- 3. resolver: live tree agrees with itself ----------------------------
if [ -r "$PROC_ASOUND/cards" ]; then
    got="$(resolve_usb_pcm "$PROC_ASOUND")"
    case "$got" in usb|internal) ok "resolver: live tree resolves to '$got'" ;;
        *) nok "resolver: live tree resolves" "got '$got'" ;; esac
else
    skip "resolver: live tree" "$PROC_ASOUND/cards unreadable"
fi

# --- 4. asound.conf aliases referenced by the resolver exist --------------
CONF="$HERE/../alsa/asound.conf"
for pcm in internal usb usb_or_internal; do
    grep -qE "^pcm\.$pcm \{" "$CONF" 2>/dev/null \
        && ok "asound.conf defines pcm.$pcm" \
        || nok "asound.conf defines pcm.$pcm"
done

# --- 5. static: backend survives ENODEV (wait-and-reopen, no exit) --------
if [ -n "$BACKEND_SRC" ] && [ -r "$BACKEND_SRC" ]; then
    grep -q 'do_open = 2' "$BACKEND_SRC" \
        && ok "backend: ENODEV → do_open=2 wait-and-reopen path present" \
        || nok "backend: ENODEV → do_open=2 wait-and-reopen path present"
    grep -q 'waiting for device %s to return' "$BACKEND_SRC" \
        && ok "backend: device-return retry loop present" \
        || nok "backend: device-return retry loop present"
    # The retry loop must sleep, not spin (power + log spam on a handheld).
    grep -q 'sleep(2)' "$BACKEND_SRC" \
        && ok "backend: retry loop sleeps between probes" \
        || nok "backend: retry loop sleeps between probes"
else
    skip "backend ENODEV survival (static)" "pass --backend-src <decode_alsa_backend.c>"
fi

# --- 6. live udev monitor (target only) ------------------------------------
if [ "$MONITOR_SECS" -gt 0 ]; then
    if command -v udevadm >/dev/null 2>&1; then
        ok "udevadm present; monitoring sound subsystem for ${MONITOR_SECS}s (plug/unplug a DAC now)"
        timeout "$MONITOR_SECS" udevadm monitor --subsystem-match=sound 2>&1 | head -20
    else
        skip "live udev monitor" "udevadm not installed"
    fi
else
    skip "live udev monitor" "pass --monitor SECS on target with a DAC to plug"
fi

echo "1..$n"
[ "$failed" -eq 0 ]
