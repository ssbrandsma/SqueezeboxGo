# Project status

Last updated: 2026-11-15 (Agent 0, WP1 merged → WP2 starting).

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

## Current work

- WP2 first-boot integration: kernel+U-Boot builds, rootfs+squeezeplay assembly,
  audio proposal review, SDL/KMS bring-up plan, first experimental `.img`.

## Blockers / external deps

- No physical RG35XX H access yet → physical tests NOT RUN; probe evdev/ALSA/DDR variant later.
- Standalone private repos unavailable → framework only; exact required repos TBD by Agent 5.
- Mainline DTS has no panel nodes → carry OOT panel DTS+driver (ROCKNIX-class).
- ROCKNIX branding CC BY-NC-SA + non-commercial parts → follow pattern, own branding, GPL-only reuse.

## Next steps (resume here)

1. WP2 workflow: kernel+U-Boot cross builds in container (or native cross),
   rootfs+squeezeplay+skin+services assembly, audio proposals review/promotion.
2. First experimental `.img` (assemble-image.sh) + validation report; mark
   physical-boot tests NOT RUN until hardware exists.
3. Prepare human hardware-test procedure (flash, boot, evtest, aplay, wifi).
4. WP3 standalone backends (librespot, slimserver plugins) per REQUIRED_SOURCES.

## Key commands

- `git worktree list`, `git branch -a`, `git log --oneline -10`
- Upstream pins: `docs/upstream-references/upstream-manifest.md`
- Never write images to block devices without explicit user authorization.
