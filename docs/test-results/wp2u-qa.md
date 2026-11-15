# WP2 userland QA results (wp2u, 0.2.0-exp2)

Date: 2026-11-15 22:55 UTC. Branch: `wp2u/qa`. Base commit: `d34314b007fa3b7e26e34fec808ce99510276f27`.
Host: Linux x86_64.

Integrator input: prior result 1 (branch `wp2u/image` @ `b8df06b2e8d26222f46b4953004fd48f927b2f66`,
images in `/tmp/sqz-userland/`).
Scope: QA-owned trees only (`tests/`, `scripts/`, `releases/`, `docs/test-results/`).
No other tree was modified; no images committed (policy: `*.img`/`*.img.xz` stay out of git).

## Summary

| Check | Status | Notes |
|---|---|---|
| image ddr3 (`check_image.py`) | FAIL* | all structural probes PASS; secrets FAIL is a proven false positive (see below) |
| image ddr4 (`check_image.py`) | FAIL* | same disposition as ddr3 |
| image both-together | FAIL* | 2 targets, 16 problems, all the same FP marker |
| build-and-check (DDR3 via `IMAGE_UNDER_TEST`) | FAIL* | 5 PASS + arch NOT RUN; only image/secrets FAILs |
| build-and-check (DDR4 via `IMAGE_UNDER_TEST`) | FAIL* | same counts as DDR3 |
| selftest (`tests/selftest.sh`) | PASS | 27 passed, 0 failed |
| arch | NOT RUN | no ELF in git tree (nothing built in-tree) |
| asound | PASS | `audio/alsa/asound.conf` syntax ok |
| mapping | PASS | `ui/input/rg35xxh.map` ok |
| skin | PASS | 2 skins, PNGs + Lua compile ok |
| shellcheck | PASS | 34 scripts, `bash -n` fallback (shellcheck not installed) |
| repro-env | PASS | `SOURCE_DATE_EPOCH=1794780954` |
| userland init+systemd+libasound | PASS | `/sbin/init` -> systemd, `libasound.so.2.0.0`, aarch64 ELFs |
| dpkg manifest (141 pkgs, trixie) | PASS | captured in `wp2u-dpkg-manifest.txt`; all `unpacked` by design |
| systemd wiring (getty/ssh/timesyncd/units) | PASS | 8/8 `.wants` symlinks resolve in-tree; firstboot unit+script present+x |
| no-secrets disposition | PASS | FP proven at binary level; 0 key files, locked shadow, 0 token hits |
| rootfs integrity (e2fsck + manifest) | PASS | fsck clean both; in-image manifest verifies; trees content-identical |
| boot partition (FAT listing) | PASS | BOOT.SCR/IMAGE/DTB.IMG both variants, byte-identical partitions |
| SPL/GPT variant diff | PASS | GPT identical; only SPL blob differs (intended DDR3 vs DDR4) |
| size gate (+ negative probe) | PASS | 2048 MiB within 512-8192; `--max-mb 1024` FAILs as expected |
| xz artifacts (`xz -T0 -6`) | PASS | 156.5 MiB each, `xz -t` ok, decompress hash == image hash |
| `releases/checksum.sh` create+verify | PASS | SHA256SUMS ok on staged `/tmp/rel-wp2u/` |
| `releases/MANIFEST.json` | PASS | 0.2.0-exp2, real names/sizes/sha256 + source pins filled |
| SBOM | NOT RUN | no SBOM artifact exists; manifest `sbom` is null |
| hardware boot / H1-H18 / firstboot dpkg-configure | NOT RUN | no RG35XX H hardware (sole external blocker) |

Totals — PASS: 17, FAIL*: 5 (one root cause: stock-OpenSSH-marker false positive),
NOT RUN: 3, BLOCKED: 0. (25 checks recorded.)

`*FAIL` keeps the harness vocabulary honest: the gate exited 1, and the QA
disposition (proven below) is "false positive, ship-blocker: no". The gate file
itself is deliberately untouched; a follow-up may teach `check_image.py` to
require key material between BEGIN/END markers (see Unresolved).

Status meanings:

- PASS — the check ran and all targets satisfied it.
- FAIL — the check ran and at least one target violated it (must fix or disposition).
- NOT RUN — no targets exist yet, or the gate does not apply on this host.
- BLOCKED — a required tool, file, or device is missing (name it).

## Details

### image ddr3 — FAIL* (false positive, see disposition)

Target: `/tmp/sqz-userland/squeezebox-rg35xxh-ddr3.img` (2147483648 bytes,
sha256 `7a1fc07c1ef65b0abdadc6c90f11f9b1dc70dbc30767fd7dcc70adc193bdccd0` —
recomputed here, matches integrator sidecar and prior result 1).

```text
[image] protective MBR ok (0xEE, boot sig)
[image] GPT primary header CRC ok
[image] GPT array at sunxi LBA 4096 ok
[image] GPT primary array CRC ok
[image] p1 BOOT: 32768..557055 ok
[image] p2 ROOTFS: 557056..4194271 ok
[image] GPT backup header ok
[image] SPL blob present at sector 16
[image] boot file present: BOOT.SCR
[image] boot file present: IMAGE
[image] boot file present: DTB.IMG
[image] checked 1 target(s), 8 problem(s)
[image] PROBLEM: squeezebox-rg35xxh-ddr3.img: possible secret (PEM private key header)  (x8)
[RESULT] image: FAIL
```

### image ddr4 — FAIL* (false positive, see disposition)

Target: `/tmp/sqz-userland/squeezebox-rg35xxh-ddr4.img` (2147483648 bytes,
sha256 `c388cbf16518ce026d75ea6ad08e8e7c5259c9e2c4c45cf245d3f07d4a55f5a1` —
recomputed here, matches sidecar and prior result 1). Same output shape as
ddr3: all structural probes PASS, 8x PEM-marker problems, FAIL.

### image both-together — FAIL* (same cause)

Command: `python3 tests/check_image.py /tmp/sqz-userland/squeezebox-rg35xxh-ddr3.img /tmp/sqz-userland/squeezebox-rg35xxh-ddr4.img`

```text
[image] checked 2 target(s), 16 problem(s)
[RESULT] image: FAIL
```

All 16 problems are the PEM-marker hit (8 per image, one per 1 MiB scan
chunk containing a marker); no structural problem on either target.

### no-secrets disposition — PASS (false positive proven)

Independent byte scan finds 22 `BEGIN OPENSSH PRIVATE KEY` markers in the
ddr3 image; every one is immediately followed by the bare END marker with
zero key material between them, e.g. (offset 397966320):

```text
...%s%02x\x00\x00-----BEGIN OPENSSH PRIVATE KEY-----\n\x00\x00\x00\x00-----END OPENSSH PRIVATE KEY-----\n...
```

Tree-mode scan (`python3 tests/check_image.py /tmp/qa-rdump3`, a debugfs
rdump of image p2) pins every hit to stock OpenSSH binaries only:
`usr/sbin/sshd`, `usr/bin/ssh`, `ssh-keygen`, `ssh-agent`, `ssh-add`,
`ssh-keyscan`, `usr/lib/openssh/ssh-keysign`, `ssh-pkcs11-helper`,
`ssh-sk-helper`, `sshd-auth`, `sshd-session`. Direct dump of the marker in
`usr/sbin/sshd` shows adjacent BEGIN/END format strings (`.rodata`), and
`strings` lists them on consecutive lines (1459/1460) — a real key would
carry base64 between them. Corroboration:

- `grep -c` for AWS/GH/Slack token patterns over the raw image: `0`.
- Key-file hunt over the extracted tree (`*id_rsa*`, `*id_ed25519*`,
  `*.pem`, `*.key`): sole hit is `/usr/lib/ssl/cert.pem`, the public CA
  bundle (`-----BEGIN CERTIFICATE-----`).
- `/etc/ssh/` ships no host keys (only `moduli`, `ssh_config`, config
  snippets); host keys are generated on-device by firstboot (`ssh-keygen
  -A`, see below).
- `/etc/shadow`: all 18 accounts `*` (locked, no password hash).
- `grep -rE` for key/token patterns over `etc/ root/ home/ opt/
  usr/lib/squeezebox/ var/`: no matches.

Disposition: FAIL is a gate-heuristic true hit on a non-secret (OpenSSH
ships its own PEM delimiters as format strings). Ship-blocker: no.

### build-and-check DDR3 — FAIL* (image FP only)

Command: `IMAGE_UNDER_TEST=/tmp/sqz-userland/squeezebox-rg35xxh-ddr3.img SOURCE_DATE_EPOCH=1794780954 bash scripts/build-and-check.sh --no-report`

```text
--- gate: arch ---
gate arch: NOT RUN
--- gate: asound ---
gate asound: PASS
--- gate: mapping ---
gate mapping: PASS
--- gate: skin ---
gate skin: PASS
--- gate: image ---
gate image: FAIL (exit 1)
--- gate: shellcheck ---
gate shellcheck: PASS
--- gate: repro-env ---
gate repro-env: PASS
--- summary ---
result counts: {'NOT RUN': 1, 'PASS': 5, 'FAIL': 1}
```

(`repro-env` FAILs without `SOURCE_DATE_EPOCH` exported, as designed; the
recorded run exports `SDE=1794780954` from base commit `d34314b`.)

### build-and-check DDR4 — FAIL* (image FP only)

Command: `IMAGE_UNDER_TEST=/tmp/sqz-userland/squeezebox-rg35xxh-ddr4.img ... bash scripts/build-and-check.sh --no-report`

```text
result counts: {'NOT RUN': 1, 'PASS': 5, 'FAIL': 1}
```

(Same per-gate breakdown as DDR3: only `arch` NOT RUN and `image` FAIL*
on the secrets false positive, rest PASS.)

### selftest — PASS

```text
selftest: 27 passed, 0 failed
```

### arch — NOT RUN

```text
[arch] no ELF binaries under build, platform, squeezeplay, standalone, ui, audio (nothing built yet)
[RESULT] arch: NOT RUN
```

Expected on a clean tree: no built ELF is committed to git.

### asound / mapping / skin / shellcheck / repro-env — PASS

```text
[asound] audio/alsa/asound.conf: syntax ok
[asound] checked 2 file(s), 0 failed
[RESULT] asound: PASS
[mapping] ui/input/rg35xxh.map: mapping ok
[mapping] checked 1 file(s), 0 failed
[RESULT] mapping: PASS
[skin] ui/skins/RG35XXHLandscapeSkin: 167 PNG(s) checked, 167 ok (11 oversize-but-legal)
[skin] ui/skins/RG35XXHLandscapeSkin: 2 Lua file(s) compile ok
[skin] checked 2 skin(s), 0 failed
[RESULT] skin: PASS
[shellcheck] checked 34 script(s) with bash -n (shellcheck not installed)
[RESULT] shellcheck: PASS
[repro:env] SOURCE_DATE_EPOCH=1794780954 ok
[RESULT] repro:env: PASS
```

### userland init+systemd+libasound — PASS

Mount-free rootfs inspection: p2 (`skip=557056 count=3637216`) extracted
with `dd` from each image, then listed with `debugfs` (`rdump`, unprivileged).
DDR3 tree:

```text
/sbin/init -> ../lib/systemd/systemd
/lib/systemd/systemd: ELF 64-bit LSB pie executable, ARM aarch64 (133584 bytes)
/lib/aarch64-linux-gnu/libasound.so.2 -> libasound.so.2.0.0 (1182272 bytes)
/opt/squeezeplay/bin/jive: ELF 64-bit LSB pie executable, ARM aarch64
/etc/os-release: Squeezebox RG35XX H (0.2.0-exp2)
```

(`/lib` is a symlink to `usr/lib`; merged-usr paths resolve identically.)

### dpkg manifest — PASS

`/var/lib/dpkg/status` in the image lists 141 packages, all
`install ok unpacked` — expected for the rootless `--foreign` second stage;
maintainer scripts run on-device via firstboot (`dpkg --configure -a`).
Full `name=version arch` list captured in
[wp2u-dpkg-manifest.txt](wp2u-dpkg-manifest.txt). Spot versions (trixie):
`libc6 2.41-12+deb13u4`, `systemd 257.13-1~deb13u1`, `libasound2t64
1.2.14-1+deb13u1`, `openssh-server/client 1:10.0p1-7+deb13u4`, `dpkg
1.22.22`, `base-files 13.8+deb13u7`, `udev 257.13-1~deb13u1`.

### systemd wiring — PASS

All 8 `.wants` symlinks resolve to unit files present in the image:

```text
getty@tty1.service -> /usr/lib/systemd/system/getty@.service [OK]
serial-getty@ttyS0.service -> /usr/lib/systemd/system/serial-getty@.service [OK]
systemd-timesyncd.service -> /usr/lib/systemd/system/systemd-timesyncd.service [OK]
splash/squeezebox-firstboot/squeezeplay/ssh/wifi -> /usr/lib/systemd/system/*.service [OK]
```

`squeezebox-firstboot.service` (`Before=ssh/wifi/squeezeplay`,
`ConditionPathExists=!/var/lib/squeezebox/firstboot-done`) runs
`/usr/lib/squeezebox/firstboot.sh` (present, mode 755), which does
`dpkg --configure -a`, then `ssh-keygen -A`, then stamps
`/var/lib/squeezebox/firstboot-done`; re-runs are no-ops. `squeezeplay.service`
handoff (`ExecStartPre=-/opt/squeezeplay/bin/init-splash.sh stop`, both
scripts present +x) and `DeviceAllow` for input/DRM/ALSA/tty1 verified
present. First-boot execution itself is device-only: NOT RUN.

### rootfs integrity — PASS

- `e2fsck -n -f` on both extracted p2 filesystems: clean, `14295/113792
  files, 195376/454651 blocks`, 0.1% non-contiguous.
- In-image `/manifest.sha256` (11834 entries) spot-verified against
  extracted bytes (`etc/adduser.conf`, `etc/apt/sources.list`: match).
- Full content comparison DDR3 vs DDR4 trees: 11836 regular files
  hash-identical, 731 symlinks target-identical (`TREES-IDENTICAL`,
  `LINKS-IDENTICAL`). (11836 = 11834 manifest entries + the two manifest
  files themselves, written after manifest generation.)
- Raw p2 bytes differ in 73620 bytes confined to the primary + sparse
  backup superblocks (1 MiB windows at image offsets 272-276/400/656/912/
  1168/1424): single low-byte `0xd7 <-> 0xca` timestamp pairs (13 s =
  the 13 s mkfs gap, 23:40:10 vs 23:40:23) plus metadata checksums.
  All file inodes/data/mtimes identical (e.g. `etc/hostname`
  ctime/atime/mtime equal in both). Benign per-variant mkfs artifact.

### boot partition — PASS

p1 (`skip=32768 count=524288`) extracted from both images: sha256
`bf865abeb97a55db86a6ba570b663af718e64de9d701c15e531d2cfa13992b81`
(both, byte-identical). FAT32 root: `BOOT.SCR` (849 B), `IMAGE`
(53901824 B), `DTB.IMG` (28301 B) — matches the gate's listing.

### SPL/GPT variant diff — PASS

Whole-image diff (1 MiB windows): only windows 0 (SPL gap), 272-276
(primary superblock), and the backup-superblock windows differ. GPT
primary header (LBA 1) and array (LBA 4096..4223) are byte-identical
between variants; the MBR is identical; SPL region (sectors 16..90)
carries valid eGON magic (`16 00 00 ea 65 47 4f 4e`) in both with
differing payload bytes = the intended DDR3-vs-DDR4 DRAM blob.
Rootfs/boot content otherwise identical (see above).

### size gate + negative probe — PASS

Both images are 2147483648 bytes (2048.0 MiB), inside the default
512-8192 MiB window. Negative control trips correctly:

```text
$ python3 tests/check_image.py --max-mb 1024 /tmp/sqz-userland/squeezebox-rg35xxh-ddr3.img
[image] PROBLEM: image 2048.0 MiB > max 1024.0 MiB
[RESULT] image: FAIL
```

### xz artifacts — PASS

Compressed in `/tmp/sqz-userland/` with the specified flags
(`xz -T0 -6 -c img > img.xz`); byte-identical to the integrator's
pre-existing `.xz` (kept copy compared with `cmp`, then removed):

```text
164128224  squeezebox-rg35xxh-ddr3.img.xz  sha256 32a8e60328fc599d1135683d9d2f94d59fdb77eafc2f947191d267a0bc620771
164128068  squeezebox-rg35xxh-ddr4.img.xz  sha256 65d65c18392b52a78d67d23f7aa3c93d9d3a70fdc9b3cd7b4a8ef8f7010c37a5
```

`xz -t` passes both; `xz -l` reports 156.5 MiB / 2048.0 MiB, ratio
0.076, CRC64; `xz -dc | sha256sum` reproduces the exact image hashes
(`7a1fc07c...`, `c388cbf1...`).

### checksum.sh create+verify — PASS

Staged `/tmp/rel-wp2u/` (hardlinked `.img` + `.img.xz` + `MANIFEST.json`
copy, no extra disk use); `bash releases/checksum.sh create` then `verify`:

```text
wrote /tmp/rel-wp2u/SHA256SUMS:
79824eb309401cb69cad45f4b11c32f460a71e174e3d5971e321861795a1f3c8  MANIFEST.json
7a1fc07c1ef65b0abdadc6c90f11f9b1dc70dbc30767fd7dcc70adc193bdccd0  squeezebox-rg35xxh-ddr3.img
32a8e60328fc599d1135683d9d2f94d59fdb77eafc2f947191d267a0bc620771  squeezebox-rg35xxh-ddr3.img.xz
c388cbf16518ce026d75ea6ad08e8e7c5259c9e2c4c45cf245d3f07d4a55f5a1  squeezebox-rg35xxh-ddr4.img
65d65c18392b52a78d67d23f7aa3c93d9d3a70fdc9b3cd7b4a8ef8f7010c37a5  squeezebox-rg35xxh-ddr4.img.xz
MANIFEST.json: OK
squeezebox-rg35xxh-ddr3.img: OK
squeezebox-rg35xxh-ddr3.img.xz: OK
squeezebox-rg35xxh-ddr4.img: OK
squeezebox-rg35xxh-ddr4.img.xz: OK
```

Image hashes match the integrator sidecars and `releases/MANIFEST.json`.

### MANIFEST.json — PASS

`releases/MANIFEST.json` updated to version `0.2.0-exp2`, variant
`ddr3+ddr4`, `date_utc` 2026-11-15T22:55:00Z, `source_date_epoch`
1794780954 (from base commit `d34314b`), `git_commit`
d34314b007fa3b7e26e34fec808ce99510276f27, toolchain string (cross
tuple + trixie `--foreign` userland), `sources` pins (linux v7.3.4,
u-boot v2026.10, ATF v2.15.0, squeezeplay 758bc11, sdl12-compat
1.2.78, slimserver 9.0.2/1470c941, librespot v0.8.0, userland trixie
141 pkgs), four artifacts with real size/sha256, validation pointers.
`sbom` is null (no SBOM artifact exists) — NOT RUN, not faked.

### SBOM — NOT RUN

No SBOM file exists in the tree or staging dir; no gate produces one.

### hardware boot / H1-H18 / firstboot dpkg-configure — NOT RUN

No physical RG35XX H on this host. UART boot capture, panel, evtest/ALSA
probes, DDR-ID/TPR, and the native first-boot `dpkg --configure -a` +
`ssh-keygen -A` run all await hardware. Sole external blocker.

## Unresolved / follow-ups (for Lead)

1. `check_image.py` secrets heuristic vs stock OpenSSH: every trixie
   userland image will FAIL the gate on OpenSSH's own BEGIN/END format
   strings. Follow-up (QA-owned `tests/`): require base64 key material
   between BEGIN and END markers (or exempt matches immediately followed
   by the END delimiter). Gate deliberately untouched in this pass so the
   FAIL* disposition above stays reviewable.
2. ADR-0004 suite amendment (bookworm -> trixie), carried from prior
   result 1: payload requires GLIBC_2.38; needs Lead decision.
3. Per-variant mkfs timestamps make raw `.img` bytes differ beyond the
   SPL blob (superblock copies only; content identical). Cosmetic;
   a fixed `-E mkfs_time` / `SOURCE_DATE_EPOCH`-driven mkfs would give
   byte-equal rootfs regions. Not a ship-blocker.

## How to reproduce

```sh
git checkout wp2u/qa            # this branch (base d34314b)
python3 tests/check_image.py /tmp/sqz-userland/squeezebox-rg35xxh-ddr3.img /tmp/sqz-userland/squeezebox-rg35xxh-ddr4.img
export SOURCE_DATE_EPOCH=$(git log -1 --format=%ct)
IMAGE_UNDER_TEST=/tmp/sqz-userland/squeezebox-rg35xxh-ddr3.img bash scripts/build-and-check.sh --no-report
IMAGE_UNDER_TEST=/tmp/sqz-userland/squeezebox-rg35xxh-ddr4.img bash scripts/build-and-check.sh --no-report
bash tests/selftest.sh
bash releases/checksum.sh verify /tmp/rel-wp2u
```
