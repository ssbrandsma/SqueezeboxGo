#!/bin/sh
# test-arbiter-integration.sh — WP2 standalone integration tests.
# Runs the standalone adapters against the REAL audio arbiter CLI
# (audio/arbiter/audio-owner from main, read-only) on the host.
# No root needed: arbiter dir, pid dir, and Now Playing state all live
# under a mktemp dir. TAP-ish output; exit 1 on any failure.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
BASE="$ROOT/standalone/base"
SERVICES="$ROOT/standalone/integration/services"
ARBITER="$ROOT/audio/arbiter/audio-owner"

pass=0; fail=0; n=0
ok() { n=$((n+1)); pass=$((pass+1)); echo "ok $n - $1"; }
bad() { n=$((n+1)); fail=$((fail+1)); echo "not ok $n - $1"; [ -n "${2:-}" ] && echo "  $2"; }

[ -x "$ARBITER" ] || { echo "missing real arbiter: $ARBITER" >&2; exit 1; }
command -v flock >/dev/null 2>&1 || { echo "need flock(1)" >&2; exit 1; }

T="$(mktemp -d /tmp/wp2-sa-int.XXXXXX)"
export AUDIO_OWNER_DIR="$T/arb" NP_STATE_DIR="$T/np" PID_DIR="$T/pid"
export AUDIO_OWNER_BIN="$ARBITER"
CLIENT="$BASE/audio-owner-client.sh"
ADAPTER="$BASE/adapter.sh"
PUB="$BASE/nowplaying-pub.sh"
EVNP="$BASE/arbiter-event-np.sh"

cleanup() {
	for p in "$PID_DIR"/*.pid; do
		[ -f "$p" ] || continue
		kill -9 "$(cat "$p" 2>/dev/null)" 2>/dev/null || true
	done
	rm -rf "$T"
}
trap cleanup EXIT

mkdemo() { # $1=name -> plugindir with /bin/sleep backend
	mkdir -p "$T/plug-$1"
	printf 'BACKEND_CMD="/bin/sleep 120"\n' > "$T/plug-$1/backend.conf"
	echo "$T/plug-$1"
}
state_key() { # $1=key -> raw JSON value from nowplaying.json
	python3 -c "import json;print(json.dumps(json.load(open('$NP_STATE_DIR/nowplaying.json')).get('$1')))"
}

# --- 1. client passthrough vs real arbiter: status/acquire/release codes ---
out="$($CLIENT status 2>&1)"; rc=$?
[ "$rc" -eq 3 ] && [ "$out" = "free" ] \
	&& ok "client status on fresh dir: free, exit 3" \
	|| bad "client status fresh" "rc=$rc out=$out"

$CLIENT acquire demo >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "client acquire demo: exit 0" || bad "client acquire" "rc=$rc"

out="$($CLIENT status 2>&1)"; rc=$?
case "$out" in 'held source=demo pid='*' since='*) s=0;; *) s=1;; esac
[ "$rc" -eq 0 ] && [ "$s" -eq 0 ] \
	&& ok "client status held: $out" \
	|| bad "client status held" "rc=$rc out=$out"

$CLIENT acquire other >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && ok "client acquire while held: exit 1" || bad "client acquire held" "rc=$rc"

$CLIENT release other >/dev/null 2>&1; rc=$?
[ "$rc" -eq 5 ] && ok "client release by non-holder: exit 5" || bad "client release non-holder" "rc=$rc"

$CLIENT release demo >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "client release holder: exit 0" || bad "client release" "rc=$rc"

$CLIENT wait --timeout 1 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "client wait on free: exit 0" || bad "client wait" "rc=$rc"

$CLIENT bogus-cmd >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && ok "client usage error: exit 1" || bad "client usage" "rc=$rc"

# --- 2. adapter start binds the claim to the backend pid ---
DEMO_DIR="$(mkdemo demo)"
$ADAPTER demo start "$DEMO_DIR" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "adapter start demo: exit 0" || bad "adapter start" "rc=$rc"

be_pid="$(cat "$PID_DIR/demo.pid" 2>/dev/null)" || be_pid=""
if [ -n "$be_pid" ] && kill -0 "$be_pid" 2>/dev/null; then
	ok "adapter start: backend alive (pid $be_pid)"
else
	bad "adapter start: backend alive" "pidfile=$(cat "$PID_DIR/demo.pid" 2>/dev/null || echo MISSING)"
fi
owner_line="$($CLIENT status 2>/dev/null)" || true
case "$owner_line" in "held source=demo pid=$be_pid since="*) ok "arbiter claim pid == backend pid";; *)
	bad "arbiter claim pid == backend pid" "status=[$owner_line] be_pid=[$be_pid]";; esac

[ "$(state_key source_id)" = '"demo"' ] && [ "$(state_key mode)" = '"play"' ] \
	&& ok "adapter start published source_id=demo mode=play" \
	|| bad "adapter start publish" "source=$(state_key source_id) mode=$(state_key mode)"

# --- 3. second source loses cleanly: no survivor, first keeps claim ---
DEMO2_DIR="$(mkdemo demo2)"
$ADAPTER demo2 start "$DEMO2_DIR" >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok "adapter start demo2 while held: fails (rc=$rc)" \
	|| bad "adapter start demo2 while held" "rc=$rc (must fail)"
if [ -f "$PID_DIR/demo2.pid" ] && kill -0 "$(cat "$PID_DIR/demo2.pid")" 2>/dev/null; then
	bad "loser backend stopped" "demo2 pid $(cat "$PID_DIR/demo2.pid") survives"
else
	ok "loser backend stopped, no survivor"
fi
owner_line="$($CLIENT status 2>/dev/null)" || true
case "$owner_line" in "held source=demo pid=$be_pid since="*) ok "first source keeps claim";; *)
	bad "first source keeps claim" "status=[$owner_line]";; esac

# --- 4. adapter stop releases claim + publishes stop ---
$ADAPTER demo stop "$DEMO_DIR" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "adapter stop demo: exit 0" || bad "adapter stop" "rc=$rc"
out="$($CLIENT status 2>&1)"; rc=$?
[ "$rc" -eq 3 ] && [ "$out" = "free" ] \
	&& ok "arbiter free after stop" \
	|| bad "arbiter free after stop" "rc=$rc out=$out"
[ "$(state_key mode)" = '"stop"' ] \
	&& ok "adapter stop published mode=stop" \
	|| bad "adapter stop publish" "mode=$(state_key mode)"

# --- 5. crash recovery: SIGKILLed backend reaps on next acquire ---
$ADAPTER demo start "$DEMO_DIR" >/dev/null 2>&1
be_pid="$(cat "$PID_DIR/demo.pid")"
kill -9 "$be_pid"
sleep 1
out="$($CLIENT acquire crashed2 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "acquire after SIGKILL: exit 0 (reaped)" || bad "acquire after SIGKILL" "rc=$rc out=$out"
case "$out" in *event=reaped*source=demo*) ok "reap event names crashed source";; *)
	bad "reap event names crashed source" "out=$out";; esac
$CLIENT release crashed2 >/dev/null 2>&1
$ADAPTER demo stop "$DEMO_DIR" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "adapter stop after crash: exit 0" || bad "adapter stop after crash" "rc=$rc"

# --- 6. all 8 shipped stubs stay honest: fail fast, exit 3, no claim ---
count=0
for svc in music proxy qobuz radio spotify squeezeplay vpn webui; do
	d="$SERVICES/$svc"
	[ -f "$d/backend.conf" ] || { bad "stub $svc has backend.conf" "missing"; continue; }
	$ADAPTER "$svc" start "$d" >/tmp/wp2-stub-err.txt 2>&1; rc=$?
	out="$($CLIENT status 2>&1)"; src_rc=$?
	if [ "$rc" -ne 0 ] && [ "$src_rc" -eq 3 ] && [ "$out" = "free" ]; then
		ok "stub $svc: adapter start fails, arbiter untouched"
	else
		bad "stub $svc honest" "rc=$rc arbiter=[$out]"
	fi
	# Unquoted $BACKEND_CMD on purpose: same word-split invocation the
	# adapter uses (reasons contain parens/semicolons; eval would break).
	direct_out="$(BASE_DIR="$BASE" sh -c '. "$1/backend.conf"; $BACKEND_CMD' _ "$d" 2>&1)"; direct_rc=$?
	case "$direct_out" in UNIMPLEMENTED*) u=0;; *) u=1;; esac
	if [ "$direct_rc" -eq 3 ] && [ "$u" -eq 0 ]; then
		ok "stub $svc backend: exit 3 + UNIMPLEMENTED text"
	else
		bad "stub $svc backend" "rc=$direct_rc out=$direct_out"
	fi
	count=$((count+1))
done
[ "$count" -eq 8 ] && ok "8 stubs covered" || bad "8 stubs covered" "count=$count"

# --- 7. arbiter event consumer ---
printf '%s\n' 'audio-owner event=acquired source=radio pid=111 ts=1' | $EVNP >/dev/null 2>&1
[ "$(state_key source_id)" = '"radio"' ] && [ "$(state_key mode)" = '"play"' ] \
	&& ok "event acquired -> source_id+mode=play" \
	|| bad "event acquired" "source=$(state_key source_id) mode=$(state_key mode)"
printf '%s\n' 'audio-owner event=released source=spotify pid=222 ts=2' | $EVNP >/dev/null 2>&1
[ "$(state_key source_id)" = '"radio"' ] && [ "$(state_key mode)" = '"play"' ] \
	&& ok "event released for other source: no clobber" \
	|| bad "event released other" "source=$(state_key source_id) mode=$(state_key mode)"
printf '%s\n' 'audio-owner event=reaped source=radio pid=111 ts=3' | $EVNP >/dev/null 2>&1
[ "$(state_key mode)" = '"stop"' ] \
	&& ok "event reaped for current source -> mode=stop" \
	|| bad "event reaped current" "mode=$(state_key mode)"
printf '%s\n' 'audio-owner event=timeout source=? pid=? ts=4' 'not an event line' | $EVNP >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ "$(state_key mode)" = '"stop"' ] \
	&& ok "timeout/garbage lines ignored" \
	|| bad "timeout/garbage" "rc=$rc mode=$(state_key mode)"

# --- 8. publisher smoke: full state validates as JSON ---
$PUB source_id=sq track='Comma, "Quote" \ Backslash' volume=80 power=true >/dev/null
python3 -c "import json;d=json.load(open('$NP_STATE_DIR/nowplaying.json'));assert d['track']=='Comma, \"Quote\" \\\\ Backslash',repr(d['track'])" \
	&& ok "publisher JSON round-trips adversarial values" \
	|| bad "publisher JSON round-trip"

echo "---"
echo "pass=$pass fail=$fail total=$n"
[ "$fail" -eq 0 ]
