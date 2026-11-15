#!/bin/sh
# test-librespot.sh — WP3 Spotify Connect backend tests (host).
# Covers the REAL librespot v0.8.0 binary (when LIBRESPOT_BIN points at a
# runnable build — native smoke build, no premium credentials needed):
# --help/--version/--backend prohes, config parse + validation via
# spotify-run.sh dry-run, adapter start/stop lifecycle against the REAL
# audio-owner arbiter, and --onevent -> Now Playing translation unit tests
# (binary not needed for those). TAP-ish output; exit 1 on any failure.
# Binary-dependent sections SKIP (not fail) when LIBRESPOT_BIN is unset or
# not executable, so the file stays green on hosts without the build.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
BASE="$ROOT/standalone/base"
INT="$ROOT/standalone/integration"
SERVICES="$INT/services"
ARBITER="$ROOT/audio/arbiter/audio-owner"
RUN="$INT/spotify-run.sh"
HOOK="$INT/spotify-onevent.sh"
ADAPTER="$BASE/adapter.sh"
CLIENT="$BASE/audio-owner-client.sh"
PUB="$BASE/nowplaying-pub.sh"

pass=0; fail=0; skip=0; n=0
ok() { n=$((n+1)); pass=$((pass+1)); echo "ok $n - $1"; }
bad() { n=$((n+1)); fail=$((fail+1)); echo "not ok $n - $1"; [ -n "${2:-}" ] && echo "  $2"; }
sk() { n=$((n+1)); skip=$((skip+1)); echo "ok $n - $1 # SKIP $2"; }

[ -x "$ARBITER" ] || { echo "missing real arbiter: $ARBITER" >&2; exit 1; }
command -v flock >/dev/null 2>&1 || { echo "need flock(1)" >&2; exit 1; }

T="$(mktemp -d /tmp/wp3-librespot.XXXXXX)"
export AUDIO_OWNER_DIR="$T/arb" NP_STATE_DIR="$T/np" PID_DIR="$T/pid"
export AUDIO_OWNER_BIN="$ARBITER"
export SPOTIFY_ONEVENT="$HOOK"

cleanup() {
	for p in "$PID_DIR"/*.pid; do
		[ -f "$p" ] || continue
		kill -9 "$(cat "$p" 2>/dev/null)" 2>/dev/null || true
	done
	rm -rf "$T"
}
trap cleanup EXIT

state_key() { # $1=key -> raw JSON value from nowplaying.json
	python3 -c "import json;print(json.dumps(json.load(open('$NP_STATE_DIR/nowplaying.json')).get('$1')))"
}
mkconf() { # $1=name $2...=lines -> plugindir with spotify.conf; echoes dir
	d="$T/plug-$1"; mkdir -p "$d"; : > "$d/spotify.conf"
	shift; for line in "$@"; do printf '%s\n' "$line" >> "$d/spotify.conf"; done
	echo "$d"
}

HAVE_BIN=0
if [ -n "${LIBRESPOT_BIN:-}" ] && [ -x "${LIBRESPOT_BIN:-}" ]; then HAVE_BIN=1; fi

# --- 1. binary probes (need the real build) ---
if [ "$HAVE_BIN" -eq 1 ]; then
	out="$("$LIBRESPOT_BIN" --version 2>&1)"; rc=$?
	case "$out" in 'librespot 0.8.0 d36f9f1 '*) v=0;; *) v=1;; esac
	[ "$rc" -eq 0 ] && [ "$v" -eq 0 ] \
		&& ok "librespot --version: 0.8.0 d36f9f1" \
		|| bad "librespot --version" "rc=$rc out=$out"

	"$LIBRESPOT_BIN" --help >/dev/null 2>&1; rc=$?
	[ "$rc" -eq 0 ] && ok "--help exits 0" || bad "--help" "rc=$rc"
	for flag in --backend --device --mixer --onevent --emit-sink-events --name --bitrate --format; do
		"$LIBRESPOT_BIN" --help 2>/dev/null | grep -q -- "$flag" \
			&& ok "--help documents $flag" \
			|| bad "--help documents $flag" "missing"
	done

	out="$("$LIBRESPOT_BIN" --backend '?' 2>&1)"; rc=$?
	case "$out" in *'- alsa (default)'*) b=0;; *) b=1;; esac
	[ "$rc" -eq 0 ] && [ "$b" -eq 0 ] \
		&& ok "--backend '?': alsa (default)" \
		|| bad "--backend '?'" "rc=$rc out=$out"

	"$LIBRESPOT_BIN" --bogus-flag >/dev/null 2>&1; rc=$?
	[ "$rc" -eq 1 ] && ok "bad flag exits 1" || bad "bad flag" "rc=$rc"
else
	sk "binary probes" "LIBRESPOT_BIN unset or not executable"
fi

# --- 2. config parse + dry-run argv (hermetic: /bin/echo as the binary) ---
D="$(mkconf dry 'LIBRESPOT_NAME="Dry Box"' 'LIBRESPOT_BITRATE="320"' 'LIBRESPOT_MIXER="softvol"')"
out="$(SPOTIFY_BIN=/bin/echo SPOTIFY_DRY_RUN=1 "$RUN" "$D" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "dry-run exits 0" || bad "dry-run" "rc=$rc out=$out"
case "$out" in *'ARG: --backend'*'ARG: alsa'*'ARG: --mixer'*'ARG: softvol'*'ARG: --onevent'*'ARG: --emit-sink-events'*)
	ok "dry-run pins backend/mixer/onevent/sink-events";; *)
	bad "dry-run pinned argv" "$out";; esac
case "$out" in *'ENV: LIBRESPOT_NAME=Dry Box'*) ok "dry-run reads LIBRESPOT_NAME from conf";; *)
	bad "dry-run conf name" "$out";; esac
case "$out" in *'ARG: --device'*) bad "dry-run omits --device when unset" "$out";; *)
	ok "dry-run omits --device when unset";; esac

D="$(mkconf dev 'LIBRESPOT_DEVICE="hw:9,9"')"
out="$(SPOTIFY_BIN=/bin/echo SPOTIFY_DRY_RUN=1 "$RUN" "$D" 2>&1)"
case "$out" in *'ARG: --device'*'ARG: hw:9,9'*) ok "dry-run passes --device hw:9,9";; *)
	bad "dry-run device" "$out";; esac

D="$(mkconf mix 'LIBRESPOT_MIXER="alsa"' 'LIBRESPOT_ALSA_MIXER_CONTROL="Master"')"
out="$(SPOTIFY_BIN=/bin/echo SPOTIFY_DRY_RUN=1 "$RUN" "$D" 2>&1)"; rc=$?
	[ "$rc" -eq 0 ] && case "$out" in *'ARG: alsa'*) ok "dry-run accepts mixer=alsa";; *)
		bad "dry-run mixer alsa" "$out";; esac \
	|| bad "dry-run mixer alsa" "rc=$rc out=$out"

D="$(mkconf fmt 'LIBRESPOT_FORMAT="S24_3"' 'LIBRESPOT_INITIAL_VOLUME="37"' 'LIBRESPOT_NAME="N"')"
SPOTIFY_BIN=/bin/echo SPOTIFY_DRY_RUN=1 "$RUN" "$D" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "dry-run accepts format S24_3 + volume 37" || bad "dry-run fmt/vol" "rc=$rc"

D="$(mkconf nofile)"; rm "$D/spotify.conf"
SPOTIFY_BIN=/bin/echo SPOTIFY_DRY_RUN=1 "$RUN" "$D" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "missing conf file: all defaults, exit 0" || bad "missing conf" "rc=$rc"

# --- 3. validation failures: exit 2 with a naming message ---
t2() { # $1=desc $2...=conf lines; expects exit 2
	desc="$1"; shift
	D="$(mkconf bad "$@")"
	out="$(SPOTIFY_BIN=/bin/echo SPOTIFY_DRY_RUN=1 "$RUN" "$D" 2>&1)"; rc=$?
	[ "$rc" -eq 2 ] && ok "$desc (exit 2)" || bad "$desc" "rc=$rc out=$out"
}
t2 "bad bitrate rejected" 'LIBRESPOT_BITRATE="999"'
t2 "bad format rejected" 'LIBRESPOT_FORMAT="S8"'
t2 "bad mixer rejected" 'LIBRESPOT_MIXER="pulse"'
t2 "bad backend rejected" 'LIBRESPOT_BACKEND="jack"'
t2 "volume 101 rejected" 'LIBRESPOT_INITIAL_VOLUME="101"'
t2 "volume -1 rejected" 'LIBRESPOT_INITIAL_VOLUME="-1"'
t2 "volume text rejected" 'LIBRESPOT_INITIAL_VOLUME="loud"'
t2 "empty device rejected" 'LIBRESPOT_DEVICE=""'
D="$(mkconf pipebe 'LIBRESPOT_BACKEND="pipe"')"
SPOTIFY_BIN=/bin/echo SPOTIFY_DRY_RUN=1 "$RUN" "$D" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "pipe backend needs escape hatch (exit 2)" || bad "pipe guard" "rc=$rc"
SPOTIFY_BIN=/bin/echo SPOTIFY_DRY_RUN=1 SPOTIFY_ALLOW_NON_ALSA=1 "$RUN" "$D" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "SPOTIFY_ALLOW_NON_ALSA=1 permits pipe" || bad "pipe hatch" "rc=$rc"

D="$(mkconf binhack)"
SPOTIFY_BIN=/nonexistent/librespot "$RUN" "$D" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 127 ] && ok "missing binary exits 127" || bad "missing binary" "rc=$rc"
SPOTIFY_BIN=/bin/echo SPOTIFY_ONEVENT=/nonexistent/hook SPOTIFY_DRY_RUN=1 "$RUN" "$D" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "missing hook exits 2" || bad "missing hook" "rc=$rc"
SPOTIFY_BIN=/bin/echo SPOTIFY_CONF=/nonexistent.conf "$RUN" "$D" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "explicit missing SPOTIFY_CONF exits 2" || bad "explicit conf" "rc=$rc"

# --- 4. onevent -> Now Playing translation (no binary needed) ---
ev() { # $1=desc, rest VAR=val; runs hook, expects exit 0
	desc="$1"; shift
	env -i PATH="$PATH" NP_STATE_DIR="$NP_STATE_DIR" "$@" "$HOOK" >/dev/null 2>&1; rc=$?
	[ "$rc" -eq 0 ] && ok "$desc" || bad "$desc" "rc=$rc"
}
rm -f "$NP_STATE_DIR/nowplaying.json"

ev "track_changed (Track)" PLAYER_EVENT=track_changed ITEM_TYPE=Track \
	NAME="Yellow Submarine" ARTISTS="The Beatles" ALBUM="Revolver" DURATION_MS=185000
[ "$(state_key track)" = '"Yellow Submarine"' ] && [ "$(state_key artist)" = '"The Beatles"' ] \
	&& [ "$(state_key album)" = '"Revolver"' ] && [ "$(state_key duration_s)" = '185' ] \
	&& [ "$(state_key position_s)" = '0' ] && [ "$(state_key source_id)" = '"spotify"' ] \
	&& ok "track_changed maps track/artist/album/duration" \
	|| bad "track_changed map" "track=$(state_key track) artist=$(state_key artist) album=$(state_key album) dur=$(state_key duration_s)"

ev "track_changed joins multi-artists" PLAYER_EVENT=track_changed ITEM_TYPE=Track \
	NAME="Duet" 'ARTISTS=Alice
Bob' ALBUM="X" DURATION_MS=60000
[ "$(state_key artist)" = '"Alice, Bob"' ] \
	&& ok "multi-artist joins with comma" \
	|| bad "multi-artist join" "artist=$(state_key artist)"

ev "track_changed (Episode)" PLAYER_EVENT=track_changed ITEM_TYPE=Episode \
	NAME="Ep 42" SHOW_NAME="Cool Cast" DURATION_MS=3600000
[ "$(state_key station)" = '"Cool Cast"' ] && [ "$(state_key duration_s)" = '3600' ] \
	&& ok "episode maps SHOW_NAME to station" \
	|| bad "episode map" "station=$(state_key station) dur=$(state_key duration_s)"

ev "track clears stale station" PLAYER_EVENT=track_changed ITEM_TYPE=Track \
	NAME="Next" ARTISTS="X" ALBUM="Y" DURATION_MS=60000
[ "$(state_key station)" = 'null' ] \
	&& ok "track clears stale episode station" \
	|| bad "station clear" "station=$(state_key station)"

ev "playing" PLAYER_EVENT=playing POSITION_MS=90000
[ "$(state_key mode)" = '"play"' ] && [ "$(state_key position_s)" = '90' ] \
	&& ok "playing -> mode=play position=90" \
	|| bad "playing map" "mode=$(state_key mode) pos=$(state_key position_s)"

ev "paused" PLAYER_EVENT=paused POSITION_MS=95000
[ "$(state_key mode)" = '"pause"' ] && [ "$(state_key position_s)" = '95' ] \
	&& ok "paused -> mode=pause position=95" \
	|| bad "paused map" "mode=$(state_key mode) pos=$(state_key position_s)"

ev "seeked" PLAYER_EVENT=seeked POSITION_MS=120000
[ "$(state_key position_s)" = '120' ] && [ "$(state_key mode)" = '"pause"' ] \
	&& ok "seeked updates position only" \
	|| bad "seeked map" "pos=$(state_key position_s) mode=$(state_key mode)"

ev "volume_changed max" PLAYER_EVENT=volume_changed VOLUME=65535
[ "$(state_key volume)" = '100' ] && ok "volume 65535 -> 100" \
	|| bad "volume max" "vol=$(state_key volume)"
ev "volume_changed zero" PLAYER_EVENT=volume_changed VOLUME=0
[ "$(state_key volume)" = '0' ] && ok "volume 0 -> 0" \
	|| bad "volume zero" "vol=$(state_key volume)"
ev "volume_changed mid" PLAYER_EVENT=volume_changed VOLUME=32768
[ "$(state_key volume)" = '50' ] && ok "volume 32768 -> 50" \
	|| bad "volume mid" "vol=$(state_key volume)"

ev "session_connected" PLAYER_EVENT=session_connected
[ "$(state_key power)" = 'true' ] && ok "session_connected -> power=true" \
	|| bad "session_connected" "power=$(state_key power)"

ev "shuffle on" PLAYER_EVENT=shuffle_changed SHUFFLE=true
[ "$(state_key shuffle)" = '"shuffleSong"' ] && ok "shuffle true -> shuffleSong" \
	|| bad "shuffle on" "shuffle=$(state_key shuffle)"
ev "repeat track" PLAYER_EVENT=repeat_changed REPEAT=false REPEAT_TRACK=true
[ "$(state_key repeat)" = '"repeatSong"' ] && ok "repeat track -> repeatSong" \
	|| bad "repeat track" "repeat=$(state_key repeat)"
ev "repeat context" PLAYER_EVENT=repeat_changed REPEAT=true REPEAT_TRACK=false
[ "$(state_key repeat)" = '"repeatPlaylist"' ] && ok "repeat context -> repeatPlaylist" \
	|| bad "repeat context" "repeat=$(state_key repeat)"
ev "repeat off" PLAYER_EVENT=repeat_changed REPEAT=false REPEAT_TRACK=false
[ "$(state_key repeat)" = '"repeatOff"' ] && ok "repeat off -> repeatOff" \
	|| bad "repeat off" "repeat=$(state_key repeat)"

# publisher boundary-key regression (WP3 fix in nowplaying-pub.sh: wrapped
# STR_KEYS/RAW_KEYS lines made shuffle/format/rate_hz/depth_bits unmatchable)
"$PUB" shuffle=shuffleSong format=FLAC rate_hz=44100 depth_bits=16 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ "$(state_key shuffle)" = '"shuffleSong"' ] \
	&& [ "$(state_key format)" = '"FLAC"' ] && [ "$(state_key rate_hz)" = '44100' ] \
	&& [ "$(state_key depth_bits)" = '16' ] \
	&& ok "publisher accepts shuffle/format/rate_hz/depth_bits" \
	|| bad "publisher boundary keys" "rc=$rc"

ev "stopped" PLAYER_EVENT=stopped
[ "$(state_key mode)" = '"stop"' ] && ok "stopped -> mode=stop" \
	|| bad "stopped map" "mode=$(state_key mode)"

# anti-clobber: background stop/position must not touch another source's NP
"$PUB" source_id=radio mode=play >/dev/null
ev "sink closed (other source)" PLAYER_EVENT=sink SINK_STATUS=closed
[ "$(state_key source_id)" = '"radio"' ] && [ "$(state_key mode)" = '"play"' ] \
	&& ok "sink closed ignores other source's NP" \
	|| bad "sink anti-clobber" "src=$(state_key source_id) mode=$(state_key mode)"
ev "seeked (other source)" PLAYER_EVENT=seeked POSITION_MS=1000
[ "$(state_key source_id)" = '"radio"' ] \
	&& ok "seeked ignores other source's NP" \
	|| bad "seeked anti-clobber" "src=$(state_key source_id)"
"$PUB" source_id=spotify mode=play >/dev/null
ev "sink closed (own source)" PLAYER_EVENT=sink SINK_STATUS=closed
[ "$(state_key mode)" = '"stop"' ] && ok "sink closed stops own NP" \
	|| bad "sink own stop" "mode=$(state_key mode)"
"$PUB" source_id=spotify mode=pause >/dev/null
ev "sink running ignored" PLAYER_EVENT=sink SINK_STATUS=running
[ "$(state_key mode)" = '"pause"' ] && ok "sink running leaves NP alone" \
	|| bad "sink running" "mode=$(state_key mode)"
ev "sink temp-closed ignored" PLAYER_EVENT=sink SINK_STATUS=temporarily_closed
[ "$(state_key mode)" = '"pause"' ] && ok "sink temporarily_closed leaves NP alone" \
	|| bad "sink temp" "mode=$(state_key mode)"

# ignored events: exit 0 and change no NP field (modulo `updated` stamp)
before_nupd="$(grep -v '"updated"' "$NP_STATE_DIR/nowplaying.json")"
for e in loading preloading preload_next session_disconnected session_client_changed \
		play_request_id_changed auto_play_changed filter_explicit_content_changed; do
	env -i PATH="$PATH" NP_STATE_DIR="$NP_STATE_DIR" PLAYER_EVENT="$e" "$HOOK" >/dev/null 2>&1; rc=$?
	after_nupd="$(grep -v '"updated"' "$NP_STATE_DIR/nowplaying.json")"
	if [ "$rc" -eq 0 ] && [ "$before_nupd" = "$after_nupd" ]; then
		ok "ignored event $e: exit 0, no NP change"
	else
		bad "ignored event $e" "rc=$rc"
	fi
done

env -i PATH="$PATH" NP_STATE_DIR="$NP_STATE_DIR" PLAYER_EVENT=some_future_event "$HOOK" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "unknown event exits 0 (forward-compat)" || bad "unknown event" "rc=$rc"
env -i PATH="$PATH" NP_STATE_DIR="$NP_STATE_DIR" "$HOOK" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && ok "unset PLAYER_EVENT exits 1" || bad "unset event" "rc=$rc"

# --- 5. lifecycle vs the REAL arbiter with the REAL binary ---
if [ "$HAVE_BIN" -eq 1 ]; then
	SPOT="$T/plug-spotify"; mkdir -p "$SPOT"
	# The shipped backend.conf references $BASE_DIR/$plugindir from the
	# adapter; for the test plugindir, write the equivalent explicit command.
	printf 'BACKEND_CMD="%s/../integration/spotify-run.sh %s"\n' "$BASE" "$SPOT" > "$SPOT/backend.conf"
	printf '%s\n' 'LIBRESPOT_NAME="WP3 Test"' 'LIBRESPOT_BITRATE="96"' > "$SPOT/spotify.conf"
	export SPOTIFY_BIN="$LIBRESPOT_BIN"
	# libasound for the smoke build (host has no system ALSA); harmless otherwise
	[ -n "${WP3_ALSA_LIBDIR:-}" ] && export LD_LIBRARY_PATH="${WP3_ALSA_LIBDIR}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

	"$ADAPTER" spotify start "$SPOT" >/dev/null 2>&1; rc=$?
	[ "$rc" -eq 0 ] && ok "adapter start spotify (real binary): exit 0" \
		|| bad "adapter start spotify" "rc=$rc"
	be_pid="$(cat "$PID_DIR/spotify.pid" 2>/dev/null)" || be_pid=""
	if [ -n "$be_pid" ] && kill -0 "$be_pid" 2>/dev/null; then
		ok "spotify backend alive (pid $be_pid)"
	else
		bad "spotify backend alive" "pidfile=$(cat "$PID_DIR/spotify.pid" 2>/dev/null || echo MISSING)"
	fi
	owner_line="$("$CLIENT" status 2>/dev/null)" || true
	case "$owner_line" in "held source=spotify pid=$be_pid since="*) ok "claim binds librespot pid";; *)
		bad "claim binds librespot pid" "status=[$owner_line] be_pid=[$be_pid]";; esac
	[ "$(state_key source_id)" = '"spotify"' ] \
		&& ok "start published source_id=spotify" \
		|| bad "start publish" "source=$(state_key source_id)"

	# real binary really running? --version via the supervised pid's exe
	if [ -n "$be_pid" ] && exe="$(readlink "/proc/$be_pid/exe" 2>/dev/null)"; then
		[ "$exe" = "$LIBRESPOT_BIN" ] && ok "supervised pid is the librespot binary" \
			|| bad "supervised exe" "exe=$exe want=$LIBRESPOT_BIN"
	else
		bad "supervised exe" "no /proc/$be_pid/exe"
	fi

	# second source loses while spotify holds; spotify keeps the claim
	D2="$T/plug-demo2"; mkdir -p "$D2"; printf 'BACKEND_CMD="/bin/sleep 120"\n' > "$D2/backend.conf"
	"$ADAPTER" demo2 start "$D2" >/dev/null 2>&1; rc=$?
	[ "$rc" -ne 0 ] && ok "demo2 start while spotify holds: fails" \
		|| bad "demo2 contention" "rc=$rc (must fail)"
	if [ -f "$PID_DIR/demo2.pid" ] && kill -0 "$(cat "$PID_DIR/demo2.pid")" 2>/dev/null; then
		bad "loser backend stopped" "demo2 survives"
	else
		ok "loser backend stopped, no survivor"
	fi

	"$ADAPTER" spotify stop "$SPOT" >/dev/null 2>&1; rc=$?
	[ "$rc" -eq 0 ] && ok "adapter stop spotify: exit 0" || bad "adapter stop" "rc=$rc"
	out="$("$CLIENT" status 2>&1)"; rc=$?
	[ "$rc" -eq 3 ] && [ "$out" = "free" ] \
		&& ok "arbiter free after spotify stop" \
		|| bad "arbiter free after stop" "rc=$rc out=$out"
	[ "$(state_key mode)" = '"stop"' ] \
		&& ok "stop published mode=stop" \
		|| bad "stop publish" "mode=$(state_key mode)"
	kill -0 "$be_pid" 2>/dev/null \
		&& bad "librespot reaped after stop" "pid $be_pid survives" \
		|| ok "librespot reaped after stop"
else
	sk "lifecycle vs real arbiter" "LIBRESPOT_BIN unset or not executable"
fi

echo "---"
echo "pass=$pass fail=$fail skip=$skip total=$n"
[ "$fail" -eq 0 ]
