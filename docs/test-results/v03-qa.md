# v03 QA results (0.3.0-exp3): LEDs + panel DT

Date: 2026-11-16 10:48 UTC. Branch: `v03/qa`. Base commit: `200c6e1a780559671cf54d0a39b74b6a8788e820`.
Host: Linux x86_64.

Integrator input: prior result 1 (branch `v03/image` @ `cbf23fc8196e6fbee7b71d4edd688ba0cedb837e`,
images in `/tmp/sqz-v03/`).
Scope: QA-owned trees only (`tests/`, `scripts/`, `releases/`, `docs/test-results/`).
No other tree was modified; no images committed (policy: `*.img`/`*.img.xz` stay out of git).

v03 delta vs 0.2.0-exp2 under test: kernel DTB with the display pipeline
(patches 0001-0005: DE33/mixer/TCON/pwm/panel) + heartbeat LED trigger
(0006), `boot.scr` driving PI11 via `gpio set 267`, and
`/usr/lib/squeezebox/led.sh` with per-stage patterns.

## Summary

| Check | Status | Notes |
|---|---|---|
| image ddr3 (`check_image.py`) | PASS | 0 problems: GPT/SPL/boot-files/size/no-secrets clean |
| image ddr4 (`check_image.py`) | PASS | 0 problems, same shape as ddr3 |
| build-and-check (DDR3 via `IMAGE_UNDER_TEST`) | PASS | 6 PASS + arch NOT RUN |
| build-and-check (DDR4 via `IMAGE_UNDER_TEST`) | PASS | same counts as DDR3 |
| selftest (`tests/selftest.sh`) | PASS | 27 passed, 0 failed |
| arch | NOT RUN | no ELF in git tree (nothing built in-tree) |
| asound | PASS | `audio/alsa/asound.conf` syntax ok |
| mapping | PASS | `ui/input/rg35xxh.map` ok |
| skin | PASS | 2 skins, 167 PNGs + Lua compile ok |
| shellcheck | PASS | 41 scripts, `bash -n` fallback (shellcheck not installed) |
| repro-env | PASS | `SOURCE_DATE_EPOCH=1794823250` |
| DTB heartbeat + panel (in-image FAT extract) | PASS | led-1 heartbeat + anbernic panel/pwm-backlight/spi-gpio, FDT-parsed |
| boot.scr `gpio set 267` (in-image) | PASS | strings show the command; 1087 B both variants |
| led.sh in rootfs | PASS | 0755 root-owned, hash == repo == in-image manifest, both variants |
| led unit tests (`test-led.sh` from repo) | PASS | 11/11 |
| tests-in-rootfs disposition | PASS | not shipped by design (`mkrootfs.sh` installs 5 scripts only) |
| rootfs integrity (e2fsck + manifest) | PASS | fsck clean both; 11837-entry manifest; p2 diff superblock-only |
| boot partition (FAT) | PASS | byte-identical across variants and staging (`f9134521...`) |
| SPL/GPT variant diff | PASS | MBR+GPT identical; SPL eGON both, 24793 payload diffs (DDR3 vs DDR4) |
| dpkg manifest (141 pkgs, trixie) | PASS | same set + versions as 0.2.0-exp2, all `unpacked` by design |
| xz artifacts (`xz -T0 -6`) | PASS | 156.5 MiB each, `xz -t` ok, decompress hash == image hash |
| `releases/checksum.sh` create+verify | PASS | SHA256SUMS ok on staged `/tmp/rel-v03/` |
| `releases/MANIFEST.json` | PASS | 0.3.0-exp3, real names/sizes/sha256 + source pins filled |
| SBOM | NOT RUN | `releases/SBOM.json` covers 0.2.0-exp2; not regenerated for these images |
| hardware boot / H1-H18 / panel timings | NOT RUN | no RG35XX H hardware (sole external blocker) |

Totals — PASS: 23, NOT RUN: 3, BLOCKED: 0, FAIL: 0. (26 checks recorded.)

Status meanings: PASS ran green; NOT RUN has no target / does not apply on
this host / awaits hardware; BLOCKED names a missing tool, file, or device.

## Details

### image ddr3 — PASS

Target: `/tmp/sqz-v03/squeezebox-rg35xxh-ddr3.img` (2147483648 bytes,
sha256 `82fd269a3baceeda5359c23f5b644383ed59755ba7652af85633f13c9730cb9d` —
recomputed here, matches the integrator sidecar and prior result 1).

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

Target: `/tmp/sqz-v03/squeezebox-rg35xxh-ddr4.img` (2147483648 bytes,
sha256 `6c3247629b4e9d1973a8622b308cbc2aff9444af4376b44581637e334a326173` —
recomputed here, matches sidecar and prior result 1). Same output shape as
ddr3: 0 problems, PASS. The wp2u secrets false positive is gone: the gate
now requires base64 key material after a PEM header, and stock-OpenSSH
`.rodata` markers no longer trip it.

### build-and-check DDR3 — PASS

Command: `IMAGE_UNDER_TEST=/tmp/sqz-v03/squeezebox-rg35xxh-ddr3.img SOURCE_DATE_EPOCH=1794823250 bash scripts/build-and-check.sh --no-report`
(`SOURCE_DATE_EPOCH` from base commit `200c6e1`: `git log -1 --format=%ct`).

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

Same command with the ddr4 image: `result counts: {'NOT RUN': 1, 'PASS': 6}`
(only `arch` NOT RUN, rest PASS — identical breakdown to DDR3).

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
[shellcheck] checked 41 script(s) with bash -n (shellcheck not installed)
[RESULT] shellcheck: PASS
[repro:env] SOURCE_DATE_EPOCH=1794823250 ok
[RESULT] repro:env: PASS
```

### DTB heartbeat + panel (in-image) — PASS

Method: mount-free. p1 (`skip=32768 count=524288`) sliced with `dd` from
each image, then `DTB.IMG` + `BOOT.SCR` extracted with a small FAT32 reader
(cluster-chain walk; no mtools needed). No `fdtdump`/`dtc` on this host, so
the DTB was checked two independent ways: `strings` grep plus a minimal
FDT structure-block parser (token walk over the in-image bytes).

In-image DTB both variants: 32473 bytes,
sha256 `fc345c3fa0d56ecf33a0996d8123cab34077c955820c5614876f9a84e27bb087`
(magic `d00dfeed`, FDT v17, totalsize 32473; byte-identical to the
integrator staging `verify/dtb-ddr{3,4}.img`).

FDT structure parse (paths + properties that matter for v03):

```text
//leds :: compatible = gpio-leds
//leds/led-0 :: default-state = on            (gpios: bank 8 pin 12 = PI12 power)
//leds/led-1 :: linux,default-trigger = heartbeat   (gpios: bank 8 pin 11 = PI11 status)
//backlight :: compatible = pwm-backlight     (pwms: PWM0, period 50000 ns, active-high)
//regulator-gpio-lcd-vdd :: compatible = regulator-fixed
//spi :: compatible = spi-gpio
//spi/panel@0 :: compatible = anbernic,rg35xx-plus-panel
//spi/panel@0 :: spi-max-frequency = 3125000, reset-gpios PI14 active-low
```

`strings` corroboration: `heartbeat` + `linux,default-trigger`, `leds` /
`gpio-leds`, `tcon-top`, `sun8i-r40-tcon-lcd`, `sun50i-h616-de33`,
`mixer@100000`, `pwm-backlight`, `spi-gpio`, `vdd-lcd`, `lcd0-rgb888-pins`
all present. The literal `nv3052` appears 0 times — expected, not a gap:
the DTB carries the panel as compatible `anbernic,rg35xx-plus-panel`, which
the in-tree `panel-newvision-nv3052c.c` driver binds (see
`platform/rg35xx-h/device-tree/rg35xx-h-display-oot.dtsi`).

### boot.scr `gpio set 267` (in-image) — PASS

In-image `BOOT.SCR` both variants: 1087 bytes,
sha256 `3535ef2b66b15366deef359d83887d05e8298fa9f3125da590b60f1fc4478754`
(byte-identical to staging). `strings` shows the source script including:

```text
setenv bootargs 'console=ttyS0,115200n8 root=PARTUUID=0a1b2c3d-0002-... rootwait rw ...'
# Status LED (PI11 = U-Boot gpio 267) ON: U-Boot proper is alive and boot.scr
gpio set 267
load mmc 0:1 ${kernel_addr_r} Image
load mmc 0:1 ${fdt_addr_r} dtb.img
```

### led.sh in rootfs — PASS

p2 (`skip=557056 count=3637216`) sliced with `dd` from each image, inspected
with `debugfs` (unprivileged). `/usr/lib/squeezebox/` holds `led.sh` plus
`firstboot/splash/squeezeplay/wifi.sh` and `standalone/`:

```text
7516  100755 (1)      0      0    2384 16-Nov-2026 11:00 led.sh
```

`debugfs dump` of `/usr/lib/squeezebox/led.sh` from both images hashes
`6dec9e904c299433c45d8b4769e0b589b20d3ef29bec2f7d7c539f4e9d05c29f` —
identical to the repo `platform/rg35xx-h/services/led.sh` and to the
in-image `/manifest.sha256` entry. `/manifest.modes` records `-rwxr-xr-x`.
mtime `0x6afad452` = SDE 1794823250 (epoch clamp holds in-image).

### led unit tests — PASS (11/11)

`sh platform/rg35xx-h/services/tests/test-led.sh` from this tree:

```text
ok 1 - firstboot blinks 100/100
ok 2 - splash blinks 500/500
ok 3 - wifi blinks 1000/250
ok 4 - squeezeplay solid
ok 5 - ok is solid
ok 6 - fail strobes 50/50
ok 7 - bogus command exits 2
ok 8 - bogus stage exits 2
ok 9 - missing sysfs exits 0
ok 10 - missing sysfs fail exits 0
ok 11 - fallback *status* name works
---
pass=11 fail=0 total=11
```

### tests-in-rootfs disposition — PASS (not shipped, by design)

The in-image `/manifest.sha256` (11837 entries) contains no `test-led.sh`
or `services/tests` path (the 24 `test` substring hits are unrelated:
squeezeplay Test applets, kernel `*-test.ko` modules, `/usr/bin/test`,
`speaker-test`). `platform/rg35xx-h/rootfs/mkrootfs.sh` installs exactly
the 5 service scripts (`squeezeplay/splash/wifi/firstboot/led.sh`) — the
unit tests are host-run from the repo (11/11 above), never shipped.
Ship-blocker: no.

### rootfs integrity — PASS

- `e2fsck -n -f` on both extracted p2 filesystems: clean,
  `14298/113792 files, 195366/454651 blocks`, 0.1% non-contiguous.
- In-image `/manifest.sha256`: 11837 entries; `led.sh` entry verified
  against extracted bytes (see above).
- Raw p2 bytes differ first at byte 1073 (primary superblock). Whole-image
  `cmp -l` window map (see SPL/GPT section) confines every rootfs-region
  diff to the primary superblock windows (272-276 MiB) and 7-byte sparse
  backup-superblock pairs at 400/656/912/1168/1424 MiB — the known
  `mke2fs 1.47.0 < 1.47.1` per-variant timestamp artifact (assemble logs
  warn about it; file inodes/data/mtimes identical, e.g. `led.sh` bytes
  hash-equal across variants). Cosmetic, not a ship-blocker.

### boot partition — PASS

p1 slices from both images hash
`f913452193099e2dfb62e0d05f12ec24c1a2bdfaa0141f3cc25ad5525a62fb9e` —
byte-identical to each other and to both staging `verify/boot-ddr{3,4}.vfat`
files. FAT32 root: `BOOT.SCR` (1087 B), `IMAGE` (53901824 B), `DTB.IMG`
(32473 B). FAT volume id bytes `52 d4 fa 6a` (LE) = `0x6AFAD452` = SDE
1794823250, matching the assemble log (`volid 6AFAD452`).

### SPL/GPT variant diff — PASS

Whole-image `cmp -l` (2 GiB × 2), diff bytes by 1 MiB window:

```text
window-1MiB-0: 24793 diff-bytes      (SPL blob region)
window-1MiB-272..276: 390+20594+20792+20484+9658   (ext4 primary superblock)
window-1MiB-400/656/912/1168/1424: 7 each          (sparse backup superblocks)
total: 96746 diff bytes; every other window identical
```

First diff at byte 8205 (inside the SPL blob at sector 16; nothing differs
below byte 8192, so MBR + GPT primary header are identical). No diffs in
window 2 (GPT array LBA 4096) or the trailing backup-GPT window. Both SPLs
carry valid eGON magic (`16 00 00 ea 65 47 4f 4e 2e 42 54 30`); the 24793
payload diffs are the intended DDR3-vs-DDR4 DRAM blob (same count class as
0.2.0). Boot-partition and file-data regions: zero diffs.

### dpkg manifest — PASS

`/var/lib/dpkg/status` in the image (`debugfs dump`) lists 141 packages,
all `install ok unpacked` — expected for the rootless `--foreign` second
stage; maintainer scripts run on-device via firstboot (`dpkg --configure
-a`). Same set and versions as 0.2.0-exp2: `libc6 2.41-12+deb13u4`,
`libasound2t64 1.2.14-1+deb13u1`, `systemd 257.13-1~deb13u1`.

### xz artifacts — PASS

Compressed in `/tmp/sqz-v03/` with the specified flags
(`xz -T0 -6 -c img > img.xz`):

```text
164121664  squeezebox-rg35xxh-ddr3.img.xz  sha256 1fbbc433e73403ec4380c2a14e63422eb3861101c643372626b19427179eb11a
164120036  squeezebox-rg35xxh-ddr4.img.xz  sha256 85938d0160294404e9ec390621f0ac5a3a415b58480b204055c8b45df2019665
```

`xz -t` passes both; `xz -l` reports 156.5 MiB / 2048.0 MiB, ratio
0.076, CRC64; `xz -dc | sha256sum` reproduces the exact image hashes
(`82fd269a...`, `6c324762...`).

### checksum.sh create+verify — PASS

Staged `/tmp/rel-v03/` (hardlinked `.img` + `.img.xz` + `MANIFEST.json`
copy, no extra disk use); `bash releases/checksum.sh create` then `verify`:

```text
wrote /tmp/rel-v03/SHA256SUMS:
67bfa15145571c4e697c07be4c46220c39640073311fe36b891798f86070c494  MANIFEST.json
82fd269a3baceeda5359c23f5b644383ed59755ba7652af85633f13c9730cb9d  squeezebox-rg35xxh-ddr3.img
1fbbc433e73403ec4380c2a14e63422eb3861101c643372626b19427179eb11a  squeezebox-rg35xxh-ddr3.img.xz
6c3247629b4e9d1973a8622b308cbc2aff9444af4376b44581637e334a326173  squeezebox-rg35xxh-ddr4.img
85938d0160294404e9ec390621f0ac5a3a415b58480b204055c8b45df2019665  squeezebox-rg35xxh-ddr4.img.xz
MANIFEST.json: OK
squeezebox-rg35xxh-ddr3.img: OK
squeezebox-rg35xxh-ddr3.img.xz: OK
squeezebox-rg35xxh-ddr4.img: OK
squeezebox-rg35xxh-ddr4.img.xz: OK
```

Image hashes match the integrator sidecars and `releases/MANIFEST.json`.

### MANIFEST.json — PASS

`releases/MANIFEST.json` updated to version `0.3.0-exp3`, variant
`ddr3+ddr4`, `date_utc` 2026-11-16T10:48:37Z, `source_date_epoch`
1794823250 (from base commit `200c6e1`; corroborated by FAT volid
`6AFAD452` and in-image mtimes), `git_commit`
200c6e1a780559671cf54d0a39b74b6a8788e820, toolchain string (cross
tuple + trixie `--foreign` userland), `sources` pins (linux v7.3.4,
u-boot v2026.10, ATF v2.15.0, squeezeplay 758bc11, sdl12-compat
1.2.78, slimserver 9.0.2/1470c941, librespot v0.8.0, userland trixie
141 pkgs — each re-verified against `pins.env` +
`upstream-manifest.md` and the in-image dpkg status), four artifacts
with real size/sha256, validation pointers. `sbom` is null (see below).

### SBOM — NOT RUN

`releases/SBOM.json` in this tree is the draft for 0.2.0-exp2
(`image_git_commit d34314b...`); it was not regenerated for these
images, so the manifest honestly records `sbom: null` rather than
pointing at a stale artifact. Follow-up for Lead (see below).

### hardware boot / H1-H18 / panel timings — NOT RUN

No physical RG35XX H on this host. UART boot capture (SPL → U-Boot →
kernel → UI), the heartbeat→led.sh handoff on real PI11, panel
init/timings, DDR3 TPR, and the native first-boot `dpkg --configure -a`
run all await hardware. Sole external blocker — same as prior result 1.

## Unresolved / follow-ups (for Lead)

1. Hardware boot (carried from prior result 1): panel timings + DDR3 TPR
   stay HW-gated; UART log pending. Nothing further provable on this host.
2. SBOM: regenerate `releases/SBOM.json` for the 0.3.0-exp3 images
   (dpkg set is unchanged at 141 pkgs, so this is largely mechanical)
   and point the manifest `sbom` field at it.
3. Per-variant mkfs timestamps make raw `.img` bytes differ beyond the
   SPL blob (superblock copies only: 71953 of 96746 diff bytes; content
   identical). Cosmetic; a `SOURCE_DATE_EPOCH`-driven fixed mkfs time
   (mke2fs >= 1.47.1) would give byte-equal rootfs regions. Not a
   ship-blocker.

## How to reproduce

```sh
git checkout v03/qa            # this branch (base 200c6e1)
python3 tests/check_image.py /tmp/sqz-v03/squeezebox-rg35xxh-ddr3.img /tmp/sqz-v03/squeezebox-rg35xxh-ddr4.img
export SOURCE_DATE_EPOCH=$(git log -1 --format=%ct)
IMAGE_UNDER_TEST=/tmp/sqz-v03/squeezebox-rg35xxh-ddr3.img bash scripts/build-and-check.sh --no-report
IMAGE_UNDER_TEST=/tmp/sqz-v03/squeezebox-rg35xxh-ddr4.img bash scripts/build-and-check.sh --no-report
bash tests/selftest.sh
sh platform/rg35xx-h/services/tests/test-led.sh
bash releases/checksum.sh verify /tmp/rel-v03
```
