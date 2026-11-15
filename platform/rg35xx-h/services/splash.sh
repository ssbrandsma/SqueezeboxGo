#!/bin/sh
# splash.sh — boot splash hook (installed to /usr/lib/squeezebox/).
# Shows the first available splash provider, always exits 0 (splash must never
# block boot). Assets/providers are owned by Agent 4 (ui/); this is the hook.
set -eu

SPLASH_DIR="${SPLASH_DIR:-/usr/share/squeezebox}"
CONF="${SYSTEM_CONF:-/etc/squeezebox/system.conf}"
[ -f "$CONF" ] && . "$CONF"

log() { printf 'splash.sh: %s\n' "$*" >&2; }
[ "${SPLASH_ENABLED:-1}" = "1" ] || { log "disabled in $CONF"; exit 0; }

# 1. Agent-4 provider script wins when present.
if [ -x "$SPLASH_DIR/splash-show" ]; then
    "$SPLASH_DIR/splash-show" "$@" || log "WARN: splash-show failed"
    exit 0
fi
# 2. Static image via fbi when available.
for img in "$SPLASH_DIR/splash.png" "$SPLASH_DIR/splash.ppm"; do
    if [ -f "$img" ] && command -v fbi >/dev/null 2>&1; then
        fbi -T 1 --noverbose --nocomments -a "$img" </dev/null >/dev/null 2>&1 || true
        log "showing $img"
        exit 0
    fi
done
# 3. Fallback: clear the console when writable so boot progress is visible.
if [ -w /dev/tty1 ]; then printf '\033c' >/dev/tty1; fi
log "no splash provider yet (WP1 hook OK)"
exit 0
