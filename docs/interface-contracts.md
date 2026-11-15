# Interface contracts

Lead-owned. Changes require Lead approval + notice to affected agents.

## Build contract (all agents)

- Target: `aarch64-linux-gnu`, `-march=armv8-a+crc -mtune=cortex-a53`, glibc.
- `PREFIX=/opt/squeezeplay`, rpath-pinned, `JIVE_VERSION=8.0.0-r<revcount>`.
- Pinned container toolchain; `SOURCE_DATE_EPOCH` set; SBOM per build.
- Upstream pins: `docs/upstream-references/upstream-manifest.md`.

## Platform HAL (`rg35xxh_bsp`, Agent 1+2)

- Display init/resolution (640x480), backlight/brightness.
- Keys/power events, battery %, charging state, standby/wake/shutdown hooks.
- Audio device enumerate/select (internal default, USB DAC optional).
- Network up/down events, persistent config store paths.

## Audio ownership (Agent 3, used by 2+5)

- Exactly one active playback source holds the ALSA device.
- `audio-owner acquire|release <source>`; crash releases automatically.
- Consistent volume/mute; Now Playing update on every switch; no stale metadata.
- Env knobs (from `squeezeplay.sh`): `USEALSA_DEVICE/SAMPLE_SIZE/BUFFER/PERIOD/NOMMAP/PCM_TIMEOUT`,
  `SQUEEZEPLAY_NOPLAYBACK`, `UTMAC`.

## Now Playing (Agent 5, rendered by Agent 4)

- Single authoritative state: title/artist/album/station, artwork, play state,
  position/duration, source id, volume, format/rate/depth, output device.
- Publishers: Jive screens, web mgmt, existing publisher interfaces. No per-source duplicates.

## Input events (Agent 4)

- Canonical Jive keys: Up/Down/Left=Back/Right=Enter, Select=A, Back=B,
  NowPlaying=X, Favorites=Y, PlayPause=Start, Home=Select,
  Prev/Next=L1/R1, VolDown/Up=L2/R2, sticks=scroll (optional).
- Key repeat, long-press, clean release; mapping file configurable.

## Standalone integration (Agent 5)

- No invented APIs for missing sources. Adapters expose: service start/stop,
  playback acquire/release via audio-owner, Now Playing publish, web routes.
- Baby/Fab4-specific deps isolated behind `standalone/integration/`.
