# diag/jammy-build — TRACK B1 test results

Date: 2026-11-16. Branch: `diag/jammy-build` (isolated worktree, base main
`ca32f0c`). Host: `Ubuntu 24.04.1 LTS x86_64` (noble), user `sjoerd`,
rootless (uid 1000, no sudo used).

Owner note: written on TRACK B1 task instruction; `docs/test-results/`
is Agent 6's tree — format follows `wp2-core.md`.

## Summary

The KEY KNOWN FACT is confirmed and then fixed: the noble-built payload
needs `GLIBC_2.38` (repo evidence `wp2u-image.md` §6) while stock Jammy
ships glibc 2.35 — so it cannot run there. A rootless Jammy arm64 sysroot
recipe plus a `jammy-staging` variant build (same Makefile, knobs only)
produces a payload whose maximum requirement is `GLIBC_2.34`, proven by
a real cross build and a qemu boot against ONLY Jammy 2.35 files.

| Check | Status | Notes |
|---|---|---|
| audit:needed | PASS | noble NEEDED (repo) vs Jammy SONAMEs (ports data): all resolve; blocker is purely symbol versions |
| audit:glibc | PASS | noble payload max GLIBC_2.38 (`__isoc23_*`, repo) > Jammy 2.35 → cannot run; Jammy package versions measured from ports.ubuntu.com |
| sysroot:assemble | PASS | 5 pinned debs, SHA256-verified, rootless; script re-proven in a fresh prefix |
| sysroot:check | PASS | sscanf/strtol/ALSA probe: max GLIBC_2.34, zero `__isoc23`, runs under qemu (`42 1.2.6.1`) |
| build:aarch64 | PASS | 7/7 patches clean, full cross build exit 0, tarball + sha256 |
| arch | PASS | all staging ELFs aarch64; RUNPATH exactly /opt/squeezeplay/lib |
| needed | PASS | jive/jive_alsa/lua NEEDED as contracted; asound only in jive_alsa |
| versions | PASS | ALL staging ELFs max GLIBC_2.34, zero `__isoc23`, ALSA ≤ 0.9.0 |
| lua:modules | PASS | 10/10 loadable Lua C modules load under qemu (rtmp needs jive, as WP2) |
| clamp:qemu | PASS | jive_alsa prints both 0005 clamp WARNs under qemu on Jammy-only root |
| boot:qemu | PASS | jive 9.0.0 r541 main loop alive (rc=124), 48 applets, settings written, 0 FATAL/GLIBC/symbol errors |
| boot:target | NOT RUN | no device access from here (hard rule); user-run probes documented |

Totals — PASS: 11, FAIL: 0, NOT RUN: 1, BLOCKED: 0.

## Details

### Toolchain used (all pre-existing / rootless)

- Cross gcc: rootless noble `aarch64-linux-gnu-gcc 13.3.0` at
  `/tmp/x-tools/usr/bin` (prior agent cache; debs still in
  `/tmp/x-tools/debs`). Needs `LD_LIBRARY_PATH=/tmp/x-tools/usr/lib/
  x86_64-linux-gnu` for `libopcodes/libbfd` (same WP2-noted quirk).
- `qemu-aarch64` from host (`/usr/bin/qemu-aarch64`), `curl`, `dpkg-deb`.

### audit — PASS

Repo evidence (noble payload, ships in trixie target today):

- `docs/test-results/wp2-core.md` §needed: jive NEEDED =
  `libtolua++.so libSDL_image-1.2.so.0 libSDL_ttf-2.0.so.0 libSDL_gfx.so.0
  libFLAC.so.8 libmad.so.0 libvorbisidec.so.1 libfdk-aac.so.2 liblua.so
  libm.so.6 libSDL-1.2.so.0 libc.so.6 ld-linux-aarch64.so.1`;
  jive_alsa adds `libasound.so.2`; lua = `liblua.so libm libc`.
- `docs/test-results/wp2u-image.md` §6: version-sweep measured
  `GLIBC_2.38` (`__isoc23_strtol/strtoul/sscanf…`, SDL2's
  `strlcat/fmod/fmodf@2.38`); bookworm 2.36 fails with
  ``version `GLIBC_2.38' not found`` for both jive and jive_alsa.

Real Jammy arm64 package data (fetched 2026-11-16 from
`ports.ubuntu.com/ubuntu-ports/dists/jammy{,-updates}/main/binary-arm64/
Packages.gz`):

| deb (arm64) | jammy (base) | jammy-updates (pinned) |
|---|---|---|
| libc6 | 2.35-0ubuntu3 | 2.35-0ubuntu3.18 |
| libc6-dev | 2.35-0ubuntu3 | 2.35-0ubuntu3.18 |
| linux-libc-dev | 5.15.0-25.25 | 5.15.0-203.213 |
| libasound2 | 1.2.6.1-1ubuntu1 | 1.2.6.1-1ubuntu1.2 |
| libasound2-dev | 1.2.6.1-1ubuntu1 | 1.2.6.1-1ubuntu1.2 |

Verdict: every SONAME the payload needs (`libc.so.6`, `libm.so.6`,
`libasound.so.2`, `/lib/ld-linux-aarch64.so.1` — all verified present in
the extracted Jammy debs) resolves on stock; the ONLY blocker is symbol
versions (2.38 > 2.35). Fix direction: build against 2.35.

### sysroot:assemble + sysroot:check — PASS

`build/toolchain/jammy-sysroot.sh` (new): downloads the 5 updates debs,
SHA256-verifies (hashes in the script, from Packages.gz above), extracts
with `dpkg-deb -x`, repoints absolute symlinks into the prefix, `=`-fixes
the `libc.so` GROUP script, and writes gcc/g++/ld wrappers.

The wrappers (measured necessity, NOT optional): with a bare
`--sysroot`, the cross gcc's install-relative noble dirs still win —
`stdio.h` etc. resolve to 2.39 headers, objects gain `__isoc23_*` refs,
and the link fails against 2.35 libc (observed: `undefined reference to
__isoc23_sscanf/strtol/fscanf`). Wrapper adds, for gcc/g++:
`--sysroot=<S> -B<S>/usr/lib/aarch64-linux-gnu -isystem
<S>/usr/include/aarch64-linux-gnu -isystem <S>/usr/include`
(multiarch dir first — without it, `<bits/...>` mix across releases and
`L_tmpnam` is undeclared, observed). Verified:
`-print-file-name=crt1.o` and `libc.so` both resolve inside `<S>`.

`--check` output (fresh second prefix `/tmp/jammy-test-sysroot`,
script-as-committed):

```text
probe max GLIBC: GLIBC_2.34 (want <= GLIBC_2.35)
CHECK OK
42 1.2.6.1
```

(`42` = strtol/sscanf/snprintf/printf all work; `1.2.6.1` = Jammy's
libasound, running under `qemu-aarch64 -L <S>` with no other root.)

### build:aarch64 — PASS

```text
$ git clone https://github.com/ralph-irving/squeezeplay /tmp/jammy-sp/squeezeplay
$ git checkout 758bc110e16de4a61905e19d012a0ad25d97859b  # revcount 541
$ cp <tree>/squeezeplay/configuration/Makefile.linux-aarch64 src/
$ for p in <tree>/squeezeplay/patches/000*.patch; do patch -p1 < "$p"; done
APPLY_DONE   # 7/7, no rejects
$ cd src && PATH=<wrap>:/tmp/x-tools/usr/bin:$PATH \
  LD_LIBRARY_PATH=/tmp/x-tools/usr/lib/x86_64-linux-gnu \
  make -f Makefile.linux-aarch64 SYSROOT=/tmp/jammy-sysroot
BUILD_EXIT=0   # 6006-line log, 683 arch-flag compiles
```

```text
$ cat squeezeplay-aarch64-9.0.0.tgz.sha256
673ec5eec78ca5127d7202951d292b194f47bc22747c9a12a8f82069bcc02baa  squeezeplay-aarch64-9.0.0.tgz
# 23536073 bytes; .so-list.txt alongside
```

Note: the first attempt (wrappers without `-isystem`) failed exactly as
predicted at `sdl-image` with the `__isoc23` undefined refs above; after
the wrapper fix, `make clean` + full rebuild went exit 0 with no source
changes. Pre-existing cosmetic (also in noble builds): freetype's
install runs `rmdir .../freetype/internal` on an absent dir (`Error 1
(ignored)`); `libfreetype.so.6.6.0` stages fine.

### arch / needed — PASS

```text
$ file .../bin/jive .../bin/jive_alsa .../bin/lua .../lib/liblua.so
.../bin/jive:      ELF 64-bit LSB pie executable, ARM aarch64 ... stripped
.../bin/jive_alsa: ELF 64-bit LSB pie executable, ARM aarch64 ... stripped
.../bin/lua:       ELF 64-bit LSB pie executable, ARM aarch64 ... stripped
.../lib/liblua.so: ELF 64-bit LSB shared object, ARM aarch64 ...
$ readelf -d bin/jive_alsa | grep NEEDED
libm.so.6 libasound.so.2 libc.so.6 ld-linux-aarch64.so.1
$ readelf -d bin/jive bin/jive_alsa bin/lua | grep RUNPATH
Library runpath: [/opt/squeezeplay/lib]   # x3, exact, no staging leakage
```

jive NEEDED matches the WP2 contract exactly (vendored libs + libm +
libSDL + libc + ld; no libasound). Sweep: every ELF under `bin/`+`lib/`
is aarch64 (only scripts/`.pc`/`.a` excluded).

### versions — PASS (the key gate)

Version sweep over ALL staging ELFs (`readelf -V`):

- Max GLIBC anywhere: **2.34** (jive, jive_alsa, lua, luac,
  libSDL-1.2, liblua, jpeg tools, xmlwf). Rest ≤ 2.33.
- **Zero** ELFs needing anything above 2.35.
- **Zero** `__isoc23` refs in `bin/`+`lib/` (byte sweep).
- ALSA versionsets: `ALSA_0.9`/`ALSA_0.9.0` in jive_alsa only
  (provided by every libasound ≥ 0.9, incl. Jammy's 1.2.6.1).

Margin: payload max 2.34 < stock 2.35. The `-std=gnu17` question is
moot — 2.35 headers cannot emit `__isoc23` refs under any `-std`.

### lua:modules / clamp:qemu — PASS

Target: `manual` (qemu-aarch64, `-L` Jammy-only root = sysroot +
staging `/opt/squeezeplay`; no noble/trixie files anywhere).

```text
$ qemu-aarch64 -L ... ./lua -e 'for ... do require(m) end'
ok  cjson, socket.core, lxp, lfs, mime.core, md5, sha1, zipfilter,
    profiler, unicode   # 10/10 (unicode needs cpath '?/core.so', as jive sets)
$ qemu-aarch64 -L ... ./jive_alsa -v -d null -b 1 -p 99 -f 1
... WARN   main:1410 buffer_time 1 us out of range, clamping to 30000
... WARN   main:1417 period_count 99 out of range, clamping to 3
... WARN   decode_lock_memory:1295 mlockall failed
... ERROR  pcm_test:916 Playback open error: No such file or directory (null)
```

(`null` PCM fails only because the 5-deb sysroot has no ALSA configs —
loader+libc+libasound all resolved or nothing would print.)

### boot:qemu — PASS

Same Jammy-only root + test-only shims (never ship, never in staging/
tarball — verified absent): `fakevideo.so` (LD_PRELOAD
`SDL_GetVideoInfo` → 640x480x32; SDL dummy video reports 0x0, so stock
jive calls `SDL_SetVideoMode(0,0)` → "Video mode not supported" →
`exit(-1)` — root-caused via an `exit()` interposer + disassembly to
`jive_framework.c` `jiveL_initSDL`; identical WP1/WP2 dummy-driver
artifact, unrelated to Jammy), writable `$HOME/.squeezeplay/userpath`
(note: qemu-user `-L` falls back to HOST paths for creations — the tree
must exist on the host side), and `logconf.lua` (log categories default
OFF — explains fully silent early runs).

```text
$ SDL_VIDEODRIVER=dummy timeout 60 script -qec "qemu-aarch64 -L ... \
    -E LD_PRELOAD=/opt/squeezeplay/lib/fakevideo.so \
    -E LD_LIBRARY_PATH=/opt/squeezeplay/lib -E HOME=/tmp/jammy-home .../jive"
JIVE_RC=124 (alive at timeout = main loop running)
SqueezePlay version 9.0.0 r541                        (JiveMain.lua:266)
640,480 32 bits/pixel 4 bytes/pixel [R<<16 G<<8 B<<0] (jiveL_initSDL:252)
48x "Registering: <applet>" (same count as WP2)
select skin: WQVGAsmallSkin (desktop default; RG35XXHBaseSkin is image-stage)
store settings: DesktopJive, SetupAppletInstaller, SlimDiscovery (on disk)
0 FATAL / 0 GLIBC / 0 undefined-symbol / 0 Lua-traceback lines
```

Only pre-existing upstream noise: `splash640x480.png` fallback and the
`start_demo` unregistered-action diagnostic (both WP1-noted).

### boot:target — NOT RUN

No device access from this sandbox (hard rule). User-run stock-device
probes (UART root shell, read-only + reversible) are documented in
`squeezeplay/configuration/jammy-staging.md`.

## Files changed (this branch, new files only)

- `build/toolchain/jammy-sysroot.sh` (new, +x): pinned rootless Jammy
  sysroot assembler + wrappers + `--env`/`--check`.
- `squeezeplay/configuration/jammy-staging.md` (new): exact Makefile
  knobs, wrapper rationale, host recipe, stock-device probes.
- `docs/test-results/diag-jammy-build.md` (new, this file).

Untouched, as required: `Makefile.linux-aarch64`, the trixie target
build, all shipped mainline target code paths.

## How to reproduce

```sh
git checkout diag/jammy-build
build/toolchain/jammy-sysroot.sh --prefix /tmp/jsr   # needs aarch64 gcc on PATH
eval "$(build/toolchain/jammy-sysroot.sh --env --prefix /tmp/jsr)"
build/toolchain/jammy-sysroot.sh --check --prefix /tmp/jsr
git clone https://github.com/ralph-irving/squeezeplay /tmp/jammy-sp/squeezeplay
cd /tmp/jammy-sp/squeezeplay && git checkout 758bc11
cp <tree>/squeezeplay/configuration/Makefile.linux-aarch64 src/
for p in <tree>/squeezeplay/patches/000*.patch; do patch -p1 < "$p"; done
cd src && make -f Makefile.linux-aarch64 SYSROOT=/tmp/jsr   # BUILD_EXIT=0
# validation: file / readelf -d / readelf -V sweep / qemu runs above
```
