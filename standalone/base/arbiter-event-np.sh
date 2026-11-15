#!/bin/sh
# arbiter-event-np.sh — fold audio-owner switch events into Now Playing.
# usage: <arbiter-output> | arbiter-event-np.sh
# Consumes the event lines audio/arbiter/audio-owner prints on stdout
# (audio/arbiter/DESIGN.md: "Now Playing publishers (Agent 5) tail these
# lines"):
#   audio-owner event=<acquired|released|reaped|timeout> source=<name> ...
# Mapping (no per-source duplicates; single authoritative state):
#   acquired source=X -> source_id=X mode=play power=true
#   released|reaped source=X -> mode=stop, but ONLY when the current
#     state still names X (a newer source may already hold the claim;
#     never clobber it with a stale stop).
#   timeout and non-event lines -> ignored (exit 0, no publish).
# jq-free like nowplaying-pub.sh (target busybox image).
set -u
BASE_DIR="$(dirname "$0")"
STATE_DIR="${NP_STATE_DIR:-/run/squeezebox}"
STATE_FILE="$STATE_DIR/nowplaying.json"

current_source() {
	[ -f "$STATE_FILE" ] || return 0
	sed -n 's/^[[:space:]]*"source_id":[[:space:]]*"\(.*\)".*$/\1/p' \
		"$STATE_FILE" | head -1
}

rc=0
while IFS= read -r line || [ -n "$line" ]; do
	case "$line" in
		'audio-owner event='*) : ;;
		*) continue ;;
	esac
	event=""; src=""
	for kv in $line; do
		case "$kv" in
			event=*) event="${kv#event=}" ;;
			source=*) src="${kv#source=}" ;;
		esac
	done
	case "$event" in
		acquired)
			[ -n "$src" ] || { echo "arbiter-event-np: acquired without source" >&2; rc=1; continue; }
			NP_STATE_DIR="$STATE_DIR" "$BASE_DIR/nowplaying-pub.sh" \
				source_id="$src" mode="play" power="true" || rc=1
			;;
		released|reaped)
			[ -n "$src" ] || { echo "arbiter-event-np: $event without source" >&2; rc=1; continue; }
			if [ "$(current_source)" = "$src" ]; then
				NP_STATE_DIR="$STATE_DIR" "$BASE_DIR/nowplaying-pub.sh" \
					mode="stop" || rc=1
			fi
			;;
		timeout) : ;; # no state change: nobody acquired
		*) echo "arbiter-event-np: unknown event: $event" >&2; rc=1 ;;
	esac
done
exit "$rc"
