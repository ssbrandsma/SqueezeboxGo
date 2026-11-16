#!/bin/sh
# led.sh — boot-progress status-LED control (installed to /usr/lib/squeezebox/).
# Usage: led.sh stage <firstboot|splash|wifi|squeezeplay> | ok | fail [msg]
#
# Drives green:status (PI11) through /sys/class/leds. Signatures (docs/hardware.md):
#   firstboot   fast blink 100/100 ms | splash 1 Hz 500/500 | wifi slow 1000/250
#   squeezeplay solid on | ok solid on | fail strobe 50/50 + stderr log.
# Kernel heartbeat (DT default-trigger) runs until the first stage call.
#
# Never blocks boot: missing/unwritable sysfs -> warn on stderr, exit 0.
# Only a usage error exits 2 (programmer error; covered by tests).
# Dependency-free (no awk/sed/grep): safe for firstboot.sh's environment.
# Test hook: LED_SYSFS overrides /sys/class/leds (see services/tests/test-led.sh).
set -eu

LED_SYSFS="${LED_SYSFS:-/sys/class/leds}"

log() { printf 'led.sh: %s\n' "$*" >&2; }

led_dir() { # prefer green:status, fall back to any *status* entry
    if [ -d "$LED_SYSFS/green:status" ]; then
        printf '%s' "$LED_SYSFS/green:status"
    else
        for d in "$LED_SYSFS/"*status*/; do
            [ -d "$d" ] && { printf '%s' "${d%/}"; return 0; }
        done
        return 1
    fi
}

write() { # $1=file $2=value — best effort, never fatal
    if [ -w "$1" ]; then printf '%s' "$2" >"$1" 2>/dev/null || \
        log "WARN: cannot write $1";
    else log "WARN: $1 not writable, LED unchanged"; fi
}

set_timer() { # $1=on_ms $2=off_ms
    d="$1"; on="$2"; off="$3"
    write "$d/trigger" "timer"
    write "$d/delay_on" "$on"
    write "$d/delay_off" "$off"
}

set_solid() { # $1=dir
    write "$1/trigger" "none"
    write "$1/brightness" "1"
}

cmd="${1:-}"
case "$cmd" in
    stage|ok|fail) ;;
    *) echo "usage: $0 stage <firstboot|splash|wifi|squeezeplay> | ok | fail [msg]" >&2; exit 2 ;;
esac

D="$(led_dir 2>/dev/null)" || { log "WARN: no status LED in $LED_SYSFS, skipping"; exit 0; }

case "$cmd" in
    stage)
        case "${2:-}" in
            firstboot) set_timer "$D" 100 100 ;;
            splash) set_timer "$D" 500 500 ;;
            wifi) set_timer "$D" 1000 250 ;;
            squeezeplay) set_solid "$D" ;;
            *) echo "usage: $0 stage <firstboot|splash|wifi|squeezeplay>" >&2; exit 2 ;;
        esac
        ;;
    ok) set_solid "$D" ;;
    fail)
        [ -n "${2:-}" ] && log "FAIL: $2"
        set_timer "$D" 50 50
        ;;
esac
exit 0
