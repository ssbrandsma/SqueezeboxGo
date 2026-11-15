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
