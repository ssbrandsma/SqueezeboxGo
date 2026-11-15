# WP2 merged-image QA results (wp2int)

Date: 2026-11-15 22:14 UTC. Branch: `wp2int/qa`. Base commit: `910d95579271fbee4d7f68a71597b4ce82190228`.
Host: `DESKTOP-OVMHVD2` (Linux x86_64, WSL2).

Integrator input: prior result 1 (branch `wp2int/image`, images in `/tmp/sqz-merged/`).
Scope: QA-owned trees only (`tests/`, `scripts/`, `releases/`, `docs/test-results/`).
No other tree was modified; no images committed (policy: `*.img` stays out of git).

## Summary

| Check | Status | Notes |
|---|---|---|
| image ddr3 (`check_image.py`) | PASS | GPT/FAT/SPL/boot-files/secrets/size, 2048.0 MiB |
| image ddr4 (`check_image.py`) | PASS | GPT/FAT/SPL/boot-files/secrets/size, 2048.0 MiB |
| image both-together | PASS | 2 targets, 0 problems |
| build-and-check (DDR3 via `IMAGE_UNDER_TEST`) | PASS | 6 PASS + arch NOT RUN |
| build-and-check (DDR4 via `IMAGE_UNDER_TEST`) | PASS | 6 PASS + arch NOT RUN |
| selftest (`tests/selftest.sh`) | PASS | 27 passed, 0 failed |
| arch | NOT RUN | no ELF in git tree (nothing built in-tree) |
| asound | PASS | `audio/alsa/asound.conf` syntax ok |
| mapping | PASS | `ui/input/rg35xxh.map` ok |
| skin | PASS | 2 Lua skins, 467 PNGs ok |
| shellcheck | PASS | 33 scripts, `bash -n` fallback (shellcheck not installed) |
| repro-env | PASS | `SOURCE_DATE_EPOCH=1794777651` |
| no-secrets (gate + independent grep) | PASS | gate clean both images; grep 0 hits on ddr3 |
| size gate (+ negative probe) | PASS | 2048 MiB within 512–8192; `--max-mb 1024` FAILs as expected |
| `releases/checksum.sh` create+verify | PASS | SHA256SUMS ok on staged `/tmp/rel-wp2int/` |
| `releases/MANIFEST.json` | PASS | real names/sizes/sha256 + source pins filled |
| SBOM | NOT RUN | no SBOM artifact exists; manifest `sbom` is null |
| hardware boot / H1–H18 | NOT RUN | no RG35XX H hardware (sole external blocker) |

Totals — PASS: 15, FAIL: 0, NOT RUN: 3, BLOCKED: 0.

Status meanings:

- PASS — the check ran and all targets satisfied it.
- FAIL — the check ran and at least one target violated it (must fix).
- NOT RUN — no targets exist yet, or the gate does not apply on this host.
- BLOCKED — a required tool, file, or device is missing (name it).

## Details

### image ddr3 — PASS

Target: `/tmp/sqz-merged/squeezebox-rg35xxh-ddr3.img` (2147483648 bytes)

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
[image] no-secrets scan clean
[image] checked 1 target(s), 0 problem(s)
[RESULT] image: PASS
```

### image ddr4 — PASS

Target: `/tmp/sqz-merged/squeezebox-rg35xxh-ddr4.img` (2147483648 bytes)

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
[image] no-secrets scan clean
[image] checked 1 target(s), 0 problem(s)
[RESULT] image: PASS
```

### image both-together — PASS

Command: `python3 tests/check_image.py /tmp/sqz-merged/squeezebox-rg35xxh-ddr3.img /tmp/sqz-merged/squeezebox-rg35xxh-ddr4.img`

```text
[image] checked 2 target(s), 0 problem(s)
[RESULT] image: PASS
```

### build-and-check DDR3 — PASS

Command: `IMAGE_UNDER_TEST=/tmp/sqz-merged/squeezebox-rg35xxh-ddr3.img SOURCE_DATE_EPOCH=1794777651 bash scripts/build-and-check.sh --no-report`

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
gate image: PASS
--- gate: shellcheck ---
gate shellcheck: PASS
--- gate: repro-env ---
gate repro-env: PASS
--- summary ---
result counts: {'NOT RUN': 1, 'PASS': 6}
```

### build-and-check DDR4 — PASS

Command: `IMAGE_UNDER_TEST=/tmp/sqz-merged/squeezebox-rg35xxh-ddr4.img ... bash scripts/build-and-check.sh --no-report`

```text
result counts: {'NOT RUN': 1, 'PASS': 6}
```

(Same per-gate breakdown as DDR3: only `arch` NOT RUN, rest PASS.)

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
[skin] ui/skins/RG35XXHBaseSkin: 300 PNG(s) checked, 300 ok (16 oversize-but-legal)
[skin] ui/skins/RG35XXHLandscapeSkin: 167 PNG(s) checked, 167 ok (11 oversize-but-legal)
[skin] checked 2 skin(s), 0 failed
[RESULT] skin: PASS
[shellcheck] checked 33 script(s) with bash -n (shellcheck not installed)
[RESULT] shellcheck: PASS
[repro:env] SOURCE_DATE_EPOCH=1794777651 ok
[RESULT] repro:env: PASS
```

### no-secrets corroboration — PASS

Independent of the gate's scan (which reported clean on both images):

```text
$ LC_ALL=C grep -c -a -E 'BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{20,}' /tmp/sqz-merged/squeezebox-rg35xxh-ddr3.img
0
```

0 matches (grep exit 1 = no match).

### size gate + negative probe — PASS

Both images are 2147483648 bytes (2048.0 MiB), inside the default
512–8192 MiB window. Negative control trips correctly:

```text
$ python3 tests/check_image.py --max-mb 1024 /tmp/sqz-merged/squeezebox-rg35xxh-ddr3.img
[image] PROBLEM: image 2048.0 MiB > max 1024.0 MiB
[RESULT] image: FAIL
```

### checksum.sh create+verify — PASS

Staged `/tmp/rel-wp2int/` (hardlinked images + `MANIFEST.json`, no extra
disk use); `bash releases/checksum.sh create` then `verify`:

```text
wrote /tmp/rel-wp2int/SHA256SUMS:
16d0e50219e3d4014ba3b3f124be708bd9ee99cb4492775842fe8e1f2e92b61f  MANIFEST.json
82b3de0a7fb59f7b66586cbba63071ab07d08065a41c20ab26999c9a9146ba25  squeezebox-rg35xxh-ddr3.img
380be5770fe7146d25896935bf8d802649fd32e3f4630679e4cd961ff1da2187  squeezebox-rg35xxh-ddr4.img
MANIFEST.json: OK
squeezebox-rg35xxh-ddr3.img: OK
squeezebox-rg35xxh-ddr4.img: OK
```

Image hashes match the integrator sidecars (`sha256sum -c` on both
`.sha256` files: OK) and `releases/MANIFEST.json`.

### MANIFEST.json — PASS

`releases/MANIFEST.json` filled from `MANIFEST.example.json`:
version `0.1.0-exp1`, variant `ddr3+ddr4`, `date_utc`
2026-11-15T22:13:51Z, `source_date_epoch` 1794777651,
`git_commit` 910d95579271fbee4d7f68a71597b4ce82190228, toolchain string,
`sources` pins (linux v7.3.4, u-boot v2026.10, ATF v2.15.0, squeezeplay
758bc11, sdl12-compat 1.2.78, slimserver 9.0.2/1470c941, librespot
v0.8.0), both artifacts with real size/sha256, validation pointers.
`sbom` is null (no SBOM artifact exists) — NOT RUN, not faked.

### SBOM — NOT RUN

No SBOM file exists in the tree or staging dir; no gate produces one.

### hardware boot / H1–H18 — NOT RUN

No physical RG35XX H on this host. Carried over from the integrator:
UART boot capture, panel, evtest/ALSA probes, DDR-ID/TPR all await hardware.

## How to reproduce

```sh
git checkout wp2int/qa            # this branch (base 910d955)
python3 tests/check_image.py /tmp/sqz-merged/squeezebox-rg35xxh-ddr3.img /tmp/sqz-merged/squeezebox-rg35xxh-ddr4.img
export SOURCE_DATE_EPOCH=$(git log -1 --format=%ct)
IMAGE_UNDER_TEST=/tmp/sqz-merged/squeezebox-rg35xxh-ddr3.img bash scripts/build-and-check.sh --no-report
IMAGE_UNDER_TEST=/tmp/sqz-merged/squeezebox-rg35xxh-ddr4.img bash scripts/build-and-check.sh --no-report
bash tests/selftest.sh
bash releases/checksum.sh verify /tmp/rel-wp2int
```
