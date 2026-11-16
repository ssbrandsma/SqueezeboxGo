# Squeezebox RG35XX H

Standalone Squeezebox firmware for the Anbernic RG35XX H handheld
(Allwinner H700, ARM Cortex-A53, 640x480 LCD).

Goal: power on → Linux boot → Squeezebox splash → original Jive home menu,
with LMS/SlimProto playback and LMS-independent standalone operation.
Flashable microSD image; no hardware modification.

Status: host-complete at 0.2.0-exp2 (bootable-to-userspace, HW-gated).
See [project status](docs/project-status.md) and [architecture](docs/architecture.md).

## Documentation

- [Repo guide](docs/REPO-GUIDE.md) — taking over: map, workflows, glossary
- [Build guide](docs/BUILD-GUIDE.md) — every binary, end to end
- [External sources](docs/EXTERNAL-SOURCES.md) — repos, libraries, distros, licenses
- [Platform survey](docs/PLATFORM-SURVEY.md) — why this Linux foundation
- [Install](docs/INSTALL.md) / [Upgrade](docs/UPGRADE.md) / [Recovery](docs/RECOVERY.md) / [Known issues](docs/KNOWN_ISSUES.md)

## Layout

- `platform/` — RG35XX H Linux foundation (boot, kernel, DT, rootfs, services)
- `squeezeplay/` — pinned upstream refs, patches, configuration
- `audio/` — ALSA config and audio tests
- `ui/` — skins, input mapping, splash
- `standalone/` — Standalone ecosystem integration
- `build/` — toolchain, container, image build
- `tests/`, `scripts/` — QA automation
- `docs/` — architecture, contracts, decisions, test evidence
- `releases/` — release manifests and checksums (images not stored in git)

## Build

See [build docs](docs/build.md). Reproducible containerized cross-build;
target `aarch64-linux-gnu`, Cortex-A53, `PREFIX=/opt/squeezeplay`.
