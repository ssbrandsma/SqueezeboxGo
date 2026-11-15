# H616/H700 (sun4i-codec) mixer-control map — RG35XX H

Sources (inspected, not vendored):
- Driver: mainline `torvalds/linux@fa2933a`
  `sound/soc/sunxi/sun4i-codec.c`, `sun50i_h616_*` tables (~L1887–2031),
  jack/GPIO probe (~L1588–1629, L2341–2348), `sun4i_codec_spk_event`
  (~L1662–1680), `SUN4I_CODEC_RATES` (L713–718), DAI formats (L729–742).
- DTS: `arch/arm64/boot/dts/allwinner/sun50i-h700-anbernic-rg35xx-h.dts`
  → `-plus.dts` → `-2024.dts` (`&codec`: audio-routing, `pa-gpios=PI5`,
  `hp-det-gpios=PI3`) → `sun50i-h616.dtsi` (`codec@5096000`,
  `compatible="allwinner,sun50i-h616-codec"`, TX-only DMA).

Card identity: name `H616 Audio Codec`, long `h616-audio-codec`,
driver `sun4i-codec`, DAI link `cdc`/`CDC PCM`, `playback_only=true`
(**no capture device** on this card).

## User-visible mixer controls (amixer names)

| # | Control | Type | Range / values | dB mapping | Default handling |
|---|---|---|---|---|---|
| 1 | `DAC Playback Volume` | stereo volume* | 0…63, inverted (`SOC_SINGLE_TLV … 0x3f, 1`) | −73.08 dB + 1.16 dB/step … 0 dB (`sun6i_codec_dvol_scale`: −7308, 116) | Master digital trim; keep at 0 dB unless headroom needed |
| 2 | `Line Out Playback Volume` | stereo volume | 0…31 | index 0–1 = mute; 2…31 = −43.5…0 dB in 1.5 dB steps (`sun6i_codec_lineout_vol_scale`) | Analog LINEOUT level; primary volume knob candidate |
| 3 | `Line Out Playback Switch` | L/R switch | on/off per channel | — | Must be **on** for any output |
| 4 | `Speaker Playback Switch` | card-level pin switch | on/off | — | Drives `allwinner,pa-gpios` (**PI5**) speaker amp via DAPM event (+700 ms settle delay on enable) |
| 5 | `Line Out Source Playback Route` | enum | `Stereo`, `Mono Differential` | — | `Stereo` for speakers/headphones |
| 6 | `DAC Playback Switch` | DAPM, per mixer (L/R) | on/off | — | Normal path: **on** (L←LDAC, R←RDAC) |
| 7 | `DAC Reversed Playback Switch` | DAPM, per mixer | on/off | — | Normally **off** (crossfeed L←RDAC for testing) |

\* Implemented as `SOC_SINGLE` (one value) but applied to the stereo DAC.

## DAPM graph (playback)

```
Codec Playback → [DAC Enable] → Left/Right DAC → Left/Right Mixer
  --(DAC Playback Switch)--> Line Out Source Playback Route [Stereo]
  --> Line Out Ramp Controller (pop suppression) --> LINEOUT
  --> Speaker widget (PI5 amp, 700 ms on-delay) --> Speaker pin switch
  --> Headphone widget (auto-switched by hp-det jack GPIO PI3)
```

DT routing (`allwinner,audio-routing`): `Speaker ← LINEOUT`,
`Headphone ← LINEOUT`. Both outputs hang off one LINEOUT through the
board's 74HC4052D analog mux — software cannot drive different signals
to speaker vs jack; jack insertion is reported via the `Headphone Jack`
kcontrol/input event (150 ms debounce), and muting policy on
insert/remove is userspace's job (see `audio/arbiter/DESIGN.md`).

## What does NOT exist on this card

- No `Headphone Playback Volume/Switch`, no `Mic/Line In` controls
  (those belong to the A33/H3/V3s table variants, not H616).
- No capture PCM (`playback_only` link, TX-only DMA `&dma 6`).
- No `IEC958 Playback Default` — `jive_alsa`'s `snd_hctl_find_elem`
  returns NULL and the copyright-bit update becomes a no-op.

## Recommended userspace policy (initial)

1. At boot: unmute `Line Out Playback Switch`, select `Stereo` route,
   enable `DAC Playback Switch`, set `DAC Playback Volume` to 0 dB,
   `Line Out Playback Volume` to a safe starting level (~−12 dB), and
   `Speaker Playback Switch` on.
2. Volume keys drive `Line Out Playback Volume` (analog, pop-free);
   keep digital `DAC Playback Volume` fixed so bit-perfect checks stay
   meaningful.
3. On `Headphone Jack` insert event: optionally mute `Speaker` pin
   switch (amp off saves power and avoids double output); restore on
   remove. Mux behavior is board-fixed, so verify acoustically on target.
4. The 700 ms PA enable delay means the first ~0.7 s after amp-on is
   silent — do not run latency/alignment checks across an amp toggle.
