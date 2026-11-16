# GO-HW report: device recon + install + lifecycle — 2026-11-16

Agent: GO-HW (exclusive device owner). Branch: `go/hw-install`.
Device: ANBERNIC RG35XX H over `ssh rg35xxh` (sudo working, no sleep hit).
End state: **SqueezeboxGo cleanly installed, device stock-healthy**
(frontend active, dmenu holding PCM, vinfo stock, zero stock files modified).

## Task results

### (1) APPS discovery recon — DONE
Evidence: [go-apps-recon.txt](../hw-evidence/go-apps-recon.txt).
- Live dir is TF1 `/mnt/mmc/Roms/APPS` (6 stock apps + `Imgs/` + payload dirs);
  TF2 `/mnt/sdcard/ROMS/APPS` exists but is empty (and TF2 is currently ro —
  kernel remounted after an error; left untouched, owner to fsck).
- Mechanism: dmenu writes `/tmp/.next` then **exits**; `dmenu_ln` runs
  `sh /tmp/.next`; `loadapp.sh` restarts dmenu when the app ends. Scripts run
  as **root**, stdout goes to **/dev/null** (log to files), env provides
  `LD_LIBRARY_PATH=/usr/lib32:/usr/lib:/mnt/vendor/lib`.
- No icon refresh step exists or is needed (rescan at each dmenu start).
- **Spec correction: stock icons are 240x180 RGBA, NOT 160x120.**
  GO-APP must target 240x180 (device is truth; all 6 icons verified by
  `file` + IHDR decode).

### (2) Display/audio/input ownership — DONE
Evidence: [go-ownership-probe.txt](../hw-evidence/go-ownership-probe.txt).
- dmenu alive: holds `/dev/fb0` (mmap), `pcmC0D0p` (aplay: busy, proven),
  event1 + event0.
- dmenu exited (= app-run state): fb write/readback/restore IDENTICAL, PCM
  opens, event1/2 free; only `systemd-logind` keeps event0 (power, hands-off).
- Rule: SSH-direct runs must `systemctl stop launcher.service` first (poll
  `pidof dmenu.bin` ≤60 s); menu runs get the free state automatically.

### (3) Install — DONE (provisional icon, pending GO-APP art)
Evidence: [go-install.txt](../hw-evidence/go-install.txt).
- SHAs verified on host AND device: tarball `673ec5ee…` ✓, fbcon lib
  `3924a625…` ✓ — no rebuild needed.
- `/opt/squeezebox-go` (46 MB, root): `app/` (jive 9.0.0 r541),
  `libexec/` (fbcon SDL shadow, ldd-clean), `logs/`, `home/`, `VERSION`.
- `/mnt/mmc/Roms/APPS/SqueezeboxGo.sh` (stock-pattern launcher, `bash -n` OK,
  exports `SQUEEZEBOX_GO=1`) + `Imgs/SqueezeboxGo.png` (**240x180 RGBA,
  provisional** blue-field art for GO-APP to overwrite).
- Additive-only: zero stock files modified; TF2 untouched.

### (4) Lifecycle test — DONE (SSH path; menu path needs human + GO-APP exit)
Evidence: [go-lifecycle-jive.txt](../hw-evidence/go-lifecycle-jive.txt) (3708 lines).
- Launch (dmenu stopped): jive 9.0.0 r541 booted, SDL 640x480, 65+ actions,
  ran 71 s stable at 2–4% CPU.
- Log errors: 4 real (9 more grep hits are locale tokens containing "ERROR"):
  missing `splash640x480.png` (fallback OK, benign), `decode_alsa_init
  shmget` (known SYSVIPC=n; audio-agent follow-up, human ears to confirm),
  `start_demo` unregistered (benign), SIGTERM (our exit signal, expected).
- Exit: SIGTERM → `term_handler` → `JIVE_EVENT_QUIT`, process gone, script done.
- Frontend return WITHOUT reboot: dmenu restarted, `launcher.service` active,
  PCM re-held. **dmenu self-heals vinfo to 1280x1024x16 on start** — no
  restore step needed in packaging (verified: stuck 640x480x32 → stock).
- Game-after-exit + saves: queued for human (item 5 below); install touched
  nothing on those paths.

### (5) evtest — READY, not run (no fingers)
Evidence: [go-evtest-ready.md](../hw-evidence/go-evtest-ready.md) + existing
[evtest-handoff.md](../hw-evidence/evtest-handoff.md). Exact command lists prepared.

## Queued for lead/human
1. APPS icon/menu visibility (runnable now — provisional art).
2. Menu launch + LCD picture (needs GO-APP Return action for safe exit; else SSH fallback).
3. Button nav + audio ears (`shmget` suspect if silent).
4. Menu exit path → frontend return without reboot.
5. Game launchable after exit, saves intact.

## Pending on GO-APP (refs, not edits)
- Final `SqueezeboxGo.png` 240x180 RGBA art → overwrite device
  `/mnt/mmc/Roms/APPS/Imgs/SqueezeboxGo.png`.
- Return-to-Anbernic Jive action gated by `SQUEEZEBOX_GO=1` (already exported
  by the installed launcher) — unblocks human menu testing.
- Optional: `jive/splash640x480.png` skin asset (kills 1 benign boot error).

## Reproduce / uninstall
- Install: `stock/go/install-squeezebox-go.sh` (on device, as root; needs the
  Jammy tarball + fbcon lib either pre-staged or passed in).
- Uninstall: `stock/go/uninstall-squeezebox-go.sh` (removes the 3 added paths only).
