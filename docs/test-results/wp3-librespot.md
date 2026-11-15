# WP3 Spotify Connect (librespot) test results (2026-11-15, branch `wp3/librespot`)

Owner: Agent 5. Cross-tree note: this file lives in Agent 6's
`docs/test-results/` tree; written here because the WP3 task explicitly
requires Standalone evidence at this path (same precedent as WP2).
Code commit: see branch `wp3/librespot` tip. Base: main @ `cd58765`.
Host: Linux x86_64 (Ubuntu 24.04 noble), no root used — all build inputs
staged under `/tmp` (`apt-get download` + `dpkg-deb -x`, no `apt install`).
The librespot tree lives ONLY in `/tmp/librespot-wp3`; nothing of it is
committed (binaries and the tree stay out of git per the vendoring rule).

## 1. Fetch + pin verification

- `git clone --branch v0.8.0 --depth 1
  https://github.com/librespot-org/librespot /tmp/librespot-wp3`
- `git rev-parse HEAD` → `d36f9f1907e8cc9d68a93f8ebc6b627b1bf7267d`
  ("Preparations for v0.8.0 (#1632)", 2025-11-10), matching the upstream
  manifest pin (`v0.8.0 (d36f9f19)`). `git ls-remote --tags` agrees.
- Tag facts re-confirmed from the tree: crate `0.8.0`, MIT, `rust-version
  = "1.85"`, edition 2024; `alsa-backend` feature present; `Cargo.lock`
  shipped (4988 lines) → `--locked` builds are reproducible.

## 2. Feature set (decided by trial build, not guessed)

`cargo build --release --locked --no-default-features --features
alsa-backend,rustls-tls-webpki-roots,with-libmdns`

- `alsa-backend`: the required ALSA sink.
- `rustls-tls-webpki-roots`: pure-Rust TLS with compiled-in Mozilla roots
  (no OpenSSL cross-build complexity; best for reproducible/container
  builds per the crate's own `Cargo.toml` comment).
- `with-libmdns`: pure-Rust mDNS (no Avahi/DNS-SD system deps).
- Observed `--backend '?'`: `alsa (default), pipe, subprocess`
  (default = first compiled backend, `playback/src/audio_backend/mod.rs`).
- Mixers compiled: `softvol` (default), `alsa`.

## 3. Toolchain (exact, as used)

- Rust 1.98.1 (`rustup`, `stable-x86_64-unknown-linux-gnu`) +
  `rustup target add aarch64-unknown-linux-gnu` (rust-std ≥ 1.85 required).
- Cross C: aarch64 gcc 13.3.0 + binutils 2.42 + libc6-dev-arm64-cross
  2.39 + libasound2-dev:arm64 1.2.11 (relocatable `/tmp/x-tools` sysroot
  from prior WP work; its `as` needed host `libopcodes-2.42-arm64.so`
  from `binutils-aarch64-linux-gnu_2.42-4ubuntu2.10_amd64.deb`, extracted
  to `/tmp` and supplied via `LD_LIBRARY_PATH` — documented, no install).
- Native smoke C: same gcc, ALSA 1.2.11 amd64 debs extracted to `/tmp`
  with `alsa.pc` repointed (`prefix=/tmp/wp3-sysroot/usr`).
- Cross env: `CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER` +
  `CC_aarch64_unknown_linux_gnu` = cross gcc wrapper,
  `CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_RUSTFLAGS='-C
  target-cpu=cortex-a53'` (build-contract CPU),
  `PKG_CONFIG_{PATH=/tmp/x-tools/.../pkgconfig,SYSROOT_DIR=/tmp/x-tools,
  ALLOW_CROSS=1}`.

## 4. Build results

### 4a. aarch64 cross (the deliverable configuration)

```
Finished `release` profile [optimized] target(s) in 51.36s
target/aarch64-unknown-linux-gnu/release/librespot:
  ELF 64-bit LSB pie executable, ARM aarch64, ... for GNU/Linux 3.7.0
NEEDED: libasound.so.2, libgcc_s.so.1, libm.so.6, libc.so.6,
        ld-linux-aarch64.so.1          (no OpenSSL: rustls is static)
size: 20890472 bytes (14311320 stripped, `-C target-cpu=cortex-a53`)
sha256: 6a153727cd2b137fcf6a9a33b794d5db3ff5ead042fb80c353d58b42baa958a8
max GLIBC needed: 2.39 (readelf -V)
```

- `qemu-aarch64 --version` → `librespot 0.8.0 d36f9f1 (Built on
  2026-11-15, ..., Profile: release)`, rc=0.
- `qemu-aarch64 --backend '?'` → `alsa (default), pipe, subprocess`.
- Compatibility: runs under `qemu-aarch64 -L /tmp/qa-rdump3` against the
  staged Debian trixie userland (glibc **2.41**, trixie libasound):
  `--version` rc=0. Max need 2.39 ≤ 2.41 provided. (Only `num-bigint-dig`
  future-incompat warning; same on native.)

### 4b. Native x86_64 smoke (test vehicle for §6)

Release build in 62 s; `--version` prints `0.8.0 d36f9f1`; ldd shows
only libasound + system libs. Runtime probes (no credentials):

- With discovery (default): idles indefinitely (rc=124 at `timeout`
  kill), logs `Using AlsaSink with format: S16`, softvol `Log(60.0)`.
  ALSA PCM opens lazily on first playback — no sound card needed to idle.
- With `--disable-discovery` and no credentials: exits 1 with the real
  message `Credentials are required if discovery and oauth login are
  disabled.` (src/main.rs:1250). Consequence: the no-creds lifecycle
  test keeps discovery enabled. No premium account exists or is needed
  for any build/config/lifecycle test here.

### 4c. Canonical container recipe (for the reproducible image build)

`build/toolchain/Dockerfile` already carries gcc-aarch64 +
libasound2-dev:arm64; the image build needs only Rust added:

```dockerfile
FROM squeezeplay-toolchain:wp1
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | sh -s -- -y --default-toolchain 1.98.1 --profile minimal \
        --target aarch64-unknown-linux-gnu
ENV PATH="/root/.cargo/bin:${PATH}"
RUN git clone --branch v0.8.0 --depth 1 \
      https://github.com/librespot-org/librespot /src/librespot \
 && cd /src/librespot \
 && git rev-parse HEAD | grep -q '^d36f9f1907e8cc9d68a93f8ebc6b627b1bf7267d$' \
 && export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc \
        CC_aarch64_unknown_linux_gnu=aarch64-linux-gnu-gcc \
        PKG_CONFIG_PATH=/usr/lib/aarch64-linux-gnu/pkgconfig \
        PKG_CONFIG_ALLOW_CROSS=1 \
        CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_RUSTFLAGS='-C target-cpu=cortex-a53' \
 && cargo build --release --locked --target aarch64-unknown-linux-gnu \
      --no-default-features --features alsa-backend,rustls-tls-webpki-roots,with-libmdns
```

(Debian's cross gcc needs no `--sysroot`; multiarch paths are built in.
`cargo vendor` + SBOM for the offline image build stays a
platform-build-step TODO.)

## 5. Service wiring (all under `standalone/`, all real APIs)

| File | Role |
|---|---|
| `integration/services/spotify/spotify.conf` | Config: real `LIBRESPOT_*` env names only (the binary's own env mechanism, src/main.rs `stripped_env_key`; CLI beats env). No credentials shipped. |
| `integration/spotify-run.sh` | `BACKEND_CMD`: sources conf (`set -a`), validates bitrate/format/mixer/backend/volume/device (exit 2), requires the alsa backend unless `SPOTIFY_ALLOW_NON_ALSA=1`, requires the hook, then execs librespot with `--backend/--device/--mixer --onevent <hook> --emit-sink-events`. `SPOTIFY_DRY_RUN=1` prints argv for tests. Exit 127 when the binary is missing. |
| `integration/spotify-onevent.sh` | `--onevent` hook: maps the real `PLAYER_EVENT` environment (`src/player_event_handler.rs`) onto Now Playing schema v1. |
| `integration/services/spotify/backend.conf` | Now `spotify-run.sh $plugindir` (was UNIMPLEMENTED stub). |

- Claim discipline: the adapter binds the audio-owner claim to the
  librespot pid and holds it for the whole backend lifetime — transient
  sink closes on pause never release mid-session (verified live, §6).
- Event truth recorded from source (no invented APIs): `PLAYER_EVENT`
  values `track_changed/playing/paused/stopped/loading/preloading/
  preload_next/end_of_track/unavailable/volume_changed/seeked/
  position_correction/session_connected/session_disconnected/
  session_client_changed/shuffle_changed/repeat_changed/auto_play_changed/
  filter_explicit_content_changed/play_request_id_changed/sink`;
  `VOLUME` is raw u16 (0–65535, `MAX_VOLUME = u16::MAX`) so NP volume =
  `VOLUME*100/65535` (inverse of src/main.rs:1477); `REPEAT`/`REPEAT_TRACK`
  and `SHUFFLE` are bools; `ARTISTS`/`COVERS` newline-joined;
  `DURATION_MS`/`POSITION_MS` u32 ms.
- NP mapping: track→track/artist(joined ", ")/album(+station=SHOW_NAME
  for episodes, station cleared otherwise)/duration_s/position 0;
  playing/paused→mode+position; stopped/end_of_track/unavailable and
  sink=closed→mode=stop with anti-clobber (only when NP source is still
  spotify); seeked/position_correction→position (anti-clobbered);
  volume→scaled volume; session_connected→power=true; shuffle/repeat→NP
  enums; sink running/temporarily_closed + 8 no-field events→ignored;
  unknown events warn + exit 0 (forward-compat).
- Honest gaps (documented in the hook header, not papered over): COVERS
  artwork URLs have no NP schema field (`artwork.icon_id` is an LMS icon
  id) → artwork stays null pending a Lead contract change; positions
  truncate ms→s; multi-artist joins to one string.

## 6. Host test results

### 6a. `standalone/tests/test-librespot.sh` — 97/97 with the real binary

Run: `LIBRESPOT_BIN=/tmp/librespot-wp3/target/release/librespot
WP3_ALSA_LIBDIR=/tmp/wp3-sysroot/usr/lib/x86_64-linux-gnu
./standalone/tests/test-librespot.sh` → `pass=97 fail=0 skip=0`.

- Binary probes: `--version` = `librespot 0.8.0 d36f9f1 …` rc=0;
  `--help` rc=0 and documents all 8 wired flags; `--backend '?'` lists
  `alsa (default)`; bad flag rc=1.
- Config/dry-run (hermetic, `/bin/echo` as binary): pinned argv present,
  `--device` omitted when unset / passed when set, mixer=alsa + format
  S24_3 + volume 37 accepted, missing conf = all defaults.
- Validation: 8 bad configs → exit 2 (bitrate/format/mixer/backend/
  volume×3/empty device); pipe needs `SPOTIFY_ALLOW_NON_ALSA=1`;
  missing binary → 127; missing hook / explicit-missing-conf → 2.
- Event→NP (37 checks, no binary): Track/Episode/multi-artist/station
...[truncated 3209 chars]