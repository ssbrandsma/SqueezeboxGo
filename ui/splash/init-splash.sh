#!/bin/sh
# init-splash.sh — show the Squeezebox boot splash as early as DRM is up.
#
# Backend ladder:
#   1. drm_splash (this tree, raw DRM ioctls, no libdrm) + PNG
#   2. ply-image (plymouth, if the image ships it)
#   3. give up with a log line (boot continues; Jive paints later)
#
# The painter holds DRM master until killed; the platform layer kills it
# when squeezeplay takes over (see SERVICE_HOOKS.md).
#
# Usage: init-splash.sh [show|stop]
set -eu

TAG="init-splash"
BIN_DIR=${BIN_DIR:-/opt/squeezeplay/bin}
PNG=${PNG:-/usr/share/squeezebox/splash_640x480.png}
CARD=${CARD:-/dev/dri/card0}
PIDFILE=${PIDFILE:-/run/splash.pid}

log() { echo "$TAG: $*" >&2; logger -t "$TAG" "$*" 2>/dev/null || true; }

have() { command -v "$1" >/dev/null 2>&1; }

do_show() {
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        log "already running (pid $(cat "$PIDFILE"))"
        return 0
    fi
    if [ ! -f "$PNG" ]; then
        log "no splash png at $PNG"
        return 1
    fi
    if [ -x "$BIN_DIR/drm_splash" ] && [ -e "$CARD" ]; then
        "$BIN_DIR/drm_splash" --card "$CARD" --png "$PNG" &
        echo "$!" >"$PIDFILE"
        log "drm_splash pid $! on $CARD"
        return 0
    fi
    if have ply-image && [ -e "$CARD" ]; then
        ply-image "$PNG" &
        echo "$!" >"$PIDFILE"
        log "ply-image fallback pid $!"
        return 0
    fi
    log "no splash backend (want $BIN_DIR/drm_splash + $CARD)"
    return 1
}

do_stop() {
    if [ -f "$PIDFILE" ]; then
        pid=$(cat "$PIDFILE")
        if kill -TERM "$pid" 2>/dev/null; then
            log "stopped pid $pid"
        fi
        rm -f "$PIDFILE"
    fi
    return 0
}

case "${1:-show}" in
    show) do_show ;;
    stop) do_stop ;;
    *) echo "usage: $0 [show|stop]" >&2; exit 2 ;;
esac
