# Project status

Last updated: 2026-11-16 (live HW: Jive fullscreen + audio + rg35xxh identity on stock OS).

## Live hardware session 2026-11-16 (RG35XX H V4.0, stock Ubuntu 22.04)

- Native Jive 9.0.0 r541 fullscreen 640x480x32 on the LCD (SDL/fbcon);
  fixed live: SDL 512x384 mode clobber (post-launch preset re-assert),
  WQVGAsmallSkin -> RG35XXHLandscapeSkin (32bpp), skin art is faithful
  Radio B&W per upstream reference screens.
- Audio engine up: SysV-SHM LD_PRELOAD shim (`stock/compat/sysv_shim.c`)
  for the SYSVIPC=n kernel; jive_alsa holds plughw:audiocodec RUNNING.
- Platform identity `rg35xxh` accepted (ADR-0005): machine + player
  type + applet query (baby fallback); HELO verified on live session.
- Paired remote library "Squeezebox Bootstrap" (49.12.198.91); baby
  applets list (Lua ones run; ARMv5 soft-float binaries cannot).
- Stock frontend stopped (launcher.service); device runs Jive from
  /home/muse/squeezebox-dev. Reboot returns stock menu (nothing
  autostarts yet). Jive test runs carry a 900s timer.
- Pending: user opens applet menu (verify rg35xxh query + fallback in
  log); VT wedge (vt_waitactive) seen once after rapid kill/relaunch,
  cleared with vt-reset.py — add prelude to runner before next cycle.

## Completed

- WP0 discovery via 6-agent workflow `Squeezebox WP0 Discovery` (completed):
  platform survey (mainline DTS merged, U-Boot defconfig, ROCKNIX/muOS/KNULLI/stock),
  SqueezePlay tree comparison with pinned baseline, UI/SDL/skin strategy,
  QA test matrix. Audio/Standalone agents confirmed greenfield (no sources yet).
- Architecture selected autonomously; ADRs in `docs/decisions/`.
- Repo scaffold + `AGENTS.md` + contracts + upstream manifest created; baseline committed.
- WP1 parallel implementation via workflow `Squeezebox WP1 Parallel Implementation`
  (completed): all 6 branches conflict-free merged to main (`f25cd41`):
  1. Platform `02461d2`: pins (linux v7.3.4, u-boot v2026.10, ATF v2.15.0),
     fetch/build scripts, OOT list, rootfs+services, image assembly, Dockerfile.
  2. Core `81bd969`: `Makefile.linux-aarch64`, 3 compat patches, toolchain,
     verified aarch64 cross build + native/qemu jive boot (9.0.0 r541).
  3. Audio `c95446d`: ALSA path doc, asound.conf, mixer map, capability-detect,
     audio-owner arbiter, target tests, 3 jive_alsa proposals (unpromoted).
  4. UI `2fec230`: 640x480 2x skin (467 PNGs), evdev2jive mapper + map,
     splash PNG + DRM painter + init script, sdl12-compat pin.
  5. Standalone `eb8a794`: REQUIRED_SOURCES (real 9.0.2 Jive trees found on disk),
     portable adapters, Now Playing schema, bsp-shim, 8 UNIMPLEMENTED stubs.
  6. QA `ef2f465`: 6-gate harness, selftest 20/20, report generator, release tools.
- Lead integration fixes: check_mapping now validates evdev2jive `.map` grammar;
  check_skin validates Lua applet skins (467 PNGs even+valid, 4 Lua compile);
  contract JIVE_VERSION corrected to truthful 9.0.0 r541; manifest pins filled.
- Post-merge gates (`docs/test-results/wp1-merge-gates.md`): 5 PASS
  (asound, mapping, skin, shellcheck, repro-env), 1 NOT RUN (arch: no ELF in git);
  selftest 20/20, input tests 13/13.

## Completed (WP2)

- Workflow `Squeezebox WP2 First-Boot Integration` (completed), all 6 branches
  merged conflict-free to main:
  1. Platform: kernel Image 53.9 MB + RG35XX-H DTB + U-Boot DDR3/DDR4 SPL+itb
     built (exit 0); assemble-image.sh produced DDR3+DDR4 2 GiB `.img` in /tmp
     (fsck-clean, GPT verified); ext4 0-diff recipe proven (mke2fs≥1.47.1+SDE).
     NOTE: pre-merge images (no squeezeplay payload yet), kept in /tmp only.
  2. Core: audio proposals 0001-0003 reviewed + promoted (0004-0006); 6/6-patch
     aarch64 cross build exit 0 (tarball 23.5 MB); qemu jive boot to main loop
     (9.0.0 r541, 48 applets); rg35xxh_bsp skeleton + INSTALL-LAYOUT.
  3. Audio: arbiter hardened; topology-probe extended; BRINGUP runbook;
     run-all.sh 7/0; asound 6 pcms, 0 dangling.
  4. UI: aarch64 cross (evdev2jive, drm_splash, SDL1.2-compat 1.2.78) zero-warning;
     qemu replay/SDL-smoke ALL PASS; install.sh overlay 479/479 sha OK; BRINGUP.
  5. Standalone: real-arbiter integration 43/43; systemd proposal (verify clean);
     BACKEND_PLAN (librespot v0.8.0 verified, slimserver re-pin requested).
  6. QA: check_image.py (414 lines) + fixtures; selftest 27/27; HW_TEST_PLAN H1-H18.
- Lead verification: slimserver re-pin APPROVED (lms-community 9.0.2 peeled
  `1470c941` confirmed via ls-remote; ralph-irving/slimserver unavailable;
  librespot v0.8.0 `d36f9f19` confirmed). Manifest updated.
- Lead fix: shellcheck gate scoped to git-tracked scripts (was scanning agent
  worktree kernel sources and failing).
- Post-merge gates (`docs/test-results/wp2-merge-gates.md`, image E2E on the
  real assembler output): 6 PASS (asound, mapping, skin, image, shellcheck,
  repro-env), 1 NOT RUN (arch: no ELF in git). selftest 27/27.

## Completed (merged image 0.1.0-exp1)

- Workflow `Squeezebox Merged Image Build` (completed), both branches merged:
  - `wp2int/image`: full pipeline green — U-Boot SHAs identical to WP2, kernel
    + DTB, 7/7-patch squeezeplay cross build, real kmsdrm SDL2 2.32.10,
    qemu jive boot with RG35XXHBaseSkin selected (51 applets, no crash),
    4685-file staging (1732 aarch64 ELFs, NEEDED/symbol sweeps clean),
    both 2 GiB `.img` in /tmp/sqz-merged (ddr3 `82b3de0a…`, ddr4 `380be577…`).
  - `wp2int/qa`: independent E2E — check_image PASS both, 6-gate suite PASS
    both variants, no-secrets grep clean, MANIFEST.json 0.1.0-exp1 filled,
    checksum.sh create+verify green. 15 PASS / 3 NOT RUN.
- Lead review: cross-tree 0007 jive patch + BSP Lua fixes APPROVED (correct,
  minimal, verified by qemu boot); README sign-off recorded.
- Lead decision ADR-0004: base userland = debootstrap bookworm arm64 minbase
  (simplest reliable; package manifest into SBOM; snapshot pinning later).
- KNOWN GAP (honest): 0.1.0-exp1 images have NO base userland (no glibc/init)
  and no OOT panel driver → not yet hardware-bootable. Next workflow closes
  userland; panel + physical boot stay HW-gated.

## Completed (0.2.0-exp2, bootable-to-userspace)

- Workflow `Squeezebox Userland Integration` (completed), both branches merged:
  - `wp2u/image`: stage-userland.sh (real debootstrap --foreign trixie minbase
    under fakeroot, Release-sig verified, 141 pkgs + rootless 2nd stage + dpkg
    manifest + container hook), firstboot/dpkg-configure/ssh-keygen wiring,
    getty+serial+ssh+timesyncd, 11834-file staging, both 2 GiB `.img` rebuilt
    in /tmp/sqz-userland (ddr3 `7a1fc07c…`, ddr4 `c388cbf1…`); qemu-user jive
    boot against staged trixie libs; systemd-analyze verify exit 0.
  - `wp2u/qa`: E2E re-verify — userland assertions via debugfs (init, systemd,
    libasound, jive ELFs; 141-pkg manifest), variant diff characterized,
    `.img.xz` both (~164 MB each, round-trip verified), MANIFEST.json 0.2.0-exp2,
    SHA256SUMS green. 25 checks: 17 PASS + FP disposition, 3 NOT RUN.
- Lead decisions: (1) ADR-0004 amended bookworm→trixie (GLIBC_2.38 measured
  requirement; bookworm loader failure reproduced). (2) check_image secrets
  heuristic fixed — PEM hits now require key material (bare OpenSSH .rodata
  markers no longer FP); image-bad fixture strengthened; real images PASS.
- Post-merge gates (`docs/test-results/wp2u-merge-gates.md`): 6 PASS + arch
  NOT RUN. selftest 27/27.

## Completed (WP3)

- Workflow `Squeezebox WP3 Panel and Backends` (completed), all 3 merged:
  - `wp3/panel`: OOT display series 0001-0005 (DE2/Tcon/PWM/nv3052c/H DT),
    applies clean on linux-7.3.4, 15/15 DTBs 0 warnings, 7 display objects
    cross-built, full Image+modules+dtbs exit 0, BRINGUP_PANEL runbook.
  - `wp3/librespot`: real librespot v0.8.0 aarch64 cross-build (20.9 MB,
    libasound+libc only, qemu smoke); spotify.conf/run/onevent wiring with
    real event APIs; 97/97 tests with binary; nowplaying-pub key-wrap bugfix.
  - `wp3/release`: SBOM.json (141 pkgs 0-diff, 13 pins, honest toolchain),
    INSTALL/UPGRADE/RECOVERY/KNOWN_ISSUES(12), checklist SBOM+docs gates,
    93/93 doc validation.
- Lead integration: display delta merged into kernel fragment config;
  NP schema extended with optional `artwork.artwork_url` (renderer precedence:
  URL over LMS icon fetch); COVERS wiring closed in spotify-onevent.sh.
- Verified here: librespot 74 pass/0 fail/2 skip (binary absent on host),
  arbiter 42/42, audio 7/0, selftest 27/27, gates 6 PASS + arch NOT RUN
  (`docs/test-results/wp3-merge-gates.md`).

## Completed (LED boot-progress scheme)

- User report: dark display on boot attempt (stage unknown — UART log
  pending). Cause candidates triaged in `docs/hardware.md` + HW_TEST_PLAN
  §5; note 0.2.0-exp2 has NO panel driver, so a dark display is expected
  even on a fully successful 0.2.0 boot.
- Implemented: SPL power-LED already on (verified in U-Boot source);
  `boot.cmd` drives status LED via `gpio set 267` (new
  `uboot-rg35xx-h-common-fragment.conf` with `CONFIG_CMD_GPIO=y`,
  applied to both variants in `build-uboot.sh`); kernel heartbeat via
  new OOT `rg35xx-h-leds-oot.dtsi` + patch 0006 (validated: applies
  after 0005 with fuzz=0 against the real v7.3.4 DTS, mirror identical);
  `CONFIG_LEDS_TRIGGER_TIMER=y` added; userspace `services/led.sh`
  (firstboot/splash/wifi/squeezeplay/ok/fail signatures, never fatal)
  hooked into all four services + installed by `mkrootfs.sh`.
- Tests: new `services/tests/test-led.sh` 11/11; `bash -n` clean;
  DTB compile + boot.scr build ride the 0.3.0 rebuild (dtc/mkimage
  absent on host — stated, not faked).

## Completed (0.3.0-exp3, panel + LED image)

- Workflow `Squeezebox 0.3.0 Panel+LED Rebuild` (completed), both merged:
  - `v03/image`: series 0001-0006, DTB 32473B with heartbeat + panel
    nodes, U-Boot both variants with CMD_GPIO, led.sh 0755 in image,
    boot.scr with gpio marker, both 2 GiB `.img` in /tmp/sqz-v03.
  - `v03/qa`: E2E re-verify (FDT-parsed DTB, BOOT.SCR strings, led.sh
    hash, variant diff, xz round-trip), MANIFEST.json 0.3.0-exp3.
- Lead independent verification (all observed): ddr4 SHA OK; `gpio set
  267` in FAT boot script at the right position; DTB carved from FAT =
  32473B fc345c3f with heartbeat/panel/pwm-backlight/led-1/spi-gpio;
  in-image led.sh == repo (debugfs); 1675 .ko incl. rtw88_8821cs;
  check_image PASS; led tests 11/11; selftest 27/27.
- SBOM regenerated for 0.3.0 (dpkg 141/141 names+versions identical,
  measured from the 0.3.0 image via debugfs); MANIFEST sbom now points
  at releases/SBOM.json.

## Completed (stock-track diagnostics, all merged)

- Workflow `Squeezebox Stock Track Diagnostics` (completed), 4 branches merged:
  - `diag/mainline-fault`: fault tree H0-H8 + UART banner guide + probes P0-P3.
  - `diag/jammy-build`: Jammy sysroot recipe + REAL Jammy-compatible tarball
    `/tmp/jammy-sp/squeezeplay/squeezeplay-aarch64-9.0.0.tgz` (23.5 MB,
    sha 673ec5ee…02baa) — Lead-verified: ARM64, max GLIBC_2.34, 0 __isoc23.
  - `diag/stock-av`: fbcon build doc, by-name input doc, audiocodec doc
    (stock daemons are foreign ALSA holders — stop unit first, no force).
  - `diag/stock-bundle`: `stock/` tree (probe, bundle, SSH docs) + 44/44 tests.
- Verified here: bundle 44/44, selftest 27/27, shellcheck PASS (49 scripts).
- Hardware agent briefed (queue): tarball path + hash, stock-probe.sh + bundle
  now on main; priorities: probe run (unprivileged parts), DT walk, frontend
  map; evtest/fb/snd writes + PoC launch blocked on the sudo fix.

## Completed (hw Phase 1 inventory, merged)

- Branch `hw/stock-poc` merged (32 files): full read-only inventory,
  /proc/device-tree tarball + DT notes (panel fog_fj035fhd05_v1 in DT),
  frontend/SDL/audio/input/sleep evidence, Jammy tarball staged on device.
- Key facts: dmenu = 32-bit armhf SDL1.2-fbcon under respawning
  launcher.service (holds ALSA); vendor SDL2 = MALI-EGL + dummy only;
  no /dev/input/by-id; sleep = dmenu timer → pwr_new.sh → mem.
- Stock DTB blob pulled via restored sudo: `docs/hw-evidence/
  rg35xxh-stock.dtb` (144320 B, sha 7915a303…) + decompiled 6652-line
  `.dts` (model sun50iw9, panel node confirmed).
- sudo fix VERIFIED working (`sudo -n whoami` → root).

## Completed (hw Phase 2, merged + Lead follow-ups)

- Branch `hw/stock-poc2` merged (privileged probes, frontend stop/start dry
  test, evtest handoff, sleep mapping). Device left stock-healthy.
- stock-probe.sh §90 quoting bug FIXED (one char) + regression test proven
  fail-before/pass-after; bundle suite now 45/45.
- SDL 1.2 fbcon cross-build DONE (Lead, Jammy sysroot): aarch64, NEEDED
  libc/m only, GLIBC ≤ 2.34, dummy+fbcon only, sha 3924a625…
  (`docs/test-results/sdl-fbcon-build.md`). Shadows dummy libSDL via
  LD_LIBRARY_PATH on device.
- Open risk: fb0 writes proven writable, visibility UNPROVEN (DE layer
  mismatch) — human red-fill look required before any video claim.

## Completed (hw Phase 3, headless PoC PASS)

- Branch `hw/stock-poc3` merged (15 files): fbcon lib deployed + verified
  (ldd shadow first), fb full-frame write/readback/restore byte-identical,
  audio chain (440 Hz, RUNNING, 0 XRUN, mixer restored), **headless Jive
  main loop reached** (fbcon, 60 s watchdog heartbeat, drawn frame stable,
  clean SIGTERM; dummy control fails exactly as expected).
- Findings: CONFIG_SYSVIPC=n (noisy-harmless SEM/SHM fails; jive_alsa SHM
  needs audio-agent follow-up), vinfo stickiness + restore (proven 2x),
  never-chvt warning, boot-path ALSA hold explained, device reboot-verified
  back to true stock. `stock/bundle/color-fill.py` ready, NOT run.
- Suites: bundle 45/45, selftest 27/27.

## Current work (SqueezeboxGo native app)

- NEW distribution target (StockOS App Center), mainline firmware continues
  in parallel. Mechanism verified from references: `Roms/APPS/<Name>.sh` +
  `Roms/APPS/Imgs/<Name>.png` (**160x120 RGBA**) + optional payload dir;
  TF slot selectable; scripts run as root; stdout lost (log to files);
  Roms is VFAT (no symlinks/perms) → runtime lives on ext4, APPS entry
  script is the launcher. Device is source of truth for mount paths.
- Workflow `SqueezeboxGo App Build` completed; both branches merged.
  GO-HW: APPS recon (icons are 240x180!, dmenu exits via /tmp/.next),
  /opt/squeezebox-go install, 71 s Jive lifecycle, no-reboot return.
  GO-APP: 240x180 icon generator, Return-to-Anbernic action (exit 42),
  reproducible ZIP, 62-test suite.
- Lead integration: icon rescaled to device-true 240x180 (render
  inspected); real shellcheck 0.9.0 run closed B3 — 25 findings fixed
  (case shadowing, local-ordering, jammy loop, directives, unused vars;
  incl. a shellcheck quirk: directives ignored on multi-command source
  lines); real device ZIP rebuilt (`/tmp/sbgo-dist/`, sha 99c28329…,
  240x180 icon, FAT-safe). Suites: go 62/62, bundle 45/45, selftest 27/27.
- Next: hw redeploy (final icon + Return action) → human observation
  batch (icon/menu/buttons/ears/game/evtest/live color/0.3.0 boot).
- MILESTONE (owner-observed): native Jive language screen VISIBLE on the
  physical LCD (corrupted: multicolour text artifacts, black regions,
  right-edge vertical line, scanlines, wrong screen fill).
- Refined (owner: splash correct, menus torn): splash.png (480x272 Lyrion
  logo) blits once right after the INITIAL SetVideoMode and shows
  correctly → scanout, format and blit path are GOOD at that mode.
  Corruption must start at the skin's setVideoMode call (mode switch or
  layout/surface mismatch after it). Prime suspect now: skin-requested
  size vs fbcon-negotiated surface (pitch/geometry), NOT the blitter.
  hw agent tasked with Video-mode log lines + skin identity + fb state
  at splash vs menu phase + SDL probe + DE state. Fix follows data.
- hw agent tasked (queued, same run): 7-item display probe (Jive video
  log line, fbset+vinfo bitfields/offsets, SDL-vs-fb pitch probe,
  DE layer state, Lyrion-splash renderer identification). No code
  changes until measurements land.
- Redeploy merged (`hw/go-redeploy`): final ZIP installed on device
  (icon 240x180, entry, payload verified), exit-42 chain device-proven
  except physical traversal, DE gains 640x480 UI layer during Jive,
  16-request negotiates 32-bit XRGB surface (key display datum).
- display-trial.py FIXED after hw review found 3 real bugs (short
  ioctl struct, unguarded flush, assumed stride): full 40-u32 layout
  from kernel UAPI, fix-screeninfo stride, guarded flush; host tests
  now 16/16 with struct round-trip coverage.
- Retired stale `stock/go/install+uninstall` (superseded layout trap);
  added `/tmp/.next` double-launch guard to `launch.sh`.
- Network moved to phone hotspot (device .99); host key re-verified
  (same ed25519). Device had rebooted (up 2 min, stock-healthy, dmenu
  running, install 0.1.0 intact).
- UNATTENDED carousel run: all 6 mode-sets ACCEPTED, **line_length is
  ALWAYS 2560 even at 640x480** (stride smoking gun for Jive tearing),
  restore-PUT failed EINVAL (fixed: geometry-forced retry + dmenu
  preflight + pre-render; tests now 18/18). Log committed.
- Awaiting owner GO for the watched carousel (dmenu stopped during run,
  restored after) + evtest/ears/game batch.
- VT-HANG ROOT CAUSE (proven by kernel stack): Jive hung in
  `__vt_event_wait <- vt_waitactive` — SDL fbcon switches to a fresh VT
  (VT_OPENQRY) at video init; a previous SDL app killed without SDL_Quit
  (our own timeout kills!) leaves KD_GRAPHICS + VT_LOCKSWITCH, wedging
  every later SDL start. dmenu works because it owns boot-time state.
  FIX: `squeezebox-go/runtime/vt-reset.py` prelude in launch.sh replays
  SDL_Quit's LeaveGraphicsMode (KD_TEXT + UNLOCKSWITCH, never switches
  VTs — chvt wedges this kernel). Suites: go 64/64, shellcheck PASS.
  Next: deploy + rerun Jive (expect boot + Video lines), collect evtest
  tail, then 640x480x32 end-to-end + skin/bpp fix from log facts.
- Link flaky on hotspot (intermittent 255s); dmesg shows RTL site-survey
  noise (possible contributor, not proven).
- dmenu itself now wedged in vt_waitactive (D-state, unkillable) after an
  owner App Center launch + exit; screen black with full fb. chvt cannot
  unstick it. ONLY recovery: reboot (needs owner approval — not yet asked
  until now). All volatile logs rescued to /tmp/rescue.tgz first.
- vt-reset.py had a wrong constant (0x5602=VT_SETMODE → EFAULT); fixed to
  0x560C per UAPI headers + pinning test. Suites: go 65/65, shellcheck PASS.
- NEXT after reboot: deploy fixed vt-reset + launch.sh, rerun Jive with
  Video-line capture, finish stock input map (evtest decoded, needs L2
  hard-press + X/Y/click/mode disambiguation round).
- INPUT DONE (host-side): evtest fully decoded → `ui/input/rg35xxh-stock.map`
  (HAT dpad, face, shoulders, vol, sticks; E2 silent, js0 ignored);
  evdev2jive extended (HAT thresholds, BTN_C/Z codes) + Jammy cross binary
  (GLIBC 2.34); suite 15/15. Awaiting live verify round (grab-0 deploy +
  owner presses X/Y/L2/R2/clicks/menu + stick dirs).
- BLACK-SCREEN incident (owner-reported): unattended carousel cycled fb
  modes UNDERNEATH live dmenu (preflight guard did not exist yet) →
  dmenu's SDL mapping went stale, fb left all-zeros, dmenu idle.
  Recovered by clean frontend restart (verified painting via fb hash).
  Lesson encoded: trial refuses while dmenu runs; always restart
  frontend after fb mode experiments. No data lost, install intact.

## Prior state (human-gated proofs)

- SSH `rg35xxh` (muse, key auth) VERIFIED; kernel 4.9.170 aarch64.
  **sudo/su/pkexec all lost setuid** — no privilege path from SSH.
  Muse lacks video/audio/input groups. DTB blob, fb0, snd, input all
  need root. ONE-LINE FIX (UART root shell):
  `chown root:root /usr/bin/sudo && chmod 4755 /usr/bin/sudo`
  (+ optional `usermod -aG video,audio,input muse`).
- Dedicated hardware agent spawned (branch `hw/stock-poc`, isolated
  worktree): exclusive device owner. Phase 1 read-only inventory +
  /proc/device-tree DT reconstruction + frontend/SDL/audio/input/sleep
  probing; stops at the privilege wall with evidence.
- Diagnostics workflow (4 agents) still running, untouched.
- Stock PoC unblocked the moment sudo is fixed: Jammy rebuild (glibc
  2.35) + reversible ~/squeezebox-dev deploy + frontend stop/launch.
- Still need from human: (1) the sudo-fix line via UART, (2) UART log +
  LED observations from a 0.3.0 ddr4 boot on the SECOND card.

## Blockers / external deps

- No physical RG35XX H access yet → physical tests NOT RUN; probe evdev/ALSA/DDR variant later.
- Standalone private repos unavailable → framework only; exact required repos TBD by Agent 5.
- Mainline DTS has no panel nodes → carry OOT panel DTS+driver (ROCKNIX-class).
- ROCKNIX branding CC BY-NC-SA + non-commercial parts → follow pattern, own branding, GPL-only reuse.

## Next steps (resume here)

1. HUMAN: flash /tmp/sqz-userland images (or rebuild via scripts), boot RG35XX H,
   run HW_TEST_PLAN H1-H18, report results (UART log + matrix).
2. On hardware results: fix whatever fails (panel params, TPR, ALSA, wifi),
   rebuild 0.3.0, re-verify, iterate.
3. Then: WP4 appliance polish (wifi-setup UI, battery/standby flows), Qobuz +
   Radio/Music backends, web mgmt UI, WP5 final release.
4. If no hardware yet: Qobuz backend + web UI are the largest remaining
   host-doable items; slimserver-plugin evaluation per BACKEND_PLAN.

## Key commands

- `git worktree list`, `git branch -a`, `git log --oneline -10`
- Upstream pins: `docs/upstream-references/upstream-manifest.md`
- Never write images to block devices without explicit user authorization.
