#!/bin/sh
# audio-owner-client.sh — client for the Agent 3 audio arbiter.
# Contract (docs/interface-contracts.md): exactly one active playback
# source holds the ALSA device; `audio-owner acquire|release <source>`;
# crash releases automatically; Now Playing update on every switch.
# This client shells out to the arbiter binary; it implements no
# arbitration itself. The passthrough surface below matches the REAL
# audio/arbiter/audio-owner CLI exactly (WP2 wired against main @
# 96217b5, read-only): acquire/release/status/wait. Arbiter exit codes
# pass through unchanged (0 ok, 1 held-by-other, 2 env error, 3 free
# on status, 4 wait timeout, 5 not-holder on release).
set -u
AUDIO_OWNER_BIN="${AUDIO_OWNER_BIN:-/usr/sbin/audio-owner}"

die() { echo "audio-owner-client: $*" >&2; exit 1; }

[ -x "$AUDIO_OWNER_BIN" ] || die "arbiter not found: $AUDIO_OWNER_BIN"

case "${1:-}" in
	acquire)
		# acquire <source> [--pid PID]: the claim PID must be the
		# long-lived ALSA holder (audio/arbiter/DESIGN.md "Claim
		# rule"); adapter.sh passes the backend pid. Omitting --pid
		# claims as our parent (the caller's shell).
		case "$#" in
			2) set -- acquire "$2" ;;
			4) [ "$3" = "--pid" ] || die "usage: $0 acquire <source> [--pid PID]"
				shift # drop "acquire"; "$@" is now <source> --pid <pid>
				set -- acquire "$@" ;;
			*) die "usage: $0 acquire <source> [--pid PID]" ;;
		esac
		exec "$AUDIO_OWNER_BIN" "$@"
		;;
	release)
		[ $# -eq 2 ] || die "usage: $0 release <source>"
		exec "$AUDIO_OWNER_BIN" release "$2"
		;;
	status)
		[ $# -eq 1 ] || die "usage: $0 status"
		exec "$AUDIO_OWNER_BIN" status
		;;
	wait)
		# wait [--timeout SECS]: exit 0 once free, 4 on timeout.
		shift
		exec "$AUDIO_OWNER_BIN" wait "$@"
		;;
	*) die "usage: $0 acquire <source> [--pid PID] | release <source> | status | wait [--timeout SECS]" ;;
esac
