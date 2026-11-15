#!/bin/sh
# spotify-onevent.sh — librespot --onevent hook: Now Playing publisher.
# Invoked by librespot (src/player_event_handler.rs `run_program`) with the
# event described ONLY by environment variables; no argv. Every PLAYER_EVENT
# value and variable below exists verbatim in v0.8.0's player_event_handler:
# nothing here is invented. Publishes via base/nowplaying-pub.sh (schema v1).
#
# Mapping (NP schema: standalone/base/nowplaying-schema.md):
#   track_changed  -> source_id=spotify track=NAME artist=ARTISTS(joined)
#                     album=ALBUM [station=SHOW_NAME for episodes, else
#                     station cleared] duration_s=DURATION_MS/1000 position_s=0
#                     artwork_url=first COVERS line (empty clears stale)
#   playing        -> mode=play  position_s=POSITION_MS/1000
#   paused         -> mode=pause position_s=POSITION_MS/1000
#   stopped | end_of_track | unavailable -> mode=stop (anti-clobber:
#                     only when current NP source is still spotify)
#   seeked | position_correction -> position_s (anti-clobber as above)
#   volume_changed -> volume=VOLUME*100/65535 (librespot emits raw u16;
#                     percent = v/65535*100, inverse of src/main.rs:1477)
#   session_connected -> power=true
#   sink (needs --emit-sink-events, pinned on by spotify-run.sh):
#     closed -> mode=stop (anti-clobber); running|temporarily_closed ignored
#   loading | preloading | preload_next | session_disconnected |
#   session_client_changed | play_request_id_changed | auto_play_changed |
#   filter_explicit_content_changed -> ignored, exit 0 (no NP field changes;
#     transport truth arrives via playing/paused/stopped/sink-closed)
#   unknown PLAYER_EVENT -> warn, exit 0 (forward-compatible with new events)
#   empty/unset PLAYER_EVENT -> usage error, exit 1
#
# Known gaps (honest, need contract work — NOT papered over):
# - Multi-artist tracks join ARTISTS lines with ", " into the single NP
#   `artist` string (schema has one artist field).
# - Millisecond positions truncate to whole seconds (schema is seconds).
# - Shuffle true/false maps to shuffleSong/shuffleOff (no album-shuffle
#   signal exists in the event); repeat maps context/track bools to
#   repeatPlaylist/repeatSong/repeatOff.
# - The audio-owner claim is held for the whole backend lifetime (adapter
#   start/stop), NOT per track/sink-open: a transient sink close on pause
#   must never release the claim mid-session.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
PUB="$HERE/../base/nowplaying-pub.sh"
STATE_DIR="${NP_STATE_DIR:-/run/squeezebox}"
STATE_FILE="$STATE_DIR/nowplaying.json"

event="${PLAYER_EVENT:-}"
[ -n "$event" ] || { echo "spotify-onevent: PLAYER_EVENT unset (run only via librespot --onevent)" >&2; exit 1; }

is_num() { case "${1:-}" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

current_source() {
	[ -f "$STATE_FILE" ] || return 0
	sed -n 's/^[[:space:]]*"source_id":[[:space:]]*"\(.*\)".*$/\1/p' \
		"$STATE_FILE" | head -1
}

# publish_hold: we own the transport truth (track/playing/paused) — always
# stamp source_id=spotify.
publish_hold() {
	NP_STATE_DIR="$STATE_DIR" "$PUB" source_id="spotify" "$@"
}

# publish_if_ours: background updates (position/volume/stop) must not clobber
# a newer source's Now Playing (same rule as arbiter-event-np.sh).
publish_if_ours() {
	cur="$(current_source)"
	if [ -z "$cur" ] || [ "$cur" = "spotify" ]; then
		NP_STATE_DIR="$STATE_DIR" "$PUB" source_id="spotify" "$@"
	fi
}

ms_to_s() { # $1=ms -> seconds (empty string when not numeric)
	is_num "${1:-}" && printf '%s' "$((${1:-0} / 1000))" || printf ''
}

case "$event" in
	track_changed)
		artists="$(printf '%s' "${ARTISTS:-}" | awk '{if(NR>1)printf ", ";printf "%s",$0}END{if(NR)print ""}')"
		dur="$(ms_to_s "${DURATION_MS:-}")"
		cover="$(printf '%s' "${COVERS:-}" | head -n 1)"
		if [ "${ITEM_TYPE:-Track}" = "Episode" ]; then
			# Episodes: SHOW_NAME rides the remote-stream `station` path.
			# shellcheck disable=SC2086
			publish_hold track="${NAME:-}" artist="$artists" album="" \
				station="${SHOW_NAME:-}" ${dur:+duration_s="$dur"} position_s="0" \
				artwork_url="$cover"
		else
			# station="" clears a stale episode/podcast label (single state).
			# shellcheck disable=SC2086
			publish_hold track="${NAME:-}" artist="$artists" album="${ALBUM:-}" \
				station="" ${dur:+duration_s="$dur"} position_s="0" \
				artwork_url="$cover"
		fi
		;;
	playing)
		pos="$(ms_to_s "${POSITION_MS:-}")"
		# shellcheck disable=SC2086
		publish_hold mode="play" ${pos:+position_s="$pos"}
		;;
	paused)
		pos="$(ms_to_s "${POSITION_MS:-}")"
		# shellcheck disable=SC2086
		publish_hold mode="pause" ${pos:+position_s="$pos"}
		;;
	stopped|end_of_track|unavailable)
		publish_if_ours mode="stop"
		;;
	seeked|position_correction)
		pos="$(ms_to_s "${POSITION_MS:-}")"
		[ -n "$pos" ] && publish_if_ours position_s="$pos"
		;;
	volume_changed)
		if is_num "${VOLUME:-}"; then
			pct=$((VOLUME * 100 / 65535))
			[ "$pct" -gt 100 ] && pct=100
			publish_if_ours volume="$pct"
		fi
		;;
	session_connected)
		publish_if_ours power="true"
		;;
	shuffle_changed)
		case "${SHUFFLE:-}" in
			true) publish_if_ours shuffle="shuffleSong" ;;
			false) publish_if_ours shuffle="shuffleOff" ;;
		esac
		;;
	repeat_changed)
		# REPEAT=context-loop, REPEAT_TRACK=track-loop (both bools).
		case "${REPEAT_TRACK:-false},${REPEAT:-false}" in
			true,*) publish_if_ours repeat="repeatSong" ;;
			*,true) publish_if_ours repeat="repeatPlaylist" ;;
			false,false) publish_if_ours repeat="repeatOff" ;;
		esac
		;;
	sink)
		case "${SINK_STATUS:-}" in
			closed) publish_if_ours mode="stop" ;;
			running|temporarily_closed) : ;; # transport events carry this
			*) echo "spotify-onevent: unknown SINK_STATUS: ${SINK_STATUS:-}" >&2 ;;
		esac
		;;
	loading|preloading|preload_next|session_disconnected|session_client_changed|play_request_id_changed|auto_play_changed|filter_explicit_content_changed)
		: ;; # no NP field changes; see header
	*)
		echo "spotify-onevent: unknown PLAYER_EVENT '$event' (ignored)" >&2
		;;
esac
exit 0
