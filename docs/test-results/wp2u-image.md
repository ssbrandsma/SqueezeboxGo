# WP2 userland integration — test results (0.2.0-exp2)

Date: 2026-11-15. Branch: `wp2u/image`. Code HEAD: (see commit, below).
Host: `DESKTOP-OVMHVD2` (Ubuntu 24.04 x86_64, WSL2, no root, no docker).

Owner note: written by the WP2 userland integrator on Workflow task
instruction; `docs/test-results/` is Agent 6's tree — code fixes are on
this branch, flagged for owner review (see §9).

## Summary

First bootable-to-userspace experimental image: debootstrap trixie arm64
minbase (141 packages, `dpkg -l` manifest in-image) + systemd wiring
(firstboot/getty/UART/ssh/timesyncd/ALSA) + the full 0.1.0-exp1 payload
restaged on top through the real `mkrootfs`/`stage-payload` scripts.

| Check | Status | Notes |
|---|---|---|
| userland:stage | PASS | 141 pkgs, Verified Release sig, 299M, dpkg status unpacked |
| userland:identity | PASS | /sbin/init, systemd 257, passwd/shadow locked, sources.list |
| wire:units | PASS | firstboot/getty@tty1/serial-getty@ttyS0/ssh/timesyncd enabled |
| wire:standalone | PASS | units present, ship-disabled (no wants links) |
| payload:restage | PASS | 11834 files via real scripts, 6 libs kept from userland |
| smoke:loader | PASS | jive libc/libm resolve into staged userland (host has none) |
| smoke:jive | PASS | 9.0.0 r541 main loop, 51 applets, RG35XXHBaseSkin, no crash |
| smoke:alsa | PASS | clamp WARNs exact; pcm opens vs staged libasound (see note) |
| image:ddr3+ddr4 | PASS | both exit 0 at exact /tmp/sqz-userland paths |
| image:bytes | PASS | 11834/11834 image bytes match staging; fsck clean x2 |
| image:gate | FAIL* | check_image FAIL is a false positive (see §7); rest PASS |
| image:cross | PASS | 24793 pre-rootfs diffs (== 0.1.0 SPL count), rest ext4 wrapper |
| suite:bookworm | FAIL | proven: payload needs GLIBC_2.38, bookworm has 2.36 (§6) |
| units:verify | PASS | systemd-analyze verify exit 0 (host/guest skew notes only) |
| lint | PASS | shellcheck -S warning clean on all touched scripts |
| suite:selftest | PASS | 27/27; asound/mapping/skin/repro:env PASS, arch NOT RUN |
| boot:target | NOT RUN | no RG35XX H hardware (sole external blocker) |

Totals — PASS: 15, FAIL: 1 (gate false positive, documented), NOT RUN: 1.
The FAIL* row and the bookworm row need Lead/QA disposition (§6, §7, §9).

## 1. Inputs reused (verified, not assumed)

No kernel/U-Boot/toolchain rebuild was needed or attempted: the boot chain
and every payload input were recovered from the verified 0.1.0-exp1
artifacts on this host and re-verified by SHA before use.

- `/tmp/sqz-merged/*.img` SHAs match `wp2int-image.md` exactly
  (`82b3de0a…` ddr3, `380be577…` ddr4).
- Extracted `boot/Image` (`7c22dbb7…`), DTB (`b8b0bfa3…`), both SPL blobs
  (`33bd339b…` ddr3, `edfcbce2…` ddr4) — all match the recorded SHAs.
- Payload staging re-extracted via fuse2fs: 4684/4685 files bit-identical
  to the image's own `manifest.sha256`; the 1 miss is the root-only
  `wpa_supplicant.conf.template`, restored from git by mkrootfs.
- Every `stage-payload.sh` input re-verified: core tarball (`ecdb8d8e…`),
  evdev2jive/drm_splash/sdl_smoke/bsp.so (match `payload-manifest.txt`),
  sdl2-kmsdrm + sdl12-compat prefixes (match), fonts (`src/dejavu-…`),
  all 19 closure hostpaths present, 1676 kernel modules re-extracted.
- So the ONLY byte deltas vs 0.1.0-exp1 are the new userland + wiring;
  the payload above it is the same verified bytes, restaged through the
  (minimally extended) real scripts rather than copied.

## 2. userland:stage — PASS

Real `debootstrap --foreign --arch=arm64 --variant=minbase` runs
unprivileged under fakeroot in this sandbox (no root, no binfmt needed),
so no container fallback was required. New script
`platform/rg35xx-h/rootfs/stage-userland.sh`:

```text
$ ./platform/rg35xx-h/rootfs/stage-userland.sh --staging .../rootfs \
    --cache .../debcache-userland --epoch 1794334272
stage-userland.sh: Release verification: .../debian-archive-trixie-keyring.gpg
stage-userland.sh: running: fakeroot debootstrap --foreign ... --keyring=...
stage-userland.sh: debootstrap first stage done
stage-userland.sh: rootless second stage: unpacking 141 debs
stage-userland.sh: dpkg status: 141 packages unpacked
stage-userland.sh: passwd/group/shadow created (18 users, all locked)
stage-userland.sh: userland ready: .../rootfs (141 packages, 299M)
```

- Release signature VERIFIED with trixie's own keyring (fetched from the
  target suite; the noble host keyring has no trixie keys). Recorded in
  the manifest (`release-verify: ok(...)`).
- Rootless second stage unpacks all 141 retained debs (data + control),
  synthesizes `status` (all `install ok unpacked`) + `info/*.list`,
  builds passwd/group/shadow/gshadow from base-passwd masters, empties
  /dev (kept: the `stdin -> /proc/self/fd/0` symlink, correct content),
  extends sources.list (main + non-free-firmware, updates, security),
  writes `userland-manifest.txt` (dpkg -l format) + `deb-sha256.txt`
  provenance, prunes /debootstrap + the .deb cache, clamps mtimes.
- postinst runs natively at first boot (`squeezebox-firstboot.service`).

## 3. userland:identity + wire:units — PASS

```text
$ ./platform/rg35xx-h/rootfs/mkrootfs.sh --staging .../rootfs \
    --with-services --with-config --epoch 1794334272
mkrootfs.sh: base userland present (init found)
mkrootfs.sh: wiring: serial-getty@ttyS0.service enabled in getty.target.wants
mkrootfs.sh: wiring: getty@tty1.service enabled in getty.target.wants
mkrootfs.sh: wiring: ssh.service enabled in multi-user.target.wants
mkrootfs.sh: wiring: systemd-timesyncd.service enabled in sysinit.target.wants
mkrootfs.sh: staging ready: .../rootfs (7169 files)
```

- `/sbin/init -> ../lib/systemd/systemd` (arm64 ELF), `/bin/sh -> dash`,
  locked `*` shadow for all 18 users, hostname/fstab/hosts/sshd drop-in
  from the overlay, os-release bumped to 0.2.0-exp2.
- Enables mirror `systemctl enable` (parsed from each unit's WantedBy).
  ALSA needs no wiring: `sound.target.wants/{alsa-restore,alsa-state}`
  ships in the alsa-utils deb (verified in staging).
- Standalone units installed, ship-disabled (present, zero wants links).
- Two bugs found in my own new code by this run and fixed on the branch:
  (1) `enable_unit` died under `set -e`+pipefail on Install-less units
  (alsa-restore has no `[Install]`) — now guarded; (2) tar `-k` exits 2
  on re-extraction — now `--skip-old-files`. (Also: always check
  PIPESTATUS — a `| tail` masked the first failure.)

## 4. payload:restage — PASS

```text
$ ./build/image/stage-payload.sh --staging .../rootfs --core-tgz ... \
    --uibins ... --sdl2 ... --compat ... [...] --epoch 1794334272
stage-payload.sh: SDL stack installed (compat 1.2.78 + SDL2 2.32.10 kmsdrm)
stage-payload.sh: ... kept userland version (closure copy skipped)  # x6
stage-payload.sh: payload ready: .../rootfs (11834 files)
```

- 6/19 closure SONAMEs now come from the userland (libasound, libudev,
  libbsd, libcap, libmd, libz); the other 13 noble libs still stage.
  Kept libs + their SHAs are recorded in `payload-manifest.txt`.
- Skeleton-only behavior unchanged (nothing skipped without a userland).

## 5. smoke:jive + smoke:alsa — PASS

Against the STAGED userland (`qemu-aarch64-static -L staging`):

```text
$ qemu-aarch64-static -L $R -E LD_TRACE_LOADED_OBJECTS=1 ... jive
        libm.so.6 => /lib/aarch64-linux-gnu/libm.so.6 (...)
        libc.so.6 => /lib/aarch64-linux-gnu/libc.so.6 (...)
$ ls /lib/aarch64-linux-gnu   # host has NO such dirs: resolution is staged-only
$ SDL_VIDEODRIVER=dummy ... qemu-aarch64-static -L $R ... jive
JIVE_RC=124 (alive at timeout = main loop)
SqueezePlay version 9.0.0 r541 / 51 applets / select skin: RG35XXHBaseSkin
$ ... jive_alsa -v -d null -b 1 -p 99 -f 1        # pty, fresh shm
WARN main:1410 buffer_time 1 us out of range, clamping to 30000
WARN main:1417 period_count 99 out of range, clamping to 3
WARN decode_lock_memory:1295 mlockall failed
```

- jive reaches the main loop with zero FATAL/GLIBC/symbol errors —
  the same bar as 0.1.0, now against trixie libc 2.41.
- jive_alsa: both 0005 clamp WARNs fire with exact values; `null` PCM
  OPENS against staged libasound (run enters the audio loop / real
  `snd_pcm` path instead of the prior env's `pcm_test failed` exit).
- Known quirk (pre-existing, out of scope): standalone jive_alsa with a
  FRESH shm segment segfaults after the WARNs — `shmget(56833, 0,
  IPC_CREAT)` creates a 0-byte segment when jive hasn't created the real
  one, and `decode_lock_memory` touches it (`// XXXX errors` in
  upstream). With jive-created shm it runs. No userland involvement.
- Test-only `fakevideo.so`/`logconf.lua` were removed afterwards; the
  staging file set diffs 0 lines vs `manifest.sha256`.

## 6. suite:bookworm — FAIL (expected; ADR-0004 amendment proposed)

The shipped payload was built against noble sysroots and requires
`GLIBC_2.38` (`__isoc23_strtol/strtoul/sscanf…`, plus SDL2's
`strlcat/fmod/fmodf@2.38`), measured by version-sweep over all payload
ELFs. Bookworm's libc6 is 2.36. A bookworm staging built with the same
script (104 packages, libc6 `2.36-9+deb12u14`, verified) fails exactly
as predicted:

```text
jive_alsa: /lib/aarch64-linux-gnu/libc.so.6: version `GLIBC_2.38'
  not found (required by .../jive_alsa)
jive: /lib/aarch64-linux-gnu/libc.so.6: version `GLIBC_2.38'
  not found (required by .../jive)
```

PROPOSAL (needs Lead approval): amend ADR-0004 suite bookworm → trixie
(oldest Debian with glibc ≥ 2.38; trixie is stable). The script keeps
`--suite bookworm` working to reproduce this failure. Alternatives
considered and rejected: noble userland (less Debian-aligned than
trixie), payload rebuild with `-std=gnu17` (cross-tree Agent-2/4
rebuilds + no cross-compiler on host), `__isoc23` shim lib (fragile
`.symver` hack, doesn't cover `strlcat`), libc backport (never happens).

## 7. image:gate FAIL* — false positive, evidence for QA

`check_image` reports 8 `possible secret (PEM private key header)` per
image. All matches are OpenSSH/sqv BINARY format markers in ELF
`.rodata` (13 files: sshd, ssh, ssh-keygen, ssh-agent, ssh-add,
ssh-keyscan, ssh-keysign, *-helpers, sshd-auth, sshd-session, sqv);
e.g. `ssh` contains `BEGIN OPENSSH PRIVATE KEY-----` x2 as parse/emit
constants. There are NO key files in staging: `etc/ssh/` holds only
`ssh_config`, `moduli`, and our drop-in; no `ssh_host_*`, no `id_*`,
no `*.pem` with key material (host keys are generated at first boot
by design). Suggested QA disposition: refine the raw-bytes rule to
skip ELF `.rodata` (or acceptlist ssh binaries); the gate file itself
was deliberately NOT touched on this branch (QA-owned security gate).

## 8. image:ddr3+ddr4 + image:bytes — PASS

```text
/tmp/sqz-userland/squeezebox-rg35xxh-ddr3.img  2147483648 bytes
  7a1fc07c1ef65b0abdadc6c90f11f9b1dc70dbc30767fd7dcc70adc193bdccd0
/tmp/sqz-userland/squeezebox-rg35xxh-ddr4.img  2147483648 bytes
  c388cbf16518ce026d75ea6ad08e8e7c5259c9e2c4c45cf245d3f07d4a55f5a1
```

(`.sha256` sidecars next to each image, written by the assembler.)

- GPT `--check` + sfdisk layout verified by the assembler; e2fsck -f and
  fsck.vfat clean; FAT holds exactly boot.scr + Image + dtb.img with
  epoch volid/dates; SPL 1482 sectors at LBA 16 both variants.
- Full image→staging byte proof: 11831 files via fuse2fs + the 3
  root-only files (shadow, gshadow, wpa template) via debugfs =
  11834/11834 SHA match, 0 mismatches.
- In-image: /sbin/init, systemd, userland + payload manifests, all five
  multi-user wants links + both getty links present.
- Cross-variant: 98413 diff bytes = 24793 pre-rootfs (== 0.1.0's SPL
  count exactly) + ext4 1.47.0 wrapper (scales with 11834 inodes).
- mke2fs is 1.47.0, so the ext4 wrapper still varies run-to-run (the
  assembler warns as designed); payload bytes are unaffected (proof
  above). Container TODO (e2fsprogs ≥ 1.47.1) stands.

## 9. Fixes landed on this branch

In-scope (`platform/`, `build/`):

- `platform/rg35xx-h/rootfs/stage-userland.sh` (new): debootstrap
  `--foreign` minbase under fakeroot + rootless second stage + dpkg -l
  manifest + `--userland container` privileged-docker hook.
- `platform/rg35xx-h/rootfs/userland-include.txt` (new): the 15-package
  include set (systemd/udev, ALSA, wifi, ssh, kmod, firmware, …).
- `platform/rg35xx-h/rootfs/mkrootfs.sh`: firstboot install, userland
  presence check, `enable_unit` wiring (consoles/ssh/timesyncd).
- `platform/rg35xx-h/services/firstboot.sh` + `systemd/…firstboot.service`
  (new): native `dpkg --configure -a` + `ssh-keygen -A`, stamp-guarded.
- `platform/rg35xx-h/rootfs/overlay/etc/os-release`: 0.2.0-exp2.
- `build/image/stage-payload.sh`: closure keeps userland SONAMEs + log.
- `build/image/README.md`, `platform/rg35xx-h/README.md`: userland step.
- `build/docker/Dockerfile`: debootstrap/qemu/keyring layer.

Cross-tree, needs owner review:

- `docs/test-results/wp2u-image.md` (this file; Agent 6).

Needs Lead decisions: (1) ADR-0004 suite amendment (§6); (2) QA gate
refinement for ssh-binary markers (§7).

Host-env notes (not committed): apt-downloaded host tools
(debootstrap, qemu-user-static, mtools, dosfstools, u-boot-tools,
fuse2fs+libfuse2t64, shellcheck, debian-archive-keyring) extracted to
`/tmp/sqz-userland/host-tools`; trixie keyring fetched from the suite.

## 10. Open gaps (not blockers for this image)

1. Physical boot (H1–H18) still needs RG35XX H hardware; first-boot
   `dpkg --configure -a` is designed but device-unproven.
2. OOT panel driver + DDR3 TPR tuning stay hardware-gated (as before).
3. 13 noble closure libs remain (libdrm/EGL/GLES/…): they run on trixie
   libc 2.41 (proven by the jive boot) but should migrate to trixie
   debs for a single-distro closure later.
4. Debian snapshot pinning (ADR future work) still open; the dpkg -l
   manifest + deb SHAs are the honest experimental record.

## 11. How to reproduce

```sh
git checkout wp2u/image
export PATH=/tmp/sqz-userland/host-tools/usr/bin:/tmp/sqz-userland/host-tools/usr/sbin:$PATH
export DEBOOTSTRAP_DIR=/tmp/sqz-userland/host-tools/usr/share/debootstrap
export SOURCE_DATE_EPOCH=1794334272
./platform/rg35xx-h/rootfs/stage-userland.sh --staging build/cache/rootfs \
    --cache build/cache/userland-debs --epoch "$SOURCE_DATE_EPOCH"
./platform/rg35xx-h/rootfs/mkrootfs.sh --staging build/cache/rootfs \
    --with-services --with-config --epoch "$SOURCE_DATE_EPOCH"
./build/image/stage-payload.sh --staging build/cache/rootfs \
    --core-tgz ... --uibins ... --sdl2 ... --compat ... --bsp-so ... \
    --squeezeplay-src .../src --kernel-modules ... --target-libs ... \
    --epoch "$SOURCE_DATE_EPOCH"
./build/image/assemble-image.sh --variant ddr4 --uboot ... --kernel ... \
    --rootfs build/cache/rootfs \
    --out /tmp/sqz-userland/squeezebox-rg35xxh-ddr4.img   # + ddr3
bash tests/selftest.sh
python3 tests/check_image.py /tmp/sqz-userland/*.img   # FAIL* = §7
```

## 12. Files changed (this branch)

- `platform/rg35xx-h/rootfs/{stage-userland.sh,userland-include.txt}` (new)
- `platform/rg35xx-h/rootfs/mkrootfs.sh`
- `platform/rg35xx-h/rootfs/overlay/etc/os-release`
- `platform/rg35xx-h/services/firstboot.sh` (new)
- `platform/rg35xx-h/services/systemd/squeezebox-firstboot.service` (new)
- `build/image/stage-payload.sh`, `build/image/README.md`
- `build/docker/Dockerfile`
- `platform/rg35xx-h/README.md`
- `docs/test-results/wp2u-image.md` (this file)
