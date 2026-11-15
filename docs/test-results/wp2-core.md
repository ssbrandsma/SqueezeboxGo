# WP2 Core — test results

Date: 2026-11-15 21:04 UTC. Branch: `wp2/core`. Commit: `e32e3fd`.
Host: `DESKTOP-OVMHVD2` (Linux x86_64, WSL2).

Owner note: written by Agent 2 on WP2 task instruction;
`docs/test-results/` is Agent 6's tree — coordinate on format changes.

## Summary

| Check | Status | Notes |
|---|---|---|
| proposals:review | PASS | 0001–0003 reviewed line-by-line against 758bc11, all accepted |
| patches:apply | PASS | 6/6 `patch -p1` clean on pristine 758bc11 |
| build:aarch64 | PASS | full cross build exit 0, tarball + sha256 |
| arch | PASS | all staging ELFs aarch64; RUNPATH exactly /opt/squeezeplay/lib |
| needed | PASS | jive/jive_alsa/lua NEEDED as expected; asound only in jive_alsa |
| strings | PASS | promoted patch strings present in jive_alsa + jive |
| clamp:qemu | PASS | jive_alsa -b 1 -p 99 prints both clamp WARNs under qemu-aarch64 |
| owner:probe | PASS | 0006 control flow TRUE/TRUE/FALSE/FALSE (verbatim harness) |
| lua:modules | PASS | 10/10 loadable Lua C modules load under qemu (rtmp needs jive) |
| boot:qemu | PASS | jive 9.0.0 r541 main loop alive, 48 applets, settings written |
| bsp:syntax | PASS | rg35xxh_bsp.c -fsyntax-only aarch64 clean; Lua luac -p clean |
| boot:target | NOT RUN | no RG35XX H hardware; image assembly is Agent 1 |

Totals — PASS: 11, FAIL: 0, NOT RUN: 1, BLOCKED: 0.

## Details

### proposals:review — PASS

Target: `audio/alsa/proposals/0001-0003` (read-only) vs
`ralph-irving/squeezeplay@758bc11` (`/tmp/wp1-core/squeezeplay`, clean).

- 0001 (log negotiated PCM): all symbols in scope at the insertion point
  (`device`/`sample_rate`/`access` params, `state->format/period_size/
  buffer_size`); `%lu` matches `snd_pcm_sframes_t` via cast; `ch=2` exact
  (function hardcodes 2 channels); placed after hw_params success so no
  NULL-device path reaches it. Hunk context matches upstream lines ~780.
- 0002 (clamp buffer/period): fields are `unsigned int` (`%u` correct);
  `LOG_WARN` no-category flavor matches this TU; placed after the usage
  check and after the `period_count>100` cpu-randomisation fold, so the
  escape hatch keeps working; clamp targets equal the `ALSA_DEFAULT_*`
  fallbacks in `decode_alsa.c`. Hunk context matches upstream ~1398.
- 0003 (audio-owner hook): category-first `LOG_WARN/LOG_ERROR` flavor
  matches `decode_alsa.c`; `bool_t/TRUE/FALSE` via `common.h`→`types.h`;
  stdlib/stdio/unistd/`PATH_MAX` all provided by `common.h`; fork path is
  `vfork`+`execv` with `_exit()` on failure so the `atexit` release cannot
  fire in the child; `decode.c` falls through to the next backend (or "no
  audio device") when init returns 0; `system()` runs pre-fork with no
  audio lock held (decode thread starts after init). Trust note:
  `AUDIO_OWNER_BIN` is operator-set env (same level as `USEALSA*`/`PATH`).
  Hunk contexts match upstream ~38 and ~326.
- Verdict: accept all three, no rejections. Promoted as
  `squeezeplay/patches/0004–0006` (audio authorship kept, core review
  notes in each header); `series` + `README.md` updated.

### patches:apply — PASS

```text
$ git clone /tmp/wp1-core/squeezeplay /tmp/wp2-core/squeezeplay  # 758bc11
$ cp <tree>/squeezeplay/configuration/Makefile.linux-aarch64 src/
$ for p in <tree>/squeezeplay/patches/000*.patch; do patch -p1 < "$p"; done
APPLY_DONE   # 6/6, no rejects (0001–0003 pre-existing, 0004–0006 promoted)
 M src/lua-5.1.5/src/Makefile, src/lua-5.1.5/src/luaconf.h
 M src/squeezeplay/Makefile.am, src/squeezeplay/Makefile.in
 M src/squeezeplay/src/audio/decode/decode_alsa.c
 M src/squeezeplay/src/audio/decode/decode_alsa_backend.c
```

### build:aarch64 — PASS

```text
$ cd /tmp/wp2-core/squeezeplay/src
$ export LD_LIBRARY_PATH=/tmp/x-tools/usr/lib/x86_64-linux-gnu
$ PATH=/tmp/x-tools/wrap:/tmp/x-tools/usr/bin:$PATH \
  make -f Makefile.linux-aarch64 SYSROOT=/tmp/x-tools
BUILD_EXIT=0
```

Toolchain notes (host drift since WP1, both environmental, both fixed
outside the repo): the cached `/tmp/x-tools` wrapper needs
`LD_LIBRARY_PATH` for `libopcodes/libbfd` (host binutils-aarch64 removed)
and `/tmp/x-tools/usr/bin` on `PATH` for `ar/ranlib/strip`. The pinned
container (`build/toolchain/Dockerfile`) is unaffected.

```text
$ cat squeezeplay-aarch64-9.0.0.tgz.sha256
908a5423c635d7212c63aa2e3f6e5cae0794719da605c97a8803a07224eb01d9  squeezeplay-aarch64-9.0.0.tgz
$ ls -l squeezeplay-aarch64-9.0.0.tgz   # 23533594 bytes
$ grep -c '\-march=armv8-a+crc -mtune=cortex-a53' /tmp/wp2-core/cross-build.log
668
$ cat src/squeezeplay/src/version.h
#define SQUEEZEPLAY_RELEASE "9.0.0"
#define SQUEEZEPLAY_REVISION "541"
```

### arch — PASS

```text
$ file build/linux-aarch64/opt/squeezeplay/bin/jive \
       build/linux-aarch64/opt/squeezeplay/bin/jive_alsa \
       build/linux-aarch64/opt/squeezeplay/bin/lua \
       build/linux-aarch64/opt/squeezeplay/lib/liblua.so
.../bin/jive:      ELF 64-bit LSB pie executable, ARM aarch64 ...
.../bin/jive_alsa: ELF 64-bit LSB pie executable, ARM aarch64 ...
.../bin/lua:       ELF 64-bit LSB pie executable, ARM aarch64 ...
.../lib/liblua.so: ELF 64-bit LSB shared object, ARM aarch64 ...
$ # sweep: every ELF under bin/ and lib/ is aarch64, no exceptions
SWEEP_DONE
$ readelf -d bin/jive bin/jive_alsa bin/lua | grep RUNPATH
Library runpath: [/opt/squeezeplay/lib]   # x3, exact, no staging leakage
```

### needed — PASS

```text
$ readelf -d bin/jive | grep NEEDED
libtolua++.so libSDL_image-1.2.so.0 libSDL_ttf-2.0.so.0 libSDL_gfx.so.0
libFLAC.so.8 libmad.so.0 libvorbisidec.so.1 libfdk-aac.so.2 liblua.so
libm.so.6 libSDL-1.2.so.0 libc.so.6 ld-linux-aarch64.so.1
$ readelf -d bin/jive_alsa | grep NEEDED
libm.so.6 libasound.so.2 libc.so.6 ld-linux-aarch64.so.1
$ readelf -d bin/lua | grep NEEDED
liblua.so libm.so.6 libc.so.6 ld-linux-aarch64.so.1
```

`jive` correctly has no `libasound` (it fork+execs `jive_alsa`); only
`jive_alsa` needs target `libasound.so.2`. Ship both binaries.

### strings — PASS

```text
$ strings bin/jive_alsa | grep -E 'Negotiated PCM|out of range, clamping'
%s:%d Negotiated PCM %s: format=%s rate=%u ch=2 access=%s period=%lu buffer=%lu
%s:%d buffer_time %u us out of range, clamping to 30000
%s:%d period_count %u out of range, clamping to 3
$ strings bin/jive | grep -E 'AUDIO_OWNER_BIN|audio-owner|held by another'
AUDIO_OWNER_BIN
%s:%d audio-owner release failed
%s:%d audio device held by another source
```

### clamp:qemu — PASS

Target: `manual` (qemu-aarch64 8.2.2, `-L` merged sysroot).

```text
$ qemu-aarch64 -L /tmp/wp2-core/a64root ./jive_alsa -v -d null -b 1 -p 99 -f 1
20261115 20:54:10.155 WARN   main:1410 buffer_time 1 us out of range, clamping to 30000
20261115 20:54:10.170 WARN   main:1417 period_count 99 out of range, clamping to 3
20261115 20:54:10.180 WARN   decode_lock_memory:1295 mlockall failed
20261115 20:54:10.202 ERROR  pcm_test:916 Playback open error: No such file or directory (null)
20261115 20:54:10.203 ERROR  main:1454 exit, pcm_test failed
```

Both patch-0005 warnings fire with the exact clamped values; the
subsequent `pcm_test` failure is the expected no-ALSA-on-host path
(`/dev/snd` absent), exit path unchanged.

### owner:probe — PASS

Target: `manual` (host harness; the desktop jive boot never forks
`jive_alsa`, so the 0006 gate is probed directly).

```text
$ gcc -Wall -Wextra -o /tmp/wp2-core/owner-probe /tmp/wp2-core/owner-probe.c
$ diff -B <patched decode_alsa.c funcs> <probe funcs> && echo VERBATIM
VERBATIM_MATCH_IGNORING_BLANK_LINES
$ env -u AUDIO_OWNER_BIN ./owner-probe; AUDIO_OWNER_BIN=/bin/true ./owner-probe
bin=(unset) acquire=1
bin=/bin/true acquire=1
$ AUDIO_OWNER_BIN=/bin/false ./owner-probe; AUDIO_OWNER_BIN=/nonexistent-owner ./owner-probe
ERROR: audio device held by another source
bin=/bin/false acquire=0
ERROR: audio device held by another source
bin=/nonexistent-owner acquire=0
```

Unset → `TRUE` no-op; working arbiter → `TRUE`; failing/missing arbiter →
`FALSE` with error (clean `Decode:open` fallback, no double-open).

### lua:modules — PASS

```text
$ qemu-aarch64 -L ... ./lua -e 'for ... do require(m) end'
ok  cjson, socket.core, lxp, lfs, mime.core, md5, sha1, zipfilter,
    profiler, unicode   # 10/10 loadable modules
```

`rtmp.so` loads only inside jive (needs `log_audio_decode` from the jive
process) — expected, same as WP1.

### boot:qemu — PASS

```text
$ SDL_VIDEODRIVER=dummy LD_LIBRARY_PATH=/opt/squeezeplay/lib \
  qemu-aarch64 -L /tmp/wp2-core/a64root \
  -E LD_PRELOAD=/opt/squeezeplay/lib/fakevideo.so ./jive
rc=137 (alive at the 60 s timeout = main loop running)
SqueezePlay version 9.0.0 r541                        (JiveMain.lua:266)
640,480 32 bits/pixel 4 bytes/pixel [R<<16 G<<8 B<<0] (jiveL_initSDL:252)
Registering: x48 applets (same set as WP1)
store settings: DesktopJive, SetupAppletInstaller (+ userpath files on disk)
```

Method notes: aarch64 `fakevideo.so` (SDL_GetVideoInfo 640x480 shim,
compiled from the WP1 recipe with the cross gcc) + `logconf.lua` (INFO)
were placed in the staging tree for the test only — the shipped tarball
predates them and contains neither (verified). qemu 8.2 has no
`QEMU_LD_PRELOAD`; guest preload needs `-E LD_PRELOAD=...`. Output
captured under `script(1)` (pty ⇒ line-buffered guest stdout). Only
pre-existing upstream diagnostics appear (`splash640x480.png` fallback,
`start_demo` unregistered) — both already noted in WP1.

### bsp:syntax — PASS

```text
$ aarch64-linux-gnu-gcc --sysroot=/tmp/x-tools -fsyntax-only -Wall \
  -I.../src/squeezeplay -I.../src/squeezeplay/src -I.../staging/include \
  -I.../staging/include/SDL rg35xxh_bsp/src/rg35xxh_bsp.c
BSP_SYNTAX_OK   # zero warnings
$ luac -p SqueezeboxRG35XXHApplet.lua SqueezeboxRG35XXHMeta.lua loadPriority.lua
LUA_COMPILE_OK  # PUC Lua 5.1.5
```

### boot:target — NOT RUN

No RG35XX H hardware on this host; first `.img` assembly is Agent 1 (WP2
platform). BSP applet + `rg35xxh_bsp.so` install wiring into
`Makefile.linux-aarch64` is queued behind this skeleton.

## How to reproduce

```sh
git checkout wp2/core
# fetch + patch + cross build (container or /tmp/x-tools equivalent):
git clone https://github.com/ralph-irving/squeezeplay && cd squeezeplay
git checkout 758bc110e16de4a61905e19d012a0ad25d97859b
cp <tree>/squeezeplay/configuration/Makefile.linux-aarch64 src/
for p in <tree>/squeezeplay/patches/000*.patch; do patch -p1 < "$p"; done
cd src && make -f Makefile.linux-aarch64   # SYSROOT=/ in the container
# validation:
file build/linux-aarch64/opt/squeezeplay/bin/jive
readelf -d build/linux-aarch64/opt/squeezeplay/bin/jive | grep -E 'NEEDED|RUNPATH'
bash tests/selftest.sh            # harness proves itself on fixtures
```

## Files changed (this branch)

- `squeezeplay/patches/0004-jive-alsa-log-negotiated-pcm-params.patch` (new)
- `squeezeplay/patches/0005-jive-alsa-clamp-buffer-params.patch` (new)
- `squeezeplay/patches/0006-decode-alsa-audio-owner-hook.patch` (new)
- `squeezeplay/patches/series`, `squeezeplay/patches/README.md`
- `squeezeplay/configuration/rg35xxh_bsp/` (new skeleton: C module, applet,
  meta, loadPriority, strings, README)
- `squeezeplay/configuration/INSTALL-LAYOUT.md` (new)
- `docs/test-results/wp2-core.md` (new, this file — Agent 6 tree, see note)
