# Project status

Last updated: 2026-11-16 (Agent 0, LED scheme implemented; 0.3.0 rebuild next).

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

## Current work

- 0.3.0 rebuild workflow: kernel+DTB (OOT incl. 0006) + U-Boot (CMD_GPIO)
  + payload (led.sh) + QA verify → bootable image WITH panel + LEDs.
- Still need from human: UART log of the failing boot (proves the stage)
  + which image was flashed (ddr3/ddr4, which release).

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
