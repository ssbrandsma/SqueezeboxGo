# ALSA audio path (decoder → PCM → ALSA)

Target: RG35XX H (Allwinner H700). Pinned source base:
`ralph-irving/squeezeplay@758bc11` (2026-09-25), inspected in `/tmp`
(not vendored into git). Reference: `ralph-irving/squeezelite@cc7ee7c`
(`output_alsa.c`), `ralph-irving/squeezeos-squeezeplay@766b6a8` (backports).

Kernel/driver base: mainline `torvalds/linux@fa2933a` (2026-11-15),
`sound/soc/sunxi/sun4i-codec.c` (H616/H700 tables), DTS
`arch/arm64/boot/dts/allwinner/sun50i-h700-anbernic-rg35xx-h.dts`
(+ `-plus` → `-2024` → `sun50i-h616.dtsi` chain).

## 1. End-to-end chain

```
SlimProto/streambuf → decoder (flac/mad/vorbis/aac/alac/pcm)
  → decode_output (gain/xfade/polarity, resample to track rate)
  → decode_fifo (shared-mem ring, S32 stereo)
  → jive_alsa (separate process, SysV shm key 56833)
  → playback_callback (volume/fade, S32 → wire format)
  → ALSA PCM (mmap or RW interleaved)
  → "H616 Audio Codec" (sun4i-codec, LINEOUT) or USB DAC (snd-usb-audio)
```

Sample flow detail (`decode_priv.h`):

- Internal unit is `sample_t` = signed 32-bit (`SAMPLES_TO_BYTES(n) =
  2*n*sizeof(sample_t)`, always stereo-interleaved).
- `DECODE_FIFO_SIZE = 10*2*44100*sizeof(sample_t)` ≈ 3.5 MB: 10 s @
  44.1 kHz, 2.29 s @ 192 kHz, 1.14 s @ 384 kHz. High-rate stall
  mitigation lives in the backend autostart rule (see §4).
- Effects (UI sounds) travel a separate `EFFECT_FIFO_SIZE` ring and are
  mixed in the backend by `decode_mix_effects()` when the effects
  stream flag is set.

## 2. Frontend: `decode_alsa.c` (in-process, `jive` binary)

File: `src/squeezeplay/src/audio/decode/decode_alsa.c` (385 lines).

- `decode_alsa_init(lua_State *L)`:
  - Creates/attaches SysV shared memory (key `56833`,
    `DECODE_AUDIO_BUFFER_SIZE` = `struct decode_audio` + decode fifo +
    effect fifo), calls `decode_init_buffers(buf, true)`.
  - Resolves config from Lua `AudioSettings` first, then environment
    overrides (env wins):
    | Lua key | Env override | Default |
    |---|---|---|
    | `alsaPlaybackDevice` | `USEALSADEVICE` | `default` |
    | `alsaCaptureDevice` | `USEALSACAPTURE` (else `USEALSADEVICE`) | `default` |
    | `alsaEffectsDevice` | `USEALSAEFFECTS` | none (no effects fork) |
    | `alsaSampleSize` | `USEALSASAMPLESIZE` (`0/16/24/24_3/32`) | `16` |
    | `alsaPcmTimeout` | `USEALSAPCMTIMEOUT` (10…1500 ms) | 500 |
    | `alsaPlaybackBufferTime` | `USEALSABUFFERTIME` (µs, ≥10) | 30000 |
    | `alsaPlaybackPeriodCount` | `USEALSAPERIODCOUNT` (≥1) | 3 |
    | `alsaFlags` | `USEALSANOMMAP` (sets `FLAG_NOMMAP`) | 0 |
  - `SQUEEZEPLAY_NOPLAYBACK` set ⇒ playback `jive_alsa` is not forked
    (headless/controller mode). `SQUEEZEPLAY_NOEFFECTS` likewise.
  - `decode_alsa_fork()` execs `./jive_alsa -d <dev> [-c <cap>]
    -b <buffer_us> -p <periods> -t <pcm_timeout_ms> -s <size>
    -f <flags>` via `vfork()` from the jive CWD, then blocks up to
    ~1.5 s waiting for the child to set `decode_audio->running`.
- `start/pause/resume/stop` only assert the audio lock and reap-dead
  children (`decode_alsa_check_pids` → `exit(-1)` if a backend died).

RG35XX H consequence: device selection, buffer sizing, format forcing,
and mmap-vs-RW fallback are all reachable from `squeezeplay.sh` env
knobs — no Lua or C change needed for normal tuning.

## 3. Backend: `jive_alsa` (`decode_alsa_backend.c`, 1456 lines)

File: `src/squeezeplay/src/audio/decode/decode_alsa_backend.c`.
Build: `src/squeezeplay/Makefile.am` (`jive_alsa_LDADD = libaudio.la
-lasound`, built when `ALSA_ENABLED`); needs only `libaudio`
(fifo/fixed_math/resample) + `libasound`.

### 3.1 Startup (`main`)

1. Parses `-d/-c/-b/-p/-f/-t/-s/-v`. `-s` rewrites the global format
   preference list `fmts[]` to a single entry (`0` = auto = full list).
2. Attaches the SysV shm segment; `mlockall()` only on `PREEMPT`
   kernels (our target kernel string decides this at runtime).
3. `pcm_test()`: opens the device, disables resampling, records
   `decode_audio->max_rate` = `hw_params_get_rate_max`. Streams above
   `max_rate` are expected to be resampled client-side by callers.
4. `decode_realtime_process()`: `SCHED_FIFO` prio 45 (playback) / 35
   (effects); `EPERM` (non-RT user) is a soft `INFO`, not fatal.
5. Sets `running=true`, signals the parent fifo, enters
   `audio_thread_execute()`.

### 3.2 Device open (`pcm_open` → `_pcm_open`)

- Playback rate = `decode_audio->set_sample_rate` (validated
  1…384000, fallback 44100). Any track-rate change sets `do_open` and
  the PCM is closed/reopened — **the device always runs at the native
  track rate**; there is no SRC in this path.
- Access: tries `SND_PCM_ACCESS_MMAP_INTERLEAVED` first, falls back to
  `SND_PCM_ACCESS_RW_INTERLEAVED` on failure or `FLAG_NOMMAP`
  (`has_mmap` switches `mmap_begin/commit` vs `writei` in the loop).
- `hw:` devices: exact-rate open with resampling **disabled**; if the
  rate is unsupported it reopens as `plug<dev>` with resampling
  enabled and `set_rate_near`. Non-`hw` (e.g. `default`) devices go
  straight to resample-on + `set_rate_near`.
- **Format negotiation** walks `fmts[]` in order and keeps the first
  the device accepts:
  `S32_LE → S24_LE → S24_3LE → S16_LE` (auto mode). On the H616 codec
  (driver offers `S16_LE | S32_LE`) the auto result is **S32_LE**.
- Buffer/period: `periods_near(period_count)` (default 3),
  `buffer_time_near(buffer_time)` (default 30000 µs); plug-mode forces
  the safe pair (2 periods / 20000 µs) to avoid a `snd_pcm_close`
  crash. Negotiated `period_size`/`buffer_size` drive the whole loop.
- Playback streams also open the card's `hctl` and look up
  `IEC958 Playback Default` for SPDIF copyright-bit updates
  (`decode_alsa_copyright`); absent on our codec, harmless no-op.

### 3.3 Pump loop (`audio_thread_execute`)

Per iteration: parent-liveness check (`kill(parent,0)` → exit if
dead) → XRUN/SUSPEND recover → `snd_pcm_avail_update` (+`ENODEV`
⇒ `do_open=2`, sleep-retry loop until the device returns: this is the
USB-unplug survival path) → `snd_pcm_wait(pcm_wait_timeout)` when
less than a period is free → drain `period_size` frames via mmap or
`writei`.

`playback_callback()` (fifo lock held):

- **Autostart gate**: starts only when buffered frames exceed both
  `(3 + period_count)` periods and `output_threshold` tenths @≤96 kHz,
  or a full **1 s of audio @>96 kHz** (the 352/384 kHz stall fix).
- `add_silence_ms` (sync'd multi-room start) is rendered as digital
  silence; `skip_ahead_bytes` fast-forwards the fifo without underrun.
- **Underrun = soft**: missing frames are zero-filled, `DECODE_STATE_UNDERRUN`
  is set, one `ERROR` line is logged. The show goes on.
- Per-sample path applies `lgain/rgain` (fixed-point), fade-out
  transitions, then converts S32→ wire format (S16: `>>16`; S24 in
  S32: `>>8`; S24_3: 3-byte pack; S32: `memcpy` at unity gain).
- On `decode_check_start_point()`: clears fade state, requests
  `set_sample_rate = track_sample_rate` for the next open, updates the
  IEC958 copyright bit.
- Sync point: once per period, `sync_elapsed_samples =
  elapsed_samples - pcm_delay` + jiffies timestamp (multi-room clock).

XRUN recovery summary: `SND_PCM_STATE_XRUN` → `snd_pcm_recover(EPIPE)`;
`avail_update`/`mmap_begin`/`mmap_commit`/`writei` errors →
`recover()` + `first=1` (re-`snd_pcm_start`). `avail > buffer_size`
(a known ALSA/driver inconsistency signature) ⇒ full `do_open`
reopen. Capture overruns ⇒ `recover()` + zero-fill.

## 4. Rate/format matrix on RG35XX H (expected)

H616 codec DAI (`sun4i-codec.c`, `SUN4I_CODEC_RATES`): 8/11.025/12/16/
22.05/24/32/44.1/48/96/192 kHz; formats `S16_LE | S32_LE`; stereo.
`jive_alsa` auto-negotiates **S32_LE @ native track rate** through
`default` (plug → hw). Rates the codec cannot do (e.g. 176.4 k, 352.8 k,
384 k) resolve via plug `set_rate_near` resampling on `default`, or
fail-then-plug-reopen on `hw:`. USB DACs expose their own matrix via
`snd-usb-audio` and take the same negotiation path unchanged.

Bit-perfect claim gate (per ADR-0003): native-rate open + S32 wire
format + unity gains + no plug resample must be verified end to end
(`hw_params` dumps in `audio/tests/`) before any such claim.

## 5. RG35XX H control/mixer map (summary)

Full map: `audio/alsa/mixer-controls.md`. Net ALSA-visible controls on
card `H616 Audio Codec`:

- `DAC Playback Volume` (−73.08…0 dB, 0.116 dB step, inverted range),
  `Line Out Playback Volume` (mute, −43.5…0 dB, 1.5 dB step),
  `Line Out Playback Switch`, `Speaker Playback Switch` (card-level,
  drives `PI5` speaker amp via 700 ms DAPM event), `Line Out Source
  Playback Route` (`Stereo` / `Mono Differential`), `DAC Playback
  Switch` + `DAC Reversed Playback Switch` (DAPM mixer muxes).
- Headphone jack (`PI3`, 150 ms debounce) auto-switches the DAPM
  `Headphone` pin; DTS route is `Speaker←LINEOUT`, `Headphone←LINEOUT`
  through the board's 74HC4052D mux. There is **no capture path**:
  the H616 DAI link is `playback_only`.

## 6. Squeezelite cross-reference (informative)

`squeezelite@cc7ee7c output_alsa.c` (`test_open`, `alsa_open`) uses the
same negotiation idiom (`hw_params_any` → test rates → open), which is
what `audio/alsa/capability-detect.sh` mirrors at shell level using
`/proc/asound` + `aplay`/`amixer` probes instead of `libasound` calls.
No squeezelite code is vendored; the script is an independent
implementation of the same probe sequence.
