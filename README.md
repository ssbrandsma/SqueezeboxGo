# SqueezeboxGo — native Squeezebox app for the Anbernic RG35XX H

SqueezeboxGo runs the full native **SqueezePlay 9 / Jive** interface as an
App Center app on the stock Anbernic firmware. No reflash, no bootloader
or kernel changes: copy one ZIP to the card, launch it, and the handheld
becomes a Squeezebox (LMS/SlimProto + standalone radio). Games and saves
are untouched, and **Return to Anbernic** hands the stock UI back without
a reboot.

Target: Anbernic RG35XX H (V4.0 verified) — Allwinner H700 (4× Cortex-A53,
aarch64), 1 GiB LPDDR4, 640x480 LCD, stock Ubuntu 22.04 / kernel 4.9.170.

Status: **0.2.10 live on hardware** — Jive fullscreen with working buttons,
ALSA audio (speakers/headphones), Wi-Fi, LMS discovery, StandaloneRadio
playback with Now Playing. See [project status](docs/project-status.md).

## Install (users)

1. Download `SqueezeboxGo-<ver>-stockos-rg35xxh.zip` from the release.
2. Verify: `sha256sum -c SqueezeboxGo-<ver>-stockos-rg35xxh.zip.sha256`.
3. Merge the ZIP's `APPS/` contents into the card's `Roms/APPS/`.
4. App Center → **SqueezeboxGo**. First launch installs (~30–60 s).

Full guide: [squeezebox-go/INSTALL.md](squeezebox-go/INSTALL.md).
Removal: [squeezebox-go/UNINSTALL.md](squeezebox-go/UNINSTALL.md).

## Build from source (developers)

```sh
git clone https://github.com/ssbrandsma/SqueezeboxGo.git
cd SqueezeboxGo
export SOURCE_DATE_EPOCH=$(git log -1 --format=%ct)
bash tests/selftest.sh                    # 27/27 host gates
bash squeezebox-go/tests/test-package.sh  # 131/131 package gates
squeezebox-go/pack.sh --output /tmp/sbgo-dist   # needs §1 inputs
```

The packer needs two prebuilt aarch64 inputs (glibc ≤ 2.35 for stock
Jammy): the SqueezePlay tree tarball and the fbcon libSDL. Complete
recipes — sysroot, cross builds, pack, deploy, gates, troubleshooting:
**[docs/BUILD-SQUEEZEBOXGO.md](docs/BUILD-SQUEEZEBOXGO.md)**.
Dev environment + device SSH + iteration loop: **[docs/SETUP.md](docs/SETUP.md)**.

## Repo layout

```text
squeezebox-go/   App Center package: pack.sh, entry, launcher, icon, tests
stock/           stock-OS track: probe, bundle, SSH guide, compat shims
squeezeplay/     upstream pins, aarch64 patches, BSP applet, skins config
ui/              skins (Base/Landscape 640x480), input mapper, splash
audio/           ALSA config, ownership arbiter, audio tests
standalone/      Standalone ecosystem integration + applet patch diffs
platform/        mainline firmware track (bootloader/kernel/rootfs/image)
build/           toolchain (incl. Jammy sysroot), docker, image assembly
tests/ scripts/ QA automation and release checks
docs/            architecture, contracts, decisions, hardware, test evidence
releases/        manifests, SBOM, checksums (images never in git)
```

## Documentation

- [Repo guide](docs/REPO-GUIDE.md) — taking over: map, workflows, glossary
- [Build (SqueezeboxGo)](docs/BUILD-SQUEEZEBOXGO.md) — every app input, pack, deploy
- [Build (firmware)](docs/BUILD-GUIDE.md) — mainline microSD image, end to end
- [Setup](docs/SETUP.md) — dev environment, device SSH, iteration loop
- [External sources](docs/EXTERNAL-SOURCES.md) — repos, libraries, distros, licenses
- [Architecture](docs/architecture.md) / [Hardware](docs/hardware.md) / [Audio](docs/audio.md)
- [Interface contracts](docs/interface-contracts.md) / [Decisions](docs/decisions/)
- [Install](docs/INSTALL.md) / [Upgrade](docs/UPGRADE.md) / [Recovery](docs/RECOVERY.md) / [Known issues](docs/KNOWN_ISSUES.md)

## Two tracks, one tree

- **SqueezeboxGo (this README)** — the shippable today: StockOS app,
  verified live on hardware. Stable, installable, demoable.
- **Standalone firmware** (`platform/`, [build guide](docs/BUILD-GUIDE.md)) —
  the long-term boot-to-Jive microSD image (mainline U-Boot/Linux 7.x,
  trixie userland). Host-complete, hardware-gated behind panel bring-up.

Both share the SqueezePlay core, skins, input, audio and Standalone work.

## Contributing

- Host gates must pass: `tests/selftest.sh`, `test-package.sh`,
  `test-rg35xxh-identity.sh`, `test-sysv-shim.sh`, `run_tests.sh`
  (input), `run_shellcheck.sh`. New behavior ships with a test.
- Reproducible builds: honor `SOURCE_DATE_EPOCH`; no timestamps/host
  paths in artifacts. No binaries, images, caches or secrets in git
  (the two device-built compat binaries are the documented exception).
- Never flash or repartition a card from scripts; never touch the
  bootloader/kernel/PMIC without verified hardware evidence.

## License

GPL-2.0-or-later for this project's own code ([LICENSE](LICENSE)).
Upstream components keep their own licenses — see
[EXTERNAL-SOURCES.md](docs/EXTERNAL-SOURCES.md) §8 and `releases/SBOM.json`
before any release (note fdk-aac and firmware-realtek terms especially).
