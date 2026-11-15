# WP1 audio — test results & evidence

Branch: `wp1/audio` (base `7b2464e` on main). Agent: WP1 Audio (Agent 3).
Date: 2026-11-15. Host: x86_64 Ubuntu 24.04 (WSL2, no ALSA hardware).

Note: `docs/test-results/` is Agent 6 (QA) owned; this file is written
here per the WP1 task instruction — QA review welcome.

## Sources inspected (all in /tmp, nothing vendored wholesale)

- `squeezeplay@758bc11`: `src/squeezeplay/src/audio/decode/decode_alsa.c`
  (385 lines), `decode_alsa_backend.c` (1456 lines), `decode_priv.h`,
  `Makefile.am` jive_alsa rules, `decode.c` init-fallback chain.
- `squeezelite@cc7ee7c`: `output_alsa.c` `test_open()` probe idiom.
- `torvalds/linux@fa2933a` (sparse): `sound/soc/sunxi/sun4i-codec.c`
  H616 tables, `arch/arm64/boot/dts/allwinner/sun50i-h700-anbernic-rg35xx-h.dts`
  chain (audio-routing, `pa-gpios=PI5`, `hp-det-gpios=PI3`).

## Files created (all under audio/, owned by Agent 3)

- `audio/ALSA_PATH.md` — full decoder→PCM→ALSA path doc.
- `audio/alsa/asound.conf` — template (internal default + USB optional).
- `audio/alsa/mixer-controls.md` — control map from DTS + driver.
- `audio/alsa/capability-detect.sh` — capability detection (key=value contract).
- `audio/alsa/proposals/{README.md,0001,0002,0003}.patch` — jive_alsa proposals.
- `audio/arbiter/{DESIGN.md,audio-owner}` — arbiter design + reference impl.
- `audio/tests/{README.md,run-all.sh,topology-probe.sh,pcm-format-matrix.sh,usb-hotplug-fallback.sh,underrun-recovery-test.sh,fixtures/}`.

## Observed results (host, 2026-11-15)

`BACKEND_SRC=<pinned decode_alsa_backend.c> sh audio/tests/run-all.sh`
→ **7 passed suites, 0 failed** (exit 0):

- `sh -n` syntax: 7/7 scripts clean.
- capability-detect: full fixture (2 cards, internal=0, usb=1) and
  no-USB fixture both exit 0 with the documented key=value contract.
- topology-probe: 8/8 TAP points on both fixtures (live amixer points SKIP).
- pcm-format-matrix: 7/7 (codec matrix asserted driver-fixed; USB
  stream0 rates+formats parse; live opens SKIP without --play).
- usb-hotplug-fallback: 10/10 (resolver usb|internal correct on both
  fixtures; 3/3 asound.conf aliases; 3/3 backend ENODEV static checks).
- underrun-recovery: 13/13 (9/9 backend static recovery checks against
  pinned source; hw_params fixture S32_LE@44.1k, 1323=3×441 integral).
- audio-owner functional: single-holder refuse, kill -9 reap
  (`event=reaped`), hold exit-code propagation, wait-on-free — all pass.
- Edge cases (manual): release-by-non-holder rc=5, wait-on-held rc=4,
  force-release→free rc=3, detect-no-cards rc=1, detect-missing rc=2.
- Proposal patches: all 3 apply cleanly (`patch -p1 --dry-run`) against
  the pinned `758bc11` files (0001 fuzz 1 off 5; 0002 off 2; 0003 both
  hunks, hunk 1 off -1).
- asound.conf: delimiter balance 24/24, 3/3, 7/7 (NOT a real ALSA parse).

## Not validated on host (need target)

- Real `aplay --dump-hw-params` / `amixer` output, `--play` opens,
  `--live` XRUN stimulus, `--monitor` udev hotplug, `alsactl` parse of
  asound.conf, acoustic jack-mux behavior, bit-perfect hw_params dumps.
- Host has no libasound headers, no /proc/asound, no aplay/amixer —
  nothing ALSA-live could run here; every live path degrades to SKIP
  with an explicit reason instead of false-passing.
