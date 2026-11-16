#!/bin/sh
# spotify-run.sh — BACKEND_CMD wrapper for the Spotify Connect backend.
# usage: spotify-run.sh <plugindir> [extra librespot args...]
#
# Reads <plugindir>/spotify.conf (shell assignments of the REAL librespot
# LIBRESPOT_* environment options; see that file), pre-validates the
# integration-critical values (exit 2 on bad config), then execs the real
# librespot binary with the audio + Now Playing flags pinned:
#   --backend <alsa> [--device ...] --mixer <softvol|alsa>
#   --onevent <spotify-onevent.sh> --emit-sink-events
# Everything else reaches librespot via the exported environment. Explicit
# argv wins over env inside librespot (src/main.rs `opt_str`), so the pinned
# flags cannot be overridden from the config file — by design.
#
# Env knobs (wrapper-level, NOT librespot options):
#   SPOTIFY_BIN        librespot binary; default: first hit of
#                      /usr/bin/librespot, /opt/squeezeplay/bin/librespot,
#                      $PATH lookup. Missing binary: exit 127, clear text.
#   SPOTIFY_CONF       config path; default: <plugindir>/spotify.conf.
#                      Missing file is OK (all defaults apply).
#   SPOTIFY_ONEVENT    event hook; default: <this-dir>/spotify-onevent.sh.
#                      Missing hook: exit 2 (Now Playing would go silent).
#   SPOTIFY_ALLOW_NON_ALSA=1
#                      permit --backend pipe/subprocess (debugging only).
#                      Default: backend must be alsa, because only the ALSA
#                      backend holds the device the audio-owner claim covers.
#   SPOTIFY_DRY_RUN=1  print the resolved argv + key env instead of execing
#                      (used by standalone/tests/test-librespot.sh).
# Exit codes: 0 dry-run ok; 1 usage; 2 bad config / missing hook;
# 127 missing binary; else librespot's own code after exec.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"

die() { echo "spotify-run: $2" >&2; exit "$1"; }
[ $# -ge 1 ] || die 1 "usage: $0 <plugindir> [extra librespot args...]"
plugindir="$1"; shift

CONF="${SPOTIFY_CONF:-$plugindir/spotify.conf}"
HOOK="${SPOTIFY_ONEVENT:-$HERE/spotify-onevent.sh}"

# --- resolve the binary (target path TBD by platform install step) ---
find_bin() {
	if [ -n "${SPOTIFY_BIN:-}" ]; then
		[ -x "$SPOTIFY_BIN" ] && { printf '%s' "$SPOTIFY_BIN"; return 0; }
		return 1
	fi
	for c in /usr/bin/librespot /opt/squeezeplay/bin/librespot; do
		[ -x "$c" ] && { printf '%s' "$c"; return 0; }
	done
	command -v librespot
}
BIN="$(find_bin 2>/dev/null)" || BIN=""
[ -n "$BIN" ] && [ -x "$BIN" ] \
	|| die 127 "librespot binary not found (SPOTIFY_BIN, /usr/bin/librespot, /opt/squeezeplay/bin/librespot, PATH)"

# --- load config: LIBRESPOT_* assignments, exported for the binary ---
if [ -f "$CONF" ]; then
	# CONF path intentionally overridable; split across lines so the
	# lint directive below attaches (shellcheck 0.9.0 ignores directives
	# on multi-command source lines).
	set -a
	# shellcheck source=/dev/null
	. "$CONF"
	set +a
elif [ -n "${SPOTIFY_CONF:-}" ]; then
	die 2 "config not found: $CONF (SPOTIFY_CONF explicitly set)"
fi
# else: no config file, all defaults apply.

# --- validate integration-critical values (sets mirror src/main.rs) ---
backend="${LIBRESPOT_BACKEND:-alsa}"
case "$backend" in
	alsa) : ;;
	pipe|subprocess)
		[ "${SPOTIFY_ALLOW_NON_ALSA:-}" = "1" ] \
			|| die 2 "LIBRESPOT_BACKEND=$backend needs SPOTIFY_ALLOW_NON_ALSA=1 (only alsa holds the claimed ALSA device)" ;;
	*) die 2 "LIBRESPOT_BACKEND: want alsa (this build also knows pipe, subprocess), got '$backend'" ;;
esac

mixer="${LIBRESPOT_MIXER:-softvol}"
case "$mixer" in
	softvol|alsa) : ;;
	*) die 2 "LIBRESPOT_MIXER: want softvol|alsa, got '$mixer'" ;;
esac

if [ -n "${LIBRESPOT_BITRATE:-}" ]; then
	case "$LIBRESPOT_BITRATE" in
		96|160|320) : ;;
		*) die 2 "LIBRESPOT_BITRATE: want 96|160|320, got '$LIBRESPOT_BITRATE'" ;;
	esac
fi

if [ -n "${LIBRESPOT_FORMAT:-}" ]; then
	case "$LIBRESPOT_FORMAT" in
		F64|F32|S32|S24|S24_3|S16) : ;;
		*) die 2 "LIBRESPOT_FORMAT: want F64|F32|S32|S24|S24_3|S16, got '$LIBRESPOT_FORMAT'" ;;
	esac
fi

if [ -n "${LIBRESPOT_INITIAL_VOLUME:-}" ]; then
	case "$LIBRESPOT_INITIAL_VOLUME" in
		''|*[!0-9]*) die 2 "LIBRESPOT_INITIAL_VOLUME: want 0-100, got '$LIBRESPOT_INITIAL_VOLUME'" ;;
		*) [ "$LIBRESPOT_INITIAL_VOLUME" -ge 0 ] && [ "$LIBRESPOT_INITIAL_VOLUME" -le 100 ] \
			|| die 2 "LIBRESPOT_INITIAL_VOLUME: want 0-100, got '$LIBRESPOT_INITIAL_VOLUME'" ;;
	esac
fi

# An empty-but-set DEVICE is rejected by librespot itself (exit 1); an
# UNSET device means "backend default" and must not become --device "".
device_arg=""
if [ -n "${LIBRESPOT_DEVICE+set}" ] && [ -n "${LIBRESPOT_DEVICE:-}" ]; then
	device_arg="$LIBRESPOT_DEVICE"
elif [ -n "${LIBRESPOT_DEVICE+set}" ]; then
	die 2 "LIBRESPOT_DEVICE is set but empty (unset it for the backend default)"
fi

[ -x "$HOOK" ] || die 2 "event hook missing/not executable: $HOOK"

# --- build pinned argv (CLI beats env: these cannot be config-overridden) ---
# Word-splitting below is deliberate: device may be legitimately absent.
# shellcheck disable=SC2086
set -- "$BIN" --backend "$backend" ${device_arg:+--device "$device_arg"} \
	--mixer "$mixer" --onevent "$HOOK" --emit-sink-events "$@"

if [ "${SPOTIFY_DRY_RUN:-}" = "1" ]; then
	printf 'DRY-RUN bin=%s\n' "$BIN"
	printf 'ARG: %s\n' "$@"
	printf 'ENV: LIBRESPOT_NAME=%s\n' "${LIBRESPOT_NAME:-<default>}"
	exit 0
fi

exec "$@"
