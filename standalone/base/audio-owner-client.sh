#!/bin/sh
# audio-owner-client.sh — client for the Agent 3 audio arbiter.
# Contract (docs/interface-contracts.md): exactly one active playback
# source holds the ALSA device; `audio-owner acquire|release <source>`;
# crash releases automatically; Now Playing update on every switch.
# This client shells out to the arbiter binary; it implements no
# arbitration itself. The arbiter daemon is Agent 3's deliverable.
set -u
AUDIO_OWNER_BIN="${AUDIO_OWNER_BIN:-/usr/sbin/audio-owner}"

die() { echo "audio-owner-client: $*" >&2; exit 1; }

case "${1:-}" in
	acquire|release)
		[ $# -eq 2 ] || die "usage: $0 acquire|release <source>"
		[ -x "$AUDIO_OWNER_BIN" ] || die "arbiter not found: $AUDIO_OWNER_BIN"
		exec "$AUDIO_OWNER_BIN" "$1" "$2"
		;;
	status)
		[ -x "$AUDIO_OWNER_BIN" ] || die "arbiter not found: $AUDIO_OWNER_BIN"
		exec "$AUDIO_OWNER_BIN" status
		;;
	*) die "usage: $0 acquire|release <source> | status" ;;
esac
