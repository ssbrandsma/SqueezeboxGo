# Audio target bring-up runbook — RG35XX H (WP2)

First-boot validation for the ALSA path: internal H616 codec
(sun4i-codec, LINEOUT → speakers/headphone jack) + optional USB DAC.
Run on the target as root (or a user in `audio`), after flashing an
image that contains `/etc/asound.conf` (from `audio/alsa/asound.conf`),
`audio-owner` in `PATH`, and `audio/tests/` in `/opt/squeezeplay/tests/`
(or copy the repo `audio/` tree to the target).

Conventions: `INTERNAL` = internal card index (pinned `0` by Agent 1
udev policy; confirm with §1). `USB` = USB DAC index when attached.

## 0. Prerequisites

- `aplay`, `arecord`, `amixer`, `alsactl`, `speaker-test` installed
  (alsa-utils), `udevadm` (systemd-udev), `evtest` for jack events.
- Kernel has `CONFIG_SND_SUN8I_CODEC=y`,
  `CONFIG_SND_SUN50I_CODEC_ANALOG=y` built in; `snd-usb-audio`
  loadable (`modprobe snd-usb-audio` if no DAC appears).
- No player running: `audio-owner status` → `free`
  (`audio-owner force-release` if a stale record says otherwise).

## 1. Topology probe (expect: internal card 0, playback-only)

```sh
cat /proc/asound/cards
# want: " 0 [H616AudioCodec]: H616_Audio_Code - H616 Audio Codec"

sh topology-probe.sh                     # live mode, no args
# want: exit 0; internal present, pcm0p avail=1, no pcm0c,
#       CDC PCM id/name, mixer controls present (needs amixer)

PROC_ASOUND=/proc/asound sh ../alsa/capability-detect.sh
# want: card.count>=1, internal.card=0
```

Fail criteria: `internal.card=-1` (driver/DTS problem — check
`dmesg | grep -i -E 'codec|sun4i|asoc'`), `subdevices_avail: 0`
(something already holds the PCM — `fuser -v /dev/snd/pcm*`).

## 2. asound.conf real-parser validation (parse-only, no audio)

The host gate (`tests/check_asound.py`) only checks delimiter balance.
On the target, the real libasound parser is the authority:

```sh
alsactl -f /etc/asound.conf nrestore 2>&1 | head   # parses includes+funcs
aplay -L | grep -E '^(default|internal|usb|usb_or_internal|silence)'
aplay -L -D internal /dev/null --dump-hw-params 2>&1 | head -30
# DAC absent: `aplay -D usb ...` must FAIL CLEANLY AT OPEN
# ("Unknown PCM" / "No such file"), never a parser error.
```

Pass = `default`/`internal`/`usb_or_internal` list and dump; `usb`
fails only at open time when no DAC is attached.

## 3. Mixer init sequence (sun4i-codec controls)

Exact control names/values: `audio/alsa/mixer-controls.md`.
Run in order (card `$INTERNAL`, default `0`):

```sh
C=${INTERNAL:-0}
amixer -c $C sset 'Line Out Playback Switch' on
amixer -c $C sset 'Line Out Source Playback Route' Stereo
amixer -c $C sset 'DAC Playback Switch' on
amixer -c $C sset 'DAC Reversed Playback Switch' off
amixer -c $C sset 'DAC Playback Volume' 0dB          # unity digital trim
amixer -c $C sset 'Line Out Playback Volume' 23      # ~-12 dB safe start
amixer -c $C sset 'Speaker Playback Switch' on       # PI5 amp, 700 ms settle
sleep 1                                              # let the PA DAPM event settle
amixer -c $C scontents
```

Verify: all switches report `on`/`off` as set; `Speaker` on. Note the
700 ms PA enable delay — the first ~0.7 s after amp-on is silent; do
not run latency checks across an amp toggle. Persist with
`alsactl store` once levels are confirmed acoustically.

## 4. aplay/arecord matrix (expect: playback everywhere, no capture)

Playback matrix — every cell must open and complete:

```sh
C=${INTERNAL:-0}
for spec in "S32_LE:44100" "S32_LE:48000" "S16_LE:44100" "S16_LE:48000" \
            "S32_LE:96000" "S32_LE:192000"; do
  f=${spec%%:*}; r=${spec##*:}
  speaker-test -D hw:$C,0 -r $r -f $f -c 2 -l 1 -t sine -T 2 >/dev/null 2>&1 \
    && echo "PASS hw:$C,0 $f @ $r" || echo "FAIL hw:$C,0 $f @ $r"
done
# plug path (what jive_alsa uses via `default`):
speaker-test -D default -r 44100 -c 2 -l 1 -t sine -T 2  && echo "PASS default"
# off-DAC rates resolve via plug resample (176.4k/384k NOT in SUN4I_CODEC_RATES):
speaker-test -D default -r 176400 -c 2 -l 1 -t sine -T 2 && echo "PASS default@176.4k(plug)"
```

Automated equivalent: `sh pcm-format-matrix.sh --play`
(live dumps + opens per jive_alsa preference cell).

Capture must NOT exist (link is `playback_only`, TX-only DMA):

```sh
arecord -l | grep -i "card $C" && echo "UNEXPECTED: capture on internal" \
  || echo "PASS: no capture on internal card"
```

After each native-rate open, capture the negotiated state for the
bit-perfect gate (ADR-0003): while audio plays, in another shell

```sh
cat /proc/asound/card$C/pcm0p/sub0/hw_params
# want: access MMAP_INTERLEAVED (or RW), format S32_LE @ native rate,
#       buffer_size = N * period_size
```

## 5. USB DAC hotplug test (expect: usb→internal fallback, ENODEV survival)

```sh
sh usb-hotplug-fallback.sh --backend-src <decode_alsa_backend.c>  # static half
# in shell A:  sh usb-hotplug-fallback.sh --monitor 60
# plug a DAC into the OTG port (via adapter), wait 5 s, unplug, wait 5 s
```

Expect in shell A: `add`/`remove` events on the `sound` subsystem;
after plug, `capability-detect.sh` reports `usb.card>=1` and the
resolver chooses `ALSA_USB_PCM=usb`; after unplug it falls back to
`internal` (never a dangling `hw:` reference, never silence).

Live playback survival: start `speaker-test -D usb ...` (or jive_alsa
on the DAC), unplug mid-play. jive_alsa must log the
"waiting for device … to return" retry loop (sleep 2 between probes,
`do_open=2`), NOT exit; replug → playback resumes. Record the log
excerpt as evidence.

## 6. Underrun recovery + XRUN log capture

```sh
sh underrun-recovery-test.sh --live --device default
# want: tiny-buffer run SHOWS `underrun` (stimulus valid),
#       sane-buffer replay is clean (device recovered, no reboot/reopen)
```

XRUN log capture (for every failure report, attach all three):

```sh
dmesg -T | grep -iE 'xrun|underrun|overrun|asoc|snd|dma' | tail -40
journalctl -b -p warning --grep='alsa|snd|audio-owner|squeezeplay' | tail -40
# during playback, in a second shell:
cat /proc/asound/card$C/pcm0p/sub0/status   # state, hw_ptr/appl_ptr
cat /proc/asound/card$C/pcm0p/sub0/xrun_debug 2>/dev/null || true
```

jive_alsa-side underruns are soft by design (zero-fill +
`DECODE_STATE_UNDERRUN` + one `ERROR` line, playback continues);
a hard stall (no progress after recover) is a bug — capture
`/proc/asound/.../hw_params` + `status` + the backend log line.

## 7. Arbiter check on target

```sh
sh run-all.sh --live            # full suite incl. live halves
audio-owner hold test -- speaker-test -D default -r 44100 -c 2 -l 1 -t sine -T 3
echo "hold rc=$? (want 0), then: $(audio-owner status)"   # want: free
```

## 8. Sign-off checklist

- [ ] §1 probe green, `internal.card=0`, `avail=1`
- [ ] §2 libasound parses asound.conf; `usb` fails cleanly at open w/o DAC
- [ ] §3 mixer init applied, `alsactl store` persisted
- [ ] §4 matrix: S32/S16 @ 44.1/48/96/192 kHz all PASS on `hw:0,0`;
      no capture device; `hw_params` dump archived
- [ ] §5 hotplug add/remove seen, resolver falls back, ENODEV log captured
- [ ] §6 tiny-buffer underrun seen, sane replay clean, XRUN logs captured
- [ ] §7 `run-all.sh --live` exit 0
