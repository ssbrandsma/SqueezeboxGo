# External sources — repos, libraries, distros

Every external input to this project: where it comes from, which revision
is pinned, what we take from it, and under what license it ships.
Authoritative pins live in [upstream-manifest](upstream-references/upstream-manifest.md),
[boot pins](../platform/rg35xx-h/kernel/pins.env),
[vendor-notes](../squeezeplay/upstream/vendor-notes.md), and the release
[SBOM](../releases/SBOM.json). Nothing below is vendored wholesale into
git; fetch scripts verify hashes at download time.

> License column = upstream-declared license. Confirm in the source tree
> at vendoring time; the SBOM is the release record.

## 1. Boot chain (shipped in every image)

| Component | Source | Pin | What we use | License |
|---|---|---|---|---|
| Linux (stable) | `git.kernel.org/.../stable/linux.git` + cdn.kernel.org tarball | `v7.3.4` (`8310b43a`), tarball sha256 `b11b6df8…` | kernel `Image`, RG35XX-H DTB, module tree (1675 .ko), in-tree H700 DTS chain | GPL-2.0 |
| U-Boot | `github.com/u-boot/u-boot` | `v2026.10` (`55084065`) | `anbernic_rg35xx_h700_defconfig`, SPL + FIT per DRAM variant | GPL-2.0+ |
| ATF | `github.com/ARM-software/arm-trusted-firmware` | `v2.15.0` (`da738d5e`) | BL31 for `sun50i_h616` (shared by both variants) | BSD-3-Clause |
| OOT display series | adapted from ROCKNIX H700 patch set (reference) | files in `platform/.../kernel/patches/0001..0005` | DE2/Tcon/PWM compatibles, H616 display DT, RG35XX-H panel DT (nv3052c) | GPL-2.0 (same as origin) |

Fetch: `platform/rg35xx-h/kernel/fetch.sh --fetch all` (tarball for Linux
with published sha256; shallow git + SHA check for U-Boot/ATF, since
GitHub tarball hashes are unstable). DTB chain asserted present after fetch.

## 2. SqueezePlay family (UI + playback + references)

| Component | Source | Pin | Role |
|---|---|---|---|
| squeezeplay | `github.com/ralph-irving/squeezeplay` | `758bc11` (2026-09-25, r541) | UI + playback base; `src/` builds all of `/opt/squeezeplay` |
| squeezeos-squeezeplay | `github.com/ralph-irving/squeezeos-squeezeplay` | `766b6a8` | Backports only (build base obsolete: arm-926/gcc-4.1) |
| squeezelite | `github.com/ralph-irving/squeezelite` | `cc7ee7c` | C SlimProto/ALSA reference (`slimproto.c`, `output_alsa.c`) |
| jivelite | `github.com/ralph-irving/jivelite` | `d43a20b` | aarch64 recipe reference |
| tcz-jivelite | `github.com/ralph-irving/tcz-jivelite` | `4bdf677` | aarch64 patch recipe (adapted into our 0001) |
| slimserver (LMS) | `github.com/lms-community/slimserver` | tag `9.0.2`, peeled `1470c941` | Radio/Music/Qobuz plugin source (Lead re-pin; `ralph-irving/slimserver` 404s) |
| EnhancedDigitalOutput | `github.com/ralph-irving/squeezeplay-EnhancedDigitalOutput` | TBD, not vendored | Future USB-DAC/hi-res reference only |

Fetch recipe (all to `/tmp`): see `vendor-notes.md`. Our delta on top is
exactly `squeezeplay/patches/0001..0007` + `Makefile.linux-aarch64`.

## 3. SDL / graphics stack (shipped)

| Component | Source | Pin | Role |
|---|---|---|---|
| sdl12-compat | `github.com/libsdl-org/sdl12-compat` | `release-1.2.78` (`07043bdc`, tarball sha `40ec5f0b…`) | SDL-1.2 API on SDL2; lets unmodified Jive run on KMSDRM |
| SDL2 | `github.com/libsdl-org/SDL` (release tarball) | `release-2.32.10` (sha `5f5993c5…`) | Target build with kmsdrm(dynamic)+opengles2+udev; NEEDED libc/m only |
| SDL 1.2.15 (+image/ttf/gfx) | vendored inside squeezeplay `src/` | upstream tree | Build-ABI only (headers + link); replaced at runtime by compat (same SONAME) |

Fetch: `ui/vendor/fetch-sdl12-compat.sh` (sha-verified). The SDL2 dummy-video
fixture exists only to compile compat; the shipped SDL2 is the kmsdrm build.
Compat `dlopen`s SDL2 at runtime, so its NEEDED is libc-only.

SDL2 NEEDED is libc/m only (148 kmsdrm refs, 0 X11 refs) — it carries no
X/Wayland baggage onto the appliance.

## 4. Vendored-inside-squeezeplay (built from `src/`, shipped under /opt)

These travel inside the `squeezeplay@758bc11` tree and are built by
`Makefile.linux-aarch64` — no separate fetch step:

zlib-1.2.11, expat-2.0.1, freetype-2.4.2, libpng-1.2.59, jpeg-9d,
SDL-1.2.15, SDL_image-1.2.5, SDL_ttf-2.0.11, SDL_gfx-2.0.15,
lua-5.1.5 (PUC), tolua++-1.0.92, luasocket-2.0.2, slnunicode-1.1,
luacjson, luaexpat-1.0.2, luafilesystem-1.2, luaprofiler-2.0.2,
luazipfilter, luamd5, loop-2.2-alpha, fdk-aac-2.0.3, libogg-1.2.2,
flac-1.2.1, libmad-0.15.1b, Tremor (Vorbis), FreeSans fonts, axTLS,
RTMP helpers. Image build prunes dev files (`*.a`, `*-config`, cjpeg…;
see `stage-payload.sh` step 2). Notable license: fdk-aac uses the
Fraunhofer FDK license (more restrictive than the rest — confirm
redistribution terms before any commercial release).

## 5. Debian userland + containers

| Input | Pin | Role |
|---|---|---|
| trixie arm64 minbase + `userland-include.txt` (141 pkgs) | Release-signed debootstrap; dpkg manifest in `docs/test-results/wp2u-dpkg-manifest.txt` | `/sbin/init`, systemd, udev, ALSA, wifi, ssh, firmware-realtek |
| `debian:bookworm-slim` container | `sha256:734a72b3…b179bc` | image-build container (`build/docker/Dockerfile`) |
| `ubuntu:24.04` + pinned apt versions | see `build/toolchain/Dockerfile` | squeezeplay cross container (gcc 13, arm64 multiarch, qemu-user) |

Suite is trixie (not bookworm): the payload needs GLIBC_2.38
(ADR-0004). Firmware blobs: `firmware-realtek` (RTL8821CS) via the
`non-free-firmware` component — redistributable per Debian, not GPL.

## 6. Spotify / Rust

| Input | Pin | Role |
|---|---|---|
| librespot | `librespot-org/librespot` tag `v0.8.0` (`d36f9f19`), MIT, rust ≥1.85 | Spotify Connect backend; `alsa-backend,rustls-tls-webpki-roots,with-libmdns` |
| Rust toolchain | 1.98.1 used (≥1.85 required), `aarch64-unknown-linux-gnu` | cross build; locked `Cargo.lock` |

Dead end recorded: legacy `libspotify` (private SVN, dead upstream) — do
not pursue (`REQUIRED_SOURCES.md` item 9).

## 7. Reference-only (read, never shipped)

ROCKNIX H700 tree (GPL-2.0 scripts; branding CC BY-NC-SA — techniques
reusable, distribution not forked), muOS (GPL-3.0 UI open, kernel closed),
KNULLI wiki/layout notes, stock-Anbernic notes, `squeezeplay-
EnhancedDigitalOutput` (future USB-DAC reference), OpenVPN 2.5.11 tarball
URI from the SqueezeOS recipe (unverified — re-check at vendoring),
`Logitech/slimserver` (dead upstream, rejected), local `~/squeezeos` /
`~/squeeze_userbuild` 9.0.2 trees (NowPlaying/Player API grounding for the
NP schema; Baby/Fab4 applet deps isolated behind `standalone/integration/`).

## 8. License + redistribution checklist (before any release)

1. Ship kernel/U-Boot source offer (GPL-2.0) + OOT patch series (already in
   git) + build scripts. 2. Confirm fdk-aac + firmware-realtek terms for
   your distribution channel. 3. Keep ROCKNIX/muOS branding out; our
   branding is original. 4. Regenerate SBOM from the release staging
   (`releases/SBOM.json` is the 0.2.0-exp2 draft). 5. No credentials/keys
   in images — enforced by the `image` gate's secrets scan.
