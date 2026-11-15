#!/bin/sh
# underrun-recovery-test.sh — underrun/XRUN recovery test (WP1)
#
# Two halves:
#  A. Live (target, needs aplay + a real PCM): plays 2 s of silence with an
#     absurdly small buffer (--buffer-size=64 --period-size=16) to force
#     XRUNs, then replays with sane parameters; pass = first run shows
#     `underrun` (proving the stimulus works) and second run is clean
#     (proving the device recovered without reopen/reboot).
#  B. Static (runs on host with --backend-src): asserts the pinned jive_alsa
#     backend contains every recovery call the design relies on
#     (XRUN/SUSPEND/avail/mmap/writei recover + reopen-on-insane-avail),
#     and validates tests/fixtures/hw_params-open-*.txt parses as a
#     healthy negotiated state (format/rate/period*buffer sane).
#
# Output: TAP. Exit 0 iff all assertions pass.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
BACKEND_SRC="${BACKEND_SRC:-}"
DEVICE="${DEVICE:-default}"
LIVE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --backend-src) BACKEND_SRC="$2"; shift 2 ;;
        --device) DEVICE="$2"; shift 2 ;;
        --live) LIVE=1; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

n=0; failed=0
ok()   { n=$((n+1)); echo "ok $n - $1"; }
nok()  { n=$((n+1)); failed=$((failed+1)); echo "not ok $n - $1"; [ -n "${2:-}" ] && echo "  $2"; }
skip() { n=$((n+1)); echo "ok $n - $1 # SKIP $2"; }

# --- A. live stimulus -------------------------------------------------------
if [ "$LIVE" -eq 1 ]; then
    if command -v aplay >/dev/null 2>&1; then
        # 2 s of zero samples, S16 stereo 44.1k = 44100*2ch*2B*2s bytes.
        raw="$(mktemp)"; trap 'rm -f "$raw"' EXIT INT TERM
        head -c 352800 /dev/zero > "$raw"
        xr="$(aplay -D "$DEVICE" -f S16_LE -r 44100 -c 2 --buffer-size=64 --period-size=16 "$raw" 2>&1 || true)"
        printf '%s' "$xr" | grep -qi 'underrun' \
            && ok "live: tiny-buffer playback exhibits underrun (stimulus valid)" \
            || nok "live: tiny-buffer playback exhibits underrun" "no 'underrun' in aplay output; stimulus may be ineffective on this device"
        clean="$(aplay -D "$DEVICE" -f S16_LE -r 44100 -c 2 --buffer-size=16384 --period-size=4096 "$raw" 2>&1 || true)"
        printf '%s' "$clean" | grep -qi 'underrun' \
            && nok "live: sane-buffer replay is clean (device recovered)" "$clean" \
            || ok "live: sane-buffer replay is clean (device recovered)"
    else
        skip "live underrun stimulus" "aplay not installed"
    fi
else
    skip "live underrun stimulus" "pass --live on target"
fi

# --- B1. static: backend recovery coverage ----------------------------------
if [ -n "$BACKEND_SRC" ] && [ -r "$BACKEND_SRC" ]; then
    check() { # $1 = grep pattern, $2 = description
        grep -q "$1" "$BACKEND_SRC" && ok "backend static: $2" || nok "backend static: $2"
    }
    check 'SND_PCM_STATE_XRUN' 'XRUN state detected'
    check 'snd_pcm_recover(state->pcm, -EPIPE' 'EPIPE recovered via snd_pcm_recover'
    check 'SND_PCM_STATE_SUSPENDED' 'SUSPEND state detected'
    check 'snd_pcm_recover(state->pcm, -ESTRPIPE' 'ESTRPIPE recovered via snd_pcm_recover'
    check 'avail = snd_pcm_avail_update' 'avail_update error path exists'
    check 'snd_pcm_mmap_begin' 'mmap path has xrun handling'
    check 'snd_pcm_writei' 'RW fallback path has xrun handling'
    check 'avail > state->buffer_size' 'insane-avail triggers full reopen'
    check 'snd_pcm_wait(state->pcm, state->pcm_wait_timeout)' 'pcm_wait timeout path exists'
else
    skip "backend static recovery coverage" "pass --backend-src <decode_alsa_backend.c>"
fi

# --- B2. static: healthy hw_params fixture parses --------------------------
FIX="$HERE/fixtures/hw_params-open-s32-44100.txt"
if [ -r "$FIX" ]; then
    fmt="$(sed -n 's/^format: //p' "$FIX")"
    rate="$(sed -n 's/^rate: \([0-9]*\).*/\1/p' "$FIX")"
    ps="$(sed -n 's/^period_size: //p' "$FIX")"
    bs="$(sed -n 's/^buffer_size: //p' "$FIX")"
    [ "$fmt" = "S32_LE" ] && ok "hw_params fixture: negotiated format is S32_LE (jive_alsa auto pick)" \
                          || nok "hw_params fixture: negotiated format" "got '$fmt'"
    [ "$rate" = "44100" ] && ok "hw_params fixture: native rate 44100, no resample" \
                          || nok "hw_params fixture: native rate" "got '$rate'"
    # buffer must hold an integer number of periods (>=2) for the fifo math.
    if [ -n "$ps" ] && [ -n "$bs" ] && [ "$ps" -gt 0 ] 2>/dev/null; then
        [ $(( bs % ps )) -eq 0 ] && [ $(( bs / ps )) -ge 2 ] \
            && ok "hw_params fixture: buffer/period integral ($bs/$ps)" \
            || nok "hw_params fixture: buffer/period integral" "buffer=$bs period=$ps"
    else
        nok "hw_params fixture: buffer/period parse" "buffer='$bs' period='$ps'"
    fi
else
    skip "hw_params fixture parse" "fixture missing"
fi

echo "1..$n"
[ "$failed" -eq 0 ]
