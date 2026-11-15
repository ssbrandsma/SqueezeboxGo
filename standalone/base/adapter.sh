#!/bin/sh
# adapter.sh — portable standalone service adapter.
# One adapter instance wraps one playback source and implements the four
# integration-contract duties (docs/interface-contracts.md "Standalone
# integration"): service start/stop, playback acquire/release via
# audio-owner, Now Playing publish, web-route registration.
#
# usage: adapter.sh <source-id> start|stop|status|publish <plugindir>
# The plugindir holds the source-specific backend:
#   backend.conf  — BACKEND_CMD="..." (argv to supervise, REQUIRED)
#   routes.conf   — "METHOD path handler" lines (optional, see web-routes.sh)
# No Baby/Fab4 code is referenced here; device deps live behind
# standalone/integration/ only.
set -u
BASE_DIR="$(dirname "$0")"

die() { echo "adapter[$1]: $2" >&2; exit 1; }
[ $# -ge 3 ] || { echo "usage: $0 <source-id> start|stop|status|publish <plugindir>" >&2; exit 1; }
src="$1"; op="$2"; plugindir="$3"
[ -f "$plugindir/backend.conf" ] || die "$src" "no backend.conf in $plugindir"
# shellcheck disable=SC1090
. "$plugindir/backend.conf"
[ -n "${BACKEND_CMD:-}" ] || die "$src" "BACKEND_CMD empty in $plugindir/backend.conf"
shift 3 # drop <source-id> <op> <plugindir>; "$@" is now op args (kv pairs for publish)

PID_DIR="${PID_DIR:-/run/squeezebox}"
pidfile="$PID_DIR/$src.pid"

case "$op" in
	start)
		# Start the backend FIRST, then bind the audio claim to the
		# backend PID (the long-lived ALSA holder). Claiming as this
		# short-lived adapter shell would go stale the moment start
		# returns (audio/arbiter/DESIGN.md "Claim rule"), letting a
		# second source double-hold the device. On acquire failure
		# the just-started backend is stopped again, so the loser
		# never plays. UNIMPLEMENTED backends exit 3 here, before
		# any arbiter or Now Playing state is touched.
		# shellcheck disable=SC2086
		"$BASE_DIR/service.sh" start "$src" "$pidfile" $BACKEND_CMD \
			|| die "$src" "backend failed to start"
		be_pid="$(cat "$pidfile" 2>/dev/null)" || be_pid=""
		case "$be_pid" in ''|*[!0-9]*)
			"$BASE_DIR/service.sh" stop "$src" "$pidfile" || true
			die "$src" "no backend pid in $pidfile" ;;
		esac
		if ! "$BASE_DIR/audio-owner-client.sh" acquire "$src" --pid "$be_pid"; then
			"$BASE_DIR/service.sh" stop "$src" "$pidfile" || true
			die "$src" "audio acquire failed"
		fi
		NP_STATE_DIR="${NP_STATE_DIR:-/run/squeezebox}" \
			"$BASE_DIR/nowplaying-pub.sh" source_id="$src" mode="play" power="true"
		;;
	stop)
		"$BASE_DIR/service.sh" stop "$src" "$pidfile" || true
		"$BASE_DIR/audio-owner-client.sh" release "$src" || true
		NP_STATE_DIR="${NP_STATE_DIR:-/run/squeezebox}" \
			"$BASE_DIR/nowplaying-pub.sh" source_id="$src" mode="stop"
		;;
	status)
		"$BASE_DIR/service.sh" status "$src" "$pidfile"
		;;
	publish)
		NP_STATE_DIR="${NP_STATE_DIR:-/run/squeezebox}" \
			"$BASE_DIR/nowplaying-pub.sh" source_id="$src" "$@"
		;;
	*) die "$src" "unknown op: $op (want start|stop|status|publish)" ;;
esac
