# Services (RG35XX H)

Init system decision (WP1, Agent 1): **systemd is primary** (standard,
matches the ROCKNIX pattern, gives restart/ordering semantics the audio
arbiter and standalone adapters need). All service LOGIC lives in POSIX
`sh` scripts so a busybox-init fallback stays cheap; units are thin wrappers.

Boot order: `splash.service` -> `wifi.service` -> `squeezeplay.service`.
`splash.sh` always exits 0 (never blocks boot); `squeezeplay.sh` starts Jive
even when `audio-owner` is not installed yet (warns, WP1 behavior).

## Files

- `squeezeplay.sh` — Jive launcher; exports the interface-contracts env knobs
  (`USEALSA_*`, `SQUEEZEPLAY_NOPLAYBACK`, `UTMAC`), best-effort
  `audio-owner acquire jive`, execs `/opt/squeezeplay/bin/jive` (the real
  Agent-2 binary; the desktop `bin/squeezeplay.sh` is not used on target).
- `splash.sh` — splash hook; tries Agent-4
  `/opt/squeezeplay/bin/init-splash.sh show` (drm_splash + pidfile), then
  `fbi` + static image, then console banner. Always exits 0.
- `wifi.sh start|stop|status` — wpa_supplicant + udhcpc/dhcpcd for `wlan0`.
- `systemd/*.service` — units, enabled by `mkrootfs.sh --with-services`.

## SSH

No custom unit: enable the base image's `sshd` (`systemctl enable sshd`) with
our drop-in `../configuration/sshd-10-squeezebox.conf` (root key-only, no
default passwords anywhere). Key provisioning is a WP2 first-boot story
(web mgmt / USB stick), owned with Agent 5.

## busybox-init fallback (if WP2 picks a non-systemd base)

Call the same scripts from `/etc/init.d/rcS` in splash/wifi/squeezeplay
order with `setsid ... &` + a respawn loop for squeezeplay.sh. No script
changes needed (they are init-agnostic).
