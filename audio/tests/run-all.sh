#!/bin/sh
# run-all.sh — run the WP1 audio test suite (host or target)
#
# Host mode (default): syntax-checks every script, runs all fixture-driven
# tests, runs the audio-owner arbiter functional tests, and runs the static
# backend checks against BACKEND_SRC when provided.
# Target mode: same, plus live ALSA tests (pass --live; runs --play opens,
# --live underrun stimulus, and the udev monitor prompt).
#
# Output: TAP streams per file + a final summary. Exit 0 iff everything passes.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
AUDIO_DIR="$(cd "$HERE/.." && pwd)"
LIVE=0
BACKEND_SRC="${BACKEND_SRC:-}"
while [ $# -gt 0 ]; do
    case "$1" in
        --live) LIVE=1; shift ;;
        --backend-src) BACKEND_SRC="$2"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done
export BACKEND_SRC

pass=0; fail=0
report() { # $1 = name, $2 = exit
    if [ "$2" -eq 0 ]; then pass=$((pass+1)); echo "# PASS: $1";
    else fail=$((fail+1)); echo "# FAIL: $1 (exit $2)"; fi
}

echo "# === 0. shell syntax (sh -n) ==="
for f in "$AUDIO_DIR/alsa/capability-detect.sh" "$AUDIO_DIR/arbiter/audio-owner" \
         "$HERE/topology-probe.sh" "$HERE/pcm-format-matrix.sh" \
         "$HERE/usb-hotplug-fallback.sh" "$HERE/underrun-recovery-test.sh" "$HERE/run-all.sh"; do
    if sh -n "$f"; then echo "# syntax ok: $f"; else echo "# SYNTAX FAIL: $f"; fail=$((fail+1)); fi
done

echo "# === 1. capability-detect (fixtures) ==="
PROC_ASOUND="$HERE/fixtures/proc-asound" SYS_ROOT=/nonexistent \
    sh "$AUDIO_DIR/alsa/capability-detect.sh" --quiet; report "capability-detect/full-fixture" $?
PROC_ASOUND="$HERE/fixtures/proc-asound-no-usb" SYS_ROOT=/nonexistent \
    sh "$AUDIO_DIR/alsa/capability-detect.sh" --quiet >/dev/null; report "capability-detect/no-usb-fixture" $?

echo "# === 2. topology-probe (fixtures) ==="
sh "$HERE/topology-probe.sh" --proc-asound "$HERE/fixtures/proc-asound" --expect-usb 1; report "topology/full-fixture" $?
sh "$HERE/topology-probe.sh" --proc-asound "$HERE/fixtures/proc-asound-no-usb" --expect-usb 0; report "topology/no-usb-fixture" $?

echo "# === 3. pcm-format-matrix (fixtures) ==="
sh "$HERE/pcm-format-matrix.sh" --proc-asound "$HERE/fixtures/proc-asound"; report "pcm-matrix/full-fixture" $?

echo "# === 4. usb-hotplug-fallback (fixtures + static) ==="
sh "$HERE/usb-hotplug-fallback.sh"; report "usb-hotplug" $?

echo "# === 5. underrun-recovery (static) ==="
sh "$HERE/underrun-recovery-test.sh"; report "underrun/static" $?

echo "# === 6. audio-owner arbiter functional ==="
ODIR="$(mktemp -d)"; export AUDIO_OWNER_DIR="$ODIR"
OWN="$AUDIO_DIR/arbiter/audio-owner"
# 6a. acquire → status held → second acquire refused → release → free.
sh "$OWN" acquire squeezeplay >/dev/null || { echo "# FAIL: arbiter acquire"; fail=$((fail+1)); }
sh "$OWN" status | grep -q '^held source=squeezeplay' \
    && echo "# arbiter: held after acquire" || { echo "# FAIL: arbiter status"; fail=$((fail+1)); }
if sh "$OWN" acquire standalone >/dev/null 2>&1; then echo "# FAIL: arbiter double-acquire allowed"; fail=$((fail+1));
else echo "# arbiter: second acquire refused (single holder)"; fi
sh "$OWN" release squeezeplay >/dev/null || { echo "# FAIL: arbiter release"; fail=$((fail+1)); }
sh "$OWN" status >/dev/null 2>&1; [ $? -eq 3 ] \
    && echo "# arbiter: free after release" || { echo "# FAIL: arbiter not free"; fail=$((fail+1)); }
# 6b. crash-safety: claim for a pid, kill -9 it, next acquire must reap.
sleep 30 & victim=$!
sh "$OWN" acquire crashtest --pid "$victim" >/dev/null || { echo "# FAIL: arbiter victim acquire"; fail=$((fail+1)); }
kill -9 "$victim"; wait "$victim" 2>/dev/null || true
reap="$(sh "$OWN" acquire newcomer 2>&1)"
printf '%s' "$reap" | grep -q 'event=reaped source=crashtest' \
    && echo "# arbiter: crashed holder reaped on next acquire" \
    || { echo "# FAIL: arbiter reap: $reap"; fail=$((fail+1)); }
sh "$OWN" release newcomer >/dev/null
# 6c. hold mode propagates exit code and releases.
sh "$OWN" hold holdertest -- sh -c 'exit 7'; rc=$?
[ "$rc" -eq 7 ] && echo "# arbiter: hold propagates exit code" \
                || { echo "# FAIL: arbiter hold rc=$rc"; fail=$((fail+1)); }
sh "$OWN" status >/dev/null 2>&1; [ $? -eq 3 ] \
    && echo "# arbiter: free after hold exits" || { echo "# FAIL: arbiter hold leak"; fail=$((fail+1)); }
# 6d. wait: free now → returns 0 immediately.
sh "$OWN" wait --timeout 2 >/dev/null 2>&1 \
    && echo "# arbiter: wait-on-free returns 0" || { echo "# FAIL: arbiter wait"; fail=$((fail+1)); }
# 6e. WP2: status reaps stale records (stale-lock cleanup) and removes them.
printf 'source=stale1 pid=999999 starttime=1 since=1\n' > "$ODIR/owner"
reapout="$(sh "$OWN" status 2>&1)"; rc=$?
[ "$rc" -eq 3 ] && [ ! -f "$ODIR/owner" ] && printf '%s' "$reapout" | grep -q 'event=reaped source=stale1' \
    && echo "# arbiter: status reaps stale record" \
    || { echo "# FAIL: arbiter status reap (rc=$rc): $reapout"; fail=$((fail+1)); }
# 6f. WP2: torn/unparseable record is reaped loudly, never silently dropped.
printf 'TORN{{{\n' > "$ODIR/owner"
reapout="$(sh "$OWN" acquire newcomer2 2>&1)"; rc=$?
printf '%s' "$reapout" | grep -q 'event=reaped source=?' && [ "$rc" -eq 0 ] \
    && echo "# arbiter: torn record reaped loudly on acquire" \
    || { echo "# FAIL: arbiter torn reap (rc=$rc): $reapout"; fail=$((fail+1)); }
sh "$OWN" release newcomer2 >/dev/null
# 6g. WP2: source-name charset enforced; force-release event goes to stdout.
sh "$OWN" acquire 'bad name' >/dev/null 2>&1; [ $? -eq 2 ] \
    && echo "# arbiter: bad source name rejected (rc=2)" \
    || { echo "# FAIL: arbiter bad-name not rejected"; fail=$((fail+1)); }
sh "$OWN" acquire forceme >/dev/null
fout="$(sh "$OWN" force-release 2>/dev/null)"
printf '%s' "$fout" | grep -q 'event=released source=forceme .*note=force-release' \
    && echo "# arbiter: force-release event on stdout" \
    || { echo "# FAIL: arbiter force-release event: $fout"; fail=$((fail+1)); }
# 6h. WP2: status creates no state; hold forwards TERM to the child.
ODIR2="$(mktemp -d)/nostate"; AUDIO_OWNER_DIR="$ODIR2" sh "$OWN" status >/dev/null 2>&1
[ $? -eq 3 ] && [ ! -e "$ODIR2" ] \
    && echo "# arbiter: status creates no state" \
    || { echo "# FAIL: arbiter status side effect"; fail=$((fail+1)); }
rmdir "$(dirname "$ODIR2")" 2>/dev/null || true
if command -v timeout >/dev/null 2>&1; then
    timeout -s TERM 3 sh "$OWN" hold sigtest -- sleep 30 >/dev/null 2>&1
    sleep 1
    sh "$OWN" status >/dev/null 2>&1; [ $? -eq 3 ] \
        && echo "# arbiter: hold+TERM leaves device free" \
        || { echo "# FAIL: arbiter hold TERM leak"; fail=$((fail+1)); }
else
    echo "# arbiter: hold+TERM test skipped (no timeout)"
fi
# 6i. Codified WP1 edge cases: release-by-non-holder rc=5, wait-on-held rc=4.
sh "$OWN" acquire holder9 >/dev/null
sh "$OWN" release intruder >/dev/null 2>&1; [ $? -eq 5 ] \
    && echo "# arbiter: release-by-non-holder refused (rc=5)" \
    || { echo "# FAIL: arbiter non-holder release"; fail=$((fail+1)); }
sh "$OWN" wait --timeout 1 >/dev/null 2>&1; [ $? -eq 4 ] \
    && echo "# arbiter: wait-on-held times out (rc=4)" \
    || { echo "# FAIL: arbiter wait timeout"; fail=$((fail+1)); }
sh "$OWN" release holder9 >/dev/null
rm -rf "$ODIR"

if [ "$LIVE" -eq 1 ]; then
    echo "# === 7. LIVE (target) ==="
    sh "$HERE/topology-probe.sh"; report "topology/live" $?
    sh "$HERE/pcm-format-matrix.sh" --play; report "pcm-matrix/live" $?
    sh "$HERE/underrun-recovery-test.sh" --live; report "underrun/live" $?
    echo "# (run usb-hotplug-fallback.sh --monitor 15 with a DAC to exercise hotplug)"
fi

echo "# ---------------- summary: $pass passed suites, $fail failed ----------------"
[ "$fail" -eq 0 ]
