#!/bin/sh
# firstboot.sh — native first-boot finalization (installed to /usr/lib/squeezebox/).
# The image ships packages UNPACKED (rootless second stage, see
# rootfs/stage-userland.sh): postinst scripts need a native arm64 CPU, so they
# run here, on the device, before ssh/wifi/squeezeplay start. Guarded by the
# stamp file AND the unit's ConditionPathExists, so re-runs are no-ops.
# Must stay dependency-free (no awk/sed): alternatives may be unconfigured.
set -eu

STAMP=/var/lib/squeezebox/firstboot-done

log() { printf 'firstboot.sh: %s\n' "$*" >&2; }

[ -f "$STAMP" ] && { log "already finalized, nothing to do"; exit 0; }

LED_SH="$(dirname "$0")/led.sh"; [ -x "$LED_SH" ] || LED_SH=""
led() { [ -n "$LED_SH" ] && "$LED_SH" "$@" || true; }
led stage firstboot

if command -v dpkg >/dev/null 2>&1; then
    if dpkg --configure -a; then
        log "dpkg --configure -a OK"
    else
        log "ERROR: dpkg --configure -a failed (see journal)"; led fail "dpkg configure"; exit 1
    fi
else
    log "no dpkg in this tree (skeleton-only staging?), skipping configure"
fi

if command -v ssh-keygen >/dev/null 2>&1; then
    if ssh-keygen -A; then
        log "ssh host keys present"
    else
        log "ERROR: ssh-keygen -A failed"; led fail "ssh-keygen"; exit 1
    fi
else
    log "no ssh-keygen in this tree, skipping host keys"
fi

mkdir -p /var/lib/squeezebox
touch "$STAMP"
log "first-boot finalization done"
exit 0
