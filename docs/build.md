# Build

## Contract

- Target `aarch64-linux-gnu`, `-march=armv8-a+crc -mtune=cortex-a53`, glibc,
  `PREFIX=/opt/squeezeplay`, pinned container, `SOURCE_DATE_EPOCH`, SBOM.
- Pins: `docs/upstream-references/upstream-manifest.md`. Validate arch + `.so` deps
  against target sysroot (Ubuntu-built ARM64 ≠ firmware userspace until proven).

## Layout

- `build/toolchain/` — container + sysroot (Agent 2).
- `build/image/` — reproducible image assembly (Agent 1).
- `build/docker/` — Dockerfiles (Agent 1).
- `squeezeplay/upstream/` — vendored refs/notes only, no wholesale trees.

## Gates (Agent 6)

- `file` arch check, `readelf -d` NEEDED review, lint/shellcheck,
  rebuild-twice/diffoscope where feasible, sha256 per artifact.
