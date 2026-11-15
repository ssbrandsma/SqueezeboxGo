#!/bin/sh
# squeezeplay.sh — Jive autostart launcher (installed to /usr/lib/squeezebox/).
# Reads /etc/squeezebox/system.conf, exports the interface-contracts audio env
# knobs, acquires the ALSA device via audio-owner when present, then execs the
# Agent-2 binary at $PREFIX/bin/squeezeplay. Never touches audio/ sources.
set -eu

CONF="${SYSTEM_CONF:-/etc/squeezebox/system.conf}"
PREFIX="${PREFIX:-/opt/squeezeplay}"
BIN="$PREFIX/bin/squeezeplay"
SRC_ID="jive"

log() { printf 'squeezeplay.sh: %s\n' "$*" >&2; }

[ -f "$CONF" ] && . "$CONF"

# Contract env knobs (docs/interface-contracts.md), overridable via system.conf.
export SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-kmsdrm}"
export SDL_AUDIODRIVER="${SDL_AUDIODRIVER:-alsa}"
export USEALSA_DEVICE="${USEALSA_DEVICE:-default}"
export USEALSA_SAMPLE_SIZE="${USEALSA_SAMPLE_SIZE:-}"
export USEALSA_BUFFER="${USEALSA_BUFFER:-}"
export USEALSA_PERIOD="${USEALSA_PERIOD:-}"
export USEALSA_NOMMAP="${USEALSA_NOMMAP:-0}"
export USEALSA_PCM_TIMEOUT="${USEALSA_PCM_TIMEOUT:-}"
export SQUEEZEPLAY_NOPLAYBACK="${SQUEEZEPLAY_NOPLAYBACK:-0}"
[ -n "${UTMAC:-}" ] || UTMAC="$(cat /sys/class/net/wlan0/address 2>/dev/null || true)"
export UTMAC

# Audio ownership (Agent 3 arbiter): best-effort acquire; Jive still starts so
# the UI is usable even if audio arbitration is not installed yet (WP1).
if command -v audio-owner >/dev/null 2>&1; then
    audio-owner acquire "$SRC_ID" || log "WARN: audio acquire failed, continuing"
else
    log "WARN: audio-owner not installed, continuing without arbitration"
fi

[ -x "$BIN" ] || { log "ERROR: missing $BIN (Agent 2 build not installed)"; exit 3; }
log "starting $BIN (alsa=$USEALSA_DEVICE mac=${UTMAC:-unset})"
exec "$BIN" "$@"
