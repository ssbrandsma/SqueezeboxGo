# Project status

Last updated: 2026-11-15 (Agent 0, WP0 complete → WP1 starting).

## Completed

- WP0 discovery via 6-agent workflow `Squeezebox WP0 Discovery` (completed):
  platform survey (mainline DTS merged, U-Boot defconfig, ROCKNIX/muOS/KNULLI/stock),
  SqueezePlay tree comparison with pinned baseline, UI/SDL/skin strategy,
  QA test matrix. Audio/Standalone agents confirmed greenfield (no sources yet).
- Architecture selected autonomously; ADRs in `docs/decisions/`.
- Repo scaffold + `AGENTS.md` + contracts + upstream manifest created; baseline committed.

## Current work

- WP1 parallel implementation (6 agents, isolated worktrees):
  1. Platform: kernel+U-Boot+DTB build, rootfs, image skeleton, services.
  2. Core: vendor pinned sources, `Makefile.linux-aarch64`, native deps, first build.
  3. Audio: ALSA topology, `jive_alsa` adaptation, ownership arbiter design, tests.
  4. UI: sdl12-compat/SDL2-KMS, 640x480 skin bootstrap, input mapper, splash.
  5. Standalone: integration framework + adapters (sources still missing, no invented APIs).
  6. QA: build checks, reproducibility harness, test-result reporting.

## Blockers / external deps

- No physical RG35XX H access yet → physical tests NOT RUN; probe evdev/ALSA/DDR variant later.
- Standalone private repos unavailable → framework only; exact required repos TBD by Agent 5.
- Mainline DTS has no panel nodes → carry OOT panel DTS+driver (ROCKNIX-class).
- ROCKNIX branding CC BY-NC-SA + non-commercial parts → follow pattern, own branding, GPL-only reuse.

## Next steps (resume here)

1. Check WP1 workflow result / agent branches; integrate to main.
2. Verify: aarch64 squeezeplay build, rootfs+image build, SDL smoke, ALSA config lint.
3. WP2 first-boot integration → first experimental `.img`.
4. Prepare human hardware-test procedure when device is available.

## Key commands

- `git worktree list`, `git branch -a`, `git log --oneline -10`
- Upstream pins: `docs/upstream-references/upstream-manifest.md`
- Never write images to block devices without explicit user authorization.
