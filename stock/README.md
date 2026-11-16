# Track B3 — reversible stock deployment

Run Jive on the **stock OS** (Ubuntu 22.04 Jammy ARM64 + vendor
4.9.170, verified in `docs/hardware.md`) without modifying the stock
system. This track exists to de-risk display, audio, and input on a
known-good kernel while the mainline image matures: if Jive drives
`/dev/fb0` + `audiocodec` + evdev here, the app side is proven and any
remaining mainline gap is purely kernel/DT.

## Strategy

1. **Probe first, decide from evidence.** `stock-probe.sh` collects
   framebuffer/SDL/ALSA/input/service facts into one tarball. Every
   later choice (SDL driver, ALSA device, frontend unit) names the
   probe file it came from.
2. **Bundle, don't install.** The deployment is one self-contained
   directory (`/opt/squeezebox-stock` or `$HOME/squeezebox-stock`).
   No packages, no `/etc` files, no systemd units, no enables.
3. **Stop, never disable.** The gaming frontend is paused with
   `systemctl stop` and resumed with `systemctl start`. A plain
   reboot restores stock behavior even if you walk away mid-run.
4. **User-executed, device-side.** The agents have no device access:
   every command in this tree is run by the human on the device.
   Scripts print their plan and refuse anything destructive.

## Safety rules (normative for this track)

- **Read-only probing.** The probe writes exactly one tarball in the
  current directory. It never writes to `/etc`, `/usr`, `/boot`,
  sysfs, ALSA state, or any device node.
- **Reversible changes only.** The ONLY persistent change this track
  ever makes is creating the bundle directory (deleted by
  `restore.sh --remove`), plus, optionally, a Wi-Fi connection so SSH
  works (see `SSH.md`, with exact undo). Everything else is runtime
  state (`systemctl stop/start`) that a reboot clears.
- **Second-card rule.** The working stock SD is never reimaged or
  repartioned for this track. Mainline images go on a SECOND card
  (per `docs/hardware.md`). This track needs no card at all.
- **No bootloader / kernel / frontend-startup changes.** No boot
  image, boot script, module, unit file, enable, mask, or autostart
  edits — not now, not "temporarily". If a step needs one, stop and
  file it as a track-exit decision instead.
- **No guessing the frontend unit.** It is identified from the probe
  tarball per `bundle/README.md`, and the scripts refuse to stop
  anything critical (ssh, console, networking, login, systemd itself).

## Layout

```text
stock/
├── README.md            # this file (strategy + safety)
├── SSH.md               # Wi-Fi + SSH setup from the UART shell
├── probe/
│   ├── stock-probe.sh   # device-side read-only collector -> one tarball
│   └── README.md        # exact run + tarball contents
├── bundle/
│   ├── install.sh       # copy bundle to /opt or $HOME (no system writes)
│   ├── run-jive.sh      # stop frontend (stop only) + launch jive
│   ├── restore.sh       # restart frontend and/or remove bundle
│   ├── lib-safety.sh    # plan/confirm/refusal helpers
│   ├── jive-env.sh      # SDL/ALSA/Jive environment knobs
│   ├── frontend-unit.txt.example
│   └── README.md        # deployment layout + reversibility proof
└── tests/
    └── test-stock-bundle.sh  # host-side logic tests (fixtures, no device)
```

## End-to-end (human checklist)

```sh
# 1. UART shell as root (115200 8N1, ttyS0). Optional: bring up
#    Wi-Fi/SSH first so you can scp instead of pasting — see SSH.md.
# 2. Run the probe, bring the tarball home:
sh stock-probe.sh
#    scp 'root@<device-ip>:~/stock-probe-*.tar.gz*' .
# 3. Read the tarball: 10-framebuffer, 20-sdl, 30-alsa, 40-input,
#    90-frontend-hunt (+ 50-processes-services). Fill in
#    bundle/frontend-unit.txt and confirm bundle/jive-env.sh.
# 4. Install + dry-run + run (see bundle/README.md for exact commands).
# 5. Restore the gaming UI:  bash restore.sh --restart-frontend
# 6. Record results: copy docs/test-results/diag-stock-bundle.md's
#    device section into a dated file with your observations.
```

Status: host logic tested (`bash stock/tests/test-stock-bundle.sh`);
device run pending (no agent device access). Evidence:
`docs/test-results/diag-stock-bundle.md`.
