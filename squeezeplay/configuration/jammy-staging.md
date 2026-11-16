# jammy-staging variant build (TRACK B1, diag/jammy-build)

Goal: a squeezeplay payload that runs on the STOCK RG35XX H card
(Ubuntu 22.04 Jammy ARM64, glibc 2.35, vendor 4.9.170 kernel).
The noble/trixie target build needs `GLIBC_2.38` and cannot start there
(repo evidence: `docs/test-results/wp2u-image.md` §6; stock env:
`docs/hardware.md`). This variant links against real Jammy 2.35
headers+libs, so the whole tree needs at most `GLIBC_2.34` (measured).

Scope: NEW files/analysis only. `Makefile.linux-aarch64` is untouched —
this variant is driven purely by its documented knobs. The trixie target
build is untouched. All device steps below are USER-RUN (no device access
from here), reversible, and second-card-safe per project rules.

## Knobs (exact)

| Knob | jammy-staging value | Note |
|---|---|---|
| `SYSROOT` | `<jammy-sysroot>` (e.g. `~/.cache/squeezeplay-jammy-sysroot`) | NOT `/`: Jammy 2.35 libc/ALSA headers+libs |
| `ARCHFLAGS` | default `-march=armv8-a+crc -mtune=cortex-a53` | unchanged (same H700/A53 target) |
| `EXTRA_CFLAGS` | empty | `-isystem` lives in the wrappers, not here |
| `EXTRA_LDFLAGS` | empty | `-B` lives in the wrappers, not here |
| `CROSS_COMPILE` | default `aarch64-linux-gnu-` | resolved via `PATH` (wrappers first) |
| `STRIPFLAGS` | default `-s` | unchanged |
| `SQUEEZEPLAY_RELEASE` | default (from `squeezeplay.version`) | unchanged |
| `PATH` | `<wrap>:<real-toolchain-bin>:$PATH` | wrappers MUST shadow gcc/g++/ld |
| `LD_LIBRARY_PATH` | `<toolchain>/../lib/x86_64-linux-gnu` if rootless-relocated | only for relocated-deb toolchains (libbfd); see `--env` |

No `-std=` override is needed: with 2.35 headers the `__isoc23_*`
redirects do not exist at all, so no flag can produce them. (The
`-std=gnu17` rebuild was the alternative considered and rejected for the
NOBLE sysroot in `wp2u-image.md` §6; the Jammy sysroot obsoletes it.)

## Why the wrappers (measured, 2026-11-16)

A bare `SYSROOT=<jammy>` FAILS with a Debian cross gcc (13.3.0 tested):
its install-relative noble dirs still win over the sysroot-prefixed ones,
so objects compile against 2.39 headers (`__isoc23_sscanf/strtol/fscanf`
refs) and then fail to link against 2.35 libc. Wrappers fix all three
leaks (this extends `sysroot-notes.md` gotcha 1, which only needed
`--sysroot` because noble==noble there):

- `--sysroot=<S>`: re-roots `ld` (`=`-prefixed `SEARCH_DIR`s) and the
  sysroot-prefixed gcc dirs.
- `-B<S>/usr/lib/aarch64-linux-gnu`: shadows startfiles (`crt1.o`) and
  `-l` resolution. Verified: `-print-file-name=crt1.o` and `libc.so`
  both resolve inside `<S>`.
- `-isystem <S>/usr/include/aarch64-linux-gnu -isystem <S>/usr/include`
  (multiarch dir FIRST, Debian order): shadows the noble 2.39 headers.
  The multiarch dir is required — without it, `<bits/...>` headers mix
  across releases and `stdio.h` breaks (`L_tmpnam` undeclared, observed).
- The `ld` wrapper (`--sysroot` only) covers raw `$(LD)` links
  (`Makefile.linux-aarch64` `luaprofiler` target).

## Recipe (host, rootless)

```sh
# 0. Real cross toolchain on PATH (container, system, or prior rootless
#    /tmp/x-tools-style prefix — any aarch64-linux-gnu gcc works).
# 1. Assemble the pinned Jammy sysroot + wrappers (SHA256-verified):
build/toolchain/jammy-sysroot.sh --prefix ~/.cache/squeezeplay-jammy-sysroot
eval "$(build/toolchain/jammy-sysroot.sh --env \
  --prefix ~/.cache/squeezeplay-jammy-sysroot)"
build/toolchain/jammy-sysroot.sh --check \
  --prefix ~/.cache/squeezeplay-jammy-sysroot   # want: CHECK OK, <= 2.35

# 2. Fetch pinned squeezeplay + 7/7 patches (pins: upstream-manifest.md):
git clone https://github.com/ralph-irving/squeezeplay /tmp/jammy-sp/squeezeplay
cd /tmp/jammy-sp/squeezeplay
git checkout 758bc110e16de4a61905e19d012a0ad25d97859b   # revcount 541
cp <tree>/squeezeplay/configuration/Makefile.linux-aarch64 src/
for p in <tree>/squeezeplay/patches/000*.patch; do patch -p1 < "$p"; done

# 3. Build (PATH/LD_LIBRARY_PATH/SYSROOT from --env):
cd src && make -f Makefile.linux-aarch64 SYSROOT="$JAMMY_SYSROOT"

# 4. Validate (all observed 2026-11-16, see docs/test-results/diag-jammy-build.md):
file build/linux-aarch64/opt/squeezeplay/bin/jive   # aarch64, want exit 0
readelf -d build/linux-aarch64/opt/squeezeplay/bin/jive | grep -E 'NEEDED|RUNPATH'
# NEEDED: vendored libs + libm/libc/ld only (no libasound in jive);
# jive_alsa: libm + libasound.so.2 + libc; RUNPATH exactly /opt/squeezeplay/lib
# version sweep over ALL staging ELFs: max GLIBC_2.34, zero __isoc23,
# ALSA symbols <= ALSA_0.9.0 (jive_alsa only)
```

Expected artifact: `squeezeplay-aarch64-9.0.0.tgz`
(23,536,073 bytes, sha256 `673ec5ee…02baa` on the reference run).

## Sysroot contents (pinned, jammy-updates arm64)

`libc6`/`libc6-dev` 2.35-0ubuntu3.18, `linux-libc-dev` 5.15.0-203.213,
`libasound2`/`libasound2-dev` 1.2.6.1-1ubuntu1.2 — pool paths + SHA256 in
`jammy-sysroot.sh` (`--suite jammy` selects the base-release set:
libc6 2.35-0ubuntu3 etc.). SONAMEs the payload needs: `libc.so.6`,
`libm.so.6`, `libasound.so.2`, interpreter `/lib/ld-linux-aarch64.so.1`
(all present in the Jammy `libc6`/`libasound2` debs — verified by
extracting them, and by running the payload under qemu against ONLY
these files).

## User-run stock-device probes (second card / reversible only)

Run on the STOCK card over the existing UART root shell (see
`docs/hardware.md`); nothing here writes to the card:

```sh
# 1. Confirm the stock userland this variant targets:
lsb_release -a; dpkg -l | grep -E '^(ii|hi)  (libc6|libasound2) '
# want: Ubuntu 22.04, libc6 2.35-*, libasound2 1.2.6.1-*
ls -l /lib/ld-linux-aarch64.so.1 /lib/aarch64-linux-gnu/libc.so.6
# 2. After copying the tarball + unpacking to /opt/squeezeplay (user step,
#    reversible via rm -rf; NEVER touch the stock rootfs otherwise):
ldd /opt/squeezeplay/bin/jive /opt/squeezeplay/bin/jive_alsa
# want: all lines resolved, no "not found", no GLIBC_* complaints
/opt/squeezeplay/bin/jive_alsa -v -d null -b 1 -p 99 -f 1
# want: both "clamping to" WARNs (0005), then pcm_test result
fuser -v /dev/snd/*   # REQUIRED before any exclusive playback attempt
```

Known test-env-only shims (never ship): qemu boot needs an
`SDL_GetVideoInfo` 640x480 LD_PRELOAD shim (dummy video reports 0x0, so
stock jive exits "Video mode not supported" — same as WP1/WP2) plus a
writable `$HOME/.squeezeplay/userpath` and `logconf.lua` (log categories
default OFF). Details in `docs/test-results/diag-jammy-build.md`.
