# Known issues — Squeezebox RG35XX H (0.2.0-exp2)

Experimental release. Nothing below is a surprise: each item links the
evidence or the tracking doc. File new hardware findings per
[docs/test-results/HW_TEST_PLAN.md](test-results/HW_TEST_PLAN.md#5-failure-triage).

## Blocking real use

1. **No panel driver — display dark on hardware.** Mainline DTS has no
   panel nodes, and the OOT panel DTS+driver is not built yet (template:
   [platform/rg35xx-h/device-tree/rg35xx-h-display-oot.dtsi.template](../platform/rg35xx-h/device-tree/rg35xx-h-display-oot.dtsi.template)).
   Expect backlight/console/UI to be absent on device; UART + SSH are
   the working consoles. Rows H3/H4 cannot pass until this lands.
2. **H1–H18 all NOT RUN — no hardware access.** The full matrix in
   [docs/test-results/HW_TEST_PLAN.md](test-results/HW_TEST_PLAN.md)
   awaits a physical RG35XX H (sole external blocker, see
   [docs/project-status.md](project-status.md)). DDR-ID method, TPR
   tuning, ALSA live validation, and panel light are all HW-gated.
3. **First-boot `dpkg --configure -a` device-unproven.** The image
   ships 141 packages `unpacked` by design (rootless second stage,
   [platform/rg35xx-h/rootfs/stage-userland.sh](../platform/rg35xx-h/rootfs/stage-userland.sh))
   and configures them natively via
   [platform/rg35xx-h/services/firstboot.sh](../platform/rg35xx-h/services/firstboot.sh).
   It is reasoned-correct and `systemd-analyze verify` is clean, but it
   has never run on the board. Watch UART on first boot; if it fails,
   recovery is re-flash ([RECOVERY.md](RECOVERY.md)).

## Provisioning gaps

4. **SSH needs a serial console first.** Root is key-only with no
   default passwords, host keys generate at first boot, and no USB or
   web key provisioning exists yet (planned with Agent 5). Without UART
   hardware you cannot get into a fresh unit — see
   [INSTALL.md](INSTALL.md#6-ssh-access).
5. **DRAM variant is trial-and-error.** No unit ID method: flash DDR4,
   and if there is no SPL output, re-flash DDR3
   ([INSTALL.md](INSTALL.md#2-pick-ddr3-vs-ddr4)).
6. **No OTA, no failsafe partition.** Upgrade and recovery both mean
   re-flashing the whole 2 GiB card ([UPGRADE.md](UPGRADE.md),
   [RECOVERY.md](RECOVERY.md)). Back up first; there is no undo.

## Build / supply-chain honesty

7. **Images are host-built, not container-built.** 0.2.0-exp2 was
   produced on Ubuntu 24.04 (gcc-aarch64 13.3.0, mke2fs 1.47.0) with no
   docker daemon; the pinned containers in `build/toolchain/Dockerfile`
   and `build/docker/Dockerfile` are the specified contract, not what
   ran. Full provenance: [releases/SBOM.json](../releases/SBOM.json).
8. **ext4 wrapper varies run-to-run.** Host mke2fs 1.47.0 < 1.47.1, so
   image bytes differ between builds; staged payload bytes are proven
   identical (11834/11834 SHA match, `docs/test-results/wp2u-image.md`).
   Container e2fsprogs ≥ 1.47.1 is still TODO.
9. **No Debian snapshot pin.** The trixie userland is recorded (141
   package versions in the SBOM), not rebuild-locked; snapshot.debian.org
   pinning is future work (ADR-0004).
10. **SBOM is a draft format** (`squeezebox-sbom-draft/1`), not
    SPDX/CycloneDX. Machine-readable conversion is future work.
11. **13 noble closure libs remain** in the payload (libdrm/EGL/GLES…);
    they run on trixie libc 2.41 (qemu-user jive boot proven) but should
    migrate to trixie debs for a single-distro closure.

## Upstream quirks (pre-existing, out of scope)

12. Standalone `jive_alsa` with a fresh shm segment segfaults after the
    clamp WARNs (`shmget` 0-byte segment when jive has not created the
    real one; `// XXXX errors` upstream). With jive-created shm it runs.
    No userland involvement (`docs/test-results/wp2u-image.md` §5).
