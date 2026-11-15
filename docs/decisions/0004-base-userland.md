# ADR-0004 — Base userland: debootstrap arm64 minbase

Date: 2026-11-15. Status: accepted. Amended: suite bookworm → trixie.

## Context

WP2 merged images contain kernel, bootloader, and the full Squeezebox payload
staging, but no base userland (no glibc, no init/systemd): they cannot boot to
userspace on hardware. Candidates: debootstrap Debian, Buildroot, Yocto.

## Decision

Use `debootstrap --arch=arm64 --variant=minbase trixie` as the rootfs base,
scripted in `platform/rg35xx-h/rootfs/stage-userland.sh` and reproducibly
pinned by recording the installed package versions (`dpkg -l` manifest) into
the release SBOM.

## Amendment (2026-11-15, evidence-based)

The original bookworm pick failed at integration: the cross-built payload
requires GLIBC_2.38 (Ubuntu 24.04 toolchain), which bookworm's glibc 2.36
cannot satisfy — loader errors reproduced against a bookworm staging rootfs
(see `docs/test-results/wp2u-image.md`). Trixie (glibc ≥ 2.38) boots the full
stack under qemu-user. Revisit suite choice only if a trixie LTS/snapshot
issue forces it; snapshot.debian.org pinning stays a future upgrade.

## Rationale

- Simplest reliable option: provides glibc + systemd + apt (libasound2,
  wireless tools) with zero new toolchain work.
- Buildroot/Yocto would give tighter size control but are a second build
  universe to maintain; revisit only if image size or boot time forces it.
- Debian snapshot pinning (snapshot.debian.org) is kept as a future
  reproducibility upgrade; package-version manifest is honest for experimental.

## Consequences

- init = systemd; service units already written fit directly.
- Rootfs grows by ~150-250 MB; still fits the 2 GiB image comfortably.
- Next: userland integration workflow stages debootstrap output under mkrootfs,
  rebuilds both variants, re-runs QA E2E, compresses `.img.xz`.
