# Repo guide — taking over this project

Start here if you are picking up the work. The full resume state is
always in [project-status](project-status.md); this guide explains where
things are and how the daily workflows run.

## 1. Map

```
SqueezeboxRG35XXH/
  AGENTS.md                 agent ownership + working rules (read first)
  README.md                 project overview
  docs/                     human documentation (you are here)
    architecture.md         selected architecture + runtime stack
    BUILD-GUIDE.md          every binary, end to end (the build manual)
    EXTERNAL-SOURCES.md     repos, libraries, distros, pins, licenses
    PLATFORM-SURVEY.md      why this Linux foundation (ROCKNIX/muOS/KNULLI/…)
    REPO-GUIDE.md           this file
    INSTALL/UPGRADE/RECOVERY/KNOWN_ISSUES.md   user-facing release docs
    interface-contracts.md  Lead-owned shared contracts (audio, NP, input…)
    hardware/audio/build.md subsystem notes
    decisions/0001..0004    ADRs (foundation, squeezeplay, audio/UI, userland)
    test-results/           evidence: wp*-*.md per phase, HW_TEST_PLAN, gates
    upstream-references/    pinned upstream manifest
  platform/rg35xx-h/        the firmware: boot/ kernel/ device-tree/ rootfs/
                            services/ configuration/  (Agent 1)
  build/                    toolchain/ (squeezeplay container+sysroot),
                            docker/ (image container), image/ (assembly)
  squeezeplay/              upstream/ notes, patches/0001..0007 + series,
                            configuration/ (aarch64 makefile, INSTALL-LAYOUT,
                            rg35xxh_bsp applet+C module)  (Agent 2)
  audio/                    ALSA_PATH, alsa/ (asound.conf, mixer map,
                            capability-detect, proposals/), arbiter/
                            (audio-owner), tests/  (Agent 3)
  ui/                       skins/ (640x480 2x bootstrap + generator),
                            input/ (evdev2jive.c + rg35xxh.map + tests),
                            splash/ (PNG, DRM painter, init glue),
                            vendor/ (sdl12-compat pin+fetcher),
                            install.sh, BRINGUP.md  (Agent 4)
  standalone/               base/ (adapters, NP schema+publisher),
                            integration/ (per-service conf, spotify wiring,
                            web-routes, UNIMPLEMENTED stubs), systemd/,
                            tests/, BACKEND_PLAN, REQUIRED_SOURCES  (Agent 5)
  tests/ scripts/ releases/ QA harness (7 gates), entrypoint, manifests,
                            SBOM, checksums  (Agent 6)
```

Upstream sources are NEVER committed wholesale: fetch to `/tmp` (verified
hashes), commit only patches/notes. Build outputs go to `build/cache/`
(gitignored) or `/tmp`; images are never committed.

## 2. Everyday commands

```sh
export SOURCE_DATE_EPOCH=$(git log -1 --format=%ct)
bash tests/selftest.sh                       # harness health (27 checks)
bash scripts/build-and-check.sh --no-report  # all 7 gates, no file write
IMAGE_UNDER_TEST=/tmp/x.img bash scripts/build-and-check.sh  # + image gate
bash ui/input/tests/run_tests.sh             # mapper unit tests (13)
bash audio/tests/run-all.sh                  # audio suites (7)
bash standalone/tests/test-librespot.sh      # needs LIBRESPOT_BIN for full set
bash standalone/tests/test-arbiter-integration.sh
git worktree list && git branch -a           # agent branches/worktrees
```

## 3. The seven gates (scripts/build-and-check.sh)

`arch` (ELF arch/NEEDED allowlist; NOT RUN when no ELF in tree),
`asound` (asound.conf parse + PCM refs), `mapping` (.json/.conf/.map incl.
evdev2jive grammar), `skin` (manifest + Lua skins: PNG validity, even dims,
luac), `image` (GPT/SPL/FAT/DTB/secrets/size on .img or tree),
`shellcheck` (tracked `*.sh` only), `repro-env` (SDE set). Exit codes:
0 PASS, 1 FAIL, 3 NOT RUN, 4 BLOCKED. Reports render to Markdown via
`scripts/gen-test-report.py`.

## 4. Changing things (conventions that keep the project green)

- **Patches**: upstream trees stay pristine in `/tmp`; every delta is a
  numbered patch + `series` entry + README row (`squeezeplay/patches/`,
  `platform/.../kernel/patches/`). Never commit upstream wholesale.
- **Contracts**: `docs/interface-contracts.md` is Lead-owned — audio
  ownership, Now Playing schema, input map, build flags. Changing a shared
  interface needs a note to affected areas + a test update.
- **Branches**: `wp<N>/<area>` per work package, merged with `--no-ff`;
  parallel write work happens in isolated git worktrees
  (`.muse/worktrees/`, retained for audit). Commit style: `[area] …`.
- **Evidence**: claims need artifacts in `docs/test-results/` (see
  `TEMPLATE.md`); `PASS/FAIL/NOT RUN/BLOCKED`, never PASS-unrun.
- **Releases**: bump `releases/MANIFEST.json` from real artifacts only
  (`checksum.sh` verifies); images + `.sha256` + `.img.xz` live outside
  git (releases carry manifests, never binaries).

## 5. Key files by task

| Task | Start here |
|---|---|
| Rebuild everything | `docs/BUILD-GUIDE.md` §1, then per-script `--help` |
| Bump Linux/U-Boot/ATF | `pins.env` + `fetch.sh --print-pins`, then rebuild + gates |
| Add a kernel patch | `kernel/patches/` + `series` + `oot-patch-list.md` + DTB build |
| Change kernel config | `kernel/config/linux-rg35xx-h-aarch64.conf` (fragment, not full .config) |
| Add a squeezeplay patch | `squeezeplay/patches/` + `series` + cross rebuild + qemu boot |
| Change input mapping | `ui/input/rg35xxh.map` + `evdev2jive` tests + mapping gate |
| Change skins/splash | generator scripts (`scale_qvga_2x.py`, `make_splash.py`), never outputs |
| Add a backend service | `standalone/integration/services/<id>/` + adapter + NP mapping + tests |
| Change NP schema | `nowplaying-schema.md` + `nowplaying-pub.sh` + both standalone suites |
| Cut a release | `RELEASE-CHECKLIST.md` + MANIFEST + SBOM + checksums + KNOWN_ISSUES |

## 6. Glossary (names you will meet everywhere)

- **Jive**: SqueezePlay UI engine (C + Lua applets). **SlimProto**: LMS
  player protocol. **BSP**: per-device glue (`rg35xxh_bsp`, cf. fab4/baby).
- **OOT**: out-of-tree (kernel patches/DT we carry). **SPL**: U-Boot
  secondary program loader (BROM loads it at sector 16). **BL31**: ATF
  secure firmware. **DTB**: compiled device tree (`dtb.img` on FAT).
- **OOT panel chain**: DE2 → TCON → DSI → nv3052c + PWM backlight.
- **audio-owner**: single-holder ALSA arbiter (`audio/arbiter/`).
- **NP**: Now Playing state (`nowplaying.json`, schema v1).
- **SDE**: `SOURCE_DATE_EPOCH` (reproducibility anchor).
- **H1–H18**: physical hardware test matrix (`test-results/HW_TEST_PLAN.md`).
