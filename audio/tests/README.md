# audio/tests — WP1 audio validation

TAP-output shell tests, runnable on the target; fixture-driven and static
halves also run on the host (no ALSA hardware needed).

| Test | Target (live) | Host |
|---|---|---|
| `topology-probe.sh` | card/PCM/jack topology + amixer controls + sun4i-codec specifics + kernel-config cross-check | `--proc-asound fixtures/...` |
| `pcm-format-matrix.sh` | `aplay --dump-hw-params` + `--play` opens | fixture matrix parse |
| `usb-hotplug-fallback.sh` | `--monitor` udev watch | resolver fallback logic + asound.conf alias checks |
| `underrun-recovery-test.sh` | `--live` tiny-buffer XRUN stimulus | `--backend-src` static recovery coverage + hw_params fixture |

`run-all.sh` runs the host-validatable whole suite plus the `audio-owner`
arbiter functional tests (single-holder, crash reap via `kill -9`,
`hold` exit-code propagation, `wait`). Pass `--live` on the target for
the audible/hardware halves.

Static backend checks need the pinned file (not vendored in git):

```
BACKEND_SRC=/tmp/wp1audio/squeezeplay/src/squeezeplay/src/audio/decode/decode_alsa_backend.c \
  sh run-all.sh
```

Fixtures in `fixtures/` mimic the target: `proc-asound/` (H616 card 0 +
USB DAC card 1), `proc-asound-no-usb/` (internal only),
`hw_params-open-s32-44100.txt` (healthy negotiated state: S32_LE @
44.1 kHz, 3×441-frame periods).
