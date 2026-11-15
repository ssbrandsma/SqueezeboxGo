# WP2 audio — test results & evidence

Branch: `wp2/audio` (base `96217b5` on main). Agent: WP2 Audio (Agent 3).
Date: 2026-11-15. Host: x86_64 Linux (no ALSA userspace/hardware).

Note: `docs/test-results/` is Agent 6 (QA) owned; this file is written
here per the WP2 task instruction ("Evidence: docs/test-results/wp2-audio.md")
— QA review welcome.

## Tasks

1. Harden `audio/arbiter/audio-owner` (locking, stale-lock cleanup,
   logging) against the wp2-core promotion review.
2. Validate `asound.conf` against a real ALSA parser if available +
   extend `topology-probe` with sun4i-codec specifics from the platform
   kernel config.
3. Write target bring-up runbook `audio/BRINGUP.md`.
4. Run `audio/tests/run-all.sh` against fixtures on host.

## Files changed (all under audio/, owned by Agent 3)

- `audio/arbiter/audio-owner` — hardened (see below).
- `audio/arbiter/DESIGN.md` — claim rule + failure table updated for
  WP2 behavior (status reaps stale, atomic writes, source charset,
  hold signal forwarding, event/diagnostic stream split).
- `audio/tests/topology-probe.sh` — sun4i-codec specifics: card id
  `H616AudioCodec`, sun4i-codec driver family, non-USB/non-aloop,
  pcm0p `CDC PCM` id/name, exactly 1 subdevice, no USB-style stream0,
  no pcm1p (SPDIF is a module); USB usbid VID:PID format + stream0
  rates; kernel-config cross-check (`CONFIG_SND_SUN8I_CODEC=y`,
  `CONFIG_SND_SUN50I_CODEC_ANALOG=y`, `CONFIG_SND_USB_AUDIO=m`,
  SPDIF/ALOOP not built-in) read from
  `platform/rg35xx-h/kernel/config/linux-rg35xx-h-aarch64.conf`.
- `audio/tests/run-all.sh` — new arbiter regression tests 6e–6i
  (status reap, torn record, bad source name, force-release event
  stream, status read-only, hold+TERM, non-holder rc=5, wait rc=4).
- `audio/tests/README.md` — topology row updated.
- `audio/BRINGUP.md` — new target bring-up runbook (§1 topology,
  §2 real-parser asound validation, §3 mixer init, §4 aplay/arecord
  matrix, §5 USB hotplug, §6 underrun/XRUN logs, §7 arbiter, §8 sign-off).

## Arbiter hardening detail (review-driven)

Bugs fixed: `die()` echoed `"$*"` so the numeric exit code leaked into
every error message; `force-release` event went to stderr while every
other event goes to stdout (DESIGN.md contract). Locking: claims now
written atomically (tmp+rename, dead-writer temp sweep in `init_dir`);
`status` reports under a shared lock and re-takes exclusively only for
a reap (no SH→EX in-place upgrade deadlock); `hold` verifies the claim
is still ours before re-pointing at the child. Stale-lock cleanup:
`status`/`acquire`/`release` all reap; torn records are
stale-with-identity (`source=?`), reaped loudly. Logging: diagnostics
to stderr with timestamps, event lines always to stdout; source names
restricted to `[A-Za-z0-9._-]+`. `hold` forwards TERM/INT to the child
and propagates the real `acquire` exit code.

## Observed results (host, 2026-11-15)

`sh audio/tests/run-all.sh` → **7 passed suites, 0 failed** (exit 0):

- `sh -n` syntax: 7/7 clean (incl. edited files).
- capability-detect: both fixtures exit 0, contract unchanged.
- topology-probe: 25/25 TAP points (full fixture), 23/23 (no-USB
  fixture); only the live-amixer point SKIPs.
- pcm-format-matrix: 7/7 (fixture matrix + stream0 parse; live SKIP).
- usb-hotplug-fallback: 8/8 (resolver both fixtures, 3/3 asound
  aliases; backend-static + live udev SKIP — no BACKEND_SRC/udev).
- underrun-recovery: 5/5 (hw_params fixture S32_LE@44.1k, 1323=3×441
  integral; live + backend-static SKIP).
- audio-owner functional: all WP1 checks + 6e–6i (status reap removes
  the record, torn record reaped as `source=?`, bad names rc=2,
  force-release event on stdout, status creates no state, hold+TERM
  leaves device free, release-by-other rc=5, wait-on-held rc=4).
- `python3 tests/check_asound.py audio/alsa/asound.conf` → PASS
  (structural, NOT a real ALSA parse).
- asound.conf cross-check: 6 pcm nodes defined
  (`!default !sysdefault internal silence usb usb_or_internal`),
  all `default "<name>"` references resolve, 0 dangling.
- `bash tests/run_shellcheck.sh` → PASS (30 scripts, `bash -n`
  fallback; shellcheck not installed).

## NOT RUN on host (need target or unavailable inputs)

- Real ALSA parser validation of asound.conf: `aplay`, `alsactl`,
  `amixer`, `speaker-test` all absent on host (`command -v` → 127, no
  pyalsaaudio). Parse-only commands are specified in BRINGUP.md §2 for
  first boot; structural gate + reference cross-check above are the
  host evidence.
- `--live` halves (`--play` opens, `--live` XRUN stimulus, `--monitor`
  udev hotplug), acoustic jack-mux behavior, bit-perfect hw_params
  dumps — need RG35XX H hardware (see BRINGUP.md §§4–6).
- Backend static checks (`--backend-src decode_alsa_backend.c`):
  pinned source not present in this worktree; SKIPs with reason.
