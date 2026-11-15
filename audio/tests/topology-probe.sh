#!/bin/sh
# topology-probe.sh — ALSA topology test (WP1)
#
# Verifies the expected RG35XX H sound topology: internal H616 codec card
# present at the pinned index with a playback PCM, no capture PCM on it,
# and (optionally) a USB DAC card. Runs live against /proc/asound, or
# against fixtures with PROC_ASOUND=<dir> (host validation).
#
# Output: TAP. Exit 0 iff all assertions pass.
#
# Usage: topology-probe.sh [--proc-asound DIR] [--expect-usb 0|1]

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
PROC_ASOUND="${PROC_ASOUND:-/proc/asound}"
EXPECT_USB=0

while [ $# -gt 0 ]; do
    case "$1" in
        --proc-asound) PROC_ASOUND="$2"; shift 2 ;;
        --expect-usb) EXPECT_USB="$2"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

DETECT="$HERE/../alsa/capability-detect.sh"
n=0; failed=0
ok()   { n=$((n+1)); echo "ok $n - $1"; }
nok()  { n=$((n+1)); failed=$((failed+1)); echo "not ok $n - $1"; [ -n "${2:-}" ] && echo "  $2"; }
skip() { n=$((n+1)); echo "ok $n - $1 # SKIP $2"; }

out="$(PROC_ASOUND="$PROC_ASOUND" SYS_ROOT="${SYS_ROOT:-/sys}" sh "$DETECT" --quiet 2>/dev/null)" \
    || { nok "capability-detect runs" "exit=$?"; echo "1..$n"; exit 1; }
ok "capability-detect runs"

val() { printf '%s' "$out" | sed -n "s/^$1=//p" | head -1; }

count="$(val 'card\.count')"
case "$count" in ''|*[!0-9]*) nok "card.count is numeric" "got '$count'"; count=0 ;;
                         *) ok "card.count is numeric ($count)" ;; esac

internal="$(val 'internal\.card')"
if [ "$internal" = "-1" ] || [ -z "$internal" ]; then
    nok "internal H616 codec card present"
else
    ok "internal H616 codec card present (index $internal)"
    info="$PROC_ASOUND/card$internal/pcm0p/info"
    if [ -r "$info" ]; then
        ok "internal card has playback PCM pcm0p"
        avail="$(sed -n 's/^subdevices_avail: *//p' "$info" | head -1)"
        [ "$avail" -ge 1 ] 2>/dev/null && ok "playback subdevice available (avail=$avail)" \
            || nok "playback subdevice available" "avail='$avail' (device busy or missing)"
    else
        nok "internal card has playback PCM pcm0p" "$info unreadable"
    fi
    if [ -e "$PROC_ASOUND/card$internal/pcm0c" ]; then
        nok "internal card has no capture PCM (H616 link is playback_only)"
    else
        ok "internal card has no capture PCM (H616 link is playback_only)"
    fi
fi

usb="$(val 'usb\.card')"
if [ "$EXPECT_USB" -eq 1 ]; then
    if [ "$usb" = "-1" ] || [ -z "$usb" ]; then
        nok "USB DAC card present (expected)"
    else
        ok "USB DAC card present (index $usb)"
    fi
else
    if [ "$usb" = "-1" ] || [ -z "$usb" ]; then
        skip "USB DAC card present" "no USB DAC attached (EXPECT_USB=0)"
    else
        ok "USB DAC card present (index $usb)"
    fi
fi

# Mixer controls on the internal card (live only: needs amixer).
if [ -n "$internal" ] && [ "$internal" != "-1" ] && command -v amixer >/dev/null 2>&1; then
    ctrls="$(amixer -c "$internal" scontents 2>/dev/null | grep -E '^Simple mixer control' || true)"
    for want in "DAC Playback Volume" "Line Out Playback Volume" \
                "Line Out Playback Switch" "Speaker Playback Switch"; do
        printf '%s' "$ctrls" | grep -qF "'$want'" \
            && ok "mixer control present: $want" \
            || nok "mixer control present: $want"
    done
else
    skip "mixer controls enumerated" "needs live amixer + internal card"
fi

echo "1..$n"
[ "$failed" -eq 0 ]
